import SwiftUI

struct SettingsSectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(LunaTheme.linen)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1)
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

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LunaTheme.linen)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LunaTheme.muted)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 16).monospacedDigit())
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isSelected {
                        Text("Aktiv")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LunaTheme.amber)
                            .lineLimit(1)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? LunaTheme.amber : (isFocused ? LunaTheme.linen : LunaTheme.muted)
                        )
                }
                .fixedSize()
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
                    .transaction { $0.animation = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.28) : .clear,
                radius: isFocused ? 8 : 0,
                x: 0,
                y: isFocused ? 3 : 0
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(isOn ? "På" : "Av")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isOn ? LunaTheme.canvas : LunaTheme.muted)
                    .lineLimit(1)
                    .frame(minWidth: 22)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .fixedSize()
                    .background(
                        Capsule()
                            .fill(isOn ? LunaTheme.amber : LunaTheme.surface)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                !isOn ? LunaTheme.warmBorderSubtle : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surfaceRaised)
                    .transaction { $0.animation = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.focusGoldBorder : LunaTheme.warmBorderSubtle,
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.28) : .clear,
                radius: isFocused ? 8 : 0,
                x: 0,
                y: isFocused ? 3 : 0
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
