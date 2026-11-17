import Foundation
import SwiftUI

public enum CatSpriteKind: String, Sendable {
    case blackNightFury
    case brownTabby
}

public enum CatPose: Equatable, Sendable {
    case running(stridePhase: Double, sprintIntensity: Double)
    case pounceCrouch(wigglePhase: Double, crouchBlend: Double)
    case prowling(stridePhase: Double, sniffProgress: Double)
    case stretching(progress: Double)
    case curledSleeping(breathPhase: Double)
    case alertPerk(hopProgress: Double)
}

public enum CatCompanionLayout: Sendable {
    public static let loadingTrackWidth: CGFloat = 640
    public static let loadingTrackHeight: CGFloat = 7
    public static let loadingContainerHeight: CGFloat = 94
    public static let loadingBlackCatSize = CGSize(width: 96, height: 67)
    public static let loadingTabbyCatSize = CGSize(width: 92, height: 64)
    public static let loadingBlackOffset: CGFloat = 54
    public static let loadingTabbySpacing: CGFloat = 88
    /// Hero-scale (~200 pt) illustrated two-cat duo perched on the paused timeline bar.
    public static let pauseCatSize = CGSize(width: 204, height: 194)
    public static let prowlingCatSize = CGSize(width: 122, height: 85)
    /// ~230 pt illustrated crescent moon + mascot duo empty state.
    public static let moonSceneSize = CGSize(width: 232, height: 232)
    public static let moonCatSize = CGSize(width: 152, height: 144)
    public static let moonCatOffset = CGSize(width: 24.2, height: 13.6)
    public static let playheadDiameter: CGFloat = 24
    public static let playheadEarsSize = CGSize(width: 28, height: 14)
}

/// Computes clamped horizontal centers along `LoadingCatTrackView` so neither
/// running cat ever clips off the left or right bounds of the 640 pt loading bar.
public struct LoadingTrackPositions: Equatable, Sendable {
    public let sparkX: CGFloat
    public let blackCatX: CGFloat
    public let tabbyCatX: CGFloat

    public static func compute(
        fraction: Double,
        trackWidth: CGFloat = CatCompanionLayout.loadingTrackWidth,
        blackCatSize: CGSize = CatCompanionLayout.loadingBlackCatSize,
        tabbyCatSize: CGSize = CatCompanionLayout.loadingTabbyCatSize,
        blackOffset: CGFloat = CatCompanionLayout.loadingBlackOffset,
        tabbySpacing: CGFloat = CatCompanionLayout.loadingTabbySpacing
    ) -> LoadingTrackPositions {
        let clampedFraction = min(1.0, max(0.0, fraction))
        let rawSparkX = max(24.0, trackWidth * CGFloat(clampedFraction))
        let tabbyHalf = tabbyCatSize.width * 0.5
        let blackHalf = blackCatSize.width * 0.5

        let minTabbyX = tabbyHalf
        let minBlackX = max(blackHalf, minTabbyX + 48.0)
        let maxBlackX = max(minBlackX, trackWidth - blackHalf)

        let blackCatX = min(maxBlackX, max(minBlackX, rawSparkX - blackOffset))
        let tabbyCatX = max(minTabbyX, blackCatX - tabbySpacing)
        let sparkX = min(trackWidth, max(rawSparkX, blackCatX + 36.0))

        return LoadingTrackPositions(
            sparkX: sparkX,
            blackCatX: blackCatX,
            tabbyCatX: tabbyCatX
        )
    }
}

public struct LoadingSprintInterpolator: Equatable, Sendable {
    public private(set) var anchorFraction: Double
    public private(set) var anchorTimestamp: TimeInterval
    public private(set) var goalFraction: Double
    public private(set) var duration: TimeInterval

    public init(
        anchorFraction: Double,
        anchorTimestamp: TimeInterval,
        goalFraction: Double,
        duration: TimeInterval
    ) {
        self.anchorFraction = anchorFraction
        self.anchorTimestamp = anchorTimestamp
        self.goalFraction = goalFraction
        self.duration = duration
    }

    public static func makeInitial(targetFraction: Double, now: TimeInterval) -> LoadingSprintInterpolator {
        let clampedGoal = min(0.99, max(0.14, targetFraction))
        let start = min(0.12, clampedGoal)
        return LoadingSprintInterpolator(
            anchorFraction: start,
            anchorTimestamp: now,
            goalFraction: clampedGoal,
            duration: sprintDuration(from: start, to: clampedGoal)
        )
    }

    public static func sprintDuration(from start: Double, to end: Double) -> TimeInterval {
        let delta = max(0, end - start)
        if delta < 0.01 {
            return 0.06
        }
        return min(0.70, max(0.32, delta * 0.78))
    }

    public mutating func updateGoal(_ newTarget: Double, now: TimeInterval) {
        let current = fraction(at: now)
        let clampedGoal = min(0.99, max(current, newTarget))
        anchorFraction = current
        anchorTimestamp = now
        goalFraction = clampedGoal
        duration = Self.sprintDuration(from: current, to: clampedGoal)
    }

    public func fraction(at now: TimeInterval) -> Double {
        guard duration > 0 else { return goalFraction }
        let elapsed = max(0, now - anchorTimestamp)
        let t = min(1.0, elapsed / duration)
        let eased = 1.0 - pow(1.0 - t, 3.0)
        return anchorFraction + (goalFraction - anchorFraction) * eased
    }

    public func isAdvancing(at now: TimeInterval) -> Bool {
        (now - anchorTimestamp) < duration && (goalFraction - anchorFraction) > 0.015
    }

    public func pounceBlend(at now: TimeInterval, isPreparingReveal: Bool) -> Double {
        guard isPreparingReveal, !isAdvancing(at: now) else {
            return 0
        }
        let settledFor = max(0, now - (anchorTimestamp + duration))
        return min(1.0, settledFor / 0.22)
    }
}

public enum PauseCatPhase: Equatable, Sendable {
    case hidden
    case active(enteredAt: TimeInterval)
    case scamperingOff(startedAt: TimeInterval)
}

public struct PauseCatSnapshot: Equatable, Sendable {
    public let xOffset: CGFloat
    public let yOffset: CGFloat
    public let opacity: Double
    public let pose: CatPose
    public let facingRight: Bool
    public let zzzElapsed: TimeInterval?
    public let breathPhase: Double
    public let blinkProgress: Double
    public let shimmerPhase: Double
    public let isAlertBadgeVisible: Bool
}

public enum PauseCatLifecycle: Sendable {
    public static let idleThresholdSeconds: TimeInterval = 6.0
    public static let strollDuration: TimeInterval = 1.9
    public static let stretchDuration: TimeInterval = 1.4
    public static let perkDuration: TimeInterval = 0.24
    public static let scamperDuration: TimeInterval = 0.85
    public static let activeAnimationInterval: TimeInterval = 1.0 / 30.0
    public static let sleepingAnimationInterval: TimeInterval = 1.0 / 12.0

    public static func centeredAnchorX(
        trackWidth: CGFloat,
        catWidth: CGFloat = CatCompanionLayout.pauseCatSize.width
    ) -> CGFloat {
        let maxAnchor = max(0, trackWidth - catWidth)
        let centered = (trackWidth - catWidth) * 0.5
        let safeMargin = min(maxAnchor, max(0, trackWidth > 640 ? 220 : 0))
        return min(maxAnchor, max(safeMargin, centered))
    }

    /// Computes a collision-free horizontal anchor along the player timeline bar,
    /// dynamically shifting left or right away from `playheadX` whenever the playhead
    /// knob sits near the center perch.
    public static func safeAnchorX(
        trackWidth: CGFloat,
        playheadX: CGFloat,
        catWidth: CGFloat = CatCompanionLayout.pauseCatSize.width,
        playheadClearance: CGFloat = 34
    ) -> CGFloat {
        let maxAnchor = max(0, trackWidth - catWidth)
        let centerAnchor = centeredAnchorX(trackWidth: trackWidth, catWidth: catWidth)
        let knobMin = playheadX - playheadClearance
        let knobMax = playheadX + playheadClearance

        let overlapsCenter = (centerAnchor + catWidth) > knobMin && centerAnchor < knobMax
        guard overlapsCenter, trackWidth >= catWidth + playheadClearance * 2 + 40 else {
            return centerAnchor
        }

        let safeEdgeMargin = min(maxAnchor * 0.45, trackWidth > 900 ? 280.0 : 40.0)
        let minAllowed = min(maxAnchor, safeEdgeMargin)
        let maxAllowed = max(minAllowed, maxAnchor - safeEdgeMargin)

        let rightCandidate = playheadX + playheadClearance
        let leftCandidate = playheadX - playheadClearance - catWidth

        if playheadX <= trackWidth * 0.5 {
            if rightCandidate <= maxAllowed {
                return max(minAllowed, rightCandidate)
            }
            return min(maxAllowed, max(minAllowed, leftCandidate))
        } else {
            if leftCandidate >= minAllowed {
                return min(maxAllowed, leftCandidate)
            }
            return min(maxAllowed, max(minAllowed, rightCandidate))
        }
    }

    public static var activeSettleToNapSeconds: TimeInterval {
        strollDuration + stretchDuration
    }

    public static func timelineMinimumInterval(
        phase: PauseCatPhase,
        at now: TimeInterval
    ) -> TimeInterval {
        switch phase {
        case .hidden:
            return sleepingAnimationInterval
        case .active(let enteredAt):
            let elapsed = max(0, now - enteredAt)
            return elapsed >= activeSettleToNapSeconds
                ? sleepingAnimationInterval
                : activeAnimationInterval
        case .scamperingOff:
            return activeAnimationInterval
        }
    }

    /// Periodic blink factor in `0...1` (0 = eyes open, 1 = gentle blink closed) every ~4.4 s.
    public static func periodicBlinkProgress(elapsed: TimeInterval) -> Double {
        let cycle = 4.4
        let rem = elapsed.truncatingRemainder(dividingBy: cycle)
        let phase = rem < 0 ? rem + cycle : rem
        let blinkWindow = 0.24
        guard phase < blinkWindow else { return 0 }
        return sin((phase / blinkWindow) * Double.pi)
    }

    public static func visualSnapshot(
        phase: PauseCatPhase,
        at now: TimeInterval,
        reduceMotion: Bool = false
    ) -> PauseCatSnapshot? {
        switch phase {
        case .hidden:
            return nil

        case .active(let enteredAt):
            if reduceMotion {
                return PauseCatSnapshot(
                    xOffset: 0,
                    yOffset: 0,
                    opacity: 1.0,
                    pose: .curledSleeping(breathPhase: 0.4),
                    facingRight: false,
                    zzzElapsed: 0.5,
                    breathPhase: 0.4,
                    blinkProgress: 0,
                    shimmerPhase: 0.5,
                    isAlertBadgeVisible: false
                )
            }
            let elapsed = max(0, now - enteredAt)
            let breath = elapsed * 1.65
            let blink = periodicBlinkProgress(elapsed: elapsed)
            let shimmer = (elapsed * 0.55).truncatingRemainder(dividingBy: 1.0)

            if elapsed < strollDuration {
                let p = elapsed / strollDuration
                let smooth = p * p * (3.0 - 2.0 * p)
                let fade = min(1.0, elapsed / 0.35)
                let stride = (elapsed * 1.45).truncatingRemainder(dividingBy: 1.0)
                let hopY = -CGFloat(abs(sin(p * Double.pi * 3.0)) * 8.0 * (1.0 - p))
                return PauseCatSnapshot(
                    xOffset: CGFloat((1.0 - smooth) * 116.0),
                    yOffset: hopY,
                    opacity: fade,
                    pose: .prowling(stridePhase: stride, sniffProgress: 0),
                    facingRight: false,
                    zzzElapsed: nil,
                    breathPhase: breath,
                    blinkProgress: 0,
                    shimmerPhase: shimmer,
                    isAlertBadgeVisible: false
                )
            }
            let afterStroll = elapsed - strollDuration
            if afterStroll < stretchDuration {
                let p = afterStroll / stretchDuration
                return PauseCatSnapshot(
                    xOffset: 0,
                    yOffset: 0,
                    opacity: 1.0,
                    pose: .stretching(progress: p),
                    facingRight: false,
                    zzzElapsed: nil,
                    breathPhase: breath,
                    blinkProgress: blink * 0.5,
                    shimmerPhase: shimmer,
                    isAlertBadgeVisible: false
                )
            }
            let napElapsed = afterStroll - stretchDuration
            return PauseCatSnapshot(
                xOffset: 0,
                yOffset: 0,
                opacity: 1.0,
                pose: .curledSleeping(breathPhase: napElapsed * 1.75),
                facingRight: false,
                zzzElapsed: napElapsed,
                breathPhase: breath,
                blinkProgress: blink,
                shimmerPhase: shimmer,
                isAlertBadgeVisible: false
            )

        case .scamperingOff(let startedAt):
            if reduceMotion {
                return nil
            }
            let elapsed = max(0, now - startedAt)
            if elapsed >= scamperDuration {
                return nil
            }
            if elapsed < perkDuration {
                let p = elapsed / perkDuration
                let hopY = -CGFloat(sin(p * Double.pi) * 16.0)
                return PauseCatSnapshot(
                    xOffset: 0,
                    yOffset: hopY,
                    opacity: 1.0,
                    pose: .alertPerk(hopProgress: p),
                    facingRight: false,
                    zzzElapsed: nil,
                    breathPhase: 0,
                    blinkProgress: 0,
                    shimmerPhase: 0,
                    isAlertBadgeVisible: true
                )
            }
            let runElapsed = elapsed - perkDuration
            let runWindow = max(0.01, scamperDuration - perkDuration)
            let p = min(1.0, runElapsed / runWindow)
            let stride = (runElapsed * 3.1).truncatingRemainder(dividingBy: 1.0)
            let fade = max(0.0, 1.0 - max(0.0, (p - 0.55) / 0.45))
            let boundY = -CGFloat(abs(sin(p * Double.pi * 2.5)) * 13.0)
            return PauseCatSnapshot(
                xOffset: CGFloat(p * p * 145.0),
                yOffset: boundY,
                opacity: fade,
                pose: .running(stridePhase: stride, sprintIntensity: 0.9),
                facingRight: true,
                zzzElapsed: nil,
                breathPhase: 0,
                blinkProgress: 0,
                shimmerPhase: 0,
                isAlertBadgeVisible: false
            )
        }
    }
}
