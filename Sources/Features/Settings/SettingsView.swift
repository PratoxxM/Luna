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
            VStack(alignment: .leading, spacing: 28) {
                Text("Innstillinger")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                // 1. Rom & Lyd/Bilde
                settingsPanel("Rom & Lyd/Bilde") {
                    VStack(spacing: 10) {
                        ForEach(HardwareProfilePreset.allCases) { preset in
                            let isSelected = sessionStore.effectiveHardwareProfile == preset.rawValue
                            SettingsRoomRowButton(
                                title: preset.displayTitle,
                                subtitle: preset.technicalSummary,
                                isSelected: isSelected
                            ) {
                                sessionStore.setRoomAndProfile(
                                    roomName: preset.defaultRoomName,
                                    hardwareProfile: preset.rawValue,
                                    persistAsLocalOverride: true
                                )
                            }
                        }
                    }

                    if sessionStore.localProfileOverride != nil {
                        LunaPillButton(
                            "Bruk rom valgt i MediaOS Web",
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

                    HStack(alignment: .top, spacing: 44) {
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
                    }
                    .padding(.top, 4)

                    Divider().overlay(LunaTheme.moonlight.opacity(0.12))

                    infoRow(
                        "HDMI & Avspillingsmotor",
                        value: hdmiSummary(caps)
                    )
                }

                // 2. Undertekster & Avspilling
                settingsPanel("Undertekster & Avspilling") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kveldslys i HDR / Dolby Vision (gjelder tekst & PGS)")
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
                            Text("Bakgrunn bak tekst")
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
                    .padding(.vertical, 2)

                    Toggle(
                        "Spill neste episode automatisk (10 s nedtelling ved rulletekst)",
                        isOn: $comfort.autoPlayNextEpisode
                    )
                    .padding(.vertical, 2)

                    Toggle(
                        "Vis sanntids teknisk status («Nerde-HUD») i spilleren",
                        isOn: $comfort.showNerdHUD
                    )
                    .padding(.vertical, 2)
                }

                // 3. System & Tilkobling
                settingsPanel("System & Tilkobling") {
                    infoRow("MediaOS-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                    infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                    infoRow("Bilde- og kataloghurtigbuffer", value: formattedCacheSize)

                    Toggle("Tillat selvsignert TLS-sertifikat på lokalnett", isOn: $sessionStore.allowSelfSignedLanTLS)
                        .padding(.vertical, 4)

                    HStack(spacing: 18) {
                        LunaPillButton("Tøm hurtigbuffer", systemImage: "trash", prominence: .subtleChip) {
                            Task {
                                DiskSWRStore.clearAll()
                                await ArtworkPipeline.shared.clearAll()
                                AetherEngine.discardPrewarmedSources()
                                refreshCacheMetrics()
                                cacheClearedNotice = true
                            }
                        }

                        LunaPillButton("Par TV på nytt", systemImage: "qrcode", prominence: .subtleChip) {
                            sessionStore.unpairDevice()
                        }

                        LunaPillButton("Nullstill tilkobling", systemImage: "xmark.circle", prominence: .subtleChip) {
                            sessionStore.resetAllConnectionSettings()
                        }

                        if cacheClearedNotice {
                            Text("Hurtigbuffer tømt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LunaTheme.emerald)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, 56)
        }
        .task {
            refreshCacheMetrics()
        }
    }

    private func hdmiSummary(_ caps: DisplayCapabilities) -> String {
        var modes: [String] = []
        if caps.supportsDolbyVision { modes.append("Dolby Vision") }
        if caps.supportsHDR10 { modes.append("HDR10") }
        if caps.supportsHLG { modes.append("HLG") }
        if modes.isEmpty { modes.append("SDR") }
        return "Luna 2.2 · AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion) · \(modes.joined(separator: " / "))"
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
                .fill(LunaTheme.surface.opacity(0.86))
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
                .font(.callout.monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsRoomRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LunaTheme.amber : LunaTheme.muted)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.amber.opacity(0.22)
                            : (isSelected ? LunaTheme.amber.opacity(0.10) : Color.white.opacity(0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.amber : (isSelected ? LunaTheme.amber.opacity(0.42) : Color.white.opacity(0.08)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
    }
}
