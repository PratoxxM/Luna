import SwiftUI

public enum MainNavigationTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case series
    case library
    case search
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Hjem"
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .library: return "Mitt bibliotek"
        case .search: return "Søk"
        case .settings: return "Innstillinger"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "sparkles.tv"
        case .movies: return "film"
        case .series: return "tv"
        case .library: return "books.vertical.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

public enum ScrollTopZone: Equatable, Sendable {
    case atTop
    case midBand
    case scrolledDown

    public nonisolated static let revealThreshold: CGFloat = 36
    public nonisolated static let collapseThreshold: CGFloat = 88

    public nonisolated static func classify(scrolledOffsetY: CGFloat) -> ScrollTopZone {
        if scrolledOffsetY <= revealThreshold {
            return .atTop
        }
        if scrolledOffsetY >= collapseThreshold {
            return .scrolledDown
        }
        return .midBand
    }
}

public struct ScrollTopSample: Equatable, Sendable {
    public let zone: ScrollTopZone
    public let downwardBucket: Int

    public nonisolated static let stepPoints: CGFloat = 48

    public nonisolated static func capture(scrolledOffsetY: CGFloat) -> ScrollTopSample {
        let zone = ScrollTopZone.classify(scrolledOffsetY: scrolledOffsetY)
        let bucket = zone == .scrolledDown ? max(1, Int((scrolledOffsetY / stepPoints).rounded(.down))) : 0
        return ScrollTopSample(zone: zone, downwardBucket: bucket)
    }
}

public enum SubpageVisibilityPolicy {
    public nonisolated static func shouldLeaveSubpageOnDisappear(
        isRootTab: Bool = false,
        hasPushedChildDestination: Bool,
        hasActivePlayback: Bool,
        isShowingModalSheet: Bool = false
    ) -> Bool {
        !isRootTab && !hasPushedChildDestination && !hasActivePlayback && !isShowingModalSheet
    }
}

public enum TabContentFreshnessPolicy {
    public nonisolated static let defaultFreshnessInterval: TimeInterval = 120

    public nonisolated static func isCacheFresh(
        hasCachedContent: Bool,
        lastValidatedAt: Date,
        now: Date = Date(),
        cachedRefreshNonce: Int,
        currentRefreshNonce: Int,
        freshnessInterval: TimeInterval = defaultFreshnessInterval
    ) -> Bool {
        guard hasCachedContent, cachedRefreshNonce == currentRefreshNonce else {
            return false
        }
        return now.timeIntervalSince(lastValidatedAt) < freshnessInterval
    }
}

@MainActor
final class LunaNavigationBarVisibility: ObservableObject {
    nonisolated static let menuFocusBounceGraceSeconds: TimeInterval = 0.14

    @Published private(set) var activeSubpageTokens: Set<UUID> = []
    @Published private(set) var activeModalTokens: Set<UUID> = []
    @Published private(set) var isCollapsedByScroll: Bool = false
    @Published private(set) var isTopBarFocused: Bool = false
    @Published private(set) var focusRequestNonce: Int = 0

    private var scrollZonesByTab: [MainNavigationTab: ScrollTopZone] = [:]
    private var activeTab: MainNavigationTab = .home
    private var menuRevealGraceUntil: Date = .distantPast
    private(set) var pendingMenuBypassExit: Bool = false

    var isSubpageActive: Bool {
        !activeSubpageTokens.isEmpty
    }

    var isModalActive: Bool {
        !activeModalTokens.isEmpty
    }

    var isTopBarHidden: Bool {
        isSubpageActive || (isCollapsedByScroll && !isTopBarFocused)
    }

    var sink: LunaSubpageVisibilitySink {
        LunaSubpageVisibilitySink(
            enterSubpage: { [weak self] token in
                self?.enterSubpage(token)
            },
            leaveSubpage: { [weak self] token in
                self?.leaveSubpage(token)
            },
            enterModal: { [weak self] token in
                self?.enterModal(token)
            },
            leaveModal: { [weak self] token in
                self?.leaveModal(token)
            },
            reportScrollSample: { [weak self] oldSample, newSample, tab in
                self?.reportScrollSample(oldSample, newSample, for: tab)
            }
        )
    }

    func enterSubpage(_ token: UUID) {
        guard !activeSubpageTokens.contains(token) else { return }
        activeSubpageTokens.insert(token)
        pendingMenuBypassExit = false
    }

    func leaveSubpage(_ token: UUID) {
        guard activeSubpageTokens.contains(token) else { return }
        activeSubpageTokens.remove(token)
    }

    func enterModal(_ token: UUID) {
        guard !activeModalTokens.contains(token) else { return }
        activeModalTokens.insert(token)
        pendingMenuBypassExit = false
    }

    func leaveModal(_ token: UUID) {
        guard activeModalTokens.contains(token) else { return }
        activeModalTokens.remove(token)
    }

    func syncActiveTab(_ tab: MainNavigationTab) {
        activeTab = tab
        pendingMenuBypassExit = false
        if isTopBarFocused {
            if isCollapsedByScroll {
                isCollapsedByScroll = false
            }
        } else {
            let shouldCollapse = (scrollZonesByTab[tab] == .scrolledDown)
            if isCollapsedByScroll != shouldCollapse {
                isCollapsedByScroll = shouldCollapse
            }
        }
    }

    func reportScrollZone(_ zone: ScrollTopZone, for tab: MainNavigationTab, now: Date = Date()) {
        let syntheticBucket = zone == .scrolledDown ? 2 : 0
        reportScrollSample(nil, ScrollTopSample(zone: zone, downwardBucket: syntheticBucket), for: tab, now: now)
    }

    func reportScrollSample(
        _ oldSample: ScrollTopSample?,
        _ newSample: ScrollTopSample,
        for tab: MainNavigationTab,
        now: Date = Date()
    ) {
        scrollZonesByTab[tab] = newSample.zone
        guard tab == activeTab else { return }
        if now >= menuRevealGraceUntil {
            pendingMenuBypassExit = false
        }

        switch newSample.zone {
        case .atTop:
            if isCollapsedByScroll {
                isCollapsedByScroll = false
            }
        case .scrolledDown:
            let scrolledFurtherDown = (oldSample == nil)
                || (oldSample?.zone != .scrolledDown)
                || (newSample.downwardBucket > (oldSample?.downwardBucket ?? 0))
            if scrolledFurtherDown, !isTopBarFocused, now >= menuRevealGraceUntil, !isCollapsedByScroll {
                isCollapsedByScroll = true
            }
        case .midBand:
            break
        }
    }

    func updateTopBarFocused(_ focused: Bool, now: Date = Date()) {
        guard isTopBarFocused != focused else { return }
        isTopBarFocused = focused
        if focused {
            pendingMenuBypassExit = false
            if isCollapsedByScroll {
                isCollapsedByScroll = false
            }
        } else if now < menuRevealGraceUntil {
            pendingMenuBypassExit = true
        } else if scrollZonesByTab[activeTab] == .scrolledDown {
            isCollapsedByScroll = true
        }
    }

    func shouldInterceptMenuPress(hasActivePlayback: Bool) -> Bool {
        !isTopBarFocused &&
        !hasActivePlayback &&
        !isSubpageActive &&
        !isModalActive &&
        !pendingMenuBypassExit
    }

    func handleMenuPressToRevealTopBar(now: Date = Date()) {
        isCollapsedByScroll = false
        pendingMenuBypassExit = true
        menuRevealGraceUntil = now.addingTimeInterval(Self.menuFocusBounceGraceSeconds)
        focusRequestNonce &+= 1
    }
}

public struct LunaSubpageVisibilitySink: Sendable {
    public let enterSubpage: @MainActor @Sendable (UUID) -> Void
    public let leaveSubpage: @MainActor @Sendable (UUID) -> Void
    public let enterModal: @MainActor @Sendable (UUID) -> Void
    public let leaveModal: @MainActor @Sendable (UUID) -> Void
    public let reportScrollSample: @MainActor @Sendable (ScrollTopSample?, ScrollTopSample, MainNavigationTab) -> Void

    public static let noop = LunaSubpageVisibilitySink(
        enterSubpage: { _ in },
        leaveSubpage: { _ in },
        enterModal: { _ in },
        leaveModal: { _ in },
        reportScrollSample: { _, _, _ in }
    )
}

private struct LunaSubpageVisibilitySinkKey: EnvironmentKey {
    static let defaultValue: LunaSubpageVisibilitySink = .noop
}

public extension EnvironmentValues {
    var lunaSubpageVisibility: LunaSubpageVisibilitySink {
        get { self[LunaSubpageVisibilitySinkKey.self] }
        set { self[LunaSubpageVisibilitySinkKey.self] = newValue }
    }
}

extension View {
    func lunaRootScrollTopBarTracking(tab: MainNavigationTab, isEnabled: Bool = true) -> some View {
        modifier(LunaRootScrollTopBarModifier(tab: tab, isEnabled: isEnabled))
    }
}

private struct LunaRootScrollTopBarModifier: ViewModifier {
    @Environment(\.lunaSubpageVisibility) private var visibilitySink
    let tab: MainNavigationTab
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onScrollGeometryChange(for: ScrollTopSample.self) { geo in
                ScrollTopSample.capture(scrolledOffsetY: geo.contentOffset.y + geo.contentInsets.top)
            } action: { oldSample, newSample in
                visibilitySink.reportScrollSample(oldSample, newSample, tab)
            }
        } else {
            content
        }
    }
}

struct LunaTopBarView: View {
    static let contentTopPadding: CGFloat = 82
    static let focusDebounceNanoseconds: UInt64 = 180_000_000

    @Binding var selectedTab: MainNavigationTab
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

            Rectangle()
                .fill(LunaTheme.warmBorder)
                .frame(width: 1, height: 20)
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                ForEach(MainNavigationTab.allCases) { tab in
                    TopBarTabPillButton(
                        tab: tab,
                        isActive: selectedTab == tab,
                        isFocused: focusedTab == tab,
                        isBarFocused: focusedTab != nil
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

    private var emblemView: some View {
        HStack(spacing: 8) {
            LunaCrescentMarkView(size: 24, color: LunaTheme.amber)

            Text("Luna")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(LunaTheme.linen)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .allowsHitTesting(false)
    }
}

struct TopBarTabPillButton: View {
    let tab: MainNavigationTab
    let isActive: Bool
    let isFocused: Bool
    var isBarFocused: Bool = false
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
            HStack(spacing: 7) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        Self.resolveIconColor(
                            isActive: isActive,
                            isFocused: isFocused,
                            isBarFocused: isBarFocused
                        )
                    )

                Text(tab.title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(
                        Self.resolveTextColor(
                            isActive: isActive,
                            isFocused: isFocused,
                            isBarFocused: isBarFocused
                        )
                    )
                    .lineLimit(1)
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(pillBackground(showActiveRest: showActiveRest))
            .overlay(
                Capsule()
                    .strokeBorder(
                        Self.resolveBorderColor(
                            isActive: isActive,
                            isFocused: isFocused,
                            isBarFocused: isBarFocused
                        ),
                        lineWidth: isFocused ? 2.0 : 1.0
                    )
                    .transaction { $0.animation = nil }
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.32) : .clear,
                radius: isFocused ? 8 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
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
