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
        dotColor: Color? = nil
    ) {
        self.label = label
        self.systemImage = nil
        self.dotColor = dotColor
        self.iconColor = LunaTheme.linen
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

/// Shared `6 pt` Lampelys playback progress capsule (`2% < pct < 95%`) across poster, backdrop & episode cards.
public struct LunaCardProgressBar: View {
    let percent: Double
    let trackWidth: CGFloat

    public init(percent: Double?, trackWidth: CGFloat) {
        self.percent = min(100.0, max(0.0, percent ?? 0))
        self.trackWidth = max(0, trackWidth)
    }

    public var isVisible: Bool {
        percent > 2 && percent < 95
    }

    public var body: some View {
        if isVisible {
            ZStack(alignment: .leading) {
                Capsule().fill(LunaTokens.Edge.progressTrack)
                Capsule()
                    .fill(LunaTheme.amber)
                    .frame(width: trackWidth * CGFloat(percent / 100.0))
            }
            .frame(width: trackWidth, height: 6)
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
/// (bronze fill on focus, borderless at rest when unselected).
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

    public nonisolated static func resolveBorderColor(
        isFocused: Bool,
        isSelected: Bool
    ) -> Color {
        if isFocused {
            return .clear
        }
        return isSelected ? LunaTheme.warmBorderStrong : .clear
    }

    public var body: some View {
        Button(action: action) {
            LunaIconButtonLabel(
                systemImage: systemImage,
                isSelected: isSelected,
                externalFocus: isDirectFocused
            )
        }
        .lunaChromelessButton(Circle())
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
                        LunaIconButton.resolveBorderColor(
                            isFocused: effectiveFocused,
                            isSelected: isSelected
                        ),
                        lineWidth: LunaTokens.Layout.hairlineWidth
                    )
                    .transaction { $0.animation = nil }
            )
            .lunaFocusSurface(.control, isFocused: effectiveFocused, cornerRadius: LunaTokens.Radius.pill)
    }
}
