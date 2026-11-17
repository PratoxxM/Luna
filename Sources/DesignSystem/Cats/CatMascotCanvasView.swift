import Foundation
import SwiftUI
import CoreGraphics

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

/// Pure vector Canvas mascot renderer faithful to Luna's two AppIcon cats:
/// - `blackNightFury`: moonlit twilight plum-charcoal coat (`#38334D`), clear white chest heart, golden eyes, and scarlet Toothless tail fin (`#E63833`).
/// - `brownTabby`: golden-cinnamon striped tabby (`#946942`) with cream muzzle/chest bib, white socks, and olive-hazel green eyes (`#85A657`).
/// Zero `@State` mutations; renders smoothly at 4K tvOS resolution in OLED/HDR-safe tones.
struct CatMascotCanvasView: View {
    let kind: CatSpriteKind
    let pose: CatPose
    var facingRight: Bool = true

    var body: some View {
        let spriteKind = kind
        let spritePose = pose
        let isFacingRight = facingRight

        Canvas { context, size in
            let scale = min(size.width / 80.0, size.height / 56.0)
            guard scale > 0.01 else { return }

            context.drawLayer { ctx in
                let xInset = (size.width - 80.0 * scale) * 0.5
                let yInset = (size.height - 56.0 * scale) * 0.5
                ctx.translateBy(x: xInset, y: yInset)
                ctx.scaleBy(x: scale, y: scale)

                if !isFacingRight {
                    ctx.translateBy(x: 80.0, y: 0)
                    ctx.scaleBy(x: -1.0, y: 1.0)
                }

                switch spritePose {
                case .curledSleeping(let breathPhase):
                    Self.drawCurledSleeping(in: &ctx, kind: spriteKind, breathPhase: breathPhase)
                default:
                    Self.drawActiveProfile(in: &ctx, kind: spriteKind, pose: spritePose)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.84), radius: 1.4, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.55), radius: 4.5, x: 0, y: 1.8)
        .allowsHitTesting(false)
    }

    // MARK: - Palette (OLED / HDR Comfort Tones)

    struct CatPalette: Sendable {
        let coat: Color
        let coatShade: Color
        let coatHighlight: Color
        let stripe: Color
        let cream: Color
        let innerEar: Color
        let eyeIris: Color
        let nose: Color
        let rimStroke: Color
        let tailFin: Color
    }

    nonisolated static func palette(for kind: CatSpriteKind) -> CatPalette {
        switch kind {
        case .blackNightFury:
            return CatPalette(
                coat: Color(red: 56.0 / 255.0, green: 51.0 / 255.0, blue: 77.0 / 255.0),
                coatShade: Color(red: 38.0 / 255.0, green: 33.0 / 255.0, blue: 54.0 / 255.0),
                coatHighlight: Color(red: 78.0 / 255.0, green: 72.0 / 255.0, blue: 107.0 / 255.0),
                stripe: Color(red: 34.0 / 255.0, green: 30.0 / 255.0, blue: 48.0 / 255.0),
                cream: Color(red: 0.94, green: 0.96, blue: 0.99),
                innerEar: Color(red: 0.42, green: 0.34, blue: 0.46),
                eyeIris: Color(red: 0.93, green: 0.68, blue: 0.24),
                nose: Color(red: 0.28, green: 0.24, blue: 0.35),
                rimStroke: LunaTheme.moonlight.opacity(0.56),
                tailFin: Color(red: 230.0 / 255.0, green: 56.0 / 255.0, blue: 51.0 / 255.0)
            )
        case .brownTabby:
            return CatPalette(
                coat: Color(red: 148.0 / 255.0, green: 105.0 / 255.0, blue: 66.0 / 255.0),
                coatShade: Color(red: 110.0 / 255.0, green: 75.0 / 255.0, blue: 46.0 / 255.0),
                coatHighlight: Color(red: 174.0 / 255.0, green: 127.0 / 255.0, blue: 84.0 / 255.0),
                stripe: Color(red: 58.0 / 255.0, green: 35.0 / 255.0, blue: 19.0 / 255.0),
                cream: Color(red: 0.95, green: 0.91, blue: 0.85),
                innerEar: Color(red: 0.72, green: 0.48, blue: 0.43),
                eyeIris: Color(red: 133.0 / 255.0, green: 166.0 / 255.0, blue: 87.0 / 255.0),
                nose: Color(red: 0.79, green: 0.50, blue: 0.48),
                rimStroke: Color(red: 0.96, green: 0.86, blue: 0.68).opacity(0.42),
                tailFin: Color(red: 230.0 / 255.0, green: 56.0 / 255.0, blue: 51.0 / 255.0)
            )
        }
    }

    // MARK: - Active Side-Profile Poses

    struct PoseMetrics: Sendable {
        var bobY: CGFloat = 0
        var bodyPitch: CGFloat = 0
        var chestDrop: CGFloat = 0
        var rumpLift: CGFloat = 0
        var archLift: CGFloat = 0
        var headOffset: CGPoint = .zero
        var headTilt: CGFloat = 0
        var earPerk: CGFloat = 0
        var frontNearAngle: CGFloat = 0
        var frontFarAngle: CGFloat = 0
        var hindNearAngle: CGFloat = 0
        var hindFarAngle: CGFloat = 0
        var legExtend: CGFloat = 0
        var tailLift: CGFloat = 0
        var tailWag: CGFloat = 0
        var tailWavePhase: Double = 0
        var isAlertEyes: Bool = false
    }

    nonisolated static func metrics(for pose: CatPose) -> PoseMetrics {
        switch pose {
        case .running(let stridePhase, let sprintIntensity):
            let theta = stridePhase * Double.pi * 2.0
            let amp = 0.75 + sprintIntensity * 0.40
            let leap = sin(theta)
            let counter = sin(theta + Double.pi * 0.85)
            return PoseMetrics(
                bobY: CGFloat(-abs(leap) * 3.0 * amp),
                bodyPitch: CGFloat(cos(theta) * 0.11 * amp),
                chestDrop: 0,
                rumpLift: 0,
                archLift: CGFloat(max(0, -leap) * 1.8),
                headOffset: CGPoint(x: 1.5, y: CGFloat(-leap * 1.4)),
                headTilt: CGFloat(cos(theta) * 0.06),
                earPerk: 0.08,
                frontNearAngle: CGFloat(sin(theta) * 0.62 * amp),
                frontFarAngle: CGFloat(sin(theta + 0.55) * 0.54 * amp),
                hindNearAngle: CGFloat(counter * 0.68 * amp),
                hindFarAngle: CGFloat(sin(theta + Double.pi * 1.1) * 0.56 * amp),
                legExtend: 1.0,
                tailLift: -2.0,
                tailWag: CGFloat(sin(theta) * 4.5),
                tailWavePhase: stridePhase,
                isAlertEyes: false
            )

        case .pounceCrouch(let wigglePhase, let crouchBlend):
            let b = CGFloat(min(1, max(0, crouchBlend)))
            let wag = sin(wigglePhase * Double.pi * 2.0 * 2.4)
            return PoseMetrics(
                bobY: 2.8 * b,
                bodyPitch: 0.16 * b,
                chestDrop: 4.5 * b,
                rumpLift: -2.6 * b,
                archLift: -1.5 * b,
                headOffset: CGPoint(x: 2.0 * b, y: 4.8 * b),
                headTilt: -0.06 * b,
                earPerk: 0.25 * b,
                frontNearAngle: -0.58 * b,
                frontFarAngle: -0.42 * b,
                hindNearAngle: 0.34 * b,
                hindFarAngle: 0.25 * b,
                legExtend: 0.72,
                tailLift: -6.0 * b,
                tailWag: CGFloat(wag * 6.5 * Double(b)),
                tailWavePhase: wigglePhase * 2.2,
                isAlertEyes: true
            )

        case .prowling(let stridePhase, let sniffProgress):
            let theta = stridePhase * Double.pi * 2.0
            let sniff = CGFloat(min(1, max(0, sniffProgress)))
            let stepScale = max(0.08, 1.0 - sniff * 0.92)
            return PoseMetrics(
                bobY: 1.4 + sniff * 1.0,
                bodyPitch: 0.06 + sniff * 0.14,
                chestDrop: 2.2 + sniff * 2.8,
                rumpLift: -0.5,
                archLift: -0.6,
                headOffset: CGPoint(x: 1.5 + sniff * 2.4, y: 3.5 + sniff * 5.8 + CGFloat(sin(theta * 3) * 0.6 * Double(sniff))),
                headTilt: 0.14 + sniff * 0.26,
                earPerk: 0.15,
                frontNearAngle: CGFloat(sin(theta) * 0.34) * stepScale - sniff * 0.18,
                frontFarAngle: CGFloat(sin(theta + .pi) * 0.28) * stepScale,
                hindNearAngle: CGFloat(sin(theta + .pi) * 0.30) * stepScale,
                hindFarAngle: CGFloat(sin(theta) * 0.24) * stepScale,
                legExtend: 0.80,
                tailLift: -5.5,
                tailWag: CGFloat(sin(theta) * 2.8),
                tailWavePhase: stridePhase,
                isAlertEyes: false
            )

        case .stretching(let progress):
            let p = CGFloat(sin(min(1, max(0, progress)) * Double.pi))
            return PoseMetrics(
                bobY: 1.0 * p,
                bodyPitch: 0.22 * p,
                chestDrop: 6.5 * p,
                rumpLift: -3.2 * p,
                archLift: 6.2 * p,
                headOffset: CGPoint(x: 3.2 * p, y: 5.2 * p),
                headTilt: -0.10 * p,
                earPerk: -0.12 * p,
                frontNearAngle: -0.68 * p,
                frontFarAngle: -0.58 * p,
                hindNearAngle: 0.15 * p,
                hindFarAngle: 0.08 * p,
                legExtend: 0.92,
                tailLift: -11.0 * p,
                tailWag: CGFloat(sin(progress * Double.pi * 2) * 2.5),
                tailWavePhase: progress,
                isAlertEyes: false
            )

        case .alertPerk(let hopProgress):
            let hop = CGFloat(sin(min(1, max(0, hopProgress)) * Double.pi))
            return PoseMetrics(
                bobY: -4.2 * hop,
                bodyPitch: -0.08 * hop,
                chestDrop: -1.0 * hop,
                rumpLift: 0,
                archLift: 0,
                headOffset: CGPoint(x: -0.5, y: -1.0 * hop),
                headTilt: -0.06 * hop,
                earPerk: 0.25,
                frontNearAngle: 0.20 * hop,
                frontFarAngle: -0.15 * hop,
                hindNearAngle: -0.24 * hop,
                hindFarAngle: 0.18 * hop,
                legExtend: 1.0,
                tailLift: -5.5,
                tailWag: 0,
                tailWavePhase: hopProgress,
                isAlertEyes: true
            )

        case .curledSleeping:
            return PoseMetrics()
        }
    }

    private nonisolated static func drawActiveProfile(in ctx: inout GraphicsContext, kind: CatSpriteKind, pose: CatPose) {
        let p = palette(for: kind)
        let m = metrics(for: pose)

        ctx.drawLayer { layer in
            layer.translateBy(x: 40, y: 34 + m.bobY)
            layer.rotate(by: Angle(radians: Double(m.bodyPitch)))
            layer.translateBy(x: -40, y: -(34 + m.bobY))

            let baseY = 34 + m.bobY
            let hasSocks = (kind == .brownTabby)

            // 1. Tail (behind torso)
            drawTail(in: &layer, kind: kind, palette: p, rumpPoint: CGPoint(x: 20, y: baseY - 2 + m.rumpLift), metrics: m)

            // 2. Far legs (behind torso)
            drawLeg(in: &layer, palette: p, origin: CGPoint(x: 25, y: baseY + 3 + m.rumpLift * 0.5), angle: m.hindFarAngle, length: 13 * m.legExtend, isFar: true, hasWhiteSock: hasSocks)
            drawLeg(in: &layer, palette: p, origin: CGPoint(x: 47, y: baseY + 3 + m.chestDrop * 0.5), angle: m.frontFarAngle, length: 13 * m.legExtend, isFar: true, hasWhiteSock: hasSocks)

            // 3. Torso
            let torsoPath = Path { path in
                let rumpY = baseY + m.rumpLift
                let chestY = baseY + m.chestDrop
                path.move(to: CGPoint(x: 19, y: rumpY + 1))
                path.addCurve(to: CGPoint(x: 51, y: chestY - 4), control1: CGPoint(x: 24, y: baseY - 10 - m.archLift), control2: CGPoint(x: 42, y: baseY - 9 - m.archLift * 0.5))
                path.addCurve(to: CGPoint(x: 49, y: chestY + 8), control1: CGPoint(x: 56, y: chestY - 1), control2: CGPoint(x: 55, y: chestY + 7))
                path.addCurve(to: CGPoint(x: 19, y: rumpY + 6), control1: CGPoint(x: 40, y: baseY + 9), control2: CGPoint(x: 27, y: baseY + 10))
                path.closeSubpath()
            }
            layer.fill(torsoPath, with: .color(p.coat))
            layer.stroke(torsoPath, with: .color(p.rimStroke), lineWidth: 1.05)

            // Coat markings on torso
            if kind == .blackNightFury {
                // Clear white chest heart
                let spot = Path { path in
                    let cx: CGFloat = 50.2
                    let cy: CGFloat = baseY + 2.5 + m.chestDrop * 0.75
                    path.move(to: CGPoint(x: cx, y: cy - 1.3))
                    path.addCurve(to: CGPoint(x: cx + 3.4, y: cy + 0.3), control1: CGPoint(x: cx + 1.4, y: cy - 3.6), control2: CGPoint(x: cx + 4.1, y: cy - 2.0))
                    path.addQuadCurve(to: CGPoint(x: cx, y: cy + 4.4), control: CGPoint(x: cx + 2.6, y: cy + 2.7))
                    path.addQuadCurve(to: CGPoint(x: cx - 3.2, y: cy + 0.3), control: CGPoint(x: cx - 2.4, y: cy + 2.7))
                    path.addCurve(to: CGPoint(x: cx, y: cy - 1.3), control1: CGPoint(x: cx - 3.9, y: cy - 2.0), control2: CGPoint(x: cx - 1.3, y: cy - 3.6))
                    path.closeSubpath()
                }
                layer.fill(spot, with: .color(p.cream.opacity(0.95)))
            } else {
                // Warm cream chest bib + dark tabby stripes along back
                let bib = Path { path in
                    let cy = baseY + 3.0 + m.chestDrop * 0.7
                    path.move(to: CGPoint(x: 46, y: cy - 4))
                    path.addQuadCurve(to: CGPoint(x: 53.5, y: cy + 1), control: CGPoint(x: 53.5, y: cy - 3))
                    path.addQuadCurve(to: CGPoint(x: 45, y: cy + 5.5), control: CGPoint(x: 51, y: cy + 6.5))
                    path.closeSubpath()
                }
                layer.fill(bib, with: .color(p.cream))

                for offset in [-10.0, -3.5, 3.0] {
                    let sx = CGFloat(34.0 + offset)
                    let sy = baseY - 5.5 - m.archLift * 0.45
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: sx, y: sy))
                    stripe.addQuadCurve(to: CGPoint(x: sx - 1.8, y: sy + 7.5), control: CGPoint(x: sx - 3.0, y: sy + 3.6))
                    layer.stroke(stripe, with: .color(p.stripe), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                }
            }

            // 4. Near legs
            drawLeg(in: &layer, palette: p, origin: CGPoint(x: 23, y: baseY + 3 + m.rumpLift * 0.5), angle: m.hindNearAngle, length: 13.5 * m.legExtend, isFar: false, hasWhiteSock: hasSocks)
            drawLeg(in: &layer, palette: p, origin: CGPoint(x: 49, y: baseY + 3 + m.chestDrop * 0.5), angle: m.frontNearAngle, length: 13.5 * m.legExtend, isFar: false, hasWhiteSock: hasSocks)

            // 5. Head
            drawHead(
                in: &layer,
                kind: kind,
                palette: p,
                center: CGPoint(x: 55.5 + m.headOffset.x, y: baseY - 9.5 + m.chestDrop * 0.45 + m.headOffset.y),
                tilt: m.headTilt,
                earPerk: m.earPerk,
                isAlertEyes: m.isAlertEyes
            )
        }
    }

    private nonisolated static func drawLeg(
        in ctx: inout GraphicsContext,
        palette p: CatPalette,
        origin: CGPoint,
        angle: CGFloat,
        length: CGFloat,
        isFar: Bool,
        hasWhiteSock: Bool
    ) {
        let footX = origin.x + sin(angle) * length
        let footY = origin.y + cos(angle) * length
        let kneeX = (origin.x + footX) * 0.5 + 1.4
        let kneeY = (origin.y + footY) * 0.5

        var leg = Path()
        leg.move(to: origin)
        leg.addQuadCurve(to: CGPoint(x: footX, y: footY), control: CGPoint(x: kneeX, y: kneeY))

        let color = isFar ? p.coatShade : p.coat
        ctx.stroke(leg, with: .color(color), style: StrokeStyle(lineWidth: 4.0, lineCap: .round))

        let pawCenter = CGPoint(x: footX + 1.2, y: footY)
        let pawRect = CGRect(x: pawCenter.x - 2.4, y: pawCenter.y - 1.8, width: 4.8, height: 3.4)
        let pawColor = hasWhiteSock ? (isFar ? p.cream.opacity(0.75) : p.cream) : color
        ctx.fill(Path(ellipseIn: pawRect), with: .color(pawColor))
    }

    struct TailGeometry: Sendable {
        let tip: CGPoint
        let ctrl1: CGPoint
        let ctrl2: CGPoint
        let angle: CGFloat
    }

    nonisolated static func tailGeometry(rumpPoint: CGPoint, metrics m: PoseMetrics) -> TailGeometry {
        let wave = CGFloat(sin(m.tailWavePhase * Double.pi * 2.0)) * 2.2
        let tipX = max(11.2, rumpPoint.x - 8.5 + m.tailWag * 0.22)
        let tipY = max(9.5, rumpPoint.y - 14.0 + m.tailLift * 0.30 + wave * 0.35 + m.tailWag * 0.28)
        let tip = CGPoint(x: tipX, y: tipY)
        let ctrl1 = CGPoint(x: rumpPoint.x - 8.5, y: rumpPoint.y + 4.5 - wave * 0.35)
        let ctrl2 = CGPoint(x: tip.x + 1.8, y: tip.y + 7.5 + wave * 0.25)
        let angle = atan2(tip.y - ctrl2.y, tip.x - ctrl2.x)
        return TailGeometry(tip: tip, ctrl1: ctrl1, ctrl2: ctrl2, angle: angle)
    }

    private nonisolated static let blackFinSamplePoints: [CGPoint] = [
        CGPoint(x: 2.4, y: 0.2), CGPoint(x: -2.0, y: 8.0), CGPoint(x: -9.2, y: 6.2), CGPoint(x: -7.0, y: 1.6)
    ]

    private nonisolated static let redFinSamplePoints: [CGPoint] = [
        CGPoint(x: 2.6, y: -0.2), CGPoint(x: -2.8, y: -10.5), CGPoint(x: -11.2, y: -8.8), CGPoint(x: -9.4, y: -0.4)
    ]

    nonisolated static func activeCanvasBounds(for pose: CatPose) -> CGRect {
        let m = metrics(for: pose)
        let baseY = 34 + m.bobY
        let pivot = CGPoint(x: 40, y: baseY)
        let rump = CGPoint(x: 20, y: baseY - 2 + m.rumpLift)
        let g = tailGeometry(rumpPoint: rump, metrics: m)

        var points: [CGPoint] = [rump, g.tip, g.ctrl1, g.ctrl2]
        let ca = cos(g.angle)
        let sa = sin(g.angle)
        for p in blackFinSamplePoints + redFinSamplePoints {
            points.append(CGPoint(x: g.tip.x + p.x * ca - p.y * sa, y: g.tip.y + p.x * sa + p.y * ca))
        }
        let head = CGPoint(x: 55.5 + m.headOffset.x, y: baseY - 9.5 + m.chestDrop * 0.45 + m.headOffset.y)
        let ct = cos(m.headTilt)
        let st = sin(m.headTilt)
        let headLocalPoints: [CGPoint] = [
            CGPoint(x: 2.0 - m.earPerk * 3, y: -15.5 - m.earPerk * 4),
            CGPoint(x: -6.2 - m.earPerk * 2, y: -15.5 - m.earPerk * 4),
            CGPoint(x: 11.0, y: 0),
            CGPoint(x: 14.5, y: 2.2 - 0.15 * 14.0),
            CGPoint(x: 14.5, y: 2.2 + 0.12 * 14.0)
        ]
        for lp in headLocalPoints {
            points.append(CGPoint(x: head.x + lp.x * ct - lp.y * st, y: head.y + lp.x * st + lp.y * ct))
        }

        let legs: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 49, y: baseY + 3 + m.chestDrop * 0.5), m.frontNearAngle, 13.5 * m.legExtend),
            (CGPoint(x: 47, y: baseY + 3 + m.chestDrop * 0.5), m.frontFarAngle, 13.0 * m.legExtend),
            (CGPoint(x: 23, y: baseY + 3 + m.rumpLift * 0.5), m.hindNearAngle, 13.5 * m.legExtend),
            (CGPoint(x: 25, y: baseY + 3 + m.rumpLift * 0.5), m.hindFarAngle, 13.0 * m.legExtend)
        ]
        for (origin, angle, len) in legs {
            let fx = origin.x + sin(angle) * len
            let fy = origin.y + cos(angle) * len
            points.append(CGPoint(x: fx + 3.6, y: fy + 1.6))
            points.append(CGPoint(x: fx - 1.2, y: fy + 1.6))
        }

        let cp = cos(m.bodyPitch)
        let sp = sin(m.bodyPitch)
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for pt in points {
            let dx = pt.x - pivot.x
            let dy = pt.y - pivot.y
            let wx = pivot.x + dx * cp - dy * sp
            let wy = pivot.y + dx * sp + dy * cp
            minX = min(minX, wx); maxX = max(maxX, wx)
            minY = min(minY, wy); maxY = max(maxY, wy)
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private nonisolated static func drawTail(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        palette p: CatPalette,
        rumpPoint: CGPoint,
        metrics m: PoseMetrics
    ) {
        let g = tailGeometry(rumpPoint: rumpPoint, metrics: m)

        var tailPath = Path()
        tailPath.move(to: rumpPoint)
        tailPath.addCurve(to: g.tip, control1: g.ctrl1, control2: g.ctrl2)

        ctx.stroke(tailPath, with: .color(p.coat), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        ctx.stroke(tailPath, with: .color(p.rimStroke), style: StrokeStyle(lineWidth: 0.85, lineCap: .round))

        if kind == .blackNightFury {
            // Upright S-tail with ~2x larger scarlet Night-Fury prosthetic tail fin (#E63833)
            ctx.drawLayer { finCtx in
                finCtx.translateBy(x: g.tip.x, y: g.tip.y)
                finCtx.rotate(by: Angle(radians: Double(g.angle)))

                // Inner charcoal winglet
                let blackFin = Path { path in
                    path.move(to: CGPoint(x: 2.4, y: 0.2))
                    path.addQuadCurve(to: CGPoint(x: -9.2, y: 6.2), control: CGPoint(x: -2.0, y: 8.0))
                    path.addQuadCurve(to: CGPoint(x: -7.0, y: 1.6), control: CGPoint(x: -8.0, y: 3.4))
                    path.closeSubpath()
                }
                finCtx.fill(blackFin, with: .color(p.coatShade))
                finCtx.stroke(blackFin, with: .color(p.rimStroke), lineWidth: 0.7)

                // Outer scarlet prosthetic tail fin (unobstructed above/left of tail tip)
                let redFin = Path { path in
                    path.move(to: CGPoint(x: 2.6, y: -0.2))
                    path.addQuadCurve(to: CGPoint(x: -11.2, y: -8.8), control: CGPoint(x: -2.8, y: -10.5))
                    path.addLine(to: CGPoint(x: -9.0, y: -4.6))
                    path.addLine(to: CGPoint(x: -8.4, y: -2.0))
                    path.addLine(to: CGPoint(x: -9.4, y: -0.4))
                    path.closeSubpath()
                }
                finCtx.fill(redFin, with: .color(p.tailFin))
                finCtx.stroke(redFin, with: .color(Color(red: 0.16, green: 0.05, blue: 0.06)), lineWidth: 0.75)

                var rib = Path()
                rib.move(to: CGPoint(x: 0.2, y: -0.5))
                rib.addQuadCurve(to: CGPoint(x: -9.2, y: -6.4), control: CGPoint(x: -4.2, y: -4.8))
                finCtx.stroke(rib, with: .color(Color(red: 1.0, green: 0.72, blue: 0.66).opacity(0.42)), lineWidth: 0.65)
            }
        } else {
            // Subtle tabby tail stripes along the upright S-curve
            for t in [0.42, 0.72] {
                let pt = cubicPoint(p0: rumpPoint, p1: g.ctrl1, p2: g.ctrl2, p3: g.tip, t: CGFloat(t))
                let dot = Path(ellipseIn: CGRect(x: pt.x - 1.6, y: pt.y - 1.6, width: 3.2, height: 3.2))
                ctx.fill(dot, with: .color(p.stripe))
            }
        }
    }

    private nonisolated static func drawHead(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        palette p: CatPalette,
        center: CGPoint,
        tilt: CGFloat,
        earPerk: CGFloat,
        isAlertEyes: Bool
    ) {
        ctx.drawLayer { hCtx in
            hCtx.translateBy(x: center.x, y: center.y)
            hCtx.rotate(by: Angle(radians: Double(tilt)))

            // Back ear
            let backEar = Path { path in
                path.move(to: CGPoint(x: -1.5, y: -6.5))
                path.addLine(to: CGPoint(x: 2.0 - earPerk * 3, y: -15.5 - earPerk * 4))
                path.addLine(to: CGPoint(x: 6.5, y: -7.0))
                path.closeSubpath()
            }
            hCtx.fill(backEar, with: .color(p.coatShade))
            hCtx.stroke(backEar, with: .color(p.rimStroke.opacity(0.75)), lineWidth: 0.7)

            // Front ear
            let frontEar = Path { path in
                path.move(to: CGPoint(x: -7.5, y: -4.5))
                path.addLine(to: CGPoint(x: -6.2 - earPerk * 2, y: -15.5 - earPerk * 4))
                path.addLine(to: CGPoint(x: -0.5, y: -7.2))
                path.closeSubpath()
            }
            hCtx.fill(frontEar, with: .color(p.coat))
            hCtx.stroke(frontEar, with: .color(p.rimStroke), lineWidth: 0.9)

            let innerEar = Path { path in
                path.move(to: CGPoint(x: -5.8, y: -6.2))
                path.addLine(to: CGPoint(x: -5.3 - earPerk * 1.4, y: -12.8 - earPerk * 3))
                path.addLine(to: CGPoint(x: -2.0, y: -7.6))
                path.closeSubpath()
            }
            hCtx.fill(innerEar, with: .color(p.innerEar))

            // Cranium + cheek silhouette
            let headRect = CGRect(x: -10.5, y: -9.5, width: 21.5, height: 18.5)
            let headPath = Path(ellipseIn: headRect)
            hCtx.fill(headPath, with: .color(p.coat))
            hCtx.stroke(headPath, with: .color(p.rimStroke), lineWidth: 1.05)

            if kind == .brownTabby {
                // Cream lower muzzle & chin
                let muzzle = Path(ellipseIn: CGRect(x: -0.5, y: -0.5, width: 11.0, height: 8.5))
                hCtx.fill(muzzle, with: .color(p.cream))
                // Forehead tabby stripes
                for dy in [-6.0, -3.8] {
                    var brow = Path()
                    brow.move(to: CGPoint(x: -4.5, y: dy))
                    brow.addLine(to: CGPoint(x: 1.5, y: dy + 0.8))
                    hCtx.stroke(brow, with: .color(p.stripe), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }

            // Expressive golden/hazel eye
            let eyeH: CGFloat = isAlertEyes ? 4.4 : 3.8
            let eyeRect = CGRect(x: 1.6, y: -3.8, width: 4.0, height: eyeH)
            hCtx.fill(Path(ellipseIn: eyeRect), with: .color(p.eyeIris))
            let pupilW: CGFloat = isAlertEyes ? 1.8 : 1.3
            let pupilRect = CGRect(x: 3.6 - pupilW * 0.5, y: -3.2, width: pupilW, height: eyeH - 1.1)
            hCtx.fill(Path(ellipseIn: pupilRect), with: .color(Color.black.opacity(0.92)))
            let glint = Path(ellipseIn: CGRect(x: 2.3, y: -3.1, width: 1.1, height: 1.1))
            hCtx.fill(glint, with: .color(LunaTheme.moonlight.opacity(0.88)))

            // Nose
            let noseRect = CGRect(x: 9.0, y: 0.2, width: 2.2, height: 1.8)
            hCtx.fill(Path(ellipseIn: noseRect), with: .color(p.nose))

            // Delicate whiskers
            for angleW in [-0.15, 0.12] {
                var w = Path()
                w.move(to: CGPoint(x: 7.2, y: 2.2))
                w.addLine(to: CGPoint(x: 14.5, y: 2.2 + CGFloat(angleW) * 14.0))
                hCtx.stroke(w, with: .color(p.cream.opacity(0.55)), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
            }
        }
    }

    // MARK: - Curled Sleeping Pose

    private nonisolated static func drawCurledSleeping(in ctx: inout GraphicsContext, kind: CatSpriteKind, breathPhase: Double) {
        let p = palette(for: kind)
        let breath = CGFloat(sin(breathPhase)) * 1.3

        ctx.drawLayer { layer in
            // Cozy oval sleeping loaf/curl
            let bodyRect = CGRect(x: 14, y: 22 - breath * 0.5, width: 48, height: 26 + breath)
            let bodyPath = Path(ellipseIn: bodyRect)
            layer.fill(bodyPath, with: .color(p.coat))
            layer.stroke(bodyPath, with: .color(p.rimStroke), lineWidth: 1.05)

            if kind == .brownTabby {
                for sx in [26.0, 34.0, 42.0] {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: sx, y: 23 - breath * 0.3))
                    stripe.addQuadCurve(to: CGPoint(x: sx - 2.0, y: 34), control: CGPoint(x: sx - 4.0, y: 28))
                    layer.stroke(stripe, with: .color(p.stripe), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                let paw = Path(ellipseIn: CGRect(x: 42, y: 42, width: 7.5, height: 4.5))
                layer.fill(paw, with: .color(p.cream))
            } else {
                // Chest tuft peeking near chin
                let spot = Path(ellipseIn: CGRect(x: 43.5, y: 38.5, width: 6.2, height: 4.5))
                layer.fill(spot, with: .color(p.cream.opacity(0.95)))
            }

            // Wrapped sleeping tail around front
            var wrapTail = Path()
            wrapTail.move(to: CGPoint(x: 17, y: 37))
            wrapTail.addCurve(
                to: CGPoint(x: 47, y: 46.5),
                control1: CGPoint(x: 16, y: 48),
                control2: CGPoint(x: 34, y: 49.5)
            )
            layer.stroke(wrapTail, with: .color(p.coatShade), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))

            if kind == .blackNightFury {
                // Red tail fin peeking cutely beside curled paw
                let fin = Path { path in
                    path.move(to: CGPoint(x: 46, y: 46.5))
                    path.addQuadCurve(to: CGPoint(x: 56.5, y: 41.5), control: CGPoint(x: 52.5, y: 49.5))
                    path.addLine(to: CGPoint(x: 51.8, y: 43.2))
                    path.closeSubpath()
                }
                layer.fill(fin, with: .color(p.tailFin))
            }

            // Tucked sleeping head
            let headCenter = CGPoint(x: 50, y: 29.5 - breath * 0.25)
            let leftEar = Path { path in
                path.move(to: CGPoint(x: headCenter.x - 8, y: headCenter.y - 3))
                path.addLine(to: CGPoint(x: headCenter.x - 7, y: headCenter.y - 13))
                path.addLine(to: CGPoint(x: headCenter.x - 1, y: headCenter.y - 6))
                path.closeSubpath()
            }
            let rightEar = Path { path in
                path.move(to: CGPoint(x: headCenter.x + 1, y: headCenter.y - 6))
                path.addLine(to: CGPoint(x: headCenter.x + 6, y: headCenter.y - 12.5))
                path.addLine(to: CGPoint(x: headCenter.x + 8, y: headCenter.y - 2.5))
                path.closeSubpath()
            }
            layer.fill(leftEar, with: .color(p.coat))
            layer.fill(rightEar, with: .color(p.coatShade))

            let headRect = CGRect(x: headCenter.x - 10, y: headCenter.y - 8, width: 20, height: 17)
            let headPath = Path(ellipseIn: headRect)
            layer.fill(headPath, with: .color(p.coat))
            layer.stroke(headPath, with: .color(p.rimStroke), lineWidth: 0.85)

            if kind == .brownTabby {
                let muzzle = Path(ellipseIn: CGRect(x: headCenter.x - 3, y: headCenter.y + 0.5, width: 11, height: 7.5))
                layer.fill(muzzle, with: .color(p.cream))
            }

            // Peaceful closed sleeping eye curve
            var eyeArc = Path()
            eyeArc.move(to: CGPoint(x: headCenter.x + 0.5, y: headCenter.y - 1.0))
            eyeArc.addQuadCurve(
                to: CGPoint(x: headCenter.x + 6.0, y: headCenter.y - 0.5),
                control: CGPoint(x: headCenter.x + 3.2, y: headCenter.y + 2.0)
            )
            layer.stroke(eyeArc, with: .color(p.eyeIris.opacity(0.92)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    private nonisolated static func cubicPoint(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        let c1 = 3.0 * uu * t
        let c2 = 3.0 * u * tt
        let px = uuu * p0.x + c1 * p1.x + c2 * p2.x + ttt * p3.x
        let py = uuu * p0.y + c1 * p1.y + c2 * p2.y + ttt * p3.y
        return CGPoint(x: px, y: py)
    }
}

/// Glowing amber/gold moon-spark chased along the loading progress bar tip.
struct MoonSparkView: View {
    let pulse: Double

    var body: some View {
        let haloScale = 0.88 + 0.22 * sin(pulse)
        ZStack {
            Circle()
                .fill(LunaTheme.amber.opacity(0.36))
                .frame(width: 38, height: 38)
                .scaleEffect(haloScale)
                .blur(radius: 5)

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(LunaTheme.amber)
                .shadow(color: LunaTheme.amberDeep.opacity(0.92), radius: 7)
        }
        .allowsHitTesting(false)
    }
}

/// Pointed cat ears perched atop the scrubber playhead knob when paused or scrubbing.
struct CatPlayheadEarsView: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 18.0
            let sy = size.height / 8.0
            let leftOuter = Path { p in
                p.move(to: CGPoint(x: 2.4 * sx, y: size.height))
                p.addLine(to: CGPoint(x: 4.3 * sx, y: 0.8 * sy))
                p.addLine(to: CGPoint(x: 7.8 * sx, y: size.height - 0.8 * sy))
                p.closeSubpath()
            }
            let rightOuter = Path { p in
                p.move(to: CGPoint(x: size.width - 7.8 * sx, y: size.height - 0.8 * sy))
                p.addLine(to: CGPoint(x: size.width - 4.3 * sx, y: 0.8 * sy))
                p.addLine(to: CGPoint(x: size.width - 2.4 * sx, y: size.height))
                p.closeSubpath()
            }
            let earFill = Color(red: 0.92, green: 0.94, blue: 0.98)
            context.fill(leftOuter, with: .color(earFill))
            context.fill(rightOuter, with: .color(earFill))

            let leftInner = Path { p in
                p.move(to: CGPoint(x: 3.2 * sx, y: size.height - 0.8 * sy))
                p.addLine(to: CGPoint(x: 4.3 * sx, y: 2.8 * sy))
                p.addLine(to: CGPoint(x: 6.4 * sx, y: size.height - 1.0 * sy))
                p.closeSubpath()
            }
            let rightInner = Path { p in
                p.move(to: CGPoint(x: size.width - 6.4 * sx, y: size.height - 1.0 * sy))
                p.addLine(to: CGPoint(x: size.width - 4.3 * sx, y: 2.8 * sy))
                p.addLine(to: CGPoint(x: size.width - 3.2 * sx, y: size.height - 0.8 * sy))
                p.closeSubpath()
            }
            context.fill(leftInner, with: .color(LunaTheme.amber.opacity(0.90)))
            context.fill(rightInner, with: .color(LunaTheme.amber.opacity(0.90)))
        }
        .frame(width: 28, height: 14)
        .shadow(color: Color.black.opacity(0.65), radius: 2, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}
