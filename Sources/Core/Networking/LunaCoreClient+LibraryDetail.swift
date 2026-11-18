import Foundation

extension LunaCoreClient {
    // MARK: - Library, Item Detail, Search & Mutations

    public func fetchLibrary(
        section: String = "all",
        tier: String = "all",
        mediaType: String = "all",
        sort: String = "recent",
        offset: Int = 0,
        limit: Int = 36
    ) async throws -> TvLibraryResponse {
        let items: [URLQueryItem] = [
            URLQueryItem(name: "section", value: section),
            URLQueryItem(name: "tier", value: tier),
            URLQueryItem(name: "mediaType", value: mediaType),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
        ]
        let path = buildQueryPath("/api/tv/v1/library", queryItems: items)
        return try await sendJSON(method: "GET", path: path)
    }

    public func fetchItemDetail(mediaType: String, itemId: String, seasonNumber: Int? = nil) async throws -> TvItemDetail {
        let encodedId = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        var path = "/api/tv/v1/items/\(mediaType)/\(encodedId)"
        if let seasonNumber, seasonNumber > 0 {
            path += "?season=\(seasonNumber)"
        }
        let res: TvItemDetailResponse = try await sendJSON(method: "GET", path: path)
        return res.item
    }

    public func fetchSeasonEpisodes(tmdbId: Int, seasonNumber: Int) async throws -> TvSeasonDetailResponse {
        try await sendJSON(
            method: "GET",
            path: "/api/tv/v1/items/series/\(tmdbId)/seasons/\(seasonNumber)"
        )
    }

    public func searchFull(query: String, limit: Int = 30) async throws -> TvSearchResponse {
        let items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
        ]
        let path = buildQueryPath("/api/tv/v1/search", queryItems: items)
        return try await sendJSON(method: "GET", path: path)
    }

    public func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {
        struct ItemPayload: Encodable, Sendable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
        }
        struct BodyPayload: Encodable, Sendable {
            let listed: Bool
            let item: ItemPayload
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/watchlist",
            body: BodyPayload(
                listed: listed,
                item: ItemPayload(kind: mediaType, title: title, year: year, ids: ids)
            )
        )
    }

    public func removeFromOngoing(mediaType: String, itemId: String? = nil, ids: TvMediaIds, title: String?) async throws {
        struct BodyPayload: Encodable, Sendable {
            let itemId: String?
            let mediaType: String
            let ids: TvMediaIds
            let title: String?
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/continue/remove",
            body: BodyPayload(itemId: itemId, mediaType: mediaType, ids: ids, title: title)
        )
    }

    public func removeFromList(rowId: String, mediaType: String, itemId: String? = nil, ids: TvMediaIds, title: String?) async throws {
        struct BodyPayload: Encodable, Sendable {
            let itemId: String?
            let mediaType: String
            let ids: TvMediaIds
            let title: String?
        }
        let cleanId = rowId.split(separator: "/").last.map(String.init) ?? rowId
        let encodedRowId = cleanId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanId
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/rows/\(encodedRowId)/remove",
            body: BodyPayload(itemId: itemId, mediaType: mediaType, ids: ids, title: title)
        )
    }

    public func deletePreflight(target: TvDeleteRequestTarget) async throws -> TvDeletePreflightResponse {
        struct BodyPayload: Encodable, Sendable {
            let itemId: String
            let mediaType: String
            let tmdbId: Int?
            let tvdbId: Int?
            let scope: String
            let season: Int?
            let episode: Int?
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/delete/preflight",
            body: BodyPayload(
                itemId: target.itemId,
                mediaType: target.kind,
                tmdbId: target.tmdbId,
                tvdbId: target.tvdbId,
                scope: target.scope.rawValue,
                season: target.season,
                episode: target.episode
            )
        )
    }

    public func executeDelete(
        target: TvDeleteRequestTarget,
        preflightId: String,
        removeFromLibrary: Bool = true
    ) async throws -> TvDeleteExecuteResponse {
        struct BodyPayload: Encodable, Sendable {
            let itemId: String
            let mediaType: String
            let tmdbId: Int?
            let tvdbId: Int?
            let scope: String
            let season: Int?
            let episode: Int?
            let preflightId: String
            let removeFromLibrary: Bool
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/delete",
            body: BodyPayload(
                itemId: target.itemId,
                mediaType: target.kind,
                tmdbId: target.tmdbId,
                tvdbId: target.tvdbId,
                scope: target.scope.rawValue,
                season: target.season,
                episode: target.episode,
                preflightId: preflightId,
                removeFromLibrary: removeFromLibrary
            )
        )
    }

    public func toggleMonitor(
        monitored: Bool? = nil,
        monitorMode: String? = nil,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        year: Int?
    ) async throws -> TvMonitorResponse {
        struct ItemPayload: Encodable, Sendable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
        }
        struct BodyPayload: Encodable, Sendable {
            let monitored: Bool?
            let monitorMode: String?
            let item: ItemPayload
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/monitor",
            body: BodyPayload(
                monitored: monitored,
                monitorMode: monitorMode,
                item: ItemPayload(kind: mediaType, title: title, year: year, ids: ids)
            )
        )
    }

    public func setWatched(
        watched: Bool,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        year: Int?,
        season: Int? = nil,
        episode: Int? = nil
    ) async throws {
        struct ItemPayload: Encodable, Sendable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
            let season: Int?
            let episode: Int?
        }
        struct BodyPayload: Encodable, Sendable {
            let watched: Bool
            let item: ItemPayload
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/watched",
            body: BodyPayload(
                watched: watched,
                item: ItemPayload(kind: mediaType, title: title, year: year, ids: ids, season: season, episode: episode)
            )
        )
    }
}
