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
        startPositionSeconds: Double? = nil,
        prepareToken: String? = nil
    ) async throws -> TvPrepareResponse {
        struct PrepareBody: Encodable, Sendable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
            let prepareToken: String?
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
            path: "/api/tv/v2/playback/prepare",
            body: PrepareBody(
                itemId: itemId,
                title: sanitizedTitle,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPositionSeconds,
                prepareToken: prepareToken
            )
        )
    }

    public func cancelInflightPlayback(
        sessionId: String? = nil,
        resolveId: String? = nil,
        itemId: String? = nil,
        prepareToken: String? = nil
    ) async throws {
        struct CancelInflightBody: Encodable, Sendable {
            let sessionId: String?
            let resolveId: String?
            let itemId: String?
            let prepareToken: String?
            let state: String
            let cancelInflight: Bool
            let positionSeconds: Double
            let durationSeconds: Double
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/playback/heartbeat",
            body: CancelInflightBody(
                sessionId: sessionId,
                resolveId: resolveId,
                itemId: itemId,
                prepareToken: prepareToken,
                state: "stopped",
                cancelInflight: true,
                positionSeconds: 0,
                durationSeconds: 0
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
            path: "/api/tv/v2/playback/resolve",
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
        return try await sendJSON(method: "GET", path: "/api/tv/v2/playback/resolve/\(encoded)")
    }

    public func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool? = nil
    ) async throws -> TvHeartbeatResponse {
        try await sendHeartbeat(
            sessionId: sessionId,
            state: state,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            completed: completed,
            subtitleDelayMs: nil,
            qos: nil
        )
    }

    public func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool? = nil,
        subtitleDelayMs: Int? = nil,
        qos: TvPlaybackQosPayload? = nil
    ) async throws -> TvHeartbeatResponse {
        struct HeartbeatBody: Encodable, Sendable {
            let sessionId: String
            let state: String
            let positionSeconds: Double
            let durationSeconds: Double
            let completed: Bool?
            let subtitleDelayMs: Int?
            let qos: TvPlaybackQosPayload?
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/playback/heartbeat",
            body: HeartbeatBody(
                sessionId: sessionId,
                state: state,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                completed: completed,
                subtitleDelayMs: subtitleDelayMs,
                qos: qos
            )
        )
    }

    public func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        return try await sendJSON(method: "GET", path: "/api/tv/v2/playback/\(encoded)/alternatives")
    }

    public func fetchItemCandidates(
        itemId: String,
        title: String,
        seriesTitle: String? = nil
    ) async throws -> TvAlternativesResponse {
        struct CandidatesBody: Encodable, Sendable {
            let itemId: String
            let title: String
            let seriesTitle: String?
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
            path: "/api/tv/v2/playback/candidates",
            body: CandidatesBody(
                itemId: itemId,
                title: sanitizedTitle,
                seriesTitle: seriesTitle
            )
        )
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
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        let res: TvSwitchResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/playback/\(encoded)/switch",
            body: SwitchBody(candidateId: candidateId, positionSeconds: positionSeconds)
        )
        return res.playbackSession
    }

    public func searchAndAttachSubtitles(
        sessionId: String,
        languages: [String] = ["nob", "nor", "no"],
        forced: Bool? = nil,
        cleanSdh: Bool? = nil
    ) async throws -> TvSubtitleSearchAttachResponse {
        struct SearchAttachBody: Encodable, Sendable {
            let languages: [String]
            let forced: Bool?
            let cleanSdh: Bool?
        }
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/playback/\(encoded)/subtitles/search-and-attach",
            body: SearchAttachBody(languages: languages, forced: forced, cleanSdh: cleanSdh)
        )
    }

    public func autoAlignSubtitles(
        sessionId: String,
        subtitleId: String? = nil,
        trackIndex: Int? = nil,
        language: String? = nil,
        subtitleDelayMs: Int? = nil,
        applyToFile: Bool? = nil
    ) async throws -> TvSubtitleAutoAlignResponse {
        struct AutoAlignBody: Encodable, Sendable {
            let subtitleId: String?
            let trackIndex: Int?
            let language: String?
            let subtitleDelayMs: Int?
            let applyToFile: Bool?
        }
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/playback/\(encoded)/subtitles/auto-align",
            body: AutoAlignBody(
                subtitleId: subtitleId,
                trackIndex: trackIndex,
                language: language,
                subtitleDelayMs: subtitleDelayMs,
                applyToFile: applyToFile
            )
        )
    }
}
