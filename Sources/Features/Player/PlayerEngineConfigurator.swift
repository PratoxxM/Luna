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

    var effectiveSpeakerLayoutLabel: String {
        effectiveSpeakerLayoutLabel(isDTSX: false)
    }

    private func effectiveSpeakerLayoutLabel(isDTSX: Bool) -> String {
        if comfort.speakerLayoutOverride == .stereo {
            return "Stereo 2.0"
        }
        if let lay = activeSession?.aetherConfig.objectAudioRendering?.layout, !lay.isEmpty {
            return (lay == "5.1.2" && isDTSX) ? "7.1.4" : lay
        }
        return "7.1.4"
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
        displayCapabilities: DisplayCapabilities = AetherEngine.displayCapabilities,
        memoryProfile: DeviceMemoryProfile = DeviceHardwareCapabilities.memoryProfile,
        availableMemoryBytes: UInt64 = DeviceHardwareCapabilities.availableMemoryBytes()
    ) -> LoadOptions {
        let cfg = session.aetherConfig
        var options = LoadOptions()

        options.autoplay = autoplay
        options.httpHeaders = client.streamHTTPHeaders()

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

        options.dualLayerRoute = cfg.dualLayerRoute == "avPlayerOutput" ? .avPlayerOutput : .softwareHost
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

        switch comfort.speakerLayoutOverride {
        case .stereo:
            options.objectAudioRendering = .off
        case .auto:
            if let obj = cfg.objectAudioRendering {
                let layout = Self.mapSpeakerLayout(obj.layout)
                switch obj.mode.lowercased() {
                case "off":
                    options.objectAudioRendering = .off
                case "apac":
                    options.objectAudioRendering = .apac(layout)
                case "lpcm":
                    options.objectAudioRendering = .lpcm(layout)
                default:
                    options.objectAudioRendering = .render(layout)
                }
            } else {
                options.objectAudioRendering = .render(.l714)
            }
        }

        options.preferredAudioLanguages = cfg.preferredAudioLanguages ?? ["nob", "nor", "no", "eng"]
        // When smart Nordic rule is enabled, let SmartTrackRuleEngine evaluate tracks once loaded
        // so Norwegian audio never flashes an initial subtitle before clearSubtitles() runs.
        options.preferredSubtitleLanguages = comfort.smartNordicSubtitleRule
            ? []
            : (cfg.preferredSubtitleLanguages ?? ["nob", "nor", "no", "eng"])
        options.skipsContainerAttachments = cfg.skipsContainerAttachments ?? true
        options.generatesBackgroundScrubPreviews = cfg.generatesBackgroundScrubPreviews ?? false
        options.serveIFramePlaylist = cfg.serveIFramePlaylist ?? false
        options.confirmAtmos = cfg.confirmAtmos ?? (memoryProfile.tier == .high2026)

        let tierLower = (session.selectedCandidate.tier ?? session.selectedCandidate.source)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isFastLocalTier = (tierLower == "ssd" || tierLower == "nvme" || tierLower == "local")
        let isSameOrigin: Bool = {
            guard let resolvedStreamURL = client.buildAbsoluteURL(session.stream.url) else {
                return true
            }
            return client.isSameOrigin(resolvedStreamURL)
        }()
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
                httpHeaders: client.streamHTTPHeaders(),
                formatHint: sub.formatHint ?? sub.format ?? "srt"
            )
        }
        options.externalSubtitles = extSubs

        return options
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
}
