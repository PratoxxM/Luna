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

        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport)
        vm.isResolving = false
        vm.playbackPhase = .playing

        vm.prepareForDismissal()
        XCTAssertTrue(vm.isDismissing)
        XCTAssertFalse(vm.isTeardownCompleted)
        XCTAssertEqual(transport.events, ["pause"])
        XCTAssertEqual(vm.playbackPhase, .playing)

        // Calling prepareForDismissal twice is idempotent
        vm.prepareForDismissal()
        XCTAssertEqual(transport.events, ["pause"])

        var didComplete = false
        vm.teardownAndStop {
            didComplete = true
        }
        XCTAssertTrue(vm.isTeardownCompleted)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(transport.events, ["pause", "stop(true,true)"])

        // Calling teardownAndStop twice is idempotent
        vm.teardownAndStop()
        XCTAssertEqual(transport.events, ["pause", "stop(true,true)"])
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

        let transport1 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let transport2 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let comfort = ComfortPreferences(defaults: defaults)
        let vm1 = PlayerViewModel(engine: engine, comfort: comfort, transport: transport1)
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort, transport: transport2)

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
        XCTAssertEqual(transport1.events, ["pause"])

        vm2.start(request: req2, client: nil)
        XCTAssertFalse(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm2.engineOwnerToken))

        vm1.teardownAndStop()
        XCTAssertTrue(vm1.isTeardownCompleted)
        XCTAssertEqual(transport1.events, ["pause"])

        vm2.teardownAndStop()
        XCTAssertTrue(vm2.isTeardownCompleted)
        XCTAssertEqual(transport2.events, ["stop(true,true)"])
    }

    @MainActor
    func testKeepDisplayModeInMenuPreferenceMigratesExistingTVsTo60HzAndSupportsPerTvOptOut() async throws {
        let suite = "luna.test.displayhold.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: SideloadSafeStorage.keepDisplayModeInMenuAfterPlaybackKey)
        XCTAssertFalse(defaults.bool(forKey: SideloadSafeStorage.didMigrateMenu60HzDefaultV240Key))

        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertFalse(comfort.keepDisplayModeInMenuAfterPlayback)
        XCTAssertTrue(comfort.returnTo60HzInMenuAfterPlayback)
        XCTAssertTrue(defaults.bool(forKey: SideloadSafeStorage.didMigrateMenu60HzDefaultV240Key))
        XCTAssertTrue(SettingsView.keepDisplayModeToggleTitle.contains("HDR-modus"))
        XCTAssertTrue(SettingsView.keepDisplayModeExplanationText.contains("60 Hz"))
        XCTAssertTrue(SettingsView.keepDisplayModeExplanationText.contains("24 Hz"))

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let defaultTransport = MockPlayerTransport()
        let defaultVm = PlayerViewModel(engine: engine, comfort: comfort, transport: defaultTransport)
        defaultVm.teardownAndStop()
        XCTAssertEqual(defaultTransport.events, ["stop(true,true)"])

        var syncCalls = 0
        comfort.onSyncRequested = { _ in syncCalls += 1 }
        comfort.keepDisplayModeInMenuAfterPlayback = true
        XCTAssertEqual(syncCalls, 0)
        XCTAssertTrue(comfort.keepDisplayModeInMenuAfterPlayback)
        XCTAssertFalse(comfort.returnTo60HzInMenuAfterPlayback)
        XCTAssertEqual(
            defaults.object(forKey: SideloadSafeStorage.keepDisplayModeInMenuAfterPlaybackKey) as? Bool,
            true
        )

        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.keepDisplayModeInMenuAfterPlayback)
        XCTAssertFalse(reloaded.returnTo60HzInMenuAfterPlayback)

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

        let optOutTransport = MockPlayerTransport()
        let optOutVm = PlayerViewModel(engine: engine, comfort: reloaded, transport: optOutTransport)
        optOutVm.teardownAndStop()
        XCTAssertEqual(optOutTransport.events, ["stop(false,true)"])
    }
}
