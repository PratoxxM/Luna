import SwiftUI

public enum LunaFocusKind: Sendable {
    case card
    case secondaryPill
    case primaryPlay
    case listRow
}

public enum LunaFocusStyle {
    public static let springResponse: Double = LunaTokens.Motion.focusSpringResponse
    public static let springDamping: Double = LunaTokens.Motion.focusSpringDamping
    public static let borderWidth: CGFloat = LunaTokens.Layout.focusBorderWidth
    public static let borderOpacity: Double = LunaTokens.Layout.focusBorderOpacity
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
        case .card, .listRow:
            return 1.0
        case .secondaryPill:
            return 1.03
        case .primaryPlay:
            return 1.04
        }
    }

    public nonisolated static func borderColor(for kind: LunaFocusKind, isFocused: Bool, accentColor: Color = LunaTheme.amber) -> Color {
        guard isFocused else {
            return .clear
        }
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
        let glowColor: Color = isFocused ? resolvedGlow.opacity(resolvedStrength) : .clear
        let scale = LunaFocusStyle.scaleEffect(for: kind, isFocused: isFocused)

        content
            .overlay(
                Group {
                    if isFocused {
                        if kind == .listRow {
                            HStack {
                                Capsule()
                                    .fill(markerColor)
                                    .frame(width: LunaFocusStyle.listMarkerWidth)
                                    .padding(.vertical, 10)
                                Spacer(minLength: 0)
                            }
                            .overlay(
                                shape.strokeBorder(
                                    LunaTheme.focusGoldBorder.opacity(0.45),
                                    lineWidth: 1.0
                                )
                            )
                        } else if kind == .primaryPlay {
                            shape.strokeBorder(
                                LunaTheme.topLightEdgeGradient(topColor: LunaTheme.warmBorderBase.opacity(0.26)),
                                lineWidth: 1.0
                            )
                        } else {
                            shape.strokeBorder(activeBorderColor, lineWidth: LunaFocusStyle.borderWidth)
                        }
                    } else if kind == .primaryPlay {
                        shape.strokeBorder(
                            LunaTheme.topLightEdgeGradient(topColor: LunaTheme.warmBorderBase.opacity(0.16)),
                            lineWidth: 1.0
                        )
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .shadow(
                color: glowColor,
                radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                x: 0,
                y: isFocused ? LunaFocusStyle.glowOffsetY : 0
            )
            .scaleEffect(scale)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
    }
}

/// Inner focus frame applied to `.buttonStyle(.card)` labels: zero resting border on posters
/// (so posters truly ignite on focus) and `1.5 pt` 70% gold frame when focused.
@MainActor
private struct LunaCardFocusFrameModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let isFocused: Bool
    let showRestingTopEdge: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
                            lineWidth: 1.0
                        )
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
    }
}

/// Outer warm lamp glow placed outside `.buttonStyle(.card)` so tvOS's card mask never clips the under-glow.
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
