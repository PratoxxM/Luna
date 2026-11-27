import Foundation

public enum TvDeleteScope: String, Codable, Equatable, Hashable, Sendable {
    case title
    case series
    case season
    case episode
}

public struct TvDeleteRequestTarget: Identifiable, Equatable, Hashable, Sendable {
    public let kind: String
    public let itemId: String
    public let tmdbId: Int?
    public let tvdbId: Int?
    public let title: String
    public let subtitle: String?
    public let scope: TvDeleteScope
    public let season: Int?
    public let episode: Int?

    public var id: String {
        "\(kind)#\(itemId)#\(scope.rawValue)#\(season ?? -1)#\(episode ?? -1)"
    }

    public init(
        kind: String,
        itemId: String,
        tmdbId: Int? = nil,
        tvdbId: Int? = nil,
        title: String,
        subtitle: String? = nil,
        scope: TvDeleteScope,
        season: Int? = nil,
        episode: Int? = nil
    ) {
        self.kind = kind
        self.itemId = itemId
        self.tmdbId = tmdbId
        self.tvdbId = tvdbId
        self.title = title
        self.subtitle = subtitle
        self.scope = scope
        self.season = season
        self.episode = episode
    }

    public var isWholeTitle: Bool {
        kind == "movie" || scope == .series || scope == .title
    }

    public var dialogHeading: String {
        switch scope {
        case .episode:
            return "Slett episode"
        case .season:
            return season == 0 ? "Slett Spesialer" : "Slett sesong \(season ?? 1)"
        case .series:
            return "Slett hele serien"
        case .title:
            return kind == "series" ? "Slett hele serien" : "Slett filmen"
        }
    }
}

public struct TvDeleteTargetSummary: Decodable, Equatable, Sendable {
    public let kind: String
    public let scope: String
    public let season: Int?
    public let episode: Int?
    public let title: String?
    public let year: Int?
    public let monitored: Bool?
}

public struct TvDeleteFilesSummary: Decodable, Equatable, Sendable {
    public let count: Int
    public let logicalBytes: Int64
    public let physicalBytes: Int64

    public var freedDisplayBytes: Int64 {
        physicalBytes > 0 ? physicalBytes : logicalBytes
    }

    public static func formatGigabytesOrMegabytes(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 GB" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return LunaCopy.formatGigabytes(gb, decimals: 2)
        }
        let mb = max(1, Int((Double(bytes) / 1_048_576.0).rounded()))
        return "\(mb) MB"
    }
}

public struct TvDeleteBlocker: Decodable, Identifiable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let sessionId: String?
    public let roomName: String?

    public var id: String { "\(code)#\(sessionId ?? message)" }
}

public struct TvDeletePreflightResponse: Decodable, Equatable, Sendable {
    public let preflightId: String?
    public let target: TvDeleteTargetSummary
    public let files: TvDeleteFilesSummary
    public let blockers: [TvDeleteBlocker]
    public let warnings: [String]?
}
