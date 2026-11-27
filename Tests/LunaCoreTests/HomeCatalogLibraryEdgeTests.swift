import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class EdgeMockClient: HomeClientProviding, CatalogClientProviding, LibraryClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var homeHandlers: [@Sendable (String?) async throws -> HomeConditionalResult] = []
        var homeETags: [String?] = []
        var catalogHandlers: [@Sendable (String, String?, Int, String?) async throws -> ConditionalHTTPResult<TvCatalogResponse>] = []
        var catalogRequests: [(kind: String, genre: String?, page: Int, etag: String?)] = []
        var libraryHandlers: [@Sendable (String, String, Int, String?) async throws -> ConditionalHTTPResult<TvLibraryResponse>] = []
        var libraryRequests: [(section: String, mediaType: String, offset: Int, etag: String?)] = []
    }

    func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
        let handler = lock.withLock { s -> (@Sendable (String?) async throws -> HomeConditionalResult)? in
            s.homeETags.append(ifNoneMatch)
            return s.homeHandlers.isEmpty ? nil : s.homeHandlers.removeFirst()
        }
        if let handler {
            return try await handler(ifNoneMatch)
        }
        return .notModified
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
        let handler = lock.withLock { s -> (@Sendable (String, String?, Int, String?) async throws -> ConditionalHTTPResult<TvCatalogResponse>)? in
            s.catalogRequests.append((kind, genre, page, ifNoneMatch))
            return s.catalogHandlers.isEmpty ? nil : s.catalogHandlers.removeFirst()
        }
        if let handler {
            return try await handler(kind, genre, page, ifNoneMatch)
        }
        return .notModified
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
        let handler = lock.withLock { s -> (@Sendable (String, String, Int, String?) async throws -> ConditionalHTTPResult<TvLibraryResponse>)? in
            s.libraryRequests.append((section, mediaType, offset, ifNoneMatch))
            return s.libraryHandlers.isEmpty ? nil : s.libraryHandlers.removeFirst()
        }
        if let handler {
            return try await handler(section, mediaType, offset, ifNoneMatch)
        }
        return .notModified
    }

    func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {}
    func setWatched(watched: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?, season: Int?, episode: Int?) async throws {}
    func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws {}
    func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool { true }
}

@MainActor
private final class EdgeTabSession: TabSessionContext {
    var serverBaseURL: URL?
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    var client: EdgeMockClient

    init(client: EdgeMockClient, host: String = "edge-\(UUID().uuidString.lowercased()).local") {
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

final class HomeCatalogLibraryEdgeTests: XCTestCase {
    @MainActor
    func testCatalogFilterSwitchResetsETagAndClearsStaleItems() async {
        await DiskSWRTestGate.shared.withLock { @MainActor in
            await self.runCatalogFilterSwitchTest()
        }
    }

    @MainActor
    private func runCatalogFilterSwitchTest() async {
        CatalogBrowseMemoryCache.shared.clear()
        defer { CatalogBrowseMemoryCache.shared.clear() }

        let client = EdgeMockClient()
        let session = EdgeTabSession(client: client)
        let popCard = TvMediaCard(itemId: "movie:tmdb:1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "PopularOnly")
        let dramaCard = TvMediaCard(itemId: "movie:tmdb:2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "DramaOnly")
        let popRes = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: false, items: [popCard])
        let dramaRes = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: false, items: [dramaCard])

        client.lock.withLock { s in
            s.catalogHandlers = [
                { _, _, _, _ in .updated(payload: popRes, etag: "\"etag-popular\"", rawPayloadData: Data()) },
                { _, _, _, etag in
                    XCTAssertNil(etag)
                    return .updated(payload: dramaRes, etag: nil, rawPayloadData: Data())
                },
                { _, _, _, _ in throw LunaCoreError.serverMessage(500, "Nettverksfeil") },
            ]
        }

        let vm = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
        await vm.handleActivation(session: session, isActive: true)
        XCTAssertEqual(vm.items.map(\.title), ["PopularOnly"])
        XCTAssertEqual(vm.cachedEtag, "\"etag-popular\"")

        // Switch to drama filter -> must clear popular ETag & items before fetch
        vm.selectedGenreSlug = "drama"
        vm.selectedGenreLabel = "Drama"
        await vm.handleActivation(session: session, isActive: true)
        XCTAssertEqual(vm.items.map(\.title), ["DramaOnly"])
        XCTAssertNil(vm.cachedEtag)

        // Switch to a fresh filter that errors -> must not show DramaOnly from previous filter
        vm.selectedGenreSlug = "sci-fi"
        vm.selectedGenreLabel = "Sci-Fi"
        await vm.handleActivation(session: session, isActive: true)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.cachedEtag)

        let reqs = client.lock.withLock { $0.catalogRequests }
        XCTAssertEqual(reqs.count, 3)
        XCTAssertEqual(reqs[1].genre, "drama")
        XCTAssertNil(reqs[1].etag)
        XCTAssertEqual(reqs[2].genre, "sci-fi")
        XCTAssertNil(reqs[2].etag)
    }

    @MainActor
    func testCatalogFilteredUnloadWithEvictedCacheNeverSendsStaleETag() async {
        await DiskSWRTestGate.shared.withLock { @MainActor in
            await self.runCatalogFilteredUnloadTest()
        }
    }

    @MainActor
    private func runCatalogFilteredUnloadTest() async {
        CatalogBrowseMemoryCache.shared.clear()
        defer { CatalogBrowseMemoryCache.shared.clear() }

        let client = EdgeMockClient()
        let session = EdgeTabSession(client: client)
        let dramaCard = TvMediaCard(itemId: "movie:tmdb:2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "DramaFilm")
        let dramaRes = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: false, items: [dramaCard])

        client.lock.withLock { s in
            s.catalogHandlers = [
                { _, _, _, _ in .updated(payload: dramaRes, etag: "\"etag-drama\"", rawPayloadData: Data()) },
                { _, _, _, etag in
                    XCTAssertNil(etag)
                    return .updated(payload: dramaRes, etag: "\"etag-drama-2\"", rawPayloadData: Data())
                },
            ]
        }

        let vm = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
        vm.selectedGenreSlug = "drama"
        await vm.handleActivation(session: session, isActive: true)
        XCTAssertEqual(vm.items.map(\.title), ["DramaFilm"])

        vm.unloadForMemoryWarning()
        CatalogBrowseMemoryCache.shared.clear()
        XCTAssertTrue(vm.items.isEmpty)

        await vm.handleActivation(session: session, isActive: true)
        XCTAssertEqual(vm.items.map(\.title), ["DramaFilm"])
        XCTAssertNil(client.lock.withLock { $0.catalogRequests.last?.etag })
    }

    @MainActor
    func testCatalogScheduleReloadAndDeferGuardPreventStuckIsLoadingMore() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runCatalogLoadMoreTest()
        }
    }

    @MainActor
    private func runCatalogLoadMoreTest() async throws {
        CatalogBrowseMemoryCache.shared.clear()
        defer { CatalogBrowseMemoryCache.shared.clear() }

        let client = EdgeMockClient()
        let session = EdgeTabSession(client: client)
        let p1 = TvMediaCard(itemId: "movie:tmdb:10", mediaType: "movie", ids: TvMediaIds(tmdb: 10), title: "Page1")
        let p1New = TvMediaCard(itemId: "movie:tmdb:20", mediaType: "movie", ids: TvMediaIds(tmdb: 20), title: "NewFilterP1")
        let p2New = TvMediaCard(itemId: "movie:tmdb:21", mediaType: "movie", ids: TvMediaIds(tmdb: 21), title: "NewFilterP2")
        let res1 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: true, items: [p1])
        let resNew1 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: true, items: [p1New])
        let resNew2 = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 2, limit: 24, hasMore: false, items: [p2New])

        let oldPage2Started = Mutex(false)
        let newPage2Started = Mutex(false)

        client.lock.withLock { s in
            s.catalogHandlers = [
                { _, _, _, _ in .updated(payload: res1, etag: "\"e1\"", rawPayloadData: Data()) },
                { _, _, _, _ in
                    oldPage2Started.withLock { $0 = true }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .notModified
                },
                { _, _, _, _ in .updated(payload: resNew1, etag: "\"e2\"", rawPayloadData: Data()) },
                { _, _, _, _ in
                    newPage2Started.withLock { $0 = true }
                    try await Task.sleep(nanoseconds: 40_000_000)
                    return .updated(payload: resNew2, etag: nil, rawPayloadData: Data())
                },
            ]
        }

        let vm = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
        await vm.handleActivation(session: session, isActive: true)
        XCTAssertTrue(vm.hasMore)

        vm.scheduleLoadNextPage(session: session)
        for _ in 0..<250 {
            if oldPage2Started.withLock({ $0 }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isLoadingMore)

        // Switching filter resets isLoadingMore immediately and cancels old page-2 fetch
        vm.selectedGenreSlug = "action"
        vm.scheduleReloadFirstPage(forceNetwork: false, session: session)
        XCTAssertFalse(vm.isLoadingMore)

        // Wait for new filter page 1 to finish
        for _ in 0..<250 {
            if vm.items.map(\.title) == ["NewFilterP1"] { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(vm.items.map(\.title), ["NewFilterP1"])
        XCTAssertFalse(vm.isLoadingMore)

        // Trigger new page 2 and ensure old unwinding defer never clobbers or blocks it
        vm.scheduleLoadNextPage(session: session)
        for _ in 0..<250 {
            if newPage2Started.withLock({ $0 }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isLoadingMore)
        for _ in 0..<250 {
            if !vm.isLoadingMore && vm.items.count == 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(vm.items.map(\.title), ["NewFilterP1", "NewFilterP2"])
        XCTAssertFalse(vm.isLoadingMore)

        vm.cancelAllTasks()
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
    }

    @MainActor
    func testHomeUnloadWithMissingDiskSWRHostSwitchAndCancelMidFlight() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runHomeEdgeTest()
        }
    }

    @MainActor
    private func runHomeEdgeTest() async throws {
        let clientA = EdgeMockClient()
        let clientB = EdgeMockClient()
        let hostA = "alpha-home-\(UUID().uuidString.lowercased()).local"
        let hostB = "beta-home-\(UUID().uuidString.lowercased()).local"
        let coldHost = "cold-home-\(UUID().uuidString.lowercased()).local"
        let session = EdgeTabSession(client: clientA, host: hostA)

        let cardAlpha = TvMediaCard(itemId: "movie:tmdb:100", mediaType: "movie", ids: TvMediaIds(tmdb: 100), title: "AlphaMovie")
        let cardBeta = TvMediaCard(itemId: "movie:tmdb:200", mediaType: "movie", ids: TvMediaIds(tmdb: 200), title: "BetaMovie")
        let homeAlpha = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "r1", title: "Alpha", rowStyle: "poster", items: [cardAlpha])])
        let homeBeta = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "r2", title: "Beta", rowStyle: "poster", items: [cardBeta])])
        let alphaData = try JSONEncoder().encode(homeAlpha)
        let betaData = try JSONEncoder().encode(homeBeta)

        // First response uses empty rawPayloadData so DiskSWR disk file cannot decode after clearMemory(),
        // isolating the missing-DiskSWR unload scenario without wiping other parallel workers' disk cache.
        clientA.lock.withLock { s in
            s.homeHandlers = [
                { _ in .updated(payload: homeAlpha, etag: "\"etag-alpha\"", rawPayloadData: Data()) },
                { etag in
                    XCTAssertNil(etag)
                    return .updated(payload: homeAlpha, etag: "\"etag-alpha-2\"", rawPayloadData: alphaData)
                },
            ]
        }
        clientB.lock.withLock { s in
            s.homeHandlers = [
                { etag in
                    XCTAssertNil(etag)
                    return .updated(payload: homeBeta, etag: "\"etag-beta\"", rawPayloadData: betaData)
                },
            ]
        }

        let vm = HomeViewModel(initialServerHost: session.serverBaseURL?.host, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "AlphaMovie")

        // 1. Unload + missing DiskSWR must clear cachedEtag and never send If-None-Match
        await DiskSWRStore.drainPendingWrites()
        DiskSWRStore.clearMemory()
        vm.unloadForMemoryWarning()
        XCTAssertNil(vm.homePayload)
        XCTAssertNil(vm.cachedEtag)

        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "AlphaMovie")
        XCTAssertNil(clientA.lock.withLock { $0.homeETags.last ?? "non-nil" })

        // 2. Switch to hostB with identical roomName & hardwareProfile -> must NOT leak hostA's ETag or payload
        await DiskSWRStore.drainPendingWrites()
        session.serverBaseURL = URL(string: "http://\(hostB):8090")
        session.client = clientB
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "BetaMovie")
        XCTAssertEqual(clientB.lock.withLock { $0.homeETags }, [nil])

        // 3. Mid-flight cancellation resets isInitialColdFetch = false
        let coldStarted = Mutex(false)
        let coldClient = EdgeMockClient()
        coldClient.lock.withLock { s in
            s.homeHandlers = [
                { _ in
                    coldStarted.withLock { $0 = true }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return .notModified
                }
            ]
        }
        session.client = coldClient
        session.serverBaseURL = URL(string: "http://\(coldHost):8090")
        let coldVM = HomeViewModel(initialServerHost: coldHost, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        coldVM.scheduleRevalidateHome(forceUnconditional: false, session: session)
        for _ in 0..<250 {
            if coldStarted.withLock({ $0 }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(coldVM.isInitialColdFetch)
        coldVM.cancelAllTasks()
        XCTAssertFalse(coldVM.isInitialColdFetch)
    }

    @MainActor
    func testHomeFailoverRefreshNonceThenHandleActivationNeverLeaksETagOrPoisonsCache() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runHomeFailoverNonceTest()
        }
    }

    @MainActor
    private func runHomeFailoverNonceTest() async throws {
        let hostA = "failover-a-\(UUID().uuidString.lowercased()).local"
        let hostB = "failover-b-\(UUID().uuidString.lowercased()).local"
        let clientA = EdgeMockClient()
        let clientB = EdgeMockClient()
        let session = EdgeTabSession(client: clientA, host: hostA)

        let cardA = TvMediaCard(itemId: "movie:tmdb:301", mediaType: "movie", ids: TvMediaIds(tmdb: 301), title: "HostA_Only")
        let cardB = TvMediaCard(itemId: "movie:tmdb:302", mediaType: "movie", ids: TvMediaIds(tmdb: 302), title: "HostB_Only")
        let homeA = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "rA", title: "A", rowStyle: "poster", items: [cardA])])
        let homeB = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "rB", title: "B", rowStyle: "poster", items: [cardB])])
        let dataA = try JSONEncoder().encode(homeA)
        let dataB = try JSONEncoder().encode(homeB)

        clientA.lock.withLock { s in
            s.homeHandlers = [
                { _ in .updated(payload: homeA, etag: "\"etag-1\"", rawPayloadData: dataA) },
            ]
        }
        clientB.lock.withLock { s in
            s.homeHandlers = [
                { etag in
                    if etag != nil { return .notModified }
                    return .updated(payload: homeB, etag: "\"etag-b\"", rawPayloadData: dataB)
                },
            ]
        }

        let vm = HomeViewModel(initialServerHost: hostA, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "HostA_Only")
        XCTAssertEqual(vm.cachedEtag, "\"etag-1\"")

        // Failover switches serverBaseURL to hostB and bumps homeRefreshNonce
        session.serverBaseURL = URL(string: "http://\(hostB):8090")
        session.client = clientB
        session.homeRefreshNonce &+= 1
        vm.handleHomeRefreshNonceChange(session.homeRefreshNonce, isActiveTab: true, session: session)
        for _ in 0..<250 {
            if vm.visibleRows.first?.items.first?.title == "HostB_Only" { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await vm.handleActivation(session: session, isActiveTab: true)

        XCTAssertEqual(clientB.lock.withLock { $0.homeETags }, [nil])
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "HostB_Only")
        XCTAssertEqual(vm.validatedScopeKey, vm.scopeKey(for: session))
    }

    @MainActor
    func testHomeForegroundTransitionRoomSwitchClearsETagAndFetchesFreshRoom() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runHomeForegroundRoomSwitchTest()
        }
    }

    @MainActor
    private func runHomeForegroundRoomSwitchTest() async throws {
        let host = "room-switch-\(UUID().uuidString.lowercased()).local"
        let client = EdgeMockClient()
        let session = EdgeTabSession(client: client, host: host)

        let stuaCard = TvMediaCard(itemId: "movie:tmdb:401", mediaType: "movie", ids: TvMediaIds(tmdb: 401), title: "StuaMovie")
        let kjellerCard = TvMediaCard(itemId: "movie:tmdb:402", mediaType: "movie", ids: TvMediaIds(tmdb: 402), title: "KjellerstuaMovie")
        let homeStua = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [TvShelfRow(rowId: "rs", title: "Stua", rowStyle: "poster", items: [stuaCard])])
        let homeKjeller = TvHomeResponse(ok: true, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", rows: [TvShelfRow(rowId: "rk", title: "Kjeller", rowStyle: "poster", items: [kjellerCard])])
        let dataStua = try JSONEncoder().encode(homeStua)
        let dataKjeller = try JSONEncoder().encode(homeKjeller)

        client.lock.withLock { s in
            s.homeHandlers = [
                { _ in .updated(payload: homeStua, etag: "\"etag-stua\"", rawPayloadData: dataStua) },
                { etag in
                    if etag != nil { return .notModified }
                    return .updated(payload: homeKjeller, etag: "\"etag-kjeller\"", rawPayloadData: dataKjeller)
                },
            ]
        }

        let vm = HomeViewModel(initialServerHost: host, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "StuaMovie")

        session.roomName = "Kjellerstua"
        session.hardwareProfile = "dv-fel-714"
        vm.handleForegroundTransition(
            isSceneActive: true,
            isActiveTab: true,
            session: session,
            now: Date().addingTimeInterval(30)
        )
        for _ in 0..<250 {
            if vm.visibleRows.first?.items.first?.title == "KjellerstuaMovie" { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(client.lock.withLock { $0.homeETags }, [nil, nil])
        XCTAssertEqual(vm.homePayload?.roomName, "Kjellerstua")
        XCTAssertEqual(vm.visibleRows.first?.items.first?.title, "KjellerstuaMovie")
        XCTAssertEqual(vm.validatedScopeKey, vm.scopeKey(for: session))
    }
}
