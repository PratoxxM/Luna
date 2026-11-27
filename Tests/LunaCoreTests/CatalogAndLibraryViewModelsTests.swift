import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class WireTabSession: TabSessionContext {
    var serverBaseURL: URL?
    var roomName: String = "Kjellerstua"
    var hardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    let client: LunaCoreClient

    init(host: String) {
        self.serverBaseURL = URL(string: "https://\(host):8920")
        self.client = LunaCoreMockURLProtocol.makeClient(host: host)
    }

    func makeHomeClient() -> (any HomeClientProviding)? { client }
    func makeCatalogClient() -> (any CatalogClientProviding)? { client }
    func makeLibraryClient() -> (any LibraryClientProviding)? { client }
    func makeSearchClient() -> (any SearchClientProviding)? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
}

final class CatalogAndLibraryViewModelsTests: XCTestCase {
    // MARK: - Policies: CustomRowContextPolicy, LibraryFilterSection & TabMemoryEvictionPolicy

    func testCustomRowContextLibrarySectionsAndTabEvictionPolicies() {
        XCTAssertEqual(CustomRowContextPolicy.extractRowId(from: "/api/tv/v2/rows/custom%3Anordic-noir?limit=24"), "custom:nordic-noir")
        XCTAssertEqual(CustomRowContextPolicy.extractRowId(from: "/api/tv/v1/rows/custom%3Ajulefilmer"), "custom:julefilmer")
        XCTAssertTrue(CustomRowContextPolicy.isOngoingList(explicitFlag: false, rowId: "custom:pagaende", sourceKind: "active_series"))
        XCTAssertEqual(CustomRowContextPolicy.removeActionTitle(explicitFlag: false, rowId: "custom:mine-pagaende-serier", sourceKind: "active_series"), "Fjern fra pågående")
        XCTAssertEqual(CustomRowContextPolicy.removeActionTitle(explicitFlag: false, rowId: "custom:nordic", sourceKind: "custom"), "Fjern fra listen")
        XCTAssertNil(CustomRowContextPolicy.removeActionTitle(explicitFlag: false, rowId: "genre:movie:action", sourceKind: "genre"))
        XCTAssertNil(CustomRowContextPolicy.removeActionTitle(explicitFlag: false, rowId: "local-movies", sourceKind: "local_library"))

        XCTAssertEqual(LibraryFilterSection.allCases.map(\.label), ["Filmer", "Serier", "Huskeliste", "Lister"])
        let counts = TvLibraryCounts(watchlist: 3, localTotal: 5, localMovies: 2, localSeries: 3, nvme: 5, archive: 0, vfs: 0, customLists: 1, customListsCount: 4)
        XCTAssertEqual(LibraryFilterSection.lists.pillTitle(counts: counts), "Lister")
        XCTAssertEqual(LibraryFilterSection.lists.pillBadgeText(counts: counts), "4")
        XCTAssertNil(LibraryFilterSection.lists.pillBadgeText(counts: nil))
        XCTAssertNil(LibraryFilterSection.lists.emptyActionTitle)
        XCTAssertEqual(LibraryFilterSection.lists.emptyHeadline, LunaCopy.emptyCustomListsHeadline)

        XCTAssertEqual(TabMemoryEvictionPolicy.inactiveTabsToUnload(activeTab: .home), [.movies, .series, .library, .search])
    }

    // MARK: - CatalogBrowseViewModel SWR, Pagination, Rollback, Filter Switch & LoadMore Race

    @MainActor
    func testCatalogBrowseViewModelSWRPaginationFilterSwitchesAndLoadMoreRace() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            CatalogBrowseMemoryCache.shared.clear()
            defer { CatalogBrowseMemoryCache.shared.clear() }

            let client = HomeEdgeMockClient()
            let session = HomeEdgeTabSession(client: client)
            let card1 = TvMediaCard(itemId: "movie:tmdb:1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "Film 1", inWatchlist: false)
            let card2 = TvMediaCard(itemId: "movie:tmdb:2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "Film 2", inWatchlist: false)
            let page1 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: true, items: [card1])
            let page2 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 2, limit: 24, hasMore: false, items: [card1, card2])
            let page1Data = try JSONEncoder().encode(page1)

            client.lock.withLock { s in
                s.shouldFailWatchlist = true
                s.catalogHandlers = [
                    { _, _, _, _ in .updated(payload: page1, etag: "\"cat-1\"", rawPayloadData: page1Data) },
                    { _, _, _, _ in .updated(payload: page2, etag: nil, rawPayloadData: Data()) },
                    { _, _, _, etag in
                        XCTAssertEqual(etag, "\"cat-1\"")
                        return .notModified
                    },
                    { _, genre, _, etag in
                        XCTAssertEqual(genre, "drama")
                        XCTAssertNil(etag)
                        return .updated(payload: page2, etag: "\"etag-drama\"", rawPayloadData: Data())
                    },
                    { _, genre, _, etag in
                        XCTAssertEqual(genre, "sci-fi")
                        XCTAssertNil(etag)
                        throw LunaCoreError.serverMessage(500, "Nettverksfeil")
                    },
                ]
            }

            let vm = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
            await vm.handleActivation(session: session, isActive: true)
            XCTAssertEqual(vm.items.map(\.title), ["Film 1"])
            XCTAssertTrue(vm.hasMore)

            await vm.loadNextPage(session: session)
            XCTAssertEqual(vm.items.map(\.title), ["Film 1", "Film 2"])
            XCTAssertFalse(vm.hasMore)

            // Failed watchlist mutation rolls back optimistic toggle
            await vm.toggleWatchlist(card1, session: session)
            XCTAssertEqual(vm.items.first?.inWatchlist, false)
            XCTAssertNotNil(vm.mutationErrorBanner)

            // Memory warning unload recovers via DiskSWR + 304
            await DiskSWRStore.drainPendingWrites()
            CatalogBrowseMemoryCache.shared.clear()
            vm.unloadForMemoryWarning()
            XCTAssertTrue(vm.items.isEmpty)
            await vm.handleActivation(session: session, isActive: true)
            XCTAssertEqual(vm.items.map(\.title), ["Film 1"])

            // Filter switch resets ETag; error on fresh filter clears previous items
            vm.selectedGenreSlug = "drama"
            await vm.handleActivation(session: session, isActive: true)
            XCTAssertEqual(vm.items.map(\.title), ["Film 1", "Film 2"])
            vm.selectedGenreSlug = "sci-fi"
            await vm.handleActivation(session: session, isActive: true)
            XCTAssertTrue(vm.items.isEmpty)
            XCTAssertNotNil(vm.errorMessage)
            XCTAssertNil(vm.cachedEtag)

            // Filtered unload with evicted cache never sends stale ETag
            let dramaClient = HomeEdgeMockClient()
            let dramaSession = HomeEdgeTabSession(client: dramaClient)
            dramaClient.lock.withLock { s in
                s.catalogHandlers = [
                    { _, _, _, _ in .updated(payload: page1, etag: "\"etag-d1\"", rawPayloadData: Data()) },
                    { _, _, _, etag in
                        XCTAssertNil(etag)
                        return .updated(payload: page1, etag: "\"etag-d2\"", rawPayloadData: Data())
                    },
                ]
            }
            let filteredVM = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
            filteredVM.selectedGenreSlug = "drama"
            await filteredVM.handleActivation(session: dramaSession, isActive: true)
            filteredVM.unloadForMemoryWarning()
            CatalogBrowseMemoryCache.shared.clear()
            await filteredVM.handleActivation(session: dramaSession, isActive: true)
            XCTAssertEqual(filteredVM.items.map(\.title), ["Film 1"])

            // scheduleLoadNextPage + scheduleReloadFirstPage race guard prevents stuck isLoadingMore
            let raceClient = HomeEdgeMockClient()
            let raceSession = HomeEdgeTabSession(client: raceClient)
            let p1New = TvMediaCard(itemId: "movie:tmdb:20", mediaType: "movie", ids: TvMediaIds(tmdb: 20), title: "NewFilterP1")
            let p2New = TvMediaCard(itemId: "movie:tmdb:21", mediaType: "movie", ids: TvMediaIds(tmdb: 21), title: "NewFilterP2")
            let resNew1 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: true, items: [p1New])
            let resNew2 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 2, limit: 24, hasMore: false, items: [p2New])
            let oldPage2Started = Mutex(false)

            raceClient.lock.withLock { s in
                s.catalogHandlers = [
                    { _, _, _, _ in .updated(payload: page1, etag: "\"e1\"", rawPayloadData: Data()) },
                    { _, _, _, _ in
                        oldPage2Started.withLock { $0 = true }
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        return .notModified
                    },
                    { _, _, _, _ in .updated(payload: resNew1, etag: "\"e2\"", rawPayloadData: Data()) },
                    { _, _, _, _ in
                        try await Task.sleep(nanoseconds: 25_000_000)
                        return .updated(payload: resNew2, etag: nil, rawPayloadData: Data())
                    },
                ]
            }
            let raceVM = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
            await raceVM.handleActivation(session: raceSession, isActive: true)
            raceVM.scheduleLoadNextPage(session: raceSession)
            for _ in 0..<250 where !oldPage2Started.withLock({ $0 }) {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(raceVM.isLoadingMore)

            raceVM.selectedGenreSlug = "action"
            raceVM.scheduleReloadFirstPage(forceNetwork: false, session: raceSession)
            XCTAssertFalse(raceVM.isLoadingMore)
            for _ in 0..<250 where raceVM.items.map(\.title) != ["NewFilterP1"] {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            raceVM.scheduleLoadNextPage(session: raceSession)
            for _ in 0..<250 where raceVM.items.count != 2 || raceVM.isLoadingMore {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertEqual(raceVM.items.map(\.title), ["NewFilterP1", "NewFilterP2"])
            raceVM.cancelAllTasks()
            XCTAssertFalse(raceVM.isLoading || raceVM.isLoadingMore)
        }
    }

    // MARK: - LibraryViewModel Lists, Tier/Sort Filters & Section Fallbacks

    @MainActor
    func testLibraryViewModelListsSWRTierSortFiltersAndSectionFallbacks() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            LibraryBrowseMemoryCache.shared.clear()
            defer { LibraryBrowseMemoryCache.shared.clear() }

            // 1. Lists section DiskSWR & memory unload recovery
            let client = HomeEdgeMockClient()
            let session = HomeEdgeTabSession(client: client)
            let listItem = TvLibraryCustomList(id: "custom:nordic", name: "Nordisk spenning", mediaType: "series", itemCount: 5, browsePath: "/api/tv/v2/rows/custom%3Anordic")
            let libLists = TvLibraryResponse(
                ok: true, section: "lists",
                counts: TvLibraryCounts(watchlist: 1, localTotal: 1, localMovies: 1, localSeries: 0, nvme: 1, archive: 0, vfs: 0, customLists: 1, customListsCount: 1),
                watchlist: [], localItems: [], customLists: [listItem]
            )
            let libListsData = try JSONEncoder().encode(libLists)
            client.lock.withLock { s in
                s.libraryHandlers = [
                    { _, _, _, _ in .updated(payload: libLists, etag: "\"lib-l1\"", rawPayloadData: libListsData) },
                    { _, _, _, etag in
                        XCTAssertEqual(etag, "\"lib-l1\"")
                        return .notModified
                    },
                ]
            }

            let vm = LibraryViewModel()
            vm.activeSection = .lists
            await vm.handleActivation(session: session, isActiveTab: true)
            XCTAssertEqual(vm.customLists.map(\.name), ["Nordisk spenning"])
            await DiskSWRStore.drainPendingWrites()
            LibraryBrowseMemoryCache.shared.clear()
            vm.unloadForMemoryWarning()
            XCTAssertTrue(vm.customLists.isEmpty)
            await vm.handleActivation(session: session, isActiveTab: true)
            XCTAssertEqual(vm.customLists.map(\.name), ["Nordisk spenning"])

            // 2. Nil-ETag overwrite, section error isolation & cold .movies -> .series fallback
            LibraryBrowseMemoryCache.shared.clear()
            let edgeClient = HomeEdgeMockClient()
            let edgeSession = HomeEdgeTabSession(client: edgeClient)
            let zeroMovieCounts = TvLibraryCounts(watchlist: 0, localTotal: 1, localMovies: 0, localSeries: 1, nvme: 1, archive: 0, vfs: 0, customLists: 0, customListsCount: 0)
            let emptyMovies = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [], customLists: [])
            let seriesCard = TvMediaCard(itemId: "series:tmdb:990", mediaType: "series", ids: TvMediaIds(tmdb: 990), title: "ColdFallbackSeries")
            let seriesResp = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [seriesCard], customLists: [])

            edgeClient.lock.withLock { s in
                s.libraryHandlers = [
                    { _, mediaType, _, etag in
                        XCTAssertEqual(mediaType, "movie")
                        XCTAssertNil(etag)
                        return .updated(payload: emptyMovies, etag: "\"m-empty\"", rawPayloadData: Data())
                    },
                    { _, mediaType, _, etag in
                        XCTAssertEqual(mediaType, "series")
                        XCTAssertNil(etag)
                        return .updated(payload: seriesResp, etag: "\"s-loaded\"", rawPayloadData: Data())
                    },
                    { _, _, _, _ in throw LunaCoreError.serverMessage(500, "Huskelistefeil") },
                ]
            }

            let coldVM = LibraryViewModel()
            await coldVM.handleActivation(session: edgeSession, isActiveTab: true)
            XCTAssertEqual(coldVM.activeSection, .series)
            await coldVM.handleActivation(session: edgeSession, isActiveTab: true)
            XCTAssertEqual(coldVM.activeMediaCards.map(\.title), ["ColdFallbackSeries"])

            coldVM.activeSection = .watchlist
            await coldVM.handleActivation(session: edgeSession, isActiveTab: true)
            XCTAssertTrue(coldVM.activeMediaCards.isEmpty)
            XCTAssertNotNil(coldVM.errorMessage)
            XCTAssertNil(coldVM.cachedEtag)

            // 3. Tier/sort filtering & DiskSWRStore bypass for non-default filters
            let wireHost = "lib-filter-\(UUID().uuidString.lowercased()).invalid"
            defer { LunaCoreMockURLProtocol.unregister(host: wireHost) }
            LunaCoreMockURLProtocol.register(host: wireHost) { req in
                let url = try XCTUnwrap(req.url)
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let tier = comps?.queryItems?.first(where: { $0.name == "tier" })?.value ?? "all"
                let sort = comps?.queryItems?.first(where: { $0.name == "sort" })?.value ?? "recent"
                let body = #"{"ok":true,"section":"local","activeFilters":{"tier":"\#(tier)","mediaType":"movie","sort":"\#(sort)"},"counts":{"watchlist":1,"localTotal":10,"localMovies":6,"localSeries":4,"nvme":3,"archive":5,"vfs":2,"customLists":0},"watchlist":[],"localItems":[{"itemId":"movie:tmdb:550","mediaType":"movie","ids":{"tmdb":550},"title":"Fight Club"}],"localHasMore":false}"#
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"lib-\(tier)-\(sort)\""]))
                return (resp, Data(body.utf8))
            }

            let filterSession = WireTabSession(host: wireHost)
            let filterVM = LibraryViewModel()
            filterVM.selectedTier = .nvme
            filterVM.selectedSort = .rating
            XCTAssertTrue(filterVM.queryKey(for: filterSession).contains("#nvme#rating#"))
            await filterVM.loadLibrary(session: filterSession)
            XCTAssertEqual(filterVM.libraryPayload?.activeFilters?.tier, "nvme")
            XCTAssertEqual(filterVM.libraryPayload?.activeFilters?.sort, "rating")
            XCTAssertEqual(filterVM.count(for: .nvme), 3)
            XCTAssertEqual(filterVM.count(for: .archive), 5)
            XCTAssertEqual(filterVM.count(for: .vfs), 2)
            XCTAssertNil(DiskSWRStore.libraryMemorySnapshot(section: "local", mediaType: "movie", serverHost: wireHost, roomName: filterSession.roomName, hardwareProfile: filterSession.hardwareProfile))
        }
    }
}
