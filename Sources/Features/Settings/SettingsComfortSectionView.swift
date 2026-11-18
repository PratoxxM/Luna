import SwiftUI
import AetherBridge

struct SettingsRoomDisplaySectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    let caps: DisplayCapabilities

    var body: some View {
        SettingsSectionPanel(title: "Rom & Skjerm") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Romprofil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LunaTheme.muted)

                let matchingProfileCount = Dictionary(
                    grouping: sessionStore.availableRooms,
                    by: \.hardwareProfile
                ).mapValues(\.count)

                ForEach(sessionStore.availableRooms) { room in
                    let isSelected = sessionStore.effectiveHardwareProfile == room.hardwareProfile &&
                        (sessionStore.roomName == room.roomName || (matchingProfileCount[room.hardwareProfile] ?? 0) == 1)
                    let fallbackPreset = HardwareProfilePreset(rawValue: room.hardwareProfile)
                    SettingsRoomRowButton(
                        title: room.label ?? fallbackPreset?.displayTitle ?? room.roomName,
                        subtitle: room.description ?? fallbackPreset?.technicalSummary ?? room.hardwareProfile,
                        isSelected: isSelected
                    ) {
                        sessionStore.setRoomAndProfile(
                            roomName: room.roomName,
                            hardwareProfile: room.hardwareProfile,
                            persistAsLocalOverride: true
                        )
                    }
                }

                if sessionStore.localProfileOverride != nil {
                    LunaPillButton(
                        "Bruk rom valgt i LunaCore Web",
                        systemImage: "arrow.uturn.backward",
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        Task {
                            await sessionStore.restoreServerManagedRoomAndProfile()
                        }
                    }
                    .padding(.top, 4)
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(title: "Dolby Vision Dual-Layer (P7 FEL)") {
                HStack(spacing: 8) {
                    ForEach(DualLayerOverrideMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.dualLayerOverride == mode,
                            prominence: comfort.dualLayerOverride == mode ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.dualLayerOverride = mode
                        }
                    }
                }
            }

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

            SettingsInfoRow(title: "HDMI & Skjermstøtte", value: hdmiSummary)
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

struct SettingsAudioSyncSectionView: View {
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Lyd & Synk") {
            SettingsControlRow(title: "Høyttaleroppsett & Objektlyd") {
                HStack(spacing: 8) {
                    ForEach(SpeakerLayoutOverrideMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.speakerLayoutOverride == mode,
                            prominence: comfort.speakerLayoutOverride == mode ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.speakerLayoutOverride = mode
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(
                title: "Fast lydsynk for denne Apple TV-en (HDMI / eARC)",
                subtitle: "Negativ verdi (f.eks. -25 til -75 ms) sender lyden tidligere ut på HDMI for å hente inn eARC- og Dolby MAT/LPCM-forsinkelse i TV og lydplanke."
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    Text(comfort.formattedAudioDelayLabel)
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundStyle(comfort.audioDelayMs == 0 ? LunaTheme.muted : LunaTheme.amber)

                    HStack(spacing: 8) {
                        LunaPillButton("-25 ms", prominence: .subtleChip, size: .compact) {
                            comfort.adjustAudioDelay(byMs: -25)
                        }
                        LunaPillButton("-10 ms", prominence: .subtleChip, size: .compact) {
                            comfort.adjustAudioDelay(byMs: -10)
                        }
                        LunaPillButton(
                            "0 ms",
                            isSelected: comfort.audioDelayMs == 0,
                            prominence: comfort.audioDelayMs == 0 ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.resetAudioDelay()
                        }
                        LunaPillButton("+10 ms", prominence: .subtleChip, size: .compact) {
                            comfort.adjustAudioDelay(byMs: 10)
                        }
                        LunaPillButton("+25 ms", prominence: .subtleChip, size: .compact) {
                            comfort.adjustAudioDelay(byMs: 25)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsSubtitlesSectionView: View {
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Undertekster") {
            SettingsControlRow(
                title: "Kveldslys i HDR / Dolby Vision",
                subtitle: "\(comfort.hdrSubtitlePreset.settingsDescription) · Gjelder tekst & PGS"
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

            SettingsToggleRowButton(
                title: "Vis teknisk status («Nerde-HUD») i spilleren",
                subtitle: "Sanntids bilde-, lyd- og buffertelemetri under avspilling",
                isOn: $comfort.showNerdHUD
            )

            SettingsSectionDivider()

            SettingsInfoRow(
                title: "Avspillingsmotor",
                value: "AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
            )
        }
    }
}
