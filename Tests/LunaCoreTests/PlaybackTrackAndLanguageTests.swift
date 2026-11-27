import Foundation
import XCTest
@testable import LunaCore

final class PlaybackTrackAndLanguageTests: XCTestCase {
    // MARK: - SmartTrackRuleEngine & OriginalLanguageTrackSelector

    func testSmartTrackRuleEngineNordicRulesWordBoundariesAndISO639Aliases() {
        let norAudio = SmartTrackDescriptor(id: 1, name: "Norsk 5.1", codec: "eac3", language: "nob")
        let fullNo = SmartTrackDescriptor(id: 10, name: "Norsk Bokmål", codec: "srt", language: "nob")
        let fullEn = SmartTrackDescriptor(id: 11, name: "English", codec: "srt", language: "eng")
        let forcedByName = SmartTrackDescriptor(id: 12, name: "Norsk Tvungen", codec: "srt", language: "nob")
        let forcedByFlag = SmartTrackDescriptor(id: 13, name: "Norwegian", codec: "pgs", language: "nor", isForced: true)

        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: norAudio, subtitleTracks: [fullNo, fullEn]), .clearSubtitles)
        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: norAudio, subtitleTracks: [fullNo, forcedByName]), .selectTrack(12))
        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: norAudio, subtitleTracks: [fullNo, forcedByFlag]), .selectTrack(13))

        let engAudio = SmartTrackDescriptor(id: 1, name: "English Atmos", codec: "truehd", language: "eng")
        let sdhNo = SmartTrackDescriptor(id: 21, name: "Norwegian SDH", codec: "srt", language: "nob", isHearingImpaired: true)
        let bitmapNo = SmartTrackDescriptor(id: 22, name: "Norwegian PGS", codec: "hdmv_pgs_subtitle", language: "nob")
        let commentaryNo = SmartTrackDescriptor(id: 23, name: "Norwegian Commentary", codec: "srt", language: "nob", isCommentary: true)
        let cleanTextNo = SmartTrackDescriptor(id: 24, name: "Norsk (Bokmål)", codec: "subrip", language: "nb")

        XCTAssertEqual(
            SmartTrackRuleEngine.evaluate(activeAudio: engAudio, subtitleTracks: [forcedByFlag, sdhNo, bitmapNo, commentaryNo, cleanTextNo]),
            .selectTrack(24)
        )
        // Full English beats forced Norwegian when full Norwegian is absent
        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: engAudio, subtitleTracks: [forcedByFlag, fullEn]), .selectTrack(11))

        let jpnAudio = SmartTrackDescriptor(id: 1, name: "Japanese", codec: "flac", language: "jpn")
        let commentaryEn = SmartTrackDescriptor(id: 30, name: "Director Commentary", codec: "srt", language: "eng", isCommentary: true)
        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: jpnAudio, subtitleTracks: [commentaryEn, fullEn]), .selectTrack(11))

        // Word boundaries & BCP-47 / ISO 639-1/2 normalization
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("nb-NO"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("nn_NO"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage(nil, fallbackName: "Norwegian Bokmål"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("en-US"), "eng")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("sv-SE"), "swe")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("da-DK"), "dan")

        XCTAssertFalse(SmartTrackRuleEngine.isTrackForced(SmartTrackDescriptor(id: 40, name: "Reinforced Dialogue", codec: "srt", language: "eng")))
        XCTAssertFalse(SmartTrackRuleEngine.isTrackForced(SmartTrackDescriptor(id: 41, name: "Norwegian (Non-Forced)", codec: "srt", language: "nob")))
        XCTAssertFalse(SmartTrackRuleEngine.isTrackForced(SmartTrackDescriptor(id: 42, name: "Norsk ikke tvungen", codec: "srt", language: "nob")))
        XCTAssertTrue(SmartTrackRuleEngine.isTrackForced(SmartTrackDescriptor(id: 43, name: "Norwegian Forced", codec: "srt", language: "nob")))

        XCTAssertFalse(SmartTrackRuleEngine.isNameSDH("Accent English"))
        XCTAssertFalse(SmartTrackRuleEngine.isNameSDH("Occitan"))
        XCTAssertTrue(SmartTrackRuleEngine.isNameSDH("English [CC]"))
        XCTAssertTrue(SmartTrackRuleEngine.isNameSDH("Norsk (SDH)"))

        let fra = SmartTrackDescriptor(id: 1, name: "Français", codec: "srt", language: "fra")
        let ger = SmartTrackDescriptor(id: 2, name: "Deutsch", codec: "srt", language: "ger")
        let zho = SmartTrackDescriptor(id: 3, name: "Chinese", codec: "srt", language: "chi")
        XCTAssertEqual(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "fre", in: [fra, fullEn]), 1)
        XCTAssertEqual(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "deu", in: [ger, fullEn]), 2)
        XCTAssertEqual(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "zh-CN", in: [zho, fullEn]), 3)
    }

    func testOriginalLanguageTrackSelectorCodecRankingAndCommentaryExclusion() {
        let tracks = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Norsk 5.1", codec: "eac3", language: "nob", channels: 6, isDefault: true),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese Commentary", codec: "truehd", language: "ja", channels: 2, isCommentary: true),
            PlaybackAudioTrackDescriptor(id: 2, name: "Japanese AAC", codec: "aac", language: "jpn", channels: 2),
            PlaybackAudioTrackDescriptor(id: 3, name: "Japanese TrueHD Atmos", codec: "truehd", language: "ja-JP", channels: 8, isAtmos: true),
            PlaybackAudioTrackDescriptor(id: 4, name: "English DTS-HD MA", codec: "dts-hd", language: "eng", channels: 8),
        ]
        XCTAssertTrue(OriginalLanguageTrackSelector.containsNorwegianTrack(in: tracks))
        XCTAssertEqual(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: tracks, originalLanguage: "ja", preferNorwegianAudio: false)?.id, 3)
        XCTAssertEqual(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: tracks, originalLanguage: "ja", preferNorwegianAudio: true)?.id, 0)
        XCTAssertEqual(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: tracks, originalLanguage: "ko", preferNorwegianAudio: false)?.id, 3)
        XCTAssertEqual(OriginalLanguageTrackSelector.preferredAudioLanguageCodes(forOriginalLanguage: "ja", preferNorwegianAudio: false), ["jpn", "ja", "eng"])
        XCTAssertEqual(OriginalLanguageTrackSelector.preferredAudioLanguageCodes(forOriginalLanguage: "ja", preferNorwegianAudio: true), ["nob", "nor", "no", "nb", "eng"])

        let dtsXvsEac3 = [
            PlaybackAudioTrackDescriptor(id: 1, name: "English EAC3", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 2, name: "English DTS:X", codec: "dts", language: "eng", channels: 8, isDTSX: true),
        ]
        XCTAssertEqual(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: dtsXvsEac3, originalLanguage: "en")?.id, 2)

        let commentaryOnly = [
            PlaybackAudioTrackDescriptor(id: 7, name: "Director Commentary", codec: "aac", language: "eng", channels: 2, isCommentary: true)
        ]
        XCTAssertFalse(OriginalLanguageTrackSelector.containsNorwegianTrack(in: commentaryOnly))
        XCTAssertEqual(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: commentaryOnly, originalLanguage: "eng")?.id, 7)
    }

    // MARK: - PlaybackTrackIntent, Sync Timing, HDR Presets, QuickPanel Tabs & Cue Index

    func testPlaybackTrackIntentSyncTimingHDRPresetsQuickPanelAndSubtitleCueIndex() {
        let mkvAAudio = [
            PlaybackAudioTrackDescriptor(id: 0, name: "English", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese", codec: "dts-hd", language: "jpn", channels: 6),
        ]
        let mkvASubs = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
        ]
        let intent = PlaybackTrackIntent.capture(
            audioTracks: mkvAAudio, activeAudioTrackID: 1, subtitleTracks: mkvASubs, activeSubtitleTrackID: 11,
            userManuallySelectedSubtitle: true, subtitleDelayMs: 150, audioDelayMs: -75
        )
        let mkvBAudio = [
            PlaybackAudioTrackDescriptor(id: 5, name: "Commentary", codec: "aac", language: "ja", channels: 2, isCommentary: true),
            PlaybackAudioTrackDescriptor(id: 7, name: "Japanese Lossless", codec: "flac", language: "ja-JP", channels: 6),
        ]
        let mkvBSubs = [
            SmartTrackDescriptor(id: 21, name: "Norwegian Full", codec: "srt", language: "no"),
            SmartTrackDescriptor(id: 22, name: "Norwegian Forced", codec: "srt", language: "nor", isForced: true),
        ]
        let resolved = intent.resolve(audioTracks: mkvBAudio, currentActiveAudioID: 5, subtitleTracks: mkvBSubs, smartNordicRuleEnabled: true)
        XCTAssertEqual(resolved.selectedAudioTrackID, 7)
        XCTAssertEqual(resolved.subtitleResolution, .select(22))
        XCTAssertTrue(resolved.preserveManualSubtitleLock)

        // Explicit off & extreme Int.max/Int.min channel count safety
        let offIntent = PlaybackTrackIntent.capture(audioTracks: mkvAAudio, activeAudioTrackID: 0, subtitleTracks: mkvASubs, activeSubtitleTrackID: nil, userManuallySelectedSubtitle: true, subtitleDelayMs: 0, audioDelayMs: 0)
        XCTAssertEqual(offIntent.resolve(audioTracks: mkvAAudio, currentActiveAudioID: 0, subtitleTracks: mkvBSubs, smartNordicRuleEnabled: true).subtitleResolution, .clear)

        let extremeIntent = PlaybackTrackIntent(audioIntent: .matching(languageCode: "eng", isCommentary: false, prefersObjectAudio: false, preferredChannels: 6), subtitleIntent: .automatic)
        let extremeTracks = [PlaybackAudioTrackDescriptor(id: 1, language: "eng", channels: Int.max), PlaybackAudioTrackDescriptor(id: 2, language: "eng", channels: 6), PlaybackAudioTrackDescriptor(id: 3, language: "eng", channels: Int.min)]
        XCTAssertEqual(extremeIntent.resolve(audioTracks: extremeTracks, currentActiveAudioID: nil, subtitleTracks: [], smartNordicRuleEnabled: false).selectedAudioTrackID, 2)

        // Sync timing arithmetic & overflow clamps
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(0), "0 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(150), "+150 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(-50), "−50 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.formatSignedDelayMs(Int.min), "−9223372036854775808 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.headerTitle(baseTitle: "Tekstsynk", delayMs: 100), "Tekstsynk · +100 ms")
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.max, deltaMs: Int.max), 10_000)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.min, deltaMs: Int.min), -5_000)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.max, deltaMs: Int.max), 2_000)
        XCTAssertEqual(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.min, deltaMs: Int.min), -2_000)

        // Warm Kveldslys RGB < 1.0 peak & QuickPanel tabs
        var previousRed = 1.0
        for preset in HDRSubtitlePreset.allCases {
            let rgb = preset.rgbComponents
            XCTAssertTrue(rgb.r < 1.0 && rgb.r >= rgb.g && rgb.g >= rgb.b && rgb.r < previousRed)
            previousRed = rgb.r
        }
        XCTAssertEqual(PlayerQuickPanelTab.source.panelHeaderTitle, "Velg utgave")
        XCTAssertEqual(PlayerQuickPanelTab.visibleTabs(hasChapters: false), [.subtitles, .audio, .source, .picture])
        XCTAssertNil(PlayerQuickPanelTab.picture.adjacentTab(direction: .right, hasChapters: false))
        XCTAssertTrue(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-kveldslys-warm_75"))
        XCTAssertFalse(PlayerQuickPanelTab.isHorizontalPillFocusID("sub-off"))

        // SubtitleCueIndex overlapping ASS sign + unsorted + invalid spans + forward/backward jumps
        struct Cue { let id: Int; let start: Double; let end: Double }
        var cues: [Cue] = [
            Cue(id: 0, start: 15.0, end: 17.0),
            Cue(id: 1, start: 10.0, end: 25.0),
            Cue(id: 2, start: .nan, end: 5.0),
            Cue(id: 3, start: 5.0, end: 5.0),
            Cue(id: 4, start: 17.0, end: 19.5),
        ]
        for i in 0..<40 {
            let base = 30.0 + Double(i) * 2.0
            cues.append(Cue(id: 5 + i, start: base, end: base + 1.5))
        }
        var cueIndex = SubtitleCueIndex(cues, startTime: \.start, endTime: \.end)
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: .nan), [])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 10.0), [1])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 15.0), [0, 1])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 17.0), [1, 4])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 20.0), [1])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 100.5), [40])
        XCTAssertEqual(cueIndex.activeOriginalIndices(at: 16.0), [0, 1])
    }

    // MARK: - PlaybackSubtitleSyncActionPolicy, PlaybackPreferenceStore & PlaybackSessionPolicy

    func testEmbeddedSubtitleTrackMatchingPreferenceStoreConcurrencyAndSessionPolicy() async throws {
        let extOld = TvExternalSubtitle(id: "sub-1", url: "/sub/1.srt", language: "eng", name: "English")
        let extNew = TvExternalSubtitle(id: "sub-2", url: "/sub/2.srt", language: "nob", name: "Norsk", isDefault: true)
        let mergedExt = PlaybackSubtitleSyncActionPolicy.mergedExternalSubtitles(
            existing: [extOld],
            response: TvSubtitleSearchAttachResponse(sessionId: "s1", attached: true, status: "attached", subtitle: extNew, externalSubtitles: [extNew])
        )
        XCTAssertEqual(mergedExt.count, 2)
        XCTAssertEqual(PlaybackSubtitleSyncActionPolicy.preferredSearchLanguages(originalLanguage: "ja"), ["nob", "nor", "no", "eng", "jpn"])

        let externalTrack = SmartTrackDescriptor(id: 5, name: "Norsk", codec: "srt", language: "nob", isExternal: true)
        XCTAssertEqual(PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(for: externalTrack, in: mergedExt)?.id, "sub-2")
        XCTAssertNil(PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(for: SmartTrackDescriptor(id: 0, name: "Norsk", codec: "subrip", language: "nob", isExternal: false), in: mergedExt))

        // 3-track ordinal collision & global stream-indexed embedded track matching
        let threeEmbeddedSameLang = [
            TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "subrip", language: "eng", displayTitle: "English SDH"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "subrip", language: "eng", displayTitle: "English Commentary"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 4, codec: "subrip", language: "eng", displayTitle: "English Forced"),
        ]
        let ordinalDescs = [
            SmartTrackDescriptor(id: 0, name: "English SDH", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 1, name: "English Commentary", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 2, name: "English Forced", codec: "subrip", language: "eng", isExternal: false),
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(for: ordinalDescs[2], embeddedSubtitles: threeEmbeddedSameLang, allDescriptors: ordinalDescs),
            4
        )
        let globalDescs = [
            SmartTrackDescriptor(id: 2, name: "English SDH", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 3, name: "English Commentary", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 4, name: "English Forced", codec: "subrip", language: "eng", isExternal: false),
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(for: globalDescs[2], embeddedSubtitles: threeEmbeddedSameLang, allDescriptors: globalDescs),
            4
        )
        XCTAssertEqual(PlaybackSubtitleSyncActionPolicy.friendlyAlignReasonMessage("invalid_extracted_srt"), "Kunne ikke lese innebygd undertekst")

        // PlaybackPreferenceStore clamping, explicit 0 reset & 24-task concurrency
        let suite = "luna.v1.test.prefstore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PlaybackPreferenceStore(suiteName: suite)
        store.setSubtitleDelayMs(15_000, forCandidateId: "cand-a")
        XCTAssertEqual(store.subtitleDelayMs(forCandidateId: "cand-a"), 10_000)
        store.setSubtitleDelayMs(0, forCandidateId: "cand-a")
        XCTAssertTrue(store.hasStoredSubtitleDelay(forCandidateId: "cand-a"))
        XCTAssertEqual(PlaybackSessionPolicy.resolvedInitialSubtitleDelayMs(candidateId: "cand-a", sessionDelayMs: 350, tracksDelayMs: 350, preferenceStore: store), 0)
        XCTAssertEqual(PlaybackSessionPolicy.resolvedInitialSubtitleDelayMs(candidateId: "cand-unseen", sessionDelayMs: 250, tracksDelayMs: nil, preferenceStore: store), 250)

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<24 {
                group.addTask {
                    store.setPreferNorwegianAudio(idx.isMultiple(of: 2), forItemId: "movie:tmdb:\(idx)")
                    store.setSubtitleDelayMs(idx * 50, forCandidateId: "cand-\(idx)")
                    _ = store.preferNorwegianAudio(forItemId: "movie:tmdb:\(idx)")
                    _ = store.subtitleDelayMs(forCandidateId: "cand-\(idx)")
                }
            }
        }
        XCTAssertTrue(store.preferNorwegianAudio(forItemId: "movie:tmdb:4"))
        XCTAssertEqual(store.subtitleDelayMs(forCandidateId: "cand-10"), 500)

        let chapters = [PlaybackChapter(id: "c1", index: 0, title: "Rulletekst", startSeconds: 5000, endSeconds: 5300, kind: .credits)]
        XCTAssertTrue(PlaybackSessionPolicy.isPlaybackCompleted(positionSeconds: 5100, durationSeconds: 5400, playbackEnded: false, chapters: chapters))
        XCTAssertEqual(PlaybackSessionPolicy.inferredMediaType(sessionMediaType: nil, requestItemId: "episode:tmdb:1:s1:e1", requestSeason: 1, requestEpisode: 1), "episode")
    }
}
