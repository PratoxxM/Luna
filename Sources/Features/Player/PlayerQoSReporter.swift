import Foundation
import Observation
import AetherBridge

/// Owns playback QoS/format state, 15s heartbeat loop, next-episode prewarm handoff,
/// remote command toasts, and `0 Hz` thresholded `DolbyVisionFallbackPolicy`.
@MainActor
@Observable
final class PlayerQoSReporter {
    var transientBannerMessage: String?
    var remoteCommandToastMessage: String?
    var lastVfsTelemetry: TvVfsTelemetry?

    var playbackPhase: PlaybackPhase = .idle
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
    var suggestsHDR10BaseLayer: Bool = false

    @ObservationIgnored weak var host: PlayerViewModel?
    @ObservationIgnored let comfort: ComfortPreferences
    @ObservationIgnored let transport: any PlayerTransportControlling

    @ObservationIgnored var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored var transientBannerTask: Task<Void, Never>?
    @ObservationIgnored var remoteCommandToastTask: Task<Void, Never>?
    @ObservationIgnored var nextEpisodePrewarmTask: Task<Void, Never>?
    @ObservationIgnored var prewarmedNextEpisodeURL: URL?
    @ObservationIgnored var prewarmedNextEpisodeItemId: String?
    @ObservationIgnored var prewarmedNextEpisodeSessionId: String?
    @ObservationIgnored var prewarmedNextEpisodeStreamToken: String?
    @ObservationIgnored var lastObservedPhase: PlaybackPhase = .idle
    @ObservationIgnored var lastReportedServerState: String?
    @ObservationIgnored var lastTelemetrySnapshot: LiveTelemetry?
    @ObservationIgnored private var dvFallbackPolicy = DolbyVisionFallbackPolicy()

    init(
        comfort: ComfortPreferences,
        transport: any PlayerTransportControlling
    ) {
        self.comfort = comfort
        self.transport = transport
    }

    func bindHost(_ host: PlayerViewModel) {
        self.host = host
    }

    func configurePreviewStats(playbackPhase phase: PlaybackPhase) {
        playbackPhase = phase
        videoFormat = .dolbyVision
        sourceDVProfile = 7
        videoRoute = .software
        audioDelivery = .bridged
        sourceVideoCodecName = "hevc"
        sourceVideoWidth = 3840
        sourceVideoHeight = 2160
        sourceVideoFrameRate = 23.976
        activeVideoDecoder = "FFmpeg + Metal P7 FEL"
        activeAudioDecoder = "TrueHD Atmos 7.1.4"
        suggestsHDR10BaseLayer = false
    }

    func resetTelemetryForSession() {
        lastObservedPhase = .idle
        lastReportedServerState = nil
        lastTelemetrySnapshot = nil
        resetDolbyVisionFallback()
    }

    func resetDolbyVisionFallback() {
        dvFallbackPolicy.reset()
        if suggestsHDR10BaseLayer {
            suggestsHDR10BaseLayer = false
        }
    }

    var isProfile7FELActive: Bool {
        videoFormat == .dolbyVision && sourceDVProfile == 7 && dolbyVisionConversion == nil
    }

    var canSwitchToHDR10BaseLayer: Bool {
        (suggestsHDR10BaseLayer || isProfile7FELActive) && comfort.dualLayerOverride != .forceOff
    }

    /// Evaluates 1 Hz engine diagnostics inside `@ObservationIgnored` storage and flips
    /// `@Observable suggestsHDR10BaseLayer` ONLY when crossing the threshold (`0 Hz` steady-state).
    func ingestDiagnosticsTelemetry(_ telemetry: LiveTelemetry?) {
        lastTelemetrySnapshot = telemetry
        guard let telemetry else { return }
        recordDolbyVisionTelemetrySample(droppedFrameCount: telemetry.droppedFrameCount ?? 0)
    }

    func recordDolbyVisionTelemetrySample(droppedFrameCount: Int) {
        let shouldSuggest = dvFallbackPolicy.recordTelemetrySample(
            droppedFrames: droppedFrameCount,
            isProfile7FEL: isProfile7FELActive,
            isBaseLayerForced: comfort.dualLayerOverride == .forceOff
        )
        if shouldSuggest && !suggestsHDR10BaseLayer {
            suggestsHDR10BaseLayer = true
        }
    }

    // MARK: - Heartbeat, Next-Episode Prewarm & Remote Commands

    func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        let interval = max(10, host?.sessionController.activeSession?.heartbeatIntervalSeconds ?? 15)
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.sendHeartbeatOnce(overrideState: nil)
            }
        }
    }

    func sendHeartbeatOnce(overrideState: String?, completed: Bool = false) async {
        guard let host,
              let client = host.sessionController.activeClient,
              let session = host.sessionController.activeSession else {
            return
        }
        let stateString: String
        if let overrideState {
            stateString = overrideState
        } else {
            switch playbackPhase {
            case .paused: stateString = "paused"
            case .ended, .idle, .error: stateString = "stopped"
            default: stateString = "playing"
            }
        }

        let pos = max(0, transport.currentTime)
        let dur = max(0, host.sessionController.effectiveDurationSeconds)
        let delayMs = host.trackController.subtitleDelayMs
        let qosPayload = lastTelemetrySnapshot.map {
            TvPlaybackQosPayload(
                videoRoute: videoRoute.rawValue,
                forwardBufferSeconds: $0.forwardBufferSeconds,
                droppedVideoFrames: $0.droppedFrameCount,
                stallCount: nil
            )
        }

        do {
            let hb = try await client.sendHeartbeat(
                sessionId: session.sessionId,
                state: stateString,
                positionSeconds: pos,
                durationSeconds: dur,
                completed: completed ? true : nil,
                subtitleDelayMs: delayMs != 0 ? delayMs : nil,
                qos: qosPayload
            )
            lastReportedServerState = stateString
            if let vfs = hb.vfsTelemetry, lastVfsTelemetry != vfs {
                lastVfsTelemetry = vfs
            }
            if let prewarmInfo = hb.nextEpisodePrewarm {
                handleNextEpisodePrewarm(prewarmInfo, client: client)
            }
            if overrideState == nil,
               !host.sessionController.isResolving,
               !host.sessionController.isSwitchingSource,
               let cmd = hb.pendingCommand {
                await handleHeartbeatPendingCommand(cmd, client: client, currentPosition: pos)
            }
        } catch LunaCoreError.unauthorized {
            host.sessionController.onUnauthorized?()
        } catch let LunaCoreError.serverMessage(statusCode, _) where statusCode == 410 || statusCode == 404 {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        } catch {}
    }

    private func handleNextEpisodePrewarm(_ prewarmInfo: TvNextEpisodePrewarmInfo, client: LunaCoreClient) {
        guard let host else { return }
        if let fallbackNext = prewarmInfo.nextEpisode,
           let cur = host.sessionController.activeSession,
           cur.nextEpisode == nil {
            host.sessionController.activeSession = TvPlaybackSession(
                sessionId: cur.sessionId, streamToken: cur.streamToken, roomName: cur.roomName,
                hardwareProfile: cur.hardwareProfile, item: cur.item, selectedCandidate: cur.selectedCandidate,
                stream: cur.stream, tracks: cur.tracks, chapters: cur.chapters,
                subtitleDelayMs: cur.subtitleDelayMs, aetherConfig: cur.aetherConfig,
                heartbeatIntervalSeconds: cur.heartbeatIntervalSeconds, nextEpisode: fallbackNext
            )
        }
        if prewarmInfo.canClientPrewarmBytes == true,
           let relPath = prewarmInfo.streamUrl,
           let streamURL = client.buildAbsoluteURL(relPath),
           prewarmedNextEpisodeURL != streamURL {
            prewarmedNextEpisodeURL = streamURL
            prewarmedNextEpisodeItemId = prewarmInfo.itemId ?? prewarmInfo.nextEpisode?.itemId ?? host.sessionController.activeSession?.nextEpisode?.itemId
            prewarmedNextEpisodeSessionId = prewarmInfo.sessionId
            if let tok = prewarmInfo.streamToken, tok.count >= 8 {
                if prewarmedNextEpisodeStreamToken != tok {
                    if let oldTok = prewarmedNextEpisodeStreamToken, oldTok.count >= 8 {
                        EngineLog.unregisterSecret(oldTok)
                    }
                    _ = EngineLog.registerSecret(tok)
                    prewarmedNextEpisodeStreamToken = tok
                }
            }
            if DeviceHardwareCapabilities.availableMemoryBytes() > 512 * 1024 * 1024 {
                let headers = client.streamHTTPHeaders(for: streamURL)
                nextEpisodePrewarmTask?.cancel()
                nextEpisodePrewarmTask = Task.detached(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    if !AetherEngine.isPrewarmed(url: streamURL) {
                        _ = await AetherEngine.prewarm(url: streamURL, httpHeaders: headers, byteBudget: 8 * 1024 * 1024)
                    }
                }
            }
        }
    }

    func handleHeartbeatPendingCommand(_ cmd: TvPendingCommand, client: LunaCoreClient?, currentPosition: Double) async {
        guard let host, !host.sessionController.isDismissing, !host.sessionController.isTeardownCompleted else { return }
        switch cmd.type {
        case "reload_switched_stream":
            guard let switchedSession = cmd.playbackSession, let client else { return }
            showRemoteCommandToast("Byttet utgave fra iPhone")
            await host.sessionController.applyServerSwitchedSession(switchedSession, client: client, fallbackPosition: currentPosition)
        case "next_episode":
            guard let next = host.sessionController.activeSession?.nextEpisode else { return }
            showRemoteCommandToast("Neste episode fra iPhone")
            host.sessionController.playNextEpisode(next)
        case "subtitles_on":
            let liveTracks = host.sessionController.engine.subtitleTracks
            if !liveTracks.isEmpty { host.trackController.subtitleTracks = liveTracks }
            if let match = SmartTrackRuleEngine.selectBestSubtitleTrack(
                forLanguage: cmd.language,
                in: host.trackController.subtitleTracks
            ) {
                host.trackController.selectSubtitleManually(match.id)
                showRemoteCommandToast("Undertekst slått på fra iPhone")
            } else {
                showRemoteCommandToast("Ingen undertekster tilgjengelig")
            }
        default: break
        }
    }

    func consumePrewarmForNextEpisode(itemId: String) -> (matchedSessionId: String?, streamToken: String?) {
        let matched = prewarmedNextEpisodeItemId == itemId ? prewarmedNextEpisodeSessionId : nil
        let token = prewarmedNextEpisodeStreamToken
        nextEpisodePrewarmTask?.cancel(); nextEpisodePrewarmTask = nil
        prewarmedNextEpisodeURL = nil
        prewarmedNextEpisodeItemId = nil
        prewarmedNextEpisodeSessionId = nil
        prewarmedNextEpisodeStreamToken = nil
        return (matched, token)
    }

    func unregisterPrewarmSecretOnTeardown() {
        if let nextTok = prewarmedNextEpisodeStreamToken, nextTok.count >= 8 {
            EngineLog.unregisterSecret(nextTok)
            prewarmedNextEpisodeStreamToken = nil
        }
        prewarmedNextEpisodeURL = nil
        prewarmedNextEpisodeItemId = nil
        prewarmedNextEpisodeSessionId = nil
    }

    func showRemoteCommandToast(_ message: String) {
        remoteCommandToastTask?.cancel()
        remoteCommandToastMessage = message
        remoteCommandToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.remoteCommandToastMessage = nil
        }
    }

    func showTransientBanner(_ message: String) {
        transientBannerTask?.cancel()
        transientBannerMessage = message
        transientBannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.transientBannerMessage = nil
        }
    }

    func cancelHeartbeatOnly() {
        heartbeatTask?.cancel(); heartbeatTask = nil
        lastReportedServerState = nil
    }

    func cancelTasks() {
        heartbeatTask?.cancel(); heartbeatTask = nil
        transientBannerTask?.cancel(); transientBannerTask = nil
        remoteCommandToastTask?.cancel(); remoteCommandToastTask = nil
        remoteCommandToastMessage = nil
        nextEpisodePrewarmTask?.cancel(); nextEpisodePrewarmTask = nil
    }
}
