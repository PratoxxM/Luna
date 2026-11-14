import Foundation

public enum LunaCoreError: LocalizedError, Sendable {
    case invalidURL(String)
    case unauthorized
    case serverMessage(Int, String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Ugyldig serveradresse (\(path))."
        case .unauthorized:
            return "TV-paringen er utløpt eller trukket tilbake. Par på nytt i LunaCore Web."
        case .serverMessage(_, let msg):
            return msg
        case .decodingFailed(let detail):
            return "Kunne ikke tolke svar fra LunaCore (\(detail))."
        }
    }
}

private struct ServerErrorEnvelope: Decodable {
    let error: String?
}

public enum HomeConditionalResult: Sendable {
    case notModified
    case updated(payload: TvHomeResponse, etag: String?, rawPayloadData: Data)
}

public struct LunaCoreClient: Sendable {
    public let baseURL: URL
    public let deviceID: String
    public let deviceToken: String?
    public let roomName: String
    public let hardwareProfile: String
    public let allowSelfSignedLanTLS: Bool
    public let appVersion: String
    public let osVersion: String

    private let session: URLSession
    private let imageSession: URLSession

    public init(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool,
        appVersion: String = AppSessionStore.currentAppVersionString(),
        osVersion: String = ""
    ) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.deviceToken = deviceToken
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        self.allowSelfSignedLanTLS = allowSelfSignedLanTLS
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.session = LunaCoreSessionPool.shared.session(
            for: baseURL,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS
        )
        self.imageSession = LunaCoreSessionPool.shared.artworkSession(
            for: baseURL,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS
        )
    }

    public func resolveArtworkURL(_ rawPathOrURL: String?) -> URL? {
        guard let raw = rawPathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return buildAbsoluteURL(raw)
    }

    public func buildAbsoluteURL(_ pathOrURL: String) -> URL? {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            return URL(string: pathOrURL)
        }
        let cleanBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanRel = pathOrURL.hasPrefix("/") ? pathOrURL : "/\(pathOrURL)"
        return URL(string: "\(cleanBase)\(cleanRel)")
    }

    private var asciiSafeRoomHeader: String {
        if roomName.canBeConverted(to: .ascii) {
            return roomName
        }
        return roomName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "AppleTV"
    }

    public func streamHTTPHeaders() -> [String: String] {
        var headers: [String: String] = [
            "X-Device-Id": deviceID,
            "X-Room-Name": asciiSafeRoomHeader,
            "X-Hardware-Profile": hardwareProfile,
            "X-Luna-Version": appVersion,
        ]
        if !osVersion.isEmpty {
            headers["X-tvOS-Version"] = osVersion
        }
        if let deviceToken, !deviceToken.isEmpty {
            headers["Authorization"] = "Bearer \(deviceToken)"
        }
        return headers
    }

    public func isSameOrigin(_ url: URL) -> Bool {
        guard let targetScheme = url.scheme?.lowercased(),
              let baseScheme = baseURL.scheme?.lowercased(),
              targetScheme == baseScheme,
              let targetHost = url.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased(),
              targetHost == baseHost else {
            return false
        }
        let targetPort = url.port ?? (targetScheme == "https" ? 443 : 80)
        let basePort = baseURL.port ?? (baseScheme == "https" ? 443 : 80)
        return targetPort == basePort
    }

    public func fetchRawImageData(from url: URL) async throws -> (Data, HTTPURLResponse?) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("image/webp,image/*;q=0.9", forHTTPHeaderField: "Accept")
        let sameOrigin = isSameOrigin(url)
        if sameOrigin {
            req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
            if let deviceToken, !deviceToken.isEmpty {
                req.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            }
        }
        let targetSession = sameOrigin ? imageSession : LunaCoreSessionPool.shared.externalArtworkSession()
        let (data, resp) = try await targetSession.data(for: req)
        let http = resp as? HTTPURLResponse
        if let status = http?.statusCode, status >= 400 {
            throw LunaCoreError.serverMessage(status, "Bildehenting feilet (HTTP \(status))")
        }
        return (data, http)
    }

    // MARK: - Device Flow Pairing

    public func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String = AppSessionStore.currentAppVersionString()
    ) async throws -> TvPairingRequestResponse {
        struct Payload: Encodable {
            let deviceId: String
            let model: String
            let osVersion: String
            let appVersion: String
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/pair/request",
            body: Payload(deviceId: deviceID, model: model, osVersion: osVersion, appVersion: appVersion),
            includeAuth: false
        )
    }

    public func pollPairingCode(_ code: String) async throws -> (httpStatus: Int, response: TvPairingPollResponse) {
        let digits = code.filter(\.isNumber)
        guard let url = buildAbsoluteURL("/api/tv/v1/pair/poll/\(digits)") else {
            throw LunaCoreError.invalidURL("/api/tv/v1/pair/poll/\(digits)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")

        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        if let decoded = try? JSONDecoder().decode(TvPairingPollResponse.self, from: data) {
            return (status, decoded)
        }
        let fallbackStatus: String
        switch status {
        case 404, 410:
            fallbackStatus = "expired"
        case 429:
            fallbackStatus = "rate_limited"
        case 400:
            fallbackStatus = "invalid"
        default:
            fallbackStatus = "error"
        }
        let serverMsg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error
        return (
            status,
            TvPairingPollResponse(
                ok: false,
                status: fallbackStatus,
                deviceToken: nil,
                device: nil,
                error: serverMsg
            )
        )
    }

    // MARK: - Bootstrap, Conditional Home & Native Catalog

    public func fetchBootstrap() async throws -> TvBootstrapResponse {
        try await sendJSON(method: "GET", path: "/api/tv/v1/bootstrap")
    }

    public func updateDeviceProfile(
        roomName: String? = nil,
        hardwareProfile: String? = nil,
        overrides: TvDeviceOverrides? = nil
    ) async throws {
        struct BodyPayload: Encodable {
            let roomName: String?
            let hardwareProfile: String?
            let overrides: TvDeviceOverrides?
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "PATCH",
            path: "/api/tv/v1/device/profile",
            body: BodyPayload(roomName: roomName, hardwareProfile: hardwareProfile, overrides: overrides)
        )
    }

    public func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
        guard let url = buildAbsoluteURL("/api/tv/v1/home") else {
            throw LunaCoreError.invalidURL("/api/tv/v1/home")
        }
        var req = authorizedRequest(url: url, method: "GET")
        if let etag = ifNoneMatch?.trimmingCharacters(in: .whitespacesAndNewlines), !etag.isEmpty {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, rawResp) = try await session.data(for: req)
        let http = rawResp as? HTTPURLResponse
        let status = http?.statusCode ?? 500

        if status == 304 {
            return .notModified
        }
        if status == 401 {
            throw LunaCoreError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error ?? "HTTP \(status)"
            throw LunaCoreError.serverMessage(status, msg)
        }
        do {
            let decoded = try JSONDecoder().decode(TvHomeResponse.self, from: data)
            let responseEtag = http?.value(forHTTPHeaderField: "ETag")
            return .updated(payload: decoded, etag: responseEtag, rawPayloadData: data)
        } catch {
            throw LunaCoreError.decodingFailed(error.localizedDescription)
        }
    }

    public func fetchCatalog(
        kind: String,
        genre: String? = nil,
        sort: String = "popular",
        localOnly: Bool = false,
        unwatchedOnly: Bool = false,
        page: Int = 1,
        limit: Int = 24
    ) async throws -> TvCatalogResponse {
        let endpointKind = (kind == "series" || kind == "tv") ? "series" : "movies"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
        ]
        if let genre, !genre.isEmpty {
            items.append(URLQueryItem(name: "genre", value: genre))
        }
        if localOnly {
            items.append(URLQueryItem(name: "localOnly", value: "1"))
        }
        if unwatchedOnly {
            items.append(URLQueryItem(name: "unwatchedOnly", value: "1"))
        }
        let path = buildQueryPath("/api/tv/v1/catalog/\(endpointKind)", queryItems: items)
        return try await sendJSON(method: "GET", path: path)
    }

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

    public func fetchRow(pathOrRowId: String, offset: Int = 0, limit: Int = 24, sort: String? = nil) async throws -> TvRowPageResponse {
        let path = Self.buildRowRequestPath(
            pathOrRowId: pathOrRowId,
            offset: offset,
            limit: limit,
            sort: sort
        )
        return try await sendJSON(method: "GET", path: path)
    }

    internal static func buildRowRequestPath(
        pathOrRowId: String,
        offset: Int = 0,
        limit: Int = 24,
        sort: String? = nil
    ) -> String {
        let clampedOffset = max(0, offset)
        let clampedLimit = max(1, limit)

        if pathOrRowId.hasPrefix("/api/tv/v1/") {
            if var comps = URLComponents(string: pathOrRowId) {
                var items = comps.queryItems ?? []
                if comps.path.hasPrefix("/api/tv/v1/catalog/") {
                    let page = (clampedOffset / clampedLimit) + 1
                    items.removeAll { $0.name == "offset" || $0.name == "limit" || $0.name == "page" }
                    items.append(URLQueryItem(name: "page", value: String(page)))
                    items.append(URLQueryItem(name: "limit", value: String(clampedLimit)))
                } else {
                    items.removeAll { $0.name == "offset" || $0.name == "limit" }
                    items.append(URLQueryItem(name: "offset", value: String(clampedOffset)))
                    items.append(URLQueryItem(name: "limit", value: String(clampedLimit)))
                }
                if let sort, !sort.isEmpty, !items.contains(where: { $0.name == "sort" }) {
                    items.append(URLQueryItem(name: "sort", value: sort))
                }
                comps.queryItems = items
                if let built = comps.string {
                    return built
                }
            }
        }

        let encoded = pathOrRowId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathOrRowId
        var path = "/api/tv/v1/rows/\(encoded)?offset=\(clampedOffset)&limit=\(clampedLimit)"
        if let sort, !sort.isEmpty {
            let encodedSort = sort.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sort
            path += "&sort=\(encodedSort)"
        }
        return path
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
        struct ItemPayload: Encodable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
        }
        struct BodyPayload: Encodable {
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

    public func setFavorite(favorite: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {
        struct ItemPayload: Encodable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
        }
        struct BodyPayload: Encodable {
            let favorite: Bool
            let item: ItemPayload
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/favorite",
            body: BodyPayload(
                favorite: favorite,
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
        struct ItemPayload: Encodable {
            let kind: String
            let title: String
            let year: Int?
            let ids: TvMediaIds
            let season: Int?
            let episode: Int?
        }
        struct BodyPayload: Encodable {
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

    // MARK: - Pre-Resolve, Playback Resolve, Heartbeat & Source Switching

    public func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        startPositionSeconds: Double? = nil
    ) async throws -> TvPrepareResponse {
        struct PrepareBody: Encodable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/playback/prepare",
            body: PrepareBody(
                itemId: itemId,
                title: title,
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
        struct ResolveBody: Encodable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
            let candidateId: String?
            let prepareToken: String?
        }
        guard let url = buildAbsoluteURL("/api/tv/v1/playback/resolve") else {
            throw LunaCoreError.invalidURL("/api/tv/v1/playback/resolve")
        }
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONEncoder().encode(
            ResolveBody(
                itemId: itemId,
                title: title,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPositionSeconds,
                candidateId: candidateId,
                prepareToken: prepareToken
            )
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        if status == 401 {
            throw LunaCoreError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error ?? "HTTP \(status)"
            throw LunaCoreError.serverMessage(status, msg)
        }
        let decoded = try JSONDecoder().decode(TvResolveStartResponse.self, from: data)
        return (status, decoded)
    }

    public func fetchResolveSnapshot(resolveId: String) async throws -> TvResolveSocketEvent {
        let encoded = resolveId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolveId
        return try await sendJSON(method: "GET", path: "/api/tv/v1/playback/resolve/\(encoded)")
    }

    public func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double
    ) async throws -> TvHeartbeatResponse {
        struct HeartbeatBody: Encodable {
            let sessionId: String
            let state: String
            let positionSeconds: Double
            let durationSeconds: Double
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v1/playback/heartbeat",
            body: HeartbeatBody(
                sessionId: sessionId,
                state: state,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
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
        struct SwitchBody: Encodable {
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

    // MARK: - Internal Helpers

    private func buildQueryPath(_ basePath: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = basePath
        components.queryItems = queryItems
        return components.string ?? basePath
    }

    private func authorizedRequest(url: URL, method: String, includeAuth: Bool = true) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        req.setValue(asciiSafeRoomHeader, forHTTPHeaderField: "X-Room-Name")
        req.setValue(hardwareProfile, forHTTPHeaderField: "X-Hardware-Profile")
        req.setValue(appVersion, forHTTPHeaderField: "X-Luna-Version")
        if !osVersion.isEmpty {
            req.setValue(osVersion, forHTTPHeaderField: "X-tvOS-Version")
        }
        if includeAuth, let deviceToken, !deviceToken.isEmpty {
            req.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func sendJSON<Response: Decodable>(
        method: String,
        path: String,
        includeAuth: Bool = true
    ) async throws -> Response {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
        }
        let req = authorizedRequest(url: url, method: method, includeAuth: includeAuth)
        return try await executeAndDecode(req)
    }

    private func sendJSON<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body,
        includeAuth: Bool = true
    ) async throws -> Response {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
        }
        var req = authorizedRequest(url: url, method: method, includeAuth: includeAuth)
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await executeAndDecode(req)
    }

    private func executeAndDecode<Response: Decodable>(_ req: URLRequest) async throws -> Response {
        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        if status == 401 {
            throw LunaCoreError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error ?? "HTTP \(status)"
            throw LunaCoreError.serverMessage(status, msg)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LunaCoreError.decodingFailed(error.localizedDescription)
        }
    }
}
