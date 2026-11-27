import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class NavigationAndSettingsViewsTests: XCTestCase {
    @MainActor
    func testTopBarScrollCollapseMenuWakeupBounceGraceAndUpNavigationReveal() {
        XCTAssertEqual(MainNavigationTab.primaryTabs, [.home, .movies, .series, .library])
        XCTAssertEqual(MainNavigationTab.utilityTabs, [.search, .settings])
        XCTAssertEqual(LunaTopBarView.focusDebounceNanoseconds, 180_000_000)
        XCTAssertEqual(LunaTopBarView.contentTopPadding, 162)
        XCTAssertEqual(ScrollTopZone.collapseThreshold, 88)

        let visibility = LunaNavigationBarVisibility()
        visibility.syncActiveTab(.home)
        XCTAssertFalse(visibility.isTopBarHidden)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: true))

        let topPressAt = Date(timeIntervalSinceReferenceDate: 500)
        visibility.handleMenuPressToRevealTopBar(now: topPressAt)
        XCTAssertEqual(visibility.focusRequestNonce, 1)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        for tab in MainNavigationTab.allCases {
            visibility.syncActiveTab(tab)
            visibility.updateTopBarFocused(false, now: topPressAt.addingTimeInterval(0.30))
            XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
            let subToken = UUID()
            visibility.enterSubpage(subToken)
            XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
            visibility.leaveSubpage(subToken)
        }

        visibility.syncActiveTab(.home)
        visibility.updateTopBarFocused(false, now: topPressAt.addingTimeInterval(0.60))
        visibility.reportScrollSample(nil, ScrollTopSample.capture(scrolledOffsetY: 420), for: .home)
        XCTAssertTrue(visibility.isCollapsedByScroll && visibility.isTopBarHidden)

        // 140 ms Frame-0 focus bounce grace keeps top bar expanded; Down-swipe at 250 ms re-collapses
        let pressAt = Date(timeIntervalSinceReferenceDate: 1_000)
        visibility.handleMenuPressToRevealTopBar(now: pressAt)
        visibility.updateTopBarFocused(true, now: pressAt.addingTimeInterval(0.01))
        visibility.updateTopBarFocused(false, now: pressAt.addingTimeInterval(0.05))
        XCTAssertFalse(visibility.isCollapsedByScroll)

        visibility.updateTopBarFocused(true, now: pressAt.addingTimeInterval(0.08))
        visibility.updateTopBarFocused(false, now: pressAt.addingTimeInterval(0.25))
        XCTAssertTrue(visibility.isCollapsedByScroll)

        // Up navigation reveals top bar safely without bypassing Menu
        visibility.syncActiveTab(.settings)
        visibility.reportScrollSample(nil, ScrollTopSample.capture(scrolledOffsetY: 420), for: .settings)
        XCTAssertTrue(visibility.isCollapsedByScroll)
        visibility.handleUpNavigationToRevealTopBar(now: Date(timeIntervalSinceReferenceDate: 3_000))
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.pendingMenuBypassExit)
        XCTAssertEqual(visibility.scrollToTopNonce, 1)
    }

    @MainActor
    func testTabMemoryInvalidationTLSResetAndEntryFocusHelpers() throws {
        let tracker = MountedEntryCardTracker()
        let ids = (0..<30).map { "movie:tmdb:\(1000 + $0)" }
        XCTAssertEqual(tracker.resolveEntryID(orderedIDs: ids), ids[0])
        for i in 18..<30 { tracker.markAppeared(ids[i]) }
        XCTAssertEqual(tracker.resolveEntryID(orderedIDs: ids), ids[18])

        XCTAssertFalse(SettingsView.shouldRevealTopBarOnUpMove(isActiveTab: false, directionIsUp: true, focusedCategory: .roomAndDisplay, isRightPanel: false))
        XCTAssertTrue(SettingsView.shouldRevealTopBarOnUpMove(isActiveTab: true, directionIsUp: true, focusedCategory: .roomAndDisplay, isRightPanel: false))
        XCTAssertFalse(SettingsView.shouldRevealTopBarOnUpMove(isActiveTab: true, directionIsUp: true, focusedCategory: .roomAndDisplay, isRightPanel: true))
        for lowerCategory in SettingsCategory.allCases.dropFirst() {
            XCTAssertFalse(SettingsView.shouldRevealTopBarOnUpMove(isActiveTab: true, directionIsUp: true, focusedCategory: lowerCategory, isRightPanel: false))
        }

        XCTAssertEqual(CustomRowBrowseView.resolveInitialFocusTarget(currentEntryCardID: nil, oldFirstID: nil, newFirstID: "movie:tmdb:100"), "movie:tmdb:100")
        XCTAssertNil(CustomRowBrowseView.resolveInitialFocusTarget(currentEntryCardID: "movie:tmdb:100", oldFirstID: "movie:tmdb:100", newFirstID: "movie:tmdb:101"))

        let scope = try IsolatedDefaultsScope(prefix: "luna.test.tabmem")
        defer {
            CatalogBrowseMemoryCache.shared.clear()
            LibraryBrowseMemoryCache.shared.clear()
            scope.cleanup()
        }

        CatalogBrowseMemoryCache.shared.store(
            CatalogBrowseSnapshot(
                items: [TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club")],
                availableGenres: [], selectedGenreLabel: nil, hasMore: false, currentPage: 1, fetchedAt: Date(), refreshNonce: 1
            ),
            for: "http://lunacore.local:8090#movie#all#popular#false#false#Stua#hdr10-512"
        )
        let libPayload = TvLibraryResponse(
            ok: true, section: "watchlist",
            counts: TvLibraryCounts(watchlist: 1, localTotal: 0, nvme: 0, archive: 0, vfs: 0, customLists: 0),
            watchlist: [], localItems: []
        )
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(payload: libPayload, localItems: [], localOffset: 0, localHasMore: false, fetchedAt: Date(), refreshNonce: 1),
            for: "http://lunacore.local:8090#watchlist#all#all#recent#Stua#hdr10-512"
        )

        let store = AppSessionStore(defaults: scope.defaults)
        let pairedURL = try XCTUnwrap(URL(string: "https://media-box.example.test:8920"))
        store.completePairing(
            baseURL: pairedURL,
            token: "test-token-value-1234",
            pairedDevice: TvPairedDeviceInfo(
                deviceId: store.deviceID, deviceName: "Apple TV", roomName: "Stua",
                hardwareProfile: "hdr10-512", overrides: TvDeviceOverrides()
            )
        )
        XCTAssertEqual(store.appliedTLSConfiguredHost, "media-box.example.test")
        XCTAssertTrue(AppSessionStore.shouldTrustServerHost("media-box.example.test", configuredHost: store.appliedTLSConfiguredHost, allowSelfSignedLanTLS: store.allowSelfSignedLanTLS))

        let prevNonce = store.homeRefreshNonce
        store.unpairDevice()
        XCTAssertEqual(CatalogBrowseMemoryCache.shared.entryCount, 0)
        XCTAssertEqual(LibraryBrowseMemoryCache.shared.entryCount, 0)
        XCTAssertNotEqual(store.homeRefreshNonce, prevNonce)

        store.resetAllConnectionSettings()
        XCTAssertNil(store.serverBaseURL)
        XCTAssertNil(store.appliedTLSConfiguredHost)
        XCTAssertFalse(AppSessionStore.shouldTrustServerHost("media-box.example.test", configuredHost: store.appliedTLSConfiguredHost, allowSelfSignedLanTLS: store.allowSelfSignedLanTLS))
    }

    @MainActor
    func testSettingsPairingDeleteSheetsAndNavigationWindowBackdrops() async throws {
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.navbackdrop")
        defer { scope.cleanup() }
        let engineScope = try SharedTestEngineScope()
        defer { engineScope.stop() }

        let probeView = NonFocusableBackdropProbeView(frame: .zero)
        XCTAssertFalse(probeView.canBecomeFocused)

        let store = AppSessionStore(defaults: scope.defaults)
        store.setRoomAndProfile(roomName: "Stua", hardwareProfile: "hdr10-512")

        let windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let topBarHost = UIHostingController(rootView: LunaTopBarView(selectedTab: .constant(.settings)))
        let topBarFit = topBarHost.sizeThatFits(in: CGSize(width: 1920, height: 1080))
        XCTAssertGreaterThan(topBarFit.width, 400)
        XCTAssertLessThanOrEqual(topBarFit.height, 140)

        let deleteTarget = TvDeleteRequestTarget(kind: "movie", itemId: "movie:tmdb:550", tmdbId: 550, title: "Fight Club", scope: .title)
        let deleteHost = UIHostingController(
            rootView: DetailDeleteSheetView(target: deleteTarget, onDeleted: { _ in }, onCancel: {}).environment(store)
        )
        let pairingHost = UIHostingController(rootView: PairingOnboardingView(isPreviewMode: true).environment(store))
        _ = deleteHost.sizeThatFits(in: CGSize(width: 1920, height: 1080))
        _ = pairingHost.sizeThatFits(in: CGSize(width: 1920, height: 1080))

        for category in SettingsCategory.allCases {
            let settingsHost = UIHostingController(
                rootView: SettingsView(initialCategory: category).environment(store).environment(store.comfort)
            )
            window.rootViewController = settingsHost
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 15_000_000)
            XCTAssertEqual(settingsHost.view.bounds.size, CGSize(width: 1920, height: 1080))
        }

        let rootHost = UIHostingController(
            rootView: HomeView().environment(store).lunaNavigationContainerBackdrop(mode: .ambient(isPaused: false))
        )
        rootHost.additionalSafeAreaInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)
        let nav = UINavigationController(rootViewController: rootHost)
        window.rootViewController = nav
        window.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 120_000_000)

        try assertCanvasUIColor(window.backgroundColor)
        try assertCanvasUIColor(nav.view.backgroundColor)
        try assertCanvasUIColor(rootHost.view.backgroundColor)

        let pushedHost = UIHostingController(
            rootView: MediaDetailView(mediaType: "movie", itemId: "movie:tmdb:550", initialTitle: "Fight Club").environment(store)
        )
        nav.pushViewController(pushedHost, animated: false)
        window.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 90_000_000)
        try assertCanvasUIColor(pushedHost.view.backgroundColor)
        nav.popViewController(animated: false)

        let shellHost = UIHostingController(
            rootView: MainNavigationShell(engine: engineScope.engine).environment(store).environment(store.comfort)
        )
        window.rootViewController = shellHost
        window.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 150_000_000)
        let installers = collectDescendants(of: shellHost).compactMap { $0 as? BackdropInstallerViewController }
        XCTAssertFalse(installers.isEmpty)
        try assertCanvasUIColor(window.backgroundColor)
    }

    @MainActor
    private func collectDescendants(of controller: UIViewController) -> [UIViewController] {
        var result: [UIViewController] = []
        for child in controller.children {
            result.append(child)
            result.append(contentsOf: collectDescendants(of: child))
        }
        return result
    }

    private func assertCanvasUIColor(_ color: UIColor?, file: StaticString = #filePath, line: UInt = #line) throws {
        let resolved = try XCTUnwrap(color, file: file, line: line).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a), file: file, line: line)
        XCTAssertEqual(Double(r), 10.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(g), 9.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(b), 8.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(a), 1.0, accuracy: 0.01, file: file, line: line)
    }
}
