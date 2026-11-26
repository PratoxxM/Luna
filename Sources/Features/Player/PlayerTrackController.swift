import Foundation
import Observation
import AetherBridge

/// Owns audio/subtitle track selection, `originalLanguage` + «Norsk tale», per-candidate
/// `subtitleDelayMs` memory, live MetalFX/speaker reloads, and chapter merging.
@MainActor
@Observable
final class PlayerTrackController {
    var durationSeconds: Double = 0
    var audioTracks: [TrackInfo] = []
    var activeAudioTrackIndex: Int?
    var audioDelayMs: Int {
        get { comfort.audioDelayMs }
        set {
            if comfort.audioDelayMs != newValue {
                comfort.audioDelayMs = newValue
            }
        }
    }
    var audioEnhancement: AudioEnhancementMode
    var subtitleTracks: [TrackInfo] = []
    var activeSubtitleTrackIndex: Int?
    var subtitleDelayMs: Int = 0
    var subtitleDelaySeconds: Double { Double(subtitleDelayMs) / 1000.0 }
    var preferNorwegianAudio: Bool = false
    var isSearchingSubtitles: Bool = false
    var isAutoAligningSubtitles: Bool = false
    var subtitleActionStatusMessage: String?

    var previewAudioOptions: [PlayerDrawerAudioOption] = []
    var previewSubtitleOptions: [PlayerDrawerSubtitleOption] = []
    var chapters: [PlaybackChapter] = []

    @ObservationIgnored weak var host: PlayerViewModel?
    @ObservationIgnored let engine: AetherEngine
    @ObservationIgnored let comfort: ComfortPreferences
    @ObservationIgnored let transport: any PlayerTransportControlling
    @ObservationIgnored let preferenceStore: PlaybackPreferenceStore

    @ObservationIgnored var engineChapters: [ChapterInfo] = []
    @ObservationIgnored var userManuallySelectedSubtitle: Bool = false
    @ObservationIgnored var didApplyInitialSmartRule: Bool = false
    @ObservationIgnored var smartRuleTask: Task<Void, Never>?
    @ObservationIgnored var audioDelayCommitTask: Task<Void, Never>?
    @ObservationIgnored var hasPendingAudioDelayCommit: Bool = false
    @ObservationIgnored var isWirelessAudioRouteActive: Bool = false
    @ObservationIgnored var upscaleReloadTask: Task<Void, Never>?
    @ObservationIgnored var subtitleActionTask: Task<Void, Never>?

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        transport: any PlayerTransportControlling,
        preferenceStore: PlaybackPreferenceStore = PlaybackPreferenceStore()
    ) {
        self.engine = engine
        self.comfort = comfort
        self.audioEnhancement = comfort.audioEnhancement
        self.transport = transport
        self.preferenceStore = preferenceStore
        self.isWirelessAudioRouteActive = PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
    }

    func bindHost(_ host: PlayerViewModel) { self.host = host }

    func effectiveAudioDelaySecondsForActiveRoute() -> Double {
        PlayerAudioSessionCoordinator.effectiveAudioDelaySeconds(
            configuredDelaySeconds: Double(audioDelayMs) / 1000.0,
            isWirelessRoute: isWirelessAudioRouteActive
        )
    }

    func resetForNewLaunch(itemId: String) {
        audioEnhancement = comfort.audioEnhancement
        subtitleDelayMs = 0
        preferNorwegianAudio = preferenceStore.preferNorwegianAudio(forItemId: itemId)
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        subtitleActionStatusMessage = nil
    }

    func resetFlagsForResolve() {
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        subtitleActionStatusMessage = nil
    }

    func prepareForEngineMount() -> Int {
        audioDelayCommitTask?.cancel(); audioDelayCommitTask = nil
        hasPendingAudioDelayCommit = false
        upscaleReloadTask?.cancel(); upscaleReloadTask = nil
        subtitleActionTask?.cancel(); subtitleActionTask = nil
        isWirelessAudioRouteActive = PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
        let initialAudioDelayMs = comfort.audioDelayMs
        audioDelayMs = initialAudioDelayMs
        audioEnhancement = comfort.audioEnhancement
        return initialAudioDelayMs
    }

    func completeEngineMount(
        session: TvPlaybackSession,
        initialAudioDelayMs: Int,
        initialWirelessRoute: Bool,
        trackIntent: PlaybackTrackIntent?
    ) {
        engineChapters = []
        let currentWirelessRoute = PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
        isWirelessAudioRouteActive = currentWirelessRoute
        if comfort.audioDelayMs != initialAudioDelayMs || currentWirelessRoute != initialWirelessRoute {
            audioDelayMs = comfort.audioDelayMs
            transport.setAudioDelay(effectiveAudioDelaySecondsForActiveRoute())
        } else {
            audioDelayMs = initialAudioDelayMs
        }

        if !engine.audioTracks.isEmpty || transport.audioTrackDescriptors.isEmpty {
            audioTracks = engine.audioTracks
        }
        activeAudioTrackIndex = transport.activeAudioTrackIndex ?? engine.activeAudioTrackIndex
        if !engine.subtitleTracks.isEmpty || transport.subtitleTrackDescriptors.isEmpty {
            subtitleTracks = engine.subtitleTracks
        }
        activeSubtitleTrackIndex = transport.activeSubtitleTrackIndex ?? engine.activeSubtitleTrackIndex
        rebuildMergedChapters()

        if let trackIntent {
            didApplyInitialSmartRule = true
            applyResolvedTrackIntent(trackIntent)
            return
        }

        let candidateId = session.selectedCandidate.candidateId
        let initialSubDelay = PlaybackSessionPolicy.resolvedInitialSubtitleDelayMs(
            candidateId: candidateId,
            sessionDelayMs: session.subtitleDelayMs,
            tracksDelayMs: session.tracks?.subtitleDelayMs,
            preferenceStore: preferenceStore
        )
        subtitleDelayMs = initialSubDelay
        transport.setSoftwareSubtitleDelay(subtitleDelaySeconds)

        let audioDescriptors = effectiveAudioDescriptors()
        if !audioDescriptors.isEmpty,
           let preferredAudio = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
               in: audioDescriptors,
               originalLanguage: session.item.originalLanguage,
               preferNorwegianAudio: preferNorwegianAudio
           ),
           preferredAudio.id != activeAudioTrackIndex {
            activeAudioTrackIndex = preferredAudio.id
            transport.selectAudioTrack(index: preferredAudio.id)
        }

        if (comfort.smartNordicSubtitleRule || preferNorwegianAudio) && !didApplyInitialSmartRule {
            didApplyInitialSmartRule = true
            applySmartSubtitleRule()
        }
    }

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

    func resetAudioDelay() { applyAudioDelayMs(0, debounceEngineCommit: false) }

    private func applyAudioDelayMs(_ targetMs: Int, debounceEngineCommit: Bool) {
        let clamped = ComfortPreferences.clampAudioDelayMs(targetMs)
        audioDelayMs = clamped
        comfort.audioDelayMs = clamped
        audioDelayCommitTask?.cancel(); audioDelayCommitTask = nil
        guard let host, !host.sessionController.isResolving, !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted else {
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
            try? await Task.sleep(nanoseconds: PlayerViewModel.audioDelayDebounceNs)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingAudioDelayCommitIfNeeded()
        }
    }

    func flushPendingAudioDelayCommitIfNeeded() {
        audioDelayCommitTask?.cancel(); audioDelayCommitTask = nil
        guard hasPendingAudioDelayCommit else { return }
        hasPendingAudioDelayCommit = false
        guard let host, !host.sessionController.isResolving, !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted else {
            return
        }
        transport.setAudioDelay(effectiveAudioDelaySecondsForActiveRoute())
    }

    func handleAudioRouteChange(isWirelessOverride: Bool? = nil) {
        let nextWireless = isWirelessOverride ?? PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
        guard nextWireless != isWirelessAudioRouteActive else { return }
        isWirelessAudioRouteActive = nextWireless
        guard let host, !host.sessionController.isResolving, !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted else {
            return
        }
        audioDelayCommitTask?.cancel(); audioDelayCommitTask = nil
        hasPendingAudioDelayCommit = false
        transport.setAudioDelay(effectiveAudioDelaySecondsForActiveRoute())
    }

    func handleSystemCaptionRequest(_ request: SystemCaptionRequest) {
        guard let host, !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted,
              !host.sessionController.isResolving, !host.sessionController.isSwitchingSource else {
            return
        }
        if subtitleTracks.isEmpty, !engine.subtitleTracks.isEmpty { subtitleTracks = engine.subtitleTracks }
        let descriptors = !transport.subtitleTrackDescriptors.isEmpty
            ? transport.subtitleTrackDescriptors
            : subtitleTracks.map(SmartTrackDescriptor.init(track:))
        guard !descriptors.isEmpty,
              activeSubtitleTrackIndex == nil && transport.activeSubtitleTrackIndex == nil,
              let matchID = SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: request.language, in: descriptors) else {
            return
        }
        activeSubtitleTrackIndex = matchID
        if previewSubtitleOptions.isEmpty { transport.selectSubtitleTrack(index: matchID) }
    }

    func setAudioEnhancement(_ mode: AudioEnhancementMode) {
        audioEnhancement = mode
        if comfort.audioEnhancement != mode { comfort.audioEnhancement = mode }
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
        applyAndPersistSubtitleDelayMs(
            PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: subtitleDelayMs, deltaMs: deltaMs)
        )
    }

    func adjustSubtitleDelay(by deltaSeconds: Double) {
        guard deltaSeconds.isFinite else { return }
        let scaledMs = (deltaSeconds * 1000.0).rounded()
        let deltaMs = Int(exactly: scaledMs)
            ?? (scaledMs >= 0
                ? PlaybackSyncTimingPolicy.subtitleDelayRangeMs.upperBound
                : PlaybackSyncTimingPolicy.subtitleDelayRangeMs.lowerBound)
        adjustSubtitleDelay(byMs: deltaMs)
    }

    func resetSubtitleDelay() { applyAndPersistSubtitleDelayMs(0) }

    func applyAndPersistSubtitleDelayMs(_ delayMs: Int) {
        let clamped = PlaybackSyncTimingPolicy.clampSubtitleDelayMs(delayMs)
        subtitleDelayMs = clamped
        if let candidateId = host?.sessionController.activeSession?.selectedCandidate.candidateId {
            preferenceStore.setSubtitleDelayMs(clamped, forCandidateId: candidateId)
        }
        transport.setSoftwareSubtitleDelay(subtitleDelaySeconds)
    }

    func applySmartSubtitleRule() {
        guard (comfort.smartNordicSubtitleRule || preferNorwegianAudio), !userManuallySelectedSubtitle else { return }
        if !engine.audioTracks.isEmpty || audioTracks.isEmpty { audioTracks = engine.audioTracks }
        if !engine.subtitleTracks.isEmpty || subtitleTracks.isEmpty { subtitleTracks = engine.subtitleTracks }
        let liveAudioDescriptors = effectiveAudioDescriptors()
        let liveAudioIdx = transport.activeAudioTrackIndex ?? activeAudioTrackIndex
        let liveSubtitleDescriptors = effectiveSubtitleDescriptors()
        let liveSubIdx = transport.activeSubtitleTrackIndex ?? activeSubtitleTrackIndex

        activeAudioTrackIndex = liveAudioIdx
        activeSubtitleTrackIndex = liveSubIdx

        let activeAudio = liveAudioDescriptors.first(where: { $0.id == liveAudioIdx }) ?? liveAudioDescriptors.first
        switch SmartTrackRuleEngine.evaluate(activeAudio: activeAudio?.asSmartDescriptor, subtitleTracks: liveSubtitleDescriptors) {
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

    var kveldslysLockReason: String? {
        guard let activeSubtitleTrackIndex else { return "Slå på undertekst for å justere" }
        if subtitleTracks.first(where: { $0.id == activeSubtitleTrackIndex })?.isNativelyRenderedSubtitle == true {
            return "Gjelder kun overleggstekst"
        }
        return nil
    }

    var speakerLayoutHeaderSummary: String {
        comfort.speakerLayoutOverride.headerSummary(forAutoLayout: host?.qosReporter.sessionRoomAutoLayout ?? "7.1.4")
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
        guard let host, !host.sessionController.isResolving, !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted,
              previewAudioOptions.isEmpty else { return }
        upscaleReloadTask?.cancel()
        upscaleReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLiveEngineOptionsReload()
            if !Task.isCancelled {
                self.upscaleReloadTask = nil
            }
        }
    }

    internal func performLiveEngineOptionsReload() async {
        guard let host, !host.sessionController.isResolving, !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted,
              previewAudioOptions.isEmpty else { return }
        let snapshot = PlayerEngineConfigurator.captureReloadComfortSnapshot(
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: effectiveAudioDelaySecondsForActiveRoute()
        )
        let session = host.sessionController.activeSession
        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10
        do {
            try await transport.reloadAtCurrentPosition { options in
                PlayerEngineConfigurator.applyRestoreDisplayAndUpscaleOptions(snapshot, session: session, to: &options)
            }
            guard !Task.isCancelled else { return }
            if subtitleDelayMs != 0 { transport.setSoftwareSubtitleDelay(subtitleDelaySeconds) }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch {
            guard !Task.isCancelled else { return }
            host.qosReporter.showTransientBanner(
                LunaCopy.friendlyErrorMessage(error, fallback: "Kunne ikke oppdatere avspillingsinnstillinger.")
            )
        }
    }

    var drawerAudioOptions: [PlayerDrawerAudioOption] {
        if !previewAudioOptions.isEmpty { return previewAudioOptions }
        return audioTracks.map {
            PlayerDrawerAudioOption(
                id: $0.id, languageCode: $0.language, rawTitle: $0.name, codec: $0.codec,
                profile: $0.profile, channelLayout: $0.channelLayout, channels: Int($0.channels),
                isAtmos: $0.isAtmos, isDTSX: $0.isDTSX, isCommentary: $0.isCommentary
            )
        }
    }

    var drawerSubtitleOptions: [PlayerDrawerSubtitleOption] {
        if !previewSubtitleOptions.isEmpty { return previewSubtitleOptions }
        return subtitleTracks.map {
            PlayerDrawerSubtitleOption(
                id: $0.id, languageCode: $0.language, rawTitle: $0.name,
                isForced: $0.isForced, isHearingImpaired: $0.isHearingImpaired, isExternal: $0.isExternal
            )
        }
    }

    func activeChapter(at timeSeconds: Double) -> PlaybackChapter? {
        guard !chapters.isEmpty, timeSeconds.isFinite else { return nil }
        return chapters.first { timeSeconds >= $0.startSeconds && timeSeconds < $0.endSeconds }
            ?? chapters.last { timeSeconds >= $0.startSeconds }
    }

    func rebuildMergedChapters() {
        let probeCh = host?.sessionController.activeSession?.chapters
            ?? host?.sessionController.activeSession?.tracks?.chapters ?? []
        let dur = host?.sessionController.effectiveDurationSeconds ?? durationSeconds
        let merged = PlaybackChapter.merge(probeChapters: probeCh, engineChapters: engineChapters, mediaDuration: dur)
        if chapters != merged { chapters = merged }
    }

    func cancelTasks() {
        smartRuleTask?.cancel(); smartRuleTask = nil
        audioDelayCommitTask?.cancel(); audioDelayCommitTask = nil
        hasPendingAudioDelayCommit = false
        upscaleReloadTask?.cancel(); upscaleReloadTask = nil
        subtitleActionTask?.cancel(); subtitleActionTask = nil
    }
}
