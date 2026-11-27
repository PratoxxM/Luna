import Foundation

/// Deterministic HDMI display-switch curtain gate evaluator.
///
/// Enforces Luna's cinema curtain invariant:
/// - Keep `ResolvingCurtainView` opaque until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch`
/// - Force-unlock after `defaultFallbackTimeoutSeconds` (5.0 s) so a missed HDMI EDID notification never hangs black
public enum PlaybackCurtainWatchdog: Sendable {
    public static let defaultFallbackTimeoutSeconds: Double = 5.0

    public static func effectiveFallbackTimeoutSeconds(
        isHoldingOutgoingPicture: Bool,
        heldPictureFrameWaitSeconds: Double
    ) -> Double {
        guard isHoldingOutgoingPicture,
              heldPictureFrameWaitSeconds.isFinite,
              heldPictureFrameWaitSeconds > 0 else {
            return defaultFallbackTimeoutSeconds
        }
        return min(defaultFallbackTimeoutSeconds, heldPictureFrameWaitSeconds)
    }

    public static func isPictureReadyForReveal(
        hasFatalError: Bool,
        isSwitchingSource: Bool,
        isResolving: Bool,
        isRestoringFromBackground: Bool,
        needsForegroundVideoRestore: Bool,
        firstFrameFallbackUnlocked: Bool,
        hasFirstFrameReadyForDisplay: Bool,
        isAwaitingDisplaySwitch: Bool,
        isReplacingSourceItem: Bool = false,
        isHoldingOutgoingPicture: Bool = false
    ) -> Bool {
        if hasFatalError {
            return false
        }
        if isRestoringFromBackground || needsForegroundVideoRestore {
            return false
        }
        if isHoldingOutgoingPicture {
            return true
        }
        if isSwitchingSource && !isReplacingSourceItem {
            return true
        }
        if isResolving {
            return false
        }
        if firstFrameFallbackUnlocked {
            return true
        }
        return hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch
    }
}

/// Flicker-free `0-RTT` warm-start curtain presentation policy (`180 ms` pure-black grace).
///
/// - When launching a warm/prepared session (`prepareToken != nil` or `preparedSession != nil`)
///   without an active HDMI display-mode switch, holds pure `#000000` for up to `180 ms`:
///   if the first video frame is ready within `180 ms`, playback opens straight into video with
///   zero curtain flash; otherwise `ResolvingCurtainView` fades in smoothly (`0.22 s`).
/// - Cold starts and active HDMI mode switches (`isAwaitingDisplaySwitch == true`) present
///   `ResolvingCurtainView` immediately from `0 ms`.
public enum PlaybackCurtainPresentationPolicy: Sendable {
    public static let warmStartGraceMilliseconds: Int = 180
    public static let warmStartGraceNanoseconds: UInt64 = 180_000_000
    public static let curtainFadeInDurationSeconds: Double = 0.22

    public static func hasWarmPreparedSession(
        prepareToken: String?,
        hasPreparedSession: Bool
    ) -> Bool {
        if hasPreparedSession {
            return true
        }
        guard let trimmed = prepareToken?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !trimmed.isEmpty
    }

    public static func shouldHoldSilentBlackGrace(
        hasWarmPreparedSession: Bool,
        isAwaitingDisplaySwitch: Bool,
        isRestoringFromBackground: Bool = false,
        graceElapsed: Bool
    ) -> Bool {
        guard hasWarmPreparedSession,
              !isAwaitingDisplaySwitch,
              !isRestoringFromBackground,
              !graceElapsed else {
            return false
        }
        return true
    }

    public static func shouldShowCurtainContent(
        hasWarmPreparedSession: Bool,
        isAwaitingDisplaySwitch: Bool,
        isRestoringFromBackground: Bool = false,
        graceElapsed: Bool
    ) -> Bool {
        !shouldHoldSilentBlackGrace(
            hasWarmPreparedSession: hasWarmPreparedSession,
            isAwaitingDisplaySwitch: isAwaitingDisplaySwitch,
            isRestoringFromBackground: isRestoringFromBackground,
            graceElapsed: graceElapsed
        )
    }
}

/// Pure-Swift interval index for subtitle cue lookup supporting `O(1)` amortized monotonic
/// 10 Hz forward playback and `O(log N + k)` binary-search + `prefixMaxEnd` seek/delay jumps,
/// including overlapping ASS/SRT cues and invalid/NaN span filtering.
public struct SubtitleCueIndex: Sendable {
    private struct Entry: Sendable {
        let originalIndex: Int
        let startTime: Double
        let endTime: Double
    }

    private let entries: [Entry]
    private let prefixMaxEnd: [Double]
    private var lastQueryTime: Double?
    private var nextEntryIndex: Int = 0
    private var activeEntryIndices: [Int] = []

    public init<C: Sequence>(
        _ cues: C,
        startTime: (C.Element) -> Double,
        endTime: (C.Element) -> Double
    ) {
        var collected: [Entry] = []
        var isSortedByStart = true
        var prevStart = -Double.infinity
        var idx = 0

        for cue in cues {
            let start = startTime(cue)
            let end = endTime(cue)
            if start.isFinite, end.isFinite, end > start {
                if start < prevStart {
                    isSortedByStart = false
                }
                prevStart = start
                collected.append(Entry(originalIndex: idx, startTime: start, endTime: end))
            }
            idx += 1
        }

        if !isSortedByStart {
            collected.sort { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                if lhs.endTime != rhs.endTime {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.originalIndex < rhs.originalIndex
            }
        }

        var maxEnds = [Double](repeating: 0, count: collected.count)
        var runningMax = -Double.infinity
        for i in collected.indices {
            if collected[i].endTime > runningMax {
                runningMax = collected[i].endTime
            }
            maxEnds[i] = runningMax
        }

        self.entries = collected
        self.prefixMaxEnd = maxEnds
    }

    public mutating func activeOriginalIndices(at effectiveTime: Double) -> [Int] {
        guard effectiveTime.isFinite else {
            lastQueryTime = nil
            nextEntryIndex = 0
            activeEntryIndices.removeAll(keepingCapacity: true)
            return []
        }
        guard !entries.isEmpty else {
            lastQueryTime = effectiveTime
            return []
        }

        let canStepMonotonically: Bool = {
            guard let prev = lastQueryTime, effectiveTime >= prev else {
                return false
            }
            let lookaheadIndex = nextEntryIndex + 32
            return lookaheadIndex >= entries.count || entries[lookaheadIndex].startTime > effectiveTime
        }()

        if canStepMonotonically {
            if !activeEntryIndices.isEmpty {
                activeEntryIndices.removeAll { entries[$0].endTime <= effectiveTime }
            }
            while nextEntryIndex < entries.count && entries[nextEntryIndex].startTime <= effectiveTime {
                if entries[nextEntryIndex].endTime > effectiveTime {
                    activeEntryIndices.append(nextEntryIndex)
                }
                nextEntryIndex += 1
            }
            lastQueryTime = effectiveTime
        } else {
            let upper = upperBound(for: effectiveTime)
            var matched: [Int] = []
            if upper > 0 {
                var i = upper - 1
                while true {
                    if prefixMaxEnd[i] <= effectiveTime {
                        break
                    }
                    if entries[i].endTime > effectiveTime {
                        matched.append(i)
                    }
                    if i == 0 {
                        break
                    }
                    i -= 1
                }
                if matched.count > 1 {
                    matched.reverse()
                }
            }
            activeEntryIndices = matched
            nextEntryIndex = upper
            lastQueryTime = effectiveTime
        }

        if activeEntryIndices.isEmpty {
            return []
        }
        if activeEntryIndices.count == 1 {
            return [entries[activeEntryIndices[0]].originalIndex]
        }
        var result = activeEntryIndices.map { entries[$0].originalIndex }
        result.sort()
        return result
    }

    public func queryOriginalIndices(at effectiveTime: Double) -> [Int] {
        guard effectiveTime.isFinite, !entries.isEmpty else {
            return []
        }
        let upper = upperBound(for: effectiveTime)
        guard upper > 0 else { return [] }
        var result: [Int] = []
        var i = upper - 1
        while true {
            if prefixMaxEnd[i] <= effectiveTime {
                break
            }
            if entries[i].endTime > effectiveTime {
                result.append(entries[i].originalIndex)
            }
            if i == 0 {
                break
            }
            i -= 1
        }
        if result.count > 1 {
            result.sort()
        }
        return result
    }

    private func upperBound(for effectiveTime: Double) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = low + (high - low) / 2
            if entries[mid].startTime <= effectiveTime {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

public enum PlaybackErrorCategory: String, CaseIterable, Sendable, Equatable {
    case sourceOpenFailed
    case sourceRefused
    case sourceCertificateRejected
    case sourceFabricatesRanges
    case noPlayableTrackWithinBudget
    case vodSourceFailed
    case sourceRateLimited
    case audioBridgeProducedNoOutput
    case storageExhausted
    case unknown
}

public enum PlaybackErrorGuidancePolicy: Sendable {
    public static func userMessage(
        category: PlaybackErrorCategory,
        underlyingCode: Int? = nil,
        ffmpegErrorCode: Int? = nil,
        rawMessage: String
    ) -> String {
        switch category {
        case .sourceOpenFailed:
            if underlyingCode == 401 {
                return "Strømmen utløp eller ble avvist (HTTP 401). Prøv på nytt eller velg en annen utgave."
            }
            if underlyingCode == 403 {
                return "Ingen tilgang til videostrømmen (HTTP 403). Prøv på nytt."
            }
            if underlyingCode == 404 {
                return "Fant ikke videostrømmen på serveren (HTTP 404). Prøv en annen utgave."
            }
            if let underlyingCode, underlyingCode != 0 {
                return "Kunne ikke åpne videostrømmen (kode \(underlyingCode)). Prøv på nytt eller velg en annen utgave."
            }
            if let ffmpegErrorCode, ffmpegErrorCode != 0 {
                return "Kunne ikke åpne videostrømmen (kode \(ffmpegErrorCode)). Prøv på nytt eller velg en annen utgave."
            }
            return "Kunne ikke åpne videostrømmen. Prøv på nytt eller velg en annen utgave."
        case .sourceRefused:
            if underlyingCode == 401 {
                return "Strømmen utløp eller ble avvist (HTTP 401). Prøv på nytt eller velg en annen utgave."
            }
            if underlyingCode == 403 {
                return "Ingen tilgang til videostrømmen (HTTP 403). Prøv på nytt."
            }
            return "Videokilden avviste tilkoblingen. Prøv på nytt eller velg en annen utgave."
        case .sourceCertificateRejected:
            return "TLS-sertifikatet for videostrømmen ble avvist. Sjekk sertifikatvalget under Innstillinger."
        case .sourceFabricatesRanges:
            return "Videokilden støtter ikke pålitelig spoling/byte-ranges. Prøv en annen utgave."
        case .noPlayableTrackWithinBudget:
            return "Ingen spillbart video- eller lydspor ble funnet innenfor strømmebudsjettet. Velg en annen utgave."
        case .vodSourceFailed:
            return "Videostrømmen fra serveren feilet under avspilling. Prøv på nytt eller velg en annen utgave."
        case .sourceRateLimited:
            return "Videokilden begrenser forespørsler midlertidig (rate-limit). Vent litt eller velg en annen utgave."
        case .audioBridgeProducedNoOutput:
            return "Lydmotoren ga ingen lydutgang for dette sporet. Prøv et annet lydspor eller bytt høyttaleroppsett."
        case .storageExhausted:
            return "Lite ledig lagringsplass på Apple TV for videobuffer. Tøm hurtigbuffer i Innstillinger eller prøv en mindre utgave."
        case .unknown:
            return LunaCopy.friendlyEngineErrorMessage(rawMessage)
        }
    }
}

public struct ActiveUpscaleSummaryInfo: Sendable, Equatable {
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let targetWidth: Int
    public let targetHeight: Int
    public let scaler: UpscaleScalerPolicy
    public let mlScale: Double?
    public let isDegraded: Bool

    public init(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        scaler: UpscaleScalerPolicy,
        mlScale: Double? = nil,
        isDegraded: Bool = false
    ) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.scaler = scaler
        self.mlScale = mlScale
        self.isDegraded = isDegraded
    }
}

public enum UpscaleSummaryFormatter: Sendable {
    public static func summary(
        activeUpscale: ActiveUpscaleSummaryInfo?,
        disabledReason: String?,
        lowResUpscaleMode: LowResUpscaleMode,
        upscalesFullHDVideo: Bool,
        isSDR: Bool,
        sourceVideoWidth: Int,
        sourceVideoHeight: Int
    ) -> String {
        let trimmedReason = disabledReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeReason = (trimmedReason?.isEmpty == false) ? trimmedReason : nil

        if let up = activeUpscale, activeReason == nil {
            let stageLabel: String
            switch up.scaler {
            case .lineArt:
                stageLabel = "Anime4K 2×"
            case .lanczos:
                stageLabel = "Lanczos"
            case .automatic:
                if let ml = up.mlScale, ml.isFinite, ml > 1.01 {
                    let factor: String
                    if ml == ml.rounded(), let intScale = Int(exactly: ml) {
                        factor = "\(intScale)×"
                    } else {
                        factor = "\(LunaCopy.formatDecimal(ml, decimals: 1))×"
                    }
                    stageLabel = up.isDegraded ? "ANE \(factor)" : "ANE \(factor) + MetalFX"
                } else {
                    stageLabel = "MetalFX"
                }
            }
            return "\(up.sourceWidth)×\(up.sourceHeight) → \(up.targetWidth)×\(up.targetHeight) (\(stageLabel))"
        }

        if lowResUpscaleMode == .off && !upscalesFullHDVideo {
            return "Nativ (Av)"
        }
        if let activeReason {
            return "Nativ (\(activeReason))"
        }
        if !isSDR {
            return "Nativ (HDR-fallback)"
        }
        if sourceVideoHeight >= 1440 || sourceVideoWidth >= 2560 {
            return "Nativ (4K-kilde)"
        }

        let isFullHD = sourceVideoHeight >= 1080 || sourceVideoWidth >= 1920
        let isSub1080p = (sourceVideoWidth > 0 || sourceVideoHeight > 0) && !isFullHD
        switch lowResUpscaleMode {
        case .animeLineArt:
            return "Nativ (Venter på ≤ 1080p SDR)"
        case .auto:
            if upscalesFullHDVideo {
                return "Nativ (Venter på ≤ 1080p SDR)"
            }
            return isFullHD ? "Nativ (1080p-oppskalering av)" : "Nativ (Venter på < 1080p SDR)"
        case .off:
            return isSub1080p ? "Nativ (< 1080p-oppskalering av)" : "Nativ (Venter på 1080p SDR)"
        }
    }
}

public enum PlaybackPrewarmBudgetPolicy: Sendable {
    public static func isFastLocalTier(source: String?, tier: String?) -> Bool {
        let sourceLower = (source ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if sourceLower.contains("easynews") {
            return false
        }
        let trimmedTier = tier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTierOrSource = (trimmedTier?.isEmpty == false ? trimmedTier : nil) ?? source ?? ""
        let tierLower = effectiveTierOrSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if tierLower.isEmpty {
            return true
        }
        return tierLower == "ssd" || tierLower == "nvme" || tierLower == "local"
    }

    public static func nextEpisodeByteBudget(
        source: String?,
        tier: String?,
        memoryProfile: DeviceMemoryProfile = DeviceMemoryProfile.current,
        availableMemoryBytes: UInt64 = DeviceHardwareCapabilities.availableMemoryBytes()
    ) -> Int {
        memoryProfile.prewarmByteBudget(
            availableMemoryBytes: availableMemoryBytes,
            isFastLocalTier: isFastLocalTier(source: source, tier: tier)
        )
    }
}

public enum AudioBinauralStatus: String, Equatable, Sendable {
    case inactive
    case active
    case suppressedByStereo
}

/// Pure-Swift resolution of headphone binaural spatialization vs explicit/auto Stereo 2.0.
public enum AudioBinauralPolicy: Sendable {
    public static func resolveStatus(
        isBinauralRouteActive: Bool,
        effectiveSpeakerLayout: String
    ) -> AudioBinauralStatus {
        guard isBinauralRouteActive else { return .inactive }
        if effectiveSpeakerLayout.trimmingCharacters(in: .whitespacesAndNewlines) == "2.0" {
            return .suppressedByStereo
        }
        return .active
    }

    public static func effectiveBinauralFlag(
        isBinauralRouteActive: Bool,
        effectiveSpeakerLayout: String
    ) -> Bool {
        resolveStatus(
            isBinauralRouteActive: isBinauralRouteActive,
            effectiveSpeakerLayout: effectiveSpeakerLayout
        ) == .active
    }

    public static func quickPanelNotice(for status: AudioBinauralStatus) -> String? {
        switch status {
        case .inactive:
            return nil
        case .active:
            return "Hodetelefoner · Binaural romlyd aktiv"
        case .suppressedByStereo:
            return "Hodetelefoner · Binaural av (Stereo 2.0 valgt)"
        }
    }
}

/// Pure-Swift `NerdHUDView` audio chain line formatter (mirroring `UpscaleSummaryFormatter`).
public enum AudioChainSummaryFormatter: Sendable {
    public static func summary(
        speakerLayoutOverride: SpeakerLayoutOverrideMode,
        sessionRoomAutoLayout: String,
        audioFormatBadge: String,
        audioDecoderLabel: String,
        audioEnhancement: AudioEnhancementMode,
        audioDelayDisplay: String?,
        binauralStatus: AudioBinauralStatus
    ) -> String {
        let setup: String = {
            switch speakerLayoutOverride {
            case .auto: return "Auto \(sessionRoomAutoLayout)"
            case .atmos512: return "5.1.2"
            case .atmos714: return "7.1.4"
            case .stereo: return "Stereo 2.0"
            }
        }()
        let formatPart: String = {
            if audioFormatBadge == setup || (audioFormatBadge == "Stereo 2.0" && setup == "Stereo 2.0") {
                return setup
            }
            if speakerLayoutOverride == .auto,
               audioFormatBadge.hasPrefix(sessionRoomAutoLayout) {
                return "Auto \(audioFormatBadge)"
            }
            if audioFormatBadge.hasPrefix(setup) {
                return audioFormatBadge
            }
            return "\(setup) · \(audioFormatBadge)"
        }()
        let binauralPart: String = {
            switch binauralStatus {
            case .inactive: return ""
            case .active: return " · Binaural"
            case .suppressedByStereo: return " · Binaural av (2.0)"
            }
        }()
        let modePart = audioEnhancement == .reference ? "" : " · \(audioEnhancement.displayTitle)"
        let delayPart = (audioDelayDisplay?.isEmpty == false) ? " · \(audioDelayDisplay!)" : ""
        return "\(formatPart) (\(audioDecoderLabel))\(binauralPart)\(modePart)\(delayPart)"
    }
}

public enum PlaybackStallPhaseKind: Equatable, Sendable {
    case normal
    case loadingOrSeeking
    case rebuffering
    case stalled
}

/// Per-session playback stall episode counter deduplicating `.rebuffering` -> `.stalled`
/// and suppressing expected startup/seek/resolve/switch/restore transitions.
public struct PlaybackStallCounter: Equatable, Sendable {
    public private(set) var stallCount: Int = 0
    private var isStallEpisodeActive: Bool = false
    private var isLoadingOrSeekingRebuffer: Bool = false

    public init() {}

    public mutating func reset() {
        stallCount = 0
        isStallEpisodeActive = false
        isLoadingOrSeekingRebuffer = false
    }

    public mutating func recordTransition(
        from previous: PlaybackStallPhaseKind,
        to next: PlaybackStallPhaseKind,
        suppressCounting: Bool
    ) {
        if suppressCounting {
            switch next {
            case .normal, .loadingOrSeeking:
                isStallEpisodeActive = false
                isLoadingOrSeekingRebuffer = false
            case .stalled:
                isLoadingOrSeekingRebuffer = false
            case .rebuffering:
                break
            }
            return
        }

        switch next {
        case .stalled:
            isLoadingOrSeekingRebuffer = false
            if !isStallEpisodeActive {
                stallCount += 1
                isStallEpisodeActive = true
            }
        case .rebuffering:
            if previous == .loadingOrSeeking || isLoadingOrSeekingRebuffer {
                isLoadingOrSeekingRebuffer = true
            } else if !isStallEpisodeActive {
                stallCount += 1
                isStallEpisodeActive = true
            }
        case .normal, .loadingOrSeeking:
            isStallEpisodeActive = false
            isLoadingOrSeekingRebuffer = false
        }
    }
}

/// Fail-closed policy enabling `LoadOptions.generatesBackgroundScrubPreviews` exclusively
/// for `.high2026` Apple TV 4K on fast local NVMe/SSD non-FEL hardware-decoded streams
/// with healthy RAM headroom (protecting 4 GB devices, archive spindown, VFS, and Easynews).
public enum BackgroundScrubPreviewPolicy: Sendable {
    private static let forbiddenTierOrSourceTokens: [String] = [
        "archive",
        "vfs",
        "infinidysk",
        "easynews",
        "usenet",
        "nzb",
        "remote",
        "http",
    ]

    public static func isFastLocalNVMeTier(source: String?, tier: String?) -> Bool {
        let sourceLower = (source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tierLower = (tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for token in forbiddenTierOrSourceTokens {
            if sourceLower.contains(token) || tierLower.contains(token) {
                return false
            }
        }
        let effective = tierLower.isEmpty ? sourceLower : tierLower
        return effective == "nvme" || effective == "ssd"
    }

    public static func shouldGenerate(
        memoryTier: DeviceMemoryTier,
        availableMemoryBytes: UInt64,
        playbackMemoryShedFloorBytes: UInt64,
        source: String?,
        tier: String?,
        supportsByteRanges: Bool?,
        preferDualLayerDolbyVision: Bool,
        dvProfile: Int?,
        dvEnhancementLayer: String?,
        requiresSoftwareVideoDecode: Bool,
        serverConfigured: Bool?
    ) -> Bool {
        guard memoryTier == .high2026 else { return false }
        guard availableMemoryBytes >= playbackMemoryShedFloorBytes else { return false }
        guard serverConfigured != false else { return false }
        guard supportsByteRanges != false else { return false }
        guard isFastLocalNVMeTier(source: source, tier: tier) else { return false }
        guard !preferDualLayerDolbyVision else { return false }

        let layerUpper = (dvEnhancementLayer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if layerUpper == "FEL" {
            return false
        }
        if dvProfile == 7 && layerUpper != "MEL" && layerUpper != "NONE" {
            return false
        }
        guard !requiresSoftwareVideoDecode else { return false }
        return true
    }
}
