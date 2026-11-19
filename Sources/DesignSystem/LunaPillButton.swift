import SwiftUI

/// Replaces `.buttonStyle(.plain)` across Luna so tvOS 18–26+ never injects a bright
/// white rectangular system platter behind custom pill buttons.
public struct LunaChromelessButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
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
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
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
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
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
            return LunaTheme.focusGoldBorder
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
            if isSelected {
                return accent == .emerald ? LunaTheme.emerald.opacity(0.38) : LunaTheme.warmBorderStrong
            }
            return prominence == .glassPill ? LunaTheme.warmBorder : LunaTheme.warmBorderSubtle
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
                size: size
            )
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }
}

private struct LunaPillLabel: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize

    var body: some View {
        let isCompact = size == .compact
        HStack(spacing: isCompact ? 7 : 9) {
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeBackground))
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 13 : 15) : (isCompact ? 16 : 19))
        .padding(.vertical, isCompact ? 8 : 9)
        .background(backgroundView)
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: borderWidth)
                .transaction { $0.animation = nil }
        )
        .shadow(
            color: isFocused ? glowAccentColor.opacity(roomAtmosphere.lampStrength) : .clear,
            radius: isFocused ? 22 : 0,
            x: 0,
            y: isFocused ? 8 : 0
        )
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(LunaFocusStyle.focusSpring, value: isFocused)
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
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var labelForegroundColor: Color {
        LunaPillButton.resolveLabelForeground(
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var badgeForegroundColor: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if isSelected {
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
            return isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceSubtle
        }
    }

    private var backgroundView: some View {
        ZStack {
            Capsule()
                .fill(restingSolidColor)
                .opacity(!isFocused && prominence != .primaryAmber ? 1 : 0)
            Capsule()
                .fill(LunaTheme.primaryAmberGradient)
                .opacity(!isFocused && prominence == .primaryAmber ? 1 : 0)
            Capsule()
                .fill(LunaTheme.focusGoldGradient)
                .opacity(isFocused ? 1 : 0)
        }
        .transaction { $0.animation = nil }
    }

    private var borderColor: Color {
        LunaPillButton.resolveBorderColor(
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var borderWidth: CGFloat {
        isFocused ? LunaFocusStyle.borderWidth : 1.0
    }

    private var badgeBackground: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas.opacity(0.16)
        }
        if isSelected {
            return LunaTheme.warmBorderBase.opacity(0.14)
        }
        return LunaTheme.warmBorderBase.opacity(0.08)
    }
}
