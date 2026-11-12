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
    public let isUpcoming: Bool?
    public let airDateBadge: String?
    public let voteAverage: Double?
    public let runtimeSeconds: Double?
    public var watched: Bool
    public let availability: TvAvailabilityInfo?
    public var progress: TvWatchProgress?

    public var id: String { itemId }

    public var codeLabel: String {
        String(format: "E%02d", episodeNumber)
    }

    public var seasonEpisodeCode: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    public var formattedRuntime: String? {
        guard let runtimeSeconds, runtimeSeconds >= 60 else { return nil }
        let mins = Int((runtimeSeconds / 60.0).rounded())
        return "\(mins) min"
    }
}

public struct TvCastMember: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let name: String
    public let character: String?
    public let profileUrl: String?

    public var id: String { "\(name)#\(character ?? "")" }
}

public struct TvItemDetail: Codable, Equatable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let originalTitle: String?
    public let tagline: String?
    public let overview: String?
    public let overviewNo: String?
    public let overviewEn: String?
    public let year: Int?
    public let status: String?
    public let runtimeSeconds: Double?
    public let genres: [String]?
    public let cast: [String]?
    public let castMembers: [TvCastMember]?
    public let voteAverage: Double?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let cardBackdropUrl: String?
    public let logoUrl: String?
    public let dominantColor: String?
    public let blurHash: String?
    public let badges: [String]?
    public let nextAirDateBadge: String?
    public var inWatchlist: Bool
    public var isFavorite: Bool?
    public var watched: Bool
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?
    public let selectedSeason: Int?
    public let nextUp: TvNextUpPointer?
    public let seasons: [TvSeasonSummary]?
    public let episodes: [TvEpisodeCard]?

    public var favoriteFlag: Bool {
        isFavorite ?? false
    }

    public var preferredOverview: String? {
        for candidate in [overviewNo, overview, overviewEn] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    public var formattedRuntime: String? {
        guard let runtimeSeconds, runtimeSeconds >= 60 else { return nil }
        let totalMins = Int((runtimeSeconds / 60.0).rounded())
        if mediaType == "movie", totalMins >= 60 {
            let hours = totalMins / 60
            let mins = totalMins % 60
            return mins > 0 ? "\(hours) t \(mins) min" : "\(hours) t"
        }
        return "\(totalMins) min"
    }
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
    public let localCount: Int?
    public let items: [TvMediaCard]
}

public struct TvWatchlistResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let items: [TvMediaCard]
    public let favorites: [TvMediaCard]?
    public let watchlist: [TvMediaCard]?
}

public struct TvMutationAckResponse: Codable, Equatable, Sendable {
    public let ok: Bool
}
