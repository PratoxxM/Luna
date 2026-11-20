import SwiftUI

/// Exact circle-circle intersection geometry for the crescent moon brand mark.
public enum LunaCrescentGeometry {
    public nonisolated static func crescentPoints(
        side: CGFloat,
        center: CGPoint,
        stepsPerArc: Int = 64
    ) -> [CGPoint] {
        guard side > 0, stepsPerArc >= 8 else { return [] }
        let c1 = center
        let r1 = side * 0.42
        let c2 = CGPoint(x: center.x + side * 0.17, y: center.y - side * 0.11)
        let r2 = side * 0.345

        let dx = c2.x - c1.x
        let dy = c2.y - c1.y
        let d = hypot(dx, dy)
        guard d > abs(r1 - r2), d < r1 + r2 else { return [] }

        let a = (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
        let h = sqrt(max(0, r1 * r1 - a * a))
        let mx = c1.x + a * (dx / d)
        let my = c1.y + a * (dy / d)
        let rx = -dy * (h / d)
        let ry = dx * (h / d)

        let pTop = CGPoint(x: mx - rx, y: my - ry)
        let pBot = CGPoint(x: mx + rx, y: my + ry)

        let t1Bot = atan2(pBot.y - c1.y, pBot.x - c1.x)
        var t1Top = atan2(pTop.y - c1.y, pTop.x - c1.x)
        if t1Top <= t1Bot {
            t1Top += 2.0 * .pi
        }

        let t2Top = atan2(pTop.y - c2.y, pTop.x - c2.x)
        var t2Bot = atan2(pBot.y - c2.y, pBot.x - c2.x)
        if t2Bot >= t2Top {
            t2Bot -= 2.0 * .pi
        }

        var points: [CGPoint] = []
        points.reserveCapacity(stepsPerArc * 2)

        for i in 0...stepsPerArc {
            let frac = CGFloat(i) / CGFloat(stepsPerArc)
            let ang = t1Bot + (t1Top - t1Bot) * frac
            points.append(CGPoint(x: c1.x + r1 * cos(ang), y: c1.y + r1 * sin(ang)))
        }
        for i in 1..<stepsPerArc {
            let frac = CGFloat(i) / CGFloat(stepsPerArc)
            let ang = t2Top + (t2Bot - t2Top) * frac
            points.append(CGPoint(x: c2.x + r2 * cos(ang), y: c2.y + r2 * sin(ang)))
        }

        return points
    }
}

/// Clean single-path vector crescent moon brand mark filled without even-odd cutter artifacts.
public struct LunaCrescentMarkView: View {
    public var size: CGFloat
    public var color: Color

    public init(size: CGFloat = 28, color: Color = LunaTheme.amber) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            let points = LunaCrescentGeometry.crescentPoints(side: side, center: center)
            guard let first = points.first else { return }

            var path = Path()
            path.move(to: first)
            for pt in points.dropFirst() {
                path.addLine(to: pt)
            }
            path.closeSubpath()
            context.fill(path, with: .color(color), style: FillStyle(eoFill: false))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
