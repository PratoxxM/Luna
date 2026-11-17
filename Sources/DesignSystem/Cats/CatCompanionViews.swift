import Foundation
import SwiftUI

// MARK: - 1. Loading Curtain Tandem Running Cats

struct LoadingCatTrackView: View {
    @ObservedObject var comfort: ComfortPreferences
    let targetFraction: Double
    let isPreparingReveal: Bool
    var trackWidth: CGFloat = CatCompanionLayout.loadingTrackWidth

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interpolator: LoadingSprintInterpolator

    init(
        comfort: ComfortPreferences,
        targetFraction: Double,
        isPreparingReveal: Bool,
        trackWidth: CGFloat = CatCompanionLayout.loadingTrackWidth
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
                .frame(width: max(24, trackWidth * CGFloat(targetFraction)))
                .animation(.easeOut(duration: 0.28), value: targetFraction)
        }
        .frame(width: trackWidth, height: CatCompanionLayout.loadingTrackHeight)
    }

    private var staticCatsBar: some View {
        let positions = LoadingTrackPositions.compute(
            fraction: targetFraction,
            trackWidth: trackWidth
        )
        let poseBlack: CatPose = isPreparingReveal
            ? .pounceCrouch(wigglePhase: 0, crouchBlend: 1.0)
            : .prowling(stridePhase: 0.2, sniffProgress: 0)
        let poseTabby: CatPose = isPreparingReveal
            ? .pounceCrouch(wigglePhase: 0.25, crouchBlend: 1.0)
            : .prowling(stridePhase: 0.6, sniffProgress: 0)

        return trackLayout(
            positions: positions,
            sparkPulse: 0.5,
            tabbyPose: poseTabby,
            blackPose: poseBlack
        )
    }

    private func animatedTrackContent(
        now: TimeInterval,
        fraction: Double,
        isAdvancing: Bool,
        pounceBlend: Double
    ) -> some View {
        let positions = LoadingTrackPositions.compute(
            fraction: fraction,
            trackWidth: trackWidth
        )
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

        return trackLayout(
            positions: positions,
            sparkPulse: now * 4.2,
            tabbyPose: tabbyPose,
            blackPose: blackPose
        )
    }

    private func trackLayout(
        positions: LoadingTrackPositions,
        sparkPulse: Double,
        tabbyPose: CatPose,
        blackPose: CatPose
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
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
                    .frame(width: max(24, positions.sparkX))
            }
            .frame(width: trackWidth, height: CatCompanionLayout.loadingTrackHeight)
            .padding(.bottom, 14)

            MoonSparkView(pulse: sparkPulse)
                .position(x: positions.sparkX, y: 76.5)

            CatMascotCanvasView(kind: .brownTabby, pose: tabbyPose)
                .frame(
                    width: CatCompanionLayout.loadingTabbyCatSize.width,
                    height: CatCompanionLayout.loadingTabbyCatSize.height
                )
                .position(x: positions.tabbyCatX, y: 47.0)

            CatMascotCanvasView(kind: .blackNightFury, pose: blackPose)
                .frame(
                    width: CatCompanionLayout.loadingBlackCatSize.width,
                    height: CatCompanionLayout.loadingBlackCatSize.height
                )
                .position(x: positions.blackCatX, y: 45.5)
        }
        .frame(width: trackWidth, height: CatCompanionLayout.loadingContainerHeight, alignment: .bottomLeading)
    }
}

// MARK: - 2. Animated Genuine Illustrated Mascot Duo (Pause & Moon)

struct MascotCatsAnimatedDuoView: View {
    let size: CGSize
    let breathPhase: Double
    let blinkProgress: Double
    let shimmerPhase: Double

    private static let tabbyEyelidColor = Color(red: 132.0 / 255.0, green: 96.0 / 255.0, blue: 72.0 / 255.0)
    private static let blackEyelidColor = Color(red: 60.0 / 255.0, green: 52.0 / 255.0, blue: 65.0 / 255.0)

    var body: some View {
        let breath = sin(breathPhase)
        let scaleX = CGFloat(1.0 + breath * 0.009)
        let scaleY = CGFloat(1.0 - breath * 0.014)
        let blink = min(1.0, max(0.0, blinkProgress))
        let shimmerOpacity = 0.14 + 0.12 * sin(shimmerPhase * Double.pi * 2.0)

        ZStack {
            // Soft dark cinema backing so paws & fur separate cleanly over bright scenes
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.18),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: size.width * 0.56
                    )
                )
                .frame(width: size.width * 1.12, height: size.height * 0.92)
                .offset(y: size.height * 0.06)

            Image("MascotCatsDuo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .overlay {
                    // Subtle warm eye glint & moonlight rim shimmer
                    if blink < 0.35 {
                        eyeGlintOverlay(opacity: shimmerOpacity * (1.0 - blink))
                    }
                    // Periodic natural eye blink eyelids aligned to MascotCatsDuo pixel coordinates
                    if blink > 0.04 {
                        blinkEyelidsOverlay(blink: blink)
                    }
                }
                .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
                .shadow(color: Color.black.opacity(0.75), radius: 10, x: 0, y: 4)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func eyeGlintOverlay(opacity: Double) -> some View {
        Canvas { context, sz in
            let points = [
                CGPoint(x: sz.width * 0.292, y: sz.height * 0.220),
                CGPoint(x: sz.width * 0.402, y: sz.height * 0.220),
                CGPoint(x: sz.width * 0.546, y: sz.height * 0.181),
                CGPoint(x: sz.width * 0.665, y: sz.height * 0.183),
            ]
            for pt in points {
                let r = sz.width * 0.011
                let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(LunaTheme.focusGoldTop.opacity(opacity)))
            }
        }
    }

    private func blinkEyelidsOverlay(blink: Double) -> some View {
        Canvas { context, sz in
            let lids: [(nx: Double, ny: Double, nw: Double, nh: Double, color: Color)] = [
                (0.298, 0.229, 0.058, 0.042, Self.tabbyEyelidColor),
                (0.409, 0.229, 0.058, 0.042, Self.tabbyEyelidColor),
                (0.553, 0.189, 0.058, 0.046, Self.blackEyelidColor),
                (0.672, 0.191, 0.058, 0.042, Self.blackEyelidColor),
            ]
            for lid in lids {
                let w = sz.width * lid.nw
                let h = sz.height * lid.nh * blink
                let cx = sz.width * lid.nx
                let cy = sz.height * lid.ny
                let lidRect = CGRect(x: cx - w * 0.5, y: cy - h * 0.45, width: w, height: max(1.0, h))
                context.fill(Path(ellipseIn: lidRect), with: .color(lid.color.opacity(blink * 0.94)))

                var lash = Path()
                lash.move(to: CGPoint(x: cx - w * 0.45, y: cy + h * 0.05))
                lash.addQuadCurve(
                    to: CGPoint(x: cx + w * 0.45, y: cy + h * 0.05),
                    control: CGPoint(x: cx, y: cy + h * 0.45)
                )
                context.stroke(
                    lash,
                    with: .color(Color.black.opacity(0.68 * blink)),
                    style: StrokeStyle(lineWidth: max(1.2, sz.width * 0.008), lineCap: .round)
                )
            }
        }
    }
}

// MARK: - 3. Pause-Katt Atop Player Timeline (~200 pt Duo, Collision-Free)

struct PauseCatOverlayLeafView: View {
    @ObservedObject var comfort: ComfortPreferences
    let isPaused: Bool
    let isScrubbing: Bool
    let trackWidth: CGFloat
    let playheadX: CGFloat
    var onVisualActivityChanged: (Bool) -> Void = { _ in }

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
        let anchorX = PauseCatLifecycle.safeAnchorX(
            trackWidth: trackWidth,
            playheadX: playheadX,
            catWidth: CatCompanionLayout.pauseCatSize.width
        )
        let baseY = -(CatCompanionLayout.pauseCatSize.height - 5)

        Group {
            if phase != .hidden && comfort.showCatCompanions && !isScrubbing {
                if reduceMotion {
                    if let snap = PauseCatLifecycle.visualSnapshot(phase: phase, at: 0, reduceMotion: true) {
                        catView(snapshot: snap)
                            .offset(x: anchorX + snap.xOffset, y: baseY + snap.yOffset)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: activeMinimumInterval)) { context in
                        if let snap = PauseCatLifecycle.visualSnapshot(
                            phase: phase,
                            at: context.date.timeIntervalSinceReferenceDate,
                            reduceMotion: false
                        ) {
                            catView(snapshot: snap)
                                .offset(x: anchorX + snap.xOffset, y: baseY + snap.yOffset)
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: anchorX)
        .allowsHitTesting(false)
        .onChange(of: phase != .hidden) { _, visible in
            onVisualActivityChanged(visible && comfort.showCatCompanions && !isScrubbing)
        }
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
        ZStack(alignment: .topTrailing) {
            MascotCatsAnimatedDuoView(
                size: CatCompanionLayout.pauseCatSize,
                breathPhase: snapshot.breathPhase,
                blinkProgress: snapshot.blinkProgress,
                shimmerPhase: snapshot.shimmerPhase
            )

            if let zElapsed = snapshot.zzzElapsed {
                let floatOffset = reduceMotion ? 0.0 : sin(zElapsed * 1.9) * 5.0
                HStack(spacing: 3) {
                    Text("z")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.82))
                        .offset(y: CGFloat(4 - floatOffset * 0.6))
                    Text("Z")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(LunaTheme.amber)
                        .offset(y: CGFloat(-3 - floatOffset))
                    Text("z")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.74))
                        .offset(y: CGFloat(-9 - floatOffset * 0.8))
                }
                .shadow(color: Color.black.opacity(0.92), radius: 4, x: 0, y: 1)
                .offset(x: -10, y: 4)
            } else if snapshot.isAlertBadgeVisible {
                Text("!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(LunaTheme.amber)
                    .shadow(color: Color.black.opacity(0.90), radius: 4, x: 0, y: 1)
                    .offset(x: -20, y: -4)
            }
        }
        .opacity(snapshot.opacity)
    }
}

// MARK: - 4. Source Picker Prowling / Sniffing Cat

struct ProwlingSourceCatView: View {
    @ObservedObject var comfort: ComfortPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !comfort.showCatCompanions {
            ProgressView()
        } else if reduceMotion {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    CatMascotCanvasView(
                        kind: .blackNightFury,
                        pose: .prowling(stridePhase: 0.15, sniffProgress: 0.9)
                    )
                    .frame(
                        width: CatCompanionLayout.prowlingCatSize.width,
                        height: CatCompanionLayout.prowlingCatSize.height
                    )

                    Image(systemName: "sparkle")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(LunaTheme.amber.opacity(0.88))
                }
                ProgressView()
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                prowlingContent(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func prowlingContent(at now: TimeInterval) -> some View {
        let cycleDuration = 5.2
        let rawRem = now.truncatingRemainder(dividingBy: cycleDuration)
        let rem = rawRem < 0 ? rawRem + cycleDuration : rawRem
        let cycle = rem / cycleDuration
        let pos: Double
        let facingRight: Bool
        let sniff: Double

        if cycle < 0.34 {
            let p = cycle / 0.34
            pos = -136 + 272 * p
            facingRight = true
            sniff = 0
        } else if cycle < 0.50 {
            pos = 136
            facingRight = true
            let p = (cycle - 0.34) / 0.16
            sniff = sin(p * Double.pi)
        } else if cycle < 0.84 {
            let p = (cycle - 0.50) / 0.34
            pos = 136 - 272 * p
            facingRight = false
            sniff = 0
        } else {
            pos = -136
            facingRight = false
            let p = (cycle - 0.84) / 0.16
            sniff = sin(p * Double.pi)
        }

        let rawStride = (now * 1.4).truncatingRemainder(dividingBy: 1.0)
        let stride = rawStride < 0 ? rawStride + 1.0 : rawStride
        return VStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(LunaTheme.moonlight.opacity(0.14))
                    .frame(width: 420, height: 5)
                    .offset(y: 36)

                if sniff > 0.15 {
                    Image(systemName: "sparkle")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(LunaTheme.amber.opacity(sniff * 0.90))
                        .offset(x: CGFloat(pos + (facingRight ? 62 : -62)), y: 20)
                }

                CatMascotCanvasView(
                    kind: .blackNightFury,
                    pose: .prowling(stridePhase: stride, sniffProgress: sniff),
                    facingRight: facingRight
                )
                .frame(
                    width: CatCompanionLayout.prowlingCatSize.width,
                    height: CatCompanionLayout.prowlingCatSize.height
                )
                .offset(x: CGFloat(pos))
            }
            .frame(width: 460, height: 90)
        }
    }
}

// MARK: - 5. Library Empty-State Genuine Moon + Mascot Duo (~232 pt)

struct MoonSleepingCatView: View {
    @ObservedObject var comfort: ComfortPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if comfort.showCatCompanions {
            if reduceMotion {
                moonScene(breathPhase: 0.4, blinkProgress: 0, shimmerPhase: 0.4, zDrift: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    moonScene(
                        breathPhase: t * 1.35,
                        blinkProgress: PauseCatLifecycle.periodicBlinkProgress(elapsed: t),
                        shimmerPhase: (t * 0.45).truncatingRemainder(dividingBy: 1.0),
                        zDrift: sin(t * 1.5) * 4.5
                    )
                }
            }
        }
    }

    private func moonScene(
        breathPhase: Double,
        blinkProgress: Double,
        shimmerPhase: Double,
        zDrift: Double
    ) -> some View {
        ZStack {
            Circle()
                .fill(LunaTheme.amber.opacity(0.14))
                .frame(width: 224, height: 224)
                .blur(radius: 18)

            Image("LunaMoonCrescent")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: CatCompanionLayout.moonSceneSize.width, height: CatCompanionLayout.moonSceneSize.height)
                .shadow(color: LunaTheme.amber.opacity(0.32), radius: 14, x: 0, y: 2)

            MascotCatsAnimatedDuoView(
                size: CatCompanionLayout.moonCatSize,
                breathPhase: breathPhase,
                blinkProgress: blinkProgress,
                shimmerPhase: shimmerPhase
            )
            .offset(
                x: CatCompanionLayout.moonCatOffset.width,
                y: CatCompanionLayout.moonCatOffset.height
            )

            HStack(spacing: 3) {
                Text("z")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.76))
                    .offset(y: CGFloat(4 - zDrift * 0.5))
                Text("Z")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(LunaTheme.amber.opacity(0.95))
                    .offset(y: CGFloat(-3 - zDrift))
            }
            .shadow(color: Color.black.opacity(0.85), radius: 3, x: 0, y: 1)
            .offset(x: 68, y: -56)

            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LunaTheme.amber.opacity(0.85))
                .offset(x: -74, y: -74)

            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LunaTheme.moonlight.opacity(0.65))
                .offset(x: 76, y: -78)
        }
        .frame(
            width: CatCompanionLayout.moonSceneSize.width,
            height: CatCompanionLayout.moonSceneSize.height
        )
        .allowsHitTesting(false)
    }
}
