import Foundation

public struct PlaybackLaunchRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let itemId: String
    public let title: String
    public let seriesTitle: String?
    public let season: Int?
    public let episode: Int?
    public let startPositionSeconds: Double?
    public let candidateId: String?
    public let prepareToken: String?
    public let preparedSession: TvPlaybackSession?
    public let inflightPrepareTask: Task<TvPrepareResponse?, Never>?
    public let inflightPrepareToken: String?
    public let preparedStreamSecretRegistered: Bool
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        startPositionSeconds: Double? = nil,
        candidateId: String? = nil,
        prepareToken: String? = nil,
        preparedSession: TvPlaybackSession? = nil,
        inflightPrepareTask: Task<TvPrepareResponse?, Never>? = nil,
        inflightPrepareToken: String? = nil,
        preparedStreamSecretRegistered: Bool = false,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.id = "\(itemId)#\(candidateId ?? "auto")#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        let parsed = EpisodeTitleFormatter.resolveSeasonAndEpisode(itemId: itemId, season: season, episode: episode)
        self.season = parsed.season
        self.episode = parsed.episode
        self.startPositionSeconds = startPositionSeconds
        self.candidateId = candidateId
        self.prepareToken = prepareToken
        self.preparedSession = preparedSession
        self.inflightPrepareTask = inflightPrepareTask
        self.inflightPrepareToken = inflightPrepareToken
        self.preparedStreamSecretRegistered = preparedStreamSecretRegistered
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }

    public static func == (lhs: PlaybackLaunchRequest, rhs: PlaybackLaunchRequest) -> Bool {
        lhs.id == rhs.id && lhs.itemId == rhs.itemId && lhs.title == rhs.title &&
            lhs.seriesTitle == rhs.seriesTitle && lhs.season == rhs.season && lhs.episode == rhs.episode &&
            lhs.startPositionSeconds == rhs.startPositionSeconds && lhs.candidateId == rhs.candidateId &&
            lhs.prepareToken == rhs.prepareToken && lhs.preparedSession == rhs.preparedSession &&
            lhs.preparedStreamSecretRegistered == rhs.preparedStreamSecretRegistered &&
            lhs.backdropUrl == rhs.backdropUrl && lhs.logoUrl == rhs.logoUrl
    }

    public var formattedEpisodeCode: String? {
        EpisodeTitleFormatter.formatEpisodeCode(season: season, episode: episode)
    }

    public var apiTitle: String {
        EpisodeTitleFormatter.apiEpisodeTitle(
            rawTitle: title,
            seriesTitle: seriesTitle,
            itemId: itemId,
            season: season,
            episode: episode
        )
    }
}

public struct TvDeviceOverrides: Codable, Equatable, Sendable {
    public var dualLayerOverride: String?
    public var speakerLayoutOverride: String?
    public var hdrSubtitlePreset: String?
    public var subtitleFontScale: Double?
    public var subtitleBoxOpacity: Double?
    public var autoPlayNextEpisode: Bool?
    public var smartNordicSubtitleRule: Bool?

    public init(
        dualLayerOverride: String? = nil,
        speakerLayoutOverride: String? = nil,
        hdrSubtitlePreset: String? = nil,
        subtitleFontScale: Double? = nil,
        subtitleBoxOpacity: Double? = nil,
        autoPlayNextEpisode: Bool? = nil,
        smartNordicSubtitleRule: Bool? = nil
    ) {
        self.dualLayerOverride = dualLayerOverride
        self.speakerLayoutOverride = speakerLayoutOverride
        self.hdrSubtitlePreset = hdrSubtitlePreset
        self.subtitleFontScale = subtitleFontScale
        self.subtitleBoxOpacity = subtitleBoxOpacity
        self.autoPlayNextEpisode = autoPlayNextEpisode
        self.smartNordicSubtitleRule = smartNordicSubtitleRule
    }
}

public struct TvPairingRequestResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let pairingCode: String
    public let displayCode: String
    public let expiresAt: String
    public let pollIntervalSeconds: Int?
}

public struct TvDeviceCapabilities: Codable, Equatable, Sendable {
    public var supportsHardwareAv1: Bool?
    public var physicalMemoryGB: Int?

    public init(supportsHardwareAv1: Bool? = nil, physicalMemoryGB: Int? = nil) {
        self.supportsHardwareAv1 = supportsHardwareAv1
        self.physicalMemoryGB = physicalMemoryGB
    }
}

extension DeviceHardwareCapabilities {
    public static var asTvCapabilities: TvDeviceCapabilities {
        TvDeviceCapabilities(
            supportsHardwareAv1: supportsHardwareAV1,
            physicalMemoryGB: physicalMemoryGB
        )
    }
}

public struct TvPairedDeviceInfo: Codable, Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let roomName: String
    public let roomUnassigned: Bool?
    public let hardwareProfile: String
    public let equipmentLabel: String?
    public let atmosphere: String?
    public let speakerLayout: String?
    public let overrides: TvDeviceOverrides?
    public let capabilities: TvDeviceCapabilities?

    public init(
        deviceId: String,
        deviceName: String,
        roomName: String,
        roomUnassigned: Bool? = nil,
        hardwareProfile: String,
        equipmentLabel: String? = nil,
        atmosphere: String? = nil,
        speakerLayout: String? = nil,
        overrides: TvDeviceOverrides? = nil,
        capabilities: TvDeviceCapabilities? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.roomUnassigned = roomUnassigned
        self.hardwareProfile = hardwareProfile
        self.equipmentLabel = equipmentLabel
        self.atmosphere = atmosphere
        self.speakerLayout = speakerLayout
        self.overrides = overrides
        self.capabilities = capabilities
    }
}

public struct TvPairingPollResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let deviceToken: String?
    public let device: TvPairedDeviceInfo?
    public let error: String?
}

public struct TvSubtitleSearchAttachResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let requestId: String?
    public let sessionId: String
    public let attached: Bool
    public let status: String
    public let provider: String?
    public let written: Bool?
    public let alignedNorwegian: Bool?
    public let downloadedCount: Int?
    public let subtitle: TvExternalSubtitle?
    public let externalSubtitles: [TvExternalSubtitle]
    public let subtitleDelayMs: Int?

    public init(
        ok: Bool = true,
        requestId: String? = nil,
        sessionId: String,
        attached: Bool,
        status: String,
        provider: String? = nil,
        written: Bool? = nil,
        alignedNorwegian: Bool? = nil,
        downloadedCount: Int? = nil,
        subtitle: TvExternalSubtitle? = nil,
        externalSubtitles: [TvExternalSubtitle] = [],
        subtitleDelayMs: Int? = nil
    ) {
        self.ok = ok
        self.requestId = requestId
        self.sessionId = sessionId
        self.attached = attached
        self.status = status
        self.provider = provider
        self.written = written
        self.alignedNorwegian = alignedNorwegian
        self.downloadedCount = downloadedCount
        self.subtitle = subtitle
        self.externalSubtitles = externalSubtitles
        self.subtitleDelayMs = subtitleDelayMs
    }

    enum CodingKeys: String, CodingKey {
        case ok, requestId, sessionId, attached, status, provider, written
        case alignedNorwegian, downloadedCount, subtitle, externalSubtitles, subtitleDelayMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
        self.requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        self.sessionId = try c.decode(String.self, forKey: .sessionId)
        self.attached = try c.decode(Bool.self, forKey: .attached)
        self.status = try c.decode(String.self, forKey: .status)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider)
        self.written = try c.decodeIfPresent(Bool.self, forKey: .written)
        self.alignedNorwegian = try c.decodeIfPresent(Bool.self, forKey: .alignedNorwegian)
        self.downloadedCount = try c.decodeIfPresent(Int.self, forKey: .downloadedCount)
        self.subtitle = try c.decodeIfPresent(TvExternalSubtitle.self, forKey: .subtitle)
        self.externalSubtitles = (try? c.decodeIfPresent([TvExternalSubtitle].self, forKey: .externalSubtitles)) ?? []
        self.subtitleDelayMs = try c.decodeIfPresent(Int.self, forKey: .subtitleDelayMs)
    }
}

public struct TvSubtitleAutoAlignResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let requestId: String?
    public let sessionId: String
    public let applied: Bool
    public let mode: String?
    public let reason: String?
    public let offsetMs: Double
    public let scale: Double?
    public let subtitleDelayMs: Int
    public let subtitle: TvExternalSubtitle?

    public init(
        ok: Bool = true,
        requestId: String? = nil,
        sessionId: String,
        applied: Bool,
        mode: String? = nil,
        reason: String? = nil,
        offsetMs: Double,
        scale: Double? = nil,
        subtitleDelayMs: Int,
        subtitle: TvExternalSubtitle? = nil
    ) {
        self.ok = ok
        self.requestId = requestId
        self.sessionId = sessionId
        self.applied = applied
        self.mode = mode
        self.reason = reason
        self.offsetMs = offsetMs
        self.scale = scale
        self.subtitleDelayMs = subtitleDelayMs
        self.subtitle = subtitle
    }
}

public struct TvAlternativesResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String
    public let roomName: String
    public let hardwareProfile: String
    public let activeCandidateId: String?
    public let alternatives: [TvCandidateInfo]

    public init(ok: Bool, sessionId: String, roomName: String, hardwareProfile: String, activeCandidateId: String? = nil, alternatives: [TvCandidateInfo]) {
        self.ok = ok
        self.sessionId = sessionId
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        self.activeCandidateId = activeCandidateId
        self.alternatives = alternatives
    }

    private enum CodingKeys: String, CodingKey {
        case ok, sessionId, roomName, hardwareProfile, activeCandidateId, alternatives
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
        self.sessionId = (try? c.decodeIfPresent(String.self, forKey: .sessionId)) ?? ""
        self.roomName = (try? c.decodeIfPresent(String.self, forKey: .roomName)) ?? ""
        self.hardwareProfile = (try? c.decodeIfPresent(String.self, forKey: .hardwareProfile)) ?? ""
        self.activeCandidateId = try? c.decodeIfPresent(String.self, forKey: .activeCandidateId)
        self.alternatives = (try? c.decodeIfPresent([TvCandidateInfo].self, forKey: .alternatives)) ?? []
    }
}

public struct TvSwitchResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let playbackSession: TvPlaybackSession

    public init(ok: Bool, playbackSession: TvPlaybackSession) {
        self.ok = ok
        self.playbackSession = playbackSession
    }
}
