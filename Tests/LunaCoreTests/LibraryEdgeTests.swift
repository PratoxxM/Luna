import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class LibraryEdgeMockClient: LibraryClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var libraryHandlers: [@Sendable (String, String, Int, String?) async throws -> ConditionalHTTPResult<TvLibraryResponse>] = []
        var libraryRequests: [(section: String, mediaType: String, offset: Int, etag: String?)] = []
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
private final class LibraryEdgeTabSession: TabSessionContext {
    var serverBaseURL: URL?
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    let client: LibraryEdgeMockClient

    init(client: LibraryEdgeMockClient, host: String = "lib-edge-\(UUID().uuidString.lowercased()).local") {
        self.client = client
        self.serverBaseURL = URL(string: "http://\(host):8090")
    }

    func makeHomeClient() -> (any HomeClientProviding)? { nil }
    func makeCatalogClient() -> (any CatalogClientProviding)? { nil }
    func makeLibraryClient() -> (any LibraryClientProviding)? { client }
    func makeSearchClient() -> (any SearchClientProviding)? { nil }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
}

final class LibraryEdgeTests: XCTestCase {
    @MainActor
    func testLibraryNilETagClearSectionSwitchErrorAndInitialFallbackSwitch() async {
        await DiskSWRTestGate.shared.withLock { @MainActor in
            await self.runLibraryEdgeTest()
        }
    }

    @MainActor
    private func runLibraryEdgeTest() async {
        LibraryBrowseMemoryCache.shared.clear()
        defer { LibraryBrowseMemoryCache.shared.clear() }

        let client = LibraryEdgeMockClient()
        let session = LibraryEdgeTabSession(client: client)

        let movieCard = TvMediaCard(itemId: "movie:tmdb:55", mediaType: "movie", ids: TvMediaIds(tmdb: 55), title: "LocalMovie")
        let moviesPayload = TvLibraryResponse(
            ok: true,
            section: "local",
            counts: TvLibraryCounts(watchlist: 0, localTotal: 1, localMovies: 1, localSeries: 1, nvme: 1, archive: 0, vfs: 0, customLists: 1, customListsCount: 1),
            watchlist: [],
            localItems: [movieCard],
            customLists: []
        )
        let listsPayload = TvLibraryResponse(
            ok: true,
            section: "lists",
            counts: moviesPayload.counts,
            watchlist: [],
            localItems: [],
            customLists: [TvLibraryCustomList(id: "custom:fav", name: "Favoritter", itemCount: 2, browsePath: "/api/tv/v2/rows/custom%3Afav")]
        )

        let vm = LibraryViewModel()
        vm.activeSection = .lists
        let listsKey = vm.queryKey(for: session)
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(
                payload: listsPayload,
                localItems: [],
                localOffset: 0,
                localHasMore: false,
                fetchedAt: Date(),
                refreshNonce: session.homeRefreshNonce,
                etag: nil
            ),
            for: listsKey
        )

        vm.activeSection = .movies
        client.lock.withLock { s in
            s.libraryHandlers = [
                { _, _, _, _ in .updated(payload: moviesPayload, etag: "\"etag-movies\"", rawPayloadData: Data()) },
                { _, _, _, _ in throw LunaCoreError.serverMessage(500, "Seriefeil") },
            ]
        }

        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.cachedEtag, "\"etag-movies\"")
        XCTAssertEqual(vm.activeMediaCards.map(\.title), ["LocalMovie"])

        // 1. Cached snapshot with etag == nil must overwrite previous section's ETag
        vm.activeSection = .lists
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertNil(vm.cachedEtag)

        // 2. Switching to uncached section that errors must clear stale items and surface error
        vm.activeSection = .series
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertTrue(vm.activeMediaCards.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.cachedEtag)

        // 3. Initial section fallback (.movies -> .series from cache) must NOT discard .series response
        LibraryBrowseMemoryCache.shared.clear()
        let fallbackClient = LibraryEdgeMockClient()
        let fallbackSession = LibraryEdgeTabSession(client: fallbackClient)
        let seriesCard = TvMediaCard(itemId: "series:tmdb:99", mediaType: "series", ids: TvMediaIds(tmdb: 99), title: "FallbackSeries")
        let zeroMovieCounts = TvLibraryCounts(watchlist: 0, localTotal: 1, localMovies: 0, localSeries: 1, nvme: 1, archive: 0, vfs: 0, customLists: 0, customListsCount: 0)
        let staleMoviesCache = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [], customLists: [])
        let freshSeriesResp = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [seriesCard], customLists: [])

        let fallbackVM = LibraryViewModel()
        fallbackVM.activeSection = .movies
        let movieCacheKey = fallbackVM.queryKey(for: fallbackSession)
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(
                payload: staleMoviesCache,
                localItems: [],
                localOffset: 0,
                localHasMore: false,
                fetchedAt: Date().addingTimeInterval(-3600),
                refreshNonce: 0,
                etag: "\"old-movies-etag\""
            ),
            for: movieCacheKey
        )
        fallbackClient.lock.withLock { s in
            s.libraryHandlers = [
                { _, mediaType, _, etag in
                    XCTAssertEqual(mediaType, "series")
                    XCTAssertNil(etag)
                    return .updated(payload: freshSeriesResp, etag: "\"etag-series\"", rawPayloadData: Data())
                }
            ]
        }

        await fallbackVM.handleActivation(session: fallbackSession, isActiveTab: true)
        XCTAssertEqual(fallbackVM.activeSection, .series)
        XCTAssertEqual(fallbackVM.activeMediaCards.map(\.title), ["FallbackSeries"])
        XCTAssertEqual(fallbackVM.cachedEtag, "\"etag-series\"")
    }

    @MainActor
    func testLibraryColdFallbackClearsMoviesETagAndLoadsSeries() async {
        await DiskSWRTestGate.shared.withLock { @MainActor in
            await self.runLibraryColdFallbackTest()
        }
    }

    @MainActor
    private func runLibraryColdFallbackTest() async {
        LibraryBrowseMemoryCache.shared.clear()
        defer { LibraryBrowseMemoryCache.shared.clear() }

        let client = LibraryEdgeMockClient()
        let session = LibraryEdgeTabSession(client: client)
        let zeroMovieCounts = TvLibraryCounts(watchlist: 0, localTotal: 1, localMovies: 0, localSeries: 1, nvme: 1, archive: 0, vfs: 0, customLists: 0, customListsCount: 0)
        let emptyMovies = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [], customLists: [])
        let seriesCard = TvMediaCard(itemId: "series:tmdb:990", mediaType: "series", ids: TvMediaIds(tmdb: 990), title: "ColdFallbackSeries")
        let seriesResp = TvLibraryResponse(ok: true, section: "local", counts: zeroMovieCounts, watchlist: [], localItems: [seriesCard], customLists: [])

        client.lock.withLock { s in
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
            ]
        }

        let vm = LibraryViewModel()
        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertEqual(vm.activeSection, .series)
        XCTAssertNil(vm.cachedEtag)
        XCTAssertTrue(vm.isLoading)

        await vm.handleActivation(session: session, isActiveTab: true)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.activeMediaCards.map(\.title), ["ColdFallbackSeries"])
        XCTAssertEqual(vm.cachedEtag, "\"s-loaded\"")
    }
}
