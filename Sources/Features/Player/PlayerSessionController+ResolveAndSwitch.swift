import Foundation
import UIKit
import AetherBridge

extension PlayerSessionController {
    func runResolveAndLoad(request: PlaybackLaunchRequest, client: LunaCoreClient, autoplay: Bool = true) async {
        guard let host else { return }
        host.scrubController.resetScrubStateOnSessionChange()
        fatalError = nil
        host.qosReporter.transientBannerMessage = nil
        isResolving = true
        firstFrameFallbackUnlocked = false
        host.trackController.resetFlagsForResolve()
        if let prepSession = request.preparedSession {
            startupState.resolveStageLabel = "Starter klargjort strøm…"
            startupState.resolvePercent = 82
            startupState.resolveHeadline = prepSession.selectedCandidate.displayHeadline
        } else {
            startupState.resolveStageLabel = "Søker etter beste kilde…"
            startupState.resolvePercent = 16
            startupState.resolveHeadline = nil
        }
        ArtworkPipeline.shared.enterPlaybackMemoryMode(
            isHeavySoftwareStream: PlayerEngineConfigurator.isLikelyHeavySoftwareSession(
                request.preparedSession,
                dualLayerOverride: comfort.dualLayerOverride,
                lowResUpscaleMode: comfort.lowResUpscaleMode
            ),
            preservedURLs: PlayerEngineConfigurator.curtainPreservedURLs(
                request: request,
                session: request.preparedSession,
                client: client
            )
        )
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            var effectivePreparedSession = request.preparedSession
            var effectivePrepareToken = request.prepareToken

            if effectivePreparedSession == nil, request.candidateId == nil, let inflightPrep = pendingInflightPrepareTask {
                startupState.resolveStageLabel = "Fullfører klargjort strøm…"
                startupState.resolvePercent = 68
                let prepResult = await withTaskCancellationHandler {
                    await inflightPrep.value
                } onCancel: { inflightPrep.cancel() }
                pendingInflightPrepareTask = nil
                pendingInflightPrepareToken = nil
                try Task.checkCancellation()
                guard !isTeardownCompleted, !isDismissing else { throw CancellationError() }
                if let prepResult, let readySession = prepResult.playbackSession {
                    effectivePreparedSession = readySession
                    effectivePrepareToken = prepResult.prepareToken ?? readySession.sessionId
                    pendingHandedOverSessionId = readySession.sessionId
                }
            }

            if let prepSession = effectivePreparedSession,
               PlayerEngineConfigurator.canDirectMountPreparedSession(request, candidateSession: prepSession) {
                try await performWarmDirectMount(
                    prepSession,
                    prepareToken: effectivePrepareToken,
                    request: request,
                    client: client,
                    autoplay: autoplay
                )
                return
            }

            let (status, startRes) = try await client.resolvePlayback(
                itemId: request.itemId,
                title: request.apiTitle,
                seriesTitle: request.seriesTitle,
                startPositionSeconds: request.startPositionSeconds,
                candidateId: request.candidateId,
                prepareToken: effectivePrepareToken
            )
            let resolved = try await PlayerResolvePipeline.extractResolvedSession(
                status: status,
                startRes: startRes,
                client: client,
                onResolveIdChanged: { [weak self] in self?.activeResolveId = $0 },
                onProgress: { [weak self] in self?.applyResolveProgressEvent($0) }
            )
            try await finishColdMount(resolved, request: request, client: client, autoplay: autoplay)
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

    private func performWarmDirectMount(
        _ prepSession: TvPlaybackSession,
        prepareToken: String?,
        request: PlaybackLaunchRequest,
        client: LunaCoreClient,
        autoplay: Bool
    ) async throws {
        guard let host else { return }
        pendingHandedOverSessionId = prepSession.sessionId
        ArtworkPipeline.shared.enterPlaybackMemoryMode(
            isHeavySoftwareStream: PlayerEngineConfigurator.isLikelyHeavySoftwareSession(
                prepSession,
                dualLayerOverride: comfort.dualLayerOverride,
                lowResUpscaleMode: comfort.lowResUpscaleMode
            ),
            preservedURLs: PlayerEngineConfigurator.curtainPreservedURLs(
                request: request,
                session: prepSession,
                client: client
            )
        )
        startupState.resolveHeadline = prepSession.selectedCandidate.displayHeadline
        startupState.resolveStageLabel = "Tilpasser skjerm og starter avspilling…"
        startupState.resolvePercent = 95

        let promoteTask = Task {
            try await client.resolvePlayback(
                itemId: request.itemId,
                title: request.apiTitle,
                seriesTitle: request.seriesTitle,
                startPositionSeconds: request.startPositionSeconds,
                candidateId: nil,
                prepareToken: prepareToken ?? prepSession.sessionId
            )
        }
        defer { promoteTask.cancel() }

        do {
            isSpeculativeWarmMountInFlight = true
            try await mountSessionInEngine(
                prepSession,
                client: client,
                overrideStartPosition: request.startPositionSeconds ?? prepSession.stream.startPositionSeconds,
                autoplay: autoplay
            )
            isSpeculativeWarmMountInFlight = false
            fatalError = nil
            isResolving = false
            armFirstFrameFallbackWatchdog()
            host.qosReporter.startHeartbeatLoop()

            if let (status, startRes) = try? await withTaskCancellationHandler(
                operation: { try await promoteTask.value },
                onCancel: { promoteTask.cancel() }
            ), !Task.isCancelled, !isTeardownCompleted, !isDismissing {
                let promoted = try? await PlayerResolvePipeline.extractResolvedSession(
                    status: status,
                    startRes: startRes,
                    client: client,
                    onResolveIdChanged: { [weak self] in self?.activeResolveId = $0 },
                    onProgress: { [weak self] in self?.applyResolveProgressEvent($0) }
                )
                if let promoted, !Task.isCancelled, !isTeardownCompleted, !isDismissing {
                    if promoted.sessionId == prepSession.sessionId {
                        activeSession = promoted
                        host.trackController.rebuildMergedChapters()
                    } else {
                        let promotedIntent = host.trackController.captureCurrentTrackIntent()
                        transport.prepareForItemReplacement()
                        let livePos = max(0, transport.currentTime)
                        try await mountSessionInEngine(
                            promoted,
                            client: client,
                            overrideStartPosition: livePos > 0.5 ? livePos : (request.startPositionSeconds ?? promoted.stream.startPositionSeconds),
                            autoplay: autoplay,
                            trackIntent: promotedIntent
                        )
                    }
                }
            }
        } catch where LunaCoreError.isCancellation(error) {
            isSpeculativeWarmMountInFlight = false
            promoteTask.cancel()
        } catch {
            isSpeculativeWarmMountInFlight = false
            fatalError = nil
            try Task.checkCancellation()
            guard !isTeardownCompleted, !isDismissing else { return }
            let (status, startRes) = try await withTaskCancellationHandler(
                operation: { try await promoteTask.value },
                onCancel: { promoteTask.cancel() }
            )
            let fallbackSession = try await PlayerResolvePipeline.extractResolvedSession(
                status: status,
                startRes: startRes,
                client: client,
                onResolveIdChanged: { [weak self] in self?.activeResolveId = $0 },
                onProgress: { [weak self] in self?.applyResolveProgressEvent($0) }
            )
            try await finishColdMount(fallbackSession, request: request, client: client, autoplay: autoplay)
        }
    }

    private func finishColdMount(
        _ resolvedSession: TvPlaybackSession,
        request: PlaybackLaunchRequest,
        client: LunaCoreClient,
        autoplay: Bool
    ) async throws {
        guard let host else { return }
        pendingHandedOverSessionId = resolvedSession.sessionId
        pendingInflightPrepareTask = nil
        pendingInflightPrepareToken = nil
        try Task.checkCancellation()
        guard !isTeardownCompleted, !isDismissing else { throw CancellationError() }
        ArtworkPipeline.shared.enterPlaybackMemoryMode(
            isHeavySoftwareStream: PlayerEngineConfigurator.isLikelyHeavySoftwareSession(
                resolvedSession,
                dualLayerOverride: comfort.dualLayerOverride,
                lowResUpscaleMode: comfort.lowResUpscaleMode
            ),
            preservedURLs: PlayerEngineConfigurator.curtainPreservedURLs(
                request: request,
                session: resolvedSession,
                client: client
            )
        )
        startupState.resolveStageLabel = "Tilpasser skjerm og starter avspilling…"
        startupState.resolvePercent = 95
        try await mountSessionInEngine(
            resolvedSession,
            client: client,
            overrideStartPosition: request.startPositionSeconds ?? resolvedSession.stream.startPositionSeconds,
            autoplay: autoplay
        )
        fatalError = nil
        isResolving = false
        armFirstFrameFallbackWatchdog()
        host.qosReporter.startHeartbeatLoop()
    }

    func applyResolveProgressEvent(_ event: TvResolveSocketEvent) {
        if let pct = event.percent { startupState.resolvePercent = pct }
        if let headline = event.winnerHeadline, !headline.isEmpty { startupState.resolveHeadline = headline }
        if let msg = event.message, !msg.isEmpty { startupState.resolveStageLabel = msg }
    }

    func triggerSourceSwitch(to candidateId: String) {
        guard !isSwitchingSource, activeSession?.selectedCandidate.candidateId != candidateId else { return }
        switchSourceTask?.cancel()
        switchSourceTask = Task { @MainActor [weak self] in await self?.switchSource(to: candidateId) }
    }

    func loadAlternatives() async {
        guard let client = activeClient, let session = activeSession else { return }
        isLoadingAlternatives = true
        defer { isLoadingAlternatives = false }
        do {
            let res = try await client.fetchAlternatives(sessionId: session.sessionId)
            alternatives = res.alternatives
            markAlternativesLoaded(forSessionId: session.sessionId)
        } catch LunaCoreError.unauthorized {
            onUnauthorized?()
        } catch {}
    }

    func switchSource(to candidateId: String) async {
        guard let host, let client = activeClient, let session = activeSession else {
            isSwitchingSource = false
            return
        }
        host.trackController.flushPendingAudioDelayCommitIfNeeded()
        let capturedIntent = host.trackController.captureCurrentTrackIntent()
        host.scrubController.resetScrubStateOnSessionChange()
        let currentPos = max(0, transport.currentTime)
        isSwitchingSource = true
        startupState.resolveStageLabel = "Bytter utgave sømløst på samme tidskode…"
        startupState.resolvePercent = 70

        do {
            let updatedSession = try await client.switchCandidate(
                sessionId: session.sessionId,
                candidateId: candidateId,
                positionSeconds: currentPos
            )
            transport.prepareForItemReplacement()
            try await mountSessionInEngine(
                updatedSession,
                client: client,
                overrideStartPosition: updatedSession.stream.startPositionSeconds ?? currentPos,
                trackIntent: capturedIntent
            )
            isSwitchingSource = false
        } catch LunaCoreError.unauthorized {
            isSwitchingSource = false
            onUnauthorized?()
        } catch {
            isSwitchingSource = false
            guard !Task.isCancelled else { return }
            host.qosReporter.showTransientBanner("Utgavebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }

    func applyServerSwitchedSession(
        _ switchedSession: TvPlaybackSession,
        client: LunaCoreClient,
        fallbackPosition: Double
    ) async {
        guard let host, !isSwitchingSource, !isResolving else { return }
        host.trackController.flushPendingAudioDelayCommitIfNeeded()
        let capturedIntent = host.trackController.captureCurrentTrackIntent()
        host.scrubController.resetScrubStateOnSessionChange()
        isSwitchingSource = true
        startupState.resolveStageLabel = "Bytter utgave valgt fra iPhone…"
        startupState.resolvePercent = 75
        do {
            transport.prepareForItemReplacement()
            try await mountSessionInEngine(
                switchedSession,
                client: client,
                overrideStartPosition: switchedSession.stream.startPositionSeconds ?? fallbackPosition,
                trackIntent: capturedIntent
            )
            isSwitchingSource = false
        } catch {
            isSwitchingSource = false
            host.qosReporter.showTransientBanner("Utgavebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }
}
