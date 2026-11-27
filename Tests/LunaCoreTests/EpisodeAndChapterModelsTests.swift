import Foundation
import XCTest
@testable import LunaCore

final class EpisodeAndChapterModelsTests: XCTestCase {
    // MARK: - EpisodeTitleFormatter, Season 0 & Request/Picker Labels

    func testEpisodeCodeAndItemIdParsingIncludingSeasonZero() {
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 4), "S01E04")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 12, episode: 105), "S12E105")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 0, episode: 1), "S00E01")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 0, episode: 4), "S00E04")
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 0))
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: nil, episode: 4))

        let parsed = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s1:e4")
        XCTAssertEqual(parsed?.season, 1)
        XCTAssertEqual(parsed?.episode, 4)

        let specialParsed = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:100:s0:e1")
        XCTAssertEqual(specialParsed?.season, 0)
        XCTAssertEqual(specialParsed?.episode, 1)

        let upper = EpisodeTitleFormatter.parseEpisodeFromItemId("EPISODE:IMDB:tt123456:S04:E01")
        XCTAssertEqual(upper?.season, 4)
        XCTAssertEqual(upper?.episode, 1)

        let combined = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s01e04")
        XCTAssertEqual(combined?.season, 1)
        XCTAssertEqual(combined?.episode, 4)

        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("S02E11")?.season, 2)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("S02E11")?.episode, 11)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("S00E04")?.season, 0)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("1x04")?.season, 1)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("0x04")?.season, 0)
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
            "S01E04", "S01E04.", "S01 E04", "1x04", "1x04.", "s1e4",
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

        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("S00E01", seriesTitle: "Show", season: 0, episode: 1))
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("S00E01 · Julegave", seriesTitle: "Show", season: 0, episode: 1),
            "Julegave"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("401 Unauthorized", seriesTitle: "Mr. Robot", season: 4, episode: 1, episodeCode: "S04E01"),
            "401 Unauthorized"
        )
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("24 Hours", seriesTitle: "ER", season: 1, episode: 24), "24 Hours")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("101", seriesTitle: "Show", season: 1, episode: 1), "101")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("101.", seriesTitle: "Show", season: 1, episode: 1), "101.")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("#101", seriesTitle: "Show", season: 1, episode: 1), "#101")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("4x4", seriesTitle: "Show", season: 4, episode: 4), "4x4")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("4x4 · Offroad", seriesTitle: "Show", season: 4, episode: 4), "4x4 · Offroad")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("Epoch", seriesTitle: "Show", season: 1, episode: 4), "Epoch")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("Episode 4: A New Dawn", seriesTitle: "Show", season: 1, episode: 4), "Episode 4: A New Dawn")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("Severance: The Beginning", seriesTitle: "Severance", season: 1, episode: 1), "Severance: The Beginning")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("S01E04 · The You You Are", seriesTitle: "Severance", season: 1, episode: 4), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("S01E04 The You You Are", seriesTitle: "Severance", season: 1, episode: 4), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 · The You You Are", seriesTitle: "Severance", season: 1, episode: 4), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("01x04 - The You You Are", seriesTitle: "Severance"), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04. The You You Are", seriesTitle: "Severance"), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04.mp4", seriesTitle: "Show"), "1x04.mp4")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1917", seriesTitle: "Show", season: 1, episode: 1), "1917")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("4", seriesTitle: "Show", season: 1, episode: 2), "4")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("?", seriesTitle: "Show", season: 1, episode: 4), "?")
    }

    func testCurtainBottomBarEpisodeCardSourcePickerAndLaunchLabels() {
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

        let genericRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "Severance",
            seriesTitle: "Severance"
        )
        XCTAssertEqual(genericRequest.season, 1)
        XCTAssertEqual(genericRequest.episode, 4)
        XCTAssertEqual(genericRequest.formattedEpisodeCode, "S01E04")
        XCTAssertEqual(genericRequest.apiTitle, "")

        let genericItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:95396:s1:e4",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 95396),
            title: "Episode 4",
            seriesTitle: "Severance",
            season: 1,
            episode: 4
        )
        let genericBottom = EpisodeTitleFormatter.bottomBarLabels(sessionItem: genericItem, request: genericRequest)
        XCTAssertEqual(genericBottom.seriesLine, "Severance")
        XCTAssertEqual(genericBottom.titleLine, "S01E04")

        let namedItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:62560:s4:e1",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 62560),
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            season: 4,
            episode: 1
        )
        let namedBottom = EpisodeTitleFormatter.bottomBarLabels(sessionItem: namedItem, request: genericRequest)
        XCTAssertEqual(namedBottom.seriesLine, "Mr. Robot · S04E01")
        XCTAssertEqual(namedBottom.titleLine, "401 Unauthorized")

        let genericEp = TvEpisodeCard(itemId: "episode:tmdb:95396:s1:e4", seasonNumber: 1, episodeNumber: 4, title: "E04", watched: false)
        XCTAssertEqual(EpisodeTitleFormatter.episodeCardTitle(episode: genericEp, seriesTitle: "Severance"), "Episode 4")
        let namedEp = TvEpisodeCard(itemId: "episode:tmdb:62560:s4:e1", seasonNumber: 4, episodeNumber: 1, title: "401 Unauthorized", watched: false)
        XCTAssertEqual(EpisodeTitleFormatter.episodeCardTitle(episode: namedEp, seriesTitle: "Mr. Robot"), "E01 · 401 Unauthorized")

        let genericPicker = SourcePickerContext(itemId: "episode:tmdb:95396:s1:e4", title: "Episode 4", seriesTitle: "Severance")
        XCTAssertEqual(genericPicker.displaySubject, "Severance · S01E04")
        XCTAssertEqual(genericPicker.apiTitle, "")
        let namedPicker = SourcePickerContext(itemId: "episode:tmdb:62560:s4:e1", title: "401 Unauthorized", seriesTitle: "Mr. Robot", season: 4, episode: 1)
        XCTAssertEqual(namedPicker.displaySubject, "Mr. Robot · S04E01 · 401 Unauthorized")
        XCTAssertEqual(namedPicker.apiTitle, "401 Unauthorized")

        XCTAssertEqual(EpisodeTitleFormatter.apiEpisodeTitle(rawTitle: "Ukjent", seriesTitle: "Severance", itemId: "episode:tmdb:95396:s1:e4", season: 1, episode: 4), "")
        XCTAssertEqual(EpisodeTitleFormatter.apiEpisodeTitle(rawTitle: "1917", seriesTitle: nil, itemId: "movie:tmdb:530915", season: nil, episode: nil), "1917")
    }

    // MARK: - Chapter Classification, Post-Credits, Coincident Merge & Overflow/NaN Safety

    func testChapterClassificationPostCreditsAndCoincidentTheIntroDbMerging() throws {
        XCTAssertEqual(TvChapterKind.classify(title: "Recap", startSeconds: 0, durationSeconds: 2700), .recap)
        XCTAssertEqual(TvChapterKind.classify(title: "Tidligere i serien", startSeconds: 10, durationSeconds: 2700), .recap)
        XCTAssertEqual(TvChapterKind.classify(title: "Opening", startSeconds: 90, durationSeconds: 1440), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "OP 1", startSeconds: 85, durationSeconds: 1440), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "Vignett", startSeconds: 45, durationSeconds: 1800), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "Closing Credits", startSeconds: 600, durationSeconds: 2700), .credits)
        XCTAssertEqual(TvChapterKind.classify(title: "Rulletekst", startSeconds: 400, durationSeconds: 2700), .credits)

        // Character names containing "Ed" never misclassify; "ED" / "Ending 2" require >= 72% window
        XCTAssertEqual(TvChapterKind.classify(title: "Talking to Ed", startSeconds: 1380, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "ED", startSeconds: 120, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "ED", startSeconds: 1320, durationSeconds: 1440), .credits)
        XCTAssertEqual(TvChapterKind.classify(title: "Ending 2", startSeconds: 120, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "Ending 2", startSeconds: 1320, durationSeconds: 1440), .credits)

        // Post-credits aliases & semantic upgrade over generic chapter/legacy credits
        XCTAssertEqual(TvChapterKind.postCredits.rawValue, "post_credits")
        XCTAssertEqual(TvChapterKind.postCredits.badgeLabel, "Etter rulletekst")
        for raw in ["post_credits", "post-credits", "postCredits", "after-credits", "stinger", "Etter rulletekst"] {
            XCTAssertEqual(TvChapterKind.parse(rawKind: raw), .postCredits)
        }
        XCTAssertEqual(TvChapterKind.classify(title: "Post-Credits Scene", startSeconds: 6900, durationSeconds: 7200), .postCredits)
        XCTAssertEqual(TvChapterKind.resolve(rawKind: "credits", title: "Etter rulletekst", startSeconds: 5100, durationSeconds: 5400), .postCredits)
        XCTAssertEqual(TvChapterKind.resolve(rawKind: "chapter", title: "Post Credits Scene", startSeconds: 5100, durationSeconds: 5400), .postCredits)

        // Clamp negative/overflowing probe chapters
        let clamped = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 1, idString: "c2", title: "Talking to Ed", startSeconds: 1300, endSeconds: 1380, kind: nil),
                TvProbeChapter(index: 0, idString: "c1", title: "Prolog", startSeconds: -5, endSeconds: 95, kind: "intro"),
                TvProbeChapter(index: 2, idString: "c3", title: "ED", startSeconds: 1390, endSeconds: 1600, kind: nil),
            ],
            engineChapters: [],
            mediaDuration: 1440
        )
        XCTAssertEqual(clamped.map(\.kind), [.intro, .chapter, .credits])
        XCTAssertEqual(clamped[0].startSeconds, 0)
        XCTAssertEqual(clamped[2].endSeconds, 1440)

        // Coincident generic MKV + TheIntroDB segments + stacked < 1.5s credits/post_credits survival
        let coincident = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "ch1", title: "Chapter 1", startSeconds: 0, endSeconds: 2000, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "tidb-intro", title: "Intro", startSeconds: 0, endSeconds: 90, kind: "intro", source: "theintrodb"),
                TvProbeChapter(index: 2, idString: "ch3", title: "Chapter 3", startSeconds: 5000, endSeconds: 5150, kind: "chapter"),
                TvProbeChapter(index: 3, idString: "tidb-credits", title: "Rulletekst", startSeconds: 5000, endSeconds: 5150, kind: "credits", source: "theintrodb"),
                TvProbeChapter(index: 4, idString: "ch4", title: "Chapter 4", startSeconds: 5150, endSeconds: 5260, kind: "chapter"),
                TvProbeChapter(index: 5, idString: "tidb-post-credits", title: "Etter rulletekst", startSeconds: 5150, endSeconds: 5260, kind: "post_credits", source: "theintrodb"),
            ],
            engineChapters: [
                RawEngineChapter(id: 0, name: "Chapter 1", startSeconds: 0, durationSeconds: 2000),
                RawEngineChapter(id: 1, name: "Chapter 2", startSeconds: 2000, durationSeconds: 3000),
                RawEngineChapter(id: 2, name: "Chapter 3", startSeconds: 5000, durationSeconds: 150),
                RawEngineChapter(id: 3, name: "Chapter 4", startSeconds: 5150, durationSeconds: 110),
            ],
            mediaDuration: 5260
        )
        XCTAssertEqual(coincident.map(\.kind), [.intro, .chapter, .credits, .postCredits])
        XCTAssertEqual(coincident[0].endSeconds, 90, accuracy: 0.1)

        let stacked = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "ch3", title: "Chapter 3", startSeconds: 5000, endSeconds: 5260, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "tidb-cr", title: "Rulletekst", startSeconds: 5000, endSeconds: 5150, kind: "credits", source: "theintrodb"),
                TvProbeChapter(index: 2, idString: "tidb-pc", title: "Etter rulletekst", startSeconds: 5001, endSeconds: 5260, kind: "post_credits", source: "theintrodb"),
            ],
            engineChapters: [RawEngineChapter(id: 2, name: "Chapter 3", startSeconds: 5000, durationSeconds: 260)],
            mediaDuration: 5260
        )
        XCTAssertEqual(Set(stacked.map(\.kind)), [.credits, .postCredits])

        // Int.max / Int.min probe index & NaN sorting safety
        let maxChapter = try JSONDecoder().decode(TvProbeChapter.self, from: Data(#"{"index":9223372036854775807}"#.utf8))
        XCTAssertEqual(maxChapter.index, Int.max)
        XCTAssertEqual(maxChapter.title, "Kapittel 9223372036854775808")
        let minChapter = try JSONDecoder().decode(TvProbeChapter.self, from: Data(#"{"index":-9223372036854775808}"#.utf8))
        XCTAssertEqual(minChapter.index, Int.min)
        XCTAssertEqual(minChapter.title, "Kapittel -9223372036854775807")

        var nanEngine: [RawEngineChapter] = []
        var nanProbes: [TvProbeChapter] = []
        for idx in 0..<45 {
            nanEngine.append(RawEngineChapter(id: 100 - idx, name: "Kapittel \(idx)", startSeconds: (idx % 5 == 0) ? .nan : Double((45 - idx) * 30), durationSeconds: 20))
            nanProbes.append(TvProbeChapter(index: idx, idString: "p-\(idx)", title: idx == 2 ? "Intro" : "Kapittel \(idx)", startSeconds: (idx % 7 == 0) ? .nan : Double((45 - idx) * 30), endSeconds: Double((45 - idx) * 30) + 25, kind: idx == 2 ? "intro" : nil))
        }
        let mergedNaN = PlaybackChapter.mergeRaw(probeChapters: nanProbes, engineChapters: nanEngine, mediaDuration: 2000)
        XCTAssertGreaterThanOrEqual(mergedNaN.count, 45)
        XCTAssertTrue(mergedNaN.allSatisfy { $0.startSeconds.isFinite && $0.startSeconds >= 0 })
    }
}
