import SwiftUI

/// Replaces `.buttonStyle(.plain)` across Luna so tvOS 18–26+ never injects a bright
/// white rectangular system platter behind custom pill buttons.
public struct LunaChromelessButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((configuration.isPressed && !reduceMotion) ? 0.96 : 1.0)
            .focusEffectDisabled(true)
            .animation(
                reduceMotion ? nil : .easeOut(duration: LunaTokens.Motion.pressDuration),
                value: configuration.isPressed
            )
    }
}

public enum LunaButtonProminence: Sendable {
    case primary
    case glassPill
    case subtleChip
}

public enum LunaButtonAccent: Sendable {
    case amber
    case emerald
    case warn
    case coral
}

public extension View {
    func lunaChromelessButton<S: Shape>(_ shape: S) -> some View {
        self
            .buttonStyle(LunaChromelessButtonStyle())
            .contentShape(shape)
            .focusEffectDisabled(true)
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
    let minWidth: CGFloat?
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
        minWidth: CGFloat? = nil,
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
        self.minWidth = minWidth
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
                return accent == .emerald ? LunaTheme.emerald : LunaTheme.amber
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
            if isSelected {
                return accent == .emerald ? LunaTheme.emerald : LunaTheme.amber
            }
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
            guard isSelected else { return .clear }
            return accent == .emerald ? LunaTokens.Status.okBorder : LunaTokens.Accent.border
        case .subtleChip:
            return .clear
        }
    }

    public nonisolated static func resolveTrailingDotColor(
        isFocused: Bool,
        prominence: LunaButtonProminence = .glassPill,
        accent: LunaButtonAccent = .amber
    ) -> Color {
        if isFocused {
            if accent == .coral && prominence != .primary {
                return LunaTheme.coral
            }
            return LunaTokens.Text.onAccent
        }
        switch accent {
        case .coral:
            return LunaTheme.coral
        case .warn:
            return LunaTheme.warn
        case .amber, .emerald:
            return LunaTheme.moonlight
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
                minWidth: minWidth,
                externalFocus: isDirectFocused
            )
        }
        .lunaChromelessButton(Capsule())
        .focused($isDirectFocused)
    }
}

private struct LunaPillLabel: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let systemImage: String?
    let badgeText: String?
    let showsTrailingDot: Bool
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize
    let minWidth: CGFloat?
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
                    .fill(
                        LunaPillButton.resolveTrailingDotColor(
                            isFocused: effectiveFocused,
                            prominence: prominence,
                            accent: accent
                        )
                    )
                    .frame(width: 8, height: 8)
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 14 : 16) : (isCompact ? 18 : 24))
        .frame(minWidth: minWidth, minHeight: minHeight)
        .background(backgroundView)
        .overlay(
            Group {
                if !isDestructiveFocus {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: LunaTokens.Layout.hairlineWidth)
                        .transaction { $0.animation = nil }
                }
            }
        )
        .lunaFocusSurface(
            .control,
            isFocused: effectiveFocused,
            cornerRadius: LunaTokens.Radius.pill,
            accentColor: isDestructiveFocus ? LunaTheme.coral : LunaTheme.amber
        )
    }

    private func iconFont(isCompact: Bool) -> SwiftUI.Font {
        if prominence == .primary && !isCompact {
            return LunaTheme.Font.primaryPlayIcon
        }
        return LunaTheme.Font.pillIcon
    }

    private func labelFont(isCompact: Bool) -> SwiftUI.Font {
        if prominence == .primary {
            let base = isCompact ? LunaTheme.Font.pillLabel.weight(.semibold) : LunaTheme.Font.primaryPlayLabel
            return base.monospacedDigit()
        }
        let base = isCompact ? LunaTheme.Font.compactPillLabel : LunaTheme.Font.pillLabel
        return base.monospacedDigit()
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

    private var badgeBackground: Color {
        if effectiveFocused && !isDestructiveFocus {
            return LunaTokens.Text.onAccent.opacity(0.16)
        }
        if effectiveFocused || isSelected {
            return LunaTheme.warmBorder
        }
        return LunaTheme.warmBorderSubtle
    }
}
