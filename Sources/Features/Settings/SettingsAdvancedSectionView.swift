import SwiftUI

struct SettingsAdvancedSectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    var body: some View {
        SettingsSectionPanel(title: "Avansert") {
            SettingsControlRow(title: "Dolby Vision Dual-Layer (P7 FEL)") {
                HStack(spacing: 10) {
                    ForEach(DualLayerOverrideMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.dualLayerOverride == mode,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.dualLayerOverride = mode
                        }
                    }
                }
            }

            SettingsSectionDivider()

            SettingsControlRow(
                title: "Høyttaleroppsett og objektlyd",
                subtitle: "Auto 7.1.4 anbefales · Stereo for TV-høyttalere"
            ) {
                HStack(spacing: 10) {
                    ForEach(SpeakerLayoutOverrideMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.speakerLayoutOverride == mode,
                            prominence: .glassPill,
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
                subtitle: "Negativ verdi sender lyden tidligere"
            ) {
                let currentDelayLabel = comfort.formattedAudioDelayLabel.replacingOccurrences(of: "-", with: "−")
                HStack(spacing: 10) {
                    LunaPillButton("−25 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: -25)
                    }
                    LunaPillButton("−10 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: -10)
                    }
                    LunaPillButton(
                        currentDelayLabel,
                        isSelected: true,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        comfort.resetAudioDelay()
                    }
                    LunaPillButton("+10 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: 10)
                    }
                    LunaPillButton("+25 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: 25)
                    }
                }
            }

            SettingsSectionDivider()

            SettingsToggleRowButton(
                title: "Vis teknisk oversikt i spilleren",
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
