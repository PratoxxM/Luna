import SwiftUI
import AetherBridge

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Innstillinger")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Romprofil, OLED/HDR-komfort, smarte språkregler og systemstatus for Luna v2.1.")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }

                // 1. Paired Room, Hardware Profile & Local AV Overrides
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
                        LunaPillButton(
                            "Tilbakestill til rom fra MediaOS Web",
                            systemImage: "arrow.uturn.backward",
                            prominence: .subtleChip
                        ) {
                            sessionStore.setRoomAndProfile(
                                roomName: sessionStore.roomName,
                                hardwareProfile: sessionStore.hardwareProfile,
                                persistAsLocalOverride: false
                            )
                        }
                    }

                    Divider().overlay(LunaTheme.moonlight.opacity(0.12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dolby Vision Dual-Layer (P7 FEL)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)

                        HStack(spacing: 12) {
                            ForEach(DualLayerOverrideMode.allCases) { mode in
                                LunaPillButton(
                                    mode.displayTitle,
                                    isSelected: comfort.dualLayerOverride == mode,
                                    prominence: comfort.dualLayerOverride == mode ? .glassPill : .subtleChip
                                ) {
                                    comfort.dualLayerOverride = mode
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Høyttaleroppsett & Objektlyd")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)

                        HStack(spacing: 12) {
                            ForEach(SpeakerLayoutOverrideMode.allCases) { mode in
                                LunaPillButton(
                                    mode.displayTitle,
                                    isSelected: comfort.speakerLayoutOverride == mode,
                                    prominence: comfort.speakerLayoutOverride == mode ? .glassPill : .subtleChip
                                ) {
                                    comfort.speakerLayoutOverride = mode
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // 2. Comfort, HDR/OLED Subtitles & Smart Nordic Language Rules
                settingsPanel("Komfort, Undertekster & Språklogikk") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OLED / HDR undertekst-lysstyrke (gjelder både SRT/ASS og PGS)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)

                        HStack(spacing: 12) {
                            ForEach(HDRSubtitlePreset.allCases) { preset in
                                LunaPillButton(
                                    preset.displayTitle,
                                    isSelected: comfort.hdrSubtitlePreset == preset,
                                    prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip
                                ) {
                                    comfort.hdrSubtitlePreset = preset
                                }
                            }
                        }

                        Text(comfort.hdrSubtitlePreset.settingsDescription)
                            .font(.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }

                    HStack(alignment: .top, spacing: 44) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tekststørrelse")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.moonlight)

                            HStack(spacing: 12) {
                                ForEach(SubtitleFontSizePreset.allCases) { sz in
                                    LunaPillButton(
                                        sz.displayTitle,
                                        isSelected: comfort.subtitleFontSize == sz,
                                        prominence: comfort.subtitleFontSize == sz ? .glassPill : .subtleChip
                                    ) {
                                        comfort.subtitleFontSize = sz
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bakgrunnsboks bak tekst")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.moonlight)

                            HStack(spacing: 12) {
                                ForEach(SubtitleBoxOpacityPreset.allCases) { box in
                                    LunaPillButton(
                                        box.displayTitle,
                                        isSelected: comfort.subtitleBoxOpacity == box,
                                        prominence: comfort.subtitleBoxOpacity == box ? .glassPill : .subtleChip
                                    ) {
                                        comfort.subtitleBoxOpacity = box
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    Divider().overlay(LunaTheme.moonlight.opacity(0.12))

                    Toggle(
                        "Smarte språkregler (norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst)",
                        isOn: $comfort.smartNordicSubtitleRule
                    )
                    .padding(.vertical, 4)

                    Toggle(
                        "Spill neste episode automatisk (10 s nedtelling ved rulletekst)",
                        isOn: $comfort.autoPlayNextEpisode
                    )
                    .padding(.vertical, 4)

                    Toggle(
                        "Vis sanntids «Nerde-HUD» i spilleren (kodek, DV-rute, objektlyd, HTTP 206 & VFS)",
                        isOn: $comfort.showNerdHUD
                    )
                    .padding(.vertical, 4)
                }

                // 3. Local Disk SWR & Artwork Cache
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

                // 4. HDMI & AetherEngine Diagnostics
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

                // 5. Server & Pairing Management
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
