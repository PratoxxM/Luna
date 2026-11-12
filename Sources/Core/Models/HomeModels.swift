import Foundation

public struct TvMediaIds: Codable, Equatable, Hashable, Sendable {
    public let tmdb: Int?
    public let imdb: String?
    public let tvdb: Int?

    public init(tmdb: Int? = nil, imdb: String? = nil, tvdb: Int? = nil) {
        self.tmdb = tmdb
        self.imdb = imdb
        self.tvdb = tvdb
    }
}

public struct TvNextUpPointer: Codable, Equatable, Hashable, Sendable {
    public let season: Int
    public let episode: Int

    public init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }
}

public struct TvAvailabilityInfo: Codable, Equatable, Hashable, Sendable {
    public let state: String
    public let tier: String?

    public init(state: String, tier: String? = nil) {
        self.state = state
        self.tier = tier
    }

    public var isLocalNvme: Bool {
        let norm = (tier ?? "").lowercased()
        return state == "instant" && (norm == "ssd" || norm == "nvme")
    }

    public var isLocalArchive: Bool {
        let norm = (tier ?? "").lowercased()
        return state == "instant" && norm == "archive"
    }

    public var isLocalVfs: Bool {
        let norm = (tier ?? "").lowercased()
        return state == "instant" && norm == "vfs"
    }

    public var householdBadgeLabel: String {
        if state == "upcoming" { return "Kommer" }
        if isLocalNvme { return "På NVMe" }
        if isLocalArchive { return "I Arkiv" }
        if isLocalVfs { return "Klar i VFS" }
        return "Strømmes ved valg"
    }
}

public struct TvWatchProgress: Codable, Equatable, Hashable, Sendable {
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let percent: Double
    public let season: Int?
    public let episode: Int?
    public let watched: Bool?
}

public struct TvDirectPlayTarget: Codable, Equatable, Hashable, Sendable {
    public let itemId: String
    public let mediaType: String?
    public let tmdbId: Int?
    public let season: Int?
    public let episode: Int?
    public let startPositionSeconds: Double?
    public let mode: String?
    public let title: String?
    public let seriesTitle: String?
}

public struct TvMediaCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let year: Int?
    public let overview: String?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let cardBackdropUrl: String?
    public let logoUrl: String?
    public let dominantColor: String?
    public let blurHash: String?
    public let imdbRating: Double?
    public let badges: [String]?
    public let inWatchlist: Bool?
    public let isFavorite: Bool?
    public let contextSubtitle: String?
    public let airDate: String?
    public let daysUntil: Int?
    public let episodeCode: String?
    public let episodeTitle: String?
    public let airDateBadge: String?
    public let directPlayTarget: TvDirectPlayTarget?
    public let nextUp: TvNextUpPointer?
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?

    public var id: String { itemId }

    public init(
        itemId: String,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        year: Int? = nil,
        overview: String? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        cardBackdropUrl: String? = nil,
        logoUrl: String? = nil,
        dominantColor: String? = nil,
        blurHash: String? = nil,
        imdbRating: Double? = nil,
        badges: [String]? = nil,
        inWatchlist: Bool? = nil,
        isFavorite: Bool? = nil,
        contextSubtitle: String? = nil,
        airDate: String? = nil,
        daysUntil: Int? = nil,
        episodeCode: String? = nil,
        episodeTitle: String? = nil,
        airDateBadge: String? = nil,
        directPlayTarget: TvDirectPlayTarget? = nil,
        nextUp: TvNextUpPointer? = nil,
        availability: TvAvailabilityInfo? = nil,
        progress: TvWatchProgress? = nil
    ) {
        self.itemId = itemId
        self.mediaType = mediaType
        self.ids = ids
        self.title = title
        self.year = year
        self.overview = overview
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.cardBackdropUrl = cardBackdropUrl
        self.logoUrl = logoUrl
        self.dominantColor = dominantColor
        self.blurHash = blurHash
        self.imdbRating = imdbRating
        self.badges = badges
        self.inWatchlist = inWatchlist
        self.isFavorite = isFavorite
        self.contextSubtitle = contextSubtitle
        self.airDate = airDate
        self.daysUntil = daysUntil
        self.episodeCode = episodeCode
        self.episodeTitle = episodeTitle
        self.airDateBadge = airDateBadge
        self.directPlayTarget = directPlayTarget
        self.nextUp = nextUp
        self.availability = availability
        self.progress = progress
    }

    public var preferredLandscapePath: String? {
        cardBackdropUrl ?? backdropUrl ?? posterUrl
    }

    public var preferredPosterPath: String? {
        posterUrl ?? cardBackdropUrl ?? backdropUrl
    }

    public var formattedSubtitle: String {
        if let contextSubtitle, !contextSubtitle.isEmpty {
            return contextSubtitle
        }
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        parts.append(mediaType == "series" ? "Serie" : "Film")
        if let rating = imdbRating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        if let code = episodeCode, !code.isEmpty {
            parts.append(code)
        } else if let nextUp {
            parts.append(String(format: "S%02dE%02d", nextUp.season, nextUp.episode))
        }
        return parts.joined(separator: " · ")
    }

    public var compactMetaLine: String {
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        if let rating = imdbRating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        if parts.isEmpty {
            parts.append(mediaType == "series" ? "Serie" : "Film")
        }
        return parts.joined(separator: " · ")
    }
}

public struct TvHeroBanner: Codable, Equatable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let year: Int?
    public let overview: String?
    public let backdropUrl: String?
    public let posterUrl: String?
    public let logoUrl: String?
    public let imdbRating: Double?
    public let runtimeSeconds: Double?
    public let badges: [String]?
    public let inWatchlist: Bool?
    public let nextUp: TvNextUpPointer?
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?
    public let primaryCta: String?
}

public struct TvGenreChip: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let slug: String
    public let label: String
    public let icon: String?
    public let accentColor: String?
    public let tmdbGenreIds: [Int]?
    public let browsePath: String
    public let catalogPath: String?

    public var id: String { "\(slug)#\(browsePath)" }

    public var inferredMediaType: String {
        if let catalogPath, catalogPath.contains("/series") {
            return "series"
        }
        if browsePath.contains(":series:") {
            return "series"
        }
        return "movie"
    }
}

public struct TvShelfRow: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let rowId: String
    public let title: String
    public let rowStyle: String
    public let sourceKind: String?
    public let listMode: String?
    public let hasMore: Bool?
    public let nextPath: String?
    public let items: [TvMediaCard]
    public let genres: [TvGenreChip]?

    public var id: String { rowId }
}

public struct TvHomeResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let generatedAt: String?
    public let layoutMode: String?
    public let roomName: String
    public let hardwareProfile: String
    public let hero: TvHeroBanner?
    public let rows: [TvShelfRow]
}

public struct TvRowPageResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let rowId: String
    public let title: String
    public let offset: Int
    public let limit: Int
    public let totalEstimate: Int?
    public let hasMore: Bool
    public let nextPath: String?
    public let items: [TvMediaCard]
}

// MARK: - Catalog & Genre Filter Models (`/api/tv/v1/catalog/:kind`)

public struct TvCatalogSortOption: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String
}

public struct TvCatalogGenreInfo: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let label: String
    public let icon: String?
    public let tmdbGenreIds: [Int]?
}

public struct TvCatalogResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let mediaType: String
    public let title: String
    public let genre: TvCatalogGenreInfo?
    public let sort: String
    public let localOnly: Bool
    public let unwatchedOnly: Bool
    public let page: Int
    public let limit: Int
    public let hasMore: Bool
    public let availableSorts: [TvCatalogSortOption]?
    public let availableGenres: [TvGenreChip]?
    public let items: [TvMediaCard]
}

// MARK: - Unified Library Hub Models (`/api/tv/v1/library`)

public struct TvLibraryActiveFilters: Codable, Equatable, Sendable {
    public let tier: String
    public let mediaType: String
    public let sort: String
}

public struct TvLibraryCounts: Codable, Equatable, Sendable {
    public let favorites: Int
    public let watchlist: Int
    public let localTotal: Int
    public let nvme: Int
    public let archive: Int
    public let vfs: Int
    public let customLists: Int
}

public struct TvCustomListSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mediaType: String?
    public let listMode: String?
    public let rowStyle: String?
    public let itemCount: Int
    public let browsePath: String
}

public struct TvLibraryResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let section: String
    public let activeFilters: TvLibraryActiveFilters?
    public let counts: TvLibraryCounts
    public let favorites: [TvMediaCard]
    public let watchlist: [TvMediaCard]
    public let localItems: [TvMediaCard]
    public let localHasMore: Bool?
    public let customLists: [TvCustomListSummary]?
}

// MARK: - Bootstrap & Room Profile Models

public struct TvRoomDefinition: Codable, Identifiable, Equatable, Sendable {
    public let roomName: String
    public let hardwareProfile: String
    public let label: String?
    public let description: String?

    public var id: String { roomName }
}

public struct TvServerBootstrapInfo: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let apiVersion: Int
    public let featureLevel: Int?
    public let capabilities: [String: Bool]?
}

public struct TvBootstrapResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let server: TvServerBootstrapInfo
    public let device: TvPairedDeviceInfo
    public let defaultRooms: [TvRoomDefinition]?
}
