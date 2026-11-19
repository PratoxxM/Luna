import SwiftUI
import AetherBridge

enum PlayerTopDrawerTab: String, CaseIterable, Identifiable, Sendable {
    case info
    case audioAndSubtitles
    case source
    case chapters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "Info"
        case .audioAndSubtitles: return "Lyd og tekst"
        case .source: return "Kilde"
        case .chapters: return "Kapitler"
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .audioAndSubtitles: return "captions.bubble"
        case .source: return "sparkles.tv"
        case .chapters: return "list.bullet.film"
        }
    }
}

/// 4-tab dark HDR-safe cinema glass top drawer opened by swiping down during playback.
/// Built exclusively with focus-safe custom buttons (`.focusEffectDisabled()`, never SwiftUI `Menu`).
struct PlayerTopDrawerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var comfort: ComfortPreferences
    @Binding var selectedTab: PlayerTopDrawerTab
    var roomEquipmentOverride: String? = nil
    let onClose: () -> Void

    @FocusState private var focusedTab: PlayerTopDrawerTab?
    @State private var tabDebounceTask: Task<Void, Never>?
    @State var chapterSnapshotTime: Double = 0
    @Namespace private var drawerTabFocusNamespace

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ForEach(PlayerTopDrawerTab.allCases) { tab in
                        LunaPillButton(
                            tab.title,
                            systemImage: tab.icon,
                            isSelected: selectedTab == tab,
                            prominence: selectedTab == tab ? .glassPill : .subtleChip
                        ) {
                            tabDebounceTask?.cancel()
                            tabDebounceTask = nil
                            withAnimation(.easeOut(duration: 0.12)) {
                                selectedTab = tab
                            }
                        }
                        .focused($focusedTab, equals: tab)
                        .prefersDefaultFocus(selectedTab == tab, in: drawerTabFocusNamespace)
                    }

                    Spacer()
                }
                .defaultFocus($focusedTab, selectedTab as PlayerTopDrawerTab?, priority: .userInitiated)
                .focusScope(drawerTabFocusNamespace)
                .focusSection()

                Divider()
                    .overlay(LunaTheme.warmBorderSubtle)

                ZStack(alignment: .topLeading) {
                    switch selectedTab {
                    case .info:
                        infoTabContent
                            .transition(.opacity)
                    case .audioAndSubtitles:
                        audioAndSubtitlesTabContent
                            .transition(.opacity)
                    case .source:
                        sourceTabContent
                            .transition(.opacity)
                    case .chapters:
                        chaptersTabContent
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.easeOut(duration: 0.12), value: selectedTab)
                .focusSection()
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 38)
            .padding(.bottom, 30)
            .background {
                Rectangle()
                    .fill(LunaTheme.cinemaGlass)
                    .ignoresSafeArea(edges: [.top, .horizontal])
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LunaTokens.Edge.top2)
                    .frame(height: 1)
                    .ignoresSafeArea(edges: .horizontal)
            }

            Spacer()
        }
        .onChange(of: focusedTab) { _, newTab in
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            guard let newTab, newTab != selectedTab else { return }
            tabDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled, focusedTab == newTab else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    selectedTab = newTab
                }
            }
        }
        .onAppear {
            focusedTab = selectedTab
        }
        .onDisappear {
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
        }
        .task(id: viewModel.activeSession?.sessionId) {
            chapterSnapshotTime = max(0, viewModel.engine.currentTime)
            if viewModel.alternativesSessionId != viewModel.activeSession?.sessionId || viewModel.alternatives.isEmpty {
                await viewModel.loadAlternatives()
            }
        }
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(LunaTheme.Font.settingsSubLabel)
            .foregroundStyle(LunaTheme.muted)
    }
}

// MARK: - Focus-Safe Row & Chapter Cards (`.focusEffectDisabled()`)

struct DrawerTrackRowButton: View {
    let title: String
    let subtitle: String
    let badges: [String]
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(LunaTheme.Font.tabIcon)
                    .foregroundStyle(
                        isSelected ? LunaTheme.emerald : (isFocused ? LunaTheme.linen : LunaTheme.muted)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(LunaTheme.Font.settingsRowTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(LunaTheme.Font.settingsRowSubtitle)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LunaTheme.warmBorderBase.opacity(isFocused ? 0.14 : 0.08),
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
            }
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.chip)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

struct ChapterPillCardButton: View {
    let chapter: PlaybackChapter
    var isActive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(TimelineScrubberLeafView.formatSeconds(chapter.startSeconds))
                        .font(LunaTheme.Font.badge.monospacedDigit())
                        .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)

                    if isActive {
                        Text("Spiller nå")
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(LunaTheme.emerald)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(LunaTokens.Status.okBg, in: Capsule())
                    } else if let kindLabel = chapter.kind.badgeLabel {
                        Text(kindLabel)
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(LunaTheme.linen)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(LunaTheme.warmBorderBase.opacity(0.12), in: Capsule())
                    }
                }

                Text(chapter.title)
                    .font(LunaTheme.Font.settingsRowTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minWidth: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : (isActive ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised))
            )
            .lunaFocusSurface(.secondaryPill, isFocused: isFocused, cornerRadius: LunaTokens.Radius.chip)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

struct ObjectAudioStatusLeafView: View {
    let fallbackBadge: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(LunaTheme.Font.pillIcon)
                .foregroundStyle(LunaTheme.moonlight)
            Text("Lyd ut: \(fallbackBadge)")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.moonlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LunaTheme.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
    }
}
