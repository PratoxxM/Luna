import Foundation
import XCTest
@testable import Luna

final class EpisodeTitleFormattingTests: XCTestCase {
    func testEpisodeCodeAndItemIdParsing() {
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 4), "S01E04")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 12, episode: 105), "S12E105")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 0, episode: 4), "S00E04")
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 0))
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: nil, episode: 4))

        let parsed = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s1:e4")
        XCTAssertEqual(parsed?.season, 1)
        XCTAssertEqual(parsed?.episode, 4)

        let upper = EpisodeTitleFormatter.parseEpisodeFromItemId("EPISODE:IMDB:tt123456:S04:E01")
        XCTAssertEqual(upper?.season, 4)
        XCTAssertEqual(upper?.episode, 1)

        let combined = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s01e04")
        XCTAssertEqual(combined?.season, 1)
        XCTAssertEqual(combined?.episode, 4)

        let fromCode = EpisodeTitleFormatter.parseEpisodeCode("S02E11")
        XCTAssertEqual(fromCode?.season, 2)
        XCTAssertEqual(fromCode?.episode, 11)

        let fromXCode = EpisodeTitleFormatter.parseEpisodeCode("1x04")
        XCTAssertEqual(fromXCode?.season, 1)
        XCTAssertEqual(fromXCode?.episode, 4)
        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeCode("4x4"))

        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeFromItemId("movie:tmdb:550"))
        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeFromItemId("series:tmdb:95396"))
    }

    func testGenericEpisodeTitlesAreFilteredWhileRealAndNumericLeadingTitlesSurvive() {
        let genericCases: [String?] = [
            nil, "", "   ",
            "Episode 4", "Episode 4.", "Episode 4:", "episode 04", "Episode #4",
            "Ep 4", "Ep. 04", "Ep. 4.", "Ep.4", "Ep4",
            "Del 4", "Avsnitt 4",
            "E04", "E04.", "e4",
            "S01E04", "S01E04.", "S01 E04",
            "1x04", "1x04.", "s1e4",
            "4", "04", "#4", "#04", "4.", "#4.",
            "TBA", "TBA.", "TBD", "Ukjent", "Ukjent!", "unknown",
            "Severance", "severance", "Severance S01E04", "Severance · S01E04",
            "Severance · Episode 4", "Severance · Episode 4.", "Severance · 4",
            "Severance — Episode 4", "Severance - E04", "Severance (S01E04)", "Serie S01E04",
            "S01E04 · Episode 4", "S01E04 — Episode 4", "S01E04 · 4", "S01E04 Episode 4",
            "E04 Episode 4", "S01E04 - TBA",
            "1x04 - Episode 4", "1x04 — Episode 4", "01x04 - Episode 4.", "1x04 · 4",
        ]
        for raw in genericCases {
            XCTAssertNil(
                EpisodeTitleFormatter.nonGenericEpisodeTitle(
                    raw,
                    seriesTitle: "Severance",
                    season: 1,
                    episode: 4,
                    episodeCode: "S01E04"
                ),
                "Expected generic title '\(raw ?? "nil")' to return nil"
            )
        }

        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 4,
                episode: 1,
                episodeCode: "S04E01"
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "24 Hours",
                seriesTitle: "ER",
                season: 1,
                episode: 1
            ),
            "24 Hours"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("101", seriesTitle: "Show", season: 1, episode: 1),
            "101"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("4x4", seriesTitle: "Show", season: 4, episode: 4),
            "4x4"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("Epoch", seriesTitle: "Show", season: 1, episode: 4),
            "Epoch"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Episode 4: A New Dawn",
                seriesTitle: "Show",
                season: 1,
                episode: 4
            ),
            "Episode 4: A New Dawn"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Severance: The Beginning",
                seriesTitle: "Severance",
                season: 1,
                episode: 1
            ),
            "Severance: The Beginning"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("Darkness Falls", seriesTitle: "Dark", season: 1, episode: 4),
            "Darkness Falls"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S01E04 · The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S01E04 The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S04E01 · 401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 4,
                episode: 1
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 · The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("01x04 · The You You Are", seriesTitle: "Severance"),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("01x04 - The You You Are", seriesTitle: "Severance"),
            "The You You Are"
        )
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 - Episode 4", seriesTitle: "Severance"))
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 — The You You Are", seriesTitle: "Severance"),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04. The You You Are", seriesTitle: "Severance"),
            "The You You Are"
        )
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 — Episode 4", seriesTitle: "Severance"))
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 · 4", seriesTitle: "Severance"))
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04.mp4", seriesTitle: "Show"), "1x04.mp4")
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 · 401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 1,
                episode: 4
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("1917", seriesTitle: "Show", season: 1, episode: 1),
            "1917"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("24 Hours", seriesTitle: "ER", season: 1, episode: 24),
            "24 Hours"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("4", seriesTitle: "Show", season: 1, episode: 2),
            "4"
        )
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("4", seriesTitle: "Show"), "4")
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("101.", seriesTitle: "Show", season: 1, episode: 1),
            "101."
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("#101", seriesTitle: "Show", season: 1, episode: 1),
            "#101"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("4x4 · Offroad", seriesTitle: "Show", season: 4, episode: 4),
            "4x4 · Offroad"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("?", seriesTitle: "Show", season: 1, episode: 4),
            "?"
        )
    }

    func testResolvingCurtainLabelsFromFrameZeroWithAndWithoutLogo() {
        let withLogoGeneric = EpisodeTitleFormatter.curtainLabels(
            title: "Episode 4",
            seriesTitle: "Severance",
            itemId: "episode:tmdb:95396:s1:e4",
            season: nil,
            episode: nil,
            hasLogo: true
        )
        XCTAssertNil(withLogoGeneric.seriesLine)
        XCTAssertEqual(withLogoGeneric.mainLine, "S01E04")

        let noLogoGeneric = EpisodeTitleFormatter.curtainLabels(
            title: "Severance",
            seriesTitle: "Severance",
            itemId: "episode:tmdb:95396:s1:e4",
            season: 1,
            episode: 4,
            hasLogo: false
        )
        XCTAssertEqual(noLogoGeneric.seriesLine, "Severance")
        XCTAssertEqual(noLogoGeneric.mainLine, "S01E04")

        let withLogoNumeric = EpisodeTitleFormatter.curtainLabels(
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            itemId: "episode:tmdb:62560:s4:e1",
            season: 4,
            episode: 1,
            hasLogo: true
        )
        XCTAssertNil(withLogoNumeric.seriesLine)
        XCTAssertEqual(withLogoNumeric.mainLine, "S04E01 · 401 Unauthorized")

        let noLogoNumeric = EpisodeTitleFormatter.curtainLabels(
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            itemId: "episode:tmdb:62560:s4:e1",
            season: 4,
            episode: 1,
            hasLogo: false
        )
        XCTAssertEqual(noLogoNumeric.seriesLine, "Mr. Robot")
        XCTAssertEqual(noLogoNumeric.mainLine, "S04E01 · 401 Unauthorized")

        let movieNoLogo = EpisodeTitleFormatter.curtainLabels(
            title: "1917",
            seriesTitle: nil,
            itemId: "movie:tmdb:530915",
            season: nil,
            episode: nil,
            hasLogo: false
        )
        XCTAssertNil(movieNoLogo.seriesLine)
        XCTAssertEqual(movieNoLogo.mainLine, "1917")
    }

    func testBottomBarLabelsPreventDuplicateEpisodeCodes() {
        let genericRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "",
            seriesTitle: "Severance",
            season: 1,
            episode: 4
        )
        let genericItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:95396:s1:e4",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 95396),
            title: "Episode 4",
            seriesTitle: "Severance",
            season: 1,
            episode: 4,
            year: 2022,
            runtimeSeconds: 2700,
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil
        )
        let genericLabels = EpisodeTitleFormatter.bottomBarLabels(
            sessionItem: genericItem,
            request: genericRequest
        )
        XCTAssertEqual(genericLabels.seriesLine, "Severance")
        XCTAssertEqual(genericLabels.titleLine, "S01E04")

        let namedItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:62560:s4:e1",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 62560),
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            season: 4,
            episode: 1,
            year: 2019,
            runtimeSeconds: 2800,
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil
        )
        let namedLabels = EpisodeTitleFormatter.bottomBarLabels(
            sessionItem: namedItem,
            request: genericRequest
        )
        XCTAssertEqual(namedLabels.seriesLine, "Mr. Robot · S04E01")
        XCTAssertEqual(namedLabels.titleLine, "401 Unauthorized")
    }
}
