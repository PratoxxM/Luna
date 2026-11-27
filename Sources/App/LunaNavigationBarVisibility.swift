import Foundation
import Observation

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
}

public enum ScrollTopZone: Equatable, Sendable {
    case atTop
    case midBand
    case scrolledDown

    public nonisolated static let revealThreshold: Double = 36
    public nonisolated static let collapseThreshold: Double = 88

    public nonisolated static func classify(scrolledOffsetY: Double) -> ScrollTopZone {
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

    public nonisolated static let stepPoints: Double = 48

    public nonisolated static func capture(scrolledOffsetY: Double) -> ScrollTopSample {
        let zone = ScrollTopZone.classify(scrolledOffsetY: scrolledOffsetY)
        let bucket: Int
        if zone == .scrolledDown {
            if scrolledOffsetY.isFinite, stepPoints.isFinite, stepPoints > 0 {
                let floored = (scrolledOffsetY / stepPoints).rounded(.down)
                if let exact = Int(exactly: floored) {
                    bucket = max(1, exact)
                } else {
                    bucket = floored > 0 ? Int.max : 1
                }
            } else {
                bucket = Int.max
            }
        } else {
            bucket = 0
        }
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
public final class LunaNavigationBarVisibility {
    public nonisolated static let menuFocusBounceGraceSeconds: TimeInterval = 0.14

    public private(set) var activeSubpageTokens: Set<UUID> = []
    public private(set) var activeModalTokens: Set<UUID> = []
    public private(set) var isCollapsedByScroll: Bool = false
    public private(set) var isTopBarFocused: Bool = false
    public private(set) var focusRequestNonce: Int = 0
    public private(set) var scrollToTopNonce: Int = 0
    public private(set) var contentEntryFocusNonce: Int = 0
    public private(set) var pendingMenuBypassExit: Bool = false

    @ObservationIgnored private var scrollZonesByTab: [MainNavigationTab: ScrollTopZone] = [:]
    @ObservationIgnored private var activeTab: MainNavigationTab = .home
    @ObservationIgnored private var menuRevealGraceUntil: Date = .distantPast

    public init() {}

    public var isSubpageActive: Bool {
        !activeSubpageTokens.isEmpty
    }

    public var isModalActive: Bool {
        !activeModalTokens.isEmpty
    }

    public var isTopBarHidden: Bool {
        isSubpageActive || (isCollapsedByScroll && !isTopBarFocused)
    }

    public var sink: LunaSubpageVisibilitySink {
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
            },
            revealTopBar: { [weak self] in
                self?.handleUpNavigationToRevealTopBar()
            }
        )
    }

    public func enterSubpage(_ token: UUID) {
        guard !activeSubpageTokens.contains(token) else { return }
        activeSubpageTokens.insert(token)
        pendingMenuBypassExit = false
    }

    public func leaveSubpage(_ token: UUID) {
        guard activeSubpageTokens.contains(token) else { return }
        activeSubpageTokens.remove(token)
    }

    public func enterModal(_ token: UUID) {
        guard !activeModalTokens.contains(token) else { return }
        activeModalTokens.insert(token)
        pendingMenuBypassExit = false
    }

    public func leaveModal(_ token: UUID) {
        guard activeModalTokens.contains(token) else { return }
        activeModalTokens.remove(token)
    }

    public func syncActiveTab(_ tab: MainNavigationTab) {
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

    public func reportScrollSample(
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

    public func updateTopBarFocused(_ focused: Bool, now: Date = Date()) {
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

    public func shouldInterceptMenuPress(hasActivePlayback: Bool) -> Bool {
        !isTopBarFocused &&
        !hasActivePlayback &&
        !isSubpageActive &&
        !isModalActive &&
        !pendingMenuBypassExit
    }

    public func handleMenuPressToRevealTopBar(now: Date = Date()) {
        isCollapsedByScroll = false
        pendingMenuBypassExit = true
        menuRevealGraceUntil = now.addingTimeInterval(Self.menuFocusBounceGraceSeconds)
        focusRequestNonce &+= 1
        scrollToTopNonce &+= 1
    }

    public func handleUpNavigationToRevealTopBar(now: Date = Date()) {
        guard !isTopBarFocused, !isSubpageActive, !isModalActive else { return }
        isCollapsedByScroll = false
        pendingMenuBypassExit = false
        menuRevealGraceUntil = now.addingTimeInterval(Self.menuFocusBounceGraceSeconds)
        focusRequestNonce &+= 1
        scrollToTopNonce &+= 1
    }

    public func requestContentEntryFocus(for tab: MainNavigationTab) {
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
    public let revealTopBar: @MainActor @Sendable () -> Void

    public init(
        enterSubpage: @escaping @MainActor @Sendable (UUID) -> Void,
        leaveSubpage: @escaping @MainActor @Sendable (UUID) -> Void,
        enterModal: @escaping @MainActor @Sendable (UUID) -> Void,
        leaveModal: @escaping @MainActor @Sendable (UUID) -> Void,
        reportScrollSample: @escaping @MainActor @Sendable (ScrollTopSample?, ScrollTopSample, MainNavigationTab) -> Void,
        revealTopBar: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.enterSubpage = enterSubpage
        self.leaveSubpage = leaveSubpage
        self.enterModal = enterModal
        self.leaveModal = leaveModal
        self.reportScrollSample = reportScrollSample
        self.revealTopBar = revealTopBar
    }

    public static let noop = LunaSubpageVisibilitySink(
        enterSubpage: { _ in },
        leaveSubpage: { _ in },
        enterModal: { _ in },
        leaveModal: { _ in },
        reportScrollSample: { _, _, _ in },
        revealTopBar: {}
    )
}
