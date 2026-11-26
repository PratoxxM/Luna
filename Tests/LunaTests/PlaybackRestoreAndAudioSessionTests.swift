import AetherBridge
import AVFoundation
import Foundation
import XCTest
@testable import Luna

final class PlaybackRestoreAndAudioSessionTests: XCTestCase {
    func testForegroundRestoreDecisionAndTransportIntentPreservation() {
        XCTAssertTrue(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: false,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: false,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: true,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: true,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: true
            )
        )

        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .playing, engineState: .playing))
        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .rebuffering, engineState: .playing))
        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .loading, engineState: .playing))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .loading, engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .seeking, engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .stalled(reconnecting: true), engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .paused, engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .ended, engineState: .ended))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .error("x"), engineState: .error("x")))

        XCTAssertFalse(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: false, userOverride: nil))
        XCTAssertTrue(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: true, userOverride: nil))
        XCTAssertTrue(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: false, userOverride: true))
        XCTAssertFalse(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: true, userOverride: false))
    }

    @MainActor
    func testBuildLoadOptionsForwardsAutoplayFlag() throws {
        let suite = "luna.test.loadoptions.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = #"""
        {
          "sessionId": "sess-autoplay-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "tmdb:movie:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K DV FEL",
            "releaseTitle": "Eksempelfilm.2024.2160p.REMUX",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": {
            "url": "/api/tv/v2/streams/sess-autoplay-1/master"
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#

        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(json.utf8))
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true
        )
        let comfort = ComfortPreferences(defaults: defaults)

        let defaultOptions = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0
        )
        XCTAssertTrue(defaultOptions.autoplay)

        let pausedOptions = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            autoplay: false
        )
        XCTAssertFalse(pausedOptions.autoplay)
    }

    func testForegroundRestoreNativeAudioActivationPredicate() {
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: false, videoRoute: .loopback))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: false, videoRoute: .remoteBypass))
        XCTAssertTrue(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .loopback))
        XCTAssertTrue(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .remoteBypass))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .software))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .audio))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .none))
        XCTAssertTrue(PlayerViewModel.shouldActivateNativeAudioBeforePlayOnResume(wasPlaying: false, needsNativeAudioActivationAfterPausedRestore: true))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioBeforePlayOnResume(wasPlaying: true, needsNativeAudioActivationAfterPausedRestore: true))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioBeforePlayOnResume(wasPlaying: false, needsNativeAudioActivationAfterPausedRestore: false))
    }

    @MainActor
    func testPausedRestoreResumeActivatesNativeAudioBeforePlayAndGuardsCancellation() async throws {
        let suite = "luna.test.resumepaused.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let log = TestLockedBox<[String]>([])
        let gate = TestStepGate()
        let transport = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        transport.onPlay = { log.withLock { $0.append("play") } }
        let activator = MockNativeAudioActivator { _ in
            await gate.wait(label: "activate", log: log)
        }

        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: activator
        )
        vm.isResolving = false

        // 1. Happy path: off-main activation finishes strictly before play runs
        vm.needsNativeAudioActivationAfterPausedRestore = true
        vm.togglePlayPause()
        await gate.waitUntilStarted()
        XCTAssertEqual(log.withLock { $0 }, ["activate_start"])
        let task1 = vm.pausedRestoreResumeTask
        XCTAssertNotNil(task1)
        await gate.finish()
        await task1?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end", "play"])
        XCTAssertFalse(vm.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertNil(vm.pausedRestoreResumeTask)

        // 2. Second togglePlayPause while activation is in flight cancels resume before play
        log.withLock { $0.removeAll() }
        await gate.reset()
        transport.state = .paused
        transport.playbackPhase = .paused
        vm.needsNativeAudioActivationAfterPausedRestore = true
        vm.togglePlayPause()
        await gate.waitUntilStarted()
        let task2 = vm.pausedRestoreResumeTask
        vm.togglePlayPause()
        XCTAssertNil(vm.pausedRestoreResumeTask)
        XCTAssertFalse(vm.lastForegroundPlaybackWasPlaying)
        await gate.finish()
        await task2?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end"])
        XCTAssertTrue(vm.needsNativeAudioActivationAfterPausedRestore)

        // 3. Backgrounding while activation is in flight prevents delayed play
        log.withLock { $0.removeAll() }
        await gate.reset()
        vm.togglePlayPause()
        await gate.waitUntilStarted()
        let task3 = vm.pausedRestoreResumeTask
        vm.handleScenePhaseChange(.background)
        await gate.finish()
        await task3?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end"])
        XCTAssertNil(vm.pausedRestoreResumeTask)

        // 4. Fatal error while activation is in flight blocks play
        log.withLock { $0.removeAll() }
        await gate.reset()
        vm.handleScenePhaseChange(.active)
        vm.togglePlayPause()
        await gate.waitUntilStarted()
        let task4 = vm.pausedRestoreResumeTask
        vm.fatalError = "Stream error"
        await gate.finish()
        await task4?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end"])
        XCTAssertTrue(vm.needsNativeAudioActivationAfterPausedRestore)
        vm.fatalError = nil

        // 5. Teardown while activation is in flight blocks play and clears flag
        log.withLock { $0.removeAll() }
        await gate.reset()
        vm.togglePlayPause()
        await gate.waitUntilStarted()
        let task5 = vm.pausedRestoreResumeTask
        vm.teardownAndStop()
        await gate.finish()
        await task5?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end"])
        XCTAssertFalse(vm.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertNil(vm.pausedRestoreResumeTask)
    }

    @MainActor
    func testForegroundRestoreTogglePlayPauseAndCurtainRevealGate() throws {
        let suite = "luna.test.restorevm.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = MockPlayerTransport()
        let comfort = ComfortPreferences(defaults: defaults)
        let viewModel = PlayerViewModel(engine: engine, comfort: comfort, transport: transport)
        viewModel.isResolving = false
        viewModel.hasFirstFrameReadyForDisplay = true
        viewModel.isAwaitingDisplaySwitch = false
        viewModel.isRestoringFromBackground = true
        viewModel.lastForegroundPlaybackWasPlaying = false

        XCTAssertFalse(viewModel.isPictureReadyForReveal)

        viewModel.togglePlayPause()
        XCTAssertEqual(viewModel.userDesiredPlayingDuringRestore, true)
        XCTAssertTrue(viewModel.lastForegroundPlaybackWasPlaying)

        viewModel.togglePlayPause()
        XCTAssertEqual(viewModel.userDesiredPlayingDuringRestore, false)
        XCTAssertFalse(viewModel.lastForegroundPlaybackWasPlaying)

        viewModel.isRestoringFromBackground = false
        viewModel.userDesiredPlayingDuringRestore = nil
        XCTAssertTrue(viewModel.isPictureReadyForReveal)

        viewModel.needsNativeAudioActivationAfterPausedRestore = true
        viewModel.teardownAndStop()
        XCTAssertFalse(viewModel.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertFalse(viewModel.isRestoringFromBackground)
        XCTAssertNil(viewModel.userDesiredPlayingDuringRestore)
    }

    @MainActor
    func testDvGuardsScrubPreviewMemoryGateZeroRttAndWirelessRouteLipSync() throws {
        let suite = "luna.test.steg52.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let sessionJson = #"""
        {
          "sessionId": "tvs_fel_1",
          "streamToken": "0123456789abcdef0123456789abcdef",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-fel",
            "displayHeadline": "4K Remux DV FEL",
            "releaseTitle": "Eksempelfilm.2024.2160p.UHD.BluRay.REMUX",
            "source": "local",
            "tier": "ssd",
            "videoCodec": "hevc",
            "dvProfile": 7,
            "dvEnhancementLayer": "FEL"
          },
          "stream": {
            "url": "/api/tv/v2/stream/tvs_fel_1/0123456789abcdef0123456789abcdef/film.mkv",
            "startPositionSeconds": 120,
            "canClientPrewarmBytes": true
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "foldsDolbyVisionFEL": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless",
            "generatesBackgroundScrubPreviews": true
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJson.utf8))
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true
        )

        // A-3: 4 GB `.standard` forces `generatesBackgroundScrubPreviews = false` on DV P7 FEL
        let dvCaps = DisplayCapabilities(supportsHDR: true, supportsDolbyVision: true, supportsHDR10: true, supportsHLG: true)
        let standard4GB = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 5)
        let comfort = ComfortPreferences(defaults: defaults, memoryTier: .standard)
        let opts4GB = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            displayCapabilities: dvCaps,
            memoryProfile: standard4GB,
            availableMemoryBytes: 900 * 1_048_576
        )
        XCTAssertTrue(opts4GB.preferDualLayerDolbyVision)
        XCTAssertFalse(opts4GB.generatesBackgroundScrubPreviews)

        // A-8: `.forceOn` cannot force Dolby Vision onto a non-DV Samsung HDR10+ panel
        comfort.dualLayerOverride = .forceOn
        let nonDvCaps = DisplayCapabilities(supportsHDR: true, supportsDolbyVision: false, supportsHDR10: true, supportsHLG: true)
        let optsNonDV = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            displayCapabilities: nonDvCaps,
            memoryProfile: standard4GB,
            availableMemoryBytes: 900 * 1_048_576
        )
        XCTAssertFalse(optsNonDV.preferDualLayerDolbyVision)
        XCTAssertFalse(optsNonDV.foldsDolbyVisionFEL)
        XCTAssertEqual(optsNonDV.dolbyVisionHandling, .baseLayerOnly)

        // A-1: 0-RTT direct-mount eligibility check
        let warmReq = PlaybackLaunchRequest(
            itemId: "movie:tmdb:550",
            title: "Eksempelfilm",
            startPositionSeconds: 120.5,
            prepareToken: session.sessionId,
            preparedSession: session
        )
        XCTAssertTrue(PlayerViewModel.canDirectMountPreparedSession(warmReq))
        let explicitCandReq = PlaybackLaunchRequest(
            itemId: "movie:tmdb:550",
            title: "Eksempelfilm",
            startPositionSeconds: 120,
            candidateId: "other-cand",
            preparedSession: session
        )
        XCTAssertFalse(PlayerViewModel.canDirectMountPreparedSession(explicitCandReq))

        // A-15: Wireless Bluetooth/AirPods route zeroes manual HDMI lip-sync and restores on HDMI return
        XCTAssertTrue(PlayerAudioSessionCoordinator.isWirelessCompensatedRoute(portTypes: [.bluetoothA2DP]))
        XCTAssertFalse(PlayerAudioSessionCoordinator.isWirelessCompensatedRoute(portTypes: [.HDMI]))

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        comfort.audioDelayMs = -50
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: false)
        vm.isResolving = false
        vm.isWirelessAudioRouteActive = false
        vm.handleAudioRouteChange(isWirelessOverride: true)
        XCTAssertEqual(transport.events.last, "audioDelay(0ms)")
        vm.handleAudioRouteChange(isWirelessOverride: false)
        XCTAssertEqual(transport.events.last, "audioDelay(-50ms)")
    }

    @MainActor
    func testForegroundVideoRestoreRoutesThroughTransportReloadAtCurrentPosition() async throws {
        let suite = "luna.test.restore.reload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let sessionJSON = #"""
        {
          "sessionId": "sess-restore-1",
          "streamToken": "tok-restore-secret-445566",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "movie:tmdb:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Fight Club"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10+",
            "releaseTitle": "Fight.Club.2160p",
            "source": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/sess-restore-1/tok-restore-secret-445566/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)
        comfort.dualLayerOverride = .forceOff
        comfort.lowResUpscaleMode = .animeLineArt
        let transport = MockPlayerTransport(
            state: .paused,
            playbackPhase: .paused,
            videoRoute: .loopback,
            currentTime: 420,
            needsForegroundVideoRestore: true
        )
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: false)
        vm.activeSession = session
        vm.isResolving = false
        vm.lastForegroundPlaybackWasPlaying = true

        vm.handleScenePhaseChange(.active)
        await vm.restoreController.foregroundRestoreTask?.value

        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertTrue(transport.events.contains("reloadAtCurrentPosition"))
        XCTAssertEqual(transport.lastReloadedOptions?.autoplay, true)
        XCTAssertEqual(transport.lastReloadedOptions?.preferDualLayerDolbyVision, false)
        XCTAssertEqual(transport.lastReloadedOptions?.foldsDolbyVisionFEL, false)
        XCTAssertEqual(transport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertEqual(transport.lastReloadedOptions?.upscalesLowResolutionVideo, true)
        XCTAssertEqual(transport.lastReloadedOptions?.upscaleScaler, .lineArt)
        XCTAssertEqual(transport.state, .playing)
    }
}
