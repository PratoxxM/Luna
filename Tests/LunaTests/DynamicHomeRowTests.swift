import XCTest
@testable import Luna

final class DynamicHomeRowTests: XCTestCase {
    func testDecodeDynamicCustomBackdropLocalAndActiveSeriesRows() throws {
        let json = #"""
        {
          "ok": true,
          "layoutMode": "evening_4_row",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "rows": [
            {
              "rowId": "medialogg-continue",
              "title": "Fortsett å se",
              "rowStyle": "continue_backdrop",
              "sourceKind": "system_continue",
              "items": []
            },
            {
              "rowId": "upcoming-episodes",
              "title": "Kommende episoder",
              "rowStyle": "upcoming_backdrop",
              "sourceKind": "system_upcoming",
              "items": [
                {
                  "itemId": "series:tmdb:95396",
                  "mediaType": "series",
                  "ids": { "tmdb": 95396 },
                  "title": "Severance",
                  "episodeCode": "S02E05",
                  "episodeTitle": "Trojan's Horse",
                  "airDateBadge": "I morgen · S02E05"
                }
              ]
            },
            {
              "rowId": "custom:julefilmer",
              "title": "Populære julefilmer",
              "rowStyle": "backdrop",
              "sourceKind": "custom",
              "listMode": "smart",
              "hasMore": true,
              "nextPath": "/api/tv/v1/rows/custom%3Ajulefilmer",
              "items": [
                {
                  "itemId": "movie:tmdb:771",
                  "mediaType": "movie",
                  "ids": { "tmdb": 771 },
                  "title": "Home Alone",
                  "year": 1990
                }
              ]
            },
            {
              "rowId": "custom:lokal-4k",
              "title": "Lokale 4K-filmer",
              "rowStyle": "poster",
              "sourceKind": "local_library",
              "hasMore": false,
              "items": [
                {
                  "itemId": "movie:tmdb:693134",
                  "mediaType": "movie",
                  "ids": { "tmdb": 693134 },
                  "title": "Dune: Part Two",
                  "year": 2024,
                  "availability": { "state": "instant", "tier": "nvme", "resolution": "2160p" }
                }
              ]
            },
            {
              "rowId": "custom:mine-serier",
              "title": "Mine pågående serier",
              "rowStyle": "poster",
              "sourceKind": "active_series",
              "hasMore": false,
              "items": [
                {
                  "itemId": "series:tmdb:95396",
                  "mediaType": "series",
                  "ids": { "tmdb": 95396 },
                  "title": "Severance",
                  "year": 2022
                }
              ]
            }
          ]
        }
        """#

        let decoded = try JSONDecoder().decode(TvHomeResponse.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.rows.count, 5)

        let visible = HomeView.filterVisibleRows(decoded.rows)
        XCTAssertEqual(visible.map(\.rowId), [
            "upcoming-episodes",
            "custom:julefilmer",
            "custom:lokal-4k",
            "custom:mine-serier"
        ])
        XCTAssertEqual(visible[0].rowStyle, "upcoming_backdrop")
        XCTAssertEqual(visible[0].items.first?.upcomingPillText, "I morgen")
        XCTAssertEqual(visible[0].items.first?.cleanUpcomingSubtitle, "S2 · E5 · Trojan's Horse")
        XCTAssertEqual(visible[1].rowStyle, "backdrop")
        XCTAssertEqual(visible[1].nextPath, "/api/tv/v1/rows/custom%3Ajulefilmer")
        XCTAssertEqual(visible[2].sourceKind, "local_library")
        XCTAssertEqual(visible[2].items.first?.availability?.isPhysicalLocal, true)
        XCTAssertEqual(visible[3].sourceKind, "active_series")
    }

    func testHomeSemanticEqualityDetectsDynamicRowReorderingAndStyleChanges() throws {
        let baseJson = #"""
        {
          "ok": true,
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "rows": [
            {
              "rowId": "custom:jul",
              "title": "Julefilmer",
              "rowStyle": "poster",
              "items": [
                { "itemId": "movie:tmdb:771", "mediaType": "movie", "ids": { "tmdb": 771 }, "title": "Home Alone" }
              ]
            }
          ]
        }
        """#
        let changedJson = baseJson.replacingOccurrences(of: "\"poster\"", with: "\"backdrop\"")
        let a = try JSONDecoder().decode(TvHomeResponse.self, from: Data(baseJson.utf8))
        let b = try JSONDecoder().decode(TvHomeResponse.self, from: Data(changedJson.utf8))
        XCTAssertFalse(a.isSemanticallyEqual(to: b))
    }

    func testHomePrepareVisibleRowsDeduplicatesWatchlistAndPrioritizesContinueFromPhone() throws {
        let json = #"""
        {
          "ok": true,
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "tonight": {
            "ok": true,
            "preparedFromPhone": {
              "itemId": "movie:tmdb:693134",
              "mediaType": "movie",
              "ids": { "tmdb": 693134 },
              "title": "Dune: Part Two",
              "origin": "phone",
              "originLabel": "Fra iPhone",
              "preparedSessionId": "prep-99"
            }
          },
          "rows": [
            {
              "rowId": "medialogg-watchlist",
              "title": "Huskeliste",
              "rowStyle": "poster",
              "sourceKind": "watchlist",
              "items": [
                { "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Fight Club" }
              ]
            },
            {
              "rowId": "medialogg-local",
              "title": "Lokalt på NAS",
              "rowStyle": "poster",
              "sourceKind": "local_library",
              "items": [
                { "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Fight Club" }
              ]
            },
            {
              "rowId": "custom:lokal-4k",
              "title": "Lokale 4K-filmer",
              "rowStyle": "poster",
              "sourceKind": "local_library",
              "items": [
                { "itemId": "movie:tmdb:771", "mediaType": "movie", "ids": { "tmdb": 771 }, "title": "Home Alone" }
              ]
            },
            {
              "rowId": "medialogg-continue",
              "title": "Fortsett å se",
              "rowStyle": "continue_backdrop",
              "sourceKind": "system_continue",
              "items": [
                { "itemId": "series:tmdb:95396", "mediaType": "series", "ids": { "tmdb": 95396 }, "title": "Severance", "origin": "tonight", "originLabel": "I kveld" }
              ]
            }
          ]
        }
        """#

        let payload = try JSONDecoder().decode(TvHomeResponse.self, from: Data(json.utf8))
        let rows = HomeView.prepareVisibleRows(from: payload)

        XCTAssertEqual(rows.map(\.rowId), ["medialogg-continue", "custom:lokal-4k"])
        XCTAssertEqual(rows[0].items.map(\.itemId), ["movie:tmdb:693134", "series:tmdb:95396"])
        XCTAssertEqual(rows[0].items.first?.origin, "phone")
        XCTAssertEqual(LibraryFilterSection.allCases.map(\.label), ["Filmer", "Serier", "Huskeliste"])

        let zeroMoviesCounts = TvLibraryCounts(
            watchlist: 2,
            localTotal: 4,
            localMovies: 0,
            localSeries: 4,
            nvme: 4,
            archive: 0,
            vfs: 0,
            customLists: 0
        )
        let fallbackRes = LibraryFilterSection.resolveInitialSection(
            counts: zeroMoviesCounts,
            didApplyInitialFallback: false,
            current: .movies
        )
        XCTAssertEqual(fallbackRes.section, .series)
        XCTAssertTrue(fallbackRes.didApplyInitialFallback)

        let normalCounts = TvLibraryCounts(
            watchlist: 2,
            localTotal: 9,
            localMovies: 5,
            localSeries: 4,
            nvme: 9,
            archive: 0,
            vfs: 0,
            customLists: 0
        )
        let defaultRes = LibraryFilterSection.resolveInitialSection(
            counts: normalCounts,
            didApplyInitialFallback: false,
            current: .movies
        )
        XCTAssertEqual(defaultRes.section, .movies)
        XCTAssertTrue(defaultRes.didApplyInitialFallback)
    }
}
