import SwiftUI

struct SettingsSectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.linen)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
        }
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(LunaTheme.warmBorderSubtle)
            .frame(height: 1)
    }
}

struct SettingsControlRow<Controls: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let controls: () -> Controls

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LunaTheme.Font.settingsRowTitle)
                .foregroundStyle(LunaTheme.linen)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(LunaTheme.Font.settingsRowSubtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                labelBlock
                    .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)

                controls()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                labelBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                controls()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(LunaTheme.Font.settingsMetaTitle)
                .foregroundStyle(LunaTheme.muted)
            Spacer(minLength: 16)
            Text(value)
                .font(LunaTheme.Font.settingsMetaValue)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsRoomRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LunaTheme.Font.settingsRowTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(LunaTheme.Font.settingsRowSubtitle)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isSelected {
                        Text("Aktiv")
                            .font(LunaTheme.Font.settingsStatusTag)
                            .foregroundStyle(LunaTheme.moonlight)
                            .lineLimit(1)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(LunaTheme.Font.settingsRowIcon)
                        .foregroundStyle(
                            isSelected ? LunaTheme.emerald : (isFocused ? LunaTheme.linen : LunaTheme.muted)
                        )
                }
                .fixedSize()
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
                    .transaction { $0.animation = nil }
            }
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.chip)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

struct SettingsToggleRowButton: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(LunaTheme.Font.settingsRowTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(LunaTheme.Font.settingsRowSubtitle)
                            .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(isOn ? "På" : "Av")
                    .font(LunaTheme.Font.settingsToggleState)
                    .foregroundStyle(isOn ? LunaTheme.linen : LunaTheme.muted)
                    .lineLimit(1)
                    .frame(minWidth: 28)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .fixedSize()
                    .background(
                        Capsule()
                            .fill(isOn ? LunaTokens.Status.okBg : LunaTheme.surface)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isOn ? LunaTokens.Status.okBorder : LunaTheme.warmBorderSubtle,
                                lineWidth: 1
                            )
                    )
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surfaceRaised)
                    .transaction { $0.animation = nil }
            }
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.chip)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
