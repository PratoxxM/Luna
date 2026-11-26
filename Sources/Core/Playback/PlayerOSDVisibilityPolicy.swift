import Foundation
#if canImport(AetherBridge)
import AetherBridge
#endif

/// Pure OSD visibility, `12 s` OLED pause-rest, and subtitle overlay visibility rules.
public enum PlayerOSDVisibilityPolicy: Sendable {
    public static let playingAutoHideSeconds: TimeInterval = 4.0
    public static let playingQuickActionsAutoHideSeconds: TimeInterval = 7.0
    public static let pausedIdleRestSeconds: TimeInterval = 12.0

    public static func shouldShowBottomBar(
        isPictureReadyForReveal: Bool,
        isQuickPanelOpen: Bool,
        hasFatalError: Bool,
        isScrubbing: Bool,
        showBottomBar: Bool,
        isPaused: Bool,
        isPausedOSDResting: Bool
    ) -> Bool {
        guard isPictureReadyForReveal, !hasFatalError else {
            return false
        }
        if isQuickPanelOpen || isScrubbing || showBottomBar {
            return true
        }
        return isPaused && !isPausedOSDResting
    }

    public static func shouldRestAmbientPlayerHUD(
        isPaused: Bool,
        isPausedOSDResting: Bool,
        isScrubbing: Bool,
        isQuickPanelOpen: Bool
    ) -> Bool {
        isPaused && isPausedOSDResting && !isScrubbing && !isQuickPanelOpen
    }

    /// Active subtitles remain visible (`opacity = 1`, lifted to top when any quick-panel tab is open)
    /// across `Tekst`, `Lyd`, `Utgave`, `Bilde`, and `Kapitler`, while staying suppressed behind
    /// fatal errors or pre-reveal emergency recovery panels.
    public static func shouldShowSubtitleOverlay(
        hasFatalError: Bool,
        hasSuspendedFatalError: Bool,
        isPictureReadyForReveal: Bool,
        isPreviewMode: Bool = false
    ) -> Bool {
        guard !hasFatalError, !hasSuspendedFatalError else {
            return false
        }
        return isPictureReadyForReveal || isPreviewMode
    }

    #if canImport(AetherBridge)
    public static func shouldShowBottomBar(
        isPictureReadyForReveal: Bool,
        isQuickPanelOpen: Bool,
        hasFatalError: Bool,
        isScrubbing: Bool,
        showBottomBar: Bool,
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool
    ) -> Bool {
        shouldShowBottomBar(
            isPictureReadyForReveal: isPictureReadyForReveal,
            isQuickPanelOpen: isQuickPanelOpen,
            hasFatalError: hasFatalError,
            isScrubbing: isScrubbing,
            showBottomBar: showBottomBar,
            isPaused: playbackPhase == .paused,
            isPausedOSDResting: isPausedOSDResting
        )
    }

    public static func shouldRestAmbientPlayerHUD(
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool,
        isScrubbing: Bool,
        isQuickPanelOpen: Bool
    ) -> Bool {
        shouldRestAmbientPlayerHUD(
            isPaused: playbackPhase == .paused,
            isPausedOSDResting: isPausedOSDResting,
            isScrubbing: isScrubbing,
            isQuickPanelOpen: isQuickPanelOpen
        )
    }
    #endif
}
