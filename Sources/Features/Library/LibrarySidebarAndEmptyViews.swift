import SwiftUI

internal struct LibraryBrowseSnapshot {
    var payload: TvLibraryResponse
    var localItems: [TvMediaCard]
    var localOffset: Int
    var localHasMore: Bool
    var fetchedAt: Date
    var refreshNonce: Int
}

internal enum LibraryBrowseMemoryCache {
    @MainActor
    static let shared = BoundedLRUMemoryCache<LibraryBrowseSnapshot>(
        maxEntries: DeviceMemoryProfile.current.libraryCacheMaxEntries
    )
}

public enum LibraryFilterSection: String, CaseIterable, Identifiable, Sendable {
    case movies
    case series
    case watchlist

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .watchlist: return "Huskeliste"
        }
    }

    public var apiSection: String {
        switch self {
        case .movies, .series: return "local"
        case .watchlist: return "watchlist"
        }
    }

    public var apiMediaType: String {
        switch self {
        case .movies: return "movie"
        case .series: return "series"
        case .watchlist: return "all"
        }
    }

    public func countValue(from counts: TvLibraryCounts?) -> Int? {
        guard let counts else { return nil }
        switch self {
        case .movies: return counts.localMovies ?? 0
        case .series: return counts.localSeries ?? 0
        case .watchlist: return counts.watchlist
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
        }
    }

    public var emptyActionTitle: String {
        switch self {
        case .series: return "Utforsk serier"
        case .movies, .watchlist: return "Utforsk filmer"
        }
    }

    public var emptyTargetTab: MainNavigationTab {
        switch self {
        case .series: return .series
        case .movies, .watchlist: return .movies
        }
    }
}
