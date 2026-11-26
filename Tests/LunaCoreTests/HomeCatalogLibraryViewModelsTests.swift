import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class MockHomeCatalogLibraryClient: HomeClientProviding, CatalogClientProviding, LibraryClientProviding, @unchecked Sendable {
    let lock = Mutex<MockState>(MockState())

    struct MockState: Sendable {
        var homeResponses: [HomeConditionalResult] = []
        var homeETagsRequested: [String?] = []
        var catalogResponses: [ConditionalHTTPResult<TvCatalogResponse>] = []
        var catalogRequests: [(kind: String, page: Int, etag: String?)] = []
        var libraryResponses: [ConditionalHTTPResult<TvLibraryResponse>] = []
        var libraryRequests: [(section: String, mediaType: String, offset: Int, etag: String?)] = []
        var shouldFailWatchlist = false
        var shouldFailWatched = false
        var watchlistCalls = 0
        var watchedCalls = 0
    }

    func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
        lock.withLock { s in
            s.homeETagsRequested.append(ifNoneMatch)
            if s.homeResponses.isEmpty {
                return .notModified
            }
            return s.homeResponses.removeFirst()
        }
    }

    func fetchCatalog(
        kind: String,
        genre: String?,
        sort: String,
        localOnly: Bool,
        unwatchedOnly: Bool,
        page: Int,
        limit: Int
    ) async throws -> TvCatalogResponse {
        TvCatalogResponse(
            ok: true,
            mediaType: kind,
            title: kind == "series" ? "Serier" : "Filmer",
            sort: sort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            page: page,
            limit: limit,
            hasMore: false,
            items: []
        )
    }

    func fetchCatalogConditional(
        kind: String,
        genre: String?,
        sort: String,
        localOnly: Bool,
        unwatchedOnly: Bool,
        page: Int,
        limit: Int,
        ifNoneMatch: String?
    ) async throws -> ConditionalHTTPResult<TvCatalogResponse> {
        lock.withLock { s in
            s.catalogRequests.append((kind, page, ifNoneMatch))
            if s.catalogResponses.isEmpty {
                return .notModified
            }
            return s.catalogResponses.removeFirst()
        }
    }

    func fetchLibrary(
        section: String,
        tier: String,
        mediaType: String,
        sort: String,
        offset: Int,
        limit: Int,
        ifNoneMatch: String?
    ) async throws -> ConditionalHTTPResult<TvLibraryResponse> {
        lock.withLock { s in
            s.libraryRequests.append((section, mediaType, offset, ifNoneMatch))
            if s.libraryResponses.isEmpty {
                return .notModified
            }
            return s.libraryResponses.removeFirst()
        }
    }

    func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {
        let fail = lock.withLock { s -> Bool in
            s.watchlistCalls += 1
            return s.shouldFailWatchlist
        }
        if fail { throw LunaCoreError.serverMessage(500, "Serverfeil") }
    }

    func setWatched(
        watched: Bool,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        year: Int?,
        season: Int?,
        episode: Int?
    ) async throws {
        let fail = lock.withLock { s -> Bool in
            s.watchedCalls += 1
            return s.shouldFailWatched
        }
        if fail { throw LunaCoreError.serverMessage(500, "Serverfeil") }
    }

    func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws {}
    func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool { true }
}

@MainActor
private final class MockTabSession: TabSessionContext {
    var serverBaseURL: URL? = URL(string: "http://mock-tabs.local:8090")
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    let client: MockHomeCatalogLibraryClient
    var mutateCount = 0
    var unpairCount = 0

    init(client: MockHomeCatalogLibraryClient, host: String = "mock-tabs-\(UUID().uuidString.lowercased()).local") {
        self.serverBaseURL = URL(string: "http://\(host):8090")
        self.client = client
    }

    func makeHomeClient() -> (any HomeClientProviding)? { client }
    func makeCatalogClient() -> (any CatalogClientProviding)? { client }
    func makeLibraryClient() -> (any LibraryClientProviding)? { client }
    func makeSearchClient() -> (any SearchClientProviding)? { nil }
    func notifyContentMutated() {
        homeRefreshNonce &+= 1
        mutateCount += 1
    }
    func unpairDevice() { unpairCount += 1 }
}

final class HomeCatalogLibraryViewModelsTests: XCTestCase {
    @MainActor
    func testPoliciesCustomRowExtractAndLibraryFourSections() {
        XCTAssertTrue(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: true, hasActivePlayback: false, secondsSinceLastValidation: 12))
        XCTAssertFalse(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: true, hasActivePlayback: true, secondsSinceLastValidation: 60))
        XCTAssertFalse(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: false, hasActivePlayback: false, secondsSinceLastValidation: 60))

        XCTAssertEqual(CustomRowContextPolicy.extractRowId(from: "/api/tv/v2/rows/custom%3Anordic-noir?limit=24"), "custom:nordic-noir")
        XCTAssertEqual(CustomRowContextPolicy.extractRowId(from: "/api/tv/v1/rows/custom%3Ajulefilmer"), "custom:julefilmer")
        XCTAssertTrue(CustomRowContextPolicy.isOngoingList(explicitFlag: false, rowId: "custom:pagaende", sourceKind: "active_series"))
        XCTAssertEqual(CustomRowContextPolicy.removeActionTitle(explicitFlag: false, rowId: "custom:nordic", sourceKind: "custom"), "Fjern fra listen")

        XCTAssertEqual(LibraryFilterSection.allCases.map(\.label), ["Filmer", "Serier", "Huskeliste", "Lister"])
        let counts = TvLibraryCounts(watchlist: 3, localTotal: 5, localMovies: 2, localSeries: 3, nvme: 5, archive: 0, vfs: 0, customLists: 1, customListsCount: 4)
        XCTAssertEqual(LibraryFilterSection.lists.pillTitle(counts: counts), "Lister · 4")
        XCTAssertNil(LibraryFilterSection.lists.pillBadgeText(counts: counts))
        XCTAssertNil(LibraryFilterSection.lists.emptyActionTitle)
        XCTAssertEqual(LibraryFilterSection.lists.emptyHeadline, LunaCopy.emptyCustomListsHeadline)

        let inactiveForHome = TabMemoryEvictionPolicy.inactiveTabsToUnload(activeTab: .home)
        XCTAssertFalse(inactiveForHome.contains(.home))
        XCTAssertFalse(inactiveForHome.contains(.settings))
        XCTAssertEqual(inactiveForHome, [.movies, .series, .library, .search])
    }

    @MainActor
    func testHomeViewModelSWR304DiffAndMemoryWarningUnload() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runHomeViewModelTest()
        }
    }

    @MainActor
    private func runHomeViewModelTest() async throws {
        let client = MockHomeCatalogLibraryClient()
        let session = MockTabSession(client: client)
        let card = TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club")
        let home1 = TvHomeResponse(
            ok: true,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            rows: [TvShelfRow(rowId: "popular-movies", title: "Populært", rowStyle: "poster", items: [card])]
        )
        let data1 = try JSONEncoder().encode(home1)
        client.lock.withLock { s in
            s.homeResponses = [.updated(payload: home1, etag: "\"h1\"", rawPayloadData: data1), .notModified]
        }

        let vm = HomeViewModel(initialServerHost: session.serverBaseURL?.host, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "Fight Club")
        XCTAssertEqual(vm.cachedEtag, "\"h1\"")

        // Unload on 4 GB memory warning clears shelves while preserving ETag and recovering from DiskSWR on re-activation
        await DiskSWRStore.drainPendingWrites()
        vm.unloadForMemoryWarning()
        XCTAssertTrue(vm.visibleRows.isEmpty)
        XCTAssertTrue(vm.isUnloadedForMemoryWarning)

        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "Fight Club")
        XCTAssertFalse(vm.isUnloadedForMemoryWarning)
        XCTAssertEqual(client.lock.withLock { $0.homeETagsRequested }, [nil, "\"h1\""])
    }

    @MainActor
    func testCatalogBrowseViewModelSWRPaginationOptimisticRollbackAndUnload() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runCatalogBrowseViewModelTest()
        }
    }

    @MainActor
    private func runCatalogBrowseViewModelTest() async throws {
        CatalogBrowseMemoryCache.shared.clear()
        defer {
            CatalogBrowseMemoryCache.shared.clear()
        }

        let client = MockHomeCatalogLibraryClient()
        let session = MockTabSession(client: client)
        let card1 = TvMediaCard(itemId: "movie:tmdb:1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "Film 1", inWatchlist: false)
        let card2 = TvMediaCard(itemId: "movie:tmdb:2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "Film 2", inWatchlist: false)
        let page1 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: true, items: [card1])
        let page2 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 2, limit: 24, hasMore: false, items: [card1, card2])

        client.lock.withLock { s in
            s.catalogResponses = [
                .updated(payload: page1, etag: "\"cat-1\"", rawPayloadData: (try? JSONEncoder().encode(page1)) ?? Data()),
                .updated(payload: page2, etag: nil, rawPayloadData: Data()),
                .notModified,
            ]
            s.shouldFailWatchlist = true
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

        // Memory warning unload clears items and recovers via DiskSWR + 304 on reactivation
        await DiskSWRStore.drainPendingWrites()
        CatalogBrowseMemoryCache.shared.clear()
        vm.unloadForMemoryWarning()
        XCTAssertTrue(vm.items.isEmpty)

        await vm.handleActivation(session: session, isActive: true)
        XCTAssertEqual(vm.items.map(\.title), ["Film 1"])
        XCTAssertEqual(client.lock.withLock { $0.catalogRequests.last?.etag }, "\"cat-1\"")
    }

    @MainActor
    func testLibraryViewModelListsPillDiskSWRAndMemoryUnload() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runLibraryViewModelTest()
        }
    }

    @MainActor
    private func runLibraryViewModelTest() async throws {
        LibraryBrowseMemoryCache.shared.clear()
        defer {
            LibraryBrowseMemoryCache.shared.clear()
        }

        let client = MockHomeCatalogLibraryClient()
        let session = MockTabSession(client: client)
        let listItem = TvLibraryCustomList(id: "custom:nordic", name: "Nordisk spenning", mediaType: "series", itemCount: 5, browsePath: "/api/tv/v2/rows/custom%3Anordic")
        let libLists = TvLibraryResponse(
            ok: true,
            section: "lists",
            counts: TvLibraryCounts(watchlist: 1, localTotal: 1, localMovies: 1, localSeries: 0, nvme: 1, archive: 0, vfs: 0, customLists: 1, customListsCount: 1),
            watchlist: [],
            localItems: [],
            customLists: [listItem]
        )

        client.lock.withLock { s in
            s.libraryResponses = [
                .updated(payload: libLists, etag: "\"lib-l1\"", rawPayloadData: (try? JSONEncoder().encode(libLists)) ?? Data()),
                .notModified,
            ]
        }

        let vm = LibraryViewModel()
        vm.activeSection = .lists
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.customLists.map(\.name), ["Nordisk spenning"])
        XCTAssertEqual(vm.cachedEtag, "\"lib-l1\"")

        await DiskSWRStore.drainPendingWrites()
        LibraryBrowseMemoryCache.shared.clear()
        vm.unloadForMemoryWarning()
        XCTAssertNil(vm.libraryPayload)
        XCTAssertTrue(vm.customLists.isEmpty)

        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.customLists.map(\.name), ["Nordisk spenning"])
        XCTAssertEqual(client.lock.withLock { $0.libraryRequests.last?.etag }, "\"lib-l1\"")
    }
}
