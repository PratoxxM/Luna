import Foundation

public protocol CardMutatingClient: Sendable {
    func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws
    func setWatched(
        watched: Bool,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        year: Int?,
        season: Int?,
        episode: Int?
    ) async throws
    func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws
    @discardableResult
    func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool
}

public protocol HomeClientProviding: CardMutatingClient {
    func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult
    func fetchCatalog(
        kind: String,
        genre: String?,
        sort: String,
        localOnly: Bool,
        unwatchedOnly: Bool,
        page: Int,
        limit: Int
    ) async throws -> TvCatalogResponse
}

public protocol CatalogClientProviding: CardMutatingClient {
    func fetchCatalogConditional(
        kind: String,
        genre: String?,
        sort: String,
        localOnly: Bool,
        unwatchedOnly: Bool,
        page: Int,
        limit: Int,
        ifNoneMatch: String?
    ) async throws -> ConditionalHTTPResult<TvCatalogResponse>
}

public protocol LibraryClientProviding: CardMutatingClient {
    func fetchLibrary(
        section: String,
        tier: String,
        mediaType: String,
        sort: String,
        offset: Int,
        limit: Int,
        ifNoneMatch: String?
    ) async throws -> ConditionalHTTPResult<TvLibraryResponse>
}

public protocol SearchClientProviding: CardMutatingClient {
    func searchFull(query: String, limit: Int) async throws -> TvSearchResponse
}

public protocol PairingClientProviding: Sendable {
    func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String,
        capabilities: TvDeviceCapabilities
    ) async throws -> TvPairingRequestResponse
    func pollPairingCode(_ code: String) async throws -> (httpStatus: Int, response: TvPairingPollResponse)
}

extension LunaCoreClient: HomeClientProviding, CatalogClientProviding, LibraryClientProviding, SearchClientProviding, PairingClientProviding {}

@MainActor
public protocol TabSessionContext: AnyObject {
    var serverBaseURL: URL? { get }
    var roomName: String { get }
    var hardwareProfile: String { get }
    var homeRefreshNonce: Int { get }
    var hasActivePlayback: Bool { get }
    func makeHomeClient() -> (any HomeClientProviding)?
    func makeCatalogClient() -> (any CatalogClientProviding)?
    func makeLibraryClient() -> (any LibraryClientProviding)?
    func makeSearchClient() -> (any SearchClientProviding)?
    func notifyContentMutated()
    func unpairDevice()
    func probeAndFailoverServerURLIfNeeded() async -> Bool
}

public extension TabSessionContext {
    func probeAndFailoverServerURLIfNeeded() async -> Bool { false }
}

@MainActor
public protocol SearchSessionContext: TabSessionContext {
    func loadRecentSearches() -> [String]
    @discardableResult
    func recordRecentSearch(_ term: String) -> [String]
    func clearRecentSearches()
}

@MainActor
public protocol ServerDiscoveryProviding: AnyObject {
    var servers: [DiscoveredLunaCoreServer] { get }
    var isSearching: Bool { get }
    func start()
    func stop()
}

public struct PairingDeviceMetadata: Sendable, Equatable {
    public let model: String
    public let osVersion: String
    public let appVersion: String

    public init(model: String, osVersion: String, appVersion: String) {
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
}

@MainActor
public protocol PairingSessionContext: AnyObject {
    var deviceMetadata: PairingDeviceMetadata { get }
    func makePairingClient(baseURL: URL) -> (any PairingClientProviding)?
    func completePairing(
        baseURL: URL,
        token: String,
        pairedDevice: TvPairedDeviceInfo,
        localHostnameURL: URL?
    )
}
