import Foundation
import XCTest
@testable import LunaCore

final class PlaybackTrackIntentAndSyncTests: XCTestCase {
    func testTrackIntentPreservesSelectedLanguageAndForcedAcrossPermutedMKVIndices() {
        let mkvAAudio = [
            PlaybackAudioTrackDescriptor(id: 0, name: "English Surround", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese Master", codec: "dts-hd", language: "jpn", channels: 6),
        ]
        let mkvASubs = [
            SmartTrackDescriptor(id: 10, name: "Norsk Bokmål", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
            SmartTrackDescriptor(id: 12, name: "English", codec: "srt", language: "eng"),
        ]

        let intent = PlaybackTrackIntent.capture(
            audioTracks: mkvAAudio,
            activeAudioTrackID: 1,
            subtitleTracks: mkvASubs,
            activeSubtitleTrackID: 11,
            userManuallySelectedSubtitle: true,
            subtitleDelayMs: 150,
            audioDelayMs: -75
        )
        XCTAssertEqual(intent.subtitleDelayMs, 150)
        XCTAssertEqual(intent.audioDelayMs, -75)

        // MKV B permutes track IDs completely and adds a Japanese commentary track at index 5
        let mkvBAudio = [
            PlaybackAudioTrackDescriptor(id: 5, name: "Director Commentary", codec: "aac", language: "ja", channels: 2, isCommentary: true),
            PlaybackAudioTrackDescriptor(id: 6, name: "English TrueHD Atmos", codec: "truehd", language: "en-US", channels: 8, isAtmos: true),
            PlaybackAudioTrackDescriptor(id: 7, name: "Japanese Lossless", codec: "flac", language: "ja-JP", channels: 6),
        ]
        let mkvBSubs = [
            SmartTrackDescriptor(id: 20, name: "English SDH", codec: "srt", language: "en", isHearingImpaired: true),
            SmartTrackDescriptor(id: 21, name: "Norwegian Full", codec: "srt", language: "no"),
            SmartTrackDescriptor(id: 22, name: "Norwegian Forced", codec: "srt", language: "nor", isForced: true),
        ]

        let resolved = intent.resolve(
            audioTracks: mkvBAudio,
            currentActiveAudioID: 6,
            subtitleTracks: mkvBSubs,
            smartNordicRuleEnabled: true
        )
        XCTAssertEqual(resolved.selectedAudioTrackID, 7, "Should match non-commentary Japanese audio at new index 7")
        XCTAssertEqual(resolved.subtitleResolution, .select(22), "Should match forced Norwegian subtitle at new index 22")
        XCTAssertTrue(resolved.preserveManualSubtitleLock)
    }

    func testTrackIntentPreservesExplicitSubtitlesOffAndFallsBackToSmartRuleWhenLanguageMissing() {
        let mkvAAudio = [
            PlaybackAudioTrackDescriptor(id: 1, name: "English Atmos", codec: "truehd", language: "eng", channels: 8, isAtmos: true),
        ]
        let mkvASubs = [
            SmartTrackDescriptor(id: 3, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 4, name: "Français", codec: "srt", language: "fra"),
        ]

        // 1. Explicit "Av" must stay off even when MKV B offers Norwegian subtitles
        let offIntent = PlaybackTrackIntent.capture(
            audioTracks: mkvAAudio,
            activeAudioTrackID: 1,
            subtitleTracks: mkvASubs,
            activeSubtitleTrackID: nil,
            userManuallySelectedSubtitle: true,
            subtitleDelayMs: 0,
            audioDelayMs: 0
        )
        XCTAssertEqual(offIntent.subtitleIntent, .off)

        let mkvBAudio = [
            PlaybackAudioTrackDescriptor(id: 10, name: "English DD+", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 11, name: "English TrueHD Atmos", codec: "truehd", language: "eng", channels: 8, isAtmos: true),
        ]
        let mkvBSubs = [
            SmartTrackDescriptor(id: 30, name: "English", codec: "srt", language: "eng"),
            SmartTrackDescriptor(id: 31, name: "Norsk", codec: "srt", language: "nob"),
        ]

        let resolvedOff = offIntent.resolve(
            audioTracks: mkvBAudio,
            currentActiveAudioID: 10,
            subtitleTracks: mkvBSubs,
            smartNordicRuleEnabled: true
        )
        XCTAssertEqual(resolvedOff.selectedAudioTrackID, 11, "Should prefer object-audio Atmos track when previous English track had Atmos")
        XCTAssertEqual(resolvedOff.subtitleResolution, .clear)
        XCTAssertTrue(resolvedOff.preserveManualSubtitleLock)

        // 2. Selected French subtitle missing in MKV B -> falls back cleanly to SmartTrackRuleEngine (selects Norwegian 31)
        let frenchIntent = PlaybackTrackIntent.capture(
            audioTracks: mkvAAudio,
            activeAudioTrackID: 1,
            subtitleTracks: mkvASubs,
            activeSubtitleTrackID: 4,
            userManuallySelectedSubtitle: true,
            subtitleDelayMs: -100,
            audioDelayMs: 50
        )
        let resolvedFallback = frenchIntent.resolve(
            audioTracks: mkvBAudio,
            currentActiveAudioID: 11,
            subtitleTracks: mkvBSubs,
            smartNordicRuleEnabled: true
        )
        XCTAssertEqual(resolvedFallback.selectedAudioTrackID, 11)
        XCTAssertEqual(resolvedFallback.subtitleResolution, .select(31))
        XCTAssertFalse(resolvedFallback.preserveManualSubtitleLock)
    }

    func testUnifiedMillisecondSyncFormattingStepArithmeticAndSafeMemoryClamps() {
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(0), "0 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(150), "+150 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(-50), "−50 ms")

        XCTAssertEqual(
            PlaybackSyncTimingPolicy.headerTitle(baseTitle: "Tekstsynk", delayMs: 0),
            "Tekstsynk · 0 ms"
        )
        XCTAssertEqual(
            PlaybackSyncTimingPolicy.headerTitle(baseTitle: "Tekstsynk", delayMs: 100),
            "Tekstsynk · +100 ms"
        )
        XCTAssertEqual(
            PlaybackSyncTimingPolicy.headerTitle(baseTitle: "Lydsynk", delayMs: -50),
            "Lydsynk · −50 ms"
        )

        // Tekstsynk ±50 ms steps and AppleTV14,1 memory-bounded -5000...+10000 ms clamps
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: 0, deltaMs: -50), -50)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: -50, deltaMs: 50), 0)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: -4980, deltaMs: -50), -5000)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: 9975, deltaMs: 50), 10_000)

        // Lydsynk ±25 ms steps and -2000...+2000 ms clamps
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: 0, deltaMs: -25), -25)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: 75, deltaMs: 25), 100)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: -1990, deltaMs: -25), -2000)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: 1990, deltaMs: 25), 2000)
    }

    func testKveldslysPresetsWarmRGBZeroRawWhiteAndConsistentLabels() {
        XCTAssertEqual(
            HDRSubtitlePreset.allCases.map(\.shortTitle),
            ["Klar 100 %", "Varm 75 %", "Dempet 60 %", "Kveldsro 50 %"]
        )
        XCTAssertEqual(
            HDRSubtitlePreset.allCases.map(\.displayTitle),
            HDRSubtitlePreset.allCases.map(\.shortTitle)
        )
        XCTAssertEqual(
            HDRSubtitlePreset.allCases.map(\.compactPillLabel),
            ["100 %", "75 %", "60 %", "50 %"]
        )

        var previousRed = 1.0
        for preset in HDRSubtitlePreset.allCases {
            let rgb = preset.rgbComponents
            // Zero raw #FFFFFF (1.0, 1.0, 1.0) glare even at 100 %
            XCTAssertLessThan(rgb.r, 1.0, "Preset \(preset) must avoid raw 1.0 red peak")
            XCTAssertLessThan(rgb.g, 1.0, "Preset \(preset) must avoid raw 1.0 green peak")
            XCTAssertLessThan(rgb.b, 1.0, "Preset \(preset) must avoid raw 1.0 blue peak")
            // Warm Lampelys tint: R >= G >= B and strictly descending luminance across presets
            XCTAssertGreaterThanOrEqual(rgb.r, rgb.g)
            XCTAssertGreaterThanOrEqual(rgb.g, rgb.b)
            XCTAssertLessThan(rgb.r, previousRed)
            previousRed = rgb.r
        }
    }

    func testQuickPanelTabOrderingEditionRenameAdjacentNavigationAndPillFocusIsolation() throws {
        XCTAssertEqual(PlayerQuickPanelTab.source.title, "Utgave")
        XCTAssertEqual(PlayerQuickPanelTab.source.panelHeaderTitle, "Velg utgave")
        XCTAssertEqual(PlayerQuickPanelTab.subtitles.panelHeaderTitle, "Tekst")
        XCTAssertEqual(PlayerQuickPanelTab.audio.panelHeaderTitle, "Lyd")

        // With chapters: Tekst <-> Lyd <-> Utgave <-> Bilde <-> Kapitler
        XCTAssertNil(PlayerQuickPanelTab.subtitles.adjacentTab(direction: .left, hasChapters: true))
        XCTAssertEqual(PlayerQuickPanelTab.subtitles.adjacentTab(direction: .right, hasChapters: true), .audio)
        XCTAssertEqual(PlayerQuickPanelTab.audio.adjacentTab(direction: .right, hasChapters: true), .source)
        XCTAssertEqual(PlayerQuickPanelTab.source.adjacentTab(direction: .right, hasChapters: true), .picture)
        XCTAssertEqual(PlayerQuickPanelTab.picture.adjacentTab(direction: .right, hasChapters: true), .chapters)
        XCTAssertNil(PlayerQuickPanelTab.chapters.adjacentTab(direction: .right, hasChapters: true))
        XCTAssertEqual(PlayerQuickPanelTab.chapters.adjacentTab(direction: .left, hasChapters: true), .picture)

        // Without chapters: .chapters is skipped cleanly
        XCTAssertEqual(
            PlayerQuickPanelTab.visibleTabs(hasChapters: false),
            [.subtitles, .audio, .source, .picture]
        )
        XCTAssertNil(PlayerQuickPanelTab.picture.adjacentTab(direction: .right, hasChapters: false))
        XCTAssertEqual(PlayerQuickPanelTab.picture.adjacentTab(direction: .left, hasChapters: false), .source)

        // Horizontal pill strips never trigger Left/Right tab switching
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-kveldslys-warm_75"))
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-sync-minus"))
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-sync-zero"))
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("aud-layout-5.1.2"))
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("aud-sync-plus"))

        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-off"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-2"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("aud-0"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("aud-mode-night"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("src-cand-1"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("pic-hud"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID(nil))

        // Concise in-player Velg utgave formatting
        let candidateJSON = #"""
        {
          "candidateId": "cand-remux",
          "displayHeadline": "4K DV FEL",
          "releaseTitle": "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HEVC.TrueHD.7.1.Atmos",
          "source": "nvme",
          "tier": "nvme",
          "resolution": "2160p",
          "videoCodec": "hevc",
          "audioCodec": "TrueHD Atmos",
          "dvProfile": 7,
          "dvEnhancementLayer": "FEL",
          "sizeBytes": 68934287360,
          "isNorwegian": true
        }
        """#
        let cand = try JSONDecoder().decode(TvCandidateInfo.self, from: Data(candidateJSON.utf8))
        XCTAssertEqual(cand.inPlayerQuickRowTitle, "4K DV P7 FEL · TrueHD Atmos")
        XCTAssertEqual(
            cand.inPlayerQuickRowSubtitle(isRecommended: true, activeLabel: "Spilles nå"),
            "Norsk · På NVMe · HEVC · 64,2 GB · Spilles nå"
        )
    }

    func testSubtitleCueIndexHandlesOverlappingUnsortedBoundariesSeeksAndInvalidSpans() {
        struct Cue {
            let id: Int
            let start: Double
            let end: Double
        }

        // Empty index
        var emptyIndex = SubtitleCueIndex([Cue](), startTime: \.start, endTime: \.end)
        XCTAssertEqual(emptyIndex.activeOriginalIndices(at: 10.0), [])
        XCTAssertEqual(emptyIndex.queryOriginalIndices(at: 10.0), [])

        // Unsorted + overlapping ASS sign [10, 25) + shorter dialogue [15, 17) + invalid spans + 50 sequential cues
        var cues: [Cue] = [
            Cue(id: 0, start: 15.0, end: 17.0),           // shorter cue out of start order
            Cue(id: 1, start: 10.0, end: 25.0),           // long overlapping ASS sign
            Cue(id: 2, start: .nan, end: 5.0),            // NaN start -> filtered out
            Cue(id: 3, start: 5.0, end: 5.0),             // zero-length -> filtered out
            Cue(id: 4, start: 8.0, end: 6.0),             // inverted -> filtered out
            Cue(id: 5, start: 17.0, end: 19.5),           // adjacent at boundary 17.0
        ]
        for i in 0..<50 {
            let base = 30.0 + Double(i) * 2.0
            cues.append(Cue(id: 6 + i, start: base, end: base + 1.5))
        }

        var index = SubtitleCueIndex(cues, startTime: \.start, endTime: \.end)

        func expectedIndices(at t: Double) -> [Int] {
            cues.enumerated().compactMap { idx, cue in
                guard cue.start.isFinite, cue.end.isFinite, cue.end > cue.start else { return nil }
                return (cue.start <= t && t < cue.end) ? idx : nil
            }
        }

        // Non-finite query returns empty safely
        XCTAssertEqual(index.activeOriginalIndices(at: .nan), [])
        XCTAssertEqual(index.activeOriginalIndices(at: .infinity), [])

        // Monotonic forward 10 Hz scan across overlaps and boundaries
        for step in stride(from: 9.0, through: 26.0, by: 0.25) {
            let got = index.activeOriginalIndices(at: step)
            let expected = expectedIndices(at: step)
            XCTAssertEqual(got, expected, "Mismatch at monotonic t=\(step)")
            XCTAssertEqual(index.queryOriginalIndices(at: step), expected)
        }

        // Exact half-open bounds [start, end)
        XCTAssertEqual(index.activeOriginalIndices(at: 10.0), [1])
        XCTAssertEqual(index.activeOriginalIndices(at: 15.0), [0, 1])
        XCTAssertEqual(index.activeOriginalIndices(at: 17.0), [1, 5], "At 17.0 cue 0 ended and cue 5 started while sign 1 remains active")
        XCTAssertEqual(index.activeOriginalIndices(at: 20.0), [1], "At 20.0 long overlapping sign 1 must still be found behind shorter cues")
        XCTAssertEqual(index.activeOriginalIndices(at: 25.0), [])

        // Large forward jump (> 32 cues) followed by monotonic playback
        XCTAssertEqual(index.activeOriginalIndices(at: 120.5), expectedIndices(at: 120.5))
        XCTAssertEqual(index.activeOriginalIndices(at: 121.0), expectedIndices(at: 121.0))

        // Backward seek / negative subtitle delay shift
        XCTAssertEqual(index.activeOriginalIndices(at: 16.0), [0, 1])
        XCTAssertEqual(index.activeOriginalIndices(at: 20.0), [1])
    }

    func testPlaybackErrorGuidancePolicyMapsAllCategoriesAndHttpCodes() {
        XCTAssertTrue(
            PlaybackErrorGuidancePolicy.userMessage(
                category: .sourceOpenFailed,
                underlyingCode: 401,
                rawMessage: "err"
            ).contains("HTTP 401")
        )
        XCTAssertTrue(
            PlaybackErrorGuidancePolicy.userMessage(
                category: .sourceRefused,
                underlyingCode: 403,
                rawMessage: "err"
            ).contains("HTTP 403")
        )
        XCTAssertTrue(
            PlaybackErrorGuidancePolicy.userMessage(
                category: .sourceOpenFailed,
                ffmpegErrorCode: -541478725,
                rawMessage: "err"
            ).contains("-541478725")
        )

        for category in PlaybackErrorCategory.allCases where category != .unknown {
            let msg = PlaybackErrorGuidancePolicy.userMessage(category: category, rawMessage: "raw error")
            XCTAssertFalse(msg.isEmpty)
            XCTAssertNotEqual(msg, "raw error")
        }

        XCTAssertEqual(
            PlaybackErrorGuidancePolicy.userMessage(category: .unknown, rawMessage: "404 Not Found"),
            LunaCopy.friendlyEngineErrorMessage("404 Not Found")
        )
    }
}
