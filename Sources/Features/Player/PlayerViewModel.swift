import Foundation
import UIKit
import Combine
import AetherBridge

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var isResolving: Bool = true
    @Published var resolveStageLabel: String = "Klargjør strøm…"
    @Published var resolvePercent: Int = 10
    @Published var resolveHeadline: String?
    @Published var fatalError: String?

    @Published var activeSession: TvPlaybackSession?
    @Published var alternatives: [TvCandidateInfo] = []
    @Published var isLoadingAlternatives: Bool = false
    @Published var isSwitchingSource: Bool = false
    @Published var nextEpisodePrewarmReady: Bool = false

    @Published var playbackPhase: PlaybackPhase = .idle
    @Published var durationSeconds: Double = 0
    @Published var videoFormat: VideoFormat = .sdr
    @Published var sourceDVProfile: Int?
    @Published var videoRoute: VideoRoute = .none
    @Published var audioDelivery: AudioDelivery = .none
    @Published var audioTracks: [TrackInfo] = []
    @Published var activeAudioTrackIndex: Int?
    @Published var subtitleTracks: [TrackInfo] = []
    @Published var activeSubtitleTrackIndex: Int?
    @Published var subtitleDelaySeconds: Double = 0

    let engine: AetherEngine

    private var cancellables = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var registeredStreamToken: String?
    private var activeClient: BFFClient?

    init(engine: AetherEngine) {
        self.engine = engine
        bindEnginePublishers()
    }

    func start(request: PlaybackLaunchRequest, client: BFFClient?) {
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
        resolveTask = Task { @MainActor in
            await sendHeartbeatOnce(overrideState: "stopped")
            engine.prepareForItemReplacement()
            let req = PlaybackLaunchRequest(
                itemId: next.itemId,
                title: next.title ?? String(format: "S%02dE%02d", next.season, next.episode),
                seriesTitle: current.item.seriesTitle ?? current.item.title,
                startPositionSeconds: 0
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
        let currentPos = max(0, engine.currentTime)
        isSwitchingSource = true
        isResolving = true
        resolveStageLabel = "Bytter kilde på eksakt tidskode…"
        resolvePercent = 65

        do {
            let updatedSession = try await client.switchCandidate(
                sessionId: session.sessionId,
                candidateId: candidateId,
                positionSeconds: currentPos
            )
            engine.prepareForItemReplacement()
            try await mountSessionInEngine(
                updatedSession,
                client: client,
                overrideStartPosition: updatedSession.stream.startPositionSeconds ?? currentPos
            )
            isSwitchingSource = false
            isResolving = false
        } catch {
            isSwitchingSource = false
            isResolving = false
            fatalError = "Kildebytte feilet: \(error.localizedDescription)"
        }
    }

    func adjustSubtitleDelay(by delta: Double) {
        let updated = (subtitleDelaySeconds + delta).clamped(to: -10.0...10.0)
        engine.setSoftwareSubtitleDelay(updated)
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    func teardownAndStop() {
        resolveTask?.cancel()
        resolveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        UIApplication.shared.isIdleTimerDisabled = false

        let client = activeClient
        let session = activeSession
        let finalPos = max(0, engine.currentTime)
        let finalDur = max(0, engine.duration)

        if let tok = registeredStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            registeredStreamToken = nil
        }

        engine.stop(resetDisplayCriteria: true)

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

    private func runResolveAndLoad(request: PlaybackLaunchRequest, client: BFFClient, isReplacement: Bool) async {
        fatalError = nil
        isResolving = true
        nextEpisodePrewarmReady = false
        resolveStageLabel = "Søker etter beste kilde for \(client.roomName)…"
        resolvePercent = 15
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
                resolvedSession = try await awaitWebSocketResolution(wsPath: wsPath, client: client)
            } else {
                throw BFFError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
            }

            resolveStageLabel = "Starter avspilling…"
            resolvePercent = 96
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
            startHeartbeatLoop()
        } catch {
            guard !Task.isCancelled else { return }
            isResolving = false
            UIApplication.shared.isIdleTimerDisabled = false
            fatalError = error.localizedDescription
        }
    }

    private func awaitWebSocketResolution(wsPath: String, client: BFFClient) async throws -> TvPlaybackSession {
        let socket = PlaybackResolveSocket(
            baseURL: client.baseURL,
            wsPath: wsPath,
            headers: client.streamHTTPHeaders(),
            allowSelfSignedLanTLS: client.allowSelfSignedLanTLS
        )

        for try await event in socket.events() {
            if let pct = event.percent {
                resolvePercent = pct
            }
            if let headline = event.winnerHeadline, !headline.isEmpty {
                resolveHeadline = headline
            }
            if let msg = event.message, !msg.isEmpty {
                resolveStageLabel = msg
            }

            if event.type == "resolve.ready", let readySession = event.playbackSession {
                return readySession
            }
            if event.type == "resolve.failed" {
                throw BFFError.serverMessage(502, event.error ?? "Kunne ikke klargjøre strøm.")
            }
        }
        throw BFFError.serverMessage(504, "Mistet sanntidstilkoblingen under klargjøring av strøm.")
    }

    private func mountSessionInEngine(
        _ session: TvPlaybackSession,
        client: BFFClient,
        overrideStartPosition: Double?
    ) async throws {
        guard let streamURL = client.buildAbsoluteURL(session.stream.url) else {
            throw BFFError.invalidURL(session.stream.url)
        }

        if let prev = registeredStreamToken, prev.count >= 8 {
            EngineLog.unregisterSecret(prev)
        }
        if session.streamToken.count >= 8 {
            _ = EngineLog.registerSecret(session.streamToken)
            registeredStreamToken = session.streamToken
        }

        self.activeSession = session
        self.resolveHeadline = session.selectedCandidate.displayHeadline

        // AE#1015: Ensure forward subtitle prefetch stays disabled before loading
        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10

        let options = Self.buildLoadOptions(session: session, client: client)
        let startPos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
        _ = try await engine.load(
            url: streamURL,
            startPosition: startPos > 0.5 ? startPos : nil,
            options: options
        )
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    static func buildLoadOptions(session: TvPlaybackSession, client: BFFClient) -> LoadOptions {
        let cfg = session.aetherConfig
        var options = LoadOptions()

        options.httpHeaders = client.streamHTTPHeaders()
        options.preferDualLayerDolbyVision = cfg.preferDualLayerDolbyVision
        options.dualLayerRoute = cfg.dualLayerRoute == "avPlayerOutput" ? .avPlayerOutput : .softwareHost
        options.dolbyVisionHandling = cfg.dolbyVisionHandling == "baseLayerOnly" ? .baseLayerOnly : .automatic
        options.matchContentEnabled = cfg.matchContentEnabled
        options.displayCriteriaOwner = .engine
        options.attemptsHDRMasterOnUnprovenPanel = cfg.attemptsHDRMasterOnUnprovenPanel

        // Let AetherEngine inspect HDMI capabilities directly via AVPlayer.availableHDRModes
        // when displayCriteriaOwner == .engine so HDMI range/rate switching stays accurate.
        options.panelPresentsDolbyVision = false
        options.panelIsInHDRMode = false

        options.audioBridgeMode = cfg.audioBridgeMode == "lossless" ? .lossless : .surroundCompat

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

        options.preferredAudioLanguages = cfg.preferredAudioLanguages ?? ["nob", "nor", "no", "eng"]
        options.preferredSubtitleLanguages = cfg.preferredSubtitleLanguages ?? ["nob", "nor", "no", "eng"]
        options.skipsContainerAttachments = cfg.skipsContainerAttachments ?? true
        options.generatesBackgroundScrubPreviews = cfg.generatesBackgroundScrubPreviews ?? false
        options.serveIFramePlaylist = cfg.serveIFramePlaylist ?? false
        options.confirmAtmos = cfg.confirmAtmos ?? false
        options.maxConcurrentSourceRequests = cfg.maxConcurrentSourceRequests ?? 2
        options.declaredDurationSeconds = cfg.declaredDurationSeconds ?? session.stream.declaredDurationSeconds

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
        let dur = max(0, engine.duration > 0 ? engine.duration : (session.stream.declaredDurationSeconds ?? 0))

        if let hb = try? await client.sendHeartbeat(
            sessionId: session.sessionId,
            state: stateString,
            positionSeconds: pos,
            durationSeconds: dur
        ) {
            if hb.nextEpisodePrewarmStarted == true {
                nextEpisodePrewarmReady = true
            }
        }
    }

    private func bindEnginePublishers() {
        engine.$playbackPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                self.playbackPhase = phase
                self.updateIdleTimer(for: phase)
                if phase == .paused || phase == .ended {
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(overrideState: phase == .ended ? "stopped" : "paused")
                    }
                }
            }
            .store(in: &cancellables)

        engine.$duration.receive(on: RunLoop.main).assign(to: &$durationSeconds)
        engine.$videoFormat.receive(on: RunLoop.main).assign(to: &$videoFormat)
        engine.$sourceDVProfile.receive(on: RunLoop.main).assign(to: &$sourceDVProfile)
        engine.$videoRoute.receive(on: RunLoop.main).assign(to: &$videoRoute)
        engine.$audioDelivery.receive(on: RunLoop.main).assign(to: &$audioDelivery)
        engine.$audioTracks.receive(on: RunLoop.main).assign(to: &$audioTracks)
        engine.$activeAudioTrackIndex.receive(on: RunLoop.main).assign(to: &$activeAudioTrackIndex)
        engine.$subtitleTracks.receive(on: RunLoop.main).assign(to: &$subtitleTracks)
        engine.$activeSubtitleTrackIndex.receive(on: RunLoop.main).assign(to: &$activeSubtitleTrackIndex)
    }

    private func updateIdleTimer(for phase: PlaybackPhase) {
        switch phase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            UIApplication.shared.isIdleTimerDisabled = true
        case .paused, .idle, .ended, .error:
            UIApplication.shared.isIdleTimerDisabled = isResolving
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
