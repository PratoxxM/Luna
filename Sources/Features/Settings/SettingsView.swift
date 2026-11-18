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
            SettingsRoomDisplaySectionView(caps: caps)
        case .audioAndSync:
            SettingsAudioSyncSectionView()
        case .subtitles:
            SettingsSubtitlesSectionView()
        case .playback:
            SettingsPlaybackSectionView()
        case .system:
            SettingsServerDiagnosticsSectionView(
                cacheBytes: cacheBytes,
                cacheClearedNotice: $cacheClearedNotice,
                showUnpairConfirm: $showUnpairConfirm,
                showResetConfirm: $showResetConfirm,
                onRefreshCacheMetrics: refreshCacheMetricsAsync
            )
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
