import Foundation

public struct TvSeasonSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let seasonNumber: Int
    public let name: String
    public let episodeCount: Int
    public let posterUrl: String?
    public let airDate: String?

    public var id: Int { seasonNumber }

    public var localizedName: String {
        LunaCopy.localizedSeasonTitle(name, seasonNumber: seasonNumber)
    }
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

    public var nonGenericTitle: String? {
        EpisodeTitleFormatter.nonGenericEpisodeTitle(
            title,
            season: seasonNumber,
            episode: episodeNumber,
            episodeCode: seasonEpisodeCode
        )
    }

    public init(
        itemId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        overview: String? = nil,
        stillUrl: String? = nil,
        airDate: String? = nil,
        isUpcoming: Bool? = nil,
        airDateBadge: String? = nil,
        voteAverage: Double? = nil,
        runtimeSeconds: Double? = nil,
        watched: Bool,
        availability: TvAvailabilityInfo? = nil,
        progress: TvWatchProgress? = nil
    ) {
        self.itemId = itemId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.stillUrl = stillUrl
        self.airDate = airDate
        self.isUpcoming = isUpcoming
        self.airDateBadge = airDateBadge
        self.voteAverage = voteAverage
        self.runtimeSeconds = runtimeSeconds
        self.watched = watched
        self.availability = availability
        self.progress = progress
    }

    public var formattedRuntime: String? {
        guard let runtimeSeconds, runtimeSeconds >= 60 else { return nil }
        let mins = Int((runtimeSeconds / 60.0).rounded())
        return "\(mins) min"
    }
}

public struct TvItemDetail: Codable, Equatable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let overview: String?
    public let overviewNo: String?
    public let overviewEn: String?
    public let year: Int?
    public let status: String?
    public let runtimeSeconds: Double?
    public let genres: [String]?
    public let voteAverage: Double?
    public let rating: Double?
    public let imdbRating: Double?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let cardBackdropUrl: String?
    public let logoUrl: String?
    public let dominantColor: String?
    public let blurHash: String?
    public let badges: [String]?
    public let nextAirDateBadge: String?
    public var inWatchlist: Bool
    public var watched: Bool
    public var monitored: Bool?
    public var monitorMode: String?
    public let availability: TvAvailabilityInfo?
    public let progress: TvWatchProgress?
    public let selectedSeason: Int?
    public let nextUp: TvNextUpPointer?
    public let seasons: [TvSeasonSummary]?
    public let episodes: [TvEpisodeCard]?

    public init(
        itemId: String,
        mediaType: String,
        ids: TvMediaIds,
        title: String,
        overview: String? = nil,
        overviewNo: String? = nil,
        overviewEn: String? = nil,
        year: Int? = nil,
        status: String? = nil,
        runtimeSeconds: Double? = nil,
        genres: [String]? = nil,
        voteAverage: Double? = nil,
        rating: Double? = nil,
        imdbRating: Double? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        cardBackdropUrl: String? = nil,
        logoUrl: String? = nil,
        dominantColor: String? = nil,
        blurHash: String? = nil,
        badges: [String]? = nil,
        nextAirDateBadge: String? = nil,
        inWatchlist: Bool,
        watched: Bool,
        monitored: Bool? = nil,
        monitorMode: String? = nil,
        availability: TvAvailabilityInfo? = nil,
        progress: TvWatchProgress? = nil,
        selectedSeason: Int? = nil,
        nextUp: TvNextUpPointer? = nil,
        seasons: [TvSeasonSummary]? = nil,
        episodes: [TvEpisodeCard]? = nil
    ) {
        self.itemId = itemId
        self.mediaType = mediaType
        self.ids = ids
        self.title = title
        self.overview = overview
        self.overviewNo = overviewNo
        self.overviewEn = overviewEn
        self.year = year
        self.status = status
        self.runtimeSeconds = runtimeSeconds
        self.genres = genres
        self.voteAverage = voteAverage
        self.rating = rating
        self.imdbRating = imdbRating
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.cardBackdropUrl = cardBackdropUrl
        self.logoUrl = logoUrl
        self.dominantColor = dominantColor
        self.blurHash = blurHash
        self.badges = badges
        self.nextAirDateBadge = nextAirDateBadge
        self.inWatchlist = inWatchlist
        self.watched = watched
        self.monitored = monitored
        self.monitorMode = monitorMode
        self.availability = availability
        self.progress = progress
        self.selectedSeason = selectedSeason
        self.nextUp = nextUp
        self.seasons = seasons
        self.episodes = episodes
    }

    public var isMonitoredFlag: Bool {
        monitored ?? false
    }

    public var displayRating: (value: Double, isImdb: Bool)? {
        if let im = imdbRating, im > 0 { return (im, true) }
        if let r = rating, r > 0 { return (r, false) }
        if let v = voteAverage, v > 0 { return (v, false) }
        return nil
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

    public init(ok: Bool, query: String, localCount: Int?, items: [TvMediaCard]) {
        self.ok = ok
        self.query = query
        self.localCount = localCount
        self.items = items
    }
}

public struct TvMutationAckResponse: Codable, Equatable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

public struct TvRowRemoveResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let removed: Bool?

    public init(ok: Bool, removed: Bool? = nil) {
        self.ok = ok
        self.removed = removed
    }
}

public struct TvMonitorResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let monitored: Bool?
    public let monitorMode: String?
    public let profileId: String?

    public init(ok: Bool, monitored: Bool? = nil, monitorMode: String? = nil, profileId: String? = nil) {
        self.ok = ok
        self.monitored = monitored
        self.monitorMode = monitorMode
        self.profileId = profileId
    }
}
