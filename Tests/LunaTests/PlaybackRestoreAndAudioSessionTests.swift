import AetherBridge
import Foundation
import Synchronization
import XCTest
@testable import Luna

final class PlaybackRestoreAndAudioSessionTests: XCTestCase {
    func testNativeAudioSessionActivationOnlyAppliesToNativeRoutes() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .loopback))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .remoteBypass))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .software))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .audio))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .none))
    }

    func testDeferredDisplayCriteriaResetStatePredicate() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .idle))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .loading))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .playing))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .paused))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .seeking))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .ended))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .error("err")))
    }

    @MainActor
    func testDeferredDisplayCriteriaResetSchedulesCancelsAndFlushesSafely() async {
        final class ResetCounter {
            var count = 0
            var eligible = true
        }

        XCTAssertGreaterThanOrEqual(PlayerAudioSessionCoordinator.defaultDisplayCriteriaResetDelayNs, 15_000_000_000)
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: false
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: true,
                isShowingSourcePicker: false
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: true
            )
        )

        let coordinator = PlayerAudioSessionCoordinator()
        let counter = ResetCounter()

        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 30_000_000,
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        coordinator.cancelDeferredDisplayCriteriaReset()
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(counter.count, 0)

        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 25_000_000,
            shouldExecute: { false },
            performReset: { counter.count += 1 }
        )
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(counter.count, 0)

        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 25_000_000,
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(counter.count, 1)

        counter.eligible = false
        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 1_000_000_000,
            shouldExecute: { counter.eligible },
            performReset: { counter.count += 1 }
        )
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 1)

        counter.eligible = true
        coordinator.handleDetailDisappear(isLaunchingPlayback: true, isShowingSourcePicker: false)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: true)
        XCTAssertEqual(counter.count, 1)

        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 2)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 2)
    }

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
            "url": "/api/tv/v1/streams/sess-autoplay-1/master"
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

        let log = Mutex<[String]>([])
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
}
