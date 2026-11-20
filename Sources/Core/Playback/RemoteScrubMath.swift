import Foundation

/// Pure, Linux-testable Siri Remote scrub calculation and click-isolation rules.
///
/// Design invariants (D1):
///  - Enforces an 18 % horizontal deadzone and 1.35:1 horizontal axis lock so accidental
///    vertical swipes or thumb rests never jitter playback.
///  - Requires a stronger intentional horizontal drag (`>= 0.30`) while actively playing
///    than when already paused (`> 0.18`).
///  - Uses a duration-independent non-linear cubic offset capped at `75 s` per full swipe
///    so long 3-hour films never jump minutes on a gentle touch.
public enum RemoteScrubMath: Sendable {
    public static let deadzoneNormalized: Double = 0.18
    public static let playingActivationThreshold: Double = 0.30
    public static let axisLockRatio: Double = 1.35
    public static let maxDeltaSeconds: Double = 75.0
    public static let clickSuppressionWindowSeconds: TimeInterval = 0.18

    public struct PanEvaluation: Equatable, Sendable {
        public let shouldActivate: Bool
        public let deltaSeconds: Double

        public init(shouldActivate: Bool, deltaSeconds: Double) {
            self.shouldActivate = shouldActivate
            self.deltaSeconds = deltaSeconds
        }
    }

    /// Computes non-linear scrub time offset in seconds from normalized horizontal travel `[-1, 1]`.
    public static func deltaSeconds(forNormalizedX normalizedX: Double) -> Double {
        let absX = abs(normalizedX)
        guard absX > deadzoneNormalized else { return 0 }
        let u = min(1.0, max(0.0, (absX - deadzoneNormalized) / (1.0 - deadzoneNormalized)))
        let magnitude = min(maxDeltaSeconds, 14.0 * u + 61.0 * u * u * u)
        return normalizedX >= 0 ? magnitude : -magnitude
    }

    /// Evaluates whether a Siri Remote surface pan should activate/update scrubbing.
    public static func evaluatePan(
        dx: Double,
        dy: Double,
        normalizedX: Double,
        isPlaying: Bool,
        alreadyActive: Bool
    ) -> PanEvaluation {
        let absDx = abs(dx)
        let absDy = abs(dy)
        if !alreadyActive && absDx < absDy * axisLockRatio {
            return PanEvaluation(shouldActivate: false, deltaSeconds: 0)
        }
        let absNorm = abs(normalizedX)
        let threshold = (isPlaying && !alreadyActive) ? playingActivationThreshold : deadzoneNormalized
        guard absNorm > threshold else {
            return PanEvaluation(shouldActivate: false, deltaSeconds: 0)
        }
        return PanEvaluation(shouldActivate: true, deltaSeconds: deltaSeconds(forNormalizedX: normalizedX))
    }

    /// Suppresses accidental scrub commits caused by tiny thumb drift right before/after a physical
    /// left/right/select button press.
    public static func isMicroDriftBeforeClick(maxAbsNormalizedX: Double) -> Bool {
        abs(maxAbsNormalizedX) < playingActivationThreshold
    }

    public static func shouldSuppressPanCommit(
        secondsSinceDiscreteClick: TimeInterval?,
        maxAbsNormalizedX: Double
    ) -> Bool {
        if let elapsed = secondsSinceDiscreteClick,
           elapsed >= 0,
           elapsed <= clickSuppressionWindowSeconds,
           isMicroDriftBeforeClick(maxAbsNormalizedX: maxAbsNormalizedX) {
            return true
        }
        return false
    }
}
