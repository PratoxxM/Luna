import Foundation
import SwiftUI
import CoreGraphics

/// High-craft modular vector Canvas mascot renderer faithful to Luna's two AppIcon cats:
/// - `blackNightFury`: moonlit plum-charcoal gradient (`#564F76 -> #38334D -> #241F34`),
///   crisp white chest heart, golden slit eyes, muscular articulated limbs, and full
///   V-spread 6-spiked scarlet/black Night-Fury dragon tail fin with structural ribs.
/// - `brownTabby`: warm golden-cinnamon mackerel tabby (`#B8885A -> #946942 -> #6A482B`)
///   with sculpted cheek pads, `"M"` brow marking, curved mackerel dorsal/flank stripes,
///   ringed tabby tail, cream muzzle/chest bib, and crisp white socks.
struct CatMascotCanvasView: View {
    let kind: CatSpriteKind
    let pose: CatPose
    var facingRight: Bool = true

    // Expose geometry helpers for unit testing without duplicating definitions.
    nonisolated static func palette(for kind: CatSpriteKind) -> CatMascotAnatomy.CatPalette {
        CatMascotAnatomy.palette(for: kind)
    }

    nonisolated static func activeCanvasBounds(for pose: CatPose) -> CGRect {
        CatMascotAnatomy.activeCanvasBounds(for: pose)
    }

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

    // MARK: - Active Side-Profile Rendering

    private nonisolated static func drawActiveProfile(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        pose: CatPose
    ) {
        let p = CatMascotAnatomy.palette(for: kind)
        let m = CatMascotAnatomy.metrics(for: pose)

        ctx.drawLayer { layer in
            layer.translateBy(x: 40, y: 34 + m.bobY)
            layer.rotate(by: Angle(radians: Double(m.bodyPitch)))
            layer.translateBy(x: -40, y: -(34 + m.bobY))

            let baseY = 34 + m.bobY
            let hasSocks = (kind == .brownTabby)

            // 1. Tail (behind torso)
            drawTail(
                in: &layer,
                kind: kind,
                palette: p,
                rumpPoint: CGPoint(x: 20, y: baseY - 2 + m.rumpLift),
                metrics: m
            )

            // 2. Far articulated muscular limbs
            drawMuscularLeg(
                in: &layer,
                palette: p,
                origin: CGPoint(x: 25, y: baseY + 3 + m.rumpLift * 0.5),
                angle: m.hindFarAngle,
                length: 13.0 * m.legExtend,
                isHind: true,
                isFar: true,
                hasWhiteSock: hasSocks
            )
            drawMuscularLeg(
                in: &layer,
                palette: p,
                origin: CGPoint(x: 47, y: baseY + 3 + m.chestDrop * 0.5),
                angle: m.frontFarAngle,
                length: 13.0 * m.legExtend,
                isHind: false,
                isFar: true,
                hasWhiteSock: hasSocks
            )

            // 3. Torso with multi-stop fur gradient & coat markings
            drawTorso(in: &layer, kind: kind, palette: p, baseY: baseY, metrics: m)

            // 4. Near articulated muscular limbs
            drawMuscularLeg(
                in: &layer,
                palette: p,
                origin: CGPoint(x: 23, y: baseY + 3 + m.rumpLift * 0.5),
                angle: m.hindNearAngle,
                length: 13.5 * m.legExtend,
                isHind: true,
                isFar: false,
                hasWhiteSock: hasSocks
            )
            drawMuscularLeg(
                in: &layer,
                palette: p,
                origin: CGPoint(x: 49, y: baseY + 3 + m.chestDrop * 0.5),
                angle: m.frontNearAngle,
                length: 13.5 * m.legExtend,
                isHind: false,
                isFar: false,
                hasWhiteSock: hasSocks
            )

            // 5. Sculpted feline head
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

    private nonisolated static func drawTorso(
        in layer: inout GraphicsContext,
        kind: CatSpriteKind,
        palette p: CatMascotAnatomy.CatPalette,
        baseY: CGFloat,
        metrics m: CatMascotAnatomy.PoseMetrics
    ) {
        let rumpY = baseY + m.rumpLift
        let chestY = baseY + m.chestDrop
        let torsoPath = Path { path in
            path.move(to: CGPoint(x: 19, y: rumpY + 1))
            path.addCurve(
                to: CGPoint(x: 51, y: chestY - 4),
                control1: CGPoint(x: 24, y: baseY - 10.5 - m.archLift),
                control2: CGPoint(x: 42, y: baseY - 9.2 - m.archLift * 0.5)
            )
            path.addCurve(
                to: CGPoint(x: 49, y: chestY + 8),
                control1: CGPoint(x: 56.5, y: chestY - 1),
                control2: CGPoint(x: 55.2, y: chestY + 7)
            )
            path.addCurve(
                to: CGPoint(x: 19, y: rumpY + 6),
                control1: CGPoint(x: 40, y: baseY + 9.2),
                control2: CGPoint(x: 27, y: baseY + 10.2)
            )
            path.closeSubpath()
        }

        let coatGrad = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: p.coatHighlight, location: 0.0),
                .init(color: p.coat, location: 0.48),
                .init(color: p.coatShade, location: 1.0),
            ]),
            startPoint: CGPoint(x: 34, y: baseY - 10 - m.archLift),
            endPoint: CGPoint(x: 36, y: baseY + 10)
        )
        layer.fill(torsoPath, with: coatGrad)
        layer.stroke(torsoPath, with: .color(p.rimStroke), lineWidth: 1.05)

        if kind == .blackNightFury {
            // Crisp white chest heart
            let heart = Path { path in
                let cx: CGFloat = 50.2
                let cy: CGFloat = baseY + 2.5 + m.chestDrop * 0.75
                path.move(to: CGPoint(x: cx, y: cy - 1.3))
                path.addCurve(
                    to: CGPoint(x: cx + 3.5, y: cy + 0.3),
                    control1: CGPoint(x: cx + 1.4, y: cy - 3.7),
                    control2: CGPoint(x: cx + 4.2, y: cy - 2.0)
                )
                path.addQuadCurve(to: CGPoint(x: cx, y: cy + 4.5), control: CGPoint(x: cx + 2.7, y: cy + 2.8))
                path.addQuadCurve(to: CGPoint(x: cx - 3.3, y: cy + 0.3), control: CGPoint(x: cx - 2.5, y: cy + 2.8))
                path.addCurve(
                    to: CGPoint(x: cx, y: cy - 1.3),
                    control1: CGPoint(x: cx - 4.0, y: cy - 2.0),
                    control2: CGPoint(x: cx - 1.3, y: cy - 3.7)
                )
                path.closeSubpath()
            }
            layer.fill(heart, with: .color(p.cream.opacity(0.96)))
        } else {
            // Cream chest bib & warm cream belly contour
            let bib = Path { path in
                let cy = baseY + 3.0 + m.chestDrop * 0.7
                path.move(to: CGPoint(x: 45.5, y: cy - 4.0))
                path.addQuadCurve(to: CGPoint(x: 53.8, y: cy + 1.2), control: CGPoint(x: 53.8, y: cy - 3.0))
                path.addQuadCurve(to: CGPoint(x: 44.5, y: cy + 5.6), control: CGPoint(x: 51.0, y: cy + 6.8))
                path.closeSubpath()
            }
            layer.fill(bib, with: .color(p.cream))

            let belly = Path { path in
                path.move(to: CGPoint(x: 27, y: baseY + 7.2))
                path.addQuadCurve(to: CGPoint(x: 45.5, y: chestY + 6.8), control: CGPoint(x: 36, y: baseY + 9.4))
                path.addQuadCurve(to: CGPoint(x: 27, y: baseY + 7.2), control: CGPoint(x: 36, y: baseY + 6.4))
                path.closeSubpath()
            }
            layer.fill(belly, with: .color(p.cream.opacity(0.75)))

            // Curved mackerel tabby stripes along dorsal spine & flank
            for (idx, offset) in [-11.5, -5.5, 0.5, 6.2].enumerated() {
                let sx = CGFloat(34.0 + offset)
                let sy = baseY - 6.8 - m.archLift * 0.45
                let stripe = Path { path in
                    path.move(to: CGPoint(x: sx + 0.6, y: sy))
                    path.addQuadCurve(
                        to: CGPoint(x: sx - 2.4, y: sy + 9.2),
                        control: CGPoint(x: sx - 3.2, y: sy + 4.4)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: sx - 0.8, y: sy + 9.2),
                        control: CGPoint(x: sx - 1.5, y: sy + 9.6)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: sx + 1.9, y: sy + 0.2),
                        control: CGPoint(x: sx - 1.2, y: sy + 4.5)
                    )
                    path.closeSubpath()
                }
                layer.fill(stripe, with: .color(p.stripe.opacity(idx == 3 ? 0.78 : 0.90)))
            }
        }
    }

    private nonisolated static func drawMuscularLeg(
        in ctx: inout GraphicsContext,
        palette p: CatMascotAnatomy.CatPalette,
        origin: CGPoint,
        angle: CGFloat,
        length: CGFloat,
        isHind: Bool,
        isFar: Bool,
        hasWhiteSock: Bool
    ) {
        let foot = CGPoint(x: origin.x + sin(angle) * length, y: origin.y + cos(angle) * length)
        let dirX = (foot.x - origin.x) / max(0.01, length)
        let dirY = (foot.y - origin.y) / max(0.01, length)
        let perpX = -dirY
        let perpY = dirX

        let kneeBias: CGFloat = isHind ? -2.2 : 1.5
        let mid = CGPoint(
            x: (origin.x + foot.x) * 0.5 + kneeBias,
            y: (origin.y + foot.y) * 0.5 - 0.4
        )
        let topHalfW: CGFloat = isHind ? 3.6 : 3.0
        let midHalfW: CGFloat = isHind ? 2.2 : 1.9
        let ankleHalfW: CGFloat = 1.45

        let limbPath = Path { path in
            path.move(to: CGPoint(x: origin.x + perpX * topHalfW, y: origin.y + perpY * topHalfW))
            path.addQuadCurve(
                to: CGPoint(x: foot.x + perpX * ankleHalfW, y: foot.y + perpY * ankleHalfW),
                control: CGPoint(x: mid.x + perpX * midHalfW, y: mid.y + perpY * midHalfW)
            )
            path.addLine(to: CGPoint(x: foot.x - perpX * ankleHalfW, y: foot.y - perpY * ankleHalfW))
            path.addQuadCurve(
                to: CGPoint(x: origin.x - perpX * topHalfW, y: origin.y - perpY * topHalfW),
                control: CGPoint(x: mid.x - perpX * midHalfW, y: mid.y - perpY * midHalfW)
            )
            path.closeSubpath()
        }

        if isFar {
            ctx.fill(limbPath, with: .color(p.coatShade))
        } else {
            let limbGrad = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [p.coatHighlight, p.coat, p.coatShade]),
                startPoint: origin,
                endPoint: foot
            )
            ctx.fill(limbPath, with: limbGrad)
            ctx.stroke(limbPath, with: .color(p.rimStroke.opacity(0.65)), lineWidth: 0.7)
        }

        if hasWhiteSock {
            let sockStart = CGPoint(
                x: origin.x + (foot.x - origin.x) * 0.72,
                y: origin.y + (foot.y - origin.y) * 0.72
            )
            let sockPath = Path { path in
                path.move(to: CGPoint(x: sockStart.x + perpX * 1.7, y: sockStart.y + perpY * 1.7))
                path.addLine(to: CGPoint(x: foot.x + perpX * ankleHalfW, y: foot.y + perpY * ankleHalfW))
                path.addLine(to: CGPoint(x: foot.x - perpX * ankleHalfW, y: foot.y - perpY * ankleHalfW))
                path.addLine(to: CGPoint(x: sockStart.x - perpX * 1.7, y: sockStart.y - perpY * 1.7))
                path.closeSubpath()
            }
            ctx.fill(sockPath, with: .color(isFar ? p.cream.opacity(0.76) : p.cream))
        }

        let pawRect = CGRect(x: foot.x - 1.5, y: foot.y - 1.6, width: 5.0, height: 3.3)
        let pawColor = hasWhiteSock
            ? (isFar ? p.cream.opacity(0.76) : p.cream)
            : (isFar ? p.coatShade : p.coat)
        ctx.fill(Path(ellipseIn: pawRect), with: .color(pawColor))
        if !isFar {
            ctx.stroke(Path(ellipseIn: pawRect), with: .color(p.rimStroke.opacity(0.5)), lineWidth: 0.6)
        }
    }

    private nonisolated static func drawTail(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        palette p: CatMascotAnatomy.CatPalette,
        rumpPoint: CGPoint,
        metrics m: CatMascotAnatomy.PoseMetrics
    ) {
        let g = CatMascotAnatomy.tailGeometry(rumpPoint: rumpPoint, metrics: m)

        var tailPath = Path()
        tailPath.move(to: rumpPoint)
        tailPath.addCurve(to: g.tip, control1: g.ctrl1, control2: g.ctrl2)

        let tailGrad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [p.coat, p.coatHighlight, p.coatShade]),
            startPoint: rumpPoint,
            endPoint: g.tip
        )
        ctx.stroke(tailPath, with: tailGrad, style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        ctx.stroke(tailPath, with: .color(p.rimStroke.opacity(0.85)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))

        if kind == .blackNightFury {
            // Full V-spread 6-spiked scarlet/black Night-Fury dragon tail fin with structural ribs
            ctx.drawLayer { finCtx in
                finCtx.translateBy(x: g.tip.x, y: g.tip.y)
                finCtx.rotate(by: Angle(radians: Double(g.angle)))

                // Upper/left charcoal-black 3-spiked vane
                let blackFin = Path { path in
                    path.move(to: CGPoint(x: 3.4, y: -0.3))
                    path.addQuadCurve(to: CGPoint(x: 1.8, y: -7.8), control: CGPoint(x: 3.0, y: -4.4))
                    path.addQuadCurve(to: CGPoint(x: -1.2, y: -5.8), control: CGPoint(x: 0.2, y: -6.2))
                    path.addQuadCurve(to: CGPoint(x: -3.8, y: -8.8), control: CGPoint(x: -2.4, y: -7.2))
                    path.addQuadCurve(to: CGPoint(x: -5.2, y: -5.6), control: CGPoint(x: -4.4, y: -6.8))
                    path.addQuadCurve(to: CGPoint(x: -8.5, y: -6.2), control: CGPoint(x: -6.8, y: -5.8))
                    path.addQuadCurve(to: CGPoint(x: -6.2, y: -1.6), control: CGPoint(x: -7.8, y: -3.8))
                    path.addLine(to: CGPoint(x: -2.0, y: -0.5))
                    path.closeSubpath()
                }
                let blackGrad = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [p.coat, p.coatShade]),
                    startPoint: CGPoint(x: 2, y: 0),
                    endPoint: CGPoint(x: -7, y: -8)
                )
                finCtx.fill(blackFin, with: blackGrad)
                finCtx.stroke(blackFin, with: .color(p.rimStroke), lineWidth: 0.65)

                for ribEnd in [CGPoint(x: 1.4, y: -7.0), CGPoint(x: -3.5, y: -8.0), CGPoint(x: -7.6, y: -5.7)] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: -1.0, y: -0.6))
                    rib.addLine(to: ribEnd)
                    finCtx.stroke(rib, with: .color(p.rimStroke.opacity(0.6)), lineWidth: 0.5)
                }

                // Lower/right scarlet 3-spiked prosthetic vane
                let redFin = Path { path in
                    path.move(to: CGPoint(x: 3.6, y: 0.3))
                    path.addQuadCurve(to: CGPoint(x: 2.0, y: 8.2), control: CGPoint(x: 3.2, y: 4.5))
                    path.addQuadCurve(to: CGPoint(x: -1.0, y: 6.1), control: CGPoint(x: 0.5, y: 6.6))
                    path.addQuadCurve(to: CGPoint(x: -4.0, y: 9.4), control: CGPoint(x: -2.4, y: 7.8))
                    path.addQuadCurve(to: CGPoint(x: -5.4, y: 6.0), control: CGPoint(x: -4.6, y: 7.2))
                    path.addQuadCurve(to: CGPoint(x: -8.8, y: 6.6), control: CGPoint(x: -7.1, y: 6.2))
                    path.addQuadCurve(to: CGPoint(x: -6.4, y: 1.6), control: CGPoint(x: -8.0, y: 4.0))
                    path.addLine(to: CGPoint(x: -2.0, y: 0.5))
                    path.closeSubpath()
                }
                let redGrad = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [p.tailFin, p.tailFinShade]),
                    startPoint: CGPoint(x: 2, y: 0),
                    endPoint: CGPoint(x: -7, y: 8)
                )
                finCtx.fill(redFin, with: redGrad)
                finCtx.stroke(redFin, with: .color(Color(red: 0.16, green: 0.05, blue: 0.06)), lineWidth: 0.7)

                for ribEnd in [CGPoint(x: 1.6, y: 7.4), CGPoint(x: -3.7, y: 8.6), CGPoint(x: -8.0, y: 6.0)] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: -1.0, y: 0.6))
                    rib.addLine(to: ribEnd)
                    finCtx.stroke(rib, with: .color(Color(red: 1.0, green: 0.78, blue: 0.72).opacity(0.52)), lineWidth: 0.55)
                }

                // Tiny silver harness rivets along tail spine
                for rx in [-3.4, -1.2, 1.0] as [CGFloat] {
                    let rivet = Path(ellipseIn: CGRect(x: rx - 0.55, y: -0.55, width: 1.1, height: 1.1))
                    finCtx.fill(rivet, with: .color(p.cream.opacity(0.9)))
                }
            }
        } else {
            // Crisp ringed tabby tail bands + dark tip
            for t in [0.24, 0.45, 0.66, 0.85] as [CGFloat] {
                let pt = CatMascotAnatomy.cubicPoint(p0: rumpPoint, p1: g.ctrl1, p2: g.ctrl2, p3: g.tip, t: t)
                let nextPt = CatMascotAnatomy.cubicPoint(
                    p0: rumpPoint,
                    p1: g.ctrl1,
                    p2: g.ctrl2,
                    p3: g.tip,
                    t: min(1.0, t + 0.06)
                )
                let dx = nextPt.x - pt.x
                let dy = nextPt.y - pt.y
                let norm = max(0.01, hypot(dx, dy))
                let nx = -dy / norm * 1.9
                let ny = dx / norm * 1.9
                var ring = Path()
                ring.move(to: CGPoint(x: pt.x - nx, y: pt.y - ny))
                ring.addLine(to: CGPoint(x: pt.x + nx, y: pt.y + ny))
                ctx.stroke(ring, with: .color(p.stripe), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            }
            let tipCap = Path(ellipseIn: CGRect(x: g.tip.x - 1.9, y: g.tip.y - 1.9, width: 3.8, height: 3.8))
            ctx.fill(tipCap, with: .color(p.stripe))
        }
    }

    private nonisolated static func drawHead(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        palette p: CatMascotAnatomy.CatPalette,
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

            // Front ear + inner pinna + ear tufts
            let frontEar = Path { path in
                path.move(to: CGPoint(x: -7.8, y: -4.2))
                path.addQuadCurve(
                    to: CGPoint(x: -6.2 - earPerk * 2, y: -15.5 - earPerk * 4),
                    control: CGPoint(x: -7.8, y: -10.5)
                )
                path.addQuadCurve(
                    to: CGPoint(x: -0.5, y: -7.2),
                    control: CGPoint(x: -2.6, y: -12.2)
                )
                path.closeSubpath()
            }
            hCtx.fill(frontEar, with: .color(p.coat))
            hCtx.stroke(frontEar, with: .color(p.rimStroke), lineWidth: 0.9)

            let innerEar = Path { path in
                path.move(to: CGPoint(x: -5.9, y: -6.0))
                path.addLine(to: CGPoint(x: -5.3 - earPerk * 1.4, y: -12.8 - earPerk * 3))
                path.addLine(to: CGPoint(x: -2.0, y: -7.5))
                path.closeSubpath()
            }
            hCtx.fill(innerEar, with: .color(p.innerEar))

            var earTuft = Path()
            earTuft.move(to: CGPoint(x: -5.2, y: -6.4))
            earTuft.addLine(to: CGPoint(x: -3.2, y: -8.6))
            hCtx.stroke(earTuft, with: .color(p.cream.opacity(0.55)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

            // Sculpted feline head: cranium + cheek pad/jowl + tapered snout
            let sculptedHead = Path { path in
                path.move(to: CGPoint(x: -10.4, y: -1.2))
                path.addCurve(
                    to: CGPoint(x: 0.5, y: -9.4),
                    control1: CGPoint(x: -10.4, y: -7.0),
                    control2: CGPoint(x: -5.2, y: -9.8)
                )
                path.addCurve(
                    to: CGPoint(x: 9.8, y: -2.2),
                    control1: CGPoint(x: 5.2, y: -9.0),
                    control2: CGPoint(x: 8.6, y: -6.2)
                )
                path.addQuadCurve(to: CGPoint(x: 11.2, y: 1.8), control: CGPoint(x: 11.4, y: -0.2))
                path.addCurve(
                    to: CGPoint(x: 2.5, y: 8.6),
                    control1: CGPoint(x: 10.6, y: 6.2),
                    control2: CGPoint(x: 6.8, y: 8.8)
                )
                path.addCurve(
                    to: CGPoint(x: -10.4, y: -1.2),
                    control1: CGPoint(x: -4.8, y: 8.6),
                    control2: CGPoint(x: -10.4, y: 4.5)
                )
                path.closeSubpath()
            }

            let headGrad = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: p.coatHighlight, location: 0.0),
                    .init(color: p.coat, location: 0.55),
                    .init(color: p.coatShade, location: 1.0),
                ]),
                startPoint: CGPoint(x: -4, y: -9),
                endPoint: CGPoint(x: 4, y: 9)
            )
            hCtx.fill(sculptedHead, with: headGrad)
            hCtx.stroke(sculptedHead, with: .color(p.rimStroke), lineWidth: 1.05)

            // Cheek pad highlight
            let cheekPad = Path(ellipseIn: CGRect(x: -5.0, y: 1.0, width: 7.4, height: 5.5))
            hCtx.fill(cheekPad, with: .color(p.coatHighlight.opacity(0.32)))

            if kind == .brownTabby {
                // Cream muzzle & chin
                let muzzle = Path(ellipseIn: CGRect(x: 0.2, y: -0.2, width: 10.4, height: 8.0))
                hCtx.fill(muzzle, with: .color(p.cream))

                // Classic "M" forehead tabby marking + cheek stripes
                let mBrow = Path { path in
                    path.move(to: CGPoint(x: -5.4, y: -6.4))
                    path.addLine(to: CGPoint(x: -3.4, y: -4.8))
                    path.addLine(to: CGPoint(x: -1.4, y: -6.6))
                    path.addLine(to: CGPoint(x: 0.4, y: -4.7))
                    path.addLine(to: CGPoint(x: 2.2, y: -6.2))
                }
                hCtx.stroke(mBrow, with: .color(p.stripe), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))

                var cheekLine = Path()
                cheekLine.move(to: CGPoint(x: -4.5, y: 1.6))
                cheekLine.addQuadCurve(to: CGPoint(x: -0.4, y: 2.4), control: CGPoint(x: -2.4, y: 1.2))
                hCtx.stroke(cheekLine, with: .color(p.stripe.opacity(0.8)), style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            }

            // Expressive almond eye with gradient iris & vertical slit pupil
            let eyeH: CGFloat = isAlertEyes ? 4.6 : 4.0
            let eyeRect = CGRect(x: 1.6, y: -3.9, width: 4.3, height: eyeH)
            let eyeGrad = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [p.eyeIris, p.eyeIrisDeep]),
                startPoint: CGPoint(x: eyeRect.midX, y: eyeRect.minY),
                endPoint: CGPoint(x: eyeRect.midX, y: eyeRect.maxY)
            )
            hCtx.fill(Path(ellipseIn: eyeRect), with: eyeGrad)
            let pupilW: CGFloat = isAlertEyes ? 1.9 : 1.3
            let pupilRect = CGRect(x: 3.8 - pupilW * 0.5, y: -3.3, width: pupilW, height: eyeH - 1.1)
            hCtx.fill(Path(ellipseIn: pupilRect), with: .color(Color.black.opacity(0.92)))
            let glint = Path(ellipseIn: CGRect(x: 2.3, y: -3.2, width: 1.2, height: 1.2))
            hCtx.fill(glint, with: .color(LunaTheme.moonlight.opacity(0.92)))

            // Nose + subtle feline smile
            let nose = Path { path in
                path.move(to: CGPoint(x: 8.8, y: 0.2))
                path.addLine(to: CGPoint(x: 11.1, y: 0.4))
                path.addLine(to: CGPoint(x: 9.8, y: 2.1))
                path.closeSubpath()
            }
            hCtx.fill(nose, with: .color(p.nose))

            var smile = Path()
            smile.move(to: CGPoint(x: 9.8, y: 2.1))
            smile.addQuadCurve(to: CGPoint(x: 7.4, y: 3.4), control: CGPoint(x: 9.0, y: 3.6))
            hCtx.stroke(smile, with: .color(p.stripe.opacity(0.85)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

            // Delicate whiskers
            for angleW in [-0.15, 0.0, 0.13] {
                var w = Path()
                w.move(to: CGPoint(x: 7.2, y: 2.2))
                w.addLine(to: CGPoint(x: 14.5, y: 2.2 + CGFloat(angleW) * 14.0))
                hCtx.stroke(w, with: .color(p.cream.opacity(0.58)), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
            }
        }
    }

    // MARK: - Curled Sleeping Pose

    private nonisolated static func drawCurledSleeping(
        in ctx: inout GraphicsContext,
        kind: CatSpriteKind,
        breathPhase: Double
    ) {
        let p = CatMascotAnatomy.palette(for: kind)
        let breath = CGFloat(sin(breathPhase)) * 1.3

        ctx.drawLayer { layer in
            let bodyRect = CGRect(x: 14, y: 22 - breath * 0.5, width: 48, height: 26 + breath)
            let bodyPath = Path(ellipseIn: bodyRect)
            let bodyGrad = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [p.coatHighlight, p.coat, p.coatShade]),
                startPoint: CGPoint(x: 38, y: 21),
                endPoint: CGPoint(x: 38, y: 48)
            )
            layer.fill(bodyPath, with: bodyGrad)
            layer.stroke(bodyPath, with: .color(p.rimStroke), lineWidth: 1.05)

            if kind == .brownTabby {
                for sx in [26.0, 34.0, 42.0] as [CGFloat] {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: sx, y: 23 - breath * 0.3))
                    stripe.addQuadCurve(to: CGPoint(x: sx - 2.0, y: 34), control: CGPoint(x: sx - 4.0, y: 28))
                    layer.stroke(stripe, with: .color(p.stripe), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                let paw = Path(ellipseIn: CGRect(x: 42, y: 42, width: 7.5, height: 4.5))
                layer.fill(paw, with: .color(p.cream))
            } else {
                let spot = Path(ellipseIn: CGRect(x: 43.5, y: 38.5, width: 6.2, height: 4.5))
                layer.fill(spot, with: .color(p.cream.opacity(0.95)))
            }

            var wrapTail = Path()
            wrapTail.move(to: CGPoint(x: 17, y: 37))
            wrapTail.addCurve(
                to: CGPoint(x: 47, y: 46.5),
                control1: CGPoint(x: 16, y: 48),
                control2: CGPoint(x: 34, y: 49.5)
            )
            layer.stroke(wrapTail, with: .color(p.coatShade), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))

            if kind == .blackNightFury {
                let fin = Path { path in
                    path.move(to: CGPoint(x: 46, y: 46.5))
                    path.addQuadCurve(to: CGPoint(x: 56.5, y: 41.5), control: CGPoint(x: 52.5, y: 49.5))
                    path.addLine(to: CGPoint(x: 51.8, y: 43.2))
                    path.closeSubpath()
                }
                layer.fill(fin, with: .color(p.tailFin))
            }

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

            var eyeArc = Path()
            eyeArc.move(to: CGPoint(x: headCenter.x + 0.5, y: headCenter.y - 1.0))
            eyeArc.addQuadCurve(
                to: CGPoint(x: headCenter.x + 6.0, y: headCenter.y - 0.5),
                control: CGPoint(x: headCenter.x + 3.2, y: headCenter.y + 2.0)
            )
            layer.stroke(eyeArc, with: .color(p.eyeIris.opacity(0.92)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
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
