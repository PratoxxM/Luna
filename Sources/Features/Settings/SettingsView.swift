import SwiftUI
import AetherBridge

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text("Innstillinger")
                    .font(.largeTitle.bold())

                // 1. Paired Room & Hardware Profile
                VStack(alignment: .leading, spacing: 18) {
                    Text("Rom & Utstyrsprofil")
                        .font(.title3.bold())

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
                                    .foregroundStyle(isSelected ? Color(red: 0.96, green: 0.77, blue: 0.42) : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.displayTitle)
                                        .font(.headline)
                                    Text(preset.technicalSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    if sessionStore.localProfileOverride != nil {
                        Button("Bruk standardprofil fra MediaOS Web") {
                            sessionStore.setRoomAndProfile(
                                roomName: sessionStore.roomName,
                                hardwareProfile: sessionStore.hardwareProfile,
                                persistAsLocalOverride: false
                            )
                        }
                    }
                }

                // 2. HDMI & AetherEngine Diagnostics
                VStack(alignment: .leading, spacing: 14) {
                    Text("Avspillingsmotor & HDMI-kapabiliteter")
                        .font(.title3.bold())

                    Group {
                        infoRow("AetherEngine-versjon", value: AetherBridgeInfo.pinnedAetherEngineVersion)
                        infoRow("HDMI HDR-støtte", value: caps.supportsHDR ? "Ja" : "Nei")
                        infoRow("HDMI Dolby Vision", value: caps.supportsDolbyVision ? "Ja" : "Nei")
                        infoRow("HDMI HDR10 / HLG", value: "\(caps.supportsHDR10 ? "HDR10" : "Ingen HDR10") · \(caps.supportsHLG ? "HLG" : "Ingen HLG")")
                    }

                    HStack(spacing: 14) {
                        ForEach(AetherEngine.OptionalComponent.allCases, id: \.rawValue) { comp in
                            HStack(spacing: 6) {
                                Image(systemName: comp.isBuiltIn ? "checkmark.seal.fill" : "xmark.circle")
                                    .foregroundStyle(comp.isBuiltIn ? .green : .secondary)
                                Text(comp.traitName)
                                    .font(.caption2.monospaced())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                }

                // 3. Server & Pairing Management
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tilkobling")
                        .font(.title3.bold())

                    infoRow("Enhetsnavn", value: sessionStore.deviceName)
                    infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                    infoRow("MediaOS-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                    infoRow("Enhets-ID (sideload-stabil)", value: sessionStore.deviceID)

                    Toggle("Tillat selvsignert TLS-sertifikat på lokalnett", isOn: $sessionStore.allowSelfSignedLanTLS)

                    HStack(spacing: 24) {
                        Button("Par på nytt") {
                            sessionStore.unpairDevice()
                        }

                        Button(role: .destructive) {
                            sessionStore.resetAllConnectionSettings()
                        } label: {
                            Text("Nullstill tilkobling")
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(64)
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
        }
        .padding(.vertical, 4)
    }
}
