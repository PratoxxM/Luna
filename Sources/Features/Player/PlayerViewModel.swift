import Foundation
import CoreGraphics
import UIKit
import SwiftUI
import Combine
import AetherBridge

/// Isolated high-frequency scrubbing state so touch-surface updates during
/// 60–120 Hz Siri Remote panning only invalidate `TimelineScrubberLeafView`.
@MainActor
final class PlayerScrubState: ObservableObject {
    @Published var targetSeconds: Double = 0
    @Published var originSeconds: Double = 0
    @Published var previewImage: CGImage?
}

@MainActor
final class PlayerViewModel: ObservableObject {
    // Resolve & First-Frame Reveal State
    @Published var isResolving: Bool = true
    @Published var resolveStageKey: String = "searching"
    @Published var resolveStageLabel: String = "Klargjør strøm…"
    @Published var resolvePercent: Int = 12
    @Published var resolveHeadline: String?
    @Published var fatalError: String?
    @Published var transientBannerMessage: String?

    @Published var hasFirstFrameReadyForDisplay: Bool = false
    @Published var isAwaitingDisplaySwitch: Bool = false
    @Published var startupProgress: StartupProgress?
    @Published var firstFrameFallbackUnlocked: Bool = false
    @Published var isRestoringFromBackground: Bool = false

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
    private var lastObservedPhase: PlaybackPhase = .idle
    var isForegroundActive: Bool = true
    var lastForegroundPlaybackWasPlaying: Bool = false
    var userDesiredPlayingDuringRestore: Bool?
    var needsNativeAudioActivationAfterPausedRestore: Bool = false
    var nativeAudioActivatorForTesting: (@Sendable (VideoRoute) async -> Void)?
    var resumePlayActionForTesting: (@MainActor () -> Void)?
    var scrubSeekActionForTesting: (@MainActor (Double) async -> Void)?
    var pauseActionForTesting: (@MainActor () -> Void)?
    var stopActionForTesting: (@MainActor (_ resetDisplayCriteria: Bool, _ finalTeardown: Bool) -> Void)?
    var lastReportedServerState: String?
    var onUnauthorized: (() -> Void)?

    init(engine: AetherEngine, comfort: ComfortPreferences) {
        self.engine = engine
        self.comfort = comfort
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
        if isResolving || isRestoringFromBackground || engine.needsForegroundVideoRestore {
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
        let finalPos = max(0, engine.currentTime)
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
        let videoRoute = engine.videoRoute
        if let customActivator = nativeAudioActivatorForTesting {
            await customActivator(videoRoute)
        } else {
            await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(
                videoRoute: videoRoute
            )
        }
    }

    private func beginPausedRestoreResumeWithNativeAudioActivation() {
        cancelPendingScrubCommit()
        cancelPendingPausedRestoreResume()
        pausedRestoreResumeToken &+= 1
        let resumeToken = pausedRestoreResumeToken
        let expectedSessionId = activeSession?.sessionId

        if isForegroundActive && !engine.needsForegroundVideoRestore {
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
                  !self.engine.needsForegroundVideoRestore,
                  self.activeSession?.sessionId == expectedSessionId else {
                return
            }
            self.needsNativeAudioActivationAfterPausedRestore = false
            if let customPlay = self.resumePlayActionForTesting {
                customPlay()
            } else if self.engine.state == .paused || self.engine.state == .loading {
                self.engine.play()
            }
            if self.isForegroundActive && !self.engine.needsForegroundVideoRestore {
                self.lastForegroundPlaybackWasPlaying = self.resumePlayActionForTesting != nil
                    ? true
                    : Self.isActiveTransportIntent(
                        playbackPhase: self.engine.playbackPhase,
                        engineState: self.engine.state
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
            if isForegroundActive && !engine.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = false
            }
            return
        }
        let wasPlaying = Self.isActiveTransportIntent(
            playbackPhase: engine.playbackPhase,
            engineState: engine.state
        )
        if Self.shouldActivateNativeAudioBeforePlayOnResume(
            wasPlaying: wasPlaying,
            needsNativeAudioActivationAfterPausedRestore: needsNativeAudioActivationAfterPausedRestore
        ) {
            beginPausedRestoreResumeWithNativeAudioActivation()
            return
        }
        engine.togglePlayPause()
        if isForegroundActive && !engine.needsForegroundVideoRestore {
            lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                playbackPhase: engine.playbackPhase,
                engineState: engine.state
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
        let base = coalescedSeekPreviewTarget ?? max(0, engine.currentTime)
        let accumulatedDelta = coalescedSeekDelta + delta
        let rawTarget = max(0, base + delta)
        let clampedTarget = dur > 1 ? min(dur - 0.5, rawTarget) : rawTarget

        coalescedSeekDelta = accumulatedDelta
        coalescedSeekPreviewTarget = clampedTarget

        coalescedSeekTask?.cancel()
        coalescedSeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, let self else { return }
            let finalTarget = self.coalescedSeekPreviewTarget ?? max(0, self.engine.currentTime)
            await self.engine.seek(to: finalTarget, exact: false)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.coalescedSeekDelta = 0
            self.coalescedSeekPreviewTarget = nil
        }
    }

    func seekToChapter(_ chapter: PlaybackChapter) {
        Task { @MainActor in
            await engine.seek(to: max(0, chapter.startSeconds), exact: true)
        }
    }

    func activeChapter(at timeSeconds: Double) -> PlaybackChapter? {
        guard !chapters.isEmpty, timeSeconds.isFinite else { return nil }
        return chapters.first { timeSeconds >= $0.startSeconds && timeSeconds < $0.endSeconds }
            ?? chapters.last { timeSeconds >= $0.startSeconds }
    }

    // MARK: - Audio & Subtitle Controls

    func selectAudioTrack(_ index: Int) {
        engine.selectAudioTrack(index: index)
        activeAudioTrackIndex = index
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

        guard !isResolving && !isSwitchingSource else {
            return
        }

        let targetSeconds = Double(clamped) / 1000.0
        if !debounceEngineCommit {
            engine.setAudioDelay(targetSeconds)
            return
        }

        audioDelayCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, !self.isResolving, !self.isSwitchingSource else { return }
            self.engine.setAudioDelay(Double(self.audioDelayMs) / 1000.0)
            self.audioDelayCommitTask = nil
        }
    }

    func setAudioEnhancement(_ mode: AudioEnhancementMode) {
        audioEnhancement = mode
        engine.setAudioShaping(comfort.buildAudioShaping(enhancement: mode))
    }

    func selectSubtitleManually(_ index: Int) {
        userManuallySelectedSubtitle = true
        engine.selectSubtitleTrack(index: index)
        activeSubtitleTrackIndex = index
    }

    func clearSubtitleManually() {
        userManuallySelectedSubtitle = true
        engine.clearSubtitle()
        activeSubtitleTrackIndex = nil
    }

    func adjustSubtitleDelay(by delta: Double) {
        let rounded = ((subtitleDelaySeconds + delta) * 10).rounded() / 10
        let updated = rounded.clamped(to: -10.0...10.0)
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
            if let stopOverride = stopActionForTesting {
                stopOverride(resetOnExit, true)
            } else {
                engine.stop(resetDisplayCriteria: resetOnExit, finalTeardown: true)
            }
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

    private func bindEnginePublishers() {
        engine.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                let previousPhase = self.lastObservedPhase
                self.lastObservedPhase = phase
                self.playbackPhase = phase
                self.updateIdleTimer(for: phase)
                if self.isForegroundActive,
                   !self.isRestoringFromBackground,
                   !self.isResolving,
                   !self.isSwitchingSource,
                   !self.engine.needsForegroundVideoRestore {
                    self.lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                        playbackPhase: phase,
                        engineState: self.engine.state
                    )
                }
                if case .error(let errMsg) = phase {
                    guard !self.isRestoringFromBackground else { return }
                    self.heartbeatTask?.cancel()
                    self.heartbeatTask = nil
                    self.isResolving = false
                    self.isSwitchingSource = false
                    if self.fatalError == nil {
                        let cleaned = errMsg.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.fatalError = cleaned.isEmpty ? "Avspillingsfeil i strømmen." : cleaned
                    }
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(overrideState: "stopped")
                    }
                } else if phase == .paused || phase == .ended {
                    guard !self.isRestoringFromBackground, !self.isDismissing else { return }
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(overrideState: phase == .ended ? "stopped" : "paused", completed: phase == .ended)
                    }
                } else if phase == .playing, previousPhase != .playing {
                    guard !self.isRestoringFromBackground else { return }
                    if self.needsNativeAudioActivationAfterPausedRestore {
                        self.needsNativeAudioActivationAfterPausedRestore = false
                        let videoRoute = self.engine.videoRoute
                        Task {
                            await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(
                                videoRoute: videoRoute
                            )
                        }
                    }
                    if self.lastReportedServerState != nil,
                       self.lastReportedServerState != "playing" {
                        Task { @MainActor [weak self] in
                            await self?.sendHeartbeatOnce(overrideState: "playing")
                        }
                    }
                }
            }
            .store(in: &cancellables)

        engine.$hasFirstFrameReadyForDisplay.assign(to: &$hasFirstFrameReadyForDisplay)
        engine.$isAwaitingDisplaySwitch.assign(to: &$isAwaitingDisplaySwitch)
        engine.$startupProgress.assign(to: &$startupProgress)

        engine.$duration
            .sink { [weak self] dur in
                guard let self else { return }
                self.durationSeconds = dur
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$mediaChapters
            .sink { [weak self] ch in
                guard let self else { return }
                self.engineChapters = ch
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$videoFormat.assign(to: &$videoFormat)
        engine.$sourceDVProfile.assign(to: &$sourceDVProfile)
        engine.$dolbyVisionConversion.assign(to: &$dolbyVisionConversion)
        engine.$videoRoute.assign(to: &$videoRoute)
        engine.$audioDelivery.assign(to: &$audioDelivery)
        engine.$sourceVideoCodecName.assign(to: &$sourceVideoCodecName)
        engine.$sourceVideoWidth.assign(to: &$sourceVideoWidth)
        engine.$sourceVideoHeight.assign(to: &$sourceVideoHeight)
        engine.$sourceVideoFrameRate.assign(to: &$sourceVideoFrameRate)
        engine.$activeVideoDecoder.assign(to: &$activeVideoDecoder)
        engine.$activeAudioDecoder.assign(to: &$activeAudioDecoder)

        engine.$audioTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                self.audioTracks = tracks
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !self.subtitleTracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex.assign(to: &$activeAudioTrackIndex)
        engine.$subtitleTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                self.subtitleTracks = tracks
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !tracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeSubtitleTrackIndex.assign(to: &$activeSubtitleTrackIndex)

        comfort.$audioDelayMs
            .sink { [weak self] updatedMs in
                guard let self, self.audioDelayMs != updatedMs else { return }
                self.audioDelayMs = updatedMs
            }
            .store(in: &cancellables)
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
