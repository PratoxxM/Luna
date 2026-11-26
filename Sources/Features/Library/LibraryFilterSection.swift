import Foundation

public struct LibraryBrowseSnapshot: Sendable {
    public var payload: TvLibraryResponse
    public var localItems: [TvMediaCard]
    public var localOffset: Int
    public var localHasMore: Bool
    public var fetchedAt: Date
    public var refreshNonce: Int
    public var etag: String?

    public init(
        payload: TvLibraryResponse,
        localItems: [TvMediaCard],
        localOffset: Int,
        localHasMore: Bool,
        fetchedAt: Date,
        refreshNonce: Int,
        etag: String? = nil
    ) {
        self.payload = payload
        self.localItems = localItems
        self.localOffset = localOffset
        self.localHasMore = localHasMore
        self.fetchedAt = fetchedAt
        self.refreshNonce = refreshNonce
        self.etag = etag
    }
}

public enum LibraryBrowseMemoryCache {
    @MainActor
    public static let shared = BoundedLRUMemoryCache<LibraryBrowseSnapshot>(
        maxEntries: DeviceMemoryProfile.current.libraryCacheMaxEntries
    )
}

public enum LibraryFilterSection: String, CaseIterable, Identifiable, Sendable {
    case movies
    case series
    case watchlist
    case lists

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .watchlist: return "Huskeliste"
        case .lists: return LunaCopy.libraryListsSectionTitle
        }
    }

    public func pillTitle(counts: TvLibraryCounts?) -> String {
        switch self {
        case .lists:
            guard let count = countValue(from: counts) else { return label }
            return LunaCopy.listsPillTitle(count)
        case .movies, .series, .watchlist:
            return label
        }
    }

    public func pillBadgeText(counts: TvLibraryCounts?) -> String? {
        switch self {
        case .lists:
            return nil
        case .movies, .series, .watchlist:
            return countValue(from: counts).map(String.init)
        }
    }

    public var apiSection: String {
        switch self {
        case .movies, .series: return "local"
        case .watchlist: return "watchlist"
        case .lists: return "lists"
        }
    }

    public var apiMediaType: String {
        switch self {
        case .movies: return "movie"
        case .series: return "series"
        case .watchlist, .lists: return "all"
        }
    }

    public func countValue(from counts: TvLibraryCounts?) -> Int? {
        guard let counts else { return nil }
        switch self {
        case .movies: return counts.localMovies ?? 0
        case .series: return counts.localSeries ?? 0
        case .watchlist: return counts.watchlist
        case .lists: return counts.resolvedCustomListsCount
        }
    }

    public static func resolveInitialSection(
        counts: TvLibraryCounts?,
        didApplyInitialFallback: Bool,
        current: LibraryFilterSection
    ) -> (section: LibraryFilterSection, didApplyInitialFallback: Bool) {
        guard !didApplyInitialFallback, let counts else {
            return (current, didApplyInitialFallback)
        }
        if current == .movies, (counts.localMovies ?? 0) == 0, (counts.localSeries ?? 0) > 0 {
            return (.series, true)
        }
        return (current, true)
    }

    public var emptyHeadline: String {
        switch self {
        case .movies: return "Ingen lokale filmer"
        case .series: return "Ingen lokale serier"
        case .watchlist: return "Huskelisten venter"
        case .lists: return LunaCopy.emptyCustomListsHeadline
        }
    }

    public var emptyActionTitle: String? {
        switch self {
        case .series: return "Utforsk serier"
        case .movies, .watchlist: return "Utforsk filmer"
        case .lists: return nil
        }
    }

    public var emptyActionSymbol: String {
        switch self {
        case .series: return "tv"
        case .lists: return "list.bullet"
        case .movies, .watchlist: return "film"
        }
    }

    public var emptyTargetTab: MainNavigationTab {
        switch self {
        case .series: return .series
        case .movies, .watchlist, .lists: return .movies
        }
    }
}
