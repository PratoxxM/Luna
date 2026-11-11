import Foundation

public struct PlaybackLaunchRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let itemId: String
    public let title: String
    public let seriesTitle: String?
    public let startPositionSeconds: Double?
    public let candidateId: String?

    public init(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        startPositionSeconds: Double? = nil,
        candidateId: String? = nil
    ) {
        self.id = "\(itemId)#\(candidateId ?? "auto")#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        self.startPositionSeconds = startPositionSeconds
        self.candidateId = candidateId
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
}

public struct TvStreamEndpoint: Codable, Equatable, Sendable {
    public let url: String
    public let container: String?
    public let supportsByteRanges: Bool?
    public let zeroCopyMode: String?
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
}

public struct TvObjectAudioConfig: Codable, Equatable, Sendable {
    public let mode: String
    public let layout: String?
}

public struct TvAetherConfig: Codable, Equatable, Sendable {
    public let preferDualLayerDolbyVision: Bool
    public let dualLayerRoute: String?
    public let foldsDolbyVisionFEL: Bool
    public let dolbyVisionHandling: String
    public let panelPresentsDolbyVision: Bool?
    public let panelIsInHDRMode: Bool?
    public let matchContentEnabled: Bool
    public let displayCriteriaOwner: String?
    public let attemptsHDRMasterOnUnprovenPanel: Bool
    public let objectAudioRendering: TvObjectAudioConfig?
    public let audioBridgeMode: String
    public let preferredAudioLanguages: [String]?
    public let preferredSubtitleLanguages: [String]?
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
}

public struct TvNextEpisodeSummary: Codable, Equatable, Sendable {
    public let itemId: String
    public let season: Int
    public let episode: Int
    public let title: String?
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
    public let aetherConfig: TvAetherConfig
    public let heartbeatIntervalSeconds: Int?
    public let nextEpisode: TvNextEpisodeSummary?
}

public struct TvResolveStartResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let status: String
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

public struct TvHeartbeatResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String
    public let state: String
    public let vfsLockActive: Bool
    public let leaseExpiresAt: String?
    public let nextEpisodePrewarmStarted: Bool?
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
