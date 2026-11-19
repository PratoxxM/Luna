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
            return kind == .listRow ? .clear : LunaTheme.warmBorderSubtle
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
        let resolvedAccent = customAccent ? accentColor : roomAtmosphere.lampColor
        let resolvedStrength = customAccent ? LunaTokens.Glow.lampStrength : roomAtmosphere.lampStrength
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let activeBorderColor = LunaFocusStyle.borderColor(
            for: kind,
            isFocused: isFocused,
            accentColor: kind == .card ? LunaTheme.focusGoldBorder : resolvedAccent
        )
        let glowColor: Color = isFocused ? resolvedAccent.opacity(resolvedStrength) : .clear
        let scale = LunaFocusStyle.scaleEffect(for: kind, isFocused: isFocused)

        content
            .overlay(
                Group {
                    if kind == .listRow && isFocused {
                        HStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(resolvedAccent)
                                .frame(width: 4)
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                    } else {
                        shape.strokeBorder(activeBorderColor, lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0)
                    }
                }
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

/// Companion focus chrome applied around `.buttonStyle(.card)` labels so Apple TV's native
/// lift & parallax remain intact while adding the `1.5 pt` gold frame and warm under-glow.
@MainActor
private struct LunaCardFocusFrameModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let cornerRadius: CGFloat
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isFocused
                        ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
                        : LunaTheme.warmBorderSubtle,
                    lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                )
                .transaction { $0.animation = nil }
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.10 : 0.0),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                x: 0,
                y: isFocused ? LunaFocusStyle.glowOffsetY : 0
            )
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusFade, value: isFocused)
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
        isFocused: Bool
    ) -> some View {
        modifier(
            LunaCardFocusFrameModifier(
                cornerRadius: cornerRadius,
                isFocused: isFocused
            )
        )
    }
}
