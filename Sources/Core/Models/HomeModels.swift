import Foundation

public struct TvMediaIds: Codable, Equatable, Hashable, Sendable {
    public let tmdb: Int?
    public let imdb: String?
    public let tvdb: Int?
}

public struct TvNextUpPointer: Codable, Equatable, Hashable, Sendable {
    public let season: Int
    public let episode: Int
}

public struct TvAvailabilityInfo: Codable, Equatable, Hashable, Sendable {
    public let state: String
    public let tier: String?
}

public struct TvWatchProgress: Codable, Equatable, Hashable, Sendable {
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let percent: Double
    public let season: Int?
    public let episode: Int?
    public let watched: Bool?
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
    public let logoUrl: String?
    public let imdbRating: Double?
    public let badges: [String]?
    public let inWatchlist: Bool?
    public let nextUp: TvNextUpPointer?
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?

    public var id: String { itemId }

    public var formattedSubtitle: String {
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        parts.append(mediaType == "series" ? "Serie" : "Film")
        if let rating = imdbRating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        if let nextUp {
            parts.append(String(format: "S%02dE%02d", nextUp.season, nextUp.episode))
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
    public let tmdbGenreIds: [Int]?
    public let browsePath: String

    public var id: String { browsePath }
}

public struct TvShelfRow: Codable, Identifiable, Equatable, Sendable {
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
}

public struct TvBootstrapResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let server: TvServerBootstrapInfo
    public let device: TvPairedDeviceInfo
    public let defaultRooms: [TvRoomDefinition]?
}
