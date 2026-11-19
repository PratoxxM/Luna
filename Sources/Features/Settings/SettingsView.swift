import SwiftUI
import AetherBridge

enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case roomAndDisplay = "room"
    case subtitles = "subtitles"
    case playback = "playback"
    case system = "system"
    case advanced = "advanced"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roomAndDisplay: return "Rom og skjerm"
        case .subtitles: return "Undertekster"
        case .playback: return "Avspilling"
        case .system: return "System"
        case .advanced: return "Avansert"
        }
    }

    var systemImage: String {
        switch self {
        case .roomAndDisplay: return "tv"
        case .subtitles: return "captions.bubble"
        case .playback: return "play.circle"
        case .system: return "gearshape"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    nonisolated static let keepDisplayModeToggleTitle =
        "Behold filmens skjerm- og HDR-modus i menyen etter avspilling"
    nonisolated static let keepDisplayModeExplanationText =
        "Av (standard) gir jevne 60 Hz-menyer umiddelbart etter avspilling. På unngår HDMI-skifte ut av spilleren på denne TV-en, men låser menyene til 24 Hz etter 24p-film frem til du forlater appen."

    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    @State private var selectedCategory: SettingsCategory
    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showReconnectDialog: Bool = false
    @State private var modalToken = UUID()
    @FocusState private var focusedCategory: SettingsCategory?
    @Namespace private var settingsSidebarNamespace

    init(initialCategory: SettingsCategory = .roomAndDisplay) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Innstillinger")
                    .font(LunaTheme.Font.settingsHeading)
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsCategoryRowButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            focusedCategory: $focusedCategory
                        ) {
                            selectedCategory = category
                        }
                        .prefersDefaultFocus(selectedCategory == category, in: settingsSidebarNamespace)
                    }
                }
                .defaultFocus($focusedCategory, selectedCategory as SettingsCategory?, priority: .userInitiated)

                Spacer(minLength: 0)
            }
            .frame(width: 340, alignment: .topLeading)
            .focusScope(settingsSidebarNamespace)
            .focusSection()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    selectedCategoryPanel(caps: caps)
                }
                .frame(maxWidth: 1240, alignment: .topLeading)
                .padding(.top, 2)
                .padding(.horizontal, 4)
                .padding(.bottom, 56)
            }
            .scrollClipDisabled()
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
            "Koble til LunaCore på nytt?",
            isPresented: $showReconnectDialog,
            titleVisibility: .visible
        ) {
            Button("Par TV på nytt (behold serveradresse)", role: .destructive) {
                sessionStore.unpairDevice()
            }
            Button("Nullstill alt og bytt server", role: .destructive) {
                sessionStore.resetAllConnectionSettings()
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Velg om du vil pare denne Apple TV-en på nytt med samme server, eller nullstille både serveradresse og tilkobling.")
        }
        .task {
            await refreshCacheMetricsAsync()
        }
        .onChange(of: showReconnectDialog) { _, isShowingDialog in
            if isShowingDialog {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .onDisappear {
            if !showReconnectDialog {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    @ViewBuilder
    private func selectedCategoryPanel(caps: DisplayCapabilities) -> some View {
        switch selectedCategory {
        case .roomAndDisplay:
            SettingsRoomDisplaySectionView(caps: caps)
        case .subtitles:
            SettingsSubtitlesSectionView()
        case .playback:
            SettingsPlaybackSectionView()
        case .system:
            SettingsServerDiagnosticsSectionView(
                cacheBytes: cacheBytes,
                cacheClearedNotice: $cacheClearedNotice,
                showReconnectDialog: $showReconnectDialog,
                onRefreshCacheMetrics: refreshCacheMetricsAsync
            )
        case .advanced:
            SettingsAdvancedSectionView()
        }
    }

    private func refreshCacheMetricsAsync() async {
        async let swr = DiskSWRStore.diskUsageBytesAsync()
        async let img = ArtworkPipeline.diskUsageBytesAsync()
        cacheBytes = await (swr + img)
    }
}

private struct SettingsCategoryRowButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    var focusedCategory: FocusState<SettingsCategory?>.Binding
    let action: () -> Void

    @State private var focusTask: Task<Void, Never>?

    private var isFocused: Bool {
        focusedCategory.wrappedValue == category
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(LunaTheme.Font.settingsRowIcon)
                    .foregroundStyle(isSelected || isFocused ? LunaTheme.linen : LunaTheme.muted)
                    .frame(width: 26)

                Text(category.title)
                    .font(LunaTheme.Font.settingsRowTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(LunaTheme.Font.microChevron)
                        .foregroundStyle(LunaTheme.moonlight)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surface)
                    )
                    .transaction { $0.animation = nil }
            )
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.chip)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .focusEffectDisabled(true)
        .focused(focusedCategory, equals: category)
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
