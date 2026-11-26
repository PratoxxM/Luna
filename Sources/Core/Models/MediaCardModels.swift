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
    public let benefitLabel: String?

    public init(state: String, tier: String? = nil, benefitLabel: String? = nil) {
        self.state = state
        self.tier = tier
        self.benefitLabel = benefitLabel
    }

    public var isLocalNvme: Bool {
        let norm = (tier ?? "").lowercased()
        return state == "instant" && (norm == "ssd" || norm == "nvme")
    }

    public var isLocalArchive: Bool {
        let norm = (tier ?? "").lowercased()
        return state == "instant" && norm == "archive"
    }

    public var isPhysicalLocal: Bool {
        isLocalNvme || isLocalArchive
    }

    public var isLocalVfs: Bool {
        let norm = (tier ?? "").lowercased()
        return norm == "vfs" || norm == "infinidysk" || norm == "usenet" || norm == "remote"
    }

    public var resolvedBenefitLabel: String {
        if let benefitLabel {
            let trimmed = benefitLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return LunaCopy.tierBenefitLabel(tier: tier, state: state)
    }

    public var householdBadgeLabel: String {
        if state == "upcoming" { return "Kommer" }
        if isLocalNvme { return "På NVMe" }
        if isLocalArchive { return "I Arkiv" }
        return "Strømmes ved start"
    }
}

public struct TvWatchProgress: Codable, Equatable, Hashable, Sendable {
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var percent: Double
    public var season: Int?
    public var episode: Int?
    public var watched: Bool?

    public init(
        positionSeconds: Double = 0, durationSeconds: Double = 0, percent: Double = 0,
        season: Int? = nil, episode: Int? = nil, watched: Bool? = nil
    ) {
        self.positionSeconds = positionSeconds; self.durationSeconds = durationSeconds; self.percent = percent
        self.season = season; self.episode = episode; self.watched = watched
    }
}

public struct TvDirectPlayTarget: Codable, Equatable, Hashable, Sendable {
    public let itemId: String
    public let mediaType: String?
    public let tmdbId: Int?
    public let season: Int?
    public let episode: Int?
    public let startPositionSeconds: Double?
    public let mode: String?
    public let prepareToken: String?

    public init(
        itemId: String, mediaType: String? = nil, tmdbId: Int? = nil,
        season: Int? = nil, episode: Int? = nil, startPositionSeconds: Double? = nil,
        mode: String? = nil, prepareToken: String? = nil
    ) {
        self.itemId = itemId; self.mediaType = mediaType; self.tmdbId = tmdbId
        self.season = season; self.episode = episode; self.startPositionSeconds = startPositionSeconds
        self.mode = mode; self.prepareToken = prepareToken
    }
}

public struct TvMediaCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let year: Int?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let cardBackdropUrl: String?
    public let logoUrl: String?
    public let dominantColor: String?
    public let blurHash: String?
    public let imdbRating: Double?
    public let badges: [String]?
    public var inWatchlist: Bool?
    public let contextSubtitle: String?
    public let airDate: String?
    public let daysUntil: Int?
    public let episodeCode: String?
    public let episodeTitle: String?
    public let airDateBadge: String?
    public let origin: String?
    public let originLabel: String?
    public let preparedSessionId: String?
    public let directPlayTarget: TvDirectPlayTarget?
    public let nextUp: TvNextUpPointer?
    public let availability: TvAvailabilityInfo?
    public var progress: TvWatchProgress?

    public var id: String { itemId }

    public init(
        itemId: String, mediaType: String, ids: TvMediaIds, title: String,
        year: Int? = nil, posterUrl: String? = nil, backdropUrl: String? = nil,
        cardBackdropUrl: String? = nil, logoUrl: String? = nil, dominantColor: String? = nil,
        blurHash: String? = nil, imdbRating: Double? = nil, badges: [String]? = nil,
        inWatchlist: Bool? = nil, contextSubtitle: String? = nil, airDate: String? = nil,
        daysUntil: Int? = nil, episodeCode: String? = nil, episodeTitle: String? = nil,
        airDateBadge: String? = nil, origin: String? = nil, originLabel: String? = nil,
        preparedSessionId: String? = nil, directPlayTarget: TvDirectPlayTarget? = nil,
        nextUp: TvNextUpPointer? = nil, availability: TvAvailabilityInfo? = nil,
        progress: TvWatchProgress? = nil
    ) {
        self.itemId = itemId; self.mediaType = mediaType; self.ids = ids; self.title = title
        self.year = year; self.posterUrl = posterUrl; self.backdropUrl = backdropUrl
        self.cardBackdropUrl = cardBackdropUrl; self.logoUrl = logoUrl; self.dominantColor = dominantColor
        self.blurHash = blurHash; self.imdbRating = imdbRating; self.badges = badges
        self.inWatchlist = inWatchlist; self.contextSubtitle = contextSubtitle; self.airDate = airDate
        self.daysUntil = daysUntil; self.episodeCode = episodeCode; self.episodeTitle = episodeTitle
        self.airDateBadge = airDateBadge; self.origin = origin; self.originLabel = originLabel
        self.preparedSessionId = preparedSessionId; self.directPlayTarget = directPlayTarget
        self.nextUp = nextUp; self.availability = availability; self.progress = progress
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
        if let year { parts.append(String(year)) }
        parts.append(mediaType == "series" ? "Serie" : "Film")
        if let rating = imdbRating, rating > 0 {
            parts.append(LunaCopy.formatRating(rating))
        }
        if let code = LunaCopy.formatListEpisodeCode(episodeCode) {
            parts.append(code)
        } else if let nextUp, let code = LunaCopy.formatListEpisodeCode(season: nextUp.season, episode: nextUp.episode) {
            parts.append(code)
        }
        return parts.joined(separator: " · ")
    }

    public var compactMetaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let rating = imdbRating, rating > 0 {
            parts.append(LunaCopy.formatRating(rating))
        }
        if parts.isEmpty {
            parts.append(mediaType == "series" ? "Serie" : "Film")
        }
        return parts.joined(separator: " · ")
    }

    public var nonGenericEpisodeTitle: String? {
        let parsedCode = EpisodeTitleFormatter.parseEpisodeCode(episodeCode)
        return EpisodeTitleFormatter.nonGenericEpisodeTitle(
            episodeTitle,
            seriesTitle: title,
            season: directPlayTarget?.season ?? nextUp?.season ?? progress?.season ?? parsedCode?.season,
            episode: directPlayTarget?.episode ?? nextUp?.episode ?? progress?.episode ?? parsedCode?.episode,
            episodeCode: episodeCode
        )
    }
}
