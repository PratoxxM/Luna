import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class DetailMockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host.lowercased()] = handler }
    }

    static func unregister(host: String) {
        _ = handlers.withLock { $0.removeValue(forKey: host.lowercased()) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeClient(host: String) -> LunaCoreClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DetailMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LunaCoreClient(
            baseURL: URL(string: "http://\(host):8090")!,
            deviceID: "luna-detail-linux-test",
            deviceToken: "tok-detail-linux",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true,
            session: session,
            imageSession: session,
            externalImageSession: session
        )
    }
}

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
    var activePlaybackTarget: PlaybackLaunchRequest? = nil
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
            item: TvPlaybackItemContext(
                itemId: itemId,
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 550),
                title: title,
                seriesTitle: seriesTitle
            ),
            selectedCandidate: candidate,
            stream: TvStreamEndpoint(url: "/api/tv/v2/streams/sess-fallback-1/master", supportsByteRanges: true, canClientPrewarmBytes: true),
            aetherConfig: TvAetherConfig(preferDualLayerDolbyVision: true, dolbyVisionHandling: "fel", matchContentEnabled: true, audioBridgeMode: "objectAudio")
        )
        return TvPrepareResponse(ok: true, prepareToken: "prep-fallback-1", playbackSession: session)
    }

    func cancelInflightPlayback(sessionId: String?, resolveId: String?, itemId: String?, prepareToken: String?) async throws {}

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        TvAlternativesResponse(ok: true, sessionId: sessionId, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", activeCandidateId: "cand-1", alternatives: [candidate])
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

final class DetailAndSourcePickerViewModelTests: XCTestCase {
    @MainActor
    func testMediaDetailZeroDelayStopReceiptAsyncWakeupAndTimeoutFallback() async throws {
        let host = "detail-linux-\(UUID().uuidString.lowercased()).local"
        defer {
            DetailMockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let fetches = Mutex(0)
        let beforeJSON = #"""
        {"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":1},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":false},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}
        """#
        let afterJSON = #"""
        {"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":2},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":true},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}
        """#

        DetailMockURLProtocol.register(host: host) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path.contains("/items/series/") {
                let n = fetches.withLock { c -> Int in c += 1; return c }
                return (resp, Data((n == 1 ? beforeJSON : afterJSON).utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = LinuxDetailSessionContext()
        context.client = DetailMockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        vm.stopReceiptTimeout = .milliseconds(80)
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 1))

        let launched = PlaybackLaunchRequest(itemId: "episode:tmdb:95396:s1:e1", title: "E1", seriesTitle: "Severance", season: 1, episode: 1)
        context.activePlaybackTarget = launched
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: launched)

        // Fire receipt asynchronously mid-wait with episode itemId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)
            context.receiptStore.record(
                PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 2800, durationSeconds: 2800, completed: true)
            )
        }
        context.activePlaybackTarget = nil
        let start = Date()
        vm.handlePlaybackTargetChange(oldTarget: launched, newTarget: nil)
        await vm.postPlaybackReloadFallbackTask?.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.6)
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 2))

        // Allow background pre-resolve URLSession task to settle before handleDisappear
        // so Linux FoundationNetworking URLSessionTask.cancel() doesn't race workQueue.sync.
        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.handleDisappear(sessionContext: context)
        XCTAssertEqual(context.disappearCalls.count, 1)
    }

    @MainActor
    func testDetailPreResolveControllerPrewarmPolicyAndSourcePickerFallback() async throws {
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: false, loadedScopeKey: nil, currentScopeKey: "a", lastSeenRefreshNonce: 1, currentRefreshNonce: 1),
            .loadInitial
        )
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: true, loadedScopeKey: "a", currentScopeKey: "a", lastSeenRefreshNonce: 1, currentRefreshNonce: 2),
            .reloadPreservingSeason
        )
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(hasLoadedDetail: true, loadedScopeKey: "a", currentScopeKey: "a", lastSeenRefreshNonce: 2, currentRefreshNonce: 2),
            .skip
        )

        let spy = SpyDetailPrewarmer()
        let controller = DetailPreResolveController(prewarmer: spy)
        controller.discardPreparedSession(client: nil)
        XCTAssertFalse(controller.isPreResolvedReady)

        // SourcePickerViewModel fast path + adoptInflightDefaultSentinel + 404 fallback + orphan stop
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
    }

    @MainActor
    func testMediaDetailRapidSameItemReplayIgnoresStalePreLaunchStopReceipt() async throws {
        let host = "detail-replay-\(UUID().uuidString.lowercased()).local"
        defer {
            DetailMockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let fetches = Mutex(0)
        let beforeJSON = #"""
        {"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":1},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":false},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}
        """#
        let afterJSON = #"""
        {"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":2},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":true},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}
        """#

        let secondReceiptCommitted = Mutex(false)
        let fetchCountWhenReplayReloaded = Mutex<Bool?>(nil)

        DetailMockURLProtocol.register(host: host) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path.contains("/items/series/") {
                let n = fetches.withLock { c -> Int in c += 1; return c }
                if n == 3 {
                    let committed = secondReceiptCommitted.withLock { $0 }
                    fetchCountWhenReplayReloaded.withLock { $0 = committed }
                    return (resp, Data((committed ? afterJSON : beforeJSON).utf8))
                }
                return (resp, Data(beforeJSON.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = LinuxDetailSessionContext()
        context.client = DetailMockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        vm.stopReceiptTimeout = .milliseconds(400)
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 1))

        let launched = PlaybackLaunchRequest(itemId: "episode:tmdb:95396:s1:e1", title: "E1", seriesTitle: "Severance", season: 1, episode: 1)

        // Session 1 records incomplete stop receipt
        context.activePlaybackTarget = launched
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: launched)
        context.receiptStore.record(
            PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 120, durationSeconds: 2800, completed: false)
        )
        context.activePlaybackTarget = nil
        vm.handlePlaybackTargetChange(oldTarget: launched, newTarget: nil)
        await vm.postPlaybackReloadFallbackTask?.value
        XCTAssertEqual(fetches.withLock { $0 }, 2)

        // Rapid < 5s Session 2 replay of the SAME item where activePlaybackTarget = nil precedes receipt #2
        context.activePlaybackTarget = launched
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: launched)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000)
            secondReceiptCommitted.withLock { $0 = true }
            context.receiptStore.record(
                PlaybackStopReceipt(itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode", seasonNumber: 1, episodeNumber: 1, positionSeconds: 2800, durationSeconds: 2800, completed: true)
            )
        }
        context.activePlaybackTarget = nil
        vm.handlePlaybackTargetChange(oldTarget: launched, newTarget: nil)
        await vm.postPlaybackReloadFallbackTask?.value

        XCTAssertEqual(fetchCountWhenReplayReloaded.withLock { $0 }, true)
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 2))
    }
}
