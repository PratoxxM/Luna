import Foundation

public extension TvMediaCard {
    var upcomingPillText: String {
        if let badge = airDateBadge?.trimmingCharacters(in: .whitespacesAndNewlines),
           !badge.isEmpty {
            if let range = badge.range(of: " · ") {
                let datePart = badge[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !datePart.isEmpty {
                    return datePart
                }
            }
            return badge
        }
        if let daysUntil {
            if daysUntil <= 0 { return "I dag" }
            if daysUntil == 1 { return "I morgen" }
        }
        return airDate ?? "Kommer"
    }

    var isUrgentUpcoming: Bool {
        if let daysUntil, daysUntil <= 1 {
            return true
        }
        let lower = upcomingPillText.lowercased()
        return lower.hasPrefix("i dag") || lower.hasPrefix("i morgen")
    }

    private var remainingMinutesLabel: String? {
        if let prog = progress,
           prog.positionSeconds.isFinite,
           prog.durationSeconds.isFinite,
           prog.positionSeconds > 15,
           prog.durationSeconds > prog.positionSeconds,
           let rawMins = Int(exactly: ((prog.durationSeconds - prog.positionSeconds) / 60.0).rounded()) {
            let mins = max(1, rawMins)
            return "\(mins) min igjen"
        }
        if let ctx = contextSubtitle {
            for part in ctx.components(separatedBy: " · ") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().contains("min igjen") {
                    return trimmed
                }
            }
        }
        return nil
    }

    var cleanContinueSubtitle: String {
        let code = LunaCopy.formatListEpisodeCode(episodeCode)
            ?? nextUp.flatMap { LunaCopy.formatListEpisodeCode(season: $0.season, episode: $0.episode) }
        let isResume = (progress?.percent ?? 0) > 1.0 || directPlayTarget?.mode == "resume"

        if mediaType == "movie" {
            if let rem = remainingMinutesLabel {
                return year.map { "\($0) · \(rem)" } ?? rem
            }
            if let contextSubtitle, !contextSubtitle.isEmpty {
                return contextSubtitle
            }
            return formattedSubtitle
        }

        if isResume {
            var parts: [String] = []
            if let code {
                parts.append(remainingMinutesLabel == nil ? "Fortsett \(code)" : code)
            } else if remainingMinutesLabel == nil {
                parts.append("Fortsett")
            }
            if let epName = nonGenericEpisodeTitle {
                parts.append(epName)
            }
            if let rem = remainingMinutesLabel {
                parts.append(rem)
            }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        } else if let code {
            if let epName = nonGenericEpisodeTitle {
                return "Neste · \(code) · \(epName)"
            }
            return "Neste · \(code)"
        }

        return formattedSubtitle
    }

    var cleanUpcomingSubtitle: String {
        let code = LunaCopy.formatListEpisodeCode(episodeCode)
            ?? nextUp.flatMap { LunaCopy.formatListEpisodeCode(season: $0.season, episode: $0.episode) }
        if let epName = nonGenericEpisodeTitle {
            return code.map { "\($0) · \(epName)" } ?? epName
        }
        if let nextUp, nextUp.season >= 0, nextUp.episode > 0 {
            return nextUp.season == 0
                ? "Spesialer · Episode \(nextUp.episode)"
                : "Sesong \(nextUp.season) · Episode \(nextUp.episode)"
        }
        if let code {
            return code
        }
        return airDate.map { "Sendes \($0)" } ?? "Kommende episode"
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

    public var id: String { rowId }

    public init(
        rowId: String, title: String, rowStyle: String,
        sourceKind: String? = nil, listMode: String? = nil,
        hasMore: Bool? = nil, nextPath: String? = nil, items: [TvMediaCard]
    ) {
        self.rowId = rowId; self.title = title; self.rowStyle = rowStyle
        self.sourceKind = sourceKind; self.listMode = listMode
        self.hasMore = hasMore; self.nextPath = nextPath; self.items = items
    }
}

public struct TvTonightPayload: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let roomName: String?
    public let hardwareProfile: String?
    public let equipmentLabel: String?
    public let atmosphere: String?
    public let reason: String?
    public let reasonLabel: String?
    public let preparedFromPhone: TvMediaCard?
    public let item: TvMediaCard?

    public init(
        ok: Bool? = nil, roomName: String? = nil, hardwareProfile: String? = nil,
        equipmentLabel: String? = nil, atmosphere: String? = nil,
        reason: String? = nil, reasonLabel: String? = nil,
        preparedFromPhone: TvMediaCard? = nil, item: TvMediaCard? = nil
    ) {
        self.ok = ok; self.roomName = roomName; self.hardwareProfile = hardwareProfile
        self.equipmentLabel = equipmentLabel; self.atmosphere = atmosphere
        self.reason = reason; self.reasonLabel = reasonLabel
        self.preparedFromPhone = preparedFromPhone; self.item = item
    }
}

public struct TvHomeResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let generatedAt: String?
    public let layout: String?
    public let roomName: String
    public let hardwareProfile: String
    public let equipmentLabel: String?
    public let atmosphere: String?
    public let tonight: TvTonightPayload?
    public let rows: [TvShelfRow]

    public init(
        ok: Bool, generatedAt: String? = nil, layout: String? = nil,
        roomName: String, hardwareProfile: String,
        equipmentLabel: String? = nil, atmosphere: String? = nil,
        tonight: TvTonightPayload? = nil, rows: [TvShelfRow]
    ) {
        self.ok = ok; self.generatedAt = generatedAt; self.layout = layout
        self.roomName = roomName; self.hardwareProfile = hardwareProfile
        self.equipmentLabel = equipmentLabel; self.atmosphere = atmosphere
        self.tonight = tonight; self.rows = rows
    }

    /// Ignores transient `generatedAt` timestamps when checking whether a home
    /// response actually changed the visible shelves or room/profile state.
    public func isSemanticallyEqual(to other: TvHomeResponse) -> Bool {
        ok == other.ok
            && layout == other.layout
            && roomName == other.roomName
            && hardwareProfile == other.hardwareProfile
            && equipmentLabel == other.equipmentLabel
            && atmosphere == other.atmosphere
            && tonight == other.tonight
            && rows == other.rows
    }
}

public struct TvRowPageResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let rowId: String
    public let sourceKind: String?
    public let title: String
    public let offset: Int
    public let limit: Int
    public let totalEstimate: Int?
    public let hasMore: Bool
    public let nextPath: String?
    public let items: [TvMediaCard]

    public init(
        ok: Bool, rowId: String, sourceKind: String? = nil, title: String,
        offset: Int, limit: Int, totalEstimate: Int? = nil,
        hasMore: Bool, nextPath: String? = nil, items: [TvMediaCard]
    ) {
        self.ok = ok; self.rowId = rowId; self.sourceKind = sourceKind; self.title = title
        self.offset = offset; self.limit = limit; self.totalEstimate = totalEstimate
        self.hasMore = hasMore; self.nextPath = nextPath; self.items = items
    }
}
