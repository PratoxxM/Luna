import Foundation
import XCTest
@testable import Luna

final class LunaNavigationAndDetailRaceTests: XCTestCase {
    func testAppVersionDisplayStringIncludesBuildNumberWhenAvailable() {
        XCTAssertEqual(
            AppSessionStore.currentAppVersionString(infoDictionary: [
                "CFBundleShortVersionString": "2.4.0",
                "CFBundleVersion": "50",
            ]),
            "2.4.0"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.4.0",
                "CFBundleVersion": "50",
            ]),
            "2.4.0 (bygg 50)"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.4.0",
                "CFBundleVersion": 52,
            ]),
            "2.4.0 (bygg 52)"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.4.0",
                "CFBundleVersion": "   ",
            ]),
            "2.4.0"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: nil),
            "2.8.1"
        )
    }

    @MainActor
    func testMainNavigationTabsAndSubpageBarVisibilityTracking() {
        XCTAssertEqual(MainNavigationTab.allCases.count, 6)
        XCTAssertEqual(
            MainNavigationTab.allCases.map(\.title),
            ["Hjem", "Filmer", "Serier", "Bibliotek", "Søk", "Innstillinger"]
        )
        XCTAssertEqual(MainNavigationTab.primaryTabs, [.home, .movies, .series, .library])
        XCTAssertEqual(MainNavigationTab.utilityTabs, [.search, .settings])
        XCTAssertTrue(MainNavigationTab.search.isIconOnlyInTopBar)
        XCTAssertTrue(MainNavigationTab.settings.isIconOnlyInTopBar)
        XCTAssertFalse(MainNavigationTab.home.isIconOnlyInTopBar)

        let visibility = LunaNavigationBarVisibility()
        XCTAssertFalse(visibility.isTopBarHidden)

        let detailToken = UUID()
        let actorSearchToken = UUID()

        visibility.enterSubpage(detailToken)
        XCTAssertTrue(visibility.isTopBarHidden)
        visibility.enterSubpage(detailToken)
        XCTAssertEqual(visibility.activeSubpageTokens.count, 1)

        visibility.enterSubpage(actorSearchToken)
        XCTAssertTrue(visibility.isTopBarHidden)
        XCTAssertEqual(visibility.activeSubpageTokens.count, 2)

        visibility.leaveSubpage(actorSearchToken)
        XCTAssertTrue(visibility.isTopBarHidden)

        visibility.leaveSubpage(detailToken)
        XCTAssertFalse(visibility.isTopBarHidden)

        // Idempotent leave never underflows
        visibility.leaveSubpage(detailToken)
        XCTAssertFalse(visibility.isTopBarHidden)
    }

    func testDetailReloadPolicyPreventsPrematurePostPlaybackPreResolveRace() {
        let scopeA = "movie#movie:tmdb:550#Kjellerstua#dv-fel-714"
        let scopeB = "movie#movie:tmdb:550#Stua#hdr10-512"

        // First appearance always loads initially
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: false,
                loadedScopeKey: nil,
                currentScopeKey: scopeA,
                lastSeenRefreshNonce: 0,
                currentRefreshNonce: 0,
                awaitingPostPlaybackRefresh: false
            ),
            .loadInitial
        )

        // Room/profile change triggers fresh load
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: true,
                loadedScopeKey: scopeA,
                currentScopeKey: scopeB,
                lastSeenRefreshNonce: 3,
                currentRefreshNonce: 3,
                awaitingPostPlaybackRefresh: false
            ),
            .loadInitial
        )

        // Returning from player BEFORE stop heartbeat advances homeRefreshNonce MUST skip premature fetch
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: true,
                loadedScopeKey: scopeA,
                currentScopeKey: scopeA,
                lastSeenRefreshNonce: 3,
                currentRefreshNonce: 3,
                awaitingPostPlaybackRefresh: true
            ),
            .skip
        )

        // Returning AFTER stop heartbeat or subpage mutation bumped homeRefreshNonce reloads preserving season
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: true,
                loadedScopeKey: scopeA,
                currentScopeKey: scopeA,
                lastSeenRefreshNonce: 3,
                currentRefreshNonce: 4,
                awaitingPostPlaybackRefresh: true
            ),
            .reloadPreservingSeason
        )
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: true,
                loadedScopeKey: scopeA,
                currentScopeKey: scopeA,
                lastSeenRefreshNonce: 3,
                currentRefreshNonce: 4,
                awaitingPostPlaybackRefresh: false
            ),
            .reloadPreservingSeason
        )

        // Unmutated subpage pop skips redundant network reload
        XCTAssertEqual(
            DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: true,
                loadedScopeKey: scopeA,
                currentScopeKey: scopeA,
                lastSeenRefreshNonce: 4,
                currentRefreshNonce: 4,
                awaitingPostPlaybackRefresh: false
            ),
            .skip
        )
    }

    func testDetailPreResolveStartPositionAwarenessPreventsStaleResumeTokenReuse() {
        // Matching item & matching startPos (including nil vs 0 and sub-second jitter) reuses token
        XCTAssertTrue(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "movie:tmdb:550",
                preparedToken: "prep-1",
                preparedStartPosition: 0,
                requestedItemId: "movie:tmdb:550",
                requestedStartPosition: nil
            )
        )
        XCTAssertTrue(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "movie:tmdb:550",
                preparedToken: "prep-1",
                preparedStartPosition: 1240.0,
                requestedItemId: "movie:tmdb:550",
                requestedStartPosition: 1240.6
            )
        )

        // Updated resume position after playback exit invalidates stale prepared token
        XCTAssertFalse(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "movie:tmdb:550",
                preparedToken: "prep-1",
                preparedStartPosition: 0,
                requestedItemId: "movie:tmdb:550",
                requestedStartPosition: 1500
            )
        )
        XCTAssertFalse(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "movie:tmdb:550",
                preparedToken: "prep-1",
                preparedStartPosition: 1500,
                requestedItemId: "movie:tmdb:550",
                requestedStartPosition: 0
            )
        )

        // Different episode or empty token cannot reuse
        XCTAssertFalse(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "episode:tmdb:95396:s1:e1",
                preparedToken: "prep-1",
                preparedStartPosition: 0,
                requestedItemId: "episode:tmdb:95396:s1:e2",
                requestedStartPosition: 0
            )
        )
        XCTAssertFalse(
            DetailPreResolveController.canReusePreparedSession(
                preparedItemId: "movie:tmdb:550",
                preparedToken: "",
                preparedStartPosition: 0,
                requestedItemId: "movie:tmdb:550",
                requestedStartPosition: 0
            )
        )
    }

    func testDecodeMonitorFieldsOnItemDetailAndMonitorResponse() throws {
        let detailJson = #"""
        {
          "itemId": "series:tmdb:95396",
          "mediaType": "series",
          "ids": { "tmdb": 95396 },
          "title": "Severance",
          "inWatchlist": true,
          "watched": false,
          "monitored": true,
          "monitorMode": "unwatched"
        }
        """#
        let decoded = try JSONDecoder().decode(TvItemDetail.self, from: Data(detailJson.utf8))
        XCTAssertTrue(decoded.isMonitoredFlag)
        XCTAssertEqual(decoded.monitorMode, "unwatched")

        let unmonitoredJson = #"""
        {
          "itemId": "movie:tmdb:550",
          "mediaType": "movie",
          "ids": { "tmdb": 550 },
          "title": "Fight Club",
          "inWatchlist": false,
          "watched": false
        }
        """#
        let decodedMovie = try JSONDecoder().decode(TvItemDetail.self, from: Data(unmonitoredJson.utf8))
        XCTAssertFalse(decodedMovie.isMonitoredFlag)
        XCTAssertNil(decodedMovie.monitorMode)

        let ackJson = #"""
        {
          "ok": true,
          "monitored": true,
          "monitorMode": "all",
          "profileId": "uhd-bluray"
        }
        """#
        let monitorAck = try JSONDecoder().decode(TvMonitorResponse.self, from: Data(ackJson.utf8))
        XCTAssertTrue(monitorAck.ok)
        XCTAssertEqual(monitorAck.monitored, true)
        XCTAssertEqual(monitorAck.monitorMode, "all")
        XCTAssertEqual(monitorAck.profileId, "uhd-bluray")
    }

    @MainActor
    func testTopBarScrollCollapseMenuWakeupTabFreshnessAndSubpagePlaybackGuard() {
        // 1. ~180 ms top bar focus debounce, 10-foot dock clearance & scroll zone hysteresis deadband
        XCTAssertEqual(LunaTopBarView.focusDebounceNanoseconds, 180_000_000)
        XCTAssertEqual(LunaTopBarView.contentTopPadding, 148)
        XCTAssertEqual(ScrollTopZone.collapseThreshold, 88)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: -12), .atTop)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 36), .atTop)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 54), .midBand)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 87), .midBand)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 88), .scrolledDown)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 420), .scrolledDown)

        // 2. Siri Remote «Menu/Tilbake» from root-tab content (both un-scrolled & scrolled) vs top bar exit
        let visibility = LunaNavigationBarVisibility()
        visibility.syncActiveTab(.home)
        XCTAssertFalse(visibility.isTopBarHidden)
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.isTopBarFocused)
        // Un-scrolled root-tab content (e.g. Home row 1 on launch) intercepts Menu to focus LunaTopBarView
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: true))

        // Pressing Menu from un-scrolled content requests focus in LunaTopBarView
        let topPressAt = Date(timeIntervalSinceReferenceDate: 500)
        visibility.handleMenuPressToRevealTopBar(now: topPressAt)
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.isTopBarHidden)
        XCTAssertEqual(visibility.focusRequestNonce, 1)
        // Immediate second Menu press before focus lands exits to Apple TV Home Screen (never traps)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Once focus is in LunaTopBarView, Menu exits to Apple TV Home Screen
        visibility.updateTopBarFocused(true, now: topPressAt.addingTimeInterval(0.02))
        XCTAssertTrue(visibility.isTopBarFocused)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Across all 6 root tabs at top (scrolledOffsetY < 88): top-bar focus -> exit, content focus -> focus top bar
        for tab in MainNavigationTab.allCases {
            visibility.syncActiveTab(tab)
            XCTAssertFalse(visibility.isCollapsedByScroll)
            XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

            visibility.updateTopBarFocused(false, now: topPressAt.addingTimeInterval(0.30))
            XCTAssertFalse(visibility.isCollapsedByScroll)
            XCTAssertTrue(
                visibility.shouldInterceptMenuPress(hasActivePlayback: false),
                "Un-scrolled content on \(tab) must intercept Menu to focus LunaTopBarView"
            )

            // Subpage & modal guards also suppress Menu interception when un-scrolled
            let unscrollSubToken = UUID()
            visibility.enterSubpage(unscrollSubToken)
            XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
            visibility.leaveSubpage(unscrollSubToken)
            XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

            let unscrollModalToken = UUID()
            visibility.enterModal(unscrollModalToken)
            XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
            visibility.leaveModal(unscrollModalToken)
            XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

            visibility.updateTopBarFocused(true, now: topPressAt.addingTimeInterval(0.40))
        }

        // Return focus to Home content at top before testing scroll collapse
        visibility.syncActiveTab(.home)
        visibility.updateTopBarFocused(false, now: topPressAt.addingTimeInterval(0.60))
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Mid-band jitter at top does NOT hide bar, while Menu still moves focus up to top bar
        visibility.reportScrollZone(.midBand, for: .home)
        XCTAssertFalse(visibility.isTopBarHidden)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Downward scroll past 88 pt hides top bar and arms Menu wakeup
        visibility.reportScrollZone(.scrolledDown, for: .home)
        XCTAssertTrue(visibility.isCollapsedByScroll)
        XCTAssertTrue(visibility.isTopBarHidden)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: true))

        // Inside a subpage or modal sheet/dialog, Menu press MUST NOT be intercepted
        let subToken = UUID()
        visibility.enterSubpage(subToken)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
        visibility.leaveSubpage(subToken)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        let modalToken = UUID()
        visibility.enterModal(modalToken)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))
        visibility.leaveModal(modalToken)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Pressing Menu springs top bar back into view & requests focus, with 140 ms Frame-0 bounce grace
        let pressAt = Date(timeIntervalSinceReferenceDate: 1_000)
        visibility.handleMenuPressToRevealTopBar(now: pressAt)
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.isTopBarHidden)
        XCTAssertEqual(visibility.focusRequestNonce, 2)
        // Second immediate Menu press passes through to tvOS Home Screen (never traps user)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Frame-0 focus bounce within 140 ms grace window neither re-collapses top bar nor re-traps Menu
        visibility.updateTopBarFocused(true, now: pressAt.addingTimeInterval(0.01))
        visibility.updateTopBarFocused(false, now: pressAt.addingTimeInterval(0.05))
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Quick human Down-swipe at 250 ms MUST immediately re-collapse top bar and re-arm Menu wakeup
        visibility.updateTopBarFocused(true, now: pressAt.addingTimeInterval(0.08))
        visibility.updateTopBarFocused(false, now: pressAt.addingTimeInterval(0.25))
        XCTAssertTrue(visibility.isCollapsedByScroll)
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        // Even if focus never entered the top bar after Menu-reveal, neither background-tab scroll samples
        // nor grace-window (<140 ms) layout scroll jitter may clear pendingMenuBypassExit (preventing a Menu trap).
        let secondPressAt = Date(timeIntervalSinceReferenceDate: 2_000)
        visibility.handleMenuPressToRevealTopBar(now: secondPressAt)
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        let s0 = ScrollTopSample.capture(scrolledOffsetY: 0)
        let s420 = ScrollTopSample.capture(scrolledOffsetY: 420)
        let s360 = ScrollTopSample.capture(scrolledOffsetY: 360)
        let s490 = ScrollTopSample.capture(scrolledOffsetY: 490)

        // Inactive tab (.movies) emitting scroll sample after Menu press MUST NOT clobber active tab's bypass guard
        visibility.reportScrollSample(s0, s420, for: .movies, now: secondPressAt.addingTimeInterval(0.30))
        XCTAssertFalse(
            visibility.shouldInterceptMenuPress(hasActivePlayback: false),
            "Inactive tab scroll sample must not clear pendingMenuBypassExit on active tab"
        )

        // Active tab (.home) emitting layout scroll jitter within 140 ms grace window MUST NOT trap Menu either
        visibility.reportScrollSample(s420, s490, for: .home, now: secondPressAt.addingTimeInterval(0.04))
        XCTAssertFalse(visibility.isCollapsedByScroll)
        XCTAssertFalse(
            visibility.shouldInterceptMenuPress(hasActivePlayback: false),
            "Active-tab scroll jitter inside menuFocusBounceGraceSeconds must preserve anti-trap exit bypass"
        )

        // Reset movies back to top for subsequent tab-switch assertion
        visibility.reportScrollZone(.atTop, for: .movies, now: secondPressAt.addingTimeInterval(0.30))

        // After 140 ms grace window, scrolling UP keeps the revealed bar & re-arms Menu, while scrolling DOWN collapses
        visibility.reportScrollSample(s420, s360, for: .home, now: secondPressAt.addingTimeInterval(0.30))
        XCTAssertFalse(visibility.isCollapsedByScroll, "Scrolling up after Menu reveal must keep top bar visible")
        XCTAssertTrue(visibility.shouldInterceptMenuPress(hasActivePlayback: false))

        visibility.reportScrollSample(s420, s490, for: .home, now: secondPressAt.addingTimeInterval(0.35))
        XCTAssertTrue(visibility.isCollapsedByScroll, "Continuing downward scroll must re-collapse top bar")

        // Switching to an un-scrolled tab (.movies) reveals top bar; scrolling back to top reveals top bar
        visibility.syncActiveTab(.movies)
        XCTAssertFalse(visibility.isCollapsedByScroll)
        visibility.syncActiveTab(.home)
        XCTAssertTrue(visibility.isCollapsedByScroll)
        visibility.reportScrollZone(.atTop, for: .home)
        XCTAssertFalse(visibility.isCollapsedByScroll)

        // 3. Subpage disappear guard when direct playback launches (`activePlaybackTarget != nil`)
        XCTAssertTrue(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: false,
                hasActivePlayback: false
            )
        )
        XCTAssertFalse(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: false,
                hasActivePlayback: true
            )
        )
        XCTAssertFalse(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: true,
                hasActivePlayback: false
            )
        )
        XCTAssertFalse(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: false,
                hasActivePlayback: false,
                isShowingModalSheet: true
            )
        )
        XCTAssertFalse(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: true,
                hasPushedChildDestination: false,
                hasActivePlayback: false
            )
        )

        // 4. Tab in-memory freshness policy prevents redundant re-fetching on tab switch
        let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
        XCTAssertTrue(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: t0,
                now: t0.addingTimeInterval(45),
                cachedRefreshNonce: 7,
                currentRefreshNonce: 7
            )
        )
        XCTAssertFalse(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: t0,
                now: t0.addingTimeInterval(45),
                cachedRefreshNonce: 7,
                currentRefreshNonce: 8
            )
        )
        XCTAssertFalse(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: t0,
                now: t0.addingTimeInterval(125),
                cachedRefreshNonce: 7,
                currentRefreshNonce: 7
            )
        )
        XCTAssertFalse(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: false,
                lastValidatedAt: t0,
                now: t0.addingTimeInterval(5),
                cachedRefreshNonce: 7,
                currentRefreshNonce: 7
            )
        )
    }
}
