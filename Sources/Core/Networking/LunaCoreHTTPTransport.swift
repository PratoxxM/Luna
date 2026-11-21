import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

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

private struct ServerErrorEnvelope: Decodable, Sendable {
    let error: String?
}

public enum HomeConditionalResult: Sendable {
    case notModified
    case updated(payload: TvHomeResponse, etag: String?, rawPayloadData: Data)
}

internal enum ConditionalHTTPResult<Payload: Decodable & Sendable>: Sendable {
    case notModified
    case updated(payload: Payload, etag: String?, rawPayloadData: Data)
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
    private let externalImageSession: URLSession

    private static let sharedDecoder = Mutex(JSONDecoder())
    private static let sharedEncoder = Mutex(JSONEncoder())

    public init(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool,
        appVersion: String = SideloadSafeStorage.currentAppVersionString(),
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
        self.externalImageSession = LunaCoreSessionPool.shared.externalArtworkSession()
    }

    public init(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool,
        appVersion: String = SideloadSafeStorage.currentAppVersionString(),
        osVersion: String = "",
        session: URLSession,
        imageSession: URLSession? = nil,
        externalImageSession: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.deviceToken = deviceToken
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        self.allowSelfSignedLanTLS = allowSelfSignedLanTLS
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.session = session
        self.imageSession = imageSession ?? session
        self.externalImageSession = externalImageSession ?? session
    }

    // MARK: - Shared JSON Coding

    internal static func decodeJSON<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        try sharedDecoder.withLock { try $0.decode(type, from: data) }
    }

    internal static func decodeJSONAsync<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        if data.count < 4096 {
            return try decodeJSON(type, from: data)
        }
        return try await Task.detached(priority: .userInitiated) {
            try decodeJSON(type, from: data)
        }.value
    }

    internal static func encodeJSON<T: Encodable & Sendable>(_ value: T) throws -> Data {
        try sharedEncoder.withLock { try $0.encode(value) }
    }

    // MARK: - URL, Header & Same-Origin Helpers

    public enum ArtworkTargetWidth: Sendable {
        case preserve
        case poster2x
        case landscape2x
        case hero4K

        public var targetPixels: Int {
            switch self {
            case .preserve: return 0
            case .poster2x: return 780
            case .landscape2x: return 1280
            case .hero4K: return 3840
            }
        }

        public var tmdbSizeSegment: String {
            switch self {
            case .preserve: return ""
            case .poster2x: return "w780"
            case .landscape2x: return "w1280"
            case .hero4K: return "original"
            }
        }
    }

    public func resolveArtworkURL(
        _ rawPathOrURL: String?,
        target: ArtworkTargetWidth = .preserve
    ) -> URL? {
        guard let raw = rawPathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let baseResolved = (raw.hasPrefix("http://") || raw.hasPrefix("https://"))
            ? URL(string: raw)
            : buildAbsoluteURL(raw)
        guard let url = baseResolved, target != .preserve else {
            return baseResolved
        }
        return Self.upgradeArtworkURL(url, target: target)
    }

    private static func upgradeArtworkURL(_ url: URL, target: ArtworkTargetWidth) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var changed = false

        var segments = comps.path.components(separatedBy: "/")
        if let pIdx = segments.firstIndex(of: "p"),
           pIdx >= 1,
           segments[pIdx - 1] == "t",
           pIdx + 1 < segments.count {
            let sizeSegment = segments[pIdx + 1]
            if sizeSegment.hasPrefix("w"),
               let existingW = Int(sizeSegment.dropFirst()),
               existingW > 0,
               existingW < target.targetPixels {
                segments[pIdx + 1] = target.tmdbSizeSegment
                comps.path = segments.joined(separator: "/")
                changed = true
            }
        }

        if let queryItems = comps.queryItems, !queryItems.isEmpty {
            var updatedItems = queryItems
            var queryChanged = false
            for idx in updatedItems.indices {
                let lowerName = updatedItems[idx].name.lowercased()
                if (lowerName == "w" || lowerName == "width"),
                   let rawVal = updatedItems[idx].value,
                   let existingW = Int(rawVal),
                   existingW > 0,
                   existingW < target.targetPixels {
                    updatedItems[idx].value = String(target.targetPixels)
                    queryChanged = true
                }
            }
            if queryChanged {
                comps.queryItems = updatedItems
                changed = true
            }
        }

        return changed ? (comps.url ?? url) : url
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
            "X-Luna-Version": appVersion,
            "X-Supports-HW-AV1": DeviceHardwareCapabilities.supportsHardwareAV1 ? "1" : "0",
            "X-Physical-Memory-GB": String(DeviceHardwareCapabilities.physicalMemoryGB),
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
        let targetSession = sameOrigin ? imageSession : externalImageSession
        let (data, resp) = try await targetSession.data(for: req)
        let http = resp as? HTTPURLResponse
        if let status = http?.statusCode, status >= 400 {
            throw LunaCoreError.serverMessage(status, "Bildehenting feilet (HTTP \(status))")
        }
        return (data, http)
    }

    // MARK: - Transport Primitives & Unified Error / ETag Handling

    internal func buildQueryPath(_ basePath: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = basePath
        components.queryItems = queryItems
        return components.string ?? basePath
    }

    internal func authorizedRequest(url: URL, method: String, includeAuth: Bool = true) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        req.setValue(appVersion, forHTTPHeaderField: "X-Luna-Version")
        req.setValue(DeviceHardwareCapabilities.supportsHardwareAV1 ? "1" : "0", forHTTPHeaderField: "X-Supports-HW-AV1")
        req.setValue(String(DeviceHardwareCapabilities.physicalMemoryGB), forHTTPHeaderField: "X-Physical-Memory-GB")
        if !osVersion.isEmpty {
            req.setValue(osVersion, forHTTPHeaderField: "X-tvOS-Version")
        }
        if includeAuth, let deviceToken, !deviceToken.isEmpty {
            req.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    internal func extractServerErrorMessage(from data: Data) -> String? {
        (try? Self.decodeJSON(ServerErrorEnvelope.self, from: data))?.error
    }

    internal func validateHTTPStatus(_ status: Int, data: Data) throws {
        if status == 401 {
            throw LunaCoreError.unauthorized
        }
        if status >= 400 {
            let msg = extractServerErrorMessage(from: data) ?? "HTTP \(status)"
            throw LunaCoreError.serverMessage(status, msg)
        }
    }

    internal func executeRawGET(path: String, includeAuth: Bool = false) async throws -> (status: Int, data: Data) {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
        }
        let req = authorizedRequest(url: url, method: "GET", includeAuth: includeAuth)
        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        return (status, data)
    }

    internal func sendConditionalGET<Payload: Decodable & Sendable>(
        path: String,
        ifNoneMatch: String?
    ) async throws -> ConditionalHTTPResult<Payload> {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
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
        try validateHTTPStatus(status, data: data)
        do {
            let decoded = try await Self.decodeJSONAsync(Payload.self, from: data)
            let responseEtag = http?.value(forHTTPHeaderField: "ETag")
            return .updated(payload: decoded, etag: responseEtag, rawPayloadData: data)
        } catch {
            throw LunaCoreError.decodingFailed(error.localizedDescription)
        }
    }

    internal func sendJSON<Response: Decodable & Sendable>(
        method: String,
        path: String,
        includeAuth: Bool = true
    ) async throws -> Response {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
        }
        let req = authorizedRequest(url: url, method: method, includeAuth: includeAuth)
        return try await executeAndDecode(req).response
    }

    internal func sendJSON<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Body,
        includeAuth: Bool = true
    ) async throws -> Response {
        try await sendJSONWithStatus(method: method, path: path, body: body, includeAuth: includeAuth).response
    }

    internal func sendJSONWithStatus<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        path: String,
        body: Body,
        includeAuth: Bool = true
    ) async throws -> (httpStatus: Int, response: Response) {
        guard let url = buildAbsoluteURL(path) else {
            throw LunaCoreError.invalidURL(path)
        }
        var req = authorizedRequest(url: url, method: method, includeAuth: includeAuth)
        req.httpBody = try Self.encodeJSON(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await executeAndDecode(req)
    }

    private func executeAndDecode<Response: Decodable & Sendable>(
        _ req: URLRequest
    ) async throws -> (httpStatus: Int, response: Response) {
        let (data, rawResp) = try await session.data(for: req)
        let status = (rawResp as? HTTPURLResponse)?.statusCode ?? 500
        try validateHTTPStatus(status, data: data)
        do {
            let decoded = try await Self.decodeJSONAsync(Response.self, from: data)
            return (status, decoded)
        } catch {
            throw LunaCoreError.decodingFailed(error.localizedDescription)
        }
    }
}
