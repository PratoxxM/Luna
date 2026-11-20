import SwiftUI

/// Replaces `.buttonStyle(.plain)` across Luna so tvOS 18–26+ never injects a bright
/// white rectangular system platter behind custom pill buttons.
public struct LunaChromelessButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .focusEffectDisabled(true)
            .animation(.easeOut(duration: LunaTokens.Motion.pressDuration), value: configuration.isPressed)
    }
}

public enum LunaButtonProminence: Sendable {
    case primaryAmber
    case glassPill
    case subtleChip
}

public enum LunaButtonAccent: Sendable {
    case amber
    case emerald
    case warn
    case coral

    public var color: Color {
        switch self {
        case .amber: return LunaTheme.amber
        case .emerald: return LunaTheme.emerald
        case .warn: return LunaTheme.warn
        case .coral: return LunaTheme.coral
        }
    }
}

public enum LunaButtonSize: Sendable {
    case regular
    case compact
}

public struct LunaPillButton: View {
    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize
    let action: () -> Void

    @FocusState private var isDirectFocused: Bool

    public init(
        _ title: String,
        systemImage: String? = nil,
        badgeText: String? = nil,
        isSelected: Bool = false,
        prominence: LunaButtonProminence = .glassPill,
        accent: LunaButtonAccent = .amber,
        size: LunaButtonSize = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.isSelected = isSelected
        self.prominence = prominence
        self.accent = accent
        self.size = size
        self.action = action
    }

    public nonisolated static func resolveIconForeground(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
        }
        if isFocused {
            return accent == .emerald && isSelected ? LunaTheme.emerald : LunaTheme.linen
        }
        if accent == .warn {
            return LunaTheme.warn
        }
        if isSelected {
            return accent == .emerald ? LunaTheme.emerald : LunaTheme.linen
        }
        return LunaTheme.moonlight
    }

    public nonisolated static func resolveLabelForeground(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
        }
        if isFocused {
            return LunaTheme.linen
        }
        if accent == .warn {
            return LunaTheme.warn
        }
        if isSelected {
            return LunaTheme.linen
        }
        return LunaTheme.moonlight
    }

    public nonisolated static func resolveBorderColor(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused {
            if accent == .coral && prominence != .primaryAmber {
                return LunaTheme.coral.opacity(0.85)
            }
            return LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
        }
        switch prominence {
        case .primaryAmber:
            return LunaTheme.focusGoldBorder.opacity(0.45)
        case .glassPill, .subtleChip:
            if accent == .coral {
                return LunaTheme.coral.opacity(0.42)
            }
            if accent == .warn {
                return LunaTheme.warn.opacity(0.42)
            }
            if prominence == .subtleChip {
                return Color.clear
            }
            if isSelected {
                return accent == .emerald ? LunaTheme.emerald.opacity(0.38) : LunaTokens.Accent.border
            }
            return LunaTheme.warmBorder
        }
    }

    public var body: some View {
        Button(action: action) {
            LunaPillLabel(
                title: title,
                systemImage: systemImage,
                badgeText: badgeText,
                isSelected: isSelected,
                prominence: prominence,
                accent: accent,
                size: size,
                externalFocus: isDirectFocused
            )
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
        .focused($isDirectFocused)
    }
}

private struct LunaPillLabel: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize
    let externalFocus: Bool

    private var effectiveFocused: Bool {
        isFocused || externalFocus
    }

    var body: some View {
        let isCompact = size == .compact
        let scale: CGFloat = effectiveFocused
            ? (prominence == .primaryAmber ? 1.04 : 1.03)
            : 1.0

        HStack(spacing: isCompact ? 8 : 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(isCompact ? LunaTheme.Font.compactPillIcon : LunaTheme.Font.pillIcon)
                    .foregroundStyle(iconForegroundColor)
            }
            if !title.isEmpty {
                Text(title)
                    .font(isCompact ? LunaTheme.Font.compactPillLabel : LunaTheme.Font.pillLabel)
                    .foregroundStyle(labelForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(LunaTheme.Font.compactPillBadge)
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeBackground))
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 14 : 16) : (isCompact ? 16 : 20))
        .padding(.vertical, isCompact ? 9 : 11)
        .background(backgroundView)
        .overlay(
            Group {
                if effectiveFocused || prominence == .primaryAmber || accent == .coral || accent == .warn || (prominence == .glassPill && isSelected) {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                } else if prominence == .glassPill {
                    Capsule()
                        .strokeBorder(
                            LunaTheme.topLightEdgeGradient(
                                topColor: LunaTokens.Edge.top3,
                                sideColor: LunaTokens.Edge.top1.opacity(0.45)
                            ),
                            lineWidth: 1.0
                        )
                }
            }
            .transaction { $0.animation = nil }
        )
        .shadow(
            color: effectiveFocused ? glowAccentColor.opacity(roomAtmosphere.lampStrength) : .clear,
            radius: effectiveFocused ? LunaFocusStyle.glowBlur : 0,
            x: 0,
            y: effectiveFocused ? LunaFocusStyle.glowOffsetY : 0
        )
        .scaleEffect(scale)
        .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: effectiveFocused)
    }

    private var glowAccentColor: Color {
        switch accent {
        case .amber: return roomAtmosphere.lampColor
        case .emerald: return LunaTheme.emerald
        case .warn: return LunaTheme.warn
        case .coral: return LunaTheme.coral
        }
    }

    private var iconForegroundColor: Color {
        LunaPillButton.resolveIconForeground(
            isFocused: effectiveFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var labelForegroundColor: Color {
        LunaPillButton.resolveLabelForeground(
            isFocused: effectiveFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var badgeForegroundColor: Color {
        if prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
        }
        if effectiveFocused || isSelected {
            return LunaTheme.linen
        }
        return LunaTheme.muted
    }

    private var restingSolidColor: Color {
        switch prominence {
        case .primaryAmber:
            return .clear
        case .glassPill:
            return isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised
        case .subtleChip:
            return isSelected ? LunaTheme.surfaceElevated : Color.clear
        }
    }

    private var focusedSecondaryFill: Color {
        if accent == .coral {
            return LunaTokens.Status.dangerBg
        }
        return LunaTheme.surfaceElevated
    }

    private var backgroundView: some View {
        ZStack {
            if prominence == .primaryAmber {
                Capsule()
                    .fill(LunaTheme.primaryAmberGradient)
                    .opacity(effectiveFocused ? 0 : 1)
                Capsule()
                    .fill(LunaTheme.playFocusGradient)
                    .opacity(effectiveFocused ? 1 : 0)
            } else {
                Capsule()
                    .fill(effectiveFocused ? focusedSecondaryFill : restingSolidColor)
                    .overlay {
                        if !effectiveFocused && prominence == .glassPill && isSelected && accent == .amber {
                            Capsule().fill(LunaTokens.Accent.soft)
                        }
                    }
            }
        }
        .transaction { $0.animation = nil }
    }

    private var borderColor: Color {
        LunaPillButton.resolveBorderColor(
            isFocused: effectiveFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var borderWidth: CGFloat {
        effectiveFocused ? LunaFocusStyle.borderWidth : 1.0
    }

    private var badgeBackground: Color {
        if prominence == .primaryAmber {
            return LunaTheme.canvas.opacity(0.16)
        }
        if effectiveFocused || isSelected {
            return LunaTheme.warmBorderBase.opacity(0.14)
        }
        return LunaTheme.warmBorderBase.opacity(0.08)
    }
}
