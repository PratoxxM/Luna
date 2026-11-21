import SwiftUI

struct SettingsAdvancedSectionView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(ComfortPreferences.self) private var comfort

    var body: some View {
        @Bindable var sessionStore = sessionStore
        @Bindable var comfort = comfort

        SettingsSectionPanel(title: "Avansert") {
            LunaControlRow(
                title: "Dolby Vision Dual-Layer (P7 FEL)",
                axis: .vertical
            ) {
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

            LunaListDivider()

            LunaControlRow(
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

            LunaListDivider()

            LunaControlRow(
                title: "Fast lydsynk for denne Apple TV-en (HDMI / eARC)",
                subtitle: "Negativ verdi sender lyden tidligere",
                axis: .vertical
            ) {
                let currentDelayLabel = ComfortPreferences.displayAudioDelayMs(comfort.audioDelayMs)
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

            LunaListDivider()

            SettingsToggleRowButton(
                title: "Vis teknisk oversikt i spilleren",
                isOn: $comfort.showNerdHUD
            )

            LunaListDivider()

            SettingsToggleRowButton(
                title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                isOn: $sessionStore.allowSelfSignedLanTLS
            )
        }
    }
}
