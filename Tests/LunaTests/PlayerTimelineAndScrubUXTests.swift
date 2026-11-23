import AetherBridge
import CoreGraphics
import Foundation
import XCTest
@testable import Luna

final class PlayerTimelineAndScrubUXTests: XCTestCase {
    @MainActor
    func testScrubPreviewBubbleUpgraded22PtSafeWidths() {
        XCTAssertEqual(ScrubPreviewBubbleView.frameWidth, 284)
        XCTAssertEqual(ScrubPreviewBubbleView.compactWidth, 252)

        let compact = ScrubPreviewBubbleView(
            targetSeconds: 10_110,
            originSeconds: 5_590,
            chapterTitle: "Kapittel 4 — Vinterstorm",
            previewImage: nil,
            drawsInCompositorView: false,
            onMountCompositorView: { _ in }
        )
        XCTAssertFalse(compact.hasVisualFrame)
        XCTAssertEqual(compact.preferredWidth, 252)

        let compositor = ScrubPreviewBubbleView(
            targetSeconds: 10_110,
            originSeconds: 5_590,
            chapterTitle: "Kapittel 4 — Vinterstorm",
            previewImage: nil,
            drawsInCompositorView: true,
            onMountCompositorView: { _ in }
        )
        XCTAssertTrue(compositor.hasVisualFrame)
        XCTAssertEqual(compositor.preferredWidth, 284)
    }

    @MainActor
    func testPauseFromFocusedQuickActionsImmediatelyRestoresScrubReadyCanvas() throws {
        let suite = "luna.test.osd.pausefocus.\(UUID().uuidString)"
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
        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: transport
        )
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true
        vm.isAwaitingDisplaySwitch = false
        vm.playbackPhase = .playing
        vm.durationSeconds = 3600

        let osd = PlayerOSDCoordinator()
        osd.revealBottomBarAndFocusQuickActions(target: .panel(.subtitles), viewModel: vm)
        XCTAssertTrue(osd.isQuickActionsModeActive)
        XCTAssertFalse(osd.shouldEnableCanvasAnchor(viewModel: vm))

        // Pressing Play/Pause while quick-action pills hold focus pauses playback and immediately
        // releases pill focus back to SiriRemoteTouchSurface so pause-scrubbing works at once.
        let prevClearNonce = osd.bottomBarClearFocusNonce
        let prevCanvasNonce = osd.canvasRestoreNonce
        osd.handlePlayPauseCommand(viewModel: vm)
        vm.playbackPhase = .paused

        XCTAssertEqual(transport.state, .paused)
        XCTAssertFalse(osd.isQuickActionsModeActive)
        XCTAssertGreaterThan(osd.bottomBarClearFocusNonce, prevClearNonce)
        XCTAssertGreaterThan(osd.canvasRestoreNonce, prevCanvasNonce)
        XCTAssertTrue(osd.showBottomBar)
        XCTAssertFalse(osd.isPausedOSDResting)
        XCTAssertTrue(osd.isPauseRestArmed)
        XCTAssertTrue(osd.shouldEnableCanvasAnchor(viewModel: vm))

        // Explicitly pressing Down while already paused focuses quick actions cleanly,
        // and pressing Menu from paused quick actions returns to canvas while keeping OSD visible.
        osd.revealBottomBarAndFocusQuickActions(target: .panel(.audio), viewModel: vm)
        XCTAssertTrue(osd.isQuickActionsModeActive)

        var didClosePlayer = false
        osd.handleExitCommand(viewModel: vm) {
            didClosePlayer = true
        }
        XCTAssertFalse(didClosePlayer)
        XCTAssertFalse(osd.isQuickActionsModeActive)
        XCTAssertTrue(osd.showBottomBar)
        XCTAssertFalse(osd.isPausedOSDResting)
        XCTAssertTrue(osd.isPauseRestArmed)
        XCTAssertTrue(osd.shouldEnableCanvasAnchor(viewModel: vm))
    }

    @MainActor
    func testOledPauseRestWakeAndMenuScrubCancellation() throws {
        let suite = "luna.test.osd.scrubcancel.\(UUID().uuidString)"
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

        let transport = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        transport.currentTime = 1840
        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: transport
        )
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true
        vm.isAwaitingDisplaySwitch = false
        vm.playbackPhase = .paused
        vm.durationSeconds = 6180

        let osd = PlayerOSDCoordinator()
        osd.enterPausedIdleRest()
        XCTAssertTrue(osd.isPausedOSDResting)
        XCTAssertFalse(osd.isBottomBarShown(viewModel: vm))
        XCTAssertTrue(osd.isHUDResting(viewModel: vm))

        // Light touch / wake clears 12s OLED rest and renews pause rest timer
        let prevRestNonce = osd.pauseRestNonce
        osd.revealBottomBarTemporarily(viewModel: vm)
        XCTAssertFalse(osd.isPausedOSDResting)
        XCTAssertTrue(osd.isBottomBarShown(viewModel: vm))
        XCTAssertGreaterThan(osd.pauseRestNonce, prevRestNonce)

        // Menu during active scrub cancels back to originSeconds without closing player
        vm.beginTouchScrub()
        vm.updateTouchScrub(deltaSeconds: 920)
        XCTAssertTrue(vm.isScrubbing)
        XCTAssertEqual(vm.scrubState.targetSeconds, 2760, accuracy: 0.01)

        var didClosePlayer = false
        let prevHoldCancelNonce = osd.ringHoldCancelNonce
        osd.handleExitCommand(viewModel: vm) {
            didClosePlayer = true
        }
        XCTAssertFalse(didClosePlayer)
        XCTAssertFalse(vm.isScrubbing)
        XCTAssertEqual(vm.scrubState.targetSeconds, 1840, accuracy: 0.01)
        XCTAssertGreaterThan(osd.ringHoldCancelNonce, prevHoldCancelNonce)

        // TouchCaptureUIView disarms active ring-hold cleanly when cancelHoldNonce advances
        let touchView = TouchCaptureUIView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        var firedRightClick = false
        touchView.onRightClick = { firedRightClick = true }
        touchView.applyCancelHoldNonce(osd.ringHoldCancelNonce)
        XCTAssertFalse(touchView.hasActiveOrPendingRingPress)
        XCTAssertFalse(firedRightClick)

        // Suspended fatalError restores when source quick-panel is dismissed via Menu without switching
        vm.fatalError = nil
        osd.suspendedFatalErrorForPanel = "Kunne ikke lese strøm."
        osd.openQuickPanel(.source)
        osd.handleExitCommand(viewModel: vm) {
            didClosePlayer = true
        }
        XCTAssertFalse(didClosePlayer)
        XCTAssertNil(osd.activeQuickPanel)
        XCTAssertEqual(vm.fatalError, "Kunne ikke lese strøm.")
    }
}
