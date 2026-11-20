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
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.id = "\(itemId)#\(candidateId ?? "auto")#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        let parsed = EpisodeTitleFormatter.resolveSeasonAndEpisode(
            itemId: itemId,
            season: season,
            episode: episode
        )
        self.season = parsed.season
        self.episode = parsed.episode
        self.startPositionSeconds = startPositionSeconds
        self.candidateId = candidateId
        self.prepareToken = prepareToken
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
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

public struct TvPairedDeviceInfo: Codable, Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let roomName: String
    public let hardwareProfile: String
    public let equipmentLabel: String?
    public let atmosphere: String?
    public let overrides: TvDeviceOverrides?

    public init(
        deviceId: String,
        deviceName: String,
        roomName: String,
        hardwareProfile: String,
        equipmentLabel: String? = nil,
        atmosphere: String? = nil,
        overrides: TvDeviceOverrides? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        self.equipmentLabel = equipmentLabel
        self.atmosphere = atmosphere
        self.overrides = overrides
    }
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
    public let explanationChips: [String]?
    public let releaseGroup: String?
    public let isNorwegian: Bool?

    public var id: String { candidateId }

    public var formattedSize: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return LunaCopy.formatGigabytes(gb, decimals: 1)
        }
        let mb = Double(sizeBytes) / 1_048_576.0
        return "\(Int(mb.rounded())) MB"
    }

    public var sourceBadgeLabel: String {
        let normTier = (tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normTier == "ssd" || normTier == "nvme" || normSource == "ssd" || normSource == "nvme" {
            return "På NVMe"
        }
        if normTier == "archive" || normSource == "archive" {
            return "I Arkiv"
        }
        if normTier == "vfs" || normTier == "infinidysk" || normSource.contains("infinidysk") || normSource == "vfs" {
            return "Strømmes ved start"
        }
        if normTier == "usenet" || normSource == "usenet" || normSource == "nzbfast" || normSource == "newznab" {
            return "Strømmes ved start"
        }
        if normTier == "remote" || normSource == "remote" || normSource == "http" {
            return "Strømmes ved start"
        }
        if normSource == "local" {
            return "Lokalt"
        }
        return LunaCopy.tierBenefitLabel(tier: normTier.isEmpty ? normSource : normTier)
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

    public var humanVideoSummary: String {
        var parts: [String] = []
        let normRes = (resolution ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normRes == "2160p" || normRes == "4k" || normRes == "uhd" {
            parts.append("4K")
        } else if !normRes.isEmpty && normRes != "unknown" {
            parts.append(normRes)
        }
        if let dv = dvProfile {
            if dv == 7, let layer = dvEnhancementLayer, !layer.isEmpty {
                parts.append("Dolby Vision P7 \(layer.uppercased())")
            } else {
                parts.append("Dolby Vision")
            }
        } else if let range = videoRangeType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !range.isEmpty,
                  range.caseInsensitiveCompare("SDR") != .orderedSame {
            let cleanRange = range
                .replacingOccurrences(of: "DolbyVision", with: "Dolby Vision")
                .replacingOccurrences(of: "HDR10Plus", with: "HDR10+")
            parts.append(cleanRange)
        }
        if parts.isEmpty {
            let headlineLower = displayHeadline.lowercased()
            if headlineLower.contains("4k") || headlineLower.contains("2160") {
                parts.append("4K")
            } else if headlineLower.contains("1080") {
                parts.append("1080p")
            } else if headlineLower.contains("720") {
                parts.append("720p")
            }
        }
        return parts.joined(separator: " ")
    }

    public var humanAudioSummary: String? {
        let lower = (audioCodec ?? displayHeadline).lowercased()
        if lower.contains("atmos") && lower.contains("truehd") {
            return "TrueHD Atmos"
        }
        if lower.contains("atmos") {
            return "Dolby Atmos"
        }
        if lower.contains("dts:x") || lower.contains("dtsx") {
            return "DTS:X"
        }
        if lower.contains("truehd") {
            return "TrueHD 7.1"
        }
        if lower.contains("dts-hd") || lower.contains("dts hd") {
            return "DTS-HD"
        }
        if lower.contains("eac3") || lower.contains("ddp") || lower.contains("dd+") || lower.contains("dolby digital+") {
            return lower.contains("5.1") ? "Dolby Digital+ 5.1" : "Dolby Digital+"
        }
        if lower.contains("ac3") || lower.contains("dd 5.1") {
            return "Surround 5.1"
        }
        return nil
    }

    public var humanQualitySummary: String {
        let components = [humanVideoSummary, humanAudioSummary].compactMap { val -> String? in
            guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        if !components.isEmpty {
            return components.joined(separator: " ")
        }
        return isNorwegian == true ? "Norsk utgave" : "Standard utgave"
    }

    public func humanDrawerTitle(roomName: String, isRecommended: Bool, isActive: Bool) -> String {
        let check = isActive ? " ✓" : ""
        let quality = humanQualitySummary
        if isRecommended {
            let trimmedRoom = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRoom.isEmpty {
                return quality.isEmpty ? "Anbefalt\(check)" : "Anbefalt · \(quality)\(check)"
            }
            return quality.isEmpty ? "Anbefalt for \(trimmedRoom)\(check)" : "Anbefalt for \(trimmedRoom) · \(quality)\(check)"
        }
        return "\(quality)\(check)"
    }

    public func humanDrawerSubtitle(isActive: Bool = false) -> String {
        var parts: [String] = [sourceBadgeLabel]
        if let size = formattedSize, !size.isEmpty {
            parts.append(size)
        }
        if isActive {
            parts.append("Spilles nå")
        }
        return parts.joined(separator: " · ")
    }
}

public struct PlayerDrawerAudioOption: Identifiable, Equatable, Sendable {
    public let id: Int
    public let languageCode: String?
    public let rawTitle: String
    public let codec: String
    public let profile: String?
    public let channelLayout: String?
    public let channels: Int
    public let isAtmos: Bool
    public let isDTSX: Bool
    public let isCommentary: Bool

    public init(
        id: Int,
        languageCode: String? = nil,
        rawTitle: String = "",
        codec: String = "",
        profile: String? = nil,
        channelLayout: String? = nil,
        channels: Int = 0,
        isAtmos: Bool = false,
        isDTSX: Bool = false,
        isCommentary: Bool = false
    ) {
        self.id = id
        self.languageCode = languageCode
        self.rawTitle = rawTitle
        self.codec = codec
        self.profile = profile
        self.channelLayout = channelLayout
        self.channels = channels
        self.isAtmos = isAtmos
        self.isDTSX = isDTSX
        self.isCommentary = isCommentary
    }

    public var humanLanguageTitle: String {
        if let lang = LunaCopy.localizedLanguageName(languageCode), lang != "Original" {
            return lang
        }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Spor \(id + 1)"
    }

    public var humanFormatSubtitle: String {
        let lowerCodec = codec.lowercased()
        let lowerProfile = (profile ?? "").lowercased()
        let layout = (channelLayout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatName: String
        if isAtmos && (lowerCodec.contains("truehd") || lowerProfile.contains("truehd")) {
            formatName = "TrueHD Atmos"
        } else if isAtmos {
            formatName = "Dolby Atmos"
        } else if isDTSX {
            formatName = "DTS:X"
        } else if lowerCodec.contains("truehd") {
            formatName = "TrueHD"
        } else if lowerCodec == "eac3" || lowerCodec.contains("dd+") {
            formatName = "Dolby Digital+"
        } else if lowerCodec == "ac3" {
            formatName = "Dolby Digital"
        } else if lowerCodec.contains("aac") {
            formatName = "AAC"
        } else if !lowerCodec.isEmpty && lowerCodec != "unknown" {
            formatName = codec.uppercased()
        } else {
            formatName = "Surround"
        }

        var segments = [formatName]
        if !layout.isEmpty {
            segments.append(layout)
        } else if channels >= 6 {
            segments.append("5.1")
        } else if channels == 2 {
            segments.append("Stereo")
        }
        if isCommentary {
            segments.append("Kommentarspor")
        }
        return segments.joined(separator: " ")
    }
}

public struct PlayerDrawerSubtitleOption: Identifiable, Equatable, Sendable {
    public let id: Int
    public let languageCode: String?
    public let rawTitle: String
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isExternal: Bool

    public init(
        id: Int,
        languageCode: String? = nil,
        rawTitle: String = "",
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isExternal: Bool = false
    ) {
        self.id = id
        self.languageCode = languageCode
        self.rawTitle = rawTitle
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isExternal = isExternal
    }

    public var humanLanguageTitle: String {
        let lang = LunaCopy.localizedLanguageName(languageCode) ?? {
            let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Undertekst \(id + 1)" : trimmed
        }()
        if isForced {
            return "\(lang) (tvunget)"
        }
        return lang
    }

    public var humanSubtitleDescription: String {
        if isForced {
            return "Kun ved fremmedspråk"
        }
        if isHearingImpaired {
            return "Tilrettelagt med lydtekst"
        }
        if isExternal {
            return "Fra egen tekstfil"
        }
        return "Innebygd i utgaven"
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
    public let language: String?
    public let issuedAt: String?
    public let switchedAt: String?
    public let playbackSession: TvPlaybackSession?

    public init(
        type: String,
        language: String? = nil,
        issuedAt: String? = nil,
        switchedAt: String? = nil,
        playbackSession: TvPlaybackSession? = nil
    ) {
        self.type = type
        self.language = language
        self.issuedAt = issuedAt
        self.switchedAt = switchedAt
        self.playbackSession = playbackSession
    }
}

public struct TvHeartbeatResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String
    public let state: String
    public let watchCompleted: Bool?
    public let vfsLockActive: Bool
    public let leaseExpiresAt: String?
    public let nextEpisodePrewarmStarted: Bool?
    public let nextEpisodePrewarmReady: Bool?
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
