import AetherBridge
import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import Luna

private final class TrackTestSpyPrewarmer: DetailStreamPrewarming, @unchecked Sendable {
    let state = TestLockedBox<(registered: [String], unregistered: [String])>(([], []))

    func registerStreamSecret(_ secret: String) {
        state.withLock { $0.registered.append(secret) }
    }

    func unregisterStreamSecret(_ secret: String) {
        state.withLock { $0.unregistered.append(secret) }
    }

    func prewarmIfNeeded(url: URL, httpHeaders: [String: String], byteBudget: Int) async {}
}

@MainActor
private final class AsyncCancellingReloadTransport: PlayerTransportControlling {
    var state: PlaybackState = .playing
    var playbackPhase: PlaybackPhase = .playing
    var videoRoute: VideoRoute = .software
    var currentTime: Double = 42
    var needsForegroundVideoRestore: Bool = false
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] = [
        PlaybackAudioTrackDescriptor(id: 0, name: "Japanese TrueHD", codec: "truehd", language: "jpn", channels: 8),
    ]
    var activeAudioTrackIndex: Int? = 0
    var subtitleTrackDescriptors: [SmartTrackDescriptor] = [
        SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob", isExternal: true),
    ]
    var activeSubtitleTrackIndex: Int? = 10

    var reloadCallCount: Int = 0
    var activeReloadCount: Int = 0
    var maxConcurrentReloads: Int = 0
    var lastReloadedOptions: LoadOptions?

    private var call1StartedContinuation: CheckedContinuation<Void, Never>?
    private var call1Started: Bool = false
    private var call1Continuation: CheckedContinuation<Void, Error>?
    private var call1Cancelled: Bool = false

    func play() {}
    func pause() {}
    func togglePlayPause() {}
    func seek(to seconds: Double, exact: Bool) async {}
    func setAudioDelay(_ seconds: Double) {}
    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool) {}

    func waitUntilFirstReloadStarts() async {
        if call1Started { return }
        await withCheckedContinuation { call1StartedContinuation = $0 }
    }

    private func completeCancelledFirstReloadAfterYield() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.call1Cancelled = true
            let cont = self.call1Continuation
            self.call1Continuation = nil
            cont?.resume(throwing: CancellationError())
        }
    }

    func reloadAtCurrentPosition(applying change: (inout LoadOptions) -> Void) async throws {
        var options = lastReloadedOptions ?? LoadOptions()
        change(&options)
        reloadCallCount += 1
        let callIndex = reloadCallCount
        activeReloadCount += 1
        maxConcurrentReloads = max(maxConcurrentReloads, activeReloadCount)
        defer { activeReloadCount -= 1 }

        if callIndex == 1 {
            call1Started = true
            call1StartedContinuation?.resume()
            call1StartedContinuation = nil
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    if call1Cancelled {
                        cont.resume(throwing: CancellationError())
                    } else {
                        call1Continuation = cont
                    }
                }
            } onCancel: { [weak self] in
                Task { @MainActor in self?.completeCancelledFirstReloadAfterYield() }
            }
        }
        lastReloadedOptions = options
    }
}

final class PlayerTimelineAndTrackSyncTests: XCTestCase {
    // MARK: - Scrub Commit Ordering, Paused Commit, Ring-Hold & OSD OLED Rest

    @MainActor
    func testTouchScrubCommitOrderingPausedScrubRingHoldAndOSDOledRest() async throws {
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.scrub")
        let engineScope = try SharedTestEngineScope(configured: false)
        defer {
            engineScope.stop()
            scope.cleanup()
        }
        let engine = engineScope.engine
        let comfort = ComfortPreferences(defaults: scope.defaults)

        let log = TestLockedBox<[String]>([])
        let seekGate = TestStepGate()
        let audioGate = TestStepGate()
        let transport = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        transport.onSeek = { target, _ in await seekGate.wait(label: "seek(\(Int(target)))", log: log) }
        transport.onPlay = { log.withLock { $0.append("play") } }
        let activator = MockNativeAudioActivator { _ in await audioGate.wait(label: "activate", log: log) }

        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, audioActivator: activator)
        vm.isResolving = false
        vm.durationSeconds = 3600
        vm.needsNativeAudioActivationAfterPausedRestore = true

        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 42)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task1 = vm.scrubCommitTask
        await seekGate.finish()
        await audioGate.waitUntilStarted()
        await audioGate.finish()
        await task1?.value
        XCTAssertEqual(log.withLock { $0 }, ["seek(42)_start", "seek(42)_end", "activate_start", "activate_end", "play"])
        XCTAssertFalse(vm.needsNativeAudioActivationAfterPausedRestore)

        // TogglePlayPause while seek is in flight cancels commit before play
        log.withLock { $0.removeAll() }
        await seekGate.reset(); await audioGate.reset()
        transport.state = .paused; transport.playbackPhase = .paused; transport.currentTime = 0
        vm.needsNativeAudioActivationAfterPausedRestore = true
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 15)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task2 = vm.scrubCommitTask
        vm.togglePlayPause()
        await seekGate.finish()
        await task2?.value
        XCTAssertEqual(log.withLock { $0 }, ["seek(15)_start", "seek(15)_end"])
        XCTAssertTrue(vm.needsNativeAudioActivationAfterPausedRestore)
        vm.teardownAndStop()

        // Chapter seek, paused scrub commit via Down, ring-hold fast seek & OSD OLED rest
        let seeks = TestLockedBox<[(Double, Bool)]>([])
        let t2 = MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 100)
        t2.onSeek = { pos, exact in seeks.withLock { $0.append((pos, exact)) } }
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort, transport: t2)
        vm2.isResolving = false
        vm2.hasFirstFrameReadyForDisplay = true
        vm2.playbackPhase = .playing
        vm2.durationSeconds = 3600

        vm2.coalesceRelativeSeek(delta: 30)
        vm2.seekToChapter(PlaybackChapter(id: "ch-2", index: 1, title: "Act II", startSeconds: 320, endSeconds: 480, kind: .chapter))
        XCTAssertNil(vm2.coalescedSeekTask)
        await vm2.chapterSeekTask?.value
        XCTAssertEqual(seeks.withLock { $0 }.first?.0, 320)
        XCTAssertEqual(seeks.withLock { $0 }.first?.1, true)

        t2.pause(); t2.currentTime = 120; vm2.playbackPhase = .paused
        vm2.beginTouchScrub()
        vm2.updateTouchScrub(deltaSeconds: 185)
        vm2.commitTouchScrubPaused()
        await vm2.scrubCommitTask?.value
        XCTAssertEqual(t2.state, .paused)
        XCTAssertEqual(seeks.withLock { $0 }.last?.0 ?? -1, 305, accuracy: 0.01)

        t2.state = .playing; t2.playbackPhase = .playing; vm2.playbackPhase = .playing
        vm2.beginRingHoldScrub(direction: 1)
        XCTAssertEqual(t2.state, .paused)
        vm2.updateTouchScrub(deltaSeconds: 420)
        vm2.endRingHoldScrub(cancelled: false)
        await vm2.scrubCommitTask?.value
        XCTAssertEqual(t2.state, .playing)
        XCTAssertEqual(seeks.withLock { $0 }.last?.1, false)

        let compositor = ScrubPreviewBubbleView(
            targetSeconds: 10_110, originSeconds: 5_590, chapterTitle: "Kapittel 4",
            previewImage: nil, drawsInCompositorView: true, onMountCompositorView: { _ in }
        )
        XCTAssertTrue(compositor.hasVisualFrame)
        XCTAssertEqual(compositor.preferredWidth, 284)
        XCTAssertEqual(ScrubPreviewBubbleView.compactWidth, 252)

        let osd = PlayerOSDCoordinator()
        osd.revealBottomBarAndFocusQuickActions(target: .panel(.subtitles), viewModel: vm2)
        osd.handlePlayPauseCommand(viewModel: vm2)
        vm2.playbackPhase = .paused
        XCTAssertFalse(osd.isQuickActionsModeActive)
        osd.enterPausedIdleRest()
        XCTAssertTrue(osd.isPausedOSDResting && !osd.isBottomBarShown(viewModel: vm2))
        osd.revealBottomBarTemporarily(viewModel: vm2)
        XCTAssertFalse(osd.isPausedOSDResting)

        t2.currentTime = 1840
        vm2.beginTouchScrub()
        vm2.updateTouchScrub(deltaSeconds: 920)
        var didClose = false
        osd.handleExitCommand(viewModel: vm2) { didClose = true }
        XCTAssertFalse(didClose || vm2.isScrubbing)
        XCTAssertEqual(vm2.scrubState.targetSeconds, 1840, accuracy: 0.01)

        let touchView = TouchCaptureUIView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        touchView.applyCancelHoldNonce(osd.ringHoldCancelNonce)
        XCTAssertTrue(touchView.gestureRecognizer(UIPanGestureRecognizer(), shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        vm2.teardownAndStop()
    }

    // MARK: - Server Trickplay Fallback & Negative Spindown Caching

    @MainActor
    func testServerTrickplayFallbackBucketCachingAndArchiveSpindownProtection() async throws {
        let host = "trickplay-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.v1.test.trickplay")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let jpegBytes = try PlayerTestFixtures.makeImageData(utType: "public.jpeg", width: 32, height: 18)
        let requestedBuckets = TestLockedBox<[String]>([])
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" })?.value ?? ""
            if url.path.hasSuffix("/scrub-frame") {
                requestedBuckets.withLock { $0.append(t) }
                if t == "120" {
                    return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)), Data(#"{"ok":false,"code":"scrub_frame_unavailable","error":"Mangler bilde"}"#.utf8))
                }
                if t == "240" {
                    return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)), Data(#"{"ok":false,"code":"archive_spindown_protected","error":"Arkiv"}"#.utf8))
                }
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])), jpegBytes)
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(#"{"ok":true}"#.utf8))
        }

        let transport = FakePlayerTransport(state: .paused, playbackPhase: .paused, currentTime: 100)
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: ComfortPreferences(defaults: scope.defaults),
            transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false
        )
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-tp-1", source: "infinidysk", tier: "vfs", declaredDurationSeconds: 7200
        )
        vm.isResolving = false
        vm.durationSeconds = 7200

        vm.beginTouchScrub()
        for _ in 0..<25 where vm.scrubState.previewImage == nil { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertNotNil(vm.scrubState.previewImage)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100"])

        vm.updateTouchScrub(deltaSeconds: 20)
        for _ in 0..<25 where requestedBuckets.withLock({ $0.count }) < 2 { try await Task.sleep(nanoseconds: 25_000_000) }
        try await Task.sleep(nanoseconds: 35_000_000)
        XCTAssertNil(vm.scrubState.previewImage)

        // Cached bucket 100 hits memory without re-requesting; 240 disables further archive scrub requests
        vm.updateTouchScrub(deltaSeconds: -18)
        for _ in 0..<15 where vm.scrubState.previewImage == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100", "120"])

        vm.updateTouchScrub(deltaSeconds: 138)
        for _ in 0..<25 where requestedBuckets.withLock({ $0.count }) < 3 { try await Task.sleep(nanoseconds: 25_000_000) }
        try await Task.sleep(nanoseconds: 35_000_000)
        vm.updateTouchScrub(deltaSeconds: 60)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100", "120", "240"])
        vm.cancelTouchScrub()
    }

    // MARK: - Stream Secret Ownership, Serialized Reloads & Embedded MKV Auto-Align

    @MainActor
    func testStreamSecretOwnershipDebouncedLiveReloadsAndSerializedReloadGuards() async throws {
        let host = "track-sync-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.v1.test.tracksync")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let token = "stream_secret_ownership_1234"
        let extSub = TvExternalSubtitle(id: "ext-nob-1", url: "/api/tv/v2/subtitles/sess-secret-1/0/nob.srt", format: "srt", language: "nob", name: "Norsk", isDefault: true)
        let session = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-secret-1", streamToken: token, canClientPrewarmBytes: false,
            tracks: TvSessionTracks(externalSubtitles: [extSub]),
            preferDualLayerDolbyVision: true, foldsDolbyVisionFEL: true
        )
        let prepRespData = try JSONEncoder().encode(TvPrepareResponse(ok: true, prepareToken: "prep-secret-1", playbackSession: session))
        let resRespData = try JSONEncoder().encode(TvResolveStartResponse(ok: true, resolveId: "res-secret-1", playbackSession: session))

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/prepare" { return (resp, prepRespData) }
            if url.path == "/api/tv/v2/playback/resolve" { return (resp, resRespData) }
            if url.path.hasSuffix("/subtitles/auto-align") {
                return (resp, Data(#"{"ok":true,"sessionId":"sess-secret-1","applied":true,"mode":"reference_srt","offsetMs":-150,"subtitleDelayMs":-150,"subtitle":{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-secret-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk","isDefault":true}}"#.utf8))
            }
            return (resp, Data(#"{"ok":true,"sessionId":"sess-secret-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-2","url":"/api/tv/v2/subtitles/sess-secret-1/1/nob.srt","format":"srt","language":"nob","name":"Norsk (Ny)"},"subtitleDelayMs":0}"#.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)
        let spyPrewarmer = TrackTestSpyPrewarmer()
        let preResolve = DetailPreResolveController(prewarmer: spyPrewarmer)
        preResolve.schedule(targetItemId: session.item.itemId, title: session.item.title, seriesTitle: nil, startPos: 0, immediate: true, client: client)
        for _ in 0..<50 where !preResolve.isPreResolvedReady { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(spyPrewarmer.state.withLock { $0.registered }, [token])

        let handoff = preResolve.consumeHandoffForPlayback(itemId: session.item.itemId, startPosition: 0, client: client)
        XCTAssertTrue(handoff.preparedStreamSecretRegistered)

        let comfort = ComfortPreferences(defaults: scope.defaults)
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software)
        transport.subtitleTrackDescriptors = [SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob", isExternal: true)]
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: scope.suiteName), bindOnInit: false
        )
        vm.sessionController.start(
            request: PlaybackLaunchRequest(
                itemId: session.item.itemId, title: session.item.title, startPositionSeconds: 0,
                prepareToken: handoff.prepareToken, preparedSession: handoff.preparedSession,
                preparedStreamSecretRegistered: handoff.preparedStreamSecretRegistered
            ),
            client: client
        )
        await vm.sessionController.resolveTask?.value
        XCTAssertEqual(vm.sessionController.registeredStreamToken, token)

        // Rapid live toggles coalesce into 1 reload preserving externalSubtitles; HDR10 reload error rolls back dualLayerOverride
        vm.trackController.activeSubtitleTrackIndex = 10
        vm.trackController.setMetalFXModeLive(.off)
        vm.trackController.setFullHDUpscaleLive(true)
        vm.trackController.setSpeakerLayoutLive(.atmos512)
        try? await Task.sleep(nanoseconds: 240_000_000)
        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(transport.lastReloadedOptions?.upscaleScaler, .lanczos)
        XCTAssertEqual(transport.lastReloadedOptions?.objectAudioRendering, .render(.l512))
        XCTAssertEqual(transport.lastReloadedOptions?.externalSubtitles.count, 1)

        comfort.dualLayerOverride = .auto
        vm.videoFormat = .dolbyVision
        vm.qosReporter.sourceDVProfile = 7
        vm.qosReporter.recordDolbyVisionTelemetrySample(droppedFrameCount: 30)
        transport.onReloadAtCurrentPosition = { _ in throw LunaCoreError.serverMessage(500, "Reload feilet") }
        await vm.trackController.performSwitchToHDR10BaseLayer()
        XCTAssertEqual(comfort.dualLayerOverride, .auto)
        XCTAssertEqual(vm.qosReporter.transientBannerMessage, "Reload feilet")

        vm.sessionController.teardownAndStop()
        XCTAssertNil(vm.sessionController.registeredStreamToken)

        // Serialized async reloads: searchAndAttach superseded by autoAlign never deadlocks or overlaps
        let serialTransport = AsyncCancellingReloadTransport()
        let serialVM = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: serialTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: scope.suiteName), bindOnInit: false
        )
        serialVM.activeClient = client; serialVM.activeSession = session; serialVM.isResolving = false
        serialVM.trackController.activeAudioTrackIndex = 0; serialVM.trackController.activeSubtitleTrackIndex = 10
        serialVM.trackController.searchAndAttachSubtitles()
        await serialTransport.waitUntilFirstReloadStarts()
        serialVM.trackController.autoAlignActiveSubtitle()
        await serialVM.trackController.subtitleActionTask?.value
        XCTAssertEqual(serialTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(serialVM.trackController.subtitleDelayMs, -150)
        XCTAssertFalse(serialVM.trackController.isSearchingSubtitles || serialVM.trackController.isAutoAligningSubtitles)
    }

    @MainActor
    func testEmbeddedMKVSubtitleAutoAlignAndBitmapErrorMapping() async throws {
        let host = "embalign-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.v1.test.embalign")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let capturedBodies = TestLockedBox<[Data]>([])
        let modeBox = TestLockedBox("success")
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            if url.path.hasSuffix("/subtitles/auto-align") {
                capturedBodies.withLock { $0.append(MockURLProtocol.bodyData(for: req)) }
                switch modeBox.withLock({ $0 }) {
                case "bitmap":
                    return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil)), Data(#"{"ok":false,"code":"bitmap_subtitle_not_supported","error":"Bitmap"}"#.utf8))
                case "unaligned":
                    return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(#"{"ok":true,"sessionId":"sess-emb-1","applied":false,"appliedToFile":false,"reason":"invalid_extracted_srt"}"#.utf8))
                default:
                    return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(#"{"ok":true,"sessionId":"sess-emb-1","applied":true,"appliedToFile":false,"mode":"embedded_ffmpeg_silencedetect","offsetMs":950,"subtitleDelayMs":950,"embeddedTrack":{"streamIndex":2,"codec":"subrip","language":"nob"}}"#.utf8))
                }
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), Data(#"{"ok":true}"#.utf8))
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing)
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 0, name: "Norsk (MKV)", codec: "subrip", language: "nob", isExternal: false),
            SmartTrackDescriptor(id: 1, name: "English PGS", codec: "hdmv_pgs_subtitle", language: "eng", isExternal: false),
        ]
        transport.activeSubtitleTrackIndex = 0

        let prefStore = PlaybackPreferenceStore(suiteName: scope.suiteName)
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: ComfortPreferences(defaults: scope.defaults), transport: transport,
            audioActivator: MockNativeAudioActivator { _ in }, preferenceStore: prefStore, bindOnInit: false
        )
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-emb-1", candidateId: "cand-vfs-1", source: "infinidysk", tier: "vfs",
            tracks: TvSessionTracks(embeddedSubtitles: [
                TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "subrip", language: "nob", displayTitle: "Norsk (MKV)"),
                TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "hdmv_pgs_subtitle", language: "eng", displayTitle: "English PGS"),
            ])
        )
        vm.trackController.activeSubtitleTrackIndex = 0

        let aligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertTrue(aligned)
        XCTAssertEqual(transport.reloadCallCount, 0)
        XCTAssertEqual(vm.subtitleDelayMs, 950)
        XCTAssertEqual(prefStore.subtitleDelayMs(forCandidateId: "cand-vfs-1"), 950)
        let body0 = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(capturedBodies.withLock { $0.first })) as? [String: Any])
        XCTAssertNil(body0["subtitleId"])
        XCTAssertEqual(body0["trackIndex"] as? Int, 2)
        XCTAssertEqual(body0["applyToFile"] as? Bool, false)

        modeBox.withLock { $0 = "unaligned" }
        let unaligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(unaligned)
        XCTAssertEqual(vm.trackController.subtitleActionStatusMessage, "Kunne ikke lese innebygd undertekst")

        modeBox.withLock { $0 = "bitmap" }
        vm.trackController.activeSubtitleTrackIndex = 1
        let bitmap = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(bitmap)
        XCTAssertEqual(vm.trackController.subtitleActionStatusMessage, "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk")
    }
}
