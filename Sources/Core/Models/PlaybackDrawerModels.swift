import Foundation

public enum HDRSubtitlePreset: String, CaseIterable, Identifiable, Sendable {
    case white100 = "white_100"
    case warm75 = "warm_75"
    case warm60 = "warm_60"
    case soft50 = "soft_50"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .white100: return "Klar 100 %"
        case .warm75: return "Varm 75 %"
        case .warm60: return "Dempet 60 %"
        case .soft50: return "Kveldsro 50 %"
        }
    }

    public var displayTitle: String {
        shortTitle
    }

    public var compactPillLabel: String {
        switch self {
        case .white100: return "100 %"
        case .warm75: return "75 %"
        case .warm60: return "60 %"
        case .soft50: return "50 %"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .white100:
            return "Varm Lampelys-hvit uten blendende råhvit topp"
        case .warm75:
            return "Anbefalt standard — behagelig varmhvit uten å blende i mørke scener"
        case .warm60:
            return "Mykere varmtone for kveldsvisning i dempet belysning"
        case .soft50:
            return "Maksimal øyekomfort i helt mørklagt hjemmekino"
        }
    }

    /// Warm Lampelys RGB multipliers applied consistently across both SDR and HDR/Dolby Vision
    /// (zero raw `(1.0, 1.0, 1.0)` `#FFFFFF` glare; `.white100` matches `LunaTokens.Text.primary` `#F5F0E8`).
    public var rgbComponents: (r: Double, g: Double, b: Double) {
        switch self {
        case .white100: return (245.0 / 255.0, 240.0 / 255.0, 232.0 / 255.0)
        case .warm75:   return (0.76, 0.72, 0.65)
        case .warm60:   return (0.62, 0.58, 0.52)
        case .soft50:   return (0.50, 0.47, 0.42)
        }
    }

    public var hdrRGB: (r: Double, g: Double, b: Double) {
        rgbComponents
    }
}

public enum QuickPanelHorizontalDirection: Sendable {
    case left
    case right
}

public enum PlayerQuickPanelTab: String, CaseIterable, Identifiable, Sendable {
    case subtitles
    case audio
    case source
    case picture
    case chapters

    public var id: String { rawValue }

    /// Compact pill label displayed in `PlayerBottomBarView` (`Tekst · Lyd · Utgave · Bilde · Kapitler`).
    public var title: String {
        switch self {
        case .subtitles: return "Tekst"
        case .audio: return "Lyd"
        case .source: return "Utgave"
        case .picture: return "Bilde"
        case .chapters: return "Kapitler"
        }
    }

    /// Header title inside the open `PlayerQuickPanelView` popover.
    public var panelHeaderTitle: String {
        switch self {
        case .source:
            return "Velg utgave"
        case .subtitles, .audio, .picture, .chapters:
            return title
        }
    }

    public var systemImage: String {
        switch self {
        case .subtitles: return "captions.bubble"
        case .audio: return "waveform"
        case .source: return "film.stack"
        case .picture: return "sparkles.tv"
        case .chapters: return "list.bullet"
        }
    }

    public static func visibleTabs(hasChapters: Bool) -> [PlayerQuickPanelTab] {
        allCases.filter { hasChapters || $0 != .chapters }
    }

    public func adjacentTab(
        direction: QuickPanelHorizontalDirection,
        hasChapters: Bool
    ) -> PlayerQuickPanelTab? {
        let tabs = Self.visibleTabs(hasChapters: hasChapters)
        guard let currentIndex = tabs.firstIndex(of: self) else { return nil }
        switch direction {
        case .left:
            let prev = currentIndex - 1
            return prev >= 0 ? tabs[prev] : nil
        case .right:
            let next = currentIndex + 1
            return next < tabs.count ? tabs[next] : nil
        }
    }

    /// True when focus rests inside an inline horizontal pill strip (`Kveldslys`, `Tekstsynk`,
    /// `Høyttaleroppsett`, `Lydsynk`), where Left/Right navigates horizontally between pills
    /// rather than switching quick-panel tabs.
    public static func isHorizontalPillFocusID(_ focusID: String?) -> Bool {
        guard let focusID else { return false }
        return focusID.hasPrefix("sub-kveldslys-") ||
            focusID.hasPrefix("sub-sync-") ||
            focusID.hasPrefix("aud-layout-") ||
            focusID.hasPrefix("aud-sync-")
    }

    public var fallbackTriggerMinX: Double {
        switch self {
        case .subtitles: return 90
        case .audio: return 242
        case .source: return 384
        case .picture: return 548
        case .chapters: return 694
        }
    }
}

public extension TvCandidateInfo {
    var formattedSize: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return LunaCopy.formatGigabytes(gb, decimals: 1)
        }
        let mb = Double(sizeBytes) / 1_048_576.0
        return "\(Int(mb.rounded())) MB"
    }

    var sourceBadgeLabel: String {
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

    var humanVideoSummary: String {
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

    var humanAudioSummary: String? {
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

    var humanQualitySummary: String {
        let components = [humanVideoSummary, humanAudioSummary].compactMap { val -> String? in
            guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        if !components.isEmpty {
            return components.joined(separator: " ")
        }
        return isNorwegian == true ? "Norsk utgave" : "Standard utgave"
    }

    func quickRowTitle(roomName: String, isRecommended: Bool) -> String {
        let quality = humanQualitySummary
        guard isRecommended else { return quality }
        let trimmedRoom = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRoom.isEmpty {
            return quality.isEmpty ? "Anbefalt" : "Anbefalt · \(quality)"
        }
        return quality.isEmpty ? "Anbefalt for \(trimmedRoom)" : "Anbefalt for \(trimmedRoom) · \(quality)"
    }

    func quickRowMetadata(activeLabel: String?) -> String {
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

    /// Concise single-line quality headline tailored for the `Velg utgave` in-player quick panel
    /// so video/HDR/audio format details never clip inside the floating popover width.
    var inPlayerQuickRowTitle: String {
        let compactVideo = humanVideoSummary
            .replacingOccurrences(of: "Dolby Vision P7 ", with: "DV P7 ")
        let components = [compactVideo, humanAudioSummary].compactMap { val -> String? in
            guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        if !components.isEmpty {
            return components.joined(separator: " · ")
        }
        return isNorwegian == true ? "Norsk utgave" : "Standard utgave"
    }

    func inPlayerQuickRowSubtitle(isRecommended: Bool, activeLabel: String?) -> String {
        var parts: [String] = []
        if isNorwegian == true {
            parts.append("Norsk")
        }
        if isRecommended && (activeLabel == nil || activeLabel?.isEmpty == true) {
            parts.append("Anbefalt")
        }
        parts.append(sourceBadgeLabel)
        if let vc = videoCodec?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vc.isEmpty, vc.caseInsensitiveCompare("unknown") != .orderedSame {
            parts.append(vc.uppercased())
        }
        if let size = formattedSize, !size.isEmpty {
            parts.append(size)
        }
        if let activeLabel, !activeLabel.isEmpty {
            parts.append(activeLabel)
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
