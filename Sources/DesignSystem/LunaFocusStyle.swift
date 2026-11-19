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

    let kind: LunaFocusKind
    let isFocused: Bool
    let cornerRadius: CGFloat
    let accentColor: Color

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
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let activeBorderColor = LunaFocusStyle.borderColor(for: kind, isFocused: isFocused, accentColor: accentColor)
        let glowColor: Color = isFocused ? accentColor.opacity(LunaTokens.Glow.lampStrength) : .clear
        let scale = LunaFocusStyle.scaleEffect(for: kind, isFocused: isFocused)

        content
            .overlay(
                Group {
                    if kind == .listRow && isFocused {
                        HStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(accentColor)
                                .frame(width: 3)
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                    } else {
                        shape.strokeBorder(activeBorderColor, lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0)
                    }
                }
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
                accentColor: accentColor
            )
        )
    }
}
