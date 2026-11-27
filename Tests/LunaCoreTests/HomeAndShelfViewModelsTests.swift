import Foundation
import Synchronization
import XCTest
@testable import LunaCore

final class HomeEdgeMockClient: HomeClientProviding, CatalogClientProviding, LibraryClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var homeHandlers: [@Sendable (String?) async throws -> HomeConditionalResult] = []
        var homeETags: [String?] = []
        var catalogHandlers: [@Sendable (String, String?, Int, String?) async throws -> ConditionalHTTPResult<TvCatalogResponse>] = []
        var catalogRequests: [(kind: String, genre: String?, page: Int, etag: String?)] = []
        var libraryHandlers: [@Sendable (String, String, Int, String?) async throws -> ConditionalHTTPResult<TvLibraryResponse>] = []
        var libraryRequests: [(section: String, mediaType: String, offset: Int, etag: String?)] = []
        var shouldFailWatchlist = false
    }

    func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
        let handler = lock.withLock { s -> (@Sendable (String?) async throws -> HomeConditionalResult)? in
            s.homeETags.append(ifNoneMatch)
            return s.homeHandlers.isEmpty ? nil : s.homeHandlers.removeFirst()
        }
        if let handler { return try await handler(ifNoneMatch) }
        return .notModified
    }

    func fetchCatalog(kind: String, genre: String?, sort: String, localOnly: Bool, unwatchedOnly: Bool, page: Int, limit: Int) async throws -> TvCatalogResponse {
        TvCatalogResponse(ok: true, mediaType: kind, title: "Filmer", sort: sort, localOnly: localOnly, unwatchedOnly: unwatchedOnly, page: page, limit: limit, hasMore: false, items: [])
    }

    func fetchCatalogConditional(kind: String, genre: String?, sort: String, localOnly: Bool, unwatchedOnly: Bool, page: Int, limit: Int, ifNoneMatch: String?) async throws -> ConditionalHTTPResult<TvCatalogResponse> {
        let handler = lock.withLock { s -> (@Sendable (String, String?, Int, String?) async throws -> ConditionalHTTPResult<TvCatalogResponse>)? in
            s.catalogRequests.append((kind, genre, page, ifNoneMatch))
            return s.catalogHandlers.isEmpty ? nil : s.catalogHandlers.removeFirst()
        }
        if let handler { return try await handler(kind, genre, page, ifNoneMatch) }
        return .notModified
    }

    func fetchLibrary(section: String, tier: String, mediaType: String, sort: String, offset: Int, limit: Int, ifNoneMatch: String?) async throws -> ConditionalHTTPResult<TvLibraryResponse> {
        let handler = lock.withLock { s -> (@Sendable (String, String, Int, String?) async throws -> ConditionalHTTPResult<TvLibraryResponse>)? in
            s.libraryRequests.append((section, mediaType, offset, ifNoneMatch))
            return s.libraryHandlers.isEmpty ? nil : s.libraryHandlers.removeFirst()
        }
        if let handler { return try await handler(section, mediaType, offset, ifNoneMatch) }
        return .notModified
    }

    func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {
        if lock.withLock({ $0.shouldFailWatchlist }) {
            throw LunaCoreError.serverMessage(500, "Serverfeil")
        }
    }

    func setWatched(watched: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?, season: Int?, episode: Int?) async throws {}
    func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws {}
    func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool { true }
}

@MainActor
final class HomeEdgeTabSession: TabSessionContext {
    var serverBaseURL: URL?
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    var client: HomeEdgeMockClient

    init(client: HomeEdgeMockClient, host: String = "tab-\(UUID().uuidString.lowercased()).local") {
        self.client = client
        self.serverBaseURL = URL(string: "http://\(host):8090")
    }

    func makeHomeClient() -> (any HomeClientProviding)? { client }
    func makeCatalogClient() -> (any CatalogClientProviding)? { client }
    func makeLibraryClient() -> (any LibraryClientProviding)? { client }
    func makeSearchClient() -> (any SearchClientProviding)? { nil }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
}

final class HomeAndShelfViewModelsTests: XCTestCase {
    // MARK: - CatalogShelfIndexer, Semantic Equality & Navigation Top-Bar Policies

    @MainActor
    func testCatalogShelfIndexerSemanticEqualityAndNavigationVisibilityPolicies() {
        let phoneCard = TvMediaCard(
            itemId: "movie:1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "Blade Runner 2049",
            origin: "phone", availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        )
        let tonightCard = TvMediaCard(
            itemId: "series:2", mediaType: "series", ids: TvMediaIds(tmdb: 2), title: "Severance",
            origin: "tonight", availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        )
        let regularCard = TvMediaCard(
            itemId: "movie:3", mediaType: "movie", ids: TvMediaIds(tmdb: 3), title: "Nosferatu",
            availability: TvAvailabilityInfo(state: "stream", tier: "vfs")
        )

        let payload = TvHomeResponse(
            ok: true, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714",
            tonight: TvTonightPayload(preparedFromPhone: phoneCard),
            rows: [
                TvShelfRow(rowId: "medialogg-watchlist", title: "Huskeliste", rowStyle: "poster", sourceKind: "watchlist", items: [regularCard]),
                TvShelfRow(rowId: "new-4k", title: "Nye filmer i 4K", rowStyle: "poster", sourceKind: "catalog", hasMore: true, items: [regularCard, phoneCard]),
                TvShelfRow(rowId: "medialogg-continue", title: "Fortsett å se", rowStyle: "continue_backdrop", sourceKind: "system_continue", listMode: "smart", items: [regularCard, tonightCard]),
            ]
        )
        let visible = CatalogShelfIndexer.prepareVisibleRows(from: payload)
        XCTAssertEqual(visible.map(\.rowId), ["medialogg-continue", "new-4k"])
        XCTAssertEqual(visible[0].title, "Fortsett")
        XCTAssertEqual(visible[0].items.map(\.itemId), ["movie:1", "series:2", "movie:3"])

        // Cross-row series deduplication collapses empty active_series shelf while preserving discovery shelves
        let lykkelandContinue = TvMediaCard(
            itemId: "episode:tmdb:79291:s4:e6", mediaType: "episode", ids: TvMediaIds(tmdb: 79291), title: "Lykkeland",
            directPlayTarget: TvDirectPlayTarget(itemId: "episode:tmdb:79291:s4:e6", mediaType: "episode", tmdbId: 79291, season: 4, episode: 6)
        )
        let lykkelandActive = TvMediaCard(itemId: "series:tmdb:79291", mediaType: "series", ids: TvMediaIds(tmdb: 79291), title: "Lykkeland")
        let andorActive = TvMediaCard(itemId: "series:tmdb:83867", mediaType: "series", ids: TvMediaIds(tmdb: 83867), title: "Andor")

        let partialRows = CatalogShelfIndexer.prepareVisibleRows(
            from: TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [
                TvShelfRow(rowId: "medialogg-continue", title: "Fortsett", rowStyle: "continue_backdrop", sourceKind: "system_continue", items: [lykkelandContinue]),
                TvShelfRow(rowId: "new-episodes", title: "Nye episoder", rowStyle: "poster", sourceKind: "active_series", items: [lykkelandActive, andorActive]),
                TvShelfRow(rowId: "popular", title: "Populært nå", rowStyle: "poster", sourceKind: "catalog", items: [lykkelandActive]),
            ])
        )
        XCTAssertEqual(partialRows[1].items.map(\.itemId), ["series:tmdb:83867"])
        XCTAssertEqual(partialRows[2].items.map(\.itemId), ["series:tmdb:79291"])

        let collapsedRows = CatalogShelfIndexer.prepareVisibleRows(
            from: TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [
                TvShelfRow(rowId: "medialogg-continue", title: "Fortsett", rowStyle: "continue_backdrop", sourceKind: "system_continue", items: [lykkelandContinue]),
                TvShelfRow(rowId: "new-episodes", title: "Nye episoder", rowStyle: "poster", sourceKind: "active_series", items: [lykkelandActive]),
            ])
        )
        XCTAssertEqual(collapsedRows.map(\.rowId), ["medialogg-continue"])

        // Semantic equality ignores generatedAt
        let h1 = TvHomeResponse(ok: true, generatedAt: "t1", layout: "rows_first", roomName: "Stua", hardwareProfile: "hdr10-512", rows: [])
        let h2 = TvHomeResponse(ok: true, generatedAt: "t2", layout: "rows_first", roomName: "Stua", hardwareProfile: "hdr10-512", rows: [])
        let h3 = TvHomeResponse(ok: true, generatedAt: "t2", layout: "rows_first", roomName: "Loft", hardwareProfile: "hdr10-512", rows: [])
        XCTAssertTrue(h1.isSemanticallyEqual(to: h2))
        XCTAssertFalse(h1.isSemanticallyEqual(to: h3))

        // HomeRefreshPolicy & LunaNavigationBarVisibility + ScrollTopSample extreme bounds
        XCTAssertFalse(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: true, hasActivePlayback: true, secondsSinceLastValidation: 120))
        XCTAssertFalse(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: true, hasActivePlayback: false, secondsSinceLastValidation: 9.9))
        XCTAssertTrue(HomeRefreshPolicy.shouldRevalidateOnForeground(isSceneActive: true, isActiveTab: true, hasActivePlayback: false, secondsSinceLastValidation: 10.0))

        XCTAssertEqual(ScrollTopSample.capture(scrolledOffsetY: 1e30).downwardBucket, Int.max)
        XCTAssertEqual(ScrollTopSample.capture(scrolledOffsetY: .infinity).downwardBucket, Int.max)
        XCTAssertEqual(ScrollTopSample.capture(scrolledOffsetY: .nan).zone, .midBand)

        let now = Date()
        let vis = LunaNavigationBarVisibility()
        vis.reportScrollSample(nil, ScrollTopSample.capture(scrolledOffsetY: 96), for: .home, now: now)
        XCTAssertTrue(vis.isTopBarHidden)
        XCTAssertTrue(vis.shouldInterceptMenuPress(hasActivePlayback: false))
        vis.handleMenuPressToRevealTopBar(now: now)
        XCTAssertFalse(vis.isTopBarHidden)
        let subToken = UUID()
        vis.enterSubpage(subToken)
        XCTAssertTrue(vis.isSubpageActive && vis.isTopBarHidden)
        vis.leaveSubpage(subToken)
        XCTAssertFalse(vis.isSubpageActive)
    }

    // MARK: - HomeViewModel SWR, Memory Unload, Host/Room Transitions & Catalog Warmup

    @MainActor
    func testHomeViewModelSWRMemoryUnloadHostRoomSwitchesAndCatalogWarmup() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            await DiskSWRStore.clearAllAsync()
            CatalogBrowseMemoryCache.shared.clear()
            defer {
                CatalogBrowseMemoryCache.shared.clear()
                Task { await DiskSWRStore.clearAllAsync() }
            }

            let hostA = "home-a-\(UUID().uuidString.lowercased()).local"
            let hostB = "home-b-\(UUID().uuidString.lowercased()).local"
            let clientA = HomeEdgeMockClient()
            let clientB = HomeEdgeMockClient()
            let session = HomeEdgeTabSession(client: clientA, host: hostA)

            let cardA = TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club")
            let cardB = TvMediaCard(itemId: "movie:tmdb:200", mediaType: "movie", ids: TvMediaIds(tmdb: 200), title: "HostBMovie")
            let cardKjeller = TvMediaCard(itemId: "movie:tmdb:402", mediaType: "movie", ids: TvMediaIds(tmdb: 402), title: "KjellerMovie")
            let homeA = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "r1", title: "Populært", rowStyle: "poster", items: [cardA])])
            let homeB = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "r2", title: "B", rowStyle: "poster", items: [cardB])])
            let homeKjeller = TvHomeResponse(ok: true, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", rows: [TvShelfRow(rowId: "rk", title: "K", rowStyle: "poster", items: [cardKjeller])])
            let dataA = try JSONEncoder().encode(homeA)
            let dataB = try JSONEncoder().encode(homeB)
            let dataKjeller = try JSONEncoder().encode(homeKjeller)

            clientA.lock.withLock { s in
                s.homeHandlers = [
                    { _ in .updated(payload: homeA, etag: "\"h1\"", rawPayloadData: dataA) },
                    { _ in .notModified },
                ]
            }
            let vm = HomeViewModel(initialServerHost: hostA, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
            XCTAssertNil(vm.tonightReasonLabel)
            await vm.handleActivation(session: session, isActiveTab: true)
            XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "Fight Club")
            XCTAssertEqual(vm.cachedEtag, "\"h1\"")

            // Memory-warning unload recovers from DiskSWR + 304 Not Modified
            await DiskSWRStore.drainPendingWrites()
            vm.unloadForMemoryWarning()
            XCTAssertTrue(vm.visibleRows.isEmpty && vm.isUnloadedForMemoryWarning)
            await vm.handleActivation(session: session, isActiveTab: true)
            XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "Fight Club")
            XCTAssertEqual(clientA.lock.withLock { $0.homeETags }, [nil, "\"h1\""])

            // Failover to hostB with homeRefreshNonce bump never leaks hostA's ETag
            clientB.lock.withLock { s in
                s.homeHandlers = [
                    { etag in
                        XCTAssertNil(etag)
                        return .updated(payload: homeB, etag: "\"etag-b\"", rawPayloadData: dataB)
                    },
                    { etag in
                        XCTAssertNil(etag)
                        return .updated(payload: homeKjeller, etag: "\"etag-k\"", rawPayloadData: dataKjeller)
                    },
                ]
            }
            session.serverBaseURL = URL(string: "http://\(hostB):8090")
            session.client = clientB
            session.homeRefreshNonce &+= 1
            vm.handleHomeRefreshNonceChange(session.homeRefreshNonce, isActiveTab: true, session: session)
            for _ in 0..<250 where vm.visibleRows.first?.items.first?.title != "HostBMovie" {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "HostBMovie")

            // Foreground room switch clears ETag and fetches fresh room
            session.roomName = "Kjellerstua"
            session.hardwareProfile = "dv-fel-714"
            vm.handleForegroundTransition(isSceneActive: true, isActiveTab: true, session: session, now: Date().addingTimeInterval(30))
            for _ in 0..<250 where vm.visibleRows.first?.items.first?.title != "KjellerMovie" {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertEqual(vm.homePayload?.roomName, "Kjellerstua")

            // Mid-flight cancel resets isInitialColdFetch
            let coldStarted = Mutex(false)
            let coldClient = HomeEdgeMockClient()
            coldClient.lock.withLock { s in
                s.homeHandlers = [{ _ in
                    coldStarted.withLock { $0 = true }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .notModified
                }]
            }
            let coldHost = "cold-\(UUID().uuidString.lowercased()).local"
            let coldSession = HomeEdgeTabSession(client: coldClient, host: coldHost)
            let coldVM = HomeViewModel(initialServerHost: coldHost, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
            coldVM.scheduleRevalidateHome(forceUnconditional: false, session: coldSession)
            for _ in 0..<250 where !coldStarted.withLock({ $0 }) {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(coldVM.isInitialColdFetch)
            coldVM.cancelAllTasks()
            XCTAssertFalse(coldVM.isInitialColdFetch)

            // warmCatalogMetadataAfterHomePaintIfEligible: .standard skips, .high2026 persists verbatim rawPayloadData
            let movieResp = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 48, hasMore: false, items: [cardA])
            let seriesResp = TvCatalogResponse(ok: true, mediaType: "series", title: "Serier", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 48, hasMore: false, items: [])
            let customMovieRaw = Data("  { \"rawMarker\": \"verbatim-movie\", \"ok\": true }  ".utf8)
            clientB.lock.withLock { s in
                s.catalogHandlers = [
                    { _, _, _, _ in .updated(payload: movieResp, etag: "\"w-mov-1\"", rawPayloadData: customMovieRaw) },
                    { _, _, _, _ in .updated(payload: seriesResp, etag: "\"w-ser-1\"", rawPayloadData: Data()) },
                    { _, _, _, etag in
                        XCTAssertEqual(etag, "\"w-mov-1\"")
                        return .notModified
                    },
                    { _, _, _, etag in
                        XCTAssertNil(etag)
                        return .notModified
                    },
                ]
            }
            let gib: UInt64 = 1_073_741_824
            await vm.warmCatalogMetadataAfterHomePaintIfEligible(
                session: session, isPreviewMode: false, delayNanoseconds: 0,
                memoryProfile: DeviceMemoryProfile(physicalMemoryBytes: 4 * gib, activeProcessorCount: 6)
            )
            XCTAssertTrue(clientB.lock.withLock { $0.catalogRequests.isEmpty })

            let highProfile = DeviceMemoryProfile(physicalMemoryBytes: 8 * gib, activeProcessorCount: 6)
            await vm.warmCatalogMetadataAfterHomePaintIfEligible(
                session: session, isPreviewMode: false, delayNanoseconds: 0, memoryProfile: highProfile
            )
            await DiskSWRStore.drainPendingWrites()
            let movieKey = CatalogBrowseViewModel.makeCacheKey(serverBaseURL: session.serverBaseURL, mediaType: "movie", roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
            XCTAssertEqual(CatalogBrowseMemoryCache.shared.snapshot(for: movieKey)?.etag, "\"w-mov-1\"")

            session.homeRefreshNonce &+= 1
            await vm.warmCatalogMetadataAfterHomePaintIfEligible(
                session: session, isPreviewMode: false, delayNanoseconds: 0, memoryProfile: highProfile
            )
            XCTAssertEqual(CatalogBrowseMemoryCache.shared.snapshot(for: movieKey)?.items.map(\.title), ["Fight Club"])
        }
    }
}
