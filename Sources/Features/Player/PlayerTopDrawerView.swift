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
    let onClose: () -> Void

    @FocusState private var focusedTab: PlayerTopDrawerTab?
    @State var chapterSnapshotTime: Double = 0

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
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedTab = tab
                            }
                        }
                        .focused($focusedTab, equals: tab)
                    }

                    Spacer()

                    Text("Menyknappen lukker")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.muted)

                    LunaPillButton("Lukk", systemImage: "chevron.up", prominence: .subtleChip) {
                        onClose()
                    }
                }

                Divider()
                    .overlay(LunaTheme.warmBorderSubtle)

                Group {
                    switch selectedTab {
                    case .info:
                        infoTabContent
                    case .audioAndSubtitles:
                        audioAndSubtitlesTabContent
                    case .source:
                        sourceTabContent
                    case .chapters:
                        chaptersTabContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    .fill(LunaTheme.warmBorder)
                    .frame(height: 1)
                    .ignoresSafeArea(edges: .horizontal)
            }

            Spacer()
        }
        .onAppear {
            focusedTab = selectedTab
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
                        isSelected ? LunaTheme.amber : (isFocused ? LunaTheme.linen : LunaTheme.muted)
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
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                isFocused ? LunaTheme.amber.opacity(0.22) : LunaTheme.warmBorderBase.opacity(0.09),
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
            .overlay(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isSelected ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.32) : .clear,
                radius: isFocused ? 10 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? 1.012 : 1.0)
            .animation(LunaFocusStyle.focusSpring, value: isFocused)
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
                        .foregroundStyle(isFocused ? LunaTheme.canvas.opacity(0.84) : LunaTheme.amber)

                    if isActive {
                        Text("Spiller nå")
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.canvas)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                isFocused ? LunaTheme.canvas : LunaTheme.amber,
                                in: Capsule()
                            )
                    } else if let kindLabel = chapter.kind.badgeLabel {
                        Text(kindLabel)
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.canvas)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                isFocused ? LunaTheme.canvas : LunaTheme.amber,
                                in: Capsule()
                            )
                    }
                }

                Text(chapter.title)
                    .font(LunaTheme.Font.settingsRowTitle)
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.linen)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minWidth: 204, alignment: .leading)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                        .fill(LunaTheme.focusGoldGradient)
                } else {
                    RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                        .fill(isActive ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isActive ? LunaTheme.warmBorderStrong : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.34) : .clear,
                radius: isFocused ? 10 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .animation(LunaFocusStyle.focusSpring, value: isFocused)
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
                .foregroundStyle(LunaTheme.amber)
            Text("Aktiv lydkjede: \(fallbackBadge)")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.moonlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LunaTheme.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
    }
}
