import Foundation
import Testing
@testable import LunaCore

@Suite("M3 Original Language, Preferences, Subtitle Sync & DV Fallback")
struct PlayerLanguageAndPreferenceTests {
    @Test("OriginalLanguageTrackSelector picks lossless original audio over dubbed tracks and excludes commentary")
    func originalLanguageAudioRankingAndCommentaryExclusion() {
        let tracks = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Norsk 5.1", codec: "eac3", language: "nob", channels: 6, isDefault: true),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese Commentary", codec: "truehd", language: "ja", channels: 2, isCommentary: true),
            PlaybackAudioTrackDescriptor(id: 2, name: "Japanese AAC", codec: "aac", language: "jpn", channels: 2),
            PlaybackAudioTrackDescriptor(id: 3, name: "Japanese TrueHD Atmos", codec: "truehd", language: "ja-JP", channels: 8, isAtmos: true),
            PlaybackAudioTrackDescriptor(id: 4, name: "English DTS-HD MA", codec: "dts-hd", language: "eng", channels: 8),
        ]

        #expect(OriginalLanguageTrackSelector.containsNorwegianTrack(in: tracks))

        let pickedOriginal = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: tracks,
            originalLanguage: "ja",
            preferNorwegianAudio: false
        )
        #expect(pickedOriginal?.id == 3)

        let pickedNorwegian = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: tracks,
            originalLanguage: "ja",
            preferNorwegianAudio: true
        )
        #expect(pickedNorwegian?.id == 0)

        let fallbackHighestQuality = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: tracks,
            originalLanguage: "ko",
            preferNorwegianAudio: false
        )
        #expect(fallbackHighestQuality?.id == 3)

        let subs = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
            SmartTrackDescriptor(id: 12, name: "English", codec: "srt", language: "eng"),
        ]
        #expect(SmartTrackRuleEngine.evaluate(activeAudio: pickedOriginal?.asSmartDescriptor, subtitleTracks: subs) == .selectTrack(10))
        #expect(SmartTrackRuleEngine.evaluate(activeAudio: pickedNorwegian?.asSmartDescriptor, subtitleTracks: subs) == .selectTrack(11))

        #expect(
            OriginalLanguageTrackSelector.preferredAudioLanguageCodes(forOriginalLanguage: "ja", preferNorwegianAudio: false)
                == ["jpn", "ja", "eng"]
        )
        #expect(
            OriginalLanguageTrackSelector.preferredAudioLanguageCodes(forOriginalLanguage: "ja", preferNorwegianAudio: true)
                == ["nob", "nor", "no", "nb", "eng"]
        )
    }

    @Test("OriginalLanguageTrackSelector handles commentary-only fallback and DTS:X > EAC3 ranking")
    func dtsXAndCommentaryOnlyFallback() {
        let mixed = [
            PlaybackAudioTrackDescriptor(id: 1, name: "English EAC3", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 2, name: "English DTS:X", codec: "dts", language: "eng", channels: 8, isDTSX: true),
        ]
        #expect(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: mixed, originalLanguage: "en")?.id == 2)

        let eac3VsDts = [
            PlaybackAudioTrackDescriptor(id: 10, name: "English DTS", codec: "dts", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 11, name: "English E-AC-3", codec: "eac-3", language: "eng", channels: 6),
        ]
        #expect(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: eac3VsDts, originalLanguage: "en")?.id == 11)

        let commentaryOnly = [
            PlaybackAudioTrackDescriptor(id: 7, name: "Director Commentary", codec: "aac", language: "eng", channels: 2, isCommentary: true),
        ]
        #expect(!OriginalLanguageTrackSelector.containsNorwegianTrack(in: commentaryOnly))
        #expect(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: commentaryOnly, originalLanguage: "eng")?.id == 7)
        #expect(OriginalLanguageTrackSelector.selectPreferredAudioTrack(in: [], originalLanguage: "eng") == nil)
    }

    @Test("PlaybackPreferenceStore persists per-title Norsk tale and clamped per-candidate subtitleDelayMs under luna.v1.*")
    func playbackPreferenceStorePersistenceAndClamping() {
        let suite = "luna.v1.test.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SideloadSafeStorage.preferNorwegianAudioPrefix.hasPrefix("luna.v1."))
        #expect(SideloadSafeStorage.candidateSubtitleDelayPrefix.hasPrefix("luna.v1."))

        let store = PlaybackPreferenceStore(defaults: defaults)
        #expect(!store.preferNorwegianAudio(forItemId: "movie:tmdb:129"))
        store.setPreferNorwegianAudio(true, forItemId: "movie:tmdb:129")
        #expect(store.preferNorwegianAudio(forItemId: "movie:tmdb:129"))
        #expect(!store.preferNorwegianAudio(forItemId: "movie:tmdb:999"))
        store.setPreferNorwegianAudio(false, forItemId: "movie:tmdb:129")
        #expect(!store.preferNorwegianAudio(forItemId: "movie:tmdb:129"))

        #expect(!store.hasStoredSubtitleDelay(forCandidateId: "cand-a"))
        #expect(store.subtitleDelayMs(forCandidateId: "cand-a") == 0)

        store.setSubtitleDelayMs(15_000, forCandidateId: "cand-a")
        #expect(store.hasStoredSubtitleDelay(forCandidateId: "cand-a"))
        #expect(store.subtitleDelayMs(forCandidateId: "cand-a") == 10_000)

        store.setSubtitleDelayMs(-9_000, forCandidateId: "cand-b")
        #expect(store.subtitleDelayMs(forCandidateId: "cand-b") == -5_000)

        // Explicit 0 reset remains stored so server session defaults do not overwrite user zeroing
        store.setSubtitleDelayMs(0, forCandidateId: "cand-a")
        #expect(store.hasStoredSubtitleDelay(forCandidateId: "cand-a"))
        #expect(store.subtitleDelayMs(forCandidateId: "cand-a") == 0)

        let resolvedFromStore = PlaybackSessionPolicy.resolvedInitialSubtitleDelayMs(
            candidateId: "cand-a",
            sessionDelayMs: 350,
            tracksDelayMs: 350,
            preferenceStore: store
        )
        #expect(resolvedFromStore == 0)

        let resolvedFromServer = PlaybackSessionPolicy.resolvedInitialSubtitleDelayMs(
            candidateId: "cand-unseen",
            sessionDelayMs: 250,
            tracksDelayMs: nil,
            preferenceStore: store
        )
        #expect(resolvedFromServer == 250)
    }

    @Test("DolbyVisionFallbackPolicy triggers only on sustained P7 FEL frame drops and resets cleanly")
    func dolbyVisionFallbackPolicyTransitions() {
        var policy = DolbyVisionFallbackPolicy()

        // Non-P7-FEL never triggers
        let nonP7 = policy.recordTelemetrySample(droppedFrames: 50, isProfile7FEL: false, isBaseLayerForced: false)
        #expect(!nonP7)

        // First P7 FEL sample below absolute threshold establishes baseline
        let baseline = policy.recordTelemetrySample(droppedFrames: 4, isProfile7FEL: true, isBaseLayerForced: false)
        #expect(!baseline)
        // Delta = 10 < 15 -> stays false
        let lowDelta = policy.recordTelemetrySample(droppedFrames: 14, isProfile7FEL: true, isBaseLayerForced: false)
        #expect(!lowDelta)
        // Delta = 16 >= 15 -> triggers
        let triggered = policy.recordTelemetrySample(droppedFrames: 20, isProfile7FEL: true, isBaseLayerForced: false)
        #expect(triggered)
        #expect(policy.shouldSuggestBaseLayer)

        // Forced base layer clears suggestion
        let forcedBaseLayer = policy.recordTelemetrySample(droppedFrames: 45, isProfile7FEL: true, isBaseLayerForced: true)
        #expect(!forcedBaseLayer)
        #expect(!policy.shouldSuggestBaseLayer)

        // Single high absolute sample triggers immediately
        let highAbsolute = policy.recordTelemetrySample(droppedFrames: 28, isProfile7FEL: true, isBaseLayerForced: false)
        #expect(highAbsolute)
        policy.reset()
        #expect(!policy.shouldSuggestBaseLayer)
    }

    @Test("PlaybackSubtitleSyncActionPolicy & PlaybackSessionPolicy helpers handle subtitle merge and completion")
    func subtitleSyncActionAndSessionPolicies() {
        #expect(PlaybackSubtitleSyncActionPolicy.preferredSearchLanguages(originalLanguage: "ja") == ["nob", "nor", "no", "eng", "jpn"])
        #expect(PlaybackSubtitleSyncActionPolicy.preferredSearchLanguages(originalLanguage: "nob") == ["nob", "nor", "no", "eng"])

        let extOld = TvExternalSubtitle(id: "sub-1", url: "/sub/1.srt", language: "eng", name: "English")
        let extNew = TvExternalSubtitle(id: "sub-2", url: "/sub/2.srt", language: "nob", name: "Norsk", isDefault: true)
        let attachRes = TvSubtitleSearchAttachResponse(
            sessionId: "sess-1",
            attached: true,
            status: "attached",
            subtitle: extNew,
            externalSubtitles: [extNew]
        )
        let merged = PlaybackSubtitleSyncActionPolicy.mergedExternalSubtitles(existing: [extOld], response: attachRes)
        #expect(merged.count == 2)
        #expect(merged.last?.id == "sub-2")

        let matched = PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(
            for: SmartTrackDescriptor(id: 5, name: "Norsk", codec: "srt", language: "nob", isExternal: true),
            in: merged
        )
        #expect(matched?.id == "sub-2")

        let chapters = [
            PlaybackChapter(id: "c1", index: 0, title: "Rulletekst", startSeconds: 5000, endSeconds: 5300, kind: .credits),
        ]
        #expect(PlaybackSessionPolicy.isPlaybackCompleted(positionSeconds: 5100, durationSeconds: 5400, playbackEnded: false, chapters: chapters))
        #expect(!PlaybackSessionPolicy.isPlaybackCompleted(positionSeconds: 1000, durationSeconds: 5400, playbackEnded: false, chapters: chapters))
        #expect(PlaybackSessionPolicy.inferredMediaType(sessionMediaType: nil, requestItemId: "episode:tmdb:1:s1:e1", requestSeason: 1, requestEpisode: 1) == "episode")
    }
}
