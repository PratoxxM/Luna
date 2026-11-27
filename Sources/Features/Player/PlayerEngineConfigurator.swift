import Foundation
import AetherBridge

/// Pure `AetherEngine` `LoadOptions`, speaker-layout, MetalFX, and capability helpers.
@MainActor
enum PlayerEngineConfigurator {
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

    nonisolated static func externalSubtitleTracks(
        for session: TvPlaybackSession,
        client: LunaCoreClient
    ) -> [ExternalSubtitleTrack] {
        (session.tracks?.externalSubtitles ?? []).compactMap { sub in
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
    }

    static func buildLoadOptions(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        comfort: ComfortPreferences,
        audioEnhancement: AudioEnhancementMode,
        audioDelaySeconds: Double,
        autoplay: Bool = true,
        suppressInitialSubtitleSelection: Bool = false,
        preferNorwegianAudio: Bool = false,
        binauralAudioActive: Bool = false,
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
        options.untaggedVideoColor = untaggedVideoColorHint(for: session.selectedCandidate)
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
        let effectiveLayout = resolvedEffectiveSpeakerLayout(
            comfortSpeakerLayoutOverride: comfort.speakerLayoutOverride,
            comfortEffectiveSpeakerLayout: comfort.effectiveSpeakerLayout,
            session: session
        )
        let effectiveBinaural = AudioBinauralPolicy.effectiveBinauralFlag(
            isBinauralRouteActive: binauralAudioActive,
            effectiveSpeakerLayout: effectiveLayout
        )
        options.audioShaping = comfort.buildAudioShaping(
            enhancement: audioEnhancement,
            binaural: effectiveBinaural,
            effectiveSpeakerLayoutOverride: effectiveLayout
        )
        applySpeakerLayoutOverride(
            comfort.speakerLayoutOverride,
            effectiveSpeakerLayout: effectiveLayout,
            session: session,
            to: &options
        )

        if preferNorwegianAudio || session.item.originalLanguage != nil {
            options.preferredAudioLanguages = OriginalLanguageTrackSelector.preferredAudioLanguageCodes(
                forOriginalLanguage: session.item.originalLanguage,
                preferNorwegianAudio: preferNorwegianAudio
            )
        } else {
            options.preferredAudioLanguages = cfg.preferredAudioLanguages ?? ["nob", "nor", "no", "eng"]
        }

        // When smart Nordic rule is enabled or an in-place source switch carries explicit track intent,
        // evaluate/select subtitles deterministically right after load so no unwanted initial subtitle flashes.
        options.preferredSubtitleLanguages = (comfort.smartNordicSubtitleRule || suppressInitialSubtitleSelection)
            ? []
            : (cfg.preferredSubtitleLanguages ?? ["nob", "nor", "no", "eng"])
        options.skipsContainerAttachments = false
        options.readsContainerAttachmentsAtOpen = false
        options.recognizesBitmapSubtitleText = comfort.effectiveRecognizesBitmapSubtitleText(
            memoryTier: memoryProfile.tier
        )
        options.generatesBackgroundScrubPreviews = BackgroundScrubPreviewPolicy.shouldGenerate(
            memoryTier: memoryProfile.tier,
            availableMemoryBytes: availableMemoryBytes,
            playbackMemoryShedFloorBytes: memoryProfile.playbackMemoryShedFloorBytes,
            source: session.selectedCandidate.source,
            tier: session.selectedCandidate.tier,
            supportsByteRanges: session.stream.supportsByteRanges,
            preferDualLayerDolbyVision: options.preferDualLayerDolbyVision,
            dvProfile: session.selectedCandidate.dvProfile,
            dvEnhancementLayer: session.selectedCandidate.dvEnhancementLayer,
            requiresSoftwareVideoDecode: session.selectedCandidate.requiresSoftwareVideoDecode(),
            serverConfigured: cfg.generatesBackgroundScrubPreviews
        )
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

        applyUpscaleSettings(
            lowResMode: comfort.lowResUpscaleMode,
            upscalesFullHDVideo: comfort.upscalesFullHDVideo,
            to: &options
        )
        options.externalSubtitles = externalSubtitleTracks(for: session, client: client)

        return options
    }

    nonisolated static func resolvedEffectiveSpeakerLayout(
        comfortSpeakerLayoutOverride: SpeakerLayoutOverrideMode,
        comfortEffectiveSpeakerLayout: String,
        session: TvPlaybackSession?
    ) -> String {
        if comfortSpeakerLayoutOverride == .auto,
           let sessionLayout = session?.aetherConfig.objectAudioRendering?.layout?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionLayout.isEmpty {
            return sessionLayout
        }
        return comfortEffectiveSpeakerLayout
    }

    nonisolated static func applySpeakerLayoutOverride(
        _ overrideMode: SpeakerLayoutOverrideMode,
        effectiveSpeakerLayout: String? = nil,
        session: TvPlaybackSession?,
        to options: inout LoadOptions
    ) {
        let resolvedLayout = effectiveSpeakerLayout
            ?? (overrideMode == .auto ? session?.aetherConfig.objectAudioRendering?.layout : nil)
        if overrideMode == .stereo
            || (overrideMode == .auto
                && resolvedLayout?.trimmingCharacters(in: .whitespacesAndNewlines) == "2.0") {
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

    struct ReloadComfortSnapshot {
        let lowResUpscaleMode: LowResUpscaleMode
        let upscalesFullHDVideo: Bool
        let speakerLayoutOverride: SpeakerLayoutOverrideMode
        let effectiveSpeakerLayout: String
        let dualLayerOverride: DualLayerOverrideMode
        let recognizesBitmapSubtitleText: Bool
        let audioDelaySeconds: Double
        let audioShaping: AudioShaping
    }

    static func captureReloadComfortSnapshot(
        comfort: ComfortPreferences,
        audioEnhancement: AudioEnhancementMode,
        audioDelaySeconds: Double,
        binauralAudioActive: Bool = false,
        session: TvPlaybackSession? = nil
    ) -> ReloadComfortSnapshot {
        let effectiveLayout = resolvedEffectiveSpeakerLayout(
            comfortSpeakerLayoutOverride: comfort.speakerLayoutOverride,
            comfortEffectiveSpeakerLayout: comfort.effectiveSpeakerLayout,
            session: session
        )
        let effectiveBinaural = AudioBinauralPolicy.effectiveBinauralFlag(
            isBinauralRouteActive: binauralAudioActive,
            effectiveSpeakerLayout: effectiveLayout
        )
        return ReloadComfortSnapshot(
            lowResUpscaleMode: comfort.lowResUpscaleMode,
            upscalesFullHDVideo: comfort.upscalesFullHDVideo,
            speakerLayoutOverride: comfort.speakerLayoutOverride,
            effectiveSpeakerLayout: effectiveLayout,
            dualLayerOverride: comfort.dualLayerOverride,
            recognizesBitmapSubtitleText: comfort.effectiveRecognizesBitmapSubtitleText(),
            audioDelaySeconds: audioDelaySeconds,
            audioShaping: comfort.buildAudioShaping(
                enhancement: audioEnhancement,
                binaural: effectiveBinaural,
                effectiveSpeakerLayoutOverride: effectiveLayout
            )
        )
    }

    nonisolated static func applyRestoreDisplayAndUpscaleOptions(
        _ snapshot: ReloadComfortSnapshot,
        session: TvPlaybackSession?,
        to options: inout LoadOptions
    ) {
        applyUpscaleSettings(
            lowResMode: snapshot.lowResUpscaleMode,
            upscalesFullHDVideo: snapshot.upscalesFullHDVideo,
            to: &options
        )
        applySpeakerLayoutOverride(
            snapshot.speakerLayoutOverride,
            effectiveSpeakerLayout: snapshot.effectiveSpeakerLayout,
            session: session,
            to: &options
        )
        if snapshot.dualLayerOverride == .forceOff {
            options.preferDualLayerDolbyVision = false
            options.foldsDolbyVisionFEL = false
            options.dolbyVisionHandling = .baseLayerOnly
        }
        options.skipsContainerAttachments = false
        options.readsContainerAttachmentsAtOpen = false
        options.recognizesBitmapSubtitleText = snapshot.recognizesBitmapSubtitleText
        options.audioDelaySeconds = snapshot.audioDelaySeconds
        options.audioShaping = snapshot.audioShaping
    }

    nonisolated static func applyUpscaleSettings(
        lowResMode: LowResUpscaleMode,
        upscalesFullHDVideo: Bool,
        to options: inout LoadOptions
    ) {
        let policy = UpscaleLoadPolicy.resolve(
            lowResMode: lowResMode,
            upscalesFullHDVideo: upscalesFullHDVideo
        )
        options.upscalesLowResolutionVideo = policy.upscalesLowResolutionVideo
        options.upscaleScaler = policy.scaler.aetherScaler
        options.upscalesFullHDVideo = policy.upscalesFullHDVideo
    }

    nonisolated static func applyLowResUpscaleMode(_ mode: LowResUpscaleMode, to options: inout LoadOptions) {
        applyUpscaleSettings(lowResMode: mode, upscalesFullHDVideo: false, to: &options)
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
        upscalesFullHDVideo: Bool = false,
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
        if lowResUpscaleMode != .off && candidate.isLikelySub1080pSDRForUpscale {
            return true
        }
        if (lowResUpscaleMode == .animeLineArt || upscalesFullHDVideo) && candidate.isLikelyFullHDSDRForUpscale {
            return true
        }
        return false
    }

    nonisolated static func shouldUpgradePlaybackMemoryMode(
        alreadyHadPreparedSession: Bool,
        initialHeavyStream: Bool,
        resolvedHeavyStream: Bool
    ) -> Bool {
        !alreadyHadPreparedSession && !initialHeavyStream && resolvedHeavyStream
    }

    nonisolated static func errorCategory(for kind: PlaybackErrorKind) -> PlaybackErrorCategory {
        switch kind {
        case .sourceOpenFailed: return .sourceOpenFailed
        case .sourceRefused: return .sourceRefused
        case .sourceCertificateRejected: return .sourceCertificateRejected
        case .sourceFabricatesRanges: return .sourceFabricatesRanges
        case .noPlayableTrackWithinBudget: return .noPlayableTrackWithinBudget
        case .vodSourceFailed: return .vodSourceFailed
        case .sourceRateLimited: return .sourceRateLimited
        case .audioBridgeProducedNoOutput: return .audioBridgeProducedNoOutput
        case .storageExhausted: return .storageExhausted
        default: return .unknown
        }
    }

    nonisolated static func friendlyEngineErrorMessage(
        rawMessage: String,
        errorInfo: PlaybackErrorInfo?
    ) -> String {
        guard let errorInfo else {
            return LunaCopy.friendlyEngineErrorMessage(rawMessage)
        }
        let effectiveRaw = errorInfo.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rawMessage
            : errorInfo.message
        return PlaybackErrorGuidancePolicy.userMessage(
            category: errorCategory(for: errorInfo.kind),
            underlyingCode: errorInfo.underlyingCode,
            ffmpegErrorCode: errorInfo.ffmpegErrorCode,
            rawMessage: effectiveRaw
        )
    }

    nonisolated static func friendlyEngineFailure(
        _ error: Error,
        engineErrorInfo: PlaybackErrorInfo?,
        fallback: String = "Kunne ikke nå LunaCore akkurat nå. Prøv igjen om litt."
    ) -> String {
        if error is LunaCoreError || error is URLError {
            return LunaCopy.friendlyErrorMessage(error, fallback: fallback)
        }
        if let engineErrorInfo {
            return friendlyEngineErrorMessage(
                rawMessage: error.localizedDescription,
                errorInfo: engineErrorInfo
            )
        }
        return LunaCopy.friendlyErrorMessage(error, fallback: fallback)
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

    nonisolated static func curtainPreservedURLs(
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

extension PlayerViewModel {
    static func buildLoadOptions(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        comfort: ComfortPreferences,
        audioEnhancement: AudioEnhancementMode,
        audioDelaySeconds: Double,
        autoplay: Bool = true,
        suppressInitialSubtitleSelection: Bool = false,
        preferNorwegianAudio: Bool = false,
        binauralAudioActive: Bool = false,
        displayCapabilities: DisplayCapabilities = AetherEngine.displayCapabilities,
        memoryProfile: DeviceMemoryProfile = DeviceHardwareCapabilities.memoryProfile,
        availableMemoryBytes: UInt64 = DeviceHardwareCapabilities.availableMemoryBytes()
    ) -> LoadOptions {
        PlayerEngineConfigurator.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: audioDelaySeconds,
            autoplay: autoplay,
            suppressInitialSubtitleSelection: suppressInitialSubtitleSelection,
            preferNorwegianAudio: preferNorwegianAudio,
            binauralAudioActive: binauralAudioActive,
            displayCapabilities: displayCapabilities,
            memoryProfile: memoryProfile,
            availableMemoryBytes: availableMemoryBytes
        )
    }

    nonisolated static func isLikelyHeavySoftwareSession(
        _ session: TvPlaybackSession?,
        dualLayerOverride: DualLayerOverrideMode = .auto,
        lowResUpscaleMode: LowResUpscaleMode = .off,
        upscalesFullHDVideo: Bool = false,
        supportsHardwareAV1: Bool = DeviceHardwareCapabilities.supportsHardwareAV1
    ) -> Bool {
        PlayerEngineConfigurator.isLikelyHeavySoftwareSession(
            session,
            dualLayerOverride: dualLayerOverride,
            lowResUpscaleMode: lowResUpscaleMode,
            upscalesFullHDVideo: upscalesFullHDVideo,
            supportsHardwareAV1: supportsHardwareAV1
        )
    }

    nonisolated static func canDirectMountPreparedSession(
        _ request: PlaybackLaunchRequest,
        candidateSession: TvPlaybackSession? = nil
    ) -> Bool {
        PlayerEngineConfigurator.canDirectMountPreparedSession(request, candidateSession: candidateSession)
    }

    nonisolated static func shouldPauseEngineOnDismiss(
        engineState: PlaybackState,
        playbackPhase: PlaybackPhase
    ) -> Bool {
        PlayerEngineConfigurator.shouldPauseEngineOnDismiss(engineState: engineState, playbackPhase: playbackPhase)
    }
}
