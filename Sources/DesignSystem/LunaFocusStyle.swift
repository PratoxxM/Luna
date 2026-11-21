import SwiftUI

public enum LunaFocusKind: Sendable {
    case card
    case control
    case listRow
}

public enum LunaFocusStyle {
    public static let springResponse: Double = LunaTokens.Motion.focusSpringResponse
    public static let springDamping: Double = LunaTokens.Motion.focusSpringDamping
    public static let borderWidth: CGFloat = LunaTokens.Layout.focusBorderWidth
    public static let borderOpacity: Double = Double(LunaTokens.Layout.focusBorderOpacity)
    public static let glowBlur: CGFloat = LunaTokens.Layout.focusGlowBlur
    public static let glowOffsetY: CGFloat = LunaTokens.Layout.focusGlowOffsetY
    public static let fadeSeconds: Double = LunaTokens.Motion.focusFadeSeconds
    public static let listMarkerWidth: CGFloat = 3.0

    public static var focusSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    public static var focusFade: Animation {
        .easeOut(duration: fadeSeconds)
    }

    public nonisolated static func scaleEffect(for kind: LunaFocusKind, isFocused: Bool) -> CGFloat {
        guard isFocused else { return 1.0 }
        switch kind {
        case .card:
            return LunaTokens.Layout.focusScaleCard
        case .control:
            return LunaTokens.Layout.focusScaleControl
        case .listRow:
            return LunaTokens.Layout.focusScaleRow
        }
    }

    public nonisolated static func borderColor(
        for kind: LunaFocusKind,
        isFocused: Bool,
        accentColor: Color = LunaTheme.amber
    ) -> Color {
        guard isFocused else { return .clear }
        return accentColor.opacity(borderOpacity)
    }
}

@MainActor
public struct LunaFocusSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let kind: LunaFocusKind
    let isFocused: Bool
    let cornerRadius: CGFloat
    let accentColor: Color
    let customAccent: Bool

    public init(
        kind: LunaFocusKind,
        isFocused: Bool,
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        accentColor: Color = LunaTheme.amber
    ) {
        self.kind = kind
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.customAccent = false
    }

    internal init(
        kind: LunaFocusKind,
        isFocused: Bool,
        cornerRadius: CGFloat,
        accentColor: Color,
        useRoomAtmosphere: Bool
    ) {
        self.kind = kind
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.customAccent = !useRoomAtmosphere
    }

    public func body(content: Content) -> some View {
        let isDestructive = customAccent && accentColor == LunaTheme.coral
        let resolvedGlow = customAccent ? accentColor : roomAtmosphere.lampColor
        let resolvedStrength = customAccent ? LunaTokens.Glow.lampStrength : roomAtmosphere.lampStrength
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let borderBase = customAccent ? accentColor : LunaTheme.focusGoldBorder
        let activeBorderColor = LunaFocusStyle.borderColor(
            for: kind,
            isFocused: isFocused,
            accentColor: borderBase
        )
        let markerColor = customAccent ? accentColor : LunaTheme.amber

        let glowColor: Color = {
            guard isFocused else { return .clear }
            switch kind {
            case .listRow:
                return .clear
            case .control:
                return isDestructive ? .clear : resolvedGlow.opacity(resolvedStrength)
            case .card:
                return resolvedGlow.opacity(resolvedStrength)
            }
        }()

        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: kind, isFocused: isFocused)

        content
            .overlay(
                Group {
                    if isFocused {
                        switch kind {
                        case .listRow:
                            HStack {
                                Capsule()
                                    .fill(markerColor)
                                    .frame(width: LunaFocusStyle.listMarkerWidth)
                                    .padding(.vertical, 12)
                                Spacer(minLength: 0)
                            }
                        case .control:
                            if isDestructive {
                                shape.strokeBorder(
                                    LunaTheme.coral.opacity(LunaFocusStyle.borderOpacity),
                                    lineWidth: LunaFocusStyle.borderWidth
                                )
                            }
                        case .card:
                            shape.strokeBorder(
                                activeBorderColor,
                                lineWidth: LunaFocusStyle.borderWidth
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .shadow(
                color: glowColor,
                radius: glowColor == .clear ? 0 : LunaFocusStyle.glowBlur,
                x: 0,
                y: glowColor == .clear ? 0 : LunaFocusStyle.glowOffsetY
            )
            .scaleEffect(scale)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
    }
}

/// Inner focus frame applied to card labels: zero resting border on posters/backdrops,
/// crisp `2.0 pt` 85% gold frame on focus, and unified `1.05x` card scale.
@MainActor
private struct LunaCardFocusFrameModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let isFocused: Bool
    let showRestingTopEdge: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: .card, isFocused: isFocused)

        content
            .clipShape(shape)
            .overlay(
                Group {
                    if isFocused {
                        shape.strokeBorder(
                            LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity),
                            lineWidth: LunaFocusStyle.borderWidth
                        )
                    } else if showRestingTopEdge {
                        shape.strokeBorder(
                            LunaTheme.topLightEdgeGradient(topColor: LunaTokens.Edge.top2),
                            lineWidth: LunaTokens.Layout.hairlineWidth
                        )
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .scaleEffect(scale)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
    }
}

/// Outer warm lamp glow placed outside card clipping masks so tvOS never clips the under-glow.
@MainActor
private struct LunaCardLampGlowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                x: 0,
                y: isFocused ? LunaFocusStyle.glowOffsetY : 0
            )
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
    }
}

public extension View {
    func lunaFocusSurface(
        _ kind: LunaFocusKind,
        isFocused: Bool,
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        accentColor: Color = LunaTheme.amber
    ) -> some View {
        modifier(
            LunaFocusSurfaceModifier(
                kind: kind,
                isFocused: isFocused,
                cornerRadius: cornerRadius,
                accentColor: accentColor,
                useRoomAtmosphere: accentColor == LunaTheme.amber
            )
        )
    }

    func lunaCardFocusFrame(
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        isFocused: Bool,
        showRestingTopEdge: Bool = false
    ) -> some View {
        modifier(
            LunaCardFocusFrameModifier(
                cornerRadius: cornerRadius,
                isFocused: isFocused,
                showRestingTopEdge: showRestingTopEdge
            )
        )
    }

    func lunaCardLampGlow(isFocused: Bool) -> some View {
        modifier(LunaCardLampGlowModifier(isFocused: isFocused))
    }
}
