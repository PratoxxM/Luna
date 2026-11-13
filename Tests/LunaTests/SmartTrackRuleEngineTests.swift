import XCTest
@testable import Luna

final class SmartTrackRuleEngineTests: XCTestCase {
    func testNorwegianAudioClearsFullSubtitlesWhenNoForcedTrackExists() {
        let audio = SmartTrackDescriptor(id: 1, name: "Norwegian", codec: "eac3", language: "nob")
        let subs = [
            SmartTrackDescriptor(id: 10, name: "Norwegian Bokmål", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "English", codec: "srt", language: "eng"),
        ]

        let decision = SmartTrackRuleEngine.evaluate(activeAudio: audio, subtitleTracks: subs)
        XCTAssertEqual(decision, .clearSubtitles)
    }

    func testNorwegianAudioKeepsNorwegianForcedTrackByFlagOrName() {
        let audio = SmartTrackDescriptor(id: 1, name: "Norsk 5.1", codec: "dts", language: "no")
        let fullNo = SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nb")
        let forcedByName = SmartTrackDescriptor(id: 11, name: "Norsk Tvungen", codec: "srt", language: "nob")

        XCTAssertEqual(
            SmartTrackRuleEngine.evaluate(activeAudio: audio, subtitleTracks: [fullNo, forcedByName]),
            .selectTrack(11)
        )

        let forcedByFlag = SmartTrackDescriptor(id: 12, name: "Norwegian", codec: "pgs", language: "nor", isForced: true)
        XCTAssertEqual(
            SmartTrackRuleEngine.evaluate(activeAudio: audio, subtitleTracks: [fullNo, forcedByFlag]),
            .selectTrack(12)
        )
    }

    func testForeignAudioPrefersStandardTextNorwegianOverSDHBitmapAndForced() {
        let audio = SmartTrackDescriptor(id: 1, name: "English Atmos", codec: "truehd", language: "eng")
        let forcedNo = SmartTrackDescriptor(id: 20, name: "Norwegian Forced", codec: "srt", language: "nob", isForced: true)
        let sdhNo = SmartTrackDescriptor(id: 21, name: "Norwegian SDH", codec: "srt", language: "nob", isHearingImpaired: true)
        let bitmapNo = SmartTrackDescriptor(id: 22, name: "Norwegian PGS", codec: "hdmv_pgs_subtitle", language: "nob")
        let commentaryNo = SmartTrackDescriptor(id: 23, name: "Norwegian Commentary", codec: "srt", language: "nob", isCommentary: true)
        let cleanTextNo = SmartTrackDescriptor(id: 24, name: "Norsk (Bokmål)", codec: "subrip", language: "nb")

        let decision = SmartTrackRuleEngine.evaluate(
            activeAudio: audio,
            subtitleTracks: [forcedNo, sdhNo, bitmapNo, commentaryNo, cleanTextNo]
        )
        XCTAssertEqual(decision, .selectTrack(24))
    }

    func testForeignAudioFallsBackToEnglishIgnoringCommentary() {
        let audio = SmartTrackDescriptor(id: 1, name: "Japanese", codec: "flac", language: "jpn")
        let commentaryEn = SmartTrackDescriptor(id: 30, name: "English Director Commentary", codec: "srt", language: "eng", isCommentary: true)
        let cleanEn = SmartTrackDescriptor(id: 31, name: "English", codec: "ass", language: "en")

        let decision = SmartTrackRuleEngine.evaluate(
            activeAudio: audio,
            subtitleTracks: [commentaryEn, cleanEn]
        )
        XCTAssertEqual(decision, .selectTrack(31))
    }

    func testNormalizeLanguageAndForcedWordBoundaries() {
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("nb"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("norsk"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage(nil, fallbackName: "Norwegian Bokmål"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("eng"), "eng")

        let reinforced = SmartTrackDescriptor(id: 40, name: "Reinforced Dialogue", codec: "srt", language: "eng")
        let forced = SmartTrackDescriptor(id: 41, name: "Norwegian Forced", codec: "srt", language: "nob")
        XCTAssertFalse(SmartTrackRuleEngine.isTrackForced(reinforced))
        XCTAssertTrue(SmartTrackRuleEngine.isTrackForced(forced))
    }
}
