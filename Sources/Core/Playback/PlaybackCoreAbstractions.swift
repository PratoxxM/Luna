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

/// Flicker-free `0-RTT` warm-start curtain presentation policy (`180 ms` pure-black grace).
///
/// - When launching a warm/prepared session (`prepareToken != nil` or `preparedSession != nil`)
///   without an active HDMI display-mode switch, holds pure `#000000` for up to `180 ms`:
///   if the first video frame is ready within `180 ms`, playback opens straight into video with
///   zero curtain flash; otherwise `ResolvingCurtainView` fades in smoothly (`0.22 s`).
/// - Cold starts and active HDMI mode switches (`isAwaitingDisplaySwitch == true`) present
///   `ResolvingCurtainView` immediately from `0 ms`.
public enum PlaybackCurtainPresentationPolicy: Sendable {
    public static let warmStartGraceMilliseconds: Int = 180
    public static let warmStartGraceNanoseconds: UInt64 = 180_000_000
    public static let curtainFadeInDurationSeconds: Double = 0.22

    public static func hasWarmPreparedSession(
        prepareToken: String?,
        hasPreparedSession: Bool
    ) -> Bool {
        if hasPreparedSession {
            return true
        }
        guard let trimmed = prepareToken?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !trimmed.isEmpty
    }

    public static func shouldHoldSilentBlackGrace(
        hasWarmPreparedSession: Bool,
        isAwaitingDisplaySwitch: Bool,
        isRestoringFromBackground: Bool = false,
        graceElapsed: Bool
    ) -> Bool {
        guard hasWarmPreparedSession,
              !isAwaitingDisplaySwitch,
              !isRestoringFromBackground,
              !graceElapsed else {
            return false
        }
        return true
    }

    public static func shouldShowCurtainContent(
        hasWarmPreparedSession: Bool,
        isAwaitingDisplaySwitch: Bool,
        isRestoringFromBackground: Bool = false,
        graceElapsed: Bool
    ) -> Bool {
        !shouldHoldSilentBlackGrace(
            hasWarmPreparedSession: hasWarmPreparedSession,
            isAwaitingDisplaySwitch: isAwaitingDisplaySwitch,
            isRestoringFromBackground: isRestoringFromBackground,
            graceElapsed: graceElapsed
        )
    }
}
