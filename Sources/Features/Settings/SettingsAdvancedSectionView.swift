import SwiftUI

struct SettingsAdvancedSectionView: View {
    private enum AudioSyncFocus: Hashable {
        case minus
        case reset
        case plus
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(ComfortPreferences.self) private var comfort
    @FocusState private var syncFocus: AudioSyncFocus?

    var body: some View {
        @Bindable var sessionStore = sessionStore
        @Bindable var comfort = comfort
        let isNonZeroDelay = comfort.audioDelayMs != 0
        let syncTitle = PlaybackSyncTimingPolicy.headerTitle(
            baseTitle: "Fast lydsynk (HDMI / eARC)",
            delayMs: comfort.audioDelayMs
        )

        SettingsSectionPanel(title: "Avansert") {
            LunaControlRow(
                title: "Dolby Vision P7 FEL",
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
                title: syncTitle,
                subtitle: "Negativ verdi sender lyden tidligere · gjelder alle avspillinger på denne Apple TV-en",
                axis: .vertical
            ) {
                HStack(spacing: 10) {
                    LunaPillButton("−25 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: -PlaybackSyncTimingPolicy.audioStepMs)
                    }
                    .focused($syncFocus, equals: .minus)

                    if isNonZeroDelay {
                        LunaPillButton("Nullstill", isSelected: true, prominence: .glassPill, size: .compact) {
                            syncFocus = .plus
                            comfort.resetAudioDelay()
                            Task { @MainActor in
                                await Task.yield()
                                if syncFocus != .plus && syncFocus != .minus {
                                    syncFocus = .plus
                                }
                                for delayNs: UInt64 in [16_000_000, 48_000_000] {
                                    try? await Task.sleep(nanoseconds: delayNs)
                                    guard !Task.isCancelled else { return }
                                    if syncFocus != .plus && syncFocus != .minus {
                                        syncFocus = .plus
                                    } else {
                                        return
                                    }
                                }
                            }
                        }
                        .focused($syncFocus, equals: .reset)
                    }

                    LunaPillButton("+25 ms", prominence: .glassPill, size: .compact) {
                        comfort.adjustAudioDelay(byMs: PlaybackSyncTimingPolicy.audioStepMs)
                    }
                    .focused($syncFocus, equals: .plus)
                }
                .focusSection()
            }

            LunaListDivider()

            SettingsToggleRowButton(
                title: "Teknisk oversikt",
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
