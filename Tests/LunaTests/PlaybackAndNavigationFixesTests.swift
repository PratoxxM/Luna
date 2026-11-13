import Foundation
import XCTest
@testable import Luna

final class PlaybackAndNavigationFixesTests: XCTestCase {
    func testBuildRowRequestPathReplacesExistingOffsetAndMapsCatalogPages() {
        XCTAssertEqual(
            MediaOSClient.buildRowRequestPath(pathOrRowId: "sci-fi", offset: 36, limit: 36),
            "/api/tv/v1/rows/sci-fi?offset=36&limit=36"
        )

        XCTAssertEqual(
            MediaOSClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/rows/custom?offset=0&limit=24",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v1/rows/custom?offset=48&limit=24"
        )

        XCTAssertEqual(
            MediaOSClient.buildRowRequestPath(
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
}
