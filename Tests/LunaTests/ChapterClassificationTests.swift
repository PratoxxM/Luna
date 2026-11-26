import XCTest
@testable import Luna

final class ChapterClassificationTests: XCTestCase {
    func testClassifyRecapAndIntroTitles() {
        XCTAssertEqual(TvChapterKind.classify(title: "Recap", startSeconds: 0, durationSeconds: 2700), .recap)
        XCTAssertEqual(TvChapterKind.classify(title: "Tidligere i serien", startSeconds: 10, durationSeconds: 2700), .recap)

        XCTAssertEqual(TvChapterKind.classify(title: "Opening", startSeconds: 90, durationSeconds: 1440), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "OP 1", startSeconds: 85, durationSeconds: 1440), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "Intro", startSeconds: 120, durationSeconds: 2600), .intro)
        XCTAssertEqual(TvChapterKind.classify(title: "Vignett", startSeconds: 45, durationSeconds: 1800), .intro)
    }

    func testClassifyCreditsAndAnimeEndingEdgeCases() {
        XCTAssertEqual(TvChapterKind.classify(title: "Closing Credits", startSeconds: 600, durationSeconds: 2700), .credits)
        XCTAssertEqual(TvChapterKind.classify(title: "Rulletekst", startSeconds: 400, durationSeconds: 2700), .credits)

        // Regression guard: ordinary character names containing "Ed" must never classify as credits
        XCTAssertEqual(TvChapterKind.classify(title: "Talking to Ed", startSeconds: 1380, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "Talking to Ed", startSeconds: 120, durationSeconds: 1440), .chapter)

        // "ED" / "Ending 2" only classify as credits in the late episode window (>= 72%)
        XCTAssertEqual(TvChapterKind.classify(title: "ED", startSeconds: 120, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "ED", startSeconds: 1320, durationSeconds: 1440), .credits)
        XCTAssertEqual(TvChapterKind.classify(title: "Ending 2", startSeconds: 120, durationSeconds: 1440), .chapter)
        XCTAssertEqual(TvChapterKind.classify(title: "Ending 2", startSeconds: 1320, durationSeconds: 1440), .credits)
    }

    func testMergeProbeChaptersPreservesExplicitKindAndClampsRanges() {
        let probes = [
            TvProbeChapter(index: 1, idString: "c2", title: "Talking to Ed", startSeconds: 1300, endSeconds: 1380, kind: nil),
            TvProbeChapter(index: 0, idString: "c1", title: "Prolog", startSeconds: -5, endSeconds: 95, kind: "intro"),
            TvProbeChapter(index: 2, idString: "c3", title: "ED", startSeconds: 1390, endSeconds: 1600, kind: nil),
        ]

        let merged = PlaybackChapter.merge(probeChapters: probes, engineChapters: [], mediaDuration: 1440)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].id, "prb-c1-0")
        XCTAssertEqual(merged[0].startSeconds, 0)
        XCTAssertEqual(merged[0].kind, .intro)

        XCTAssertEqual(merged[1].id, "prb-c2-1")
        XCTAssertEqual(merged[1].kind, .chapter)

        XCTAssertEqual(merged[2].id, "prb-c3-2")
        XCTAssertEqual(merged[2].endSeconds, 1440)
        XCTAssertEqual(merged[2].kind, .credits)
    }

    func testMergeRawSortsEngineChaptersAndClampsToMediaDuration() {
        let engineChapters = [
            RawEngineChapter(id: 2, name: "ED", startSeconds: 1390, durationSeconds: 200),
            RawEngineChapter(id: 1, name: "Opening", startSeconds: 85, durationSeconds: 0),
        ]
        let probes = [
            TvProbeChapter(index: 0, idString: "op", title: "OP", startSeconds: 85.4, endSeconds: 175, kind: "intro")
        ]

        let merged = PlaybackChapter.mergeRaw(
            probeChapters: probes,
            engineChapters: engineChapters,
            mediaDuration: 1440
        )
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].title, "Opening")
        XCTAssertEqual(merged[0].kind, .intro)
        XCTAssertEqual(merged[0].endSeconds, 1390, accuracy: 0.1)

        XCTAssertEqual(merged[1].title, "ED")
        XCTAssertEqual(merged[1].endSeconds, 1440, accuracy: 0.1)
        XCTAssertEqual(merged[1].kind, .credits)
    }

    func testDecodeTheIntroDbSegmentAndMergeWithGenericEngineChapters() throws {
        let json = """
        [
          {"id":"theintrodb-intro-0","title":"Intro","startSeconds":45,"endSeconds":118,"kind":"intro","type":"intro","source":"theintrodb"},
          {"id":"theintrodb-credits-1","title":"Rulletekst","startSeconds":2580,"endSeconds":2700,"kind":"credits","type":"credits","source":"theintrodb"}
        ]
        """.data(using: .utf8)!

        let probes = try JSONDecoder().decode([TvProbeChapter].self, from: json)
        XCTAssertEqual(probes.count, 2)
        XCTAssertEqual(probes[0].kind, "intro")
        XCTAssertEqual(probes[0].source, "theintrodb")

        let genericEngine = [
            RawEngineChapter(id: 1, name: "Chapter 01", startSeconds: 0, durationSeconds: 2700)
        ]
        let merged = PlaybackChapter.mergeRaw(probeChapters: probes, engineChapters: genericEngine, mediaDuration: 2700)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.kind), [.chapter, .intro, .credits])
        XCTAssertEqual(merged.map(\.index), [0, 1, 2])
    }

    func testPostCreditsClassificationParsingAndMergeRaw() throws {
        XCTAssertEqual(TvChapterKind.postCredits.rawValue, "post_credits")
        XCTAssertEqual(TvChapterKind.postCredits.badgeLabel, "Etter rulletekst")
        XCTAssertEqual(TvChapterKind.parse(rawKind: "post_credits"), .postCredits)
        XCTAssertEqual(TvChapterKind.parse(rawKind: "post-credits"), .postCredits)
        XCTAssertEqual(TvChapterKind.parse(rawKind: "postCredits"), .postCredits)
        XCTAssertEqual(TvChapterKind.parse(rawKind: "after-credits"), .postCredits)
        XCTAssertEqual(TvChapterKind.parse(rawKind: "stinger"), .postCredits)
        XCTAssertEqual(TvChapterKind.parse(rawKind: "Etter rulletekst"), .postCredits)

        XCTAssertEqual(TvChapterKind.classify(title: "Post-Credits Scene", startSeconds: 6900, durationSeconds: 7200), .postCredits)
        XCTAssertEqual(TvChapterKind.classify(title: "After Credits", startSeconds: 6900, durationSeconds: 7200), .postCredits)
        XCTAssertEqual(TvChapterKind.classify(title: "Stinger", startSeconds: 6900, durationSeconds: 7200), .postCredits)
        XCTAssertEqual(TvChapterKind.classify(title: "Etter rulletekst", startSeconds: 6900, durationSeconds: 7200), .postCredits)

        let json = """
        [
          {"id":"cr-1","title":"Rulletekst","startSeconds":6600,"endSeconds":6900,"type":"credits"},
          {"id":"pc-1","title":"Bonus","startSeconds":6900,"endSeconds":7050,"type":"post-credits"}
        ]
        """.data(using: .utf8)!
        let probes = try JSONDecoder().decode([TvProbeChapter].self, from: json)
        XCTAssertEqual(probes.map(\.kind), ["credits", "post-credits"])

        let genericEngine = [
            RawEngineChapter(id: 1, name: "Chapter 01", startSeconds: 0, durationSeconds: 7200)
        ]
        let merged = PlaybackChapter.mergeRaw(probeChapters: probes, engineChapters: genericEngine, mediaDuration: 7200)
        XCTAssertEqual(merged.map(\.kind), [.chapter, .credits, .postCredits])
    }

    func testMergeRawGenericChapterAndLegacyCreditsDoNotSuppressSemanticTitles() {
        let engineMerged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "intro", title: "Intro", startSeconds: 45, endSeconds: 120, kind: "chapter"),
                TvProbeChapter(index: 12, idString: "stinger", title: "Post Credits Scene", startSeconds: 5100, endSeconds: 5220, kind: "chapter"),
            ],
            engineChapters: [
                RawEngineChapter(id: 1, name: "Intro", startSeconds: 45, durationSeconds: 75),
                RawEngineChapter(id: 12, name: "Post Credits Scene", startSeconds: 5100, durationSeconds: 120),
            ],
            mediaDuration: 5400
        )
        XCTAssertEqual(engineMerged.map(\.kind), [.intro, .postCredits])

        let probeOnlyMerged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "op", title: "Intro", startSeconds: 30, endSeconds: 100, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "pc", title: "Etter rulletekst", startSeconds: 5100, endSeconds: 5220, kind: "credits"),
            ],
            engineChapters: [],
            mediaDuration: 5400
        )
        XCTAssertEqual(probeOnlyMerged.map(\.kind), [.intro, .postCredits])
    }

    func testCoincidentGenericMkvAndTheIntroDbSegmentsArePreserved() {
        let merged = PlaybackChapter.mergeRaw(
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

        XCTAssertEqual(merged.map(\.kind), [.intro, .chapter, .credits, .postCredits])
        XCTAssertEqual(merged[0].endSeconds, 90, accuracy: 0.1)
    }
}
