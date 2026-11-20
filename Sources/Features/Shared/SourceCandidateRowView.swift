import SwiftUI

/// Shared release/source row shared cleanly between pre-play `SourcePickerSheetView`
/// and in-player `Kilde` popover (`PlayerQuickPanelView`).
struct SourceCandidateRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let candidate: TvCandidateInfo
    let roomName: String
    let isRecommended: Bool
    let isSelected: Bool
    let activeStatusLabel: String
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        let title = candidate.quickRowTitle(roomName: roomName, isRecommended: isRecommended)
        let subtitle = candidate.quickRowMetadata(activeLabel: isSelected ? activeStatusLabel : nil)

        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitle)
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if candidate.isNorwegian == true {
                    Text("🇳🇴 Norsk")
                        .font(LunaTheme.Font.badge)
                        .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(LunaTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                        .fixedSize()
                }

                if isSelected {
                    Text("✓")
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.amber)
                        .fixedSize()
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceSelected
                            : (isSelected ? LunaTheme.surfaceRaised : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
                            : (isSelected ? LunaTokens.Accent.border : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                    )
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength * 0.7) : .clear,
                radius: isFocused ? 20 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
    }
}
