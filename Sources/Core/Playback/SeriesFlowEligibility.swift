import Foundation

/// Pure visibility, duration, and stinger-skip rules for series & movie continuity overlays,
/// tested natively on both Linux `LunaCore` and tvOS.
public enum SeriesFlowEligibility: Sendable {
    public static let maxNextEpisodeCreditsLeadSeconds: Double = 420.0
    public static let passiveCreditsDisplayCapSeconds: TimeInterval = 18.0
    public static let minPostCreditsTailSeconds: Double = 25.0

    public static func authoritativeStreamDurationSeconds(
        engineDurationSeconds: Double,
        declaredStreamDurationSeconds: Double?
    ) -> Double {
        if engineDurationSeconds > 0 {
            return engineDurationSeconds
        }
        if let declared = declaredStreamDurationSeconds, declared > 0 {
            return declared
        }
        return 0
    }

    public static func shouldShowNextEpisodePrompt(
        hasNextEpisode: Bool,
        isDismissedForCurrentSession: Bool,
        currentTime: Double,
        authoritativeDurationSeconds: Double,
        chapters: [PlaybackChapter]
    ) -> Bool {
        guard hasNextEpisode, !isDismissedForCurrentSession else {
            return false
        }
        guard authoritativeDurationSeconds > 90, currentTime > 30 else {
            return false
        }
        let remaining = authoritativeDurationSeconds - currentTime
        if remaining <= 30.0 && remaining >= -5.0 {
            return true
        }
        if remaining >= -5.0,
           remaining <= maxNextEpisodeCreditsLeadSeconds,
           currentTime >= authoritativeDurationSeconds * 0.5,
           chapters.contains(where: { $0.kind == .credits && currentTime >= $0.startSeconds && currentTime < $0.endSeconds }) {
            return true
        }
        return false
    }

    /// Returns the target timestamp (`seconds`) for a 1-click «Hopp til etter rulletekst» stinger jump
    /// whenever playback is currently inside a `.credits` chapter followed by either:
    /// 1. An explicit `.postCredits` chapter starting after the credits begin, or
    /// 2. At least `minPostCreditsTailSeconds` (`25 s`) of remaining content after the credits end.
    public static func postCreditsSkipTargetSeconds(
        currentTime: Double,
        authoritativeDurationSeconds: Double,
        chapters: [PlaybackChapter]
    ) -> Double? {
        guard authoritativeDurationSeconds.isFinite, authoritativeDurationSeconds > 0, currentTime.isFinite, currentTime >= 0 else {
            return nil
        }
        guard let activeCredits = chapters.first(where: {
            $0.kind == .credits && currentTime >= $0.startSeconds && currentTime < ($0.endSeconds - 1.5)
        }) else {
            return nil
        }

        if chapters.contains(where: {
            $0.kind == .postCredits && currentTime >= $0.startSeconds && currentTime < $0.endSeconds
        }) {
            return nil
        }

        if let stinger = chapters
            .filter({
                $0.kind == .postCredits &&
                    $0.startSeconds > currentTime &&
                    $0.startSeconds >= activeCredits.startSeconds &&
                    $0.startSeconds < authoritativeDurationSeconds
            })
            .min(by: { $0.startSeconds < $1.startSeconds }) {
            return stinger.startSeconds
        }

        if (authoritativeDurationSeconds - activeCredits.endSeconds) >= minPostCreditsTailSeconds {
            return activeCredits.endSeconds
        }

        return nil
    }

    public static func initialResumeBannerSeconds(
        sessionId: String?,
        streamStartPositionSeconds: Double?,
        requestStartPositionSeconds: Double?,
        shownForSessionID: String?
    ) -> Double? {
        guard let sid = sessionId, !sid.isEmpty, shownForSessionID != sid else {
            return nil
        }
        let startPos = streamStartPositionSeconds ?? requestStartPositionSeconds ?? 0
        return startPos > 15.0 ? startPos : nil
    }
}
