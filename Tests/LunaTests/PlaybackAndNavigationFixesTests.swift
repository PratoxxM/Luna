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
}
