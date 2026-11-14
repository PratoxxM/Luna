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
        let configuredLayout = effectiveSpeakerLayoutLabel
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
        if comfort.speakerLayoutOverride != .auto {
            return comfort.speakerLayoutOverride.rawValue
        }
        if let lay = activeSession?.aetherConfig.objectAudioRendering?.layout, !lay.isEmpty {
            return lay
        }
        return activeSession?.hardwareProfile == "hdr10-512" ? "5.1.2" : "7.1.4"
    }

    // MARK: - AetherEngine LoadOptions

    static func buildLoadOptions(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        comfort: ComfortPreferences,
        audioEnhancement: AudioEnhancementMode,
        audioDelaySeconds: Double
    ) -> LoadOptions {
        let cfg = session.aetherConfig
        var options = LoadOptions()

        options.httpHeaders = client.streamHTTPHeaders()

        switch comfort.dualLayerOverride {
        case .auto:
            options.preferDualLayerDolbyVision = cfg.preferDualLayerDolbyVision
            options.foldsDolbyVisionFEL = cfg.foldsDolbyVisionFEL ?? true
            options.dolbyVisionHandling = cfg.dolbyVisionHandling == "baseLayerOnly" ? .baseLayerOnly : .automatic
        case .forceOn:
            options.preferDualLayerDolbyVision = true
            options.foldsDolbyVisionFEL = true
            options.dolbyVisionHandling = .automatic
        case .forceOff:
            options.preferDualLayerDolbyVision = false
            options.foldsDolbyVisionFEL = false
            options.dolbyVisionHandling = .baseLayerOnly
        }

        options.dualLayerRoute = cfg.dualLayerRoute == "avPlayerOutput" ? .avPlayerOutput : .softwareHost
        options.matchContentEnabled = cfg.matchContentEnabled
        options.displayCriteriaOwner = .engine
        options.attemptsHDRMasterOnUnprovenPanel = cfg.attemptsHDRMasterOnUnprovenPanel ?? false

        // Let AetherEngine inspect HDMI capabilities directly via AVPlayer.availableHDRModes
        options.panelPresentsDolbyVision = false
        options.panelIsInHDRMode = false

        options.audioBridgeMode = cfg.audioBridgeMode == "lossless" ? .lossless : .surroundCompat
        options.audioDelaySeconds = audioDelaySeconds
        options.audioShaping = comfort.buildAudioShaping(enhancement: audioEnhancement)

        switch comfort.speakerLayoutOverride {
        case .stereo:
            options.objectAudioRendering = .off
        case .l714:
            options.objectAudioRendering = .render(.l714)
        case .l512:
            options.objectAudioRendering = .render(.l512)
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
        options.confirmAtmos = cfg.confirmAtmos ?? false
        options.maxConcurrentSourceRequests = cfg.maxConcurrentSourceRequests ?? 2
        options.declaredDurationSeconds = cfg.declaredDurationSeconds ?? session.stream.declaredDurationSeconds

        switch comfort.lowResUpscaleMode {
        case .off:
            options.upscalesLowResolutionVideo = false
        case .auto:
            options.upscalesLowResolutionVideo = true
            options.upscaleScaler = .automatic
        case .animeLineArt:
            options.upscalesLowResolutionVideo = true
            options.upscaleScaler = .lineArt
        }

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

    private static func mapSpeakerLayout(_ raw: String?) -> SpatialSpeakerLayout {
        switch raw {
        case "7.1.4": return .l714
        case "7.1.2": return .l712
        case "5.1.4": return .l514
        case "9.1.6": return .l916
        default: return .l512
        }
    }
}
