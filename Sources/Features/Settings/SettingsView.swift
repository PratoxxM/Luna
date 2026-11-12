import SwiftUI
import AetherBridge

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Innstillinger")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Romprofil, bilde-/lydkapabiliteter og lokal hurtigbuffer for Luna v2.0.")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }

                // 1. Paired Room & Hardware Profile
                settingsPanel("Rom & Utstyrsprofil") {
                    ForEach(HardwareProfilePreset.allCases) { preset in
                        let isSelected = sessionStore.effectiveHardwareProfile == preset.rawValue
                        Button {
                            sessionStore.setRoomAndProfile(
                                roomName: preset.defaultRoomName,
                                hardwareProfile: preset.rawValue,
                                persistAsLocalOverride: true
                            )
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? LunaTheme.amber : LunaTheme.muted)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.displayTitle)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(preset.technicalSummary)
                                        .font(.caption)
                                        .foregroundStyle(LunaTheme.muted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    if sessionStore.localProfileOverride != nil {
                        LunaPillButton("Tilbakestill til rom fra MediaOS Web", systemImage: "arrow.uturn.backward", prominence: .subtleChip) {
                            sessionStore.setRoomAndProfile(
                                roomName: sessionStore.roomName,
                                hardwareProfile: sessionStore.hardwareProfile,
                                persistAsLocalOverride: false
                            )
                        }
                    }
                }

                // 2. Local Disk SWR & Artwork Cache
                settingsPanel("Hurtigbuffer på Apple TV") {
                    infoRow("Katalog- og bildehurtigbuffer", value: formattedCacheSize)

                    HStack(spacing: 18) {
                        LunaPillButton("Tøm hurtigbuffer", systemImage: "trash") {
                            Task {
                                DiskSWRStore.clearAll()
                                await ArtworkPipeline.shared.clearAll()
                                AetherEngine.discardPrewarmedSources()
                                refreshCacheMetrics()
                                cacheClearedNotice = true
                            }
                        }

                        if cacheClearedNotice {
                            Text("Hurtigbuffer tømt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LunaTheme.emerald)
                        }
                    }
                }

                // 3. HDMI & AetherEngine Diagnostics
                settingsPanel("Avspillingsmotor & HDMI-kapabiliteter") {
                    infoRow("AetherEngine-versjon", value: AetherBridgeInfo.pinnedAetherEngineVersion)
                    infoRow("HDMI HDR-støtte", value: caps.supportsHDR ? "Ja" : "Nei")
                    infoRow("HDMI Dolby Vision", value: caps.supportsDolbyVision ? "Ja" : "Nei")
                    infoRow("HDMI HDR10 / HLG", value: "\(caps.supportsHDR10 ? "HDR10" : "Ingen HDR10") · \(caps.supportsHLG ? "HLG" : "Ingen HLG")")

                    HStack(spacing: 14) {
                        ForEach(AetherEngine.OptionalComponent.allCases, id: \.rawValue) { comp in
                            HStack(spacing: 6) {
                                Image(systemName: comp.isBuiltIn ? "checkmark.seal.fill" : "xmark.circle")
                                    .foregroundStyle(comp.isBuiltIn ? LunaTheme.emerald : LunaTheme.muted)
                                Text(comp.traitName)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(LunaTheme.moonlight)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07), in: Capsule())
                        }
                    }
                    .padding(.top, 6)
                }

                // 4. Server & Pairing Management
                settingsPanel("Tilkobling") {
                    infoRow("Enhetsnavn", value: sessionStore.deviceName)
                    infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                    infoRow("MediaOS-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                    infoRow("Enhets-ID (sideload-stabil)", value: sessionStore.deviceID)

                    Toggle("Tillat selvsignert TLS-sertifikat på lokalnett", isOn: $sessionStore.allowSelfSignedLanTLS)
                        .padding(.vertical, 4)

                    HStack(spacing: 22) {
                        LunaPillButton("Par på nytt", systemImage: "qrcode") {
                            sessionStore.unpairDevice()
                        }

                        Button(role: .destructive) {
                            sessionStore.resetAllConnectionSettings()
                        } label: {
                            Text("Nullstill tilkobling")
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 36)
        }
        .task {
            refreshCacheMetrics()
        }
    }

    private var formattedCacheSize: String {
        if cacheBytes <= 0 {
            return "0 MB"
        }
        let mb = Double(cacheBytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }

    private func refreshCacheMetrics() {
        cacheBytes = DiskSWRStore.diskUsageBytes() + ArtworkPipeline.diskUsageBytes()
    }

    private func settingsPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LunaTheme.surface.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LunaTheme.moonlight.opacity(0.10), lineWidth: 1)
        )
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(LunaTheme.muted)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(LunaTheme.moonlight)
        }
        .padding(.vertical, 3)
    }
}
