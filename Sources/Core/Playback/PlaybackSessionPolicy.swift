import Foundation

/// Pure playback completion, resume-target, media-type inference, and initial subtitle-delay
/// policies shared across `PlayerSessionController`, `PlayerTrackController`, and `PlayerRestoreController`.
public enum PlaybackSessionPolicy: Sendable {
    public static func inferredMediaType(
        sessionMediaType: String?,
        requestItemId: String?,
        requestSeason: Int?,
        requestEpisode: Int?
    ) -> String {
        if let mt = sessionMediaType?.trimmingCharacters(in: .whitespacesAndNewlines), !mt.isEmpty {
            return mt
        }
        if requestSeason != nil || requestEpisode != nil || (requestItemId?.hasPrefix("episode:") == true) {
            return "episode"
        }
        return "movie"
    }

    public static func isPlaybackCompleted(
        positionSeconds: Double,
        durationSeconds: Double,
        playbackEnded: Bool,
        chapters: [PlaybackChapter]
    ) -> Bool {
        if playbackEnded {
            return true
        }
        guard durationSeconds > 0, positionSeconds.isFinite, positionSeconds >= 0 else {
            return false
        }
        let inCredits = chapters.contains {
            ($0.kind == .credits || $0.kind == .postCredits) && positionSeconds >= $0.startSeconds
        }
        return inCredits && (positionSeconds / durationSeconds) >= 0.75
    }

    public static func resolvedInitialSubtitleDelayMs(
        candidateId: String?,
        sessionDelayMs: Int?,
        tracksDelayMs: Int?,
        preferenceStore: PlaybackPreferenceStore
    ) -> Int {
        if let candidateId, !candidateId.isEmpty,
           preferenceStore.hasStoredSubtitleDelay(forCandidateId: candidateId) {
            return preferenceStore.subtitleDelayMs(forCandidateId: candidateId)
        }
        return PlaybackSyncTimingPolicy.clampSubtitleDelayMs(sessionDelayMs ?? tracksDelayMs ?? 0)
    }

    public static func resolvedPostRestorePlayingIntent(
        defaultShouldPlay: Bool,
        userOverride: Bool?
    ) -> Bool {
        userOverride ?? defaultShouldPlay
    }
}
