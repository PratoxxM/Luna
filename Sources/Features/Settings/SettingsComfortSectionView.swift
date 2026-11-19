import SwiftUI
import AetherBridge

struct SettingsRoomDisplaySectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    let caps: DisplayCapabilities

    var body: some View {
        SettingsSectionPanel(title: "Rom og skjerm") {
            SettingsInfoRow(
                title: "Aktivt rom",
                value: "\(sessionStore.roomName) · \(sessionStore.effectiveEquipmentLabel)"
            )

            SettingsSectionDivider()

            SettingsControlRow(
                title: "Lavoppløst oppskalering (SD / 720p / Anime)",
                subtitle: comfort.lowResUpscaleMode.shortDescription
            ) {
                HStack(spacing: 8) {
                    ForEach(LowResUpscaleMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.lowResUpscaleMode == mode,
                            prominence: comfort.lowResUpscaleMode == mode ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.lowResUpscaleMode = mode
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsToggleRowButton(
                title: SettingsView.keepDisplayModeToggleTitle,
                subtitle: SettingsView.keepDisplayModeExplanationText,
                isOn: $comfort.keepDisplayModeInMenuAfterPlayback
            )

            SettingsSectionDivider()

            SettingsInfoRow(title: "HDMI og skjermstøtte", value: hdmiSummary)
        }
    }

    private var hdmiSummary: String {
        var modes: [String] = []
        if caps.supportsDolbyVision { modes.append("Dolby Vision") }
        if caps.supportsHDR10 { modes.append("HDR10") }
        if caps.supportsHLG { modes.append("HLG") }
        if modes.isEmpty { modes.append("SDR") }
        let appVer = AppSessionStore.currentAppVersionDisplayString()
        return "Luna \(appVer) · AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion) · \(modes.joined(separator: " / "))"
    }
}

struct SettingsSubtitlesSectionView: View {
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Undertekster") {
            SettingsControlRow(
                title: "Kveldslys",
                subtitle: "\(comfort.hdrSubtitlePreset.settingsDescription) · Gjelder HDR og Dolby Vision"
            ) {
                HStack(spacing: 8) {
                    ForEach(HDRSubtitlePreset.allCases) { preset in
                        LunaPillButton(
                            preset.displayTitle,
                            isSelected: comfort.hdrSubtitlePreset == preset,
                            prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.hdrSubtitlePreset = preset
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(title: "Tekststørrelse") {
                HStack(spacing: 8) {
                    ForEach(SubtitleFontSizePreset.allCases) { sz in
                        LunaPillButton(
                            sz.displayTitle,
                            isSelected: comfort.subtitleFontSize == sz,
                            prominence: comfort.subtitleFontSize == sz ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.subtitleFontSize = sz
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(title: "Bakgrunn bak tekst") {
                HStack(spacing: 8) {
                    ForEach(SubtitleBoxOpacityPreset.allCases) { box in
                        LunaPillButton(
                            box.displayTitle,
                            isSelected: comfort.subtitleBoxOpacity == box,
                            prominence: comfort.subtitleBoxOpacity == box ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.subtitleBoxOpacity = box
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsToggleRowButton(
                title: "Smarte språkregler",
                subtitle: "Norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst",
                isOn: $comfort.smartNordicSubtitleRule
            )
        }
    }
}

struct SettingsPlaybackSectionView: View {
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Avspilling") {
            SettingsToggleRowButton(
                title: "Spill neste episode automatisk",
                subtitle: "Starter neste episode automatisk når episoden er helt ferdig",
                isOn: $comfort.autoPlayNextEpisode
            )

            SettingsSectionDivider()

            SettingsInfoRow(
                title: "Avspillingsmotor",
                value: "AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
            )
        }
    }
}
