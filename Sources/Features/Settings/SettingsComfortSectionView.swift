import SwiftUI
import AetherBridge

struct SettingsRoomDisplaySectionView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(ComfortPreferences.self) private var comfort

    let caps: DisplayCapabilities

    var body: some View {
        SettingsSectionPanel(title: "Rom og skjerm") {
            let matchingProfileCount = Dictionary(
                grouping: sessionStore.availableRooms,
                by: \.hardwareProfile
            ).mapValues(\.count)

            ForEach(sessionStore.availableRooms) { room in
                let isSelected = sessionStore.effectiveHardwareProfile == room.hardwareProfile &&
                    (sessionStore.roomName == room.roomName || (matchingProfileCount[room.hardwareProfile] ?? 0) == 1)
                let fallbackPreset = HardwareProfilePreset(rawValue: room.hardwareProfile)
                let eqLabel = LunaCopy.roomEquipmentLabel(
                    hardwareProfile: room.hardwareProfile,
                    roomName: room.roomName,
                    serverLabel: room.equipmentLabel
                )
                LunaListRow(
                    title: room.label ?? fallbackPreset?.displayTitle ?? room.roomName,
                    subtitle: room.description ?? eqLabel,
                    isSelected: isSelected
                ) {
                    sessionStore.setRoomAndProfile(
                        roomName: room.roomName,
                        hardwareProfile: room.hardwareProfile
                    )
                }

                LunaListDivider()
            }

            LunaControlRow(
                title: "MetalFX 4K-oppskalering",
                subtitle: comfort.lowResUpscaleMode.shortDescription,
                axis: .vertical
            ) {
                HStack(spacing: 10) {
                    ForEach(LowResUpscaleMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.lowResUpscaleMode == mode,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.lowResUpscaleMode = mode
                        }
                    }
                }
            }

            LunaListDivider()

            LunaControlRow(
                title: "Skjermmodus i meny etter film",
                subtitle: comfort.menuDisplayMode.shortDescription,
                axis: .vertical
            ) {
                HStack(spacing: 10) {
                    ForEach(MenuDisplayMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.menuDisplayMode == mode,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.menuDisplayMode = mode
                        }
                    }
                }
            }

            LunaListDivider()

            LunaInfoRow(title: "Skjermen støtter", value: activeVideoModeSummary)
        }
    }

    private var activeVideoModeSummary: String {
        var modes: [String] = []
        if caps.supportsDolbyVision { modes.append("Dolby Vision") }
        if caps.supportsHDR10 { modes.append("HDR10") }
        if caps.supportsHLG { modes.append("HLG") }
        if modes.isEmpty { modes.append("SDR") }
        if !caps.supportsDolbyVision && caps.supportsHDR10 {
            return "\(modes.joined(separator: " / ")) · HDR10+ aktiveres dynamisk i spiller"
        }
        return modes.joined(separator: " / ")
    }
}

struct SettingsSubtitlesSectionView: View {
    @Environment(ComfortPreferences.self) private var comfort

    var body: some View {
        @Bindable var comfort = comfort

        SettingsSectionPanel(title: "Undertekster") {
            LunaControlRow(
                title: "Kveldslys",
                subtitle: "\(comfort.hdrSubtitlePreset.settingsDescription) · Gjelder HDR og Dolby Vision",
                axis: .vertical
            ) {
                HStack(spacing: 10) {
                    ForEach(HDRSubtitlePreset.allCases) { preset in
                        LunaPillButton(
                            preset.displayTitle,
                            isSelected: comfort.hdrSubtitlePreset == preset,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.hdrSubtitlePreset = preset
                        }
                    }
                }
            }

            LunaListDivider()

            LunaControlRow(title: "Tekststørrelse", axis: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(SubtitleFontSizePreset.allCases) { sz in
                        LunaPillButton(
                            sz.displayTitle,
                            isSelected: comfort.subtitleFontSize == sz,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.subtitleFontSize = sz
                        }
                    }
                }
            }

            LunaListDivider()

            LunaControlRow(title: "Bakgrunn bak tekst", axis: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(SubtitleBoxOpacityPreset.allCases) { box in
                        LunaPillButton(
                            box.displayTitle,
                            isSelected: comfort.subtitleBoxOpacity == box,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.subtitleBoxOpacity = box
                        }
                    }
                }
            }

            LunaListDivider()

            SettingsToggleRowButton(
                title: "Smarte språkregler",
                subtitle: "Norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst",
                isOn: $comfort.smartNordicSubtitleRule
            )
        }
    }
}

struct SettingsPlaybackSectionView: View {
    @Environment(ComfortPreferences.self) private var comfort

    var body: some View {
        @Bindable var comfort = comfort

        SettingsSectionPanel(title: "Avspilling") {
            SettingsToggleRowButton(
                title: "Spill neste episode automatisk",
                isOn: $comfort.autoPlayNextEpisode
            )

            LunaListDivider()

            LunaInfoRow(
                title: "Siri Remote-spoling",
                value: "Kun ved pause · adaptiv · hold ring"
            )
        }
    }
}
