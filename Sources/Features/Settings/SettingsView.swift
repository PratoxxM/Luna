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
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    @State private var selectedCategory: SettingsCategory
    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showReconnectDialog: Bool = false
    @State private var modalToken = UUID()
    @State private var entryFocusRetryTask: Task<Void, Never>?
    @FocusState private var focusedCategory: SettingsCategory?
    @Namespace private var settingsSidebarNamespace

    init(initialCategory: SettingsCategory = .roomAndDisplay, isActiveTab: Bool = true) {
        self.isActiveTab = isActiveTab
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        let caps = AetherEngine.displayCapabilities

        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 10) {
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

                Spacer(minLength: 0)
            }
            .frame(width: 320, alignment: .topLeading)
            .padding(.top, 12)
            .focusScope(settingsSidebarNamespace)
            .focusSection()

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LunaTokens.Layout.sectionGap) {
                        Color.clear
                            .frame(height: 0)
                            .id("luna-scroll-top")

                        selectedCategoryPanel(caps: caps)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
                    .padding(.bottom, 84)
                }
                .scrollClipDisabled()
                .contentMargins(.zero, for: .scrollContent)
                .id(selectedCategory)
                .lunaRootScrollTopBarTracking(tab: .settings)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
                .onChange(of: scrollToTopNonce) { _, _ in
                    guard isActiveTab else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, LunaTokens.Layout.contentTop)
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .ignoresSafeArea()
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
            await sessionStore.refreshProfileFromServer()
        }
        .onChange(of: showReconnectDialog) { _, isShowingDialog in
            if isShowingDialog {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .onChange(of: contentEntryFocusNonce) { _, _ in
            guard isActiveTab else { return }
            focusSidebarCategoryEntry()
        }
        .onDisappear {
            entryFocusRetryTask?.cancel()
            entryFocusRetryTask = nil
            if !showReconnectDialog {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    private func focusSidebarCategoryEntry() {
        entryFocusRetryTask?.cancel()
        let targetCategory = selectedCategory
        focusedCategory = targetCategory
        entryFocusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, isActiveTab else { return }
                if focusedCategory == nil {
                    focusedCategory = targetCategory
                } else {
                    return
                }
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
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .font(LunaTheme.Font.pillIcon)
                    .foregroundStyle(isFocused ? LunaTheme.linen : (isSelected ? LunaTheme.amber : LunaTheme.muted))
                    .frame(width: 28, alignment: .center)

                Text(category.title)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(isFocused || isSelected ? LunaTheme.linen : LunaTheme.muted)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, LunaTokens.Layout.listRowPadX)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceSelected : Color.clear)
                    .transaction { $0.animation = nil }
            )
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.card)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous))
        .focusEffectDisabled(true)
        .focused(focusedCategory, equals: category)
        .onChange(of: isFocused) { _, focused in
            focusTask?.cancel()
            focusTask = nil
            guard focused, !isSelected else { return }
            focusTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: LunaTokens.Motion.focusSelectDebounceNanoseconds)
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
