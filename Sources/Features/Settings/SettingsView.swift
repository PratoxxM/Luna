import SwiftUI
import AetherBridge

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences

    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showUnpairConfirm: Bool = false
    @State private var showResetConfirm: Bool = false

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
                    }

                    if sessionStore.localProfileOverride != nil {
                        LunaPillButton(
                            "Bruk rom valgt i LunaCore Web",
                            systemImage: "arrow.uturn.backward",
                            prominence: .glassPill,
                            accent: .periwinkle
                        ) {
                            Task {
                                await sessionStore.restoreServerManagedRoomAndProfile()
                            }
                        }
                    }

                    Divider().overlay(LunaTheme.moonlight.opacity(0.12))

                    VStack(alignment: .leading, spacing: 18) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Fast lydsynk for denne Apple TV-en (HDMI / eARC)")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.moonlight)

                            Spacer()

                            Text(comfort.formattedAudioDelayLabel)
                                .font(.callout.monospacedDigit().weight(.bold))
                                .foregroundStyle(comfort.audioDelayMs == 0 ? LunaTheme.muted : LunaTheme.amber)
                        }

                        HStack(spacing: 12) {
                            LunaPillButton("-25 ms", prominence: .subtleChip) {
                                comfort.adjustAudioDelay(byMs: -25)
                            }
                            LunaPillButton("-10 ms", prominence: .subtleChip) {
                                comfort.adjustAudioDelay(byMs: -10)
                            }
                            LunaPillButton(
                                "0 ms",
                                isSelected: comfort.audioDelayMs == 0,
                                prominence: comfort.audioDelayMs == 0 ? .glassPill : .subtleChip
                            ) {
                                comfort.resetAudioDelay()
                            }
                            LunaPillButton("+10 ms", prominence: .subtleChip) {
                                comfort.adjustAudioDelay(byMs: 10)
                            }
                            LunaPillButton("+25 ms", prominence: .subtleChip) {
                                comfort.adjustAudioDelay(byMs: 25)
                            }
                        }

                        Text("Negativ verdi (f.eks. -25 til -75 ms) sender lyden tidligere ut på HDMI for å hente inn eARC- og Dolby MAT/LPCM-forsinkelse i TV og lydplanke.")
                            .font(.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }

                    Divider().overlay(LunaTheme.moonlight.opacity(0.12))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Lavoppløst oppskalering (SD / 720p / Anime)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)

                        HStack(spacing: 12) {
                            ForEach(LowResUpscaleMode.allCases) { mode in
                                LunaPillButton(
                                    mode.displayTitle,
                                    isSelected: comfort.lowResUpscaleMode == mode,
                                    prominence: comfort.lowResUpscaleMode == mode ? .glassPill : .subtleChip
                                ) {
                                    comfort.lowResUpscaleMode = mode
                                }
                            }
                        }

                        Text(comfort.lowResUpscaleMode.shortDescription)
                            .font(.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }

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

                    VStack(spacing: 10) {
                        SettingsToggleRowButton(
                            title: "Smarte språkregler (norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst)",
                            isOn: $comfort.smartNordicSubtitleRule
                        )

                        SettingsToggleRowButton(
                            title: "Spill neste episode automatisk når episoden er helt ferdig",
                            isOn: $comfort.autoPlayNextEpisode
                        )

                        SettingsToggleRowButton(
                            title: "Vis animerte kattefølgesvenner ved innlasting og pause",
                            isOn: $comfort.showCatCompanions
                        )

                        SettingsToggleRowButton(
                            title: "Vis sanntids teknisk status («Nerde-HUD») i spilleren",
                            isOn: $comfort.showNerdHUD
                        )
                    }
                }

                // 3. System & Tilkobling
                settingsPanel("System & Tilkobling") {
                    infoRow("LunaCore-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                    infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                    infoRow("Bilde- og kataloghurtigbuffer", value: formattedCacheSize)

                    SettingsToggleRowButton(
                        title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                        isOn: $sessionStore.allowSelfSignedLanTLS
                    )

                    HStack(spacing: 18) {
                        LunaPillButton("Tøm hurtigbuffer", systemImage: "trash", prominence: .subtleChip, accent: .coral) {
                            Task {
                                await DiskSWRStore.clearAllAsync()
                                await ArtworkPipeline.shared.clearAll()
                                AetherEngine.discardPrewarmedSources()
                                await refreshCacheMetricsAsync()
                                cacheClearedNotice = true
                            }
                        }

                        LunaPillButton("Par TV på nytt", systemImage: "qrcode", prominence: .subtleChip, accent: .coral) {
                            showUnpairConfirm = true
                        }

                        LunaPillButton("Nullstill tilkobling", systemImage: "xmark.circle", prominence: .subtleChip, accent: .coral) {
                            showResetConfirm = true
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
        .confirmationDialog(
            "Par denne Apple TV-en på nytt?",
            isPresented: $showUnpairConfirm,
            titleVisibility: .visible
        ) {
            Button("Par TV på nytt", role: .destructive) {
                sessionStore.unpairDevice()
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Dette fjerner aktiv paringstoken og tømmer lokal katalogbuffer. Du beholder serveradressen.")
        }
        .confirmationDialog(
            "Nullstille alle tilkoblingsinnstillinger?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Nullstill tilkobling", role: .destructive) {
                sessionStore.resetAllConnectionSettings()
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Fjerner både serveradresse og paringstoken fra Apple TV.")
        }
        .task {
            await refreshCacheMetricsAsync()
        }
    }

    private func hdmiSummary(_ caps: DisplayCapabilities) -> String {
        var modes: [String] = []
        if caps.supportsDolbyVision { modes.append("Dolby Vision") }
        if caps.supportsHDR10 { modes.append("HDR10") }
        if caps.supportsHLG { modes.append("HLG") }
        if modes.isEmpty { modes.append("SDR") }
        let appVer = AppSessionStore.currentAppVersionString()
        return "Luna \(appVer) · AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion) · \(modes.joined(separator: " / "))"
    }

    private var formattedCacheSize: String {
        if cacheBytes <= 0 {
            return "0 MB"
        }
        let mb = Double(cacheBytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }

    private func refreshCacheMetricsAsync() async {
        async let swr = DiskSWRStore.diskUsageBytesAsync()
        async let img = ArtworkPipeline.diskUsageBytesAsync()
        cacheBytes = await (swr + img)
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
                    .foregroundStyle(
                        isFocused
                            ? LunaTheme.canvas
                            : (isSelected ? LunaTheme.amber : LunaTheme.moonlight.opacity(0.62))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isFocused ? LunaTheme.canvas : .white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isFocused ? LunaTheme.canvas.opacity(0.76) : LunaTheme.moonlight.opacity(0.76))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LunaTheme.pearlFocusGradient)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LunaTheme.buttonRestGradient)
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LunaTheme.amber.opacity(0.16))
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Color.white.opacity(0.95)
                            : (isSelected ? LunaTheme.amber.opacity(0.78) : LunaTheme.moonlight.opacity(0.24)),
                        lineWidth: isFocused ? 2.2 : (isSelected ? 1.5 : 1.0)
                    )
            )
            .shadow(
                color: isFocused ? LunaTheme.pearlFocusBottom.opacity(0.35) : .black.opacity(0.25),
                radius: isFocused ? 16 : 6,
                x: 0,
                y: isFocused ? 6 : 3
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

private struct SettingsToggleRowButton: View {
    let title: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 18) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isFocused ? LunaTheme.canvas : .white)
                    .lineLimit(2)

                Spacer(minLength: 16)

                Text(isOn ? "På" : "Av")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        isFocused
                            ? (isOn ? LunaTheme.emerald : LunaTheme.canvas)
                            : (isOn ? LunaTheme.canvas : LunaTheme.moonlight)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        isFocused
                            ? (isOn ? LunaTheme.canvas : LunaTheme.canvas.opacity(0.14))
                            : (isOn ? LunaTheme.emerald : Color.white.opacity(0.16)),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LunaTheme.pearlFocusGradient)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LunaTheme.buttonRestGradient)
                        if isOn {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LunaTheme.emerald.opacity(0.08))
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Color.white.opacity(0.95)
                            : (isOn ? LunaTheme.emerald.opacity(0.45) : LunaTheme.moonlight.opacity(0.24)),
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? LunaTheme.pearlFocusBottom.opacity(0.35) : .black.opacity(0.25),
                radius: isFocused ? 16 : 6,
                x: 0,
                y: isFocused ? 6 : 3
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
