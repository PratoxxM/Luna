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
}
