import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LunaCoreClient {
    // MARK: - Pre-Resolve, Playback Resolve, Heartbeat & Source Switching

    public func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        startPositionSeconds: Double? = nil
    ) async throws -> TvPrepareResponse {
        struct PrepareBody: Encodable, Sendable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
        }
        let sanitizedTitle = EpisodeTitleFormatter.apiEpisodeTitle(
            rawTitle: title,
            seriesTitle: seriesTitle,
            itemId: itemId,
            season: nil,
            episode: nil
        )
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/playback/prepare",
            body: PrepareBody(
                itemId: itemId,
                title: sanitizedTitle,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPositionSeconds
            )
        )
    }

    public func resolvePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        candidateId: String?,
        prepareToken: String? = nil
    ) async throws -> (httpStatus: Int, response: TvResolveStartResponse) {
        struct ResolveBody: Encodable, Sendable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
            let candidateId: String?
            let prepareToken: String?
        }
        let sanitizedTitle = EpisodeTitleFormatter.apiEpisodeTitle(
            rawTitle: title,
            seriesTitle: seriesTitle,
            itemId: itemId,
            season: nil,
            episode: nil
        )
        return try await sendJSONWithStatus(
            method: "POST",
            path: "/api/tv/v1/playback/resolve",
            body: ResolveBody(
                itemId: itemId,
                title: sanitizedTitle,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPositionSeconds,
                candidateId: candidateId,
                prepareToken: prepareToken
            )
        )
    }

    public func fetchResolveSnapshot(resolveId: String) async throws -> TvResolveSocketEvent {
        let encoded = resolveId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolveId
        return try await sendJSON(method: "GET", path: "/api/tv/v1/playback/resolve/\(encoded)")
    }

    public func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool? = nil
    ) async throws -> TvHeartbeatResponse {
        struct HeartbeatBody: Encodable, Sendable {
            let sessionId: String
            let state: String
            let positionSeconds: Double
            let durationSeconds: Double
            let completed: Bool?
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/playback/heartbeat",
            body: HeartbeatBody(
                sessionId: sessionId,
                state: state,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                completed: completed
            )
        )
    }

    public func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        try await sendJSON(method: "GET", path: "/api/tv/v1/playback/\(sessionId)/alternatives")
    }

    public func switchCandidate(
        sessionId: String,
        candidateId: String,
        positionSeconds: Double
    ) async throws -> TvPlaybackSession {
        struct SwitchBody: Encodable, Sendable {
            let candidateId: String
            let positionSeconds: Double
        }
        let res: TvSwitchResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/playback/\(sessionId)/switch",
            body: SwitchBody(candidateId: candidateId, positionSeconds: positionSeconds)
        )
        return res.playbackSession
    }
}
