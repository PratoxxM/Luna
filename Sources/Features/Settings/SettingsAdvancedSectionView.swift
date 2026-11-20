import SwiftUI

struct SettingsAdvancedSectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Avansert") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Velg annet rom på denne TV-en")
                    .font(LunaTheme.Font.settingsSubLabel)
                    .foregroundStyle(LunaTheme.muted)

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
                    SettingsRoomRowButton(
                        title: room.label ?? fallbackPreset?.displayTitle ?? room.roomName,
                        subtitle: room.description ?? eqLabel,
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
                        "Bruk rom valgt i LunaCore",
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

            SettingsControlRow(title: "Høyttaleroppsett og objektlyd") {
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
                subtitle: "Negativ verdi (f.eks. −25 til −75 ms) sender lyden tidligere ut på HDMI for å hente inn eARC- og Dolby MAT/LPCM-forsinkelse i TV og lydplanke."
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    Text(comfort.formattedAudioDelayLabel.replacingOccurrences(of: "-", with: "−"))
                        .font(LunaTheme.Font.settingsAudioDelay)
                        .foregroundStyle(comfort.audioDelayMs == 0 ? LunaTheme.muted : LunaTheme.linen)

                    HStack(spacing: 8) {
                        LunaPillButton("−25 ms", prominence: .subtleChip, size: .compact) {
                            comfort.adjustAudioDelay(byMs: -25)
                        }
                        LunaPillButton("−10 ms", prominence: .subtleChip, size: .compact) {
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

            SettingsSectionDivider()

            SettingsControlRow(
                title: "Lavoppløst oppskalering (Auto MetalFX)",
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
                title: "Vis teknisk oversikt i spilleren",
                subtitle: "Sanntids bilde-, lyd- og bufferoversikt under avspilling",
                isOn: $comfort.showNerdHUD
            )

            SettingsSectionDivider()

            SettingsToggleRowButton(
                title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                isOn: $sessionStore.allowSelfSignedLanTLS
            )
        }
    }
}
