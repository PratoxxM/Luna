import SwiftUI

/// Clean vector crescent moon brand mark rendered with even-odd fill.
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
            let outerR = side * 0.44
            let innerR = side * 0.36
            let cutOffset = CGPoint(x: side * 0.17, y: -side * 0.12)

            var path = Path()
            path.addEllipse(
                in: CGRect(
                    x: center.x - outerR,
                    y: center.y - outerR,
                    width: outerR * 2,
                    height: outerR * 2
                )
            )
            path.addEllipse(
                in: CGRect(
                    x: center.x + cutOffset.x - innerR,
                    y: center.y + cutOffset.y - innerR,
                    width: innerR * 2,
                    height: innerR * 2
                )
            )
            context.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
