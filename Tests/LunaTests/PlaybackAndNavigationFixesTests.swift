import AVFoundation
import Foundation
import XCTest
@testable import Luna

final class PlaybackAndNavigationFixesTests: XCTestCase {
    func testBuildRowRequestPathReplacesExistingOffsetAndMapsCatalogPages() {
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "sci-fi", offset: 36, limit: 36),
            "/api/tv/v1/rows/sci-fi?offset=36&limit=36"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/rows/custom?offset=0&limit=24",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v1/rows/custom?offset=48&limit=24"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/catalog/movies?sort=popular",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v1/catalog/movies?sort=popular&page=3&limit=24"
        )
    }

    func testTvHomeResponseSemanticEqualityIgnoresGeneratedAtOnly() {
        let row = TvShelfRow(
            rowId: "medialogg-continue",
            title: "Fortsett å se",
            rowStyle: "continue_backdrop",
            sourceKind: "system_continue",
            listMode: "smart",
            hasMore: false,
            nextPath: nil,
            items: [],
            genres: nil
        )

        let first = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:00:00Z",
            layoutMode: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let refreshedSameContent = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layoutMode: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let changedRoom = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layoutMode: "rows_first",
            roomName: "Loft",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )

        XCTAssertTrue(first.isSemanticallyEqual(to: refreshedSameContent))
        XCTAssertFalse(first.isSemanticallyEqual(to: changedRoom))
    }

    @MainActor
    func testDetailPreResolveControllerConsumeAndDiscardResetSafely() {
        let controller = DetailPreResolveController()
        XCTAssertNil(controller.consumeForPlayback(itemId: "tmdb:movie:1", client: nil))
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)

        controller.discardPreparedSession(client: nil)
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)
    }

    func testRapidReentrySettleDelayGuardsRecentDisplayCriteriaReset() {
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: nil), 0)
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: -5), 0)
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: 0), 1100)
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: 300), 800)
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: 1100), 0)
        XCTAssertEqual(PlayerAudioSessionCoordinator.rapidReentrySettleDelayMs(elapsedSinceResetMs: 2500), 0)
    }

    func testRouteChangeReactivationFilter() {
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(reasonRawValue: nil))
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(
                reasonRawValue: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(
                reasonRawValue: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(
                reasonRawValue: AVAudioSession.RouteChangeReason.override.rawValue
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(
                reasonRawValue: AVAudioSession.RouteChangeReason.categoryChange.rawValue
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldReactivateOnRouteChange(
                reasonRawValue: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            )
        )
    }

    func testAuthoritativeStreamDurationIgnoresFallbackMetadataRuntime() {
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 2642.5,
                declaredStreamDurationSeconds: 2640.0
            ),
            2642.5
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 0,
                declaredStreamDurationSeconds: 2640.0
            ),
            2640.0
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 0,
                declaredStreamDurationSeconds: nil
            ),
            0
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: -1,
                declaredStreamDurationSeconds: 0
            ),
            0
        )
    }

    func testNextEpisodePromptEligibilityWindowAndCredits() {
        let totalDuration: Double = 2400
        let chapters: [PlaybackChapter] = [
            PlaybackChapter(
                id: "credits-1",
                index: 1,
                title: "Credits",
                startSeconds: 2290,
                endSeconds: 2340,
                kind: .credits
            ),
            PlaybackChapter(
                id: "epilogue-1",
                index: 2,
                title: "Post Credits",
                startSeconds: 2340,
                endSeconds: 2400,
                kind: .chapter
            ),
        ]

        // 45s remaining without credits must NOT show prematurely
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2355,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )

        // Final 30s window (including slight audio overrun up to -5s) MUST show
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2370,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2404.5,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2406,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )

        // Credits chapter within final 120s shows pill; non-credits epilogue at 55s left hides; final 30s reappears
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2305, // 95s remaining, inside .credits
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2345, // 55s remaining, inside .chapter epilogue
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2375, // 25s remaining
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )

        // Guard conditions: dismissed, missing next episode, short/unknown duration, early playback
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: true,
                currentTime: 2385,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: false,
                isDismissedForCurrentSession: false,
                currentTime: 2385,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 60,
                authoritativeDurationSeconds: 90,
                chapters: []
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 30,
                authoritativeDurationSeconds: 100,
                chapters: []
            )
        )
    }
}
