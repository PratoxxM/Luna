import Foundation
import CoreGraphics
import UIKit
import SwiftUI
import Combine
import AetherBridge

@MainActor
final class PlayerViewModel: ObservableObject {
    // Resolve & First-Frame Reveal State
    @Published var isResolving: Bool = true
    let startupState = PlayerStartupState()
    @Published var fatalError: String?
    @Published var transientBannerMessage: String?

    @Published var hasFirstFrameReadyForDisplay: Bool = false
    @Published var isAwaitingDisplaySwitch: Bool = false
    @Published var firstFrameFallbackUnlocked: Bool = false
    @Published var isRestoringFromBackground: Bool = false

    var resolveStageKey: String {
        get { startupState.resolveStageKey }
        set { if startupState.resolveStageKey != newValue { startupState.resolveStageKey = newValue } }
    }
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
    @Published var currentRequest: PlaybackLaunchRequest?
    @Published var activeSession: TvPlaybackSession?
    @Published var alternatives: [TvCandidateInfo] = []
    @Published private(set) var alternativesSessionId: String?
    @Published var isLoadingAlternatives: Bool = false
    @Published var isSwitchingSource: Bool = false
    @Published var nextEpisodePrewarmReady: Bool = false
    @Published var lastVfsTelemetry: TvVfsTelemetry?

    // Playback, Tracks & Chapters
    @Published var playbackPhase: PlaybackPhase = .idle
    @Published var durationSeconds: Double = 0
    @Published var videoFormat: VideoFormat = .sdr
    @Published var sourceDVProfile: Int?
    @Published var dolbyVisionConversion: DolbyVisionConversion?
    @Published var videoRoute: VideoRoute = .none
    @Published var audioDelivery: AudioDelivery = .none
    @Published var sourceVideoCodecName: String?
    @Published var sourceVideoWidth: Int32 = 0
    @Published var sourceVideoHeight: Int32 = 0
    @Published var sourceVideoFrameRate: Double?
    @Published var activeVideoDecoder: String?
    @Published var activeAudioDecoder: String?

    @Published var audioTracks: [TrackInfo] = []
    @Published var activeAudioTrackIndex: Int?
    @Published var audioDelayMs: Int
    var audioDelaySeconds: Double { Double(audioDelayMs) / 1000.0 }
    @Published var audioEnhancement: AudioEnhancementMode = .reference

    @Published var subtitleTracks: [TrackInfo] = []
    @Published var activeSubtitleTrackIndex: Int?
    @Published var subtitleDelaySeconds: Double = 0

    @Published var chapters: [PlaybackChapter] = []

    // Tactile Coalesced Seeking & Continuous Siri Remote Touch Scrubbing
    @Published var coalescedSeekDelta: Double = 0
    @Published var coalescedSeekPreviewTarget: Double?
    @Published var isScrubbing: Bool = false
    let scrubState = PlayerScrubState()

    let engine: AetherEngine
    let comfort: ComfortPreferences
    let transport: any PlayerTransportControlling
    let audioActivator: any NativeAudioActivating

    var wasPlayingBeforeScrub: Bool = false
    var pendingScrubPreviewTarget: Double?
    var scrubPreviewLoopTask: Task<Void, Never>?
    weak var compositorPreviewView: AetherScrubPreviewView?

    var resolveTask: Task<Void, Never>?
    var heartbeatTask: Task<Void, Never>?
    var firstFrameFallbackTask: Task<Void, Never>?
    var transientBannerTask: Task<Void, Never>?
    var nowPlayingArtworkTask: Task<Void, Never>?
    var engineChapters: [ChapterInfo] = []
    var registeredStreamToken: String?
    var activeClient: LunaCoreClient?
    var userManuallySelectedSubtitle: Bool = false
    var didApplyInitialSmartRule: Bool = false

    var cancellables = Set<AnyCancellable>()
    var coalescedSeekTask: Task<Void, Never>?
    var smartRuleTask: Task<Void, Never>?
    var switchSourceTask: Task<Void, Never>?
    var audioDelayCommitTask: Task<Void, Never>?
    var foregroundRestoreTask: Task<Void, Never>?
    private(set) var pausedRestoreResumeTask: Task<Void, Never>?
    private var pausedRestoreResumeToken: UInt64 = 0
    var scrubCommitTask: Task<Void, Never>?
    var scrubCommitToken: UInt64 = 0
    private var didTeardown: Bool = false
    var engineOwnerToken: UInt64 = 0
    var isDismissing: Bool = false
    var pendingStopSnapshot: PendingStopSnapshot?
    var lastObservedPhase: PlaybackPhase = .idle
    var isForegroundActive: Bool = true
    var lastForegroundPlaybackWasPlaying: Bool = false
    var userDesiredPlayingDuringRestore: Bool?
    var needsNativeAudioActivationAfterPausedRestore: Bool = false
    var lastReportedServerState: String?
    var onUnauthorized: (() -> Void)?

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        transport: (any PlayerTransportControlling)? = nil,
        audioActivator: any NativeAudioActivating = DefaultNativeAudioActivator()
    ) {
        self.engine = engine
        self.comfort = comfort
        self.transport = transport ?? AetherEngineTransport(engine: engine)
        self.audioActivator = audioActivator
        self.audioDelayMs = comfort.audioDelayMs
        bindEnginePublishers()
    }

    /// True only once the first decoded video frame is ready and HDMI range/frame-rate
    /// switching has settled (or when an in-place source replacement is holding a still frame).
    var isPictureReadyForReveal: Bool {
        if fatalError != nil {
            return false
        }
        if isSwitchingSource {
            return true
        }
        if isResolving || isRestoringFromBackground || transport.needsForegroundVideoRestore {
            return false
        }
        if firstFrameFallbackUnlocked {
            return true
        }
        return hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch
    }

    var effectiveDurationSeconds: Double {
        if durationSeconds > 0 {
            return durationSeconds
        }
        return activeSession?.stream.declaredDurationSeconds ?? activeSession?.item.runtimeSeconds ?? 0
    }

    // MARK: - Lifecycle & Commands

    func start(request: PlaybackLaunchRequest, client: LunaCoreClient?) {
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
        didTeardown = false
        fatalError = nil
        firstFrameFallbackUnlocked = false
        lastObservedPhase = .idle
        lastReportedServerState = nil
        currentRequest = request
        guard let client else {
            fatalError = "Mangler tilkobling til LunaCore."
            isResolving = false
            return
        }
        self.activeClient = client
        self.alternatives = []
        self.alternativesSessionId = nil
        resolveTask?.cancel()
        resolveTask = Task { @MainActor in
            await runResolveAndLoad(request: request, client: client, isReplacement: false)
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
        nextEpisodePrewarmReady = false
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
        Task { @MainActor [weak self] in
            await self?.transport.seek(to: max(0, chapter.startSeconds), exact: true)
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
        cancellables.removeAll()

        if PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(engineOwnerToken) {
            PlayerNowPlayingCoordinator.clear(engine: engine)
            let resetOnExit = PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                keepDisplayModeInMenuAfterPlayback: comfort.keepDisplayModeInMenuAfterPlayback,
                isForegroundActive: isForegroundActive
            )
            transport.stop(resetDisplayCriteria: resetOnExit, finalTeardown: true)
            if resetOnExit {
                PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            } else {
                PlayerAudioSessionCoordinator.shared.holdDisplayCriteriaUntilBackground(engine: engine)
            }
        }

        if let tok = registeredStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            registeredStreamToken = nil
        }

        if let client = snapshot.client, let sessionId = snapshot.sessionId {
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
        } else {
            onComplete?()
        }
    }

    func rebuildMergedChapters() {
        let probeCh = activeSession?.chapters ?? activeSession?.tracks?.chapters ?? []
        chapters = PlaybackChapter.merge(
            probeChapters: probeCh,
            engineChapters: engineChapters,
            mediaDuration: effectiveDurationSeconds
        )
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
