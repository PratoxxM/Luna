import SwiftUI
import AetherBridge

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case roomAndDisplay = "room"
    case audioAndSync = "audio"
    case subtitles = "subtitles"
    case playback = "playback"
    case system = "system"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roomAndDisplay: return "Rom & Skjerm"
        case .audioAndSync: return "Lyd & Synk"
        case .subtitles: return "Undertekster"
        case .playback: return "Avspilling"
        case .system: return "System"
        }
    }

    var systemImage: String {
        switch self {
        case .roomAndDisplay: return "tv"
        case .audioAndSync: return "speaker.wave.2"
        case .subtitles: return "captions.bubble"
        case .playback: return "play.circle"
        case .system: return "gearshape"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .roomAndDisplay: return "Profil, Dolby Vision og oppskalering"
        case .audioAndSync: return "Høyttalere og HDMI/eARC-forsinkelse"
        case .subtitles: return "HDR-lys, størrelse og nordiske regler"
        case .playback: return "Neste episode og spiller-HUD"
        case .system: return "Server, hurtigbuffer og paring"
        }
    }
}

struct SettingsView: View {
    static let keepDisplayModeToggleTitle =
        "Behold filmens skjerm- og HDR-modus i menyen etter avspilling"
    static let keepDisplayModeExplanationText =
        "Av (standard) gir jevne 60 Hz-menyer umiddelbart etter avspilling. På unngår HDMI-skifte ut av spilleren på denne TV-en, men låser menyene til 24 Hz etter 24p-film frem til du forlater appen."

    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    @State private var selectedCategory: SettingsCategory = .roomAndDisplay
    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showUnpairConfirm: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var modalToken = UUID()

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Innstillinger")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)

                VStack(spacing: 10) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsCategoryRowButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 390, alignment: .topLeading)
            .focusSection()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    selectedCategoryPanel(caps: caps)
                }
                .padding(.bottom, 56)
            }
            .contentMargins(.zero, for: .scrollContent)
            .id(selectedCategory)
            .lunaRootScrollTopBarTracking(tab: .settings)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focusSection()
        }
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .ignoresSafeArea(edges: .horizontal)
        .safeAreaPadding(.top, LunaTopBarView.contentTopPadding)
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
        .onChange(of: showUnpairConfirm || showResetConfirm) { _, isShowingDialog in
            if isShowingDialog {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .onDisappear {
            if !showUnpairConfirm && !showResetConfirm {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    @ViewBuilder
    private func selectedCategoryPanel(caps: DisplayCapabilities) -> some View {
        switch selectedCategory {
        case .roomAndDisplay:
            settingsPanel("Rom & Skjerm") {
                VStack(spacing: 8) {
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
                        prominence: .glassPill
                    ) {
                        Task {
                            await sessionStore.restoreServerManagedRoomAndProfile()
                        }
                    }
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

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

                Divider().overlay(LunaTheme.warmBorderSubtle)

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

                Divider().overlay(LunaTheme.warmBorderSubtle)

                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggleRowButton(
                        title: Self.keepDisplayModeToggleTitle,
                        isOn: $comfort.keepDisplayModeInMenuAfterPlayback
                    )

                    Text(Self.keepDisplayModeExplanationText)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                infoRow("HDMI & Skjermstøtte", value: hdmiSummary(caps))
            }

        case .audioAndSync:
            settingsPanel("Lyd & Synk") {
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

                Divider().overlay(LunaTheme.warmBorderSubtle)

                VStack(alignment: .leading, spacing: 12) {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .subtitles:
            settingsPanel("Undertekster") {
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

                    Text(comfort.hdrSubtitlePreset.settingsDescription)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

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

                Divider().overlay(LunaTheme.warmBorderSubtle)

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

                Divider().overlay(LunaTheme.warmBorderSubtle)

                SettingsToggleRowButton(
                    title: "Smarte språkregler (norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst)",
                    isOn: $comfort.smartNordicSubtitleRule
                )
            }

        case .playback:
            settingsPanel("Avspilling") {
                VStack(spacing: 10) {
                    SettingsToggleRowButton(
                        title: "Spill neste episode automatisk når episoden er helt ferdig",
                        isOn: $comfort.autoPlayNextEpisode
                    )

                    SettingsToggleRowButton(
                        title: "Vis sanntids teknisk status («Nerde-HUD») i spilleren",
                        isOn: $comfort.showNerdHUD
                    )
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                infoRow(
                    "Avspillingsmotor",
                    value: "AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
                )
            }

        case .system:
            settingsPanel("System") {
                infoRow("App-versjon", value: "Luna \(AppSessionStore.currentAppVersionDisplayString())")
                infoRow("LunaCore-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                infoRow("Bilde- og kataloghurtigbuffer", value: formattedCacheSize)

                Divider().overlay(LunaTheme.warmBorderSubtle)

                SettingsToggleRowButton(
                    title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                    isOn: $sessionStore.allowSelfSignedLanTLS
                )

                HStack(spacing: 16) {
                    LunaPillButton("Tøm hurtigbuffer", systemImage: "trash", prominence: .subtleChip, accent: .coral) {
                        Task {
                            CatalogBrowseMemoryCache.shared.clear()
                            LibraryBrowseMemoryCache.shared.clear()
                            await DiskSWRStore.clearAllAsync()
                            await ArtworkPipeline.shared.clearAll()
                            AetherEngine.discardPrewarmedSources()
                            sessionStore.notifyContentMutated()
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
                            .foregroundStyle(LunaTheme.amber)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func hdmiSummary(_ caps: DisplayCapabilities) -> String {
        var modes: [String] = []
        if caps.supportsDolbyVision { modes.append("Dolby Vision") }
        if caps.supportsHDR10 { modes.append("HDR10") }
        if caps.supportsHLG { modes.append("HLG") }
        if modes.isEmpty { modes.append("SDR") }
        let appVer = AppSessionStore.currentAppVersionDisplayString()
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
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(LunaTheme.linen)

            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LunaTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1)
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
        .padding(.vertical, 4)
    }
}

private struct SettingsCategoryRowButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected || isFocused ? LunaTheme.amber : LunaTheme.muted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.headline)
                        .foregroundStyle(LunaTheme.linen)
                    Text(category.shortSubtitle)
                        .font(.caption2)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LunaTheme.amber)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            focusTask?.cancel()
            focusTask = nil
            guard focused, !isSelected else { return }
            focusTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, isFocused else { return }
                action()
            }
        }
        .onDisappear {
            focusTask?.cancel()
            focusTask = nil
        }
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
                        isSelected ? LunaTheme.amber : (isFocused ? LunaTheme.linen : LunaTheme.muted)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(LunaTheme.linen)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.32) : .clear,
                radius: isFocused ? 10 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? 1.012 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(2)

                Spacer(minLength: 16)

                Text(isOn ? "På" : "Av")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isOn ? LunaTheme.canvas : LunaTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(isOn ? LunaTheme.amber : LunaTheme.surface, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                !isOn ? LunaTheme.warmBorderSubtle : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surfaceRaised)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.focusGoldBorder : LunaTheme.warmBorderSubtle,
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.32) : .clear,
                radius: isFocused ? 10 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? 1.012 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
