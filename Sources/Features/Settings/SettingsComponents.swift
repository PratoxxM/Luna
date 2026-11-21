import SwiftUI

struct SettingsSectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
            LunaSectionHeader(title: title)

            LunaListGroup {
                content()
            }
        }
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        LunaListDivider()
    }
}

struct SettingsControlRow<Controls: View>: View {
    let title: String
    var subtitle: String? = nil
    var axis: Axis = .horizontal
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        LunaControlRow(title: title, subtitle: subtitle, axis: axis) {
            controls()
        }
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        LunaInfoRow(title: title, value: value)
    }
}

struct SettingsRoomRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        LunaListRow(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
            action: action
        )
    }
}

struct SettingsToggleRowButton: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        LunaListRow(
            title: title,
            subtitle: subtitle,
            trailingText: isOn ? "På" : "Av",
            trailingTextProminent: isOn
        ) {
            isOn.toggle()
        }
    }
}
