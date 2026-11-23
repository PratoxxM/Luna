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
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(itemId: String, title: String, seriesTitle: String? = nil, season: Int? = nil, episode: Int? = nil, startPositionSeconds: Double? = nil, candidateId: String? = nil, prepareToken: String? = nil, preparedSession: TvPlaybackSession? = nil, inflightPrepareTask: Task<TvPrepareResponse?, Never>? = nil, inflightPrepareToken: String? = nil, backdropUrl: String? = nil, logoUrl: String? = nil) {
        self.id = "\(itemId)#\(candidateId ?? "auto")#\(UUID().uuidString)"
        self.itemId = itemId; self.title = title; self.seriesTitle = seriesTitle
        let parsed = EpisodeTitleFormatter.resolveSeasonAndEpisode(itemId: itemId, season: season, episode: episode)
        self.season = parsed.season; self.episode = parsed.episode; self.startPositionSeconds = startPositionSeconds
        self.candidateId = candidateId; self.prepareToken = prepareToken; self.preparedSession = preparedSession
        self.inflightPrepareTask = inflightPrepareTask; self.inflightPrepareToken = inflightPrepareToken
        self.backdropUrl = backdropUrl; self.logoUrl = logoUrl
    }

    public static func == (lhs: PlaybackLaunchRequest, rhs: PlaybackLaunchRequest) -> Bool {
        lhs.id == rhs.id && lhs.itemId == rhs.itemId && lhs.title == rhs.title &&
            lhs.seriesTitle == rhs.seriesTitle && lhs.season == rhs.season && lhs.episode == rhs.episode &&
            lhs.startPositionSeconds == rhs.startPositionSeconds && lhs.candidateId == rhs.candidateId &&
            lhs.prepareToken == rhs.prepareToken && lhs.preparedSession == rhs.preparedSession &&
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
    public let videoCodec: String?
    public let sourceQuality: String?
    public let channels: String?

    public init(
        candidateId: String, displayHeadline: String, releaseTitle: String, source: String,
        tier: String?, resolution: String?, videoRangeType: String?, dvProfile: Int?,
        dvEnhancementLayer: String?, audioCodec: String?, sizeBytes: Int64?, tvScore: Int?,
        isActive: Bool?, explanationChips: [String]?, releaseGroup: String?, isNorwegian: Bool?,
        videoCodec: String? = nil, sourceQuality: String? = nil, channels: String? = nil
    ) {
        self.candidateId = candidateId; self.displayHeadline = displayHeadline
        self.releaseTitle = releaseTitle; self.source = source; self.tier = tier
        self.resolution = resolution; self.videoRangeType = videoRangeType; self.dvProfile = dvProfile
        self.dvEnhancementLayer = dvEnhancementLayer; self.audioCodec = audioCodec; self.sizeBytes = sizeBytes
        self.tvScore = tvScore; self.isActive = isActive; self.explanationChips = explanationChips
        self.releaseGroup = releaseGroup; self.isNorwegian = isNorwegian; self.videoCodec = videoCodec
        self.sourceQuality = sourceQuality; self.channels = channels
    }

    public var id: String { candidateId }

    enum CodingKeys: String, CodingKey {
        case candidateId, displayHeadline, releaseTitle, source, tier, resolution
        case videoRangeType, dvProfile, dvEnhancementLayer, audioCodec, sizeBytes
        case tvScore, isActive, explanationChips, releaseGroup, isNorwegian
        case videoCodec, sourceQuality, channels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawRelease = c.decodeFlexString(.releaseTitle) ?? ""
        let rawHeadline = c.decodeFlexString(.displayHeadline)
        self.candidateId = c.decodeFlexString(.candidateId) ?? "unknown"
        self.releaseTitle = rawRelease
        self.displayHeadline = (rawHeadline?.isEmpty == false ? rawHeadline : nil)
            ?? (rawRelease.isEmpty ? "Ukjent utgave" : rawRelease)
        self.source = c.decodeFlexString(.source) ?? "unknown"
        self.tier = c.decodeFlexString(.tier)
        self.resolution = c.decodeFlexString(.resolution)
        self.videoRangeType = c.decodeFlexString(.videoRangeType)
        self.dvProfile = c.decodeFlexInt(.dvProfile)
        self.dvEnhancementLayer = c.decodeFlexString(.dvEnhancementLayer)
        self.audioCodec = c.decodeFlexString(.audioCodec)
        self.sizeBytes = c.decodeFlexInt(.sizeBytes)
        self.tvScore = c.decodeFlexInt(.tvScore)
        self.isActive = c.decodeFlexBool(.isActive)
        self.explanationChips = try? c.decodeIfPresent([String].self, forKey: .explanationChips)
        self.releaseGroup = c.decodeFlexString(.releaseGroup)
        self.isNorwegian = c.decodeFlexBool(.isNorwegian)
        self.videoCodec = c.decodeFlexString(.videoCodec)
        self.sourceQuality = c.decodeFlexString(.sourceQuality)
        self.channels = c.decodeFlexChannels(.channels)
    }

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
        if normSource.contains("easynews") {
            return "Arkiv-strøm (HTTPS)"
        }
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
        let chanLower = (channels ?? "").lowercased()
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
            return chanLower.contains("5.1") ? "TrueHD 5.1" : "TrueHD 7.1"
        }
        if lower.contains("dts-hd") || lower.contains("dts hd") {
            return chanLower.contains("7.1") ? "DTS-HD 7.1" : "DTS-HD"
        }
        if lower.contains("eac3") || lower.contains("ddp") || lower.contains("dd+") || lower.contains("dolby digital+") {
            return (lower.contains("5.1") || chanLower.contains("5.1")) ? "Dolby Digital+ 5.1" : "Dolby Digital+"
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

    public func quickRowTitle(roomName: String, isRecommended: Bool) -> String {
        let quality = humanQualitySummary
        guard isRecommended else { return quality }
        let trimmedRoom = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRoom.isEmpty {
            return quality.isEmpty ? "Anbefalt" : "Anbefalt · \(quality)"
        }
        return quality.isEmpty ? "Anbefalt for \(trimmedRoom)" : "Anbefalt for \(trimmedRoom) · \(quality)"
    }

    public func quickRowMetadata(activeLabel: String?) -> String {
        var parts: [String] = [sourceBadgeLabel]
        if let vc = videoCodec?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vc.isEmpty, vc.caseInsensitiveCompare("unknown") != .orderedSame {
            parts.append(vc.uppercased())
        }
        if let sq = sourceQuality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sq.isEmpty, sq.caseInsensitiveCompare("unknown") != .orderedSame {
            parts.append(sq)
        }
        if let size = formattedSize, !size.isEmpty { parts.append(size) }
        if let activeLabel, !activeLabel.isEmpty { parts.append(activeLabel) }
        return parts.joined(separator: " · ")
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func decodeFlexInt<T: FixedWidthInteger & Decodable & LosslessStringConvertible>(_ key: Key) -> T? {
        if let i = try? decodeIfPresent(T.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return T(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return T(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    func decodeFlexChannels(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let count: Int = decodeFlexInt(key), count > 0 else { return nil }
        switch count {
        case 1: return "1.0"
        case 2: return "2.0"
        case 3...5: return "\(count).0"
        case 6...7: return "5.1"
        default: return "7.1"
        }
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

    public init(url: String, container: String? = nil, supportsByteRanges: Bool? = nil, zeroCopyMode: String? = nil, canClientPrewarmBytes: Bool? = nil, startPositionSeconds: Double? = nil, declaredDurationSeconds: Double? = nil) {
        self.url = url; self.container = container; self.supportsByteRanges = supportsByteRanges
        self.zeroCopyMode = zeroCopyMode; self.canClientPrewarmBytes = canClientPrewarmBytes
        self.startPositionSeconds = startPositionSeconds; self.declaredDurationSeconds = declaredDurationSeconds
    }
}

public struct TvExternalSubtitle: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let format: String?
    public let language: String?
    public let name: String?
    public let isForced: Bool?
    public let isHearingImpaired: Bool?
    public let isDefault: Bool?

    public init(id: String, url: String, format: String? = nil, language: String? = nil, name: String? = nil, isForced: Bool? = nil, isHearingImpaired: Bool? = nil, isDefault: Bool? = nil) {
        self.id = id; self.url = url; self.format = format; self.language = language; self.name = name
        self.isForced = isForced; self.isHearingImpaired = isHearingImpaired; self.isDefault = isDefault
    }
}

public struct TvSessionTracks: Codable, Equatable, Sendable {
    public let probeConfidence: String?
    public let externalSubtitles: [TvExternalSubtitle]?
    public let chapters: [TvProbeChapter]?

    public init(probeConfidence: String? = nil, externalSubtitles: [TvExternalSubtitle]? = nil, chapters: [TvProbeChapter]? = nil) {
        self.probeConfidence = probeConfidence; self.externalSubtitles = externalSubtitles; self.chapters = chapters
    }
}

public struct TvObjectAudioConfig: Codable, Equatable, Sendable {
    public let mode: String
    public let layout: String?

    public init(mode: String, layout: String? = nil) {
        self.mode = mode; self.layout = layout
    }
}

public struct TvAetherConfig: Codable, Equatable, Sendable {
    public let preferDualLayerDolbyVision: Bool
    public let foldsDolbyVisionFEL: Bool?
    public let dolbyVisionHandling: String
    public let matchContentEnabled: Bool
    public let attemptsHDRMasterOnUnprovenPanel: Bool?
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

    public init(preferDualLayerDolbyVision: Bool, foldsDolbyVisionFEL: Bool? = nil, dolbyVisionHandling: String, matchContentEnabled: Bool, attemptsHDRMasterOnUnprovenPanel: Bool? = nil, objectAudioRendering: TvObjectAudioConfig? = nil, audioBridgeMode: String, preferredAudioLanguages: [String]? = nil, preferredSubtitleLanguages: [String]? = nil, skipsContainerAttachments: Bool? = nil, generatesBackgroundScrubPreviews: Bool? = nil, serveIFramePlaylist: Bool? = nil, confirmAtmos: Bool? = nil, maxConcurrentSourceRequests: Int? = nil, declaredDurationSeconds: Double? = nil) {
        self.preferDualLayerDolbyVision = preferDualLayerDolbyVision
        self.foldsDolbyVisionFEL = foldsDolbyVisionFEL; self.dolbyVisionHandling = dolbyVisionHandling
        self.matchContentEnabled = matchContentEnabled; self.attemptsHDRMasterOnUnprovenPanel = attemptsHDRMasterOnUnprovenPanel
        self.objectAudioRendering = objectAudioRendering; self.audioBridgeMode = audioBridgeMode
        self.preferredAudioLanguages = preferredAudioLanguages; self.preferredSubtitleLanguages = preferredSubtitleLanguages
        self.skipsContainerAttachments = skipsContainerAttachments; self.generatesBackgroundScrubPreviews = generatesBackgroundScrubPreviews
        self.serveIFramePlaylist = serveIFramePlaylist; self.confirmAtmos = confirmAtmos
        self.maxConcurrentSourceRequests = maxConcurrentSourceRequests; self.declaredDurationSeconds = declaredDurationSeconds
    }
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

    public init(itemId: String, mediaType: String, ids: TvMediaIds, title: String, seriesTitle: String? = nil, season: Int? = nil, episode: Int? = nil, year: Int? = nil, runtimeSeconds: Double? = nil, posterUrl: String? = nil, backdropUrl: String? = nil, logoUrl: String? = nil) {
        self.itemId = itemId; self.mediaType = mediaType; self.ids = ids; self.title = title
        self.seriesTitle = seriesTitle; self.season = season; self.episode = episode; self.year = year
        self.runtimeSeconds = runtimeSeconds; self.posterUrl = posterUrl; self.backdropUrl = backdropUrl; self.logoUrl = logoUrl
    }
}

public struct TvNextEpisodeSummary: Codable, Equatable, Sendable {
    public let itemId: String
    public let season: Int
    public let episode: Int
    public let title: String?
    public let stillUrl: String?

    public init(itemId: String, season: Int, episode: Int, title: String? = nil, stillUrl: String? = nil) {
        self.itemId = itemId; self.season = season; self.episode = episode; self.title = title; self.stillUrl = stillUrl
    }
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

    public init(sessionId: String, streamToken: String, roomName: String, hardwareProfile: String, item: TvPlaybackItemContext, selectedCandidate: TvCandidateInfo, stream: TvStreamEndpoint, tracks: TvSessionTracks? = nil, chapters: [TvProbeChapter]? = nil, aetherConfig: TvAetherConfig, heartbeatIntervalSeconds: Int? = nil, nextEpisode: TvNextEpisodeSummary? = nil) {
        self.sessionId = sessionId; self.streamToken = streamToken; self.roomName = roomName
        self.hardwareProfile = hardwareProfile; self.item = item; self.selectedCandidate = selectedCandidate
        self.stream = stream; self.tracks = tracks; self.chapters = chapters
        self.aetherConfig = aetherConfig; self.heartbeatIntervalSeconds = heartbeatIntervalSeconds; self.nextEpisode = nextEpisode
    }
}

public struct TvPrepareResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let prepareToken: String?
    public let playbackSession: TvPlaybackSession?

    public init(ok: Bool, prepareToken: String? = nil, playbackSession: TvPlaybackSession? = nil) {
        self.ok = ok; self.prepareToken = prepareToken; self.playbackSession = playbackSession
    }
}

public struct TvResolveStartResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let resolveId: String
    public let wsPath: String?
    public let playbackSession: TvPlaybackSession?
    public let error: String?

    public init(ok: Bool, resolveId: String, wsPath: String? = nil, playbackSession: TvPlaybackSession? = nil, error: String? = nil) {
        self.ok = ok; self.resolveId = resolveId; self.wsPath = wsPath; self.playbackSession = playbackSession; self.error = error
    }
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

    public init(type: String, resolveId: String? = nil, stage: String? = nil, percent: Int? = nil, candidateCount: Int? = nil, winnerHeadline: String? = nil, message: String? = nil, error: String? = nil, playbackSession: TvPlaybackSession? = nil) {
        self.type = type; self.resolveId = resolveId; self.stage = stage; self.percent = percent
        self.candidateCount = candidateCount; self.winnerHeadline = winnerHeadline
        self.message = message; self.error = error; self.playbackSession = playbackSession
    }
}

public struct TvVfsTelemetry: Codable, Equatable, Sendable {
    public let streamSource: String?

    public init(streamSource: String? = nil) {
        self.streamSource = streamSource
    }
}

public struct TvPendingCommand: Codable, Equatable, Sendable {
    public let type: String
    public let language: String?
    public let issuedAt: String?
    public let switchedAt: String?
    public let playbackSession: TvPlaybackSession?

    public init(type: String, language: String? = nil, issuedAt: String? = nil, switchedAt: String? = nil, playbackSession: TvPlaybackSession? = nil) {
        self.type = type; self.language = language; self.issuedAt = issuedAt; self.switchedAt = switchedAt; self.playbackSession = playbackSession
    }
}

public struct TvNextEpisodePrewarmInfo: Codable, Equatable, Sendable {
    public let itemId: String?
    public let sessionId: String?
    public let streamToken: String?
    public let streamUrl: String?
    public let canClientPrewarmBytes: Bool?
    public let nextEpisode: TvNextEpisodeSummary?

    public init(itemId: String? = nil, sessionId: String? = nil, streamToken: String? = nil, streamUrl: String? = nil, canClientPrewarmBytes: Bool? = nil, nextEpisode: TvNextEpisodeSummary? = nil) {
        self.itemId = itemId; self.sessionId = sessionId; self.streamToken = streamToken
        self.streamUrl = streamUrl; self.canClientPrewarmBytes = canClientPrewarmBytes; self.nextEpisode = nextEpisode
    }
}

public struct TvHeartbeatResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let sessionId: String?
    public let state: String
    public let pendingCommand: TvPendingCommand?
    public let vfsTelemetry: TvVfsTelemetry?
    public let nextEpisodePrewarm: TvNextEpisodePrewarmInfo?

    public init(ok: Bool, sessionId: String? = nil, state: String, pendingCommand: TvPendingCommand? = nil, vfsTelemetry: TvVfsTelemetry? = nil, nextEpisodePrewarm: TvNextEpisodePrewarmInfo? = nil) {
        self.ok = ok; self.sessionId = sessionId; self.state = state
        self.pendingCommand = pendingCommand; self.vfsTelemetry = vfsTelemetry; self.nextEpisodePrewarm = nextEpisodePrewarm
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
        self.ok = ok; self.sessionId = sessionId; self.roomName = roomName
        self.hardwareProfile = hardwareProfile; self.activeCandidateId = activeCandidateId; self.alternatives = alternatives
    }
}

public struct TvSwitchResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let playbackSession: TvPlaybackSession

    public init(ok: Bool, playbackSession: TvPlaybackSession) {
        self.ok = ok; self.playbackSession = playbackSession
    }
}
