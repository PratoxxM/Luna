import Foundation
import CoreGraphics
import UIKit
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

    // Session, Sources & Next Episode
    @Published private(set) var currentRequest: PlaybackLaunchRequest?
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
    @Published var audioDelaySeconds: Double = 0
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

    private var cancellables = Set<AnyCancellable>()
    private var coalescedSeekTask: Task<Void, Never>?
    private var smartRuleTask: Task<Void, Never>?
    var switchSourceTask: Task<Void, Never>?
    private var didTeardown: Bool = false
    private var lastObservedPhase: PlaybackPhase = .idle
    var lastReportedServerState: String?
    var onUnauthorized: (() -> Void)?

    init(engine: AetherEngine, comfort: ComfortPreferences) {
        self.engine = engine
        self.comfort = comfort
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
        if isResolving {
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
        resolveTask?.cancel()
        switchSourceTask?.cancel()
        switchSourceTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        lastReportedServerState = nil

        let req = PlaybackLaunchRequest(
            itemId: next.itemId,
            title: next.title ?? String(format: "S%02dE%02d", next.season, next.episode),
            seriesTitle: current.item.seriesTitle ?? current.item.title,
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
        activeSession = nil
        engine.prepareForItemReplacement()

        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: prevSessionId,
                state: "stopped",
                positionSeconds: finalPos,
                durationSeconds: finalDur
            )
        }

        resolveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runResolveAndLoad(request: req, client: client, isReplacement: true)
        }
    }

    func triggerSourceSwitch(to candidateId: String) {
        guard activeClient != nil, activeSession != nil else { return }
        fatalError = nil
        isSwitchingSource = true
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

    func adjustAudioDelay(by deltaSeconds: Double) {
        let next = ((audioDelaySeconds + deltaSeconds) * 20).rounded() / 20
        let clamped = next.clamped(to: -2.0...2.0)
        engine.setAudioDelay(clamped)
        audioDelaySeconds = engine.audioDelaySeconds
    }

    func resetAudioDelay() {
        engine.setAudioDelay(0)
        audioDelaySeconds = engine.audioDelaySeconds
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
        resolveTask?.cancel()
        resolveTask = nil
        switchSourceTask?.cancel()
        switchSourceTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        firstFrameFallbackTask?.cancel()
        firstFrameFallbackTask = nil
        coalescedSeekTask?.cancel()
        coalescedSeekTask = nil
        smartRuleTask?.cancel()
        smartRuleTask = nil
        transientBannerTask?.cancel()
        transientBannerTask = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false

        let client = activeClient
        let session = activeSession
        let finalPos = max(0, engine.currentTime)
        let finalDur = max(0, effectiveDurationSeconds)

        PlayerNowPlayingCoordinator.clear(engine: engine)
        cancellables.removeAll()
        engine.stop(resetDisplayCriteria: true)

        if let tok = registeredStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            registeredStreamToken = nil
        }

        if let client, let session {
            Task.detached {
                _ = try? await client.sendHeartbeat(
                    sessionId: session.sessionId,
                    state: "stopped",
                    positionSeconds: finalPos,
                    durationSeconds: finalDur
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
                if case .error(let errMsg) = phase {
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
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(overrideState: phase == .ended ? "stopped" : "paused")
                    }
                } else if phase == .playing,
                          previousPhase != .playing,
                          self.lastReportedServerState != nil,
                          self.lastReportedServerState != "playing" {
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(overrideState: "playing")
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
    }

    func updateIdleTimer(for phase: PlaybackPhase) {
        switch phase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            UIApplication.shared.isIdleTimerDisabled = true
        case .paused, .idle, .ended, .error:
            UIApplication.shared.isIdleTimerDisabled = isResolving || isScrubbing
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
