import Foundation
import UIKit
import AetherBridge

struct PendingStopSnapshot {
    let client: LunaCoreClient?
    let sessionId: String?
    let finalPos: Double
    let finalDur: Double
    let isCompleted: Bool
}

extension PlayerViewModel {
    // MARK: - Resolve & Engine Load Pipeline

    func runResolveAndLoad(
        request: PlaybackLaunchRequest,
        client: LunaCoreClient,
        isReplacement: Bool,
        autoplay: Bool = true
    ) async {
        resetScrubStateOnSessionChange()
        fatalError = nil
        transientBannerMessage = nil
        isResolving = true
        firstFrameFallbackUnlocked = false
        nextEpisodePrewarmReady = false
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        resolveStageKey = "searching_indexers"
        resolveStageLabel = "Søker etter beste kilde…"
        resolvePercent = 16
        resolveHeadline = nil
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            let (status, startRes) = try await client.resolvePlayback(
                itemId: request.itemId,
                title: request.apiTitle,
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
                throw LunaCoreError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
            }

            resolveStageKey = "awaiting_first_frame"
            resolveStageLabel = "Tilpasser skjerm og starter avspilling…"
            resolvePercent = 95
            if !isReplacement {
                engine.ownsSoftwareNowPlaying = true
                engine.ownsVideoNowPlayingSession = true
                engine.ownsVideoNowPlayingCommands = true
            }
            try await mountSessionInEngine(
                resolvedSession,
                client: client,
                overrideStartPosition: request.startPositionSeconds ?? resolvedSession.stream.startPositionSeconds,
                autoplay: autoplay
            )
            isResolving = false
            armFirstFrameFallbackWatchdog()
            startHeartbeatLoop()
        } catch LunaCoreError.unauthorized {
            guard !Task.isCancelled else { return }
            isResolving = false
            UIApplication.shared.isIdleTimerDisabled = false
            onUnauthorized?()
        } catch {
            guard !Task.isCancelled else { return }
            isResolving = false
            UIApplication.shared.isIdleTimerDisabled = false
            fatalError = LunaCopy.friendlyErrorMessage(error)
        }
    }

    func switchSource(to candidateId: String) async {
        guard let client = activeClient, let session = activeSession else {
            isSwitchingSource = false
            return
        }
        resetScrubStateOnSessionChange()
        let currentPos = max(0, transport.currentTime)
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
            if !userManuallySelectedSubtitle {
                didApplyInitialSmartRule = false
            }
            try await mountSessionInEngine(
                updatedSession,
                client: client,
                overrideStartPosition: updatedSession.stream.startPositionSeconds ?? currentPos
            )
            isSwitchingSource = false
        } catch LunaCoreError.unauthorized {
            isSwitchingSource = false
            onUnauthorized?()
        } catch {
            isSwitchingSource = false
            guard !Task.isCancelled else { return }
            showTransientBanner("Kildebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }

    func applyServerSwitchedSession(
        _ switchedSession: TvPlaybackSession,
        client: LunaCoreClient,
        fallbackPosition: Double
    ) async {
        guard !isSwitchingSource, !isResolving else { return }
        resetScrubStateOnSessionChange()
        isSwitchingSource = true
        resolveStageKey = "switching"
        resolveStageLabel = "Bytter kilde valgt fra iPhone…"
        resolvePercent = 75
        do {
            engine.prepareForItemReplacement()
            if !userManuallySelectedSubtitle {
                didApplyInitialSmartRule = false
            }
            try await mountSessionInEngine(
                switchedSession,
                client: client,
                overrideStartPosition: switchedSession.stream.startPositionSeconds ?? fallbackPosition
            )
            isSwitchingSource = false
        } catch {
            isSwitchingSource = false
            showTransientBanner("Kildebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }

    func mountSessionInEngine(
        _ session: TvPlaybackSession,
        client: LunaCoreClient,
        overrideStartPosition: Double?,
        autoplay: Bool = true
    ) async throws {
        guard let streamURL = client.buildAbsoluteURL(session.stream.url) else {
            throw LunaCoreError.invalidURL(session.stream.url)
        }

        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        needsNativeAudioActivationAfterPausedRestore = false
        try Task.checkCancellation()

        let previousToken = registeredStreamToken
        if session.streamToken.count >= 8 {
            _ = EngineLog.registerSecret(session.streamToken)
        }

        // AE#1015 / AE#1031: Disable forward subtitle prefetch while preserving 10 s delay history.
        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10

        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        upscaleReloadTask?.cancel()
        upscaleReloadTask = nil
        let initialAudioDelayMs = comfort.audioDelayMs
        audioDelayMs = initialAudioDelayMs

        let options = Self.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: Double(initialAudioDelayMs) / 1000.0,
            autoplay: autoplay
        )
        let startPos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
        do {
            _ = try await engine.load(
                url: streamURL,
                startPosition: startPos > 0.5 ? startPos : nil,
                options: options
            )
            try Task.checkCancellation()
            guard !isTeardownCompleted, !isDismissing else {
                throw CancellationError()
            }
            if autoplay {
                await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
                try Task.checkCancellation()
            } else {
                needsNativeAudioActivationAfterPausedRestore = PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(
                    for: transport.videoRoute
                )
            }
        } catch {
            if session.streamToken.count >= 8, session.streamToken != previousToken {
                EngineLog.unregisterSecret(session.streamToken)
            }
            throw error
        }

        self.activeSession = session
        self.lastReportedServerState = autoplay ? "playing" : "paused"
        self.registeredStreamToken = session.streamToken.count >= 8 ? session.streamToken : previousToken
        self.resolveHeadline = session.selectedCandidate.displayHeadline
        self.engineChapters = []
        if let prev = previousToken, prev.count >= 8, prev != session.streamToken {
            EngineLog.unregisterSecret(prev)
        }

        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
        if comfort.audioDelayMs != initialAudioDelayMs {
            audioDelayMs = comfort.audioDelayMs
            engine.setAudioDelay(comfort.audioDelaySeconds)
        } else {
            audioDelayMs = initialAudioDelayMs
        }
        rebuildMergedChapters()
        PlayerNowPlayingCoordinator.publish(session: session, client: client, viewModel: self)

        if comfort.smartNordicSubtitleRule && !didApplyInitialSmartRule {
            didApplyInitialSmartRule = true
            applySmartSubtitleRule()
        }
    }

    func armFirstFrameFallbackWatchdog() {
        firstFrameFallbackTask?.cancel()
        firstFrameFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if !self.isPictureReadyForReveal {
                self.firstFrameFallbackUnlocked = true
            }
        }
    }

    func applyResolveProgressEvent(_ event: TvResolveSocketEvent) {
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

    func awaitWebSocketResolution(
        wsPath: String,
        resolveId: String,
        client: LunaCoreClient
    ) async throws -> TvPlaybackSession {
        let socket = PlaybackResolveSocket(
            baseURL: client.baseURL,
            wsPath: wsPath,
            headers: client.streamHTTPHeaders(),
            allowSelfSignedLanTLS: client.allowSelfSignedLanTLS
        )

        let latch = ResolveFirstEventLatch()
        let streamTask = Task { @MainActor [weak self] () throws -> TvPlaybackSession? in
            for try await event in socket.events() {
                await latch.markReceived()
                self?.applyResolveProgressEvent(event)
                if event.type == "resolve.ready", let readySession = event.playbackSession {
                    return readySession
                }
                if event.type == "resolve.failed" {
                    throw LunaCoreError.serverMessage(502, event.error ?? "Kunne ikke klargjøre strøm.")
                }
            }
            return nil
        }

        let watchdogTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if await !latch.received {
                streamTask.cancel()
            }
        }

        defer {
            watchdogTask.cancel()
            streamTask.cancel()
        }

        do {
            let ready = try await withTaskCancellationHandler {
                try await streamTask.value
            } onCancel: {
                watchdogTask.cancel()
                streamTask.cancel()
            }
            if let readySession = ready {
                return readySession
            }
        } catch let err as LunaCoreError {
            if case .serverMessage(502, _) = err {
                throw err
            }
            if case .decodingFailed = err {
                throw err
            }
        } catch {
            // Fall through to HTTP snapshot polling if WebSocket stalls or drops
        }

        try Task.checkCancellation()
        return try await pollHttpResolutionFallback(resolveId: resolveId, client: client)
    }

    func pollHttpResolutionFallback(
        resolveId: String,
        client: LunaCoreClient
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
                throw LunaCoreError.serverMessage(502, snap.error ?? "Kunne ikke klargjøre strøm.")
            }
        }
        throw LunaCoreError.serverMessage(504, "Tidsavbrudd under klargjøring av strøm.")
    }

    // MARK: - 15s Pause-Safe VFS Heartbeat

    func startHeartbeatLoop() {
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

    func sendHeartbeatOnce(overrideState: String?, completed: Bool = false) async {
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

        let pos = max(0, transport.currentTime)
        let dur = max(0, effectiveDurationSeconds)

        do {
            let hb = try await client.sendHeartbeat(
                sessionId: session.sessionId,
                state: stateString,
                positionSeconds: pos,
                durationSeconds: dur,
                completed: completed ? true : nil
            )
            lastReportedServerState = stateString
            if let ready = hb.nextEpisodePrewarmReady {
                nextEpisodePrewarmReady = ready
            } else if hb.nextEpisodePrewarmStarted == true {
                nextEpisodePrewarmReady = true
            }
            if let vfs = hb.vfsTelemetry {
                lastVfsTelemetry = vfs
            }
            if overrideState == nil,
               !isResolving,
               !isSwitchingSource,
               let cmd = hb.pendingCommand {
                await handleHeartbeatPendingCommand(cmd, client: client, currentPosition: pos)
            }
        } catch LunaCoreError.unauthorized {
            onUnauthorized?()
        } catch {
            // Heartbeats are periodic best-effort telemetry
        }
    }

    func handleHeartbeatPendingCommand(
        _ cmd: TvPendingCommand,
        client: LunaCoreClient?,
        currentPosition: Double
    ) async {
        guard !isDismissing, !isTeardownCompleted else { return }
        switch cmd.type {
        case "reload_switched_stream":
            guard let switchedSession = cmd.playbackSession, let client else { return }
            showRemoteCommandToast("Byttet kilde fra iPhone")
            await applyServerSwitchedSession(switchedSession, client: client, fallbackPosition: currentPosition)

        case "next_episode":
            guard let next = activeSession?.nextEpisode else { return }
            showRemoteCommandToast("Neste episode fra iPhone")
            playNextEpisode(next)

        case "subtitles_on":
            let liveTracks = engine.subtitleTracks
            if !liveTracks.isEmpty {
                subtitleTracks = liveTracks
            }
            if let match = SmartTrackRuleEngine.selectBestSubtitleTrack(
                forLanguage: cmd.language,
                in: subtitleTracks
            ) {
                selectSubtitleManually(match.id)
                showRemoteCommandToast("Undertekst slått på fra iPhone")
            } else {
                showRemoteCommandToast("Ingen undertekster tilgjengelig")
            }

        default:
            break
        }
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

    // MARK: - Two-Phase Dismissal & Teardown Helpers

    nonisolated static func shouldPauseEngineOnDismiss(
        engineState: PlaybackState,
        playbackPhase: PlaybackPhase
    ) -> Bool {
        switch engineState {
        case .playing, .loading, .seeking:
            return true
        case .paused, .idle, .ended, .error:
            break
        }
        switch playbackPhase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            return true
        case .paused, .idle, .ended, .error:
            return false
        }
    }

    func cancelAllSessionTasks() {
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        needsNativeAudioActivationAfterPausedRestore = false
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
        chapterSeekTask?.cancel()
        chapterSeekTask = nil
        smartRuleTask?.cancel()
        smartRuleTask = nil
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil
        upscaleReloadTask?.cancel()
        upscaleReloadTask = nil
        transientBannerTask?.cancel()
        transientBannerTask = nil
        remoteCommandToastTask?.cancel()
        remoteCommandToastTask = nil
        remoteCommandToastMessage = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
    }

    func captureStopSnapshot() -> PendingStopSnapshot {
        let finalPos = max(0, transport.currentTime)
        let finalDur = max(0, effectiveDurationSeconds)
        let inCredits = chapters.contains { $0.kind == .credits && finalPos >= $0.startSeconds }
        let isCompleted = playbackPhase == .ended || (inCredits && finalDur > 0 && finalPos / finalDur >= 0.75)
        return PendingStopSnapshot(
            client: activeClient,
            sessionId: activeSession?.sessionId,
            finalPos: finalPos,
            finalDur: finalDur,
            isCompleted: isCompleted
        )
    }

    /// Silence audio and freeze the last video frame while `fullScreenCover` dismisses,
    /// deferring `engine.stop(...)` and `notifyContentMutated()` until `.onDisappear`.
    func prepareForDismissal() {
        guard !isTeardownCompleted, !isDismissing else { return }
        isDismissing = true
        cancelAllSessionTasks()
        resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false
        pendingStopSnapshot = captureStopSnapshot()
        // Disconnect Combine sinks first so pausing does not publish `.paused` and flash the bottom bar.
        cancellables.removeAll()

        if PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(engineOwnerToken) {
            if Self.shouldPauseEngineOnDismiss(engineState: transport.state, playbackPhase: playbackPhase) {
                transport.pause()
            }
        }
    }
}

private actor ResolveFirstEventLatch {
    private(set) var received = false

    func markReceived() {
        received = true
    }
}
