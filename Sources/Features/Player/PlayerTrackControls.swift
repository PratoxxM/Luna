import Foundation
import AetherBridge

extension PlayerViewModel {
    // MARK: - Audio & Subtitle Controls

    func selectAudioTrack(_ index: Int) {
        activeAudioTrackIndex = index
        guard previewAudioOptions.isEmpty else { return }
        engine.selectAudioTrack(index: index)
        if comfort.smartNordicSubtitleRule && !userManuallySelectedSubtitle {
            smartRuleTask?.cancel()
            smartRuleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                self?.applySmartSubtitleRule()
            }
        }
    }

    func adjustAudioDelay(byMs deltaMs: Int) {
        applyAudioDelayMs(audioDelayMs + deltaMs, debounceEngineCommit: true)
    }

    func resetAudioDelay() {
        applyAudioDelayMs(0, debounceEngineCommit: false)
    }

    private func applyAudioDelayMs(_ targetMs: Int, debounceEngineCommit: Bool) {
        let clamped = ComfortPreferences.clampAudioDelayMs(targetMs)
        audioDelayMs = clamped
        comfort.audioDelayMs = clamped
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil

        guard !isResolving && !isSwitchingSource && !isDismissing && !isTeardownCompleted else {
            hasPendingAudioDelayCommit = false
            return
        }

        let targetSeconds = effectiveAudioDelaySecondsForActiveRoute()
        if !debounceEngineCommit {
            hasPendingAudioDelayCommit = false
            transport.setAudioDelay(targetSeconds)
            return
        }

        hasPendingAudioDelayCommit = true
        audioDelayCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.audioDelayDebounceNs)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingAudioDelayCommitIfNeeded()
        }
    }

    func flushPendingAudioDelayCommitIfNeeded() {
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        guard hasPendingAudioDelayCommit else { return }
        hasPendingAudioDelayCommit = false
        guard !isResolving, !isSwitchingSource, !isDismissing, !isTeardownCompleted else {
            return
        }
        transport.setAudioDelay(effectiveAudioDelaySecondsForActiveRoute())
    }

    func handleAudioRouteChange(isWirelessOverride: Bool? = nil) {
        let nextWireless = isWirelessOverride ?? PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
        guard nextWireless != isWirelessAudioRouteActive else { return }
        isWirelessAudioRouteActive = nextWireless
        guard !isResolving, !isSwitchingSource, !isDismissing, !isTeardownCompleted else {
            return
        }
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        hasPendingAudioDelayCommit = false
        transport.setAudioDelay(effectiveAudioDelaySecondsForActiveRoute())
    }

    func handleSystemCaptionRequest(_ request: SystemCaptionRequest) {
        guard !isDismissing, !isTeardownCompleted, !isResolving, !isSwitchingSource else {
            return
        }
        let availableTracks = !subtitleTracks.isEmpty ? subtitleTracks : engine.subtitleTracks
        guard !availableTracks.isEmpty else {
            return
        }
        if subtitleTracks != availableTracks {
            subtitleTracks = availableTracks
        }
        guard activeSubtitleTrackIndex == nil && engine.activeSubtitleTrackIndex == nil else {
            return
        }
        guard let match = SmartTrackRuleEngine.selectBestSubtitleTrack(
            forLanguage: request.language,
            in: availableTracks
        ) else {
            return
        }
        activeSubtitleTrackIndex = match.id
        if previewSubtitleOptions.isEmpty {
            engine.selectSubtitleTrack(index: match.id)
        }
    }

    func setAudioEnhancement(_ mode: AudioEnhancementMode) {
        audioEnhancement = mode
        engine.setAudioShaping(comfort.buildAudioShaping(enhancement: mode))
    }

    func selectSubtitleManually(_ index: Int) {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = index
        guard previewSubtitleOptions.isEmpty else { return }
        engine.selectSubtitleTrack(index: index)
    }

    func clearSubtitleManually() {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = nil
        guard previewSubtitleOptions.isEmpty else { return }
        engine.clearSubtitle()
    }

    func adjustSubtitleDelay(by delta: Double) {
        let rounded = ((subtitleDelaySeconds + delta) * 10).rounded() / 10
        let updated = min(max(rounded, -10.0), 10.0)
        engine.setSoftwareSubtitleDelay(updated)
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    func resetSubtitleDelay() {
        engine.setSoftwareSubtitleDelay(0)
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    func applySmartSubtitleRule() {
        guard comfort.smartNordicSubtitleRule, !userManuallySelectedSubtitle else { return }
        let liveAudioTracks = engine.audioTracks
        let liveAudioIdx = engine.activeAudioTrackIndex
        let liveSubtitleTracks = engine.subtitleTracks
        let liveSubIdx = engine.activeSubtitleTrackIndex

        audioTracks = liveAudioTracks
        activeAudioTrackIndex = liveAudioIdx
        subtitleTracks = liveSubtitleTracks
        activeSubtitleTrackIndex = liveSubIdx

        let activeAudio = liveAudioTracks.first(where: { $0.id == liveAudioIdx }) ?? liveAudioTracks.first
        let decision = SmartTrackRuleEngine.evaluate(activeAudio: activeAudio, subtitleTracks: liveSubtitleTracks)
        switch decision {
        case .clearSubtitles:
            if liveSubIdx != nil {
                engine.clearSubtitle()
                activeSubtitleTrackIndex = nil
            }
        case .selectTrack(let trackID):
            if liveSubIdx != trackID {
                engine.selectSubtitleTrack(index: trackID)
                activeSubtitleTrackIndex = trackID
            }
        case .keepCurrent:
            break
        }
    }

    // MARK: - Tillegg A: Live MetalFX & Kveldslys Diagnostics

    var isMetalFXActive: Bool {
        activeUpscale != nil && activeUpscale?.disabledReason == nil
    }

    var liveQualitySummaryBadge: String? {
        if let metalBadge = activeMetalFXBadge {
            return metalBadge
        }
        if let quality = activeSession?.selectedCandidate.humanQualitySummary, !quality.isEmpty {
            return quality
        }
        return nil
    }

    var activeMetalFXBadge: String? {
        guard isMetalFXActive else { return nil }
        let rawH = sourceVideoHeight > 0
            ? Int(sourceVideoHeight)
            : Int((activeUpscale?.sourceSize.height ?? 1080).rounded())
        let sourceLabel = rawH > 0 ? "\(rawH)p" : "SD/HD"
        if activeUpscale?.scaler == .lineArt || comfort.lowResUpscaleMode == .animeLineArt {
            return "\(sourceLabel) → 4K MetalFX (Animasjon)"
        }
        return "\(sourceLabel) → 4K MetalFX"
    }

    var videoFormatSummaryLine: String {
        var parts: [String] = []
        if sourceVideoHeight > 0 {
            parts.append(sourceVideoHeight >= 1800 ? "4K" : "\(sourceVideoHeight)p")
        }
        switch videoFormat {
        case .dolbyVision:
            parts.append("Dolby Vision")
        case .hdr10Plus:
            parts.append("HDR10+")
        case .hdr10:
            parts.append("HDR10")
        case .hlg:
            parts.append("HLG")
        case .sdr:
            parts.append("SDR")
        @unknown default:
            break
        }
        if let fps = sourceVideoFrameRate, fps > 0 {
            let rounded = (fps * 100).rounded() / 100
            parts.append(rounded == rounded.rounded() ? "\(Int(rounded))p" : "\(LunaCopy.formatDecimal(rounded, decimals: 2))p")
        }
        if let dec = activeVideoDecoder, !dec.isEmpty {
            parts.append(dec)
        }
        return parts.isEmpty ? "Video: Avspillingsklar" : "Video: " + parts.joined(separator: " · ")
    }

    var kveldslysLockReason: String? {
        guard let activeSubtitleTrackIndex else {
            return "Slå på undertekst for å justere"
        }
        if videoFormat == .sdr {
            return "Kun aktiv på HDR-innhold"
        }
        if subtitleTracks.first(where: { $0.id == activeSubtitleTrackIndex })?.isNativelyRenderedSubtitle == true {
            return "Gjelder kun overleggstekst"
        }
        return nil
    }

    func setMetalFXModeLive(_ targetMode: LowResUpscaleMode) {
        comfort.lowResUpscaleMode = targetMode

        guard !isResolving, !isSwitchingSource, previewAudioOptions.isEmpty else {
            return
        }

        upscaleReloadTask?.cancel()
        upscaleReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let effectiveDelaySeconds = self.effectiveAudioDelaySecondsForActiveRoute()
            let currentShaping = self.comfort.buildAudioShaping(enhancement: self.audioEnhancement)
            _ = try? await self.engine.reloadAtCurrentPosition { options in
                Self.applyLowResUpscaleMode(targetMode, to: &options)
                options.audioDelaySeconds = effectiveDelaySeconds
                options.audioShaping = currentShaping
            }
            if !Task.isCancelled {
                self.upscaleReloadTask = nil
            }
        }
    }
}
