import Foundation
import AetherBridge

extension PlayerViewModel {
    // MARK: - Live Format Badges

    var videoFormatBadge: String {
        switch videoFormat {
        case .dolbyVision:
            if sourceDVProfile == 7 {
                if videoRoute == .software && dolbyVisionConversion == nil {
                    return "DV P7 FEL"
                }
                return "DV P7"
            }
            if sourceDVProfile == 8 || dolbyVisionConversion == .profile7ToProfile81 {
                return "DV P8"
            }
            if let p = sourceDVProfile {
                return "DV P\(p)"
            }
            return "Dolby Vision"
        case .hdr10Plus:
            return "HDR10+"
        case .hdr10:
            return "HDR10"
        case .hlg:
            return "HLG"
        case .sdr:
            return sourceVideoHeight >= 2000 ? "4K SDR" : "SDR"
        }
    }

    var audioFormatBadge: String {
        if comfort.speakerLayoutOverride == .stereo {
            return "Stereo 2.0"
        }
        let activeTrack = audioTracks.first(where: { $0.id == activeAudioTrackIndex })
        let configuredLayout = effectiveSpeakerLayoutLabel(isDTSX: activeTrack?.isDTSX == true)
        if let activeTrack {
            if activeTrack.isAtmos {
                return "\(configuredLayout) Atmos"
            }
            if activeTrack.isDTSX {
                return "\(configuredLayout) DTS:X"
            }
            let codecUpper = activeTrack.codec.uppercased()
            if codecUpper.contains("TRUEHD") {
                return "TrueHD \(activeTrack.channelLayout ?? "7.1")"
            }
            if codecUpper.contains("DTS") || codecUpper.contains("DCA") {
                return "\(activeTrack.profile ?? "DTS-HD") \(activeTrack.channelLayout ?? "")"
                    .trimmingCharacters(in: .whitespaces)
            }
            if audioDelivery == .bridged {
                return "LPCM \(activeTrack.channelLayout ?? "")".trimmingCharacters(in: .whitespaces)
            }
            return "\(codecUpper) \(activeTrack.channelLayout ?? "")".trimmingCharacters(in: .whitespaces)
        }
        return configuredLayout
    }

    var sessionRoomAutoLayout: String {
        if let lay = activeSession?.aetherConfig.objectAudioRendering?.layout, !lay.isEmpty {
            return lay
        }
        if activeSession?.hardwareProfile == HardwareProfilePreset.hdr10512.rawValue {
            return "5.1.2"
        }
        return "7.1.4"
    }

    private func effectiveSpeakerLayoutLabel(isDTSX: Bool) -> String {
        switch comfort.speakerLayoutOverride {
        case .stereo:
            return "Stereo 2.0"
        case .atmos512:
            return isDTSX ? "7.1.4" : "5.1.2"
        case .atmos714:
            return "7.1.4"
        case .auto:
            let base = sessionRoomAutoLayout
            return (base == "5.1.2" && isDTSX) ? "7.1.4" : base
        }
    }

    // MARK: - AetherEngine LoadOptions

    nonisolated static func untaggedVideoColorHint(for candidate: TvCandidateInfo) -> UntaggedVideoColor {
        if candidate.dvProfile != nil {
            return .standard
        }
        let range = (candidate.videoRangeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !range.isEmpty, !range.contains("dv"), !range.contains("dolby") else {
            return .standard
        }
        if range.contains("hlg") {
            return .hlg
        }
        if range.contains("hdr10") || range == "hdr" || range.contains("pq") {
            return .hdr10
        }
        return .standard
    }

    static func buildLoadOptions(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        comfort: ComfortPreferences,
        audioEnhancement: AudioEnhancementMode,
        audioDelaySeconds: Double,
        autoplay: Bool = true,
        suppressInitialSubtitleSelection: Bool = false,
        displayCapabilities: DisplayCapabilities = AetherEngine.displayCapabilities,
        memoryProfile: DeviceMemoryProfile = DeviceHardwareCapabilities.memoryProfile,
        availableMemoryBytes: UInt64 = DeviceHardwareCapabilities.availableMemoryBytes()
    ) -> LoadOptions {
        let cfg = session.aetherConfig
        var options = LoadOptions()

        let resolvedStreamURL = client.buildAbsoluteURL(session.stream.url)
        options.autoplay = autoplay
        options.httpHeaders = resolvedStreamURL.map { client.streamHTTPHeaders(for: $0) } ?? client.streamHTTPHeaders()

        switch comfort.dualLayerOverride {
        case .auto:
            let allowsDualLayer = session.selectedCandidate.canCarryDualLayerDolbyVision
            options.preferDualLayerDolbyVision = cfg.preferDualLayerDolbyVision && allowsDualLayer
            options.foldsDolbyVisionFEL = (cfg.foldsDolbyVisionFEL ?? true) && allowsDualLayer
            options.dolbyVisionHandling = cfg.dolbyVisionHandling == "baseLayerOnly" ? .baseLayerOnly : .automatic
        case .forceOn:
            let allowsForced = session.selectedCandidate.allowsDualLayerDolbyVisionWhenForced
            options.preferDualLayerDolbyVision = allowsForced
            options.foldsDolbyVisionFEL = allowsForced
            options.dolbyVisionHandling = .automatic
        case .forceOff:
            options.preferDualLayerDolbyVision = false
            options.foldsDolbyVisionFEL = false
            options.dolbyVisionHandling = .baseLayerOnly
        }

        let panelLacksDolbyVision = !displayCapabilities.supportsDolbyVision
            || session.hardwareProfile == HardwareProfilePreset.hdr10512.rawValue
        if panelLacksDolbyVision {
            options.preferDualLayerDolbyVision = false
            options.foldsDolbyVisionFEL = false
            options.dolbyVisionHandling = .baseLayerOnly
        }

        options.dualLayerRoute = .softwareHost
        options.matchContentEnabled = cfg.matchContentEnabled
        options.displayCriteriaOwner = .engine
        options.untaggedVideoColor = Self.untaggedVideoColorHint(for: session.selectedCandidate)
        options.inverseTelecine = .auto
        options.attemptsHDRMasterOnUnprovenPanel = cfg.attemptsHDRMasterOnUnprovenPanel ?? true
        options.preferHDR10PlusOverForcedDolbyVision =
            (session.hardwareProfile == HardwareProfilePreset.hdr10512.rawValue)
            || (!displayCapabilities.supportsDolbyVision && displayCapabilities.supportsHDR10)

        // Let AetherEngine inspect HDMI capabilities directly via AVPlayer.availableHDRModes
        options.panelPresentsDolbyVision = false
        options.panelIsInHDRMode = false

        options.audioBridgeMode = cfg.audioBridgeMode == "lossless" ? .lossless : .surroundCompat
        options.audioDelaySeconds = audioDelaySeconds
        options.audioShaping = comfort.buildAudioShaping(enhancement: audioEnhancement)
        Self.applySpeakerLayoutOverride(comfort.speakerLayoutOverride, session: session, to: &options)

        options.preferredAudioLanguages = cfg.preferredAudioLanguages ?? ["nob", "nor", "no", "eng"]
        // When smart Nordic rule is enabled or an in-place source switch carries explicit track intent,
        // evaluate/select subtitles deterministically right after load so no unwanted initial subtitle flashes.
        options.preferredSubtitleLanguages = (comfort.smartNordicSubtitleRule || suppressInitialSubtitleSelection)
            ? []
            : (cfg.preferredSubtitleLanguages ?? ["nob", "nor", "no", "eng"])
        options.skipsContainerAttachments = cfg.skipsContainerAttachments ?? true
        if options.preferDualLayerDolbyVision && memoryProfile.tier == .standard {
            options.generatesBackgroundScrubPreviews = false
        } else {
            options.generatesBackgroundScrubPreviews = cfg.generatesBackgroundScrubPreviews ?? false
        }
        options.serveIFramePlaylist = cfg.serveIFramePlaylist ?? false
        options.confirmAtmos = cfg.confirmAtmos ?? (memoryProfile.tier == .high2026)

        let sourceLower = session.selectedCandidate.source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isEasynews = sourceLower.contains("easynews")
        let tierLower = (session.selectedCandidate.tier ?? session.selectedCandidate.source)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isFastLocalTier = !isEasynews && (tierLower == "ssd" || tierLower == "nvme" || tierLower == "local")
        let isSameOrigin = resolvedStreamURL.map { client.isSameOrigin($0) } ?? true
        options.maxConcurrentSourceRequests = memoryProfile.maxConcurrentSourceRequests(
            isFastLocalTier: isFastLocalTier,
            isSameOrigin: isSameOrigin,
            serverConfigured: cfg.maxConcurrentSourceRequests
        )
        options.progressiveSegmentDelivery = true
        options.sessionCacheByteBudget = memoryProfile.sessionCacheByteBudget
        options.sessionCacheFreeReserveBytes = memoryProfile.sessionCacheFreeReserveBytes
        options.retainsSessionCacheAfterStop = memoryProfile.retainsSessionCacheAfterStop(
            availableMemoryBytes: availableMemoryBytes
        )
        options.forwardBufferSegments = memoryProfile.forwardBufferSegments(
            availableMemoryBytes: availableMemoryBytes
        )
        options.declaredDurationSeconds = cfg.declaredDurationSeconds ?? session.stream.declaredDurationSeconds

        Self.applyLowResUpscaleMode(comfort.lowResUpscaleMode, to: &options)

        let extSubs: [ExternalSubtitleTrack] = (session.tracks?.externalSubtitles ?? []).compactMap { sub in
            guard let fullURL = client.buildAbsoluteURL(sub.url) else { return nil }
            return ExternalSubtitleTrack(
                url: fullURL,
                name: sub.name,
                language: sub.language,
                isForced: sub.isForced ?? false,
                isHearingImpaired: sub.isHearingImpaired ?? false,
                isDefault: sub.isDefault ?? false,
                httpHeaders: client.streamHTTPHeaders(for: fullURL),
                formatHint: sub.format ?? "srt"
            )
        }
        options.externalSubtitles = extSubs

        return options
    }

    nonisolated static func applySpeakerLayoutOverride(
        _ overrideMode: SpeakerLayoutOverrideMode,
        session: TvPlaybackSession?,
        to options: inout LoadOptions
    ) {
        if overrideMode == .stereo {
            options.objectAudioRendering = .off
            return
        }
        let cfgObj = session?.aetherConfig.objectAudioRendering
        let targetLayout: SpatialSpeakerLayout = {
            switch overrideMode {
            case .atmos512:
                return .l512
            case .atmos714:
                return .l714
            case .auto, .stereo:
                if let explicit = cfgObj?.layout, !explicit.isEmpty {
                    return mapSpeakerLayout(explicit)
                }
                return session?.hardwareProfile == HardwareProfilePreset.hdr10512.rawValue ? .l512 : .l714
            }
        }()
        if let cfgObj {
            switch cfgObj.mode.lowercased() {
            case "off" where overrideMode == .auto:
                options.objectAudioRendering = .off
            case "apac":
                options.objectAudioRendering = .apac(targetLayout)
            case "lpcm":
                options.objectAudioRendering = .lpcm(targetLayout)
            default:
                options.objectAudioRendering = .render(targetLayout)
            }
        } else {
            options.objectAudioRendering = .render(targetLayout)
        }
    }

    nonisolated static func applyLowResUpscaleMode(_ mode: LowResUpscaleMode, to options: inout LoadOptions) {
        switch mode {
        case .off:
            options.upscalesLowResolutionVideo = false
        case .auto:
            options.upscalesLowResolutionVideo = true
            options.upscaleScaler = .automatic
        case .animeLineArt:
            options.upscalesLowResolutionVideo = true
            options.upscaleScaler = .lineArt
        }
    }

    nonisolated static func mapSpeakerLayout(_ raw: String?) -> SpatialSpeakerLayout {
        switch raw {
        case "5.1.2": return .l512
        case "5.1.4": return .l514
        case "7.1.2": return .l712
        case "9.1.6": return .l916
        default: return .l714
        }
    }

    nonisolated static func isLikelyHeavySoftwareSession(
        _ session: TvPlaybackSession?,
        dualLayerOverride: DualLayerOverrideMode = .auto,
        lowResUpscaleMode: LowResUpscaleMode = .off,
        supportsHardwareAV1: Bool = DeviceHardwareCapabilities.supportsHardwareAV1
    ) -> Bool {
        guard let session else { return false }
        let candidate = session.selectedCandidate
        if candidate.requiresSoftwareVideoDecode(supportsHardwareAV1: supportsHardwareAV1) {
            return true
        }
        let forceBaseLayerOnly = (dualLayerOverride == .forceOff)
            || (session.aetherConfig.dolbyVisionHandling == "baseLayerOnly" && dualLayerOverride != .forceOn)
        if !forceBaseLayerOnly {
            let layerUpper = (candidate.dvEnhancementLayer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if dualLayerOverride == .forceOn && candidate.allowsDualLayerDolbyVisionWhenForced {
                if candidate.dvProfile == 7
                    || layerUpper == "FEL"
                    || (candidate.dvProfile == nil && candidate.canCarryDualLayerDolbyVision) {
                    return true
                }
            } else if session.aetherConfig.preferDualLayerDolbyVision && candidate.canCarryDualLayerDolbyVision {
                if candidate.dvProfile == 7 || layerUpper == "FEL" {
                    return true
                }
            }
        }
        if lowResUpscaleMode != .off && candidate.isLikelyLowResolutionSDRForUpscale {
            return true
        }
        return false
    }

    nonisolated static func canDirectMountPreparedSession(
        _ request: PlaybackLaunchRequest,
        candidateSession: TvPlaybackSession? = nil
    ) -> Bool {
        guard request.candidateId == nil,
              let prep = candidateSession ?? request.preparedSession,
              !prep.sessionId.isEmpty,
              !prep.stream.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if let reqStart = request.startPositionSeconds,
           let prepStart = prep.stream.startPositionSeconds {
            return abs(max(0, reqStart) - max(0, prepStart)) <= 1.5
        }
        return true
    }

    func curtainPreservedURLs(
        request: PlaybackLaunchRequest,
        session: TvPlaybackSession?,
        client: LunaCoreClient
    ) -> [URL] {
        let backdropRaw = request.backdropUrl ?? session?.item.backdropUrl ?? request.preparedSession?.item.backdropUrl
        let logoRaw = session?.item.logoUrl ?? request.logoUrl ?? request.preparedSession?.item.logoUrl
        return [
            client.resolveArtworkURL(backdropRaw, target: .hero4K),
            client.resolveArtworkURL(logoRaw),
        ].compactMap { $0 }
    }

    nonisolated static func shouldPauseEngineOnDismiss(
        engineState: PlaybackState,
        playbackPhase: PlaybackPhase
    ) -> Bool {
        switch engineState {
        case .playing, .loading, .seeking:
            return true
        case .paused, .idle, .ended, .error:
            break
        }
        switch playbackPhase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            return true
        case .paused, .idle, .ended, .error:
            return false
        }
    }
}
