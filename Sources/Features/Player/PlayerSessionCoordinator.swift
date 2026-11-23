import Foundation
import UIKit
import AetherBridge

struct PendingStopSnapshot {
    let client: LunaCoreClient?
    let sessionId: String?
    let resolveId: String?
    let cancelItemId: String?
    let cancelPrepareToken: String?
    let inflightPrepareTask: Task<TvPrepareResponse?, Never>?
    let finalPos: Double
    let finalDur: Double
    let isCompleted: Bool
}

extension PlayerViewModel {
    // MARK: - Resolve & Engine Load Pipeline

    private func extractResolvedSession(
        status: Int,
        startRes: TvResolveStartResponse,
        client: LunaCoreClient
    ) async throws -> TvPlaybackSession {
        if status == 200, let immediate = startRes.playbackSession {
            activeResolveId = nil
            return immediate
        }
        if let wsPath = startRes.wsPath {
            activeResolveId = startRes.resolveId
            let resolved = try await awaitWebSocketResolution(
                wsPath: wsPath,
                resolveId: startRes.resolveId,
                client: client
            )
            activeResolveId = nil
            return resolved
        }
        activeResolveId = nil
        throw LunaCoreError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
    }

    private func finishColdMount(
        _ resolvedSession: TvPlaybackSession,
        request: PlaybackLaunchRequest,
        client: LunaCoreClient,
        autoplay: Bool
    ) async throws {
        pendingHandedOverSessionId = resolvedSession.sessionId
        pendingInflightPrepareTask = nil
        pendingInflightPrepareToken = nil
        try Task.checkCancellation()
        guard !isTeardownCompleted, !isDismissing else {
            throw CancellationError()
        }
        ArtworkPipeline.shared.enterPlaybackMemoryMode(
            isHeavySoftwareStream: Self.isLikelyHeavySoftwareSession(
                resolvedSession,
                dualLayerOverride: comfort.dualLayerOverride,
                lowResUpscaleMode: comfort.lowResUpscaleMode
            ),
            preservedURLs: curtainPreservedURLs(request: request, session: resolvedSession, client: client)
        )
        resolveStageLabel = "Tilpasser skjerm og starter avspilling…"
        resolvePercent = 95
        try await mountSessionInEngine(
            resolvedSession,
            client: client,
            overrideStartPosition: request.startPositionSeconds ?? resolvedSession.stream.startPositionSeconds,
            autoplay: autoplay
        )
        isResolving = false
        armFirstFrameFallbackWatchdog()
        startHeartbeatLoop()
    }

    func runResolveAndLoad(
        request: PlaybackLaunchRequest,
        client: LunaCoreClient,
        autoplay: Bool = true
    ) async {
        resetScrubStateOnSessionChange()
        fatalError = nil
        transientBannerMessage = nil
        isResolving = true
        firstFrameFallbackUnlocked = false
        userManuallySelectedSubtitle = false
        didApplyInitialSmartRule = false
        if let prepSession = request.preparedSession {
            resolveStageLabel = "Starter klargjort strøm…"
            resolvePercent = 82
            resolveHeadline = prepSession.selectedCandidate.displayHeadline
        } else {
            resolveStageLabel = "Søker etter beste kilde…"
            resolvePercent = 16
            resolveHeadline = nil
        }
        ArtworkPipeline.shared.enterPlaybackMemoryMode(
            isHeavySoftwareStream: Self.isLikelyHeavySoftwareSession(
                request.preparedSession,
                dualLayerOverride: comfort.dualLayerOverride,
                lowResUpscaleMode: comfort.lowResUpscaleMode
            ),
            preservedURLs: curtainPreservedURLs(request: request, session: request.preparedSession, client: client)
        )
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            var effectivePreparedSession = request.preparedSession
            var effectivePrepareToken = request.prepareToken

            if effectivePreparedSession == nil,
               request.candidateId == nil,
               let inflightPrep = pendingInflightPrepareTask {
                resolveStageLabel = "Fullfører klargjort strøm…"
                resolvePercent = 68
                let prepResult = await withTaskCancellationHandler {
                    await inflightPrep.value
                } onCancel: {
                    inflightPrep.cancel()
                }
                pendingInflightPrepareTask = nil
                pendingInflightPrepareToken = nil
                try Task.checkCancellation()
                guard !isTeardownCompleted, !isDismissing else {
                    throw CancellationError()
                }
                if let prepResult, let readySession = prepResult.playbackSession {
                    effectivePreparedSession = readySession
                    effectivePrepareToken = prepResult.prepareToken ?? readySession.sessionId
                    pendingHandedOverSessionId = readySession.sessionId
                }
            }

            if let prepSession = effectivePreparedSession,
               Self.canDirectMountPreparedSession(request, candidateSession: prepSession) {
                pendingHandedOverSessionId = prepSession.sessionId
                ArtworkPipeline.shared.enterPlaybackMemoryMode(
                    isHeavySoftwareStream: Self.isLikelyHeavySoftwareSession(
                        prepSession,
                        dualLayerOverride: comfort.dualLayerOverride,
                        lowResUpscaleMode: comfort.lowResUpscaleMode
                    ),
                    preservedURLs: curtainPreservedURLs(request: request, session: prepSession, client: client)
                )
                resolveHeadline = prepSession.selectedCandidate.displayHeadline
                resolveStageLabel = "Tilpasser skjerm og starter avspilling…"
                resolvePercent = 95

                let reqItemId = request.itemId
                let reqApiTitle = request.apiTitle
                let reqSeriesTitle = request.seriesTitle
                let reqStartPos = request.startPositionSeconds
                let tokenToPromote = effectivePrepareToken ?? prepSession.sessionId
                let promoteTask = Task {
                    try await client.resolvePlayback(
                        itemId: reqItemId,
                        title: reqApiTitle,
                        seriesTitle: reqSeriesTitle,
                        startPositionSeconds: reqStartPos,
                        candidateId: nil,
                        prepareToken: tokenToPromote
                    )
                }
                defer { promoteTask.cancel() }

                do {
                    try await mountSessionInEngine(
                        prepSession,
                        client: client,
                        overrideStartPosition: reqStartPos ?? prepSession.stream.startPositionSeconds,
                        autoplay: autoplay
                    )
                    isResolving = false
                    armFirstFrameFallbackWatchdog()
                    startHeartbeatLoop()

                    if let (status, startRes) = try? await withTaskCancellationHandler(
                        operation: { try await promoteTask.value },
                        onCancel: { promoteTask.cancel() }
                    ), !Task.isCancelled, !isTeardownCompleted, !isDismissing {
                        let promoted = try? await extractResolvedSession(status: status, startRes: startRes, client: client)
                        if let promoted, !Task.isCancelled, !isTeardownCompleted, !isDismissing {
                            if promoted.sessionId == prepSession.sessionId {
                                self.activeSession = promoted
                                rebuildMergedChapters()
                            } else {
                                let promotedIntent = captureCurrentTrackIntent()
                                transport.prepareForItemReplacement()
                                let livePos = max(0, transport.currentTime)
                                try await mountSessionInEngine(
                                    promoted,
                                    client: client,
                                    overrideStartPosition: livePos > 0.5 ? livePos : (reqStartPos ?? promoted.stream.startPositionSeconds),
                                    autoplay: autoplay,
                                    trackIntent: promotedIntent
                                )
                            }
                        }
                    }
                    return
                } catch where LunaCoreError.isCancellation(error) {
                    promoteTask.cancel()
                    return
                } catch {
                    try Task.checkCancellation()
                    guard !isTeardownCompleted, !isDismissing else { return }
                    let (status, startRes) = try await withTaskCancellationHandler(
                        operation: { try await promoteTask.value },
                        onCancel: { promoteTask.cancel() }
                    )
                    let fallbackSession = try await extractResolvedSession(status: status, startRes: startRes, client: client)
                    try await finishColdMount(fallbackSession, request: request, client: client, autoplay: autoplay)
                    return
                }
            }

            let (status, startRes) = try await client.resolvePlayback(
                itemId: request.itemId,
                title: request.apiTitle,
                seriesTitle: request.seriesTitle,
                startPositionSeconds: request.startPositionSeconds,
                candidateId: request.candidateId,
                prepareToken: effectivePrepareToken
            )
            let resolvedSession = try await extractResolvedSession(status: status, startRes: startRes, client: client)
            try await finishColdMount(resolvedSession, request: request, client: client, autoplay: autoplay)
        } catch where LunaCoreError.isCancellation(error) {
            return
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

    func mountSessionInEngine(
        _ session: TvPlaybackSession,
        client: LunaCoreClient,
        overrideStartPosition: Double?,
        autoplay: Bool = true,
        trackIntent: PlaybackTrackIntent? = nil
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
        hasPendingAudioDelayCommit = false
        upscaleReloadTask?.cancel()
        upscaleReloadTask = nil
        isWirelessAudioRouteActive = PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
        let initialAudioDelayMs = comfort.audioDelayMs
        let initialWirelessRoute = isWirelessAudioRouteActive
        audioDelayMs = initialAudioDelayMs
        audioEnhancement = comfort.audioEnhancement

        let options = Self.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: effectiveAudioDelaySecondsForActiveRoute(),
            autoplay: autoplay,
            suppressInitialSubtitleSelection: trackIntent != nil
        )
        let startPos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
        do {
            try await transport.loadStream(
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
        self.pendingHandedOverSessionId = nil
        self.pendingInflightPrepareTask = nil
        self.lastReportedServerState = autoplay ? "playing" : "paused"
        self.registeredStreamToken = session.streamToken.count >= 8 ? session.streamToken : previousToken
        self.resolveHeadline = session.selectedCandidate.displayHeadline
        self.engineChapters = []
        if let prev = previousToken, prev.count >= 8, prev != session.streamToken {
            EngineLog.unregisterSecret(prev)
        }

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
        PlayerNowPlayingCoordinator.publish(session: session, client: client, viewModel: self)

        if let trackIntent {
            didApplyInitialSmartRule = true
            applyResolvedTrackIntent(trackIntent)
        } else {
            subtitleDelayMs = 0
            transport.setSoftwareSubtitleDelay(0)
            if comfort.smartNordicSubtitleRule && !didApplyInitialSmartRule {
                didApplyInitialSmartRule = true
                applySmartSubtitleRule()
            }
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
        let maxAttempts = 248
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

    // MARK: - Two-Phase Dismissal & Teardown Helpers

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
        hasPendingAudioDelayCommit = false
        upscaleReloadTask?.cancel()
        upscaleReloadTask = nil
        transientBannerTask?.cancel()
        transientBannerTask = nil
        remoteCommandToastTask?.cancel()
        remoteCommandToastTask = nil
        remoteCommandToastMessage = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        nextEpisodePrewarmTask?.cancel()
        nextEpisodePrewarmTask = nil
    }

    func captureStopSnapshot() -> PendingStopSnapshot {
        let hasActiveSession = activeSession != nil
        let finalPos = hasActiveSession ? max(0, transport.currentTime) : 0
        let finalDur = hasActiveSession ? max(0, effectiveDurationSeconds) : 0
        let inCredits = hasActiveSession && chapters.contains { $0.kind == .credits && finalPos >= $0.startSeconds }
        let isCompleted = hasActiveSession && (
            playbackPhase == .ended || (inCredits && finalDur > 0 && finalPos / finalDur >= 0.75)
        )
        return PendingStopSnapshot(
            client: activeClient,
            sessionId: activeSession?.sessionId ?? pendingHandedOverSessionId,
            resolveId: hasActiveSession ? nil : activeResolveId,
            cancelItemId: hasActiveSession ? nil : currentRequest?.itemId,
            cancelPrepareToken: hasActiveSession ? nil : pendingInflightPrepareToken,
            inflightPrepareTask: hasActiveSession ? nil : pendingInflightPrepareTask,
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
        activeResolveId = nil
        pendingInflightPrepareTask?.cancel()
        pendingInflightPrepareTask = nil
        pendingInflightPrepareToken = nil
        pendingHandedOverSessionId = nil
        // Disconnect Combine sinks first so pausing does not publish `.paused` and flash the bottom bar.
        cancellables.removeAll()
        didBindEnginePublishers = false

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
