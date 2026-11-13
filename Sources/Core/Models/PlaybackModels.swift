import Foundation

public struct PlaybackLaunchRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let itemId: String
    public let title: String
    public let seriesTitle: String?
    public let startPositionSeconds: Double?
    public let candidateId: String?
    public let prepareToken: String?
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        startPositionSeconds: Double? = nil,
        candidateId: String? = nil,
        prepareToken: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.id = "\(itemId)#\(candidateId ?? "auto")#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        self.startPositionSeconds = startPositionSeconds
        self.candidateId = candidateId
        self.prepareToken = prepareToken
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
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

public struct TvPairedDeviceInfo: Codable, Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let roomName: String
    public let hardwareProfile: String
    public let overrides: TvDeviceOverrides?
}

public struct TvPairingPollResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let deviceToken: String?
    public let device: TvPairedDeviceInfo?
    public let error: String?
}

public struct TvCandidateInfo: Codable, Identifiable, Equatable, Sendable {
    public let candidateId: String
    public let displayHeadline: String
    public let releaseTitle: String
    public let source: String
    public let tier: String?
    public let resolution: String?
    public let videoRangeType: String?
    public let dvProfile: Int?
    public let dvEnhancementLayer: String?
    public let audioCodec: String?
    public let sizeBytes: Int64?
    public let tvScore: Int?
    public let isActive: Bool?

    public var id: String { candidateId }

    public var formattedSize: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeBytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }

    public var sourceBadgeLabel: String {
        let normTier = (tier ?? "").lowercased()
        if normTier == "ssd" || normTier == "nvme" { return "På NVMe" }
        if normTier == "archive" { return "I Arkiv" }
        if normTier == "vfs" || source.lowercased() == "infinidysk" { return "InfiniDysk VFS" }
        return source.uppercased()
    }

    public var capabilityBadges: [String] {
        var tags: [String] = [sourceBadgeLabel]
        if let res = resolution, !res.isEmpty, res != "unknown" {
            tags.append(res.uppercased())
        }
        if let dv = dvProfile {
            if dv == 7, let layer = dvEnhancementLayer, !layer.isEmpty {
                tags.append("DV P7 \(layer.uppercased())")
            } else {
                tags.append("DV P\(dv)")
            }
        } else if let range = videoRangeType, !range.isEmpty, range != "SDR" {
            tags.append(range.replacingOccurrences(of: "HDR10Plus", with: "HDR10+"))
        }
        if let ac = audioCodec, !ac.isEmpty, ac != "unknown" {
            tags.append(ac)
        }
        if let size = formattedSize {
            tags.append(size)
        }
        return tags
    }
}

public struct TvStreamEndpoint: Codable, Equatable, Sendable {
    public let url: String
    public let container: String?
    public let supportsByteRanges: Bool?
    public let zeroCopyMode: String?
    public let canClientPrewarmBytes: Bool?
    public let startPositionSeconds: Double?
    public let declaredDurationSeconds: Double?
}

public struct TvExternalSubtitle: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let format: String?
    public let formatHint: String?
    public let language: String?
    public let name: String?
    public let isForced: Bool?
    public let isHearingImpaired: Bool?
    public let isDefault: Bool?
}

public struct TvSessionTracks: Codable, Equatable, Sendable {
    public let probeConfidence: String?
    public let externalSubtitles: [TvExternalSubtitle]?
    public let chapters: [TvProbeChapter]?
}

public struct TvObjectAudioConfig: Codable, Equatable, Sendable {
    public let mode: String
    public let layout: String?
}

public struct TvAetherConfig: Codable, Equatable, Sendable {
    public let preferDualLayerDolbyVision: Bool
    public let dualLayerRoute: String?
    public let foldsDolbyVisionFEL: Bool?
    public let dolbyVisionHandling: String
    public let panelPresentsDolbyVision: Bool?
    public let panelIsInHDRMode: Bool?
    public let matchContentEnabled: Bool
    public let displayCriteriaOwner: String?
    public let attemptsHDRMasterOnUnprovenPanel: Bool?
    public let objectAudioRendering: TvObjectAudioConfig?
    public let audioBridgeMode: String
    public let preferredAudioLanguages: [String]?
    public let preferredSubtitleLanguages: [String]?
    public let autoPlayNextEpisode: Bool?
    public let smartNordicSubtitleRule: Bool?
    public let skipsContainerAttachments: Bool?
    public let generatesBackgroundScrubPreviews: Bool?
    public let serveIFramePlaylist: Bool?
    public let confirmAtmos: Bool?
    public let maxConcurrentSourceRequests: Int?
    public let declaredDurationSeconds: Double?
}

public struct TvPlaybackItemContext: Codable, Equatable, Sendable {
    public let itemId: String
    public let mediaType: String
    public let ids: TvMediaIds
    public let title: String
    public let seriesTitle: String?
    public let season: Int?
    public let episode: Int?
    public let year: Int?
    public let runtimeSeconds: Double?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let logoUrl: String?
}

public struct TvNextEpisodeSummary: Codable, Equatable, Sendable {
    public let itemId: String
    public let season: Int
    public let episode: Int
    public let title: String?
    public let stillUrl: String?
}

public struct TvPlaybackSession: Codable, Equatable, Sendable {
    public let sessionId: String
    public let streamToken: String
    public let roomName: String
    public let hardwareProfile: String
    public let item: TvPlaybackItemContext
    public let selectedCandidate: TvCandidateInfo
    public let stream: TvStreamEndpoint
    public let tracks: TvSessionTracks?
    public let chapters: [TvProbeChapter]?
    public let aetherConfig: TvAetherConfig
    public let heartbeatIntervalSeconds: Int?
    public let nextEpisode: TvNextEpisodeSummary?
}

public struct TvPrepareResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let reused: Bool?
    public let prepareToken: String?
    public let canClientPrewarmBytes: Bool?
    public let playbackSession: TvPlaybackSession?
}

public struct TvResolveStartResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let preResolved: Bool?
    public let resolveId: String
    public let wsPath: String?
    public let playbackSession: TvPlaybackSession?
    public let error: String?
}

public struct TvResolveSocketEvent: Codable, Equatable, Sendable {
    public let type: String
    public let resolveId: String?
    public let stage: String?
    public let percent: Int?
    public let candidateCount: Int?
    public let winnerHeadline: String?
    public let message: String?
    public let error: String?
    public let playbackSession: TvPlaybackSession?
}

public struct TvVfsTelemetry: Codable, Equatable, Sendable {
    public let streamSource: String?
    public let vfsMountFolder: String?
}

public struct TvPendingCommand: Codable, Equatable, Sendable {
    public let type: String
    public let switchedAt: String?
    public let playbackSession: TvPlaybackSession?
}

public struct TvHeartbeatResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String
    public let state: String
    public let watchCompleted: Bool?
    public let vfsLockActive: Bool
    public let leaseExpiresAt: String?
    public let nextEpisodePrewarmStarted: Bool?
    public let pendingCommand: TvPendingCommand?
    public let vfsTelemetry: TvVfsTelemetry?
}

public struct TvAlternativesResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String
    public let roomName: String
    public let hardwareProfile: String
    public let activeCandidateId: String?
    public let alternatives: [TvCandidateInfo]
}

public struct TvSwitchResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
    public let switched: Bool
    public let playbackSession: TvPlaybackSession
}
