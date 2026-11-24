import Foundation
import AetherBridge

extension PlayerViewModel {
    // MARK: - Audio, Subtitle & Sync Controls

    func selectAudioTrack(_ index: Int) {
        activeAudioTrackIndex = index
        guard previewAudioOptions.isEmpty else { return }
        transport.selectAudioTrack(index: index)
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
        let nextMs = PlaybackSyncTimingPolicy.stepAudioDelayMs(from: audioDelayMs, deltaMs: deltaMs)
        applyAudioDelayMs(nextMs, debounceEngineCommit: true)
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
        if subtitleTracks.isEmpty, !engine.subtitleTracks.isEmpty {
            subtitleTracks = engine.subtitleTracks
        }
        let descriptors = !transport.subtitleTrackDescriptors.isEmpty
            ? transport.subtitleTrackDescriptors
            : subtitleTracks.map(SmartTrackDescriptor.init(track:))
        guard !descriptors.isEmpty else {
            return
        }
        guard activeSubtitleTrackIndex == nil && transport.activeSubtitleTrackIndex == nil else {
            return
        }
        guard let matchID = SmartTrackRuleEngine.selectBestSubtitleID(
            forLanguage: request.language,
            in: descriptors
        ) else {
            return
        }
        activeSubtitleTrackIndex = matchID
        if previewSubtitleOptions.isEmpty {
            transport.selectSubtitleTrack(index: matchID)
        }
    }

    func setAudioEnhancement(_ mode: AudioEnhancementMode) {
        audioEnhancement = mode
        if comfort.audioEnhancement != mode {
            comfort.audioEnhancement = mode
        }
        transport.setAudioShaping(comfort.buildAudioShaping(enhancement: mode))
    }

    func selectSubtitleManually(_ index: Int) {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = index
        guard previewSubtitleOptions.isEmpty else { return }
        transport.selectSubtitleTrack(index: index)
    }

    func clearSubtitleManually() {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = nil
        guard previewSubtitleOptions.isEmpty else { return }
        transport.clearSubtitle()
    }

    func adjustSubtitleDelay(byMs deltaMs: Int) {
        let updatedMs = PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: subtitleDelayMs, deltaMs: deltaMs)
        subtitleDelayMs = updatedMs
        transport.setSoftwareSubtitleDelay(subtitleDelaySeconds)
    }

    func adjustSubtitleDelay(by deltaSeconds: Double) {
        adjustSubtitleDelay(byMs: Int((deltaSeconds * 1000.0).rounded()))
    }

    func resetSubtitleDelay() {
        subtitleDelayMs = 0
        transport.setSoftwareSubtitleDelay(0)
    }

    func applySmartSubtitleRule() {
        guard comfort.smartNordicSubtitleRule, !userManuallySelectedSubtitle else { return }
        if !engine.audioTracks.isEmpty || audioTracks.isEmpty {
            audioTracks = engine.audioTracks
        }
        if !engine.subtitleTracks.isEmpty || subtitleTracks.isEmpty {
            subtitleTracks = engine.subtitleTracks
        }
        let liveAudioDescriptors = transport.audioTrackDescriptors
        let liveAudioIdx = transport.activeAudioTrackIndex ?? activeAudioTrackIndex
        let liveSubtitleDescriptors = transport.subtitleTrackDescriptors
        let liveSubIdx = transport.activeSubtitleTrackIndex ?? activeSubtitleTrackIndex

        activeAudioTrackIndex = liveAudioIdx
        activeSubtitleTrackIndex = liveSubIdx

        let activeAudio = liveAudioDescriptors.first(where: { $0.id == liveAudioIdx }) ?? liveAudioDescriptors.first
        let decision = SmartTrackRuleEngine.evaluate(
            activeAudio: activeAudio?.asSmartDescriptor,
            subtitleTracks: liveSubtitleDescriptors
        )
        switch decision {
        case .clearSubtitles:
            if liveSubIdx != nil {
                transport.clearSubtitle()
                activeSubtitleTrackIndex = nil
            }
        case .selectTrack(let trackID):
            if liveSubIdx != trackID {
                transport.selectSubtitleTrack(index: trackID)
                activeSubtitleTrackIndex = trackID
            }
        case .keepCurrent:
            break
        }
    }

    // MARK: - Live MetalFX, Høyttaleroppsett & Kveldslys

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
        if subtitleTracks.first(where: { $0.id == activeSubtitleTrackIndex })?.isNativelyRenderedSubtitle == true {
            return "Gjelder kun overleggstekst"
        }
        return nil
    }

    var speakerLayoutHeaderSummary: String {
        comfort.speakerLayoutOverride.headerSummary(forAutoLayout: sessionRoomAutoLayout)
    }

    var wirelessAudioDelayNotice: String? {
        isWirelessAudioRouteActive ? "Automatisk trådløs synk aktiv (AirPlay / Bluetooth)" : nil
    }

    func setSpeakerLayoutLive(_ targetMode: SpeakerLayoutOverrideMode) {
        comfort.speakerLayoutOverride = targetMode
        transport.setAudioShaping(comfort.buildAudioShaping(enhancement: audioEnhancement))
        scheduleLiveEngineOptionsReload()
    }

    func setMetalFXModeLive(_ targetMode: LowResUpscaleMode) {
        comfort.lowResUpscaleMode = targetMode
        scheduleLiveEngineOptionsReload()
    }

    private func scheduleLiveEngineOptionsReload() {
        guard !isResolving, !isSwitchingSource, !isDismissing, !isTeardownCompleted, previewAudioOptions.isEmpty else {
            return
        }

        upscaleReloadTask?.cancel()
        upscaleReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let upscaleMode = self.comfort.lowResUpscaleMode
            let speakerMode = self.comfort.speakerLayoutOverride
            let session = self.activeSession
            let effectiveDelaySeconds = self.effectiveAudioDelaySecondsForActiveRoute()
            let currentShaping = self.comfort.buildAudioShaping(enhancement: self.audioEnhancement)
            let preservedSubtitleDelay = self.subtitleDelaySeconds
            _ = try? await self.engine.reloadAtCurrentPosition { options in
                Self.applyLowResUpscaleMode(upscaleMode, to: &options)
                Self.applySpeakerLayoutOverride(speakerMode, session: session, to: &options)
                options.audioDelaySeconds = effectiveDelaySeconds
                options.audioShaping = currentShaping
            }
            guard !Task.isCancelled else { return }
            if self.subtitleDelayMs != 0 {
                self.transport.setSoftwareSubtitleDelay(preservedSubtitleDelay)
            }
            self.upscaleReloadTask = nil
        }
    }

    // MARK: - Drawer Track Descriptors, Coalesced Seek & Chapters

    var drawerAudioOptions: [PlayerDrawerAudioOption] {
        if !previewAudioOptions.isEmpty {
            return previewAudioOptions
        }
        return audioTracks.map {
            PlayerDrawerAudioOption(
                id: $0.id,
                languageCode: $0.language,
                rawTitle: $0.name,
                codec: $0.codec,
                profile: $0.profile,
                channelLayout: $0.channelLayout,
                channels: Int($0.channels),
                isAtmos: $0.isAtmos,
                isDTSX: $0.isDTSX,
                isCommentary: $0.isCommentary
            )
        }
    }

    var drawerSubtitleOptions: [PlayerDrawerSubtitleOption] {
        if !previewSubtitleOptions.isEmpty {
            return previewSubtitleOptions
        }
        return subtitleTracks.map {
            PlayerDrawerSubtitleOption(
                id: $0.id,
                languageCode: $0.language,
                rawTitle: $0.name,
                isForced: $0.isForced,
                isHearingImpaired: $0.isHearingImpaired,
                isExternal: $0.isExternal
            )
        }
    }

    func coalesceRelativeSeek(delta: Double) {
        guard !isResolving else { return }
        let dur = effectiveDurationSeconds
        let base = coalescedSeekPreviewTarget ?? max(0, transport.currentTime)
        let accumulatedDelta = coalescedSeekDelta + delta
        let rawTarget = max(0, base + delta)
        let clampedTarget = dur > 1 ? min(dur - 0.5, rawTarget) : rawTarget

        coalescedSeekDelta = accumulatedDelta
        coalescedSeekPreviewTarget = clampedTarget

        chapterSeekTask?.cancel()
        chapterSeekTask = nil
        coalescedSeekTask?.cancel()
        coalescedSeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.relativeSeekDebounceNs)
            guard !Task.isCancelled, let self else { return }
            let finalTarget = self.coalescedSeekPreviewTarget ?? max(0, self.transport.currentTime)
            await self.transport.seek(to: finalTarget, exact: false)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.coalescedSeekDelta = 0
            self.coalescedSeekPreviewTarget = nil
        }
    }

    func seekToChapter(_ chapter: PlaybackChapter) {
        seekToPosition(chapter.startSeconds, exact: true)
    }

    func seekToPosition(_ rawTargetSeconds: Double, exact: Bool = true) {
        guard !isResolving else { return }
        coalescedSeekTask?.cancel()
        coalescedSeekTask = nil
        coalescedSeekDelta = 0
        coalescedSeekPreviewTarget = nil
        chapterSeekTask?.cancel()
        let targetSeconds = max(0, rawTargetSeconds)
        chapterSeekTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.transport.seek(to: targetSeconds, exact: exact)
            if !Task.isCancelled {
                self.chapterSeekTask = nil
            }
        }
    }

    func activeChapter(at timeSeconds: Double) -> PlaybackChapter? {
        guard !chapters.isEmpty, timeSeconds.isFinite else { return nil }
        return chapters.first { timeSeconds >= $0.startSeconds && timeSeconds < $0.endSeconds }
            ?? chapters.last { timeSeconds >= $0.startSeconds }
    }

    func rebuildMergedChapters() {
        let probeCh = activeSession?.chapters ?? activeSession?.tracks?.chapters ?? []
        let merged = PlaybackChapter.merge(
            probeChapters: probeCh,
            engineChapters: engineChapters,
            mediaDuration: effectiveDurationSeconds
        )
        if chapters != merged {
            chapters = merged
        }
    }
}
