import Foundation

public struct TvSeasonSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let seasonNumber: Int
    public let name: String
    public let episodeCount: Int
    public let posterUrl: String?
    public let airDate: String?

    public var id: Int { seasonNumber }
}

public struct TvEpisodeCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let itemId: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let overview: String?
    public let stillUrl: String?
    public let airDate: String?
    public let runtimeSeconds: Double?
    public let watched: Bool
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?

    public var id: String { itemId }

    public var codeLabel: String {
        String(format: "E%02d", episodeNumber)
    }
}

public struct TvItemDetail: Codable, Equatable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let originalTitle: String?
    public let tagline: String?
    public let overview: String?
    public let year: Int?
    public let status: String?
    public let runtimeSeconds: Double?
    public let genres: [String]?
    public let cast: [String]?
    public let voteAverage: Double?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let inWatchlist: Bool
    public let watched: Bool
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?
    public let nextUp: TvNextUpPointer?
    public let seasons: [TvSeasonSummary]?
}

public struct TvItemDetailResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let item: TvItemDetail
}

public struct TvSeasonDetailResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let tmdbId: Int
    public let seasonNumber: Int
    public let title: String
    public let episodes: [TvEpisodeCard]
}

public struct TvSearchResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let query: String
    public let items: [TvMediaCard]
}

public struct TvWatchlistResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let items: [TvMediaCard]
}

public struct TvMutationAckResponse: Codable, Equatable, Sendable {
    public let ok: Bool
}
