import Foundation

/// Deterministic HDMI display-switch curtain gate evaluator.
///
/// Enforces Luna's cinema curtain invariant:
/// - Keep `ResolvingCurtainView` opaque until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch`
/// - Force-unlock after `defaultFallbackTimeoutSeconds` (5.0 s) so a missed HDMI EDID notification never hangs black
public enum PlaybackCurtainWatchdog: Sendable {
    public static let defaultFallbackTimeoutSeconds: Double = 5.0

    public static func isPictureReadyForReveal(
        hasFatalError: Bool,
        isSwitchingSource: Bool,
        isResolving: Bool,
        isRestoringFromBackground: Bool,
        needsForegroundVideoRestore: Bool,
        firstFrameFallbackUnlocked: Bool,
        hasFirstFrameReadyForDisplay: Bool,
        isAwaitingDisplaySwitch: Bool
    ) -> Bool {
        if hasFatalError {
            return false
        }
        if isSwitchingSource {
            return true
        }
        if isResolving || isRestoringFromBackground || needsForegroundVideoRestore {
            return false
        }
        if firstFrameFallbackUnlocked {
            return true
        }
        return hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch
    }
}
