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
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    @State private var selectedCategory: SettingsCategory
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var cacheBytes: Int64 = 0
    @State private var cacheClearedNotice: Bool = false
    @State private var showReconnectDialog: Bool = false
    @State private var modalToken = UUID()
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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.sectionGap) {
                    selectedCategoryPanel(caps: caps)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.bottom, 84)
            }
            .scrollPosition($scrollPosition)
            .scrollClipDisabled()
            .contentMargins(.zero, for: .scrollContent)
            .id(selectedCategory)
            .lunaRootScrollTopBarTracking(tab: .settings)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focusSection()
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isActiveTab else { return }
                withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion)) {
                    scrollPosition.scrollTo(edge: .top)
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
        .task(id: isActiveTab) {
            guard isActiveTab else { return }
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
        .lunaEntryFocusTarget(
            nonce: contentEntryFocusNonce,
            isActive: isActiveTab,
            focus: $focusedCategory,
            target: { selectedCategory }
        )
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
        .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous))
        .focused(focusedCategory, equals: category)
        .task(id: isFocused) {
            guard isFocused, !isSelected else { return }
            try? await Task.sleep(nanoseconds: LunaTokens.Motion.focusSelectDebounceNanoseconds)
            guard !Task.isCancelled, isFocused, !isSelected else { return }
            action()
        }
    }
}

struct SettingsSectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
            LunaSectionHeader(title: title)

            LunaListGroup {
                content()
            }
        }
    }
}

struct SettingsToggleRowButton: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        LunaListRow(
            title: title,
            subtitle: subtitle,
            trailingText: isOn ? "På" : "Av",
            trailingTextProminent: isOn
        ) {
            isOn.toggle()
        }
    }
}
