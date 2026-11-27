import AetherBridge
import Foundation
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
                Task { @MainActor in
                    self?.completeCancelledFirstReloadAfterYield()
                }
            }
        }
        lastReloadedOptions = options
    }
}

final class PlayerTrackReloadAndSecretTests: XCTestCase {
    @MainActor
    private func makeLoadedPlayerVM(
        host: String,
        suite: String
    ) throws -> (PlayerViewModel, MockPlayerTransport, ComfortPreferences, AetherEngine, TvPlaybackSession, LunaCoreClient) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let comfort = ComfortPreferences(defaults: defaults)
        let prefStore = PlaybackPreferenceStore(suiteName: suite)
        let engine = try LunaApp.makeSharedEngine()
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software)
        transport.audioTrackDescriptors = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Japanese TrueHD", codec: "truehd", language: "jpn", channels: 8),
        ]
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob", isExternal: true),
        ]
        let sessionJSON = #"""
        {
          "sessionId": "sess-reload-test-1",
          "streamToken": "stream_secret_reload_1234",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:129",
            "mediaType": "movie",
            "ids": { "tmdb": 129 },
            "title": "Spirited Away",
            "originalLanguage": "ja"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K DV P7 FEL",
            "releaseTitle": "Spirited.Away.2160p",
            "source": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/sess-reload-test-1/stream_secret_reload_1234/video.mkv" },
          "tracks": {
            "externalSubtitles": [
              {
                "id": "ext-nob-1",
                "url": "/api/tv/v2/subtitles/sess-reload-test-1/0/nob.srt",
                "format": "srt",
                "language": "nob",
                "name": "Norsk",
                "isDefault": true
              }
            ]
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "foldsDolbyVisionFEL": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        let client = try MockURLProtocol.makeClient(host: host)
        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: prefStore,
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10
        return (vm, transport, comfort, engine, session, client)
    }

    @MainActor
    func testAutoAlignSubtitleReloadFailureAndCancellationSurfaceExpectedStatus() async throws {
        let host = "track-align-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.align.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/subtitles/auto-align") {
                let body = #"""
                {
                  "ok": true,
                  "sessionId": "sess-reload-test-1",
                  "applied": true,
                  "mode": "reference_srt",
                  "offsetMs": -120,
                  "subtitleDelayMs": -120,
                  "subtitle": {
                    "id": "ext-nob-1",
                    "url": "/api/tv/v2/subtitles/sess-reload-test-1/0/nob.srt",
                    "format": "srt",
                    "language": "nob",
                    "name": "Norsk",
                    "isDefault": true
                  }
                }
                """#
                return (resp, Data(body.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let (vm, transport, _, engine, _, _) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        transport.onReloadAtCurrentPosition = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let failedOk = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(failedOk)
        XCTAssertEqual(
            vm.trackController.subtitleActionStatusMessage,
            LunaCopy.friendlyErrorMessage(URLError(.cannotConnectToHost), fallback: LunaCopy.subtitlesAlignFailedStatus)
        )
        XCTAssertFalse((vm.trackController.subtitleActionStatusMessage ?? "").contains(LunaCopy.subtitlesAlignedStatus))

        transport.onReloadAtCurrentPosition = { _ in
            throw CancellationError()
        }
        let cancelledOk = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(cancelledOk)
        XCTAssertNil(vm.trackController.subtitleActionStatusMessage)
    }

    @MainActor
    func testHDR10SwitchAndLiveOptionsReloadErrorRestoreAndBannerBehavior() async throws {
        let host = "track-hdr-live-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.hdr.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let (vm, transport, comfort, engine, _, _) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        comfort.dualLayerOverride = .auto
        vm.videoFormat = .dolbyVision
        vm.qosReporter.sourceDVProfile = 7
        vm.qosReporter.recordDolbyVisionTelemetrySample(droppedFrameCount: 30)
        XCTAssertTrue(vm.suggestsHDR10BaseLayer)

        transport.onReloadAtCurrentPosition = { _ in
            throw LunaCoreError.serverMessage(500, "Reload feilet")
        }
        await vm.trackController.performSwitchToHDR10BaseLayer()
        XCTAssertEqual(comfort.dualLayerOverride, .auto)
        XCTAssertTrue(vm.suggestsHDR10BaseLayer)
        XCTAssertEqual(vm.qosReporter.transientBannerMessage, "Reload feilet")

        vm.qosReporter.transientBannerMessage = nil
        transport.onReloadAtCurrentPosition = { _ in
            throw CancellationError()
        }
        await vm.trackController.performSwitchToHDR10BaseLayer()
        XCTAssertEqual(comfort.dualLayerOverride, .auto)
        XCTAssertNil(vm.qosReporter.transientBannerMessage)

        transport.onReloadAtCurrentPosition = { _ in
            throw URLError(.timedOut)
        }
        await vm.trackController.performLiveEngineOptionsReload()
        XCTAssertEqual(
            vm.qosReporter.transientBannerMessage,
            LunaCopy.friendlyErrorMessage(URLError(.timedOut), fallback: "Kunne ikke oppdatere avspillingsinnstillinger.")
        )

        vm.qosReporter.transientBannerMessage = nil
        transport.onReloadAtCurrentPosition = { _ in
            throw CancellationError()
        }
        await vm.trackController.performLiveEngineOptionsReload()
        XCTAssertNil(vm.qosReporter.transientBannerMessage)
    }

    @MainActor
    func testWarmStartStreamSecretOwnershipRegistersOnceAndUnregistersSymmetrically() async throws {
        let host = "secret-ownership-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.secret.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let token = "stream_secret_ownership_1234"
        let sessionJSON = #"""
        {
          "sessionId": "sess-secret-1",
          "streamToken": "stream_secret_ownership_1234",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Fight Club"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10",
            "releaseTitle": "Fight.Club.2160p",
            "source": "nvme"
          },
          "stream": {
            "url": "/api/tv/v2/stream/sess-secret-1/stream_secret_ownership_1234/film.mkv",
            "canClientPrewarmBytes": false
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let prepareJSON = #"{"ok":true,"prepareToken":"prep-secret-1","playbackSession":\#(sessionJSON)}"#
        let resolveJSON = #"{"ok":true,"resolveId":"res-secret-1","playbackSession":\#(sessionJSON)}"#

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/prepare" {
                return (resp, Data(prepareJSON.utf8))
            }
            if url.path == "/api/tv/v2/playback/resolve" {
                return (resp, Data(resolveJSON.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)
        let spyPrewarmer = TrackTestSpyPrewarmer()
        let preResolve = DetailPreResolveController(prewarmer: spyPrewarmer)
        preResolve.schedule(
            targetItemId: "movie:tmdb:550",
            title: "Fight Club",
            seriesTitle: nil,
            startPos: 0,
            immediate: true,
            client: client
        )
        for _ in 0..<50 where !preResolve.isPreResolvedReady {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(preResolve.isPreResolvedReady)
        XCTAssertEqual(spyPrewarmer.state.withLock { $0.registered }, [token])

        let handoff = preResolve.consumeHandoffForPlayback(itemId: "movie:tmdb:550", startPosition: 0, client: client)
        XCTAssertTrue(handoff.preparedStreamSecretRegistered)
        XCTAssertTrue(spyPrewarmer.state.withLock { $0.unregistered }.isEmpty)

        let (vm, _, _, engine, _, _) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let req = PlaybackLaunchRequest(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            startPositionSeconds: 0,
            prepareToken: handoff.prepareToken,
            preparedSession: handoff.preparedSession,
            preparedStreamSecretRegistered: handoff.preparedStreamSecretRegistered
        )
        vm.sessionController.start(request: req, client: client)
        XCTAssertEqual(vm.sessionController.registeredStreamToken, token)
        await vm.sessionController.resolveTask?.value
        XCTAssertEqual(vm.sessionController.registeredStreamToken, token)

        vm.sessionController.teardownAndStop()
        XCTAssertNil(vm.sessionController.registeredStreamToken)

        // Short token (< 8 chars) is never recorded in registeredStreamToken
        let shortSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Data(sessionJSON.replacingOccurrences(of: token, with: "short").utf8)
        )
        let (vm2, _, _, engine2, _, _) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine2.stop(resetDisplayCriteria: true)
        }
        try await vm2.sessionController.mountSessionInEngine(
            shortSession,
            client: client,
            overrideStartPosition: 0,
            autoplay: true
        )
        XCTAssertNil(vm2.sessionController.registeredStreamToken)
    }

    @MainActor
    func testLiveUpscaleAndSpeakerTogglesCoalesceRapidTapsAndSkipNoOps() async throws {
        let host = "track-debounce-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.debounce.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let (vm, transport, comfort, engine, _, _) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        // Unchanged toggles must not schedule reload
        let initialFullHD = comfort.upscalesFullHDVideo
        let initialMetalFX = comfort.lowResUpscaleMode
        let initialSpeaker = comfort.speakerLayoutOverride
        vm.trackController.setFullHDUpscaleLive(initialFullHD)
        vm.trackController.setMetalFXModeLive(initialMetalFX)
        vm.trackController.setSpeakerLayoutLive(initialSpeaker)
        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertEqual(transport.reloadCallCount, 0)

        // Rapid consecutive toggles coalesce into 1 reload after 150 ms
        vm.trackController.setMetalFXModeLive(.off)
        vm.trackController.setFullHDUpscaleLive(true)
        vm.trackController.setSpeakerLayoutLive(.atmos512)
        XCTAssertEqual(transport.reloadCallCount, 0, "Debounce must wait ~150 ms before reloading")
        try? await Task.sleep(nanoseconds: 240_000_000)
        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(transport.lastReloadedOptions?.upscaleScaler, .lanczos)
        XCTAssertEqual(transport.lastReloadedOptions?.upscalesFullHDVideo, true)
        XCTAssertEqual(transport.lastReloadedOptions?.objectAudioRendering, .render(.l512))
        XCTAssertEqual(engine.maximumSubtitleAdvanceSeconds, 0)
        XCTAssertEqual(engine.maximumSubtitleDelaySeconds, 10)

        // Teardown cancels pending debounced reload
        vm.trackController.setFullHDUpscaleLive(false)
        vm.teardownAndStop()
        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertEqual(transport.reloadCallCount, 1)
    }

    @MainActor
    func testDoubleTapSwitchToHDR10BaseLayerPreservesForceOffAndSerializesReloads() async throws {
        let host = "track-hdr-doubletap-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.hdr.doubletap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let (_, _, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let asyncTransport = AsyncCancellingReloadTransport()
        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: asyncTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite),
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10

        comfort.dualLayerOverride = .auto
        vm.trackController.switchToHDR10BaseLayer()
        await asyncTransport.waitUntilFirstReloadStarts()

        // Second tap cancels the in-flight reload while it settles cancellation asynchronously
        vm.trackController.switchToHDR10BaseLayer()
        await vm.trackController.hdrBaseLayerSwitchTask?.value

        XCTAssertEqual(comfort.dualLayerOverride, .forceOff)
        XCTAssertEqual(asyncTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(asyncTransport.reloadCallCount, 2)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.preferDualLayerDolbyVision, false)
        XCTAssertNil(vm.trackController.hdrBaseLayerSwitchTask)
        XCTAssertNil(vm.trackController.hdrBaseLayerPreSwitchOverride)
    }

    @MainActor
    func testSwitchToHDR10BaseLayerFollowedByFullHDUpscaleLiveSerializesReloadsAndPreservesForceOff() async throws {
        let host = "track-hdr-upscale-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.hdr.upscale.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let (_, _, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let asyncTransport = AsyncCancellingReloadTransport()
        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: asyncTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite),
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10

        comfort.dualLayerOverride = .auto
        comfort.upscalesFullHDVideo = true

        vm.trackController.switchToHDR10BaseLayer()
        await asyncTransport.waitUntilFirstReloadStarts()

        vm.trackController.setFullHDUpscaleLive(false)
        await vm.trackController.upscaleReloadTask?.value

        XCTAssertEqual(comfort.dualLayerOverride, .forceOff)
        XCTAssertFalse(comfort.upscalesFullHDVideo)
        XCTAssertEqual(asyncTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.preferDualLayerDolbyVision, false)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.upscalesFullHDVideo, false)
        XCTAssertNil(vm.trackController.hdrBaseLayerSwitchTask)
        XCTAssertNil(vm.trackController.upscaleReloadTask)
    }

    @MainActor
    func testLiveEngineOptionsReloadPreservesExternalSubtitles() async throws {
        let host = "track-live-extsubs-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.live.extsubs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let (vm, transport, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        comfort.upscalesFullHDVideo = true
        await vm.trackController.performLiveEngineOptionsReload()
        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(transport.lastReloadedOptions?.externalSubtitles.count, 1)
        XCTAssertEqual(PlayerEngineConfigurator.externalSubtitleTracks(for: session, client: client).count, 1)
        let activeExternalSubtitles = try XCTUnwrap(vm.sessionController.activeSession?.tracks?.externalSubtitles)
        XCTAssertEqual(activeExternalSubtitles.count, 1)
        XCTAssertEqual(activeExternalSubtitles.first?.url, "/api/tv/v2/subtitles/sess-reload-test-1/0/nob.srt")
        XCTAssertEqual(activeExternalSubtitles.first?.name, "Norsk")
        XCTAssertEqual(activeExternalSubtitles.first?.language, "nob")
    }

    @MainActor
    func testSearchAndAttachSubtitlesFollowedByFullHDUpscaleLiveSerializesReloadsAndPreservesExternalSubtitles() async throws {
        let host = "track-sub-upscale-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.sub.upscale.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let body = #"{"ok":true,"sessionId":"sess-reload-test-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-2","url":"/api/tv/v2/subtitles/sess-reload-test-1/1/nob.srt","format":"srt","language":"nob","name":"Norsk (Ny)"},"subtitleDelayMs":0}"#
            return (resp, Data(body.utf8))
        }

        let (_, _, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let asyncTransport = AsyncCancellingReloadTransport()
        let vm = PlayerViewModel(
            engine: engine, comfort: comfort, transport: asyncTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite), bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10
        comfort.upscalesFullHDVideo = true

        vm.trackController.searchAndAttachSubtitles()
        await asyncTransport.waitUntilFirstReloadStarts()

        vm.trackController.setFullHDUpscaleLive(false)
        await vm.trackController.upscaleReloadTask?.value

        XCTAssertEqual(asyncTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(asyncTransport.reloadCallCount, 2)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.upscalesFullHDVideo, false)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.externalSubtitles.count, 2)
        XCTAssertTrue(
            vm.sessionController.activeSession?.tracks?.externalSubtitles?.contains(where: {
                $0.url.hasSuffix("/1/nob.srt") && $0.name == "Norsk (Ny)" && $0.language == "nob"
            }) == true
        )
        XCTAssertFalse(vm.trackController.isSearchingSubtitles)
        XCTAssertNil(vm.trackController.subtitleActionTask)
        XCTAssertNil(vm.trackController.upscaleReloadTask)
    }

    @MainActor
    func testSwitchToHDR10BaseLayerFollowedBySearchAndAttachSubtitlesSerializesReloadsAndPreservesForceOff() async throws {
        let host = "track-hdr-sub-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.hdr.sub.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let body = #"{"ok":true,"sessionId":"sess-reload-test-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-2","url":"/api/tv/v2/subtitles/sess-reload-test-1/1/nob.srt","format":"srt","language":"nob","name":"Norsk (Ny)"},"subtitleDelayMs":0}"#
            return (resp, Data(body.utf8))
        }

        let (_, _, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let asyncTransport = AsyncCancellingReloadTransport()
        let vm = PlayerViewModel(
            engine: engine, comfort: comfort, transport: asyncTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite), bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10
        comfort.dualLayerOverride = .auto

        vm.trackController.switchToHDR10BaseLayer()
        await asyncTransport.waitUntilFirstReloadStarts()

        vm.trackController.searchAndAttachSubtitles()
        await vm.trackController.subtitleActionTask?.value

        XCTAssertEqual(asyncTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(asyncTransport.reloadCallCount, 2)
        XCTAssertEqual(comfort.dualLayerOverride, .forceOff)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertEqual(asyncTransport.lastReloadedOptions?.preferDualLayerDolbyVision, false)
        XCTAssertGreaterThanOrEqual(asyncTransport.lastReloadedOptions?.externalSubtitles.count ?? 0, 1)
        XCTAssertNil(vm.trackController.hdrBaseLayerSwitchTask)
        XCTAssertNil(vm.trackController.subtitleActionTask)
    }

    @MainActor
    func testSearchAndAttachSubtitlesSupersededByAutoAlignCompletesSequentiallyWithoutBusyFlagDeadlock() async throws {
        let host = "track-sub-align-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.sub.align.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/subtitles/auto-align") {
                let body = #"{"ok":true,"sessionId":"sess-reload-test-1","applied":true,"mode":"reference_srt","offsetMs":-150,"subtitleDelayMs":-150,"subtitle":{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-reload-test-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk","isDefault":true}}"#
                return (resp, Data(body.utf8))
            }
            let body = #"{"ok":true,"sessionId":"sess-reload-test-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-2","url":"/api/tv/v2/subtitles/sess-reload-test-1/1/nob.srt","format":"srt","language":"nob","name":"Norsk (Ny)"},"subtitleDelayMs":0}"#
            return (resp, Data(body.utf8))
        }

        let (_, _, comfort, engine, session, client) = try makeLoadedPlayerVM(host: host, suite: suite)
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let asyncTransport = AsyncCancellingReloadTransport()
        let vm = PlayerViewModel(
            engine: engine, comfort: comfort, transport: asyncTransport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite), bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.trackController.activeAudioTrackIndex = 0
        vm.trackController.activeSubtitleTrackIndex = 10

        vm.trackController.searchAndAttachSubtitles()
        await asyncTransport.waitUntilFirstReloadStarts()

        vm.trackController.autoAlignActiveSubtitle()
        await vm.trackController.subtitleActionTask?.value

        XCTAssertEqual(asyncTransport.maxConcurrentReloads, 1)
        XCTAssertEqual(asyncTransport.reloadCallCount, 2)
        XCTAssertEqual(vm.trackController.subtitleDelayMs, -150)
        XCTAssertFalse(vm.trackController.isSearchingSubtitles)
        XCTAssertFalse(vm.trackController.isAutoAligningSubtitles)
        XCTAssertNil(vm.trackController.subtitleActionTask)
        XCTAssertTrue((vm.trackController.subtitleActionStatusMessage ?? "").contains(LunaCopy.subtitlesAlignedStatus))
    }
}
