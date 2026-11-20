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
}

/// Centered 4-tab M0 charcoal top drawer opened by swiping down during playback.
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
    @State var showAudioAdvancedControls: Bool = false
    @Namespace private var drawerTabFocusNamespace

    private let drawerBaseColor = Color(red: 14.0 / 255.0, green: 12.0 / 255.0, blue: 10.0 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    ForEach(PlayerTopDrawerTab.allCases) { tab in
                        DrawerTabTextButton(
                            title: tab.title,
                            isSelected: selectedTab == tab,
                            isFocused: focusedTab == tab
                        ) {
                            tabDebounceTask?.cancel()
                            tabDebounceTask = nil
                            withAnimation(.easeOut(duration: 0.14)) {
                                selectedTab = tab
                            }
                        }
                        .focused($focusedTab, equals: tab)
                        .prefersDefaultFocus(selectedTab == tab, in: drawerTabFocusNamespace)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .defaultFocus($focusedTab, selectedTab as PlayerTopDrawerTab?, priority: .userInitiated)
                .focusScope(drawerTabFocusNamespace)
                .focusSection()

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
                .animation(.easeOut(duration: 0.14), value: selectedTab)
                .focusSection()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 50)
            .padding(.bottom, 64)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: drawerBaseColor.opacity(0.96), location: 0.0),
                        .init(color: drawerBaseColor.opacity(0.92), location: 0.80),
                        .init(color: drawerBaseColor.opacity(0.70), location: 0.92),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: [.top, .horizontal])
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onChange(of: focusedTab) { _, newTab in
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            guard let newTab, newTab != selectedTab else { return }
            tabDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled, focusedTab == newTab else { return }
                withAnimation(.easeOut(duration: 0.14)) {
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

private struct DrawerTabTextButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let title: String
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LunaTheme.Font.tabTitle)
                .foregroundStyle(isFocused || isSelected ? LunaTheme.linen : LunaTheme.muted)
                .lineLimit(1)
                .padding(.horizontal, 28)
                .frame(height: 58)
                .background(
                    Capsule()
                        .fill(LunaTheme.surfaceElevated)
                        .opacity(isFocused || isSelected ? 1 : 0)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LunaTheme.focusGoldBorder.opacity(isFocused ? 0.85 : (isSelected ? 0.55 : 0.0)),
                            lineWidth: LunaFocusStyle.borderWidth
                        )
                )
                .shadow(
                    color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                    radius: isFocused ? 24 : 0,
                    x: 0,
                    y: isFocused ? 8 : 0
                )
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }
}

struct PlayerDrawerOptionCardButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let title: String
    let subtitle: String?
    let isSelected: Bool
    var width: CGFloat = 330
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isSelected ? "\(title) ✓" : title)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(isFocused ? LunaTheme.linen.opacity(0.86) : LunaTheme.moonlight)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(minWidth: width - 52, maxWidth: width - 52, minHeight: 84, alignment: .topLeading)
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
            )
            .overlay(
                Group {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity),
                                lineWidth: LunaFocusStyle.borderWidth
                            )
                    }
                }
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? 28 : 0,
                x: 0,
                y: isFocused ? 10 : 0
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
