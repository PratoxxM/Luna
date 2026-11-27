import Foundation

/// Pure-Swift trickplay fallback policy for server-extracted scrub frames
/// (`GET /api/tv/v2/playback/:sessionId/scrub-frame?t=<seconds>`).
///
/// Used when `AetherEngine` local scrub previews are unavailable (VFS, Easynews,
/// DV Profile 7 FEL `.softwareHost`, or 4 GB devices), while protecting archive
/// storage from spindown.
public enum PlaybackTrickplayPolicy: Sendable {
    public static let defaultBucketSeconds: Int = 5
    public static let maxSessionCacheFrames: Int = 40
    public static let httpDebounceNanoseconds: UInt64 = 90_000_000

    public static func quantizedBucketSeconds(
        for rawSeconds: Double,
        durationSeconds: Double,
        bucketSeconds: Int = defaultBucketSeconds
    ) -> Int? {
        guard rawSeconds.isFinite, rawSeconds >= 0, bucketSeconds > 0 else {
            return nil
        }
        let clamped: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            clamped = min(rawSeconds, max(0, durationSeconds - 0.5))
        } else {
            clamped = rawSeconds
        }
        let step = Double(bucketSeconds)
        guard let bucketIndex = Int(exactly: (clamped / step).rounded(.down)) else {
            return nil
        }
        let multiplied = bucketIndex.multipliedReportingOverflow(by: bucketSeconds)
        guard !multiplied.overflow else {
            return nil
        }
        return max(0, multiplied.partialValue)
    }

    public static func shouldAttemptServerTrickplay(session: TvPlaybackSession?) -> Bool {
        guard let session,
              !session.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let tier = (session.selectedCandidate.tier ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let source = session.selectedCandidate.source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if source == "infinidysk" || source == "easynews" || tier == "vfs" {
            return true
        }
        if tier == "archive" || source == "archive" {
            return false
        }
        return true
    }

    public static func shouldDisableTrickplayForSession(statusCode: Int, errorCode: String?) -> Bool {
        if statusCode == 403 || statusCode == 410 {
            return true
        }
        if statusCode == 404 {
            let normalized = (errorCode ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return [
                "archive_spindown_protected",
                "restricted_symlink_target",
                "scrub_source_unavailable",
                "session_not_found",
            ].contains(normalized)
        }
        return false
    }

    public static func buildScrubFramePath(sessionId: String, bucketSeconds: Int) -> String {
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        return "/api/tv/v2/playback/\(encoded)/scrub-frame?t=\(max(0, bucketSeconds))"
    }
}
