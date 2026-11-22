import Foundation
import Observation
import UIKit
import Combine
import AetherBridge

@MainActor
@Observable
final class PlayerViewModel {
    // Resolve & First-Frame Reveal State
    var isResolving: Bool = true
    let startupState = PlayerStartupState()
    var fatalError: String?
    var transientBannerMessage: String?
    var remoteCommandToastMessage: String?

    var hasFirstFrameReadyForDisplay: Bool = false
    var isAwaitingDisplaySwitch: Bool = false
    var firstFrameFallbackUnlocked: Bool = false
    var isRestoringFromBackground: Bool = false

    var resolveStageLabel: String {
        get { startupState.resolveStageLabel }
        set { if startupState.resolveStageLabel != newValue { startupState.resolveStageLabel = newValue } }
    }
    var resolvePercent: Int {
        get { startupState.resolvePercent }
        set { if startupState.resolvePercent != newValue { startupState.resolvePercent = newValue } }
    }
    var resolveHeadline: String? {
        get { startupState.resolveHeadline }
        set { if startupState.resolveHeadline != newValue { startupState.resolveHeadline = newValue } }
    }

    // Session, Sources & Next Episode
    var currentRequest: PlaybackLaunchRequest?
    var activeSession: TvPlaybackSession?
    var alternatives: [TvCandidateInfo] = []
    private(set) var alternativesSessionId: String?
    var isLoadingAlternatives: Bool = false
    var isSwitchingSource: Bool = false
    var lastVfsTelemetry: TvVfsTelemetry?

    // Playback, Tracks & Chapters
    var playbackPhase: PlaybackPhase = .idle
    var durationSeconds: Double = 0
    var videoFormat: VideoFormat = .sdr
    var sourceDVProfile: Int?
    var dolbyVisionConversion: DolbyVisionConversion?
    var videoRoute: VideoRoute = .none
    var audioDelivery: AudioDelivery = .none
    var sourceVideoCodecName: String?
    var sourceVideoWidth: Int32 = 0
    var sourceVideoHeight: Int32 = 0
    var sourceVideoFrameRate: Double?
    var activeVideoDecoder: String?
    var activeAudioDecoder: String?
    var activeUpscale: UpscaleStatus?

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
    var audioEnhancement: AudioEnhancementMode = .reference

    var subtitleTracks: [TrackInfo] = []
    var activeSubtitleTrackIndex: Int?
    var subtitleDelaySeconds: Double = 0

    var previewAudioOptions: [PlayerDrawerAudioOption] = []
    var previewSubtitleOptions: [PlayerDrawerSubtitleOption] = []

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

    var chapters: [PlaybackChapter] = []
    var previewPlayheadOverrideSeconds: Double?

    // Tactile Coalesced Seeking & Continuous Siri Remote Touch Scrubbing
    var coalescedSeekDelta: Double = 0
    var coalescedSeekPreviewTarget: Double?
    var isScrubbing: Bool = false
    let scrubState = PlayerScrubState()

    let engine: AetherEngine
    let comfort: ComfortPreferences
    let transport: any PlayerTransportControlling
    let audioActivator: any NativeAudioActivating

    @ObservationIgnored var wasPlayingBeforeScrub: Bool = false
    @ObservationIgnored var pendingScrubPreviewTarget: Double?
    @ObservationIgnored var scrubPreviewLoopTask: Task<Void, Never>?
    @ObservationIgnored weak var compositorPreviewView: AetherScrubPreviewView?

    @ObservationIgnored var resolveTask: Task<Void, Never>?
    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var firstFrameFallbackTask: Task<Void, Never>?
    @ObservationIgnored var transientBannerTask: Task<Void, Never>?
    @ObservationIgnored var remoteCommandToastTask: Task<Void, Never>?
    @ObservationIgnored var nowPlayingArtworkTask: Task<Void, Never>?
    @ObservationIgnored var engineChapters: [ChapterInfo] = []
    @ObservationIgnored var registeredStreamToken: String?
    @ObservationIgnored var activeClient: LunaCoreClient?
    @ObservationIgnored var userManuallySelectedSubtitle: Bool = false
    @ObservationIgnored var didApplyInitialSmartRule: Bool = false
    @ObservationIgnored var didBindEnginePublishers: Bool = false

    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    @ObservationIgnored var coalescedSeekTask: Task<Void, Never>?
    @ObservationIgnored var chapterSeekTask: Task<Void, Never>?
    @ObservationIgnored var smartRuleTask: Task<Void, Never>?
    @ObservationIgnored var switchSourceTask: Task<Void, Never>?
    @ObservationIgnored var audioDelayCommitTask: Task<Void, Never>?
    @ObservationIgnored var upscaleReloadTask: Task<Void, Never>?
    @ObservationIgnored var foregroundRestoreTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pausedRestoreResumeTask: Task<Void, Never>?
    @ObservationIgnored private var pausedRestoreResumeToken: UInt64 = 0
    @ObservationIgnored var scrubCommitTask: Task<Void, Never>?
    @ObservationIgnored var scrubCommitToken: UInt64 = 0
    @ObservationIgnored var ringHoldLoopTask: Task<Void, Never>?
    @ObservationIgnored private var didTeardown: Bool = false
    @ObservationIgnored var engineOwnerToken: UInt64 = 0
    @ObservationIgnored var isDismissing: Bool = false
    @ObservationIgnored var pendingStopSnapshot: PendingStopSnapshot?
    @ObservationIgnored var pendingHandedOverSessionId: String?
    @ObservationIgnored var pendingInflightPrepareTask: Task<TvPrepareResponse?, Never>?
    @ObservationIgnored var lastObservedPhase: PlaybackPhase = .idle
    @ObservationIgnored var isForegroundActive: Bool = true
    @ObservationIgnored var lastForegroundPlaybackWasPlaying: Bool = false
    @ObservationIgnored var userDesiredPlayingDuringRestore: Bool?
    @ObservationIgnored var needsNativeAudioActivationAfterPausedRestore: Bool = false
    @ObservationIgnored var lastReportedServerState: String?
    @ObservationIgnored var onUnauthorized: (() -> Void)?

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        transport: (any PlayerTransportControlling)? = nil,
        audioActivator: any NativeAudioActivating = DefaultNativeAudioActivator(),
        bindOnInit: Bool = true
    ) {
        self.engine = engine
        self.comfort = comfort
        self.transport = transport ?? AetherEngineTransport(engine: engine)
        self.audioActivator = audioActivator
        if bindOnInit {
            bindEnginePublishersIfNeeded()
        }
    }

    func bindEnginePublishersIfNeeded() {
        guard !didBindEnginePublishers else { return }
        didBindEnginePublishers = true
        bindEnginePublishers()
    }

    /// True only once the first decoded video frame is ready and HDMI range/frame-rate
    /// switching has settled (or when an in-place source replacement is holding a still frame).
    var isPictureReadyForReveal: Bool {
        PlaybackCurtainWatchdog.isPictureReadyForReveal(
            hasFatalError: fatalError != nil,
            isSwitchingSource: isSwitchingSource,
            isResolving: isResolving,
            isRestoringFromBackground: isRestoringFromBackground,
            needsForegroundVideoRestore: transport.needsForegroundVideoRestore,
            firstFrameFallbackUnlocked: firstFrameFallbackUnlocked,
            hasFirstFrameReadyForDisplay: hasFirstFrameReadyForDisplay,
            isAwaitingDisplaySwitch: isAwaitingDisplaySwitch
        )
    }

    var effectiveDurationSeconds: Double {
        if durationSeconds > 0 {
            return durationSeconds
        }
        return activeSession?.stream.declaredDurationSeconds ?? activeSession?.item.runtimeSeconds ?? 0
    }

    // MARK: - Lifecycle & Commands

    func configurePreviewPlayback(
        request: PlaybackLaunchRequest,
        session: TvPlaybackSession,
        client: LunaCoreClient?,
        audioOptions: [PlayerDrawerAudioOption] = PreviewMockFixtures.previewAudioOptions,
        subtitleOptions: [PlayerDrawerSubtitleOption] = PreviewMockFixtures.previewSubtitleOptions,
        candidates: [TvCandidateInfo] = PreviewMockFixtures.previewCandidates
    ) {
        bindEnginePublishersIfNeeded()
        currentRequest = request
        activeSession = session
        activeClient = client
        fatalError = nil
        isResolving = false
        hasFirstFrameReadyForDisplay = true
        isAwaitingDisplaySwitch = false
        firstFrameFallbackUnlocked = true
        isRestoringFromBackground = false
        playbackPhase = .paused
        let declared = session.stream.declaredDurationSeconds ?? session.item.runtimeSeconds ?? 6180
        durationSeconds = declared
        previewPlayheadOverrideSeconds = request.startPositionSeconds ?? session.stream.startPositionSeconds ?? 1840
        videoFormat = .sdr
        sourceDVProfile = nil
        videoRoute = .loopback
        audioDelivery = .bridged
        sourceVideoCodecName = "hevc"
        sourceVideoWidth = 1920
        sourceVideoHeight = 1080
        sourceVideoFrameRate = 24.0
        activeVideoDecoder = "VideoToolbox HW"
        activeAudioDecoder = "Dolby Atmos 7.1.4"
        previewAudioOptions = audioOptions
        previewSubtitleOptions = subtitleOptions
        activeAudioTrackIndex = audioOptions.first?.id
        activeSubtitleTrackIndex = subtitleOptions.first?.id
        alternatives = candidates
        alternativesSessionId = session.sessionId
        chapters = PlaybackChapter.mergeRaw(
            probeChapters: session.chapters ?? [],
            engineChapters: [],
            mediaDuration: declared
        )
    }

    func start(request: PlaybackLaunchRequest, client: LunaCoreClient?) {
        bindEnginePublishersIfNeeded()
        engineOwnerToken = PlayerAudioSessionCoordinator.shared.claimEngineOwnership()
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        lastForegroundPlaybackWasPlaying = false
        needsNativeAudioActivationAfterPausedRestore = false
        isDismissing = false
        pendingStopSnapshot = nil
        pendingInflightPrepareTask?.cancel()
        pendingInflightPrepareTask = request.inflightPrepareTask
        pendingHandedOverSessionId = request.preparedSession?.sessionId ?? request.prepareToken
        if let preTok = request.preparedSession?.streamToken, preTok.count >= 8 {
            if let oldTok = registeredStreamToken, oldTok.count >= 8, oldTok != preTok {
                EngineLog.unregisterSecret(oldTok)
            }
            _ = EngineLog.registerSecret(preTok)
            registeredStreamToken = preTok
        }
        didTeardown = false
        fatalError = nil
        firstFrameFallbackUnlocked = false
        lastObservedPhase = .idle
        lastReportedServerState = nil
        currentRequest = request
        guard let client else {
            pendingInflightPrepareTask?.cancel()
            pendingInflightPrepareTask = nil
            pendingHandedOverSessionId = nil
            fatalError = "Mangler tilkobling til LunaCore."
            isResolving = false
            return
        }
        self.activeClient = client
        self.alternatives = []
        self.alternativesSessionId = nil
        resolveTask?.cancel()
        resolveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runResolveAndLoad(request: request, client: client, isReplacement: false)
        }
    }

    func playNextEpisode(_ next: TvNextEpisodeSummary) {
        guard let client = activeClient, let current = activeSession else { return }
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        needsNativeAudioActivationAfterPausedRestore = false
        resolveTask?.cancel()
        pendingInflightPrepareTask?.cancel()
        pendingInflightPrepareTask = nil
        pendingHandedOverSessionId = nil
        switchSourceTask?.cancel()
        switchSourceTask = nil
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        lastReportedServerState = nil

        let seriesName = current.item.seriesTitle
        let cleanNextTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            next.title,
            seriesTitle: seriesName,
            season: next.season,
            episode: next.episode
        ) ?? ""
        let req = PlaybackLaunchRequest(
            itemId: next.itemId,
            title: cleanNextTitle,
            seriesTitle: seriesName,
            season: next.season,
            episode: next.episode,
            startPositionSeconds: 0,
            backdropUrl: next.stillUrl ?? current.item.backdropUrl,
            logoUrl: current.item.logoUrl
        )
        currentRequest = req
        alternatives = []
        alternativesSessionId = nil
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        resolveHeadline = nil
        resolvePercent = 12
        resolveStageLabel = "Starter neste episode…"
        isResolving = true
        hasFirstFrameReadyForDisplay = false
        firstFrameFallbackUnlocked = false

        let prevSessionId = current.sessionId
        let finalPos = max(0, transport.currentTime)
        let finalDur = max(0, effectiveDurationSeconds)
        let inCredits = chapters.contains { $0.kind == .credits && finalPos >= $0.startSeconds }
        let isCompleted = playbackPhase == .ended || inCredits || (finalDur > 0 && finalPos / finalDur >= 0.75)
        activeSession = nil
        engine.prepareForItemReplacement()

        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: prevSessionId,
                state: "stopped",
                positionSeconds: finalPos,
                durationSeconds: finalDur,
                completed: isCompleted ? true : nil
            )
        }

        resolveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runResolveAndLoad(request: req, client: client, isReplacement: true)
        }
    }

    nonisolated static func shouldActivateNativeAudioBeforePlayOnResume(
        wasPlaying: Bool,
        needsNativeAudioActivationAfterPausedRestore: Bool
    ) -> Bool {
        !wasPlaying && needsNativeAudioActivationAfterPausedRestore
    }

    func cancelPendingPausedRestoreResume() {
        pausedRestoreResumeToken &+= 1
        pausedRestoreResumeTask?.cancel()
        pausedRestoreResumeTask = nil
    }

    func activateNativeAudioForPendingResumeIfNeeded() async {
        guard needsNativeAudioActivationAfterPausedRestore else { return }
        await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
    }

    private func beginPausedRestoreResumeWithNativeAudioActivation() {
        cancelPendingScrubCommit()
        cancelPendingPausedRestoreResume()
        pausedRestoreResumeToken &+= 1
        let resumeToken = pausedRestoreResumeToken
        let expectedSessionId = activeSession?.sessionId

        if isForegroundActive && !transport.needsForegroundVideoRestore {
            lastForegroundPlaybackWasPlaying = true
        }

        pausedRestoreResumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.activateNativeAudioForPendingResumeIfNeeded()
            if self.pausedRestoreResumeToken == resumeToken {
                self.pausedRestoreResumeTask = nil
            }
            guard !Task.isCancelled,
                  self.pausedRestoreResumeToken == resumeToken,
                  !self.isTeardownCompleted,
                  self.fatalError == nil,
                  !self.isResolving,
                  !self.isSwitchingSource,
                  !self.isRestoringFromBackground,
                  !self.isScrubbing,
                  self.isForegroundActive,
                  !self.transport.needsForegroundVideoRestore,
                  self.activeSession?.sessionId == expectedSessionId else {
                return
            }
            self.needsNativeAudioActivationAfterPausedRestore = false
            if self.transport.state == .paused || self.transport.state == .loading {
                self.transport.play()
            }
            if self.isForegroundActive && !self.transport.needsForegroundVideoRestore {
                self.lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                    playbackPhase: self.transport.playbackPhase,
                    engineState: self.transport.state
                )
            }
        }
    }

    func togglePlayPause() {
        if isRestoringFromBackground {
            let currentTarget = userDesiredPlayingDuringRestore ?? lastForegroundPlaybackWasPlaying
            let nextTarget = !currentTarget
            userDesiredPlayingDuringRestore = nextTarget
            lastForegroundPlaybackWasPlaying = nextTarget
            return
        }
        if pausedRestoreResumeTask != nil || scrubCommitTask != nil {
            cancelPendingPausedRestoreResume()
            cancelPendingScrubCommit()
            if isForegroundActive && !transport.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = false
            }
            return
        }
        let wasPlaying = Self.isActiveTransportIntent(
            playbackPhase: transport.playbackPhase,
            engineState: transport.state
        )
        if Self.shouldActivateNativeAudioBeforePlayOnResume(
            wasPlaying: wasPlaying,
            needsNativeAudioActivationAfterPausedRestore: needsNativeAudioActivationAfterPausedRestore
        ) {
            beginPausedRestoreResumeWithNativeAudioActivation()
            return
        }
        transport.togglePlayPause()
        if isForegroundActive && !transport.needsForegroundVideoRestore {
            lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                playbackPhase: transport.playbackPhase,
                engineState: transport.state
            )
        }
    }

    func triggerSourceSwitch(to candidateId: String) {
        guard activeClient != nil, activeSession != nil else { return }
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        needsNativeAudioActivationAfterPausedRestore = false
        fatalError = nil
        isSwitchingSource = true
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        switchSourceTask?.cancel()
        switchSourceTask = Task { @MainActor [weak self] in
            await self?.switchSource(to: candidateId)
        }
    }

    func loadAlternatives() async {
        guard let client = activeClient, let sessionId = activeSession?.sessionId else { return }
        isLoadingAlternatives = true
        defer { isLoadingAlternatives = false }
        if let res = try? await client.fetchAlternatives(sessionId: sessionId) {
            alternatives = res.alternatives
            alternativesSessionId = sessionId
        }
    }

    // MARK: - Tactile Coalesced Seek & Chapter Seek

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
            try? await Task.sleep(nanoseconds: 220_000_000)
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

    func teardownAndStop(onComplete: (@MainActor @Sendable () -> Void)? = nil) {
        guard !didTeardown else { return }
        didTeardown = true
        cancelAllSessionTasks()
        resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false

        let snapshot = pendingStopSnapshot ?? captureStopSnapshot()
        pendingStopSnapshot = nil
        pendingHandedOverSessionId = nil
        pendingInflightPrepareTask = nil
        ArtworkPipeline.shared.exitPlaybackMemoryMode()
        cancellables.removeAll()
        didBindEnginePublishers = false

        if PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(engineOwnerToken) {
            PlayerNowPlayingCoordinator.clear(engine: engine)
            let resetOnExit = PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: comfort.menuDisplayMode,
                videoFormat: videoFormat,
                isForegroundActive: isForegroundActive
            )
            transport.stop(resetDisplayCriteria: resetOnExit, finalTeardown: true)
            if resetOnExit {
                PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            } else {
                if comfort.menuDisplayMode == .preserveHDR60HzQMS {
                    PlayerAudioSessionCoordinator.shared.applyMenu60HzHDRCriteriaIfNeeded(videoFormat: videoFormat)
                }
                PlayerAudioSessionCoordinator.shared.holdDisplayCriteriaUntilBackground(engine: engine)
            }
        }

        if let tok = registeredStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            registeredStreamToken = nil
        }

        if let client = snapshot.client, let sessionId = snapshot.sessionId, !sessionId.isEmpty {
            snapshot.inflightPrepareTask?.cancel()
            let finalPos = snapshot.finalPos
            let finalDur = snapshot.finalDur
            let isCompleted = snapshot.isCompleted
            Task.detached {
                _ = try? await client.sendHeartbeat(
                    sessionId: sessionId,
                    state: "stopped",
                    positionSeconds: finalPos,
                    durationSeconds: finalDur,
                    completed: isCompleted ? true : nil
                )
                if let onComplete {
                    await onComplete()
                }
            }
        } else if let client = snapshot.client, let inflightPrep = snapshot.inflightPrepareTask {
            inflightPrep.cancel()
            Task.detached {
                if let latePrep = await inflightPrep.value {
                    if let lateTok = latePrep.playbackSession?.streamToken, lateTok.count >= 8 {
                        EngineLog.unregisterSecret(lateTok)
                    }
                    if let orphanSid = latePrep.playbackSession?.sessionId ?? latePrep.prepareToken,
                       !orphanSid.isEmpty {
                        _ = try? await client.sendHeartbeat(
                            sessionId: orphanSid,
                            state: "stopped",
                            positionSeconds: 0,
                            durationSeconds: 0
                        )
                    }
                }
                if let onComplete {
                    await onComplete()
                }
            }
        } else {
            snapshot.inflightPrepareTask?.cancel()
            onComplete?()
        }
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

    func updateIdleTimer(for phase: PlaybackPhase) {
        switch phase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            UIApplication.shared.isIdleTimerDisabled = true
        case .paused, .idle, .ended, .error:
            UIApplication.shared.isIdleTimerDisabled = isResolving || isScrubbing || isRestoringFromBackground
        }
    }

    var isTeardownCompleted: Bool {
        didTeardown
    }
}
