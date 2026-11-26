import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LunaCoreClient {
    // MARK: - Device Flow Pairing

    public func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String = SideloadSafeStorage.currentAppVersionString(),
        capabilities: TvDeviceCapabilities = DeviceHardwareCapabilities.asTvCapabilities
    ) async throws -> TvPairingRequestResponse {
        struct Payload: Encodable, Sendable {
            let deviceId: String
            let model: String
            let osVersion: String
            let appVersion: String
            let capabilities: TvDeviceCapabilities
        }
        return try await sendJSON(
            method: "POST",
            path: "/api/tv/v2/pair/request",
            body: Payload(
                deviceId: deviceID,
                model: model,
                osVersion: osVersion,
                appVersion: appVersion,
                capabilities: capabilities
            ),
            includeAuth: false
        )
    }

    public func pollPairingCode(_ code: String) async throws -> (httpStatus: Int, response: TvPairingPollResponse) {
        let digits = code.filter(\.isNumber)
        let (status, data) = try await executeRawGET(path: "/api/tv/v2/pair/poll/\(digits)", includeAuth: false)
        if let decoded = try? Self.decodeJSON(TvPairingPollResponse.self, from: data) {
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
        return (
            status,
            TvPairingPollResponse(
                ok: false,
                status: fallbackStatus,
                deviceToken: nil,
                device: nil,
                error: extractServerErrorMessage(from: data)
            )
        )
    }

    // MARK: - Bootstrap, Conditional Home & Native Catalog

    public func fetchBootstrap() async throws -> TvBootstrapResponse {
        try await sendJSON(method: "GET", path: "/api/tv/v2/bootstrap")
    }

    public func updateDeviceProfile(
        roomName: String? = nil,
        hardwareProfile: String? = nil,
        overrides: TvDeviceOverrides? = nil,
        capabilities: TvDeviceCapabilities? = nil
    ) async throws {
        struct BodyPayload: Encodable, Sendable {
            let roomName: String?
            let hardwareProfile: String?
            let overrides: TvDeviceOverrides?
            let capabilities: TvDeviceCapabilities?
        }
        let _: TvMutationAckResponse = try await sendJSON(
            method: "PATCH",
            path: "/api/tv/v2/device/profile",
            body: BodyPayload(
                roomName: roomName,
                hardwareProfile: hardwareProfile,
                overrides: overrides,
                capabilities: capabilities
            )
        )
    }

    public func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
        try await sendConditionalGET(path: "/api/tv/v2/home", ifNoneMatch: ifNoneMatch)
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
        let path = Self.buildCatalogRequestPath(
            kind: kind,
            genre: genre,
            sort: sort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            page: page,
            limit: limit
        )
        return try await sendJSON(method: "GET", path: path)
    }

    public func fetchCatalogConditional(
        kind: String,
        genre: String? = nil,
        sort: String = "popular",
        localOnly: Bool = false,
        unwatchedOnly: Bool = false,
        page: Int = 1,
        limit: Int = 24,
        ifNoneMatch: String? = nil
    ) async throws -> ConditionalHTTPResult<TvCatalogResponse> {
        let path = Self.buildCatalogRequestPath(
            kind: kind,
            genre: genre,
            sort: sort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            page: page,
            limit: limit
        )
        return try await sendConditionalGET(path: path, ifNoneMatch: ifNoneMatch)
    }

    private static func buildCatalogRequestPath(
        kind: String,
        genre: String?,
        sort: String,
        localOnly: Bool,
        unwatchedOnly: Bool,
        page: Int,
        limit: Int
    ) -> String {
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
        let query = items.compactMap { item -> String? in
            guard let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let val = item.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return nil
            }
            return "\(name)=\(val)"
        }.joined(separator: "&")
        return query.isEmpty ? "/api/tv/v2/catalog/\(endpointKind)" : "/api/tv/v2/catalog/\(endpointKind)?\(query)"
    }

    public func fetchRow(
        pathOrRowId: String,
        offset: Int = 0,
        limit: Int = 24,
        sort: String? = nil
    ) async throws -> TvRowPageResponse {
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

        let normalizedPathOrRowId = pathOrRowId.hasPrefix("/api/tv/v1/")
            ? "/api/tv/v2/" + pathOrRowId.dropFirst("/api/tv/v1/".count)
            : pathOrRowId

        if normalizedPathOrRowId.hasPrefix("/api/tv/v2/") {
            if var comps = URLComponents(string: normalizedPathOrRowId) {
                var items = comps.queryItems ?? []
                if comps.path.hasPrefix("/api/tv/v2/catalog/") {
                    let pageIndex = clampedOffset / clampedLimit
                    let page = pageIndex < Int.max ? pageIndex + 1 : Int.max
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

        let encoded = normalizedPathOrRowId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedPathOrRowId
        var path = "/api/tv/v2/rows/\(encoded)?offset=\(clampedOffset)&limit=\(clampedLimit)"
        if let sort, !sort.isEmpty {
            let encodedSort = sort.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sort
            path += "&sort=\(encodedSort)"
        }
        return path
    }
}
