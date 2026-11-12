import Foundation
import CoreGraphics
import UIKit
import Combine
import AetherBridge

@MainActor
final class PlayerViewModel: ObservableObject {
    // Resolve & First-Frame Reveal State
    @Published var isResolving: Bool = true
    @Published var resolveStageKey: String = "searching"
    @Published var resolveStageLabel: String = "Klargjør strøm…"
    @Published var resolvePercent: Int = 12
    @Published var resolveHeadline: String?
    @Published var fatalError: String?

    @Published var hasFirstFrameReadyForDisplay: Bool = false
    @Published var isAwaitingDisplaySwitch: Bool = false
    @Published var startupProgress: StartupProgress?
    @Published var firstFrameFallbackUnlocked: Bool = false

    // Session, Sources & Next Episode
    @Published var activeSession: TvPlaybackSession?
    @Published var alternatives: [TvCandidateInfo] = []
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
    @Published var scrubTargetSeconds: Double = 0
    @Published var scrubOriginSeconds: Double = 0
    @Published var scrubPreviewImage: CGImage?

    let engine: AetherEngine
    let comfort: ComfortPreferences

    var wasPlayingBeforeScrub: Bool = false
    var pendingScrubPreviewTarget: Double?
    var scrubPreviewLoopTask: Task<Void, Never>?
    weak var compositorPreviewView: AetherScrubPreviewView?

    private var cancellables = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var firstFrameFallbackTask: Task<Void, Never>?
    private var coalescedSeekTask: Task<Void, Never>?
    private var smartRuleTask: Task<Void, Never>?
    private var engineChapters: [ChapterInfo] = []
    private var registeredStreamToken: String?
    private var activeClient: MediaOSClient?
    private var userManuallySelectedSubtitle: Bool = false
    private var didApplyInitialSmartRule: Bool = false

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

    func start(request: PlaybackLaunchRequest, client: MediaOSClient?) {
        guard let client else {
            fatalError = "Mangler tilkobling til MediaOS."
            isResolving = false
            return
        }
        self.activeClient = client
        resolveTask?.cancel()
        resolveTask = Task { @MainActor in
            await runResolveAndLoad(request: request, client: client, isReplacement: false)
        }
    }

    func playNextEpisode(_ next: TvNextEpisodeSummary) {
        guard let client = activeClient, let current = activeSession else { return }
        resolveTask?.cancel()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        resolveTask = Task { @MainActor in
            await sendHeartbeatOnce(overrideState: "stopped")
            engine.prepareForItemReplacement()
            let req = PlaybackLaunchRequest(
                itemId: next.itemId,
                title: next.title ?? String(format: "S%02dE%02d", next.season, next.episode),
                seriesTitle: current.item.seriesTitle ?? current.item.title,
                startPositionSeconds: 0,
                backdropUrl: next.stillUrl ?? current.item.backdropUrl,
                logoUrl: current.item.logoUrl
            )
            await runResolveAndLoad(request: req, client: client, isReplacement: true)
        }
    }

    func loadAlternatives() async {
        guard let client = activeClient, let sessionId = activeSession?.sessionId else { return }
        isLoadingAlternatives = true
        defer { isLoadingAlternatives = false }
        if let res = try? await client.fetchAlternatives(sessionId: sessionId) {
            alternatives = res.alternatives
        }
    }

    func switchSource(to candidateId: String) async {
        guard let client = activeClient, let session = activeSession else { return }
        resetScrubStateOnSessionChange()
        let currentPos = max(0, engine.currentTime)
        isSwitchingSource = true
        resolveStageKey = "switching"
        resolveStageLabel = "Bytter kilde sømløst på samme tidskode…"
        resolvePercent = 70

        do {
            let updatedSession = try await client.switchCandidate(
                sessionId: session.sessionId,
                candidateId: candidateId,
                positionSeconds: currentPos
            )
            // Freeze current decoded frame via HeldStillPresenter so there is zero black blink
            engine.prepareForItemReplacement()
            try await mountSessionInEngine(
                updatedSession,
                client: client,
                overrideStartPosition: updatedSession.stream.startPositionSeconds ?? currentPos
            )
            isSwitchingSource = false
        } catch {
            isSwitchingSource = false
            heartbeatTask?.cancel()
            heartbeatTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
            fatalError = "Kildebytte feilet: \(error.localizedDescription)"
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
        let activeAudio = audioTracks.first(where: { $0.id == activeAudioTrackIndex }) ?? audioTracks.first
        let decision = SmartTrackRuleEngine.evaluate(activeAudio: activeAudio, subtitleTracks: subtitleTracks)
        switch decision {
        case .clearSubtitles:
            if activeSubtitleTrackIndex != nil {
                engine.clearSubtitle()
            }
        case .selectTrack(let trackID):
            if activeSubtitleTrackIndex != trackID {
                engine.selectSubtitleTrack(index: trackID)
            }
        case .keepCurrent:
            break
        }
    }

    func teardownAndStop() {
        resolveTask?.cancel()
        resolveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        firstFrameFallbackTask?.cancel()
        firstFrameFallbackTask = nil
        coalescedSeekTask?.cancel()
        coalescedSeekTask = nil
        smartRuleTask?.cancel()
        smartRuleTask = nil
        resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false

        let client = activeClient
        let session = activeSession
        let finalPos = max(0, engine.currentTime)
        let finalDur = max(0, effectiveDurationSeconds)

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
            }
        }
    }

    // MARK: - Resolve & Engine Load Pipeline

    private func runResolveAndLoad(request: PlaybackLaunchRequest, client: MediaOSClient, isReplacement: Bool) async {
        resetScrubStateOnSessionChange()
        fatalError = nil
        isResolving = true
        firstFrameFallbackUnlocked = false
        nextEpisodePrewarmReady = false
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        resolveStageKey = "searching_indexers"
        resolveStageLabel = "Søker etter beste kilde for \(client.roomName)…"
        resolvePercent = 16
        resolveHeadline = nil
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            let (status, startRes) = try await client.resolvePlayback(
                itemId: request.itemId,
                title: request.title,
                seriesTitle: request.seriesTitle,
                startPositionSeconds: request.startPositionSeconds,
                candidateId: request.candidateId,
                prepareToken: request.prepareToken
            )

            let resolvedSession: TvPlaybackSession
            if status == 200, let immediate = startRes.playbackSession {
                resolvedSession = immediate
            } else if let wsPath = startRes.wsPath {
                resolvedSession = try await awaitWebSocketResolution(
                    wsPath: wsPath,
                    resolveId: startRes.resolveId,
                    client: client
                )
            } else {
                throw MediaOSError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
            }

            resolveStageKey = "awaiting_first_frame"
            resolveStageLabel = "Tilpasser HDMI & starter avspilling…"
            resolvePercent = 95
            if !isReplacement {
                engine.ownsVideoNowPlayingSession = true
                engine.ownsSoftwareNowPlaying = true
            }
            try await mountSessionInEngine(
                resolvedSession,
                client: client,
                overrideStartPosition: request.startPositionSeconds ?? resolvedSession.stream.startPositionSeconds
            )
            isResolving = false
            armFirstFrameFallbackWatchdog()
            startHeartbeatLoop()
        } catch {
            guard !Task.isCancelled else { return }
            isResolving = false
            UIApplication.shared.isIdleTimerDisabled = false
            fatalError = error.localizedDescription
        }
    }

    private func armFirstFrameFallbackWatchdog() {
        firstFrameFallbackTask?.cancel()
        firstFrameFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if !self.hasFirstFrameReadyForDisplay {
                self.firstFrameFallbackUnlocked = true
            }
        }
    }

    private func applyResolveProgressEvent(_ event: TvResolveSocketEvent) {
        if let stage = event.stage, !stage.isEmpty {
            resolveStageKey = stage
        }
        if let pct = event.percent {
            resolvePercent = pct
        }
        if let headline = event.winnerHeadline, !headline.isEmpty {
            resolveHeadline = headline
        }
        if let msg = event.message, !msg.isEmpty {
            resolveStageLabel = msg
        }
    }

    private func awaitWebSocketResolution(
        wsPath: String,
        resolveId: String,
        client: MediaOSClient
    ) async throws -> TvPlaybackSession {
        let socket = PlaybackResolveSocket(
            baseURL: client.baseURL,
            wsPath: wsPath,
            headers: client.streamHTTPHeaders(),
            allowSelfSignedLanTLS: client.allowSelfSignedLanTLS
        )

        do {
            for try await event in socket.events() {
                applyResolveProgressEvent(event)
                if event.type == "resolve.ready", let readySession = event.playbackSession {
                    return readySession
                }
                if event.type == "resolve.failed" {
                    throw MediaOSError.serverMessage(502, event.error ?? "Kunne ikke klargjøre strøm.")
                }
            }
        } catch let err as MediaOSError {
            if case .serverMessage(502, _) = err {
                throw err
            }
            if case .decodingFailed = err {
                throw err
            }
        } catch {
            // Fall through to HTTP snapshot polling if WebSocket upgrade/stream drops
        }

        return try await pollHttpResolutionFallback(resolveId: resolveId, client: client)
    }

    private func pollHttpResolutionFallback(
        resolveId: String,
        client: MediaOSClient
    ) async throws -> TvPlaybackSession {
        let maxAttempts = 60
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 750_000_000)
            }
            let snap = try await client.fetchResolveSnapshot(resolveId: resolveId)
            applyResolveProgressEvent(snap)
            if snap.type == "resolve.ready", let readySession = snap.playbackSession {
                return readySession
            }
            if snap.type == "resolve.failed" {
                throw MediaOSError.serverMessage(502, snap.error ?? "Kunne ikke klargjøre strøm.")
            }
        }
        throw MediaOSError.serverMessage(504, "Tidsavbrudd under klargjøring av strøm.")
    }

    private func mountSessionInEngine(
        _ session: TvPlaybackSession,
        client: MediaOSClient,
        overrideStartPosition: Double?
    ) async throws {
        guard let streamURL = client.buildAbsoluteURL(session.stream.url) else {
            throw MediaOSError.invalidURL(session.stream.url)
        }

        let previousToken = registeredStreamToken
        if session.streamToken.count >= 8 {
            _ = EngineLog.registerSecret(session.streamToken)
            registeredStreamToken = session.streamToken
        }

        self.activeSession = session
        self.resolveHeadline = session.selectedCandidate.displayHeadline
        self.engineChapters = []
        rebuildMergedChapters()

        // AE#1015: Ensure forward subtitle prefetch stays disabled before loading
        engine.maximumSubtitleOffsetSeconds = 0

        let options = Self.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: audioDelaySeconds
        )
        let startPos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
        do {
            _ = try await engine.load(
                url: streamURL,
                startPosition: startPos > 0.5 ? startPos : nil,
                options: options
            )
            if let prev = previousToken, prev.count >= 8, prev != session.streamToken {
                EngineLog.unregisterSecret(prev)
            }
        } catch {
            if let prev = previousToken, prev.count >= 8, prev != session.streamToken {
                EngineLog.unregisterSecret(prev)
            }
            throw error
        }
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
        audioDelaySeconds = engine.audioDelaySeconds
        rebuildMergedChapters()

        if comfort.smartNordicSubtitleRule && !didApplyInitialSmartRule {
            didApplyInitialSmartRule = true
            applySmartSubtitleRule()
        }
    }

    private func rebuildMergedChapters() {
        let probeCh = activeSession?.chapters ?? activeSession?.tracks?.chapters ?? []
        chapters = PlaybackChapter.merge(
            probeChapters: probeCh,
            engineChapters: engineChapters,
            mediaDuration: effectiveDurationSeconds
        )
    }

    // MARK: - 15s Pause-Safe VFS Heartbeat & Screensaver Guard

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        let interval = max(10, activeSession?.heartbeatIntervalSeconds ?? 15)
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.sendHeartbeatOnce(overrideState: nil)
            }
        }
    }

    private func sendHeartbeatOnce(overrideState: String?) async {
        guard let client = activeClient, let session = activeSession else { return }
        let stateString: String
        if let overrideState {
            stateString = overrideState
        } else {
            switch playbackPhase {
            case .paused:
                stateString = "paused"
            case .ended, .idle, .error:
                stateString = "stopped"
            default:
                stateString = "playing"
            }
        }

        let pos = max(0, engine.currentTime)
        let dur = max(0, effectiveDurationSeconds)

        if let hb = try? await client.sendHeartbeat(
            sessionId: session.sessionId,
            state: stateString,
            positionSeconds: pos,
            durationSeconds: dur
        ) {
            if hb.nextEpisodePrewarmStarted == true {
                nextEpisodePrewarmReady = true
            }
            if let vfs = hb.vfsTelemetry {
                lastVfsTelemetry = vfs
            }
            if overrideState == nil,
               let cmd = hb.pendingCommand,
               cmd.type == "reload_switched_stream",
               let switchedSession = cmd.playbackSession {
                await applyServerSwitchedSession(switchedSession, client: client, fallbackPosition: pos)
            }
        }
    }

    private func applyServerSwitchedSession(
        _ switchedSession: TvPlaybackSession,
        client: MediaOSClient,
        fallbackPosition: Double
    ) async {
        guard !isSwitchingSource, !isResolving else { return }
        resetScrubStateOnSessionChange()
        isSwitchingSource = true
        resolveStageKey = "switching"
        resolveStageLabel = "Bytter kilde valgt fra MediaOS Web…"
        resolvePercent = 75
        do {
            engine.prepareForItemReplacement()
            try await mountSessionInEngine(
                switchedSession,
                client: client,
                overrideStartPosition: switchedSession.stream.startPositionSeconds ?? fallbackPosition
            )
            isSwitchingSource = false
        } catch {
            isSwitchingSource = false
            heartbeatTask?.cancel()
            heartbeatTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
            fatalError = "Kildebytte fra Web feilet: \(error.localizedDescription)"
        }
    }

    private func bindEnginePublishers() {
        engine.$playbackPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
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
                }
            }
            .store(in: &cancellables)

        engine.$hasFirstFrameReadyForDisplay.receive(on: RunLoop.main).assign(to: &$hasFirstFrameReadyForDisplay)
        engine.$isAwaitingDisplaySwitch.receive(on: RunLoop.main).assign(to: &$isAwaitingDisplaySwitch)
        engine.$startupProgress.receive(on: RunLoop.main).assign(to: &$startupProgress)

        engine.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] dur in
                guard let self else { return }
                self.durationSeconds = dur
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$mediaChapters
            .receive(on: RunLoop.main)
            .sink { [weak self] ch in
                guard let self else { return }
                self.engineChapters = ch
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$videoFormat.receive(on: RunLoop.main).assign(to: &$videoFormat)
        engine.$sourceDVProfile.receive(on: RunLoop.main).assign(to: &$sourceDVProfile)
        engine.$dolbyVisionConversion.receive(on: RunLoop.main).assign(to: &$dolbyVisionConversion)
        engine.$videoRoute.receive(on: RunLoop.main).assign(to: &$videoRoute)
        engine.$audioDelivery.receive(on: RunLoop.main).assign(to: &$audioDelivery)
        engine.$sourceVideoCodecName.receive(on: RunLoop.main).assign(to: &$sourceVideoCodecName)
        engine.$sourceVideoWidth.receive(on: RunLoop.main).assign(to: &$sourceVideoWidth)
        engine.$sourceVideoHeight.receive(on: RunLoop.main).assign(to: &$sourceVideoHeight)
        engine.$sourceVideoFrameRate.receive(on: RunLoop.main).assign(to: &$sourceVideoFrameRate)
        engine.$activeVideoDecoder.receive(on: RunLoop.main).assign(to: &$activeVideoDecoder)
        engine.$activeAudioDecoder.receive(on: RunLoop.main).assign(to: &$activeAudioDecoder)

        engine.$audioTracks.receive(on: RunLoop.main).assign(to: &$audioTracks)
        engine.$activeAudioTrackIndex.receive(on: RunLoop.main).assign(to: &$activeAudioTrackIndex)
        engine.$subtitleTracks
            .receive(on: RunLoop.main)
            .sink { [weak self] tracks in
                guard let self else { return }
                self.subtitleTracks = tracks
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !tracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeSubtitleTrackIndex.receive(on: RunLoop.main).assign(to: &$activeSubtitleTrackIndex)
    }

    private func updateIdleTimer(for phase: PlaybackPhase) {
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
