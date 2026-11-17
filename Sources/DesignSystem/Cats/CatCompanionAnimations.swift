import Foundation
import SwiftUI

// MARK: - Pure Sprint & Pause State Machines (Unit-Tested, Zero View-Body Mutations)

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
        let clampedGoal = min(0.99, max(0.08, targetFraction))
        let start = min(0.06, clampedGoal)
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
    public let opacity: Double
    public let pose: CatPose
    public let facingRight: Bool
    public let zzzElapsed: TimeInterval?
    public let isAlertBadgeVisible: Bool
}

public enum PauseCatLifecycle: Sendable {
    public static let idleThresholdSeconds: TimeInterval = 20.0
    public static let strollDuration: TimeInterval = 1.9
    public static let stretchDuration: TimeInterval = 1.4
    public static let perkDuration: TimeInterval = 0.24
    public static let scamperDuration: TimeInterval = 0.85
    public static let activeAnimationInterval: TimeInterval = 1.0 / 30.0
    public static let sleepingAnimationInterval: TimeInterval = 1.0 / 12.0

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
                    opacity: 1.0,
                    pose: .curledSleeping(breathPhase: 0.4),
                    facingRight: false,
                    zzzElapsed: 0.5,
                    isAlertBadgeVisible: false
                )
            }
            let elapsed = max(0, now - enteredAt)
            if elapsed < strollDuration {
                let p = elapsed / strollDuration
                let smooth = p * p * (3.0 - 2.0 * p)
                let fade = min(1.0, elapsed / 0.35)
                let stride = (elapsed * 1.45).truncatingRemainder(dividingBy: 1.0)
                return PauseCatSnapshot(
                    xOffset: CGFloat((1.0 - smooth) * 116.0),
                    opacity: fade,
                    pose: .prowling(stridePhase: stride, sniffProgress: 0),
                    facingRight: false,
                    zzzElapsed: nil,
                    isAlertBadgeVisible: false
                )
            }
            let afterStroll = elapsed - strollDuration
            if afterStroll < stretchDuration {
                let p = afterStroll / stretchDuration
                return PauseCatSnapshot(
                    xOffset: 0,
                    opacity: 1.0,
                    pose: .stretching(progress: p),
                    facingRight: false,
                    zzzElapsed: nil,
                    isAlertBadgeVisible: false
                )
            }
            let napElapsed = afterStroll - stretchDuration
            return PauseCatSnapshot(
                xOffset: 0,
                opacity: 1.0,
                pose: .curledSleeping(breathPhase: napElapsed * 1.75),
                facingRight: false,
                zzzElapsed: napElapsed,
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
                return PauseCatSnapshot(
                    xOffset: 0,
                    opacity: 1.0,
                    pose: .alertPerk(hopProgress: p),
                    facingRight: false,
                    zzzElapsed: nil,
                    isAlertBadgeVisible: true
                )
            }
            let runElapsed = elapsed - perkDuration
            let runWindow = max(0.01, scamperDuration - perkDuration)
            let p = min(1.0, runElapsed / runWindow)
            let stride = (runElapsed * 3.1).truncatingRemainder(dividingBy: 1.0)
            let fade = max(0.0, 1.0 - max(0.0, (p - 0.55) / 0.45))
            return PauseCatSnapshot(
                xOffset: CGFloat(p * p * 145.0),
                opacity: fade,
                pose: .running(stridePhase: stride, sprintIntensity: 0.9),
                facingRight: true,
                zzzElapsed: nil,
                isAlertBadgeVisible: false
            )
        }
    }
}

// MARK: - 1. Loading Curtain Tandem Running Cats

struct LoadingCatTrackView: View {
    @ObservedObject var comfort: ComfortPreferences
    let targetFraction: Double
    let isPreparingReveal: Bool
    var trackWidth: CGFloat = 440

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interpolator: LoadingSprintInterpolator

    init(
        comfort: ComfortPreferences,
        targetFraction: Double,
        isPreparingReveal: Bool,
        trackWidth: CGFloat = 440
    ) {
        self.comfort = comfort
        self.targetFraction = targetFraction
        self.isPreparingReveal = isPreparingReveal
        self.trackWidth = trackWidth
        _interpolator = State(
            initialValue: LoadingSprintInterpolator.makeInitial(
                targetFraction: targetFraction,
                now: Date().timeIntervalSinceReferenceDate
            )
        )
    }

    var body: some View {
        Group {
            if !comfort.showCatCompanions {
                standardBarOnly
            } else if reduceMotion {
                staticCatsBar
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let now = context.date.timeIntervalSinceReferenceDate
                    let fraction = interpolator.fraction(at: now)
                    let advancing = interpolator.isAdvancing(at: now)
                    let pounceBlend = interpolator.pounceBlend(at: now, isPreparingReveal: isPreparingReveal)
                    animatedTrackContent(
                        now: now,
                        fraction: fraction,
                        isAdvancing: advancing,
                        pounceBlend: pounceBlend
                    )
                }
            }
        }
        .onChange(of: targetFraction) { _, newValue in
            interpolator.updateGoal(newValue, now: Date().timeIntervalSinceReferenceDate)
        }
    }

    private var standardBarOnly: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.14))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [LunaTheme.amber, LunaTheme.amberDeep],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(20, trackWidth * CGFloat(targetFraction)))
                .animation(.easeOut(duration: 0.28), value: targetFraction)
        }
        .frame(width: trackWidth, height: 4)
    }

    private var staticCatsBar: some View {
        let sparkX = trackWidth * CGFloat(targetFraction)
        let blackX = sparkX - 28
        let tabbyX = blackX - 38
        let poseBlack: CatPose = isPreparingReveal
            ? .pounceCrouch(wigglePhase: 0, crouchBlend: 1.0)
            : .prowling(stridePhase: 0.2, sniffProgress: 0)
        let poseTabby: CatPose = isPreparingReveal
            ? .pounceCrouch(wigglePhase: 0.25, crouchBlend: 1.0)
            : .prowling(stridePhase: 0.6, sniffProgress: 0)

        return ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [LunaTheme.amber, LunaTheme.amberDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(20, sparkX))
            }
            .frame(width: trackWidth, height: 4.5)
            .padding(.bottom, 7)

            MoonSparkView(pulse: 0.5)
                .position(x: sparkX, y: 36.75)

            CatMascotCanvasView(kind: .brownTabby, pose: poseTabby)
                .frame(width: 44, height: 31)
                .position(x: tabbyX, y: 21.0)

            CatMascotCanvasView(kind: .blackNightFury, pose: poseBlack)
                .frame(width: 46, height: 32)
                .position(x: blackX, y: 20.5)
        }
        .frame(width: trackWidth, height: 46, alignment: .bottomLeading)
    }

    private func animatedTrackContent(
        now: TimeInterval,
        fraction: Double,
        isAdvancing: Bool,
        pounceBlend: Double
    ) -> some View {
        let sparkX = trackWidth * CGFloat(fraction)
        let blackCatX = sparkX - 28
        let tabbyCatX = blackCatX - 38

        let gallopRate = isAdvancing ? 2.85 : 1.75
        let strideA = (now * gallopRate).truncatingRemainder(dividingBy: 1.0)
        let strideB = (now * gallopRate + 0.34).truncatingRemainder(dividingBy: 1.0)
        let sprintBoost = isAdvancing ? 1.0 : 0.25

        let blackPose: CatPose = pounceBlend > 0.05
            ? .pounceCrouch(wigglePhase: now, crouchBlend: pounceBlend)
            : .running(stridePhase: strideA, sprintIntensity: sprintBoost)

        let tabbyPose: CatPose = pounceBlend > 0.05
            ? .pounceCrouch(wigglePhase: now + 0.18, crouchBlend: pounceBlend)
            : .running(stridePhase: strideB, sprintIntensity: sprintBoost)

        return ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [LunaTheme.amber, LunaTheme.amberDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(18, sparkX))
            }
            .frame(width: trackWidth, height: 4.5)
            .padding(.bottom, 7)

            MoonSparkView(pulse: now * 4.2)
                .position(x: sparkX, y: 36.75)

            CatMascotCanvasView(kind: .brownTabby, pose: tabbyPose)
                .frame(width: 44, height: 31)
                .position(x: tabbyCatX, y: 21.0)

            CatMascotCanvasView(kind: .blackNightFury, pose: blackPose)
                .frame(width: 46, height: 32)
                .position(x: blackCatX, y: 20.5)
        }
        .frame(width: trackWidth, height: 46, alignment: .bottomLeading)
    }
}

// MARK: - 2. Pause-Katt Atop Player Timeline

struct PauseCatOverlayLeafView: View {
    @ObservedObject var comfort: ComfortPreferences
    let isPaused: Bool
    let isScrubbing: Bool
    let trackWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: PauseCatPhase = .hidden
    @State private var isSettledNapping: Bool = false

    private struct IdleTaskKey: Equatable {
        let enabled: Bool
        let isPaused: Bool
        let isScrubbing: Bool
    }

    private var activeMinimumInterval: TimeInterval {
        if case .active = phase, isSettledNapping {
            return PauseCatLifecycle.sleepingAnimationInterval
        }
        return PauseCatLifecycle.activeAnimationInterval
    }

    var body: some View {
        let anchorX = max(trackWidth * 0.50, min(trackWidth * 0.58, trackWidth - 660))

        Group {
            if phase != .hidden && comfort.showCatCompanions && !isScrubbing {
                if reduceMotion {
                    if let snap = PauseCatLifecycle.visualSnapshot(phase: phase, at: 0, reduceMotion: true) {
                        catView(snapshot: snap)
                            .offset(x: anchorX + snap.xOffset, y: -33)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: activeMinimumInterval)) { context in
                        if let snap = PauseCatLifecycle.visualSnapshot(
                            phase: phase,
                            at: context.date.timeIntervalSinceReferenceDate,
                            reduceMotion: false
                        ) {
                            catView(snapshot: snap)
                                .offset(x: anchorX + snap.xOffset, y: -33)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: IdleTaskKey(enabled: comfort.showCatCompanions, isPaused: isPaused, isScrubbing: isScrubbing)) {
            guard comfort.showCatCompanions, !isScrubbing else {
                isSettledNapping = false
                phase = .hidden
                return
            }
            if isPaused {
                if case .active(let enteredAt) = phase {
                    let remainingToNap = (enteredAt + PauseCatLifecycle.activeSettleToNapSeconds)
                        - Date().timeIntervalSinceReferenceDate
                    if reduceMotion {
                        isSettledNapping = true
                    } else if remainingToNap > 0 {
                        isSettledNapping = false
                        try? await Task.sleep(nanoseconds: UInt64(remainingToNap * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        isSettledNapping = true
                    } else {
                        isSettledNapping = true
                    }
                    return
                }
                isSettledNapping = false
                phase = .hidden
                try? await Task.sleep(nanoseconds: UInt64(PauseCatLifecycle.idleThresholdSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                phase = .active(enteredAt: Date().timeIntervalSinceReferenceDate)
                if reduceMotion {
                    isSettledNapping = true
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(PauseCatLifecycle.activeSettleToNapSeconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    isSettledNapping = true
                }
            } else {
                isSettledNapping = false
                if case .active = phase {
                    if reduceMotion {
                        phase = .hidden
                        return
                    }
                    phase = .scamperingOff(startedAt: Date().timeIntervalSinceReferenceDate)
                    try? await Task.sleep(nanoseconds: UInt64(PauseCatLifecycle.scamperDuration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    phase = .hidden
                } else {
                    phase = .hidden
                }
            }
        }
    }

    private func catView(snapshot: PauseCatSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            CatMascotCanvasView(
                kind: .brownTabby,
                pose: snapshot.pose,
                facingRight: snapshot.facingRight
            )
            .frame(width: 54, height: 38)

            if let zElapsed = snapshot.zzzElapsed {
                let floatOffset = reduceMotion ? 0.0 : sin(zElapsed * 1.9) * 3.0
                HStack(spacing: 1) {
                    Text("z")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.62))
                        .offset(y: CGFloat(2 - floatOffset * 0.6))
                    Text("Z")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LunaTheme.amber.opacity(0.84))
                        .offset(y: CGFloat(-2 - floatOffset))
                    Text("z")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.55))
                        .offset(y: CGFloat(-5 - floatOffset * 0.8))
                }
                .offset(x: 6, y: -7)
            } else if snapshot.isAlertBadgeVisible {
                Text("!")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(LunaTheme.amber)
                    .offset(x: 11, y: -10)
            }
        }
        .opacity(snapshot.opacity)
    }
}

// MARK: - 3. Source Picker Prowling / Sniffing Cat

struct ProwlingSourceCatView: View {
    @ObservedObject var comfort: ComfortPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !comfort.showCatCompanions {
            ProgressView()
        } else if reduceMotion {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    CatMascotCanvasView(
                        kind: .blackNightFury,
                        pose: .prowling(stridePhase: 0.15, sniffProgress: 0.9)
                    )
                    .frame(width: 66, height: 46)

                    Image(systemName: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LunaTheme.amber.opacity(0.8))
                }
                ProgressView()
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let cycle = t.truncatingRemainder(dividingBy: 5.2) / 5.2
                // Walk right -> sniff -> walk left -> sniff
                let pos: Double
                let facingRight: Bool
                let sniff: Double

                if cycle < 0.34 {
                    let p = cycle / 0.34
                    pos = -80 + 160 * p
                    facingRight = true
                    sniff = 0
                } else if cycle < 0.50 {
                    pos = 80
                    facingRight = true
                    let p = (cycle - 0.34) / 0.16
                    sniff = sin(p * Double.pi)
                } else if cycle < 0.84 {
                    let p = (cycle - 0.50) / 0.34
                    pos = 80 - 160 * p
                    facingRight = false
                    sniff = 0
                } else {
                    pos = -80
                    facingRight = false
                    let p = (cycle - 0.84) / 0.16
                    sniff = sin(p * Double.pi)
                }

                let stride = (t * 1.4).truncatingRemainder(dividingBy: 1.0)
                VStack(spacing: 8) {
                    ZStack {
                        Capsule()
                            .fill(LunaTheme.moonlight.opacity(0.08))
                            .frame(width: 240, height: 3)
                            .offset(y: 19)

                        if sniff > 0.15 {
                            Image(systemName: "sparkle")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(LunaTheme.amber.opacity(sniff * 0.85))
                                .offset(x: CGFloat(pos + (facingRight ? 34 : -34)), y: 12)
                        }

                        CatMascotCanvasView(
                            kind: .blackNightFury,
                            pose: .prowling(stridePhase: stride, sniffProgress: sniff),
                            facingRight: facingRight
                        )
                        .frame(width: 66, height: 46)
                        .offset(x: CGFloat(pos))
                    }
                    .frame(width: 260, height: 48)
                }
            }
        }
    }
}

// MARK: - 4. Library Empty-State Sleeping Cat Curled in Crescent Moon

struct MoonSleepingCatView: View {
    @ObservedObject var comfort: ComfortPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if comfort.showCatCompanions {
            if reduceMotion {
                moonScene(breathPhase: 0.4, zDrift: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    moonScene(
                        breathPhase: t * 1.35,
                        zDrift: sin(t * 1.5) * 3.0
                    )
                }
            }
        }
    }

    private func moonScene(breathPhase: Double, zDrift: Double) -> some View {
        ZStack {
            // Soft amber crescent moon aura
            Circle()
                .fill(LunaTheme.amber.opacity(0.09))
                .frame(width: 138, height: 138)
                .blur(radius: 10)

            // Crescent moon silhouette (exact two-circle intersection for crisp horns)
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let c1 = CGPoint(x: w * 0.48, y: h * 0.50)
                let bigR = min(w, h) * 0.42
                let c2 = CGPoint(x: c1.x + bigR * 0.34, y: c1.y - bigR * 0.14)
                let smallR = bigR * 0.82

                let dx = c2.x - c1.x
                let dy = c2.y - c1.y
                let dist = max(0.001, hypot(dx, dy))
                let a = (bigR * bigR - smallR * smallR + dist * dist) / (2.0 * dist)
                let hLen = sqrt(max(0.0, bigR * bigR - a * a))
                let mx = c1.x + (a / dist) * dx
                let my = c1.y + (a / dist) * dy
                let px = -dy / dist
                let py = dx / dist

                let bottomHorn = CGPoint(x: mx + hLen * px, y: my + hLen * py)
                let topHorn = CGPoint(x: mx - hLen * px, y: my - hLen * py)

                let outerStart = Angle(radians: Double(atan2(bottomHorn.y - c1.y, bottomHorn.x - c1.x)))
                let outerEnd = Angle(radians: Double(atan2(topHorn.y - c1.y, topHorn.x - c1.x)))
                let innerStart = Angle(radians: Double(atan2(topHorn.y - c2.y, topHorn.x - c2.x)))
                let innerEnd = Angle(radians: Double(atan2(bottomHorn.y - c2.y, bottomHorn.x - c2.x)))

                let moonPath = Path { path in
                    path.addArc(
                        center: c1,
                        radius: bigR,
                        startAngle: outerStart,
                        endAngle: outerEnd,
                        clockwise: false
                    )
                    path.addArc(
                        center: c2,
                        radius: smallR,
                        startAngle: innerStart,
                        endAngle: innerEnd,
                        clockwise: true
                    )
                    path.closeSubpath()
                }
                context.fill(
                    moonPath,
                    with: .linearGradient(
                        Gradient(colors: [LunaTheme.amber.opacity(0.92), LunaTheme.amberDeep.opacity(0.88)]),
                        startPoint: CGPoint(x: c1.x - bigR, y: c1.y - bigR),
                        endPoint: CGPoint(x: c1.x + bigR * 0.5, y: c1.y + bigR)
                    )
                )
            }
            .frame(width: 144, height: 144)

            // Sleeping mascot cat curled snugly inside the crescent curve
            CatMascotCanvasView(
                kind: .blackNightFury,
                pose: .curledSleeping(breathPhase: breathPhase)
            )
            .frame(width: 72, height: 50)
            .offset(x: 7, y: 19)

            // Soft muted twinkle stars & zZz
            HStack(spacing: 2) {
                Text("z")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.55))
                    .offset(y: CGFloat(3 - zDrift * 0.5))
                Text("Z")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(LunaTheme.amber.opacity(0.80))
                    .offset(y: CGFloat(-2 - zDrift))
            }
            .offset(x: 36, y: -10)

            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LunaTheme.amber.opacity(0.65))
                .offset(x: -44, y: -44)

            Image(systemName: "sparkle")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(LunaTheme.moonlight.opacity(0.45))
                .offset(x: 44, y: -46)
        }
        .frame(width: 148, height: 148)
        .allowsHitTesting(false)
    }
}
