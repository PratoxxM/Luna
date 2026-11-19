import SwiftUI

struct LunaTopBarView: View {
    static let contentTopPadding: CGFloat = 82
    static let focusDebounceNanoseconds: UInt64 = 180_000_000

    @Environment(\.lunaRoomAtmosphere) private var environmentAtmosphere

    @Binding var selectedTab: MainNavigationTab
    var roomName: String? = nil
    var focusRequestNonce: Int = 0
    var onFocusPresenceChanged: (Bool) -> Void = { _ in }

    @FocusState private var focusedTab: MainNavigationTab?
    @State private var wasBarFocused: Bool = false
    @State private var tabDebounceTask: Task<Void, Never>?
    @State private var focusRetryTask: Task<Void, Never>?
    @Namespace private var topBarFocusNamespace

    var body: some View {
        HStack(spacing: 14) {
            emblemView

            dividerView

            HStack(spacing: 8) {
                ForEach(MainNavigationTab.primaryTabs) { tab in
                    tabButton(for: tab, isIconOnly: false)
                }
            }

            dividerView

            HStack(spacing: 8) {
                ForEach(MainNavigationTab.utilityTabs) { tab in
                    tabButton(for: tab, isIconOnly: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Capsule().fill(LunaTheme.cinemaGlass))
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.warmBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 18, x: 0, y: 8)
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .padding(.top, 6)
        .defaultFocus($focusedTab, selectedTab as MainNavigationTab?)
        .focusScope(topBarFocusNamespace)
        .focusSection()
        .onChange(of: focusedTab) { _, newFocus in
            onFocusPresenceChanged(newFocus != nil)
            guard let newTab = newFocus else {
                wasBarFocused = false
                tabDebounceTask?.cancel()
                tabDebounceTask = nil
                return
            }
            wasBarFocused = true
            tabDebounceTask?.cancel()
            guard selectedTab != newTab else {
                tabDebounceTask = nil
                return
            }
            let debounceNs = Self.focusDebounceNanoseconds
            tabDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: debounceNs)
                guard !Task.isCancelled, wasBarFocused, focusedTab == newTab else { return }
                if selectedTab != newTab {
                    selectedTab = newTab
                }
            }
        }
        .onChange(of: focusRequestNonce) { _, _ in
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            focusRetryTask?.cancel()
            let target = selectedTab
            focusedTab = target
            focusRetryTask = Task { @MainActor in
                for delayNs: UInt64 in [16_000_000, 44_000_000, 72_000_000] {
                    try? await Task.sleep(nanoseconds: delayNs)
                    guard !Task.isCancelled, selectedTab == target else { return }
                    if focusedTab == nil {
                        focusedTab = target
                    } else {
                        return
                    }
                }
            }
        }
        .onAppear {
            wasBarFocused = (focusedTab != nil)
            onFocusPresenceChanged(focusedTab != nil)
        }
        .onDisappear {
            wasBarFocused = false
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            focusRetryTask?.cancel()
            focusRetryTask = nil
        }
    }

    @ViewBuilder
    private func tabButton(for tab: MainNavigationTab, isIconOnly: Bool) -> some View {
        TopBarTabPillButton(
            tab: tab,
            isActive: selectedTab == tab,
            isFocused: focusedTab == tab,
            isBarFocused: focusedTab != nil,
            isIconOnly: isIconOnly
        ) {
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            if selectedTab != tab {
                selectedTab = tab
            }
            focusedTab = tab
        }
        .focused($focusedTab, equals: tab)
        .prefersDefaultFocus(selectedTab == tab, in: topBarFocusNamespace)
    }

    private var dividerView: some View {
        Rectangle()
            .fill(LunaTheme.warmBorder)
            .frame(width: 1, height: 22)
            .allowsHitTesting(false)
    }

    private var emblemView: some View {
        let displayLabel: String = {
            let trimmed = (roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Luna" : trimmed
        }()

        return HStack(spacing: 10) {
            LunaCrescentMarkView(size: 26, color: environmentAtmosphere.lampColor)

            Text(displayLabel)
                .font(LunaTheme.Font.brandSerif)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .allowsHitTesting(false)
    }
}

struct TopBarTabPillButton: View {
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let tab: MainNavigationTab
    let isActive: Bool
    let isFocused: Bool
    var isBarFocused: Bool = false
    var isIconOnly: Bool = false
    let action: () -> Void

    nonisolated static func resolveIconColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused { return LunaTheme.canvas }
        if isActive && !isBarFocused { return LunaTheme.linen }
        return LunaTheme.muted
    }

    nonisolated static func resolveTextColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused { return LunaTheme.canvas }
        if isActive && !isBarFocused { return LunaTheme.linen }
        return LunaTheme.moonlight
    }

    nonisolated static func resolveBorderColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused { return LunaTheme.focusGoldBorder }
        if isActive && !isBarFocused { return LunaTheme.warmBorderStrong }
        return Color.clear
    }

    var body: some View {
        let showActiveRest = isActive && !isBarFocused

        Button(action: action) {
            HStack(spacing: isIconOnly ? 0 : 8) {
                if isIconOnly || tab == .home {
                    Image(systemName: tab.systemImage)
                        .font(LunaTheme.Font.tabIcon)
                        .foregroundStyle(
                            Self.resolveIconColor(
                                isActive: isActive,
                                isFocused: isFocused,
                                isBarFocused: isBarFocused
                            )
                        )
                }

                if !isIconOnly {
                    Text(tab.title)
                        .font(LunaTheme.Font.tabTitle)
                        .foregroundStyle(
                            Self.resolveTextColor(
                                isActive: isActive,
                                isFocused: isFocused,
                                isBarFocused: isBarFocused
                            )
                        )
                        .lineLimit(1)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, isIconOnly ? 14 : 18)
            .padding(.vertical, 8)
            .background(pillBackground(showActiveRest: showActiveRest))
            .overlay(
                Capsule()
                    .strokeBorder(
                        Self.resolveBorderColor(
                            isActive: isActive,
                            isFocused: isFocused,
                            isBarFocused: isBarFocused
                        ),
                        lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? 20 : 0,
                x: 0,
                y: isFocused ? 8 : 0
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
        .accessibilityLabel(tab.title)
    }

    private func pillBackground(showActiveRest: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(LunaTheme.surfaceSelected)
                .opacity(!isFocused && showActiveRest ? 1 : 0)
            Capsule()
                .fill(LunaTheme.focusGoldGradient)
                .opacity(isFocused ? 1 : 0)
        }
        .transaction { $0.animation = nil }
    }
}
