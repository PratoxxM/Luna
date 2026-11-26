import Observation
import SwiftUI
import UIKit
import AetherBridge

/// Coordinates bottom-OSD visibility, `12 s` OLED pause rest, quick-panel popovers,
/// Siri Remote `Play/Pause` focus handoff, and the 6-step `Menu` (`onExitCommand`) ladder.
///
/// Subscribes to **zero** `AetherEngine` clock/telemetry publishers (`0 Hz` steady-state).
@MainActor
@Observable
final class PlayerOSDCoordinator {
    var showBottomBar: Bool = false
    var isPausedOSDResting: Bool = false
    var activeQuickPanel: PlayerQuickPanelTab? = nil
    var lastSelectedQuickTab: PlayerQuickPanelTab = .subtitles
    var quickActionFrames: [PlayerQuickPanelTab: CGRect] = [:]
    var isQuickActionsModeActive: Bool = false
    var bottomBarFocusRequestNonce: Int = 0
    var bottomBarClearFocusNonce: Int = 0
    var requestedBottomBarAction: PlayerBottomBarAction = .panel(.subtitles)
    var activeSeriesOverlay: ActiveSeriesOverlayKind = .none
    var hasSeriesPrompt: Bool = false
    var isSeriesPromptFocused: Bool = false
    var seriesPromptDismissNonce: Int = 0
    var seriesPromptFocusNonce: Int = 0
    var dismissedNextForSessionID: String? = nil
    var isAutoHideArmed: Bool = false
    var autoHideNonce: Int = 0
    var isPauseRestArmed: Bool = false
    var pauseRestNonce: Int = 0
    var canvasRestoreNonce: Int = 0
    var ringHoldCancelNonce: Int = 0
    var suspendedFatalErrorForPanel: String? = nil

    private static func osdAnimation(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }

    func shouldEnableCanvasAnchor(viewModel: PlayerViewModel) -> Bool {
        viewModel.isPictureReadyForReveal &&
            viewModel.fatalError == nil &&
            activeQuickPanel == nil &&
            !isQuickActionsModeActive
    }

    func isBottomBarShown(viewModel: PlayerViewModel) -> Bool {
        PlayerOSDVisibilityPolicy.shouldShowBottomBar(
            isPictureReadyForReveal: viewModel.isPictureReadyForReveal,
            isQuickPanelOpen: activeQuickPanel != nil,
            hasFatalError: viewModel.fatalError != nil,
            isScrubbing: viewModel.isScrubbing,
            showBottomBar: showBottomBar,
            playbackPhase: viewModel.playbackPhase,
            isPausedOSDResting: isPausedOSDResting
        )
    }

    func isHUDResting(viewModel: PlayerViewModel) -> Bool {
        PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
            playbackPhase: viewModel.playbackPhase,
            isPausedOSDResting: isPausedOSDResting,
            isScrubbing: viewModel.isScrubbing,
            isQuickPanelOpen: activeQuickPanel != nil
        )
    }

    func activeTopStatusToast(
        viewModel: PlayerViewModel
    ) -> (message: String, tone: LunaToastTone, showsSpinner: Bool)? {
        if viewModel.isSwitchingSource {
            return ("Bytter utgave…", .ok, true)
        }
        switch viewModel.playbackPhase {
        case .rebuffering, .stalled:
            return ("Bufrer…", .warn, true)
        default:
            break
        }
        if let banner = viewModel.qosReporter.transientBannerMessage, !banner.isEmpty {
            return (banner, .warn, false)
        }
        if let toast = viewModel.remoteCommandToastMessage, !toast.isEmpty {
            return (toast, .ok, false)
        }
        return nil
    }

    // MARK: - Siri Remote Play/Pause, Menu & Focus Transitions

    func beginInteractiveScrub() {
        isAutoHideArmed = false
        isPauseRestArmed = false
        withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
            isPausedOSDResting = false
            showBottomBar = true
        }
    }

    func handlePlayPauseCommand(viewModel: PlayerViewModel) {
        guard !viewModel.isResolving else { return }
        if activeQuickPanel != nil {
            closeQuickPanel(viewModel: viewModel, returnFocusToPill: false)
        }
        if viewModel.isScrubbing {
            ringHoldCancelNonce &+= 1
            viewModel.commitTouchScrub()
            revealBottomBarTemporarily(viewModel: viewModel)
            restoreCanvasFocusSoon()
            return
        }

        let wasActivelyPlaying = (viewModel.playbackPhase == .playing) ||
            PlayerViewModel.isActiveTransportIntent(
                playbackPhase: viewModel.transport.playbackPhase,
                engineState: viewModel.transport.state
            )
        let hadPendingResumeOrScrub = (viewModel.pausedRestoreResumeTask != nil || viewModel.scrubCommitTask != nil)
        viewModel.togglePlayPause()

        let enteredPausedState = wasActivelyPlaying || hadPendingResumeOrScrub
        if isQuickActionsModeActive && enteredPausedState {
            isAutoHideArmed = false
            isQuickActionsModeActive = false
            bottomBarClearFocusNonce &+= 1
            withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
                isPausedOSDResting = false
                showBottomBar = true
            }
            schedulePausedIdleRestTimer()
            restoreCanvasFocusSoon()
        } else {
            revealBottomBarTemporarily(viewModel: viewModel)
            if enteredPausedState {
                restoreCanvasFocusSoon()
            }
        }
    }

    func handleExitCommand(viewModel: PlayerViewModel, onClosePlayer: () -> Void) {
        let action = PlayerTimelinePolicy.resolveExitAction(
            hasActiveQuickPanel: activeQuickPanel != nil,
            isScrubbing: viewModel.isScrubbing,
            hasSeriesPrompt: hasSeriesPrompt,
            isHUDResting: isHUDResting(viewModel: viewModel),
            isQuickActionsModeActive: isQuickActionsModeActive,
            showBottomBar: showBottomBar,
            isPlaying: viewModel.playbackPhase == .playing
        )

        switch action {
        case .closeQuickPanel:
            closeQuickPanel(viewModel: viewModel, returnFocusToPill: true)
        case .cancelScrubbing:
            ringHoldCancelNonce &+= 1
            viewModel.cancelTouchScrub()
            revealBottomBarTemporarily(viewModel: viewModel)
            restoreCanvasFocusSoon()
        case .dismissSeriesPrompt:
            isSeriesPromptFocused = false
            seriesPromptDismissNonce &+= 1
            restoreCanvasFocusSoon()
        case .releaseQuickActionsFocus(let hideBottomBar):
            isAutoHideArmed = false
            isQuickActionsModeActive = false
            bottomBarClearFocusNonce &+= 1
            if hideBottomBar {
                withAnimation(Self.osdAnimation(.easeOut(duration: 0.2))) {
                    showBottomBar = false
                }
            } else {
                withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
                    isPausedOSDResting = false
                    showBottomBar = true
                }
                schedulePausedIdleRestTimer()
            }
            restoreCanvasFocusSoon()
        case .hideBottomBar:
            isAutoHideArmed = false
            withAnimation(Self.osdAnimation(.easeOut(duration: 0.2))) {
                showBottomBar = false
            }
            restoreCanvasFocusSoon()
        case .closePlayer:
            ringHoldCancelNonce &+= 1
            onClosePlayer()
        }
    }

    func handlePlaybackPhaseChange(
        oldPhase: PlaybackPhase,
        newPhase: PlaybackPhase,
        viewModel: PlayerViewModel,
        autoPlayNextEpisode: Bool,
        onClosePlayer: () -> Void
    ) {
        if newPhase == .paused {
            if oldPhase != .paused && isQuickActionsModeActive && activeQuickPanel == nil {
                isAutoHideArmed = false
                isQuickActionsModeActive = false
                bottomBarClearFocusNonce &+= 1
                restoreCanvasFocusSoon()
            }
            withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
                isPausedOSDResting = false
            }
            if activeQuickPanel == nil {
                schedulePausedIdleRestTimer()
            }
        } else {
            isPauseRestArmed = false
            if isPausedOSDResting {
                withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
                    isPausedOSDResting = false
                }
            }
            if oldPhase == .paused && newPhase == .playing && viewModel.isPictureReadyForReveal && activeQuickPanel == nil {
                revealBottomBarTemporarily(viewModel: viewModel)
            }
        }

        guard newPhase == .ended,
              !viewModel.isResolving,
              !viewModel.isSwitchingSource,
              !viewModel.isRestoringFromBackground else {
            return
        }
        if let next = viewModel.activeSession?.nextEpisode,
           SeriesFlowPolicy.shouldAutoPlayNextEpisodeOnEnded(
               autoPlayEnabled: autoPlayNextEpisode,
               hasNextEpisode: true,
               activeSessionID: viewModel.activeSession?.sessionId,
               dismissedNextForSessionID: dismissedNextForSessionID
           ) {
            viewModel.playNextEpisode(next)
        } else {
            onClosePlayer()
        }
    }

    func revealBottomBarAndFocusQuickActions(target: PlayerBottomBarAction, viewModel: PlayerViewModel) {
        isAutoHideArmed = false
        isPauseRestArmed = false
        isQuickActionsModeActive = true
        requestedBottomBarAction = target
        withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
            isPausedOSDResting = false
            showBottomBar = true
        }
        bottomBarFocusRequestNonce &+= 1
        scheduleBottomBarAutoHide(viewModel: viewModel)
    }

    func openQuickPanel(_ tab: PlayerQuickPanelTab) {
        isAutoHideArmed = false
        isPauseRestArmed = false
        isQuickActionsModeActive = false
        lastSelectedQuickTab = tab
        requestedBottomBarAction = .panel(tab)
        bottomBarClearFocusNonce &+= 1
        withAnimation(Self.osdAnimation(LunaFocusStyle.focusSpring)) {
            isPausedOSDResting = false
            showBottomBar = true
            activeQuickPanel = tab
        }
    }

    func switchQuickPanelTab(direction: QuickPanelHorizontalDirection, hasChapters: Bool) {
        guard suspendedFatalErrorForPanel == nil,
              let current = activeQuickPanel,
              let next = current.adjacentTab(direction: direction, hasChapters: hasChapters) else {
            return
        }
        lastSelectedQuickTab = next
        requestedBottomBarAction = .panel(next)
        withAnimation(Self.osdAnimation(LunaFocusStyle.focusSpring)) {
            activeQuickPanel = next
        }
    }

    func closeQuickPanel(viewModel: PlayerViewModel, returnFocusToPill: Bool) {
        viewModel.flushPendingAudioDelayCommitIfNeeded()
        isQuickActionsModeActive = returnFocusToPill
        withAnimation(Self.osdAnimation(.easeOut(duration: 0.18))) {
            activeQuickPanel = nil
        }
        if let suspended = suspendedFatalErrorForPanel {
            suspendedFatalErrorForPanel = nil
            isQuickActionsModeActive = false
            if !viewModel.isSwitchingSource && viewModel.fatalError == nil {
                viewModel.fatalError = suspended
                return
            }
        }
        if returnFocusToPill {
            revealBottomBarAndFocusQuickActions(target: .panel(lastSelectedQuickTab), viewModel: viewModel)
        } else {
            bottomBarClearFocusNonce &+= 1
            revealBottomBarTemporarily(viewModel: viewModel)
            restoreCanvasFocusSoon()
        }
    }

    func clearQuickActionFocusAndHideBarIfPlaying(viewModel: PlayerViewModel) {
        isAutoHideArmed = false
        isQuickActionsModeActive = false
        bottomBarClearFocusNonce &+= 1
        if viewModel.playbackPhase == .playing {
            withAnimation(Self.osdAnimation(.easeOut(duration: 0.2))) {
                showBottomBar = false
            }
        } else {
            schedulePausedIdleRestTimer()
        }
        restoreCanvasFocusSoon()
    }

    func revealBottomBarTemporarily(viewModel: PlayerViewModel) {
        withAnimation(Self.osdAnimation(.easeOut(duration: 0.16))) {
            isPausedOSDResting = false
            showBottomBar = true
        }
        scheduleBottomBarAutoHide(viewModel: viewModel)
    }

    func scheduleBottomBarAutoHide(viewModel: PlayerViewModel) {
        guard activeQuickPanel == nil else {
            isAutoHideArmed = false
            isPauseRestArmed = false
            return
        }
        isAutoHideArmed = true
        autoHideNonce &+= 1
        let isPausedNow = (viewModel.playbackPhase == .paused) || (viewModel.transport.state == .paused)
        if isPausedNow && !viewModel.isScrubbing && activeQuickPanel == nil {
            schedulePausedIdleRestTimer()
        }
    }

    func schedulePausedIdleRestTimer() {
        guard activeQuickPanel == nil else {
            isPauseRestArmed = false
            return
        }
        isPauseRestArmed = true
        pauseRestNonce &+= 1
    }

    func enterPausedIdleRest() {
        isQuickActionsModeActive = false
        bottomBarClearFocusNonce &+= 1
        withAnimation(Self.osdAnimation(.easeInOut(duration: 0.65))) {
            showBottomBar = false
            isPausedOSDResting = true
        }
        restoreCanvasFocusSoon()
    }

    func restoreCanvasFocusSoon() {
        canvasRestoreNonce &+= 1
    }

    func disarmAllTimers() {
        isAutoHideArmed = false
        isPauseRestArmed = false
    }
}
