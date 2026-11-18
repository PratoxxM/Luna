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
}

struct SettingsView: View {
    static let keepDisplayModeToggleTitle =
        "Behold filmens skjerm- og HDR-modus i menyen etter avspilling"
    static let keepDisplayModeExplanationText =
        "Av (standard) gir jevne 60 Hz-menyer umiddelbart etter avspilling. På unngår HDMI-skifte ut av spilleren på denne TV-en, men låser menyene til 24 Hz etter 24p-film frem til du forlater appen."

    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var comfort: ComfortPreferences
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    @State private var selectedCategory: SettingsCategory
    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showUnpairConfirm: Bool = false
    @State private var showResetConfirm: Bool = false
    @State private var modalToken = UUID()

    init(initialCategory: SettingsCategory = .roomAndDisplay) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Innstillinger")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.leading, 4)

                VStack(spacing: 6) {
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
            .frame(width: 270, alignment: .topLeading)
            .focusSection()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    selectedCategoryPanel(caps: caps)
                }
                .frame(maxWidth: 980, alignment: .topLeading)
                .padding(.top, 2)
                .padding(.horizontal, 4)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Romprofil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LunaTheme.muted)

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

                    if sessionStore.localProfileOverride != nil {
                        LunaPillButton(
                            "Bruk rom valgt i LunaCore Web",
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

                settingsDivider

                settingControlRow("Dolby Vision Dual-Layer (P7 FEL)") {
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

                settingsDivider

                settingControlRow(
                    "Lavoppløst oppskalering (SD / 720p / Anime)",
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

                settingsDivider

                SettingsToggleRowButton(
                    title: Self.keepDisplayModeToggleTitle,
                    subtitle: Self.keepDisplayModeExplanationText,
                    isOn: $comfort.keepDisplayModeInMenuAfterPlayback
                )

                settingsDivider

                infoRow("HDMI & Skjermstøtte", value: hdmiSummary(caps))
            }

        case .audioAndSync:
            settingsPanel("Lyd & Synk") {
                settingControlRow("Høyttaleroppsett & Objektlyd") {
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

                settingsDivider

                settingControlRow(
                    "Fast lydsynk for denne Apple TV-en (HDMI / eARC)",
                    subtitle: "Negativ verdi (f.eks. -25 til -75 ms) sender lyden tidligere ut på HDMI for å hente inn eARC- og Dolby MAT/LPCM-forsinkelse i TV og lydplanke."
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(comfort.formattedAudioDelayLabel)
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(comfort.audioDelayMs == 0 ? LunaTheme.muted : LunaTheme.amber)

                        HStack(spacing: 8) {
                            LunaPillButton("-25 ms", prominence: .subtleChip, size: .compact) {
                                comfort.adjustAudioDelay(byMs: -25)
                            }
                            LunaPillButton("-10 ms", prominence: .subtleChip, size: .compact) {
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
            }

        case .subtitles:
            settingsPanel("Undertekster") {
                settingControlRow(
                    "Kveldslys i HDR / Dolby Vision",
                    subtitle: "\(comfort.hdrSubtitlePreset.settingsDescription) · Gjelder tekst & PGS"
                ) {
                    HStack(spacing: 8) {
                        ForEach(HDRSubtitlePreset.allCases) { preset in
                            LunaPillButton(
                                preset.displayTitle,
                                isSelected: comfort.hdrSubtitlePreset == preset,
                                prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                comfort.hdrSubtitlePreset = preset
                            }
                        }
                    }
                }

                settingsDivider

                settingControlRow("Tekststørrelse") {
                    HStack(spacing: 8) {
                        ForEach(SubtitleFontSizePreset.allCases) { sz in
                            LunaPillButton(
                                sz.displayTitle,
                                isSelected: comfort.subtitleFontSize == sz,
                                prominence: comfort.subtitleFontSize == sz ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                comfort.subtitleFontSize = sz
                            }
                        }
                    }
                }

                settingsDivider

                settingControlRow("Bakgrunn bak tekst") {
                    HStack(spacing: 8) {
                        ForEach(SubtitleBoxOpacityPreset.allCases) { box in
                            LunaPillButton(
                                box.displayTitle,
                                isSelected: comfort.subtitleBoxOpacity == box,
                                prominence: comfort.subtitleBoxOpacity == box ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                comfort.subtitleBoxOpacity = box
                            }
                        }
                    }
                }

                settingsDivider

                SettingsToggleRowButton(
                    title: "Smarte språkregler",
                    subtitle: "Norsk tale uten tekst · utenlandsk tale med norsk/engelsk tekst",
                    isOn: $comfort.smartNordicSubtitleRule
                )
            }

        case .playback:
            settingsPanel("Avspilling") {
                SettingsToggleRowButton(
                    title: "Spill neste episode automatisk",
                    subtitle: "Starter neste episode automatisk når episoden er helt ferdig",
                    isOn: $comfort.autoPlayNextEpisode
                )

                settingsDivider

                SettingsToggleRowButton(
                    title: "Vis teknisk status («Nerde-HUD») i spilleren",
                    subtitle: "Sanntids bilde-, lyd- og buffertelemetri under avspilling",
                    isOn: $comfort.showNerdHUD
                )

                settingsDivider

                infoRow(
                    "Avspillingsmotor",
                    value: "AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
                )
            }

        case .system:
            settingsPanel("System") {
                infoRow("App-versjon", value: "Luna \(AppSessionStore.currentAppVersionDisplayString())")
                settingsDivider
                infoRow("LunaCore-server", value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet")
                settingsDivider
                infoRow("Aktivt rom", value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))")
                settingsDivider
                infoRow("Bilde- og kataloghurtigbuffer", value: formattedCacheSize)
                settingsDivider

                SettingsToggleRowButton(
                    title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                    isOn: $sessionStore.allowSelfSignedLanTLS
                )

                settingsDivider

                HStack(spacing: 12) {
                    LunaPillButton("Tøm hurtigbuffer", systemImage: "trash", prominence: .subtleChip, accent: .coral, size: .compact) {
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

                    LunaPillButton("Par TV på nytt", systemImage: "qrcode", prominence: .subtleChip, accent: .coral, size: .compact) {
                        showUnpairConfirm = true
                    }

                    LunaPillButton("Nullstill tilkobling", systemImage: "xmark.circle", prominence: .subtleChip, accent: .coral, size: .compact) {
                        showResetConfirm = true
                    }

                    Spacer(minLength: 0)

                    if cacheClearedNotice {
                        Text("Hurtigbuffer tømt")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LunaTheme.amber)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.top, 2)
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

    private var settingsDivider: some View {
        Rectangle()
            .fill(LunaTheme.warmBorderSubtle)
            .frame(height: 1)
    }

    private func settingsPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(LunaTheme.linen)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1)
            )
        }
    }

    private func settingControlRow<Controls: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LunaTheme.linen)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LunaTheme.muted)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 16).monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
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
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected || isFocused ? LunaTheme.amber : LunaTheme.muted)
                    .frame(width: 22)

                Text(category.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LunaTheme.amber)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surface)
                    )
                    .transaction { $0.animation = nil }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isSelected {
                        Text("Aktiv")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LunaTheme.amber)
                            .lineLimit(1)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? LunaTheme.amber : (isFocused ? LunaTheme.linen : LunaTheme.muted)
                        )
                }
                .fixedSize()
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
                    .transaction { $0.animation = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.28) : .clear,
                radius: isFocused ? 8 : 0,
                x: 0,
                y: isFocused ? 3 : 0
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

private struct SettingsToggleRowButton: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LunaTheme.linen)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(isOn ? "På" : "Av")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isOn ? LunaTheme.canvas : LunaTheme.muted)
                    .lineLimit(1)
                    .frame(minWidth: 22)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .fixedSize()
                    .background(
                        Capsule()
                            .fill(isOn ? LunaTheme.amber : LunaTheme.surface)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                !isOn ? LunaTheme.warmBorderSubtle : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surfaceRaised)
                    .transaction { $0.animation = nil }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.focusGoldBorder : LunaTheme.warmBorderSubtle,
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.28) : .clear,
                radius: isFocused ? 8 : 0,
                x: 0,
                y: isFocused ? 3 : 0
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
