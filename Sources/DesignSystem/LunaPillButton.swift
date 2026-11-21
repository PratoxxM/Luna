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
    case primary
    case glassPill
    case subtleChip

    @available(*, deprecated, renamed: "primary")
    public static let primaryAmber: Self = .primary
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
    let showsTrailingDot: Bool
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
        showsTrailingDot: Bool = false,
        isSelected: Bool = false,
        prominence: LunaButtonProminence = .glassPill,
        accent: LunaButtonAccent = .amber,
        size: LunaButtonSize = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.showsTrailingDot = showsTrailingDot
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
        if isFocused {
            if accent == .coral && prominence != .primary {
                return LunaTheme.coral
            }
            return LunaTokens.Text.onAccent
        }
        switch prominence {
        case .primary:
            return LunaTheme.amber
        case .glassPill, .subtleChip:
            if accent == .coral { return LunaTheme.coral }
            if accent == .warn { return LunaTheme.warn }
            if isSelected {
                return accent == .emerald ? LunaTheme.emerald : LunaTheme.linen
            }
            return LunaTheme.moonlight
        }
    }

    public nonisolated static func resolveLabelForeground(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused {
            if accent == .coral && prominence != .primary {
                return LunaTheme.coral
            }
            return LunaTokens.Text.onAccent
        }
        switch prominence {
        case .primary:
            return LunaTheme.linen
        case .glassPill, .subtleChip:
            if accent == .coral { return LunaTheme.coral }
            if accent == .warn { return LunaTheme.warn }
            if isSelected { return LunaTheme.linen }
            return LunaTheme.moonlight
        }
    }

    public nonisolated static func resolveBorderColor(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused {
            if accent == .coral && prominence != .primary {
                return LunaTheme.coral.opacity(LunaFocusStyle.borderOpacity)
            }
            return .clear
        }
        switch prominence {
        case .primary:
            return LunaTokens.Accent.border
        case .glassPill:
            return isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorder
        case .subtleChip:
            return .clear
        }
    }

    public var body: some View {
        Button(action: action) {
            LunaPillLabel(
                title: title,
                systemImage: systemImage,
                badgeText: badgeText,
                showsTrailingDot: showsTrailingDot,
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
    let showsTrailingDot: Bool
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize
    let externalFocus: Bool

    private var effectiveFocused: Bool {
        isFocused || externalFocus
    }

    private var isDestructiveFocus: Bool {
        effectiveFocused && accent == .coral && prominence != .primary
    }

    var body: some View {
        let isCompact = size == .compact
        let minHeight = isCompact ? LunaTokens.Layout.compactControlH : LunaTokens.Layout.controlH
        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: .control, isFocused: effectiveFocused)

        HStack(spacing: isCompact ? 8 : 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(iconFont(isCompact: isCompact))
                    .foregroundStyle(iconForegroundColor)
            }
            if !title.isEmpty {
                Text(title)
                    .font(labelFont(isCompact: isCompact))
                    .foregroundStyle(labelForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(LunaTheme.Font.badge.monospacedDigit())
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeBackground))
            }
            if showsTrailingDot {
                Circle()
                    .fill(effectiveFocused && !isDestructiveFocus ? LunaTokens.Text.onAccent : LunaTheme.moonlight)
                    .frame(width: 8, height: 8)
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 14 : 16) : (isCompact ? 18 : 24))
        .frame(minHeight: minHeight)
        .background(backgroundView)
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: borderWidth)
                .transaction { $0.animation = nil }
        )
        .shadow(
            color: (effectiveFocused && !isDestructiveFocus)
                ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength)
                : .clear,
            radius: (effectiveFocused && !isDestructiveFocus) ? LunaFocusStyle.glowBlur : 0,
            x: 0,
            y: (effectiveFocused && !isDestructiveFocus) ? LunaFocusStyle.glowOffsetY : 0
        )
        .scaleEffect(scale)
        .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: effectiveFocused)
    }

    private func iconFont(isCompact: Bool) -> SwiftUI.Font {
        if prominence == .primary && !isCompact {
            return LunaTheme.Font.primaryPlayIcon
        }
        return isCompact ? LunaTheme.Font.compactPillIcon : LunaTheme.Font.pillIcon
    }

    private func labelFont(isCompact: Bool) -> SwiftUI.Font {
        if prominence == .primary {
            return isCompact ? LunaTheme.Font.pillLabel.weight(.semibold) : LunaTheme.Font.primaryPlayLabel
        }
        return isCompact ? LunaTheme.Font.compactPillLabel : LunaTheme.Font.pillLabel
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
        if isDestructiveFocus {
            return LunaTheme.coral
        }
        if effectiveFocused {
            return LunaTokens.Text.onAccent
        }
        if isSelected {
            return LunaTheme.linen
        }
        return LunaTheme.muted
    }

    private var restingSolidColor: Color {
        switch prominence {
        case .primary:
            return LunaTheme.surfaceElevated
        case .glassPill:
            return isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised
        case .subtleChip:
            return isSelected ? LunaTheme.surfaceSelected : Color.clear
        }
    }

    private var backgroundView: some View {
        ZStack {
            if effectiveFocused {
                if isDestructiveFocus {
                    Capsule()
                        .fill(LunaTheme.surfaceElevated)
                        .overlay(Capsule().fill(LunaTokens.Status.dangerBg))
                } else {
                    Capsule()
                        .fill(LunaTheme.playFocusGradient)
                }
            } else {
                Capsule()
                    .fill(restingSolidColor)
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
        isDestructiveFocus ? LunaFocusStyle.borderWidth : LunaTokens.Layout.hairlineWidth
    }

    private var badgeBackground: Color {
        if effectiveFocused && !isDestructiveFocus {
            return LunaTokens.Text.onAccent.opacity(0.16)
        }
        if effectiveFocused || isSelected {
            return LunaTheme.warmBorderBase.opacity(0.14)
        }
        return LunaTheme.warmBorderBase.opacity(0.10)
    }
}
