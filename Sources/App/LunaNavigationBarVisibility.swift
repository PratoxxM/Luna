import Observation
import SwiftUI

public enum MainNavigationTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case series
    case library
    case search
    case settings

    public static let primaryTabs: [MainNavigationTab] = [.home, .movies, .series, .library]
    public static let utilityTabs: [MainNavigationTab] = [.search, .settings]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Hjem"
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .library: return "Bibliotek"
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
        case .settings: return "slider.horizontal.3"
        }
    }

    public var isIconOnlyInTopBar: Bool {
        self == .search || self == .settings
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

    public nonisolated static var effectiveFreshnessInterval: TimeInterval {
        DeviceHardwareCapabilities.isHighMemoryDevice ? 600 : defaultFreshnessInterval
    }

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
@Observable
final class LunaNavigationBarVisibility {
    nonisolated static let menuFocusBounceGraceSeconds: TimeInterval = 0.14

    private(set) var activeSubpageTokens: Set<UUID> = []
    private(set) var activeModalTokens: Set<UUID> = []
    private(set) var isCollapsedByScroll: Bool = false
    private(set) var isTopBarFocused: Bool = false
    private(set) var focusRequestNonce: Int = 0
    private(set) var scrollToTopNonce: Int = 0
    private(set) var contentEntryFocusNonce: Int = 0
    private(set) var pendingMenuBypassExit: Bool = false

    @ObservationIgnored private var scrollZonesByTab: [MainNavigationTab: ScrollTopZone] = [:]
    @ObservationIgnored private var activeTab: MainNavigationTab = .home
    @ObservationIgnored private var menuRevealGraceUntil: Date = .distantPast

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
        scrollToTopNonce &+= 1
    }

    func requestContentEntryFocus(for tab: MainNavigationTab) {
        activeTab = tab
        pendingMenuBypassExit = false
        isTopBarFocused = false
        isCollapsedByScroll = (scrollZonesByTab[tab] == .scrolledDown)
        contentEntryFocusNonce &+= 1
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

private struct LunaScrollToTopNonceKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

private struct LunaContentEntryFocusNonceKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    var lunaSubpageVisibility: LunaSubpageVisibilitySink {
        get { self[LunaSubpageVisibilitySinkKey.self] }
        set { self[LunaSubpageVisibilitySinkKey.self] = newValue }
    }

    var lunaScrollToTopNonce: Int {
        get { self[LunaScrollToTopNonceKey.self] }
        set { self[LunaScrollToTopNonceKey.self] = newValue }
    }

    var lunaContentEntryFocusNonce: Int {
        get { self[LunaContentEntryFocusNonceKey.self] }
        set { self[LunaContentEntryFocusNonceKey.self] = newValue }
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
