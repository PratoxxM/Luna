import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class SpyDetailPrewarmer: DetailStreamPrewarming, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var registeredSecrets: [String] = []
        var unregisteredSecrets: [String] = []
        var prewarmedURLs: [URL] = []
    }

    func registerStreamSecret(_ secret: String) {
        lock.withLock { $0.registeredSecrets.append(secret) }
    }

    func unregisterStreamSecret(_ secret: String) {
        lock.withLock { $0.unregisteredSecrets.append(secret) }
    }

    func prewarmIfNeeded(url: URL, httpHeaders: [String: String], byteBudget: Int) async {
        lock.withLock { $0.prewarmedURLs.append(url) }
    }
}

@MainActor
private final class LinuxDetailSessionContext: MediaDetailSessionContext {
    var roomName: String = "Kjellerstua"
    var hardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var activePlaybackTarget: PlaybackLaunchRequest?
    var keepDisplayModeInMenuAfterPlayback: Bool = false
    var client: LunaCoreClient?
    let receiptStore = PlaybackStopReceiptStore()
    let spyPrewarmer = SpyDetailPrewarmer()
    var disappearCalls: [(Bool, Bool)] = []

    var lastPlaybackStopReceipt: PlaybackStopReceipt? { receiptStore.lastReceipt }
    var detailStreamPrewarmer: any DetailStreamPrewarming { spyPrewarmer }

    func makeClient() -> LunaCoreClient? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
    func awaitPlaybackStopReceipt(for itemId: String, timeout: Duration) async -> PlaybackStopReceipt? {
        await receiptStore.awaitReceipt(for: itemId, timeout: timeout)
    }
    func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration,
        recordedAfter: Date?,
        excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt? {
        await receiptStore.awaitReceipt(
            for: itemId,
            timeout: timeout,
            recordedAfter: recordedAfter,
            excluding: preLaunchReceipt
        )
    }
    func handleDetailDisappear(isLaunchingPlayback: Bool, isShowingSourcePicker: Bool) {
        disappearCalls.append((isLaunchingPlayback, isShowingSourcePicker))
    }
}

private final class MockSourcePickerClient: SourcePickerSessionClient, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var use404ForItemCandidates = false
        var cancelAlternatives = false
        var stoppedSessions: [String] = []
    }

    private let candidate = TvCandidateInfo(
        candidateId: "cand-1",
        displayHeadline: "4K HDR10+ TrueHD Atmos",
        releaseTitle: "Film.2024.2160p",
        source: "nvme",
        tier: "nvme",
        resolution: "2160p",
        videoRangeType: "HDR10Plus",
        dvProfile: nil,
        dvEnhancementLayer: nil,
        audioCodec: "TrueHD Atmos",
        sizeBytes: 53_687_091_200,
        tvScore: 1500,
        isActive: true,
        explanationChips: nil,
        releaseGroup: nil,
        isNorwegian: false
    )

    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        prepareToken: String?
    ) async throws -> TvPrepareResponse {
        let session = TvPlaybackSession(
            sessionId: "sess-fallback-1",
            streamToken: "stream-tok-12345678",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            item: TvPlaybackItemContext(itemId: itemId, mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: title, seriesTitle: seriesTitle),
            selectedCandidate: candidate,
            stream: TvStreamEndpoint(url: "/api/tv/v2/streams/sess-fallback-1/master", supportsByteRanges: true, canClientPrewarmBytes: true),
            aetherConfig: TvAetherConfig(preferDualLayerDolbyVision: true, dolbyVisionHandling: "fel", matchContentEnabled: true, audioBridgeMode: "objectAudio")
        )
        return TvPrepareResponse(ok: true, prepareToken: "prep-fallback-1", playbackSession: session)
    }

    func cancelInflightPlayback(sessionId: String?, resolveId: String?, itemId: String?, prepareToken: String?) async throws {}

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        if lock.withLock({ $0.cancelAlternatives }) {
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        }
        return TvAlternativesResponse(ok: true, sessionId: sessionId, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", activeCandidateId: "cand-1", alternatives: [candidate])
    }

    func fetchItemCandidates(itemId: String, title: String, seriesTitle: String?) async throws -> TvAlternativesResponse {
        if lock.withLock({ $0.use404ForItemCandidates }) {
            throw LunaCoreError.serverMessage(404, "Not found")
        }
        return TvAlternativesResponse(ok: true, sessionId: "", roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", activeCandidateId: "cand-1", alternatives: [candidate])
    }

    func sendHeartbeat(sessionId: String, state: String, positionSeconds: Double, durationSeconds: Double, completed: Bool?) async throws -> TvHeartbeatResponse {
        if state == "stopped" {
            lock.withLock { $0.stoppedSessions.append(sessionId) }
        }
        return TvHeartbeatResponse(ok: true, sessionId: sessionId, state: state)
    }
}

final class DetailAndSourcePickerViewModelsTests: XCTestCase {
    // MARK: - PlaybackStopReceiptStore, Pre-Resolve Policy & SourcePickerViewModel

    @MainActor
    func testPlaybackStopReceiptStorePreResolvePolicyAndSourcePickerViewModel() async throws {
        // PlaybackStopReceiptStore wakeup, timeout, excluding, recordedAfter & cancellation
        let store = PlaybackStopReceiptStore()
        let baseDate = Date()
        let oldReceipt = PlaybackStopReceipt(itemId: "movie:tmdb:10", mediaType: "movie", positionSeconds: 100, durationSeconds: 1000, completed: false, recordedAt: baseDate)
        store.record(oldReceipt)

        let excluded = await store.awaitReceipt(for: "movie:tmdb:10", timeout: .milliseconds(25), excluding: oldReceipt)
        XCTAssertNil(excluded)
        let futureCutoff = await store.awaitReceipt(for: "movie:tmdb:10", timeout: .milliseconds(25), recordedAfter: baseDate.addingTimeInterval(60))
        XCTAssertNil(futureCutoff)

        let cancelledWaiter = Task { @MainActor in
            await store.awaitReceipt(for: "movie:tmdb:20", timeout: .seconds(5))
        }
        try? await Task.sleep(for: .milliseconds(10))
        cancelledWaiter.cancel()
        let cancelledVal = await cancelledWaiter.value
        XCTAssertNil(cancelledVal)

        let targetWaiter = Task { @MainActor in
            await store.awaitReceipt(for: "series:tmdb:95396", timeout: .seconds(2))
        }
        try? await Task.sleep(for: .milliseconds(15))
        store.record(PlaybackStopReceipt(itemId: "movie:tmdb:999", mediaType: "movie", positionSeconds: 50, durationSeconds: 200, completed: false))
        let matching = PlaybackStopReceipt(itemId: "series:tmdb:95396", mediaType: "episode", seasonNumber: 2, episodeNumber: 4, positionSeconds: 1800, durationSeconds: 3000, completed: true)
        store.record(matching)
        let received = await targetWaiter.value
        XCTAssertEqual(received, matching)

        // DetailReloadPolicy & DetailPreResolveController
        XCTAssertEqual(DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: false, loadedScopeKey: nil, currentScopeKey: "a", lastSeenRefreshNonce: 1, currentRefreshNonce: 1), .loadInitial)
        XCTAssertEqual(DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: true, loadedScopeKey: "a", currentScopeKey: "a", lastSeenRefreshNonce: 1, currentRefreshNonce: 2), .reloadPreservingSeason)
        XCTAssertEqual(DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: true, loadedScopeKey: "a", currentScopeKey: "a", lastSeenRefreshNonce: 2, currentRefreshNonce: 2), .skip)

        let preController = DetailPreResolveController()
        let handoff = preController.consumeHandoffForPlayback(itemId: "movie:tmdb:1", startPosition: nil, client: nil)
        XCTAssertNil(handoff.prepareToken)
        preController.discardPreparedSession(client: nil)
        XCTAssertFalse(preController.isPreResolvedReady)

        // SourcePickerViewModel fast path, 404 fallback + orphan stop, and NSURLErrorCancelled handling
        let pickerClient = MockSourcePickerClient()
        let ctx = SourcePickerContext(itemId: "movie:tmdb:550", title: "Fight Club", startPositionSeconds: 0)
        let fastVM = SourcePickerViewModel()
        await fastVM.loadCandidates(context: ctx, client: pickerClient, onUnauthorized: {})
        XCTAssertEqual(fastVM.candidates.count, 1)
        var handedToken: String?
        fastVM.selectCandidate(fastVM.candidates[0], isCurrent: true, context: ctx, client: pickerClient) { _, tok, _ in
            handedToken = tok
        }
        XCTAssertEqual(handedToken, SourcePickerTokenPolicy.adoptInflightDefaultSentinel)

        pickerClient.lock.withLock { $0.use404ForItemCandidates = true }
        let fallbackVM = SourcePickerViewModel()
        await fallbackVM.loadCandidates(context: ctx, client: pickerClient, onUnauthorized: {})
        XCTAssertEqual(fallbackVM.resolvedPrepareToken, "prep-fallback-1")
        fallbackVM.handleDisappear(context: ctx, client: pickerClient)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(pickerClient.lock.withLock { $0.stoppedSessions }, ["sess-fallback-1"])

        pickerClient.lock.withLock { s in
            s.stoppedSessions.removeAll()
            s.cancelAlternatives = true
        }
        let cancelVM = SourcePickerViewModel()
        var unauthCalls = 0
        await cancelVM.loadCandidates(context: ctx, client: pickerClient, onUnauthorized: { unauthCalls += 1 })
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(cancelVM.errorMessage)
        XCTAssertNil(cancelVM.createdOrphanSessionId)
        XCTAssertEqual(unauthCalls, 0)
        XCTAssertEqual(pickerClient.lock.withLock { $0.stoppedSessions }, ["sess-fallback-1"])
    }

    // MARK: - MediaDetailViewModel Stop-Receipt Wakeup, Replay, Generation Guard & Season 0

    @MainActor
    func testMediaDetailViewModelStopReceiptReplayOptimisticPreservationAndSeasonZero() async throws {
        let host = "detail-vm-\(UUID().uuidString.lowercased()).local"
        defer {
            LunaCoreMockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        // 1. Extreme & non-finite heroPrimaryPlayTitle overflow guard
        let overflowVM = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:1", initialTitle: "Test")
        let extremeMovie = TvItemDetail(itemId: "movie:tmdb:1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "Test", inWatchlist: false, watched: false, progress: TvWatchProgress(positionSeconds: 40, durationSeconds: 1e30, percent: 50))
        let infMovie = TvItemDetail(itemId: "movie:tmdb:2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "Test", inWatchlist: false, watched: false, progress: TvWatchProgress(positionSeconds: 40, durationSeconds: .infinity, percent: 50))
        let normalMovie = TvItemDetail(itemId: "movie:tmdb:3", mediaType: "movie", ids: TvMediaIds(tmdb: 3), title: "Test", inWatchlist: false, watched: false, progress: TvWatchProgress(positionSeconds: 600, durationSeconds: 5400, percent: 11))
        XCTAssertEqual(overflowVM.heroPrimaryPlayTitle(extremeMovie), "Fortsett")
        XCTAssertEqual(overflowVM.heroPrimaryPlayTitle(infMovie), "Fortsett")
        XCTAssertEqual(overflowVM.heroPrimaryPlayTitle(normalMovie), "Fortsett · 1 t 20 min igjen")

        // 2. Optimistic stop receipt preserves castMembers, ratings & tagline while advancing nextUp
        let richDetail = TvItemDetail(
            itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396), title: "Severance",
            tagline: "We're all different people.", imdbRating: 8.7, imdbVotes: 340000, rottenTomatoesScore: 97, metacriticScore: 83,
            castMembers: [TvCastMember(name: "Adam Scott", character: "Mark Scout")],
            inWatchlist: true, watched: false, selectedSeason: 1, nextUp: TvNextUpPointer(season: 1, episode: 1),
            seasons: [TvSeasonSummary(seasonNumber: 1, name: "Sesong 1", episodeCount: 2, posterUrl: nil, airDate: nil)],
            episodes: [
                TvEpisodeCard(itemId: "episode:tmdb:95396:s1:e1", seasonNumber: 1, episodeNumber: 1, title: "E1", watched: false),
                TvEpisodeCard(itemId: "episode:tmdb:95396:s1:e2", seasonNumber: 1, episodeNumber: 2, title: "E2", watched: false),
            ]
        )
        let optVM = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        optVM.detail = richDetail
        optVM.episodes = richDetail.episodes ?? []
        optVM.applyOptimisticStopReceipt(PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 900, durationSeconds: 1800, completed: false))
        XCTAssertEqual(optVM.episodes[0].progress?.positionSeconds, 900)
        XCTAssertEqual(optVM.detail?.castMembers?.count, 1)
        XCTAssertEqual(optVM.detail?.rottenTomatoesScore, 97)
        XCTAssertEqual(optVM.detail?.tagline, "We're all different people.")

        optVM.applyOptimisticStopReceipt(PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 1800, durationSeconds: 1800, completed: true))
        XCTAssertTrue(optVM.episodes[0].watched)
        XCTAssertEqual(optVM.detail?.nextUp, TvNextUpPointer(season: 1, episode: 2))

        // 3. Zero-delay async receipt wakeup, rapid same-item replay & cancelled generation task guard
        let fetches = CoreLockedBox(0)
        let secondReceiptCommitted = CoreLockedBox(false)
        let beforeJSON = #"{"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":1},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":false},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}"#
        let afterJSON = #"{"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":2},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":true},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}"#
        let s0JSON = #"{"ok":true,"item":{"itemId":"series:tmdb:100","mediaType":"series","ids":{"tmdb":100},"title":"Specials Show","inWatchlist":false,"watched":false,"selectedSeason":0,"seasons":[{"seasonNumber":0,"name":"Specials","episodeCount":1}],"episodes":[{"itemId":"episode:tmdb:100:s0:e1","seasonNumber":0,"episodeNumber":1,"title":"Pilot Special","watched":false}]}}"#

        LunaCoreMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/items/series/series:tmdb:100" {
                return (resp, Data(s0JSON.utf8))
            }
            if url.path.contains("/items/series/") {
                let n = fetches.withLock { c -> Int in c += 1; return c }
                let useAfter = (n >= 3 && secondReceiptCommitted.get())
                return (resp, Data((useAfter ? afterJSON : beforeJSON).utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = LinuxDetailSessionContext()
        context.client = LunaCoreMockURLProtocol.makeClient(host: host, scheme: "http", port: 8090)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        vm.stopReceiptTimeout = .milliseconds(300)
        await vm.handleTaskAppearance(scopeKey: vm.currentScopeKey, sessionContext: context)
        XCTAssertEqual(fetches.get(), 1)

        let req1 = PlaybackLaunchRequest(itemId: "episode:tmdb:95396:s1:e1", title: "E1", seriesTitle: "Severance", season: 1, episode: 1)
        context.activePlaybackTarget = req1
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: req1)
        context.receiptStore.record(PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 120, durationSeconds: 2800, completed: false))
        context.activePlaybackTarget = nil
        vm.handlePlaybackTargetChange(oldTarget: req1, newTarget: nil)
        context.notifyContentMutated()
        vm.handleHomeRefreshNonceChange(context.homeRefreshNonce)
        await vm.postPlaybackReloadFallbackTask?.value
        XCTAssertEqual(fetches.get(), 2, "homeRefreshNonce during postPlaybackReloadFallbackTask must not double-fetch")

        // Rapid replay ignores stale pre-launch receipt and waits for fresh receipt #2
        context.activePlaybackTarget = req1
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: req1)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 35_000_000)
            secondReceiptCommitted.set(true)
            context.receiptStore.record(PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 2800, durationSeconds: 2800, completed: true))
        }
        context.activePlaybackTarget = nil
        vm.handlePlaybackTargetChange(oldTarget: req1, newTarget: nil)
        await vm.postPlaybackReloadFallbackTask?.value
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 2))

        // Season 0 specials detail & reload preservation
        let s0VM = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:100", initialTitle: "Specials Show")
        s0VM.bind(sessionContext: context)
        await s0VM.handleTaskAppearance(scopeKey: s0VM.currentScopeKey, sessionContext: context)
        XCTAssertEqual(s0VM.selectedSeasonNumber, 0)
        let loadedS0 = try XCTUnwrap(s0VM.detail)
        XCTAssertEqual(s0VM.primaryPlayLabel(loadedS0), "Spill S0 E1")
        await s0VM.markLocalMutationAndReload()
        XCTAssertEqual(s0VM.selectedSeasonNumber, 0)

        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.handleDisappear(sessionContext: context)
        s0VM.handleDisappear(sessionContext: context)
        XCTAssertEqual(context.disappearCalls.count, 2)
    }
}
