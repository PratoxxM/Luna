import Foundation

/// Pure, Linux-testable Siri Remote scrub calculation and ring-hold state rules.
///
/// Design invariants (`v2.9.0`):
///  - Touch-surface scrubbing activates **only when paused** (`!isPlaying`), preventing accidental
///    thumb-rest pauses/seeks during active playback.
///  - Suppresses pan activation while `Select` is pressed or within `180 ms` of a discrete click.
///  - Uses a `20 pt` (`~7.7%` of `260 pt`) initial breakaway with `1.35:1` horizontal axis lock,
///    followed by **zero (`0 pt`) reversal deadzone** and incremental duration-adaptive 3-zone
///    velocity scaling across the full timeline (eliminating the fixed `75 s` ceiling).
///  - Ring hold (`>= 280 ms` on `.leftArrow`/`.rightArrow`) drives progressive `30 -> 120 -> 300 s/s` seek.
public enum RemoteScrubMath: Sendable {
    public static let trackReferenceWidth: Double = 260.0
    public static let pauseBreakawayPoints: Double = 20.0
    public static let axisLockRatio: Double = 1.35
    public static let clickSuppressionWindowSeconds: TimeInterval = 0.18
    public static let velocitySmoothingAlpha: Double = 0.35
    public static let ringHoldThresholdSeconds: TimeInterval = 0.28

    /// Evaluates whether indirect clickpad movement should enter continuous touch-scrubbing.
    public static func shouldActivateTouchScrub(
        dx: Double,
        dy: Double,
        isPlaying: Bool,
        isSelectPressed: Bool,
        secondsSinceDiscreteClick: TimeInterval?
    ) -> Bool {
        guard !isPlaying, !isSelectPressed else {
            return false
        }
        if let elapsed = secondsSinceDiscreteClick,
           elapsed >= 0,
           elapsed < clickSuppressionWindowSeconds {
            return false
        }
        let absDx = abs(dx)
        let absDy = abs(dy)
        return absDx >= pauseBreakawayPoints && absDx >= absDy * axisLockRatio
    }

    /// Exponentially smoothed normalized swipe speed (`|pts/s| / 260 pt`), damped against 1-frame spikes.
    public static func smoothedSpeedNorm(
        previous: Double,
        velocityXPointsPerSecond: Double
    ) -> Double {
        let raw = max(0.0, abs(velocityXPointsPerSecond) / trackReferenceWidth)
        let safePrev = max(0.0, previous)
        return safePrev * (1.0 - velocitySmoothingAlpha) + raw * velocitySmoothingAlpha
    }

    /// Hermite smoothstep interpolation on `[edge0, edge1]`.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1.0 : 0.0 }
        let t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    /// Full `260 pt` swipe span scaled across 3 speed zones against total media duration (`seconds`).
    public static func secondsPerFullSwipe(
        durationSeconds: Double,
        speedNorm: Double
    ) -> Double {
        let dur = max(60.0, durationSeconds.isFinite ? durationSeconds : 60.0)
        let spd = max(0.0, speedNorm.isFinite ? speedNorm : 0.0)

        let zone1 = min(max(dur * 0.015, 18.0), 90.0)
        let zone2 = min(max(dur * 0.16, 150.0), 1620.0)
        let zone3 = min(max(dur * 0.32, 300.0), 3300.0)

        if spd <= 0.6 {
            return zone1
        }
        if spd <= 2.4 {
            let t = smoothstep(0.6, 2.4, spd)
            return zone1 + (zone2 - zone1) * t
        }
        let t = smoothstep(2.4, 4.0, spd)
        return zone2 + (zone3 - zone2) * t
    }

    /// Incremental frame-to-frame timeline delta (`pt -> seconds`) with zero reversal deadzone once active.
    public static func incrementalStepSeconds(
        stepDxPoints: Double,
        durationSeconds: Double,
        speedNorm: Double
    ) -> Double {
        guard stepDxPoints.isFinite, stepDxPoints != 0 else { return 0 }
        let span = secondsPerFullSwipe(durationSeconds: durationSeconds, speedNorm: speedNorm)
        return (stepDxPoints / trackReferenceWidth) * span
    }

    /// Progressive seek speed (seconds per held second) after crossing `ringHoldThresholdSeconds`.
    public static func ringHoldSpeedSecondsPerSecond(holdDurationSeconds: TimeInterval) -> Double {
        let elapsed = max(0.0, holdDurationSeconds)
        if elapsed < 1.1 {
            return 30.0
        }
        if elapsed < 2.9 {
            return 120.0
        }
        return 300.0
    }
}
