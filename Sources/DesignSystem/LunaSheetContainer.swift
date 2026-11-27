import SwiftUI

public enum LunaSheetWidth: Sendable {
    case narrow
    case wide

    public var maxWidth: CGFloat {
        switch self {
        case .narrow: return LunaTokens.Layout.sheetNarrowW
        case .wide: return LunaTokens.Layout.sheetWideW
        }
    }
}

/// Canonical Lampelys modal sheet container (`880 pt` narrow / `1240 pt` wide, `48 pt` padding,
/// `r24` `Surface.sheet` + `0.5 pt` top light edge, zero internal header dividers).
public struct LunaSheetContainer<Content: View>: View {
    let title: String
    let titleUsesSerif: Bool
    let subtitle: String?
    let trailingMeta: String?
    let width: LunaSheetWidth
    let maxHeight: CGFloat?
    let onClose: (() -> Void)?
    @ViewBuilder let content: () -> Content

    public init(
        title: String,
        titleUsesSerif: Bool = false,
        subtitle: String? = nil,
        trailingMeta: String? = nil,
        width: LunaSheetWidth = .narrow,
        maxHeight: CGFloat? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleUsesSerif = titleUsesSerif
        self.subtitle = subtitle
        self.trailingMeta = trailingMeta
        self.width = width
        self.maxHeight = maxHeight
        self.onClose = onClose
        self.content = content
    }

    public nonisolated static func resolveTitleFont(usesSerif: Bool) -> SwiftUI.Font {
        usesSerif ? LunaTheme.Font.titleSerif : LunaTheme.Font.pageTitle
    }

    public var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Self.resolveTitleFont(usesSerif: titleUsesSerif))
                            .foregroundStyle(LunaTheme.linen)
                            .lineLimit(2)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(LunaTheme.Font.subtitle)
                                .foregroundStyle(LunaTheme.muted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 16)

                    if let trailingMeta, !trailingMeta.isEmpty {
                        Text(trailingMeta)
                            .font(LunaTheme.Font.caption.monospacedDigit())
                            .foregroundStyle(LunaTheme.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, LunaTokens.Layout.sheetPadding)
                .padding(.top, LunaTokens.Layout.sheetPadding)
                .padding(.bottom, LunaTokens.Layout.blockGap * 0.5)

                content()
                    .padding(.top, LunaTokens.Layout.blockGap * 0.5)
                    .padding(.horizontal, LunaTokens.Layout.sheetPadding)
                    .padding(.bottom, LunaTokens.Layout.sheetPadding)
                    .clipped()
            }
            .frame(maxWidth: width.maxWidth, maxHeight: maxHeight, alignment: .topLeading)
            .lunaCinemaGlassSurface(fill: LunaTokens.Surface.sheet, clipsContent: true)
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, LunaTokens.Layout.safeBottom)
        }
        .onExitCommand {
            onClose?()
        }
    }
}

private struct LunaCinemaGlassSurfaceModifier: ViewModifier {
    let fill: Color
    let cornerRadius: CGFloat
    let topEdgeColor: Color
    let sideEdgeColor: Color
    let shadowColor: Color?
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let clipsContent: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let base = clippedContent(content.background(shape.fill(fill)), shape: shape)
            .lunaTopLightEdge(
                cornerRadius: cornerRadius,
                topColor: topEdgeColor,
                sideColor: sideEdgeColor,
                lineWidth: LunaTokens.Layout.hairlineWidth
            )
        if let shadowColor {
            base.shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        } else {
            base
        }
    }

    @ViewBuilder
    private func clippedContent<V: View>(_ view: V, shape: RoundedRectangle) -> some View {
        if clipsContent {
            view.clipShape(shape)
        } else {
            view
        }
    }
}

public extension View {
    func lunaCinemaGlassSurface(
        fill: Color = LunaTheme.cinemaGlass,
        cornerRadius: CGFloat = LunaTokens.Radius.panel,
        topEdgeColor: Color = LunaTokens.Edge.top3,
        sideEdgeColor: Color = LunaTokens.Edge.top1,
        shadowColor: Color? = nil,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0,
        clipsContent: Bool = false
    ) -> some View {
        modifier(
            LunaCinemaGlassSurfaceModifier(
                fill: fill,
                cornerRadius: cornerRadius,
                topEdgeColor: topEdgeColor,
                sideEdgeColor: sideEdgeColor,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                clipsContent: clipsContent
            )
        )
    }
}
