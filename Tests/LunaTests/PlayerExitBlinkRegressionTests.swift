import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PlayerExitBlinkRegressionTests: XCTestCase {
    @MainActor
    func testSharedEngineDisablesAudioSessionDeactivationOnStop() throws {
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        XCTAssertFalse(engine.deactivatesAudioSessionOnStop)
        XCTAssertEqual(engine.maximumSubtitleAdvanceSeconds, 0)
        XCTAssertEqual(engine.maximumSubtitleDelaySeconds, 10)
        XCTAssertTrue(engine.ownsSoftwareNowPlaying)
        XCTAssertTrue(engine.ownsVideoNowPlayingSession)
        XCTAssertTrue(engine.ownsVideoNowPlayingCommands)
    }

    func testShouldPauseEngineOnDismissPredicate() {
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .playing, playbackPhase: .playing))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .seeking, playbackPhase: .seeking))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .loading, playbackPhase: .loading))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .rebuffering))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .stalled(reconnecting: true)))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .paused))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .idle, playbackPhase: .idle))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .ended, playbackPhase: .ended))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .error("err"), playbackPhase: .error("err")))
    }

    @MainActor
    func testPrepareForDismissalPausesWithoutFrameZeroStopAndTeardownStopsOffScreen() throws {
        let suite = "luna.test.dismissal.\(UUID().uuidString)"
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

        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(engine: engine, comfort: comfort)
        vm.isResolving = false
        vm.playbackPhase = .playing

        var events: [String] = []
        vm.pauseActionForTesting = {
            events.append("pause")
        }
        vm.stopActionForTesting = { resetCriteria, finalTeardown in
            events.append("stop(\(resetCriteria),\(finalTeardown))")
        }

        vm.prepareForDismissal()
        XCTAssertTrue(vm.isDismissing)
        XCTAssertFalse(vm.isTeardownCompleted)
        XCTAssertEqual(events, ["pause"])
        XCTAssertEqual(vm.playbackPhase, .playing)

        // Calling prepareForDismissal twice is idempotent
        vm.prepareForDismissal()
        XCTAssertEqual(events, ["pause"])

        var didComplete = false
        vm.teardownAndStop {
            didComplete = true
        }
        XCTAssertTrue(vm.isTeardownCompleted)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(events, ["pause", "stop(false,true)"])

        // Calling teardownAndStop twice is idempotent
        vm.teardownAndStop()
        XCTAssertEqual(events, ["pause", "stop(false,true)"])
    }

    @MainActor
    func testSupersededOwnerSkipsEngineStopDuringLateDisappear() throws {
        let suite = "luna.test.ownership.\(UUID().uuidString)"
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

        let comfort = ComfortPreferences(defaults: defaults)
        let vm1 = PlayerViewModel(engine: engine, comfort: comfort)
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort)

        var vm1Pauses = 0
        var vm1Stops = 0
        var vm2Stops = 0

        vm1.pauseActionForTesting = { vm1Pauses += 1 }
        vm1.stopActionForTesting = { _, _ in vm1Stops += 1 }
        vm2.stopActionForTesting = { _, _ in vm2Stops += 1 }

        let req1 = PlaybackLaunchRequest(
            itemId: "episode:tmdb:100:s1:e1",
            title: "Episode 1",
            seriesTitle: "Test",
            season: 1,
            episode: 1
        )
        let req2 = PlaybackLaunchRequest(
            itemId: "episode:tmdb:100:s1:e2",
            title: "Episode 2",
            seriesTitle: "Test",
            season: 1,
            episode: 2
        )

        vm1.start(request: req1, client: nil)
        vm1.fatalError = nil
        vm1.playbackPhase = .playing
        XCTAssertTrue(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))

        vm1.prepareForDismissal()
        XCTAssertEqual(vm1Pauses, 1)
        XCTAssertEqual(vm1Stops, 0)

        vm2.start(request: req2, client: nil)
        XCTAssertFalse(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm2.engineOwnerToken))

        vm1.teardownAndStop()
        XCTAssertTrue(vm1.isTeardownCompleted)
        XCTAssertEqual(vm1Stops, 0)

        vm2.teardownAndStop()
        XCTAssertTrue(vm2.isTeardownCompleted)
        XCTAssertEqual(vm2Stops, 1)
    }

    @MainActor
    func testKeepDisplayModeInMenuPreferenceControlsPlayerExitAndBackgroundReset() async throws {
        let suite = "luna.test.displayhold.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertTrue(comfort.keepDisplayModeInMenuAfterPlayback)

        var syncCalls = 0
        comfort.onSyncRequested = { _ in syncCalls += 1 }
        comfort.keepDisplayModeInMenuAfterPlayback = false
        XCTAssertEqual(syncCalls, 0)
        XCTAssertEqual(
            defaults.object(forKey: SideloadSafeStorage.keepDisplayModeInMenuAfterPlaybackKey) as? Bool,
            false
        )
        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.keepDisplayModeInMenuAfterPlayback)

        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                keepDisplayModeInMenuAfterPlayback: true,
                isForegroundActive: true
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                keepDisplayModeInMenuAfterPlayback: true,
                isForegroundActive: false
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                keepDisplayModeInMenuAfterPlayback: false,
                isForegroundActive: true
            )
        )

        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: false,
                keepDisplayModeInMenu: true
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isActiveScene: false,
                hasActivePlayback: false,
                engineState: .idle
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isActiveScene: true,
                hasActivePlayback: false,
                engineState: .idle
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isActiveScene: false,
                hasActivePlayback: true,
                engineState: .idle
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isActiveScene: false,
                hasActivePlayback: false,
                engineState: .playing
            )
        )

        // Held display criteria survives detail disappear and only resets on explicit flush (scenePhase != .active)
        let coordinator = PlayerAudioSessionCoordinator()
        var resetCount = 0
        coordinator.holdDisplayCriteriaUntilBackground(
            shouldExecute: { true },
            performReset: { resetCount += 1 }
        )
        coordinator.handleDetailDisappear(
            isLaunchingPlayback: false,
            isShowingSourcePicker: false,
            keepDisplayModeInMenu: true
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resetCount, 0)

        coordinator.flushDeferredDisplayCriteriaResetIfIdle()
        XCTAssertEqual(resetCount, 1)
        coordinator.flushDeferredDisplayCriteriaResetIfIdle()
        XCTAssertEqual(resetCount, 1)

        // When user disables keepDisplayModeInMenuAfterPlayback, teardownAndStop passes resetDisplayCriteria: true
        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let vm = PlayerViewModel(engine: engine, comfort: reloaded)
        var capturedStops: [(Bool, Bool)] = []
        vm.stopActionForTesting = { resetCriteria, finalTeardown in
            capturedStops.append((resetCriteria, finalTeardown))
        }
        vm.teardownAndStop()
        XCTAssertEqual(capturedStops.count, 1)
        XCTAssertEqual(capturedStops.first?.0, true)
        XCTAssertEqual(capturedStops.first?.1, true)
    }
}
