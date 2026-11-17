import Foundation
import SwiftUI
import CoreGraphics

/// Pure anatomical pose kinematics, palette tokens, and exact canvas-bounds computation
/// for the vector cat mascot renderer (`CatMascotCanvasView`).
enum CatMascotAnatomy {
    struct CatPalette: Sendable {
        let coat: Color
        let coatShade: Color
        let coatHighlight: Color
        let stripe: Color
        let cream: Color
        let innerEar: Color
        let eyeIris: Color
        let eyeIrisDeep: Color
        let nose: Color
        let rimStroke: Color
        let tailFin: Color
        let tailFinShade: Color
    }

    nonisolated static func palette(for kind: CatSpriteKind) -> CatPalette {
        switch kind {
        case .blackNightFury:
            return CatPalette(
                coat: Color(red: 56.0 / 255.0, green: 51.0 / 255.0, blue: 77.0 / 255.0),
                coatShade: Color(red: 36.0 / 255.0, green: 31.0 / 255.0, blue: 52.0 / 255.0),
                coatHighlight: Color(red: 86.0 / 255.0, green: 79.0 / 255.0, blue: 118.0 / 255.0),
                stripe: Color(red: 28.0 / 255.0, green: 24.0 / 255.0, blue: 42.0 / 255.0),
                cream: Color(red: 0.94, green: 0.96, blue: 0.99),
                innerEar: Color(red: 0.44, green: 0.35, blue: 0.49),
                eyeIris: Color(red: 245.0 / 255.0, green: 184.0 / 255.0, blue: 62.0 / 255.0),
                eyeIrisDeep: Color(red: 196.0 / 255.0, green: 122.0 / 255.0, blue: 32.0 / 255.0),
                nose: Color(red: 0.25, green: 0.21, blue: 0.32),
                rimStroke: LunaTheme.moonlight.opacity(0.62),
                tailFin: Color(red: 230.0 / 255.0, green: 56.0 / 255.0, blue: 51.0 / 255.0),
                tailFinShade: Color(red: 162.0 / 255.0, green: 26.0 / 255.0, blue: 24.0 / 255.0)
            )
        case .brownTabby:
            return CatPalette(
                coat: Color(red: 148.0 / 255.0, green: 105.0 / 255.0, blue: 66.0 / 255.0),
                coatShade: Color(red: 106.0 / 255.0, green: 72.0 / 255.0, blue: 43.0 / 255.0),
                coatHighlight: Color(red: 184.0 / 255.0, green: 136.0 / 255.0, blue: 90.0 / 255.0),
                stripe: Color(red: 54.0 / 255.0, green: 32.0 / 255.0, blue: 17.0 / 255.0),
                cream: Color(red: 0.95, green: 0.91, blue: 0.85),
                innerEar: Color(red: 0.74, green: 0.49, blue: 0.44),
                eyeIris: Color(red: 133.0 / 255.0, green: 166.0 / 255.0, blue: 87.0 / 255.0),
                eyeIrisDeep: Color(red: 92.0 / 255.0, green: 122.0 / 255.0, blue: 56.0 / 255.0),
                nose: Color(red: 0.79, green: 0.50, blue: 0.48),
                rimStroke: Color(red: 0.97, green: 0.87, blue: 0.70).opacity(0.48),
                tailFin: Color(red: 230.0 / 255.0, green: 56.0 / 255.0, blue: 51.0 / 255.0),
                tailFinShade: Color(red: 162.0 / 255.0, green: 26.0 / 255.0, blue: 24.0 / 255.0)
            )
        }
    }

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
                bobY: 1.2 + sniff * 0.8,
                bodyPitch: 0.06 + sniff * 0.13,
                chestDrop: 2.2 + sniff * 2.4,
                rumpLift: -0.5,
                archLift: -0.6,
                headOffset: CGPoint(
                    x: 1.5 + sniff * 2.4,
                    y: 3.5 + sniff * 5.2 + CGFloat(sin(theta * 3) * 0.6 * Double(sniff))
                ),
                headTilt: 0.14 + sniff * 0.24,
                earPerk: 0.15,
                frontNearAngle: CGFloat(sin(theta) * 0.34) * stepScale - sniff * 0.18,
                frontFarAngle: CGFloat(sin(theta + .pi) * 0.28) * stepScale,
                hindNearAngle: CGFloat(sin(theta + .pi) * 0.30) * stepScale,
                hindFarAngle: CGFloat(sin(theta) * 0.24) * stepScale,
                legExtend: 0.80 - 0.08 * sniff,
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
                legExtend: 0.86,
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

    struct TailGeometry: Sendable {
        let tip: CGPoint
        let ctrl1: CGPoint
        let ctrl2: CGPoint
        let angle: CGFloat
    }

    nonisolated static func tailGeometry(rumpPoint: CGPoint, metrics m: PoseMetrics) -> TailGeometry {
        let wave = CGFloat(sin(m.tailWavePhase * Double.pi * 2.0)) * 2.2
        let tipX = max(13.2, rumpPoint.x - 6.8 + m.tailWag * 0.22)
        let tipY = max(11.5, rumpPoint.y - 13.0 + m.tailLift * 0.28 + wave * 0.35 + m.tailWag * 0.28)
        let tip = CGPoint(x: tipX, y: tipY)
        let ctrl1 = CGPoint(x: rumpPoint.x - 8.0, y: rumpPoint.y + 4.5 - wave * 0.35)
        let ctrl2 = CGPoint(x: tip.x + 1.8, y: tip.y + 7.2 + wave * 0.25)
        let angle = atan2(tip.y - ctrl2.y, tip.x - ctrl2.x)
        return TailGeometry(tip: tip, ctrl1: ctrl1, ctrl2: ctrl2, angle: angle)
    }

    /// 6-spiked V-spread Night-Fury dragon tail fin coordinates (upper charcoal vane + lower scarlet vane).
    nonisolated static let charcoalFinPoints: [CGPoint] = [
        CGPoint(x: 3.4, y: -0.3),
        CGPoint(x: 1.8, y: -7.8),
        CGPoint(x: -1.2, y: -5.8),
        CGPoint(x: -3.8, y: -8.8),
        CGPoint(x: -5.2, y: -5.6),
        CGPoint(x: -8.5, y: -6.2),
        CGPoint(x: -6.2, y: -1.6),
    ]

    nonisolated static let scarletFinPoints: [CGPoint] = [
        CGPoint(x: 3.6, y: 0.3),
        CGPoint(x: 2.0, y: 8.2),
        CGPoint(x: -1.0, y: 6.1),
        CGPoint(x: -4.0, y: 9.4),
        CGPoint(x: -5.4, y: 6.0),
        CGPoint(x: -8.8, y: 6.6),
        CGPoint(x: -6.4, y: 1.6),
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
        for p in charcoalFinPoints + scarletFinPoints {
            points.append(CGPoint(x: g.tip.x + p.x * ca - p.y * sa, y: g.tip.y + p.x * sa + p.y * ca))
        }

        let head = CGPoint(x: 55.5 + m.headOffset.x, y: baseY - 9.5 + m.chestDrop * 0.45 + m.headOffset.y)
        let ct = cos(m.headTilt)
        let st = sin(m.headTilt)
        let headLocalPoints: [CGPoint] = [
            CGPoint(x: 2.0 - m.earPerk * 3, y: -15.5 - m.earPerk * 4),
            CGPoint(x: -6.2 - m.earPerk * 2, y: -15.5 - m.earPerk * 4),
            CGPoint(x: 11.2, y: 0),
            CGPoint(x: 14.5, y: 2.2 - 0.15 * 14.0),
            CGPoint(x: 14.5, y: 2.2 + 0.12 * 14.0),
            CGPoint(x: -10.8, y: 0),
            CGPoint(x: 0, y: 9.2),
        ]
        for lp in headLocalPoints {
            points.append(CGPoint(x: head.x + lp.x * ct - lp.y * st, y: head.y + lp.x * st + lp.y * ct))
        }

        let legs: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: 49, y: baseY + 3 + m.chestDrop * 0.5), m.frontNearAngle, 13.5 * m.legExtend),
            (CGPoint(x: 47, y: baseY + 3 + m.chestDrop * 0.5), m.frontFarAngle, 13.0 * m.legExtend),
            (CGPoint(x: 23, y: baseY + 3 + m.rumpLift * 0.5), m.hindNearAngle, 13.5 * m.legExtend),
            (CGPoint(x: 25, y: baseY + 3 + m.rumpLift * 0.5), m.hindFarAngle, 13.0 * m.legExtend),
        ]
        for (origin, angle, len) in legs {
            let fx = origin.x + sin(angle) * len
            let fy = origin.y + cos(angle) * len
            points.append(CGPoint(x: fx + 4.0, y: fy + 1.8))
            points.append(CGPoint(x: fx - 2.6, y: fy + 1.8))
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
            minX = min(minX, wx)
            maxX = max(maxX, wx)
            minY = min(minY, wy)
            maxY = max(maxY, wy)
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    nonisolated static func cubicPoint(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        let c1 = 3.0 * uu * t
        let c2 = 3.0 * u * tt
        return CGPoint(
            x: uuu * p0.x + c1 * p1.x + c2 * p2.x + ttt * p3.x,
            y: uuu * p0.y + c1 * p1.y + c2 * p2.y + ttt * p3.y
        )
    }
}
