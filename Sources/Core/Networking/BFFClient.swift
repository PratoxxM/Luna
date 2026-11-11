import Foundation

public enum BFFError: LocalizedError, Sendable {
    case invalidURL(String)
    case unauthorized
    case serverMessage(Int, String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Ugyldig serveradresse (\(path))."
        case .unauthorized:
            return "TV-paringen er utløpt eller trukket tilbake. Par på nytt i MediaOS Web."
        case .serverMessage(_, let msg):
            return msg
        case .decodingFailed(let detail):
            return "Kunne ikke tolke svar fra MediaOS (\(detail))."
        }
    }
}

private struct ServerErrorEnvelope: Decodable {
    let error: String?
}

public final class LanURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    public let trustedHost: String?
    public let allowSelfSignedTLS: Bool

    public init(trustedHost: String?, allowSelfSignedTLS: Bool) {
        self.trustedHost = trustedHost?.lowercased()
        self.allowSelfSignedTLS = allowSelfSignedTLS
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowSelfSignedTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()
        if host == trustedHost || host.hasSuffix(".local") {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

public struct BFFClient: Sendable {
    public let baseURL: URL
    public let deviceID: String
    public let deviceToken: String?
    public let roomName: String
    public let hardwareProfile: String
    public let allowSelfSignedLanTLS: Bool

    private let session: URLSession

    public init(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool
    ) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.deviceToken = deviceToken
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        self.allowSelfSignedLanTLS = allowSelfSignedLanTLS

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 90
        let delegate = LanURLSessionDelegate(
            trustedHost: baseURL.host,
            allowSelfSignedTLS: allowSelfSignedLanTLS
        )
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

    public func streamHTTPHeaders() -> [String: String] {
        var headers: [String: String] = [
            "X-Device-Id": deviceID,
            "X-Room-Name": roomName,
            "X-Hardware-Profile": hardwareProfile,
        ]
        if let deviceToken, !deviceToken.isEmpty {
            headers["Authorization"] = "Bearer \(deviceToken)"
        }
        return headers
    }

    // MARK: - Device Flow Pairing

    public func requestPairingCode(model: String, osVersion: String, appVersion: String = "1.0.0") async throws -> TvPairingRequestResponse {
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
            throw BFFError.invalidURL("/api/tv/v1/pair/poll/\(digits)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")

        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        let decoded = try JSONDecoder().decode(TvPairingPollResponse.self, from: data)
        return (status, decoded)
    }

    // MARK: - Catalog & Detail

    public func fetchBootstrap() async throws -> TvBootstrapResponse {
        try await sendJSON(method: "GET", path: "/api/tv/v1/bootstrap")
    }

    public func fetchHome() async throws -> TvHomeResponse {
        try await sendJSON(method: "GET", path: "/api/tv/v1/home")
    }

    public func fetchRow(pathOrRowId: String, offset: Int = 0, limit: Int = 24) async throws -> TvRowPageResponse {
        let path: String
        if pathOrRowId.hasPrefix("/api/tv/v1/") {
            let joiner = pathOrRowId.contains("?") ? "&" : "?"
            path = "\(pathOrRowId)\(joiner)offset=\(offset)&limit=\(limit)"
        } else {
            let encoded = pathOrRowId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathOrRowId
            path = "/api/tv/v1/rows/\(encoded)?offset=\(offset)&limit=\(limit)"
        }
        return try await sendJSON(method: "GET", path: path)
    }

    public func fetchItemDetail(mediaType: String, itemId: String) async throws -> TvItemDetail {
        let encodedId = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId
        let res: TvItemDetailResponse = try await sendJSON(
            method: "GET",
            path: "/api/tv/v1/items/\(mediaType)/\(encodedId)"
        )
        return res.item
    }

    public func fetchSeasonEpisodes(tmdbId: Int, seasonNumber: Int) async throws -> TvSeasonDetailResponse {
        try await sendJSON(
            method: "GET",
            path: "/api/tv/v1/items/series/\(tmdbId)/seasons/\(seasonNumber)"
        )
    }

    public func search(query: String) async throws -> [TvMediaCard] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let res: TvSearchResponse = try await sendJSON(
            method: "GET",
            path: "/api/tv/v1/search?q=\(encoded)"
        )
        return res.items
    }

    public func fetchWatchlist() async throws -> [TvMediaCard] {
        let res: TvWatchlistResponse = try await sendJSON(method: "GET", path: "/api/tv/v1/watchlist")
        return res.items
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

    public func setWatched(watched: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?, season: Int? = nil, episode: Int? = nil) async throws {
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

    // MARK: - Playback Resolve, Heartbeat & Source Switching

    public func resolvePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        candidateId: String?
    ) async throws -> (httpStatus: Int, response: TvResolveStartResponse) {
        struct ResolveBody: Encodable {
            let itemId: String
            let title: String
            let seriesTitle: String?
            let startPositionSeconds: Double?
            let candidateId: String?
        }
        guard let url = buildAbsoluteURL("/api/tv/v1/playback/resolve") else {
            throw BFFError.invalidURL("/api/tv/v1/playback/resolve")
        }
        var req = authorizedRequest(url: url, method: "POST")
        req.httpBody = try JSONEncoder().encode(
            ResolveBody(
                itemId: itemId,
                title: title,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPositionSeconds,
                candidateId: candidateId
            )
        )
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        if status == 401 {
            throw BFFError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error ?? "HTTP \(status)"
            throw BFFError.serverMessage(status, msg)
        }
        let decoded = try JSONDecoder().decode(TvResolveStartResponse.self, from: data)
        return (status, decoded)
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

    private func authorizedRequest(url: URL, method: String, includeAuth: Bool = true) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        req.setValue(roomName, forHTTPHeaderField: "X-Room-Name")
        req.setValue(hardwareProfile, forHTTPHeaderField: "X-Hardware-Profile")
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
            throw BFFError.invalidURL(path)
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
            throw BFFError.invalidURL(path)
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
            throw BFFError.unauthorized
        }
        if status >= 400 {
            let msg = (try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data))?.error ?? "HTTP \(status)"
            throw BFFError.serverMessage(status, msg)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BFFError.decodingFailed(error.localizedDescription)
        }
    }
}
