import SwiftUI

/// Calm scrim capsule or completion mark placed in the top-left corner of card artwork.
/// At most one `LunaArtBadge` may appear on any card, always without borders.
public struct LunaArtBadge: View {
    let label: String?
    let systemImage: String?
    let dotColor: Color?
    let iconColor: Color

    public init(
        label: String,
        systemImage: String? = nil,
        dotColor: Color? = nil,
        iconColor: Color = LunaTheme.linen
    ) {
        self.label = label
        self.systemImage = systemImage
        self.dotColor = dotColor
        self.iconColor = iconColor
    }

    private init(systemImage: String, iconColor: Color) {
        self.label = nil
        self.systemImage = systemImage
        self.dotColor = nil
        self.iconColor = iconColor
    }

    public static func watchedCheckmark() -> LunaArtBadge {
        LunaArtBadge(systemImage: "checkmark", iconColor: LunaTheme.emerald)
    }

    public var body: some View {
        if label == nil, let systemImage {
            Image(systemName: systemImage)
                .font(LunaTheme.Font.badge)
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(LunaTokens.Surface.badgeScrim, in: Circle())
        } else if let label {
            HStack(spacing: 7) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(LunaTheme.Font.badge)
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(LunaTheme.Font.badge)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(LunaTokens.Surface.badgeScrim, in: Capsule())
        }
    }
}

/// Subtle `8 pt` storage tier indicator placed ahead of card/detail metadata text (never over artwork).
public struct LunaTierDotView: View {
    let availability: TvAvailabilityInfo

    public init(availability: TvAvailabilityInfo) {
        self.availability = availability
    }

    public var body: some View {
        if availability.isLocalNvme {
            Circle()
                .fill(LunaTheme.tierNvme)
                .frame(width: 8, height: 8)
                .accessibilityLabel(availability.resolvedBenefitLabel)
        } else if availability.isLocalArchive {
            Circle()
                .strokeBorder(LunaTheme.tierArchive, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .accessibilityLabel(availability.resolvedBenefitLabel)
        }
    }
}

/// Canonical `56×56 pt` circular icon button using the unified `.control` focus style
/// (bronze fill on focus, crisp `0.5 pt` warm hairline on `@2x` at rest).
public struct LunaIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @FocusState private var isDirectFocused: Bool

    public init(
        systemImage: String,
        isSelected: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LunaIconButtonLabel(
                systemImage: systemImage,
                isSelected: isSelected,
                externalFocus: isDirectFocused
            )
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Circle())
        .focusEffectDisabled(true)
        .focused($isDirectFocused)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LunaIconButtonLabel: View {
    @Environment(\.isFocused) private var envFocused

    let systemImage: String
    let isSelected: Bool
    let externalFocus: Bool

    private var effectiveFocused: Bool {
        envFocused || externalFocus
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(LunaTheme.Font.tabIcon)
            .foregroundStyle(
                effectiveFocused
                    ? LunaTokens.Text.onAccent
                    : (isSelected ? LunaTheme.linen : LunaTheme.moonlight)
            )
            .transaction { $0.animation = nil }
            .frame(width: LunaTokens.Layout.iconButton, height: LunaTokens.Layout.iconButton)
            .background(
                ZStack {
                    if effectiveFocused {
                        Circle().fill(LunaTheme.playFocusGradient)
                    } else {
                        Circle().fill(isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    }
                }
                .transaction { $0.animation = nil }
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        effectiveFocused
                            ? Color.clear
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorder),
                        lineWidth: LunaTokens.Layout.hairlineWidth
                    )
                    .transaction { $0.animation = nil }
            )
            .lunaFocusSurface(.control, isFocused: effectiveFocused, cornerRadius: LunaTokens.Radius.pill)
    }
}
