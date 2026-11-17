import Foundation
import XCTest
@testable import Luna

final class LunaNavigationAndDetailRaceTests: XCTestCase {
    func testAppVersionDisplayStringIncludesBuildNumberWhenAvailable() {
        XCTAssertEqual(
            AppSessionStore.currentAppVersionString(infoDictionary: [
                "CFBundleShortVersionString": "2.3.6",
                "CFBundleVersion": "49",
            ]),
            "2.3.6"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.3.6",
                "CFBundleVersion": "49",
            ]),
            "2.3.6 (bygg 49)"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.3.6",
                "CFBundleVersion": 52,
            ]),
            "2.3.6 (bygg 52)"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: [
                "CFBundleShortVersionString": "2.3.6",
                "CFBundleVersion": "   ",
            ]),
            "2.3.6"
        )

        XCTAssertEqual(
            AppSessionStore.currentAppVersionDisplayString(infoDictionary: nil),
            "2.3.6"
        )
    }

    @MainActor
    func testMainNavigationTabsAndSubpageBarVisibilityTracking() {
        XCTAssertEqual(MainNavigationTab.allCases.count, 6)
        XCTAssertEqual(
            MainNavigationTab.allCases.map(\.title),
            ["Hjem", "Filmer", "Serier", "Mitt bibliotek", "Søk", "Innstillinger"]
        )

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

    func testPeriodicBlinkCadenceIsBoundedInUnitInterval() {
        XCTAssertEqual(PauseCatLifecycle.periodicBlinkProgress(elapsed: 0.0), 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(PauseCatLifecycle.periodicBlinkProgress(elapsed: 0.12), 0.9)
        XCTAssertEqual(PauseCatLifecycle.periodicBlinkProgress(elapsed: 2.0), 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(PauseCatLifecycle.periodicBlinkProgress(elapsed: 4.52), 0.9)
    }
}
