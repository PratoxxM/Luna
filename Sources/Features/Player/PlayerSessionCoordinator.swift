import Foundation
import SwiftUI
import UIKit
import AetherBridge

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
                throw LunaCoreError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
            }

            resolveStageKey = "awaiting_first_frame"
            resolveStageLabel = "Tilpasser HDMI & starter avspilling…"
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
            fatalError = error.localizedDescription
        }
    }

    func switchSource(to candidateId: String) async {
        guard let client = activeClient, let session = activeSession else {
            isSwitchingSource = false
            return
        }
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
            showTransientBanner("Kildebytte feilet: \(error.localizedDescription)")
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
        resolveStageLabel = "Bytter kilde valgt fra LunaCore Web…"
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
            showTransientBanner("Kildebytte fra Web feilet: \(error.localizedDescription)")
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
            guard !isTeardownCompleted else {
                throw CancellationError()
            }
            if autoplay {
                await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(
                    videoRoute: engine.videoRoute
                )
                try Task.checkCancellation()
            } else {
                needsNativeAudioActivationAfterPausedRestore = PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(
                    for: engine.videoRoute
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

        let pos = max(0, engine.currentTime)
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
               let cmd = hb.pendingCommand,
               cmd.type == "reload_switched_stream",
               let switchedSession = cmd.playbackSession {
                await applyServerSwitchedSession(switchedSession, client: client, fallbackPosition: pos)
            }
        } catch LunaCoreError.unauthorized {
            onUnauthorized?()
        } catch {
            // Heartbeats are periodic best-effort telemetry
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

    // MARK: - Foreground Return Recovery

    nonisolated static func isActiveTransportIntent(
        playbackPhase: PlaybackPhase,
        engineState: PlaybackState
    ) -> Bool {
        switch playbackPhase {
        case .playing, .seeking, .rebuffering, .stalled:
            return true
        case .loading:
            return engineState == .playing || engineState == .seeking
        case .paused, .idle, .ended, .error:
            return false
        }
    }

    nonisolated static func resolvedPostRestorePlayingIntent(
        defaultShouldPlay: Bool,
        userOverride: Bool?
    ) -> Bool {
        userOverride ?? defaultShouldPlay
    }

    nonisolated static func shouldActivateNativeAudioDuringRestore(
        shouldPlay: Bool,
        videoRoute: VideoRoute
    ) -> Bool {
        shouldPlay && PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: videoRoute)
    }

    nonisolated static func shouldAttemptForegroundVideoRestore(
        needsForegroundVideoRestore: Bool,
        hasActiveSession: Bool,
        isResolving: Bool,
        isSwitchingSource: Bool,
        isRestoringFromBackground: Bool,
        hasFatalError: Bool,
        didTeardown: Bool
    ) -> Bool {
        guard needsForegroundVideoRestore,
              hasActiveSession,
              !isResolving,
              !isSwitchingSource,
              !isRestoringFromBackground,
              !hasFatalError,
              !didTeardown else {
            return false
        }
        return true
    }

    func updateInitialScenePhase(_ phase: ScenePhase) {
        isForegroundActive = (phase == .active)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            isForegroundActive = true
            Task { @MainActor [weak self] in
                await self?.attemptForegroundRecoveryIfNeeded()
            }
        } else if phase == .inactive || phase == .background {
            if isForegroundActive,
               !isRestoringFromBackground,
               !isResolving,
               !isSwitchingSource,
               !engine.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                    playbackPhase: playbackPhase,
                    engineState: engine.state
                )
            }
            isForegroundActive = false
        }
    }

    func attemptForegroundRecoveryIfNeeded() async {
        guard isForegroundActive else { return }
        guard Self.shouldAttemptForegroundVideoRestore(
            needsForegroundVideoRestore: engine.needsForegroundVideoRestore,
            hasActiveSession: activeSession != nil,
            isResolving: isResolving,
            isSwitchingSource: isSwitchingSource,
            isRestoringFromBackground: isRestoringFromBackground,
            hasFatalError: fatalError != nil,
            didTeardown: isTeardownCompleted
        ) else {
            return
        }

        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        let wasPlayingBeforeBackground = lastForegroundPlaybackWasPlaying
        let savedResumePosition = max(0, engine.currentTime)
        userDesiredPlayingDuringRestore = nil
        isRestoringFromBackground = true
        hasFirstFrameReadyForDisplay = false
        firstFrameFallbackUnlocked = false
        resolveStageKey = "reconnecting"
        resolveStageLabel = "Gjenoppretter avspilling…"
        resolvePercent = 90
        updateIdleTimer(for: playbackPhase)

        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performForegroundRestore(
                defaultShouldPlay: wasPlayingBeforeBackground,
                fallbackPositionSeconds: savedResumePosition
            )
        }
    }

    private func performForegroundRestore(
        defaultShouldPlay: Bool,
        fallbackPositionSeconds: Double
    ) async {
        defer {
            if isRestoringFromBackground {
                isRestoringFromBackground = false
            }
            userDesiredPlayingDuringRestore = nil
            updateIdleTimer(for: playbackPhase)
        }

        do {
            try await engine.reloadAtCurrentPosition { options in
                options.autoplay = defaultShouldPlay
            }
            guard !Task.isCancelled, !isTeardownCompleted else { return }

            needsNativeAudioActivationAfterPausedRestore = false
            let initialShouldPlay = Self.resolvedPostRestorePlayingIntent(
                defaultShouldPlay: defaultShouldPlay,
                userOverride: userDesiredPlayingDuringRestore
            )
            if Self.shouldActivateNativeAudioDuringRestore(
                shouldPlay: initialShouldPlay,
                videoRoute: engine.videoRoute
            ) {
                await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(
                    videoRoute: engine.videoRoute
                )
                guard !Task.isCancelled, !isTeardownCompleted else { return }
            }

            let finalShouldPlay = Self.resolvedPostRestorePlayingIntent(
                defaultShouldPlay: defaultShouldPlay,
                userOverride: userDesiredPlayingDuringRestore
            )
            if finalShouldPlay {
                if Self.shouldActivateNativeAudioDuringRestore(
                    shouldPlay: true,
                    videoRoute: engine.videoRoute
                ) && !initialShouldPlay {
                    await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(
                        videoRoute: engine.videoRoute
                    )
                    guard !Task.isCancelled, !isTeardownCompleted else { return }
                }
                if engine.state != .playing {
                    engine.play()
                }
            } else {
                if engine.state != .paused {
                    engine.pause()
                }
                needsNativeAudioActivationAfterPausedRestore = PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(
                    for: engine.videoRoute
                )
            }

            lastForegroundPlaybackWasPlaying = finalShouldPlay
            isRestoringFromBackground = false
            userDesiredPlayingDuringRestore = nil
            armFirstFrameFallbackWatchdog()
            updateIdleTimer(for: playbackPhase)
            if activeSession != nil {
                await sendHeartbeatOnce(overrideState: finalShouldPlay ? "playing" : "paused")
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !isTeardownCompleted else { return }
            let capturedShouldPlay = Self.resolvedPostRestorePlayingIntent(
                defaultShouldPlay: defaultShouldPlay,
                userOverride: userDesiredPlayingDuringRestore
            )
            if let client = activeClient, let baseReq = currentRequest {
                isRestoringFromBackground = false
                userDesiredPlayingDuringRestore = nil
                let fallbackTime = max(fallbackPositionSeconds, max(0, engine.currentTime))
                let resumeAt = fallbackTime > 0.5 ? fallbackTime : baseReq.startPositionSeconds
                let retryReq = PlaybackLaunchRequest(
                    itemId: baseReq.itemId,
                    title: baseReq.title,
                    seriesTitle: baseReq.seriesTitle,
                    startPositionSeconds: resumeAt,
                    candidateId: activeSession?.selectedCandidate.id ?? baseReq.candidateId,
                    prepareToken: nil,
                    backdropUrl: baseReq.backdropUrl,
                    logoUrl: baseReq.logoUrl
                )
                currentRequest = retryReq
                await runResolveAndLoad(
                    request: retryReq,
                    client: client,
                    isReplacement: false,
                    autoplay: capturedShouldPlay
                )
                guard !Task.isCancelled, !isTeardownCompleted, fatalError == nil else { return }
                if !capturedShouldPlay && engine.state != .paused {
                    engine.pause()
                }
                lastForegroundPlaybackWasPlaying = capturedShouldPlay
            } else {
                isRestoringFromBackground = false
                userDesiredPlayingDuringRestore = nil
                fatalError = error.localizedDescription
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
