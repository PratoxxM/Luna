import Foundation
import Observation
import UIKit
import AetherBridge

/// Owns playback resolution, warm/cold `AetherEngine` mount, episode & source switches,
/// curtain watchdog, two-phase dismissal, and `PlaybackStopReceipt` dispatch.
@MainActor
@Observable
final class PlayerSessionController {
    var isResolving: Bool = true
    let startupState = PlayerStartupState()
    var fatalError: String?
    var currentRequest: PlaybackLaunchRequest?
    var activeSession: TvPlaybackSession?
    var alternatives: [TvCandidateInfo] = []
    private(set) var alternativesSessionId: String?
    var isLoadingAlternatives: Bool = false
    var isSwitchingSource: Bool = false
    var hasFirstFrameReadyForDisplay: Bool = false
    var isAwaitingDisplaySwitch: Bool = false
    var firstFrameFallbackUnlocked: Bool = false

    @ObservationIgnored weak var host: PlayerViewModel?
    @ObservationIgnored let engine: AetherEngine
    @ObservationIgnored let comfort: ComfortPreferences
    @ObservationIgnored let transport: any PlayerTransportControlling
    @ObservationIgnored let audioActivator: any NativeAudioActivating

    @ObservationIgnored var resolveTask: Task<Void, Never>?
    @ObservationIgnored var firstFrameFallbackTask: Task<Void, Never>?
    @ObservationIgnored var nowPlayingArtworkTask: Task<Void, Never>?
    @ObservationIgnored var switchSourceTask: Task<Void, Never>?
    @ObservationIgnored var registeredStreamToken: String?
    @ObservationIgnored var activeClient: LunaCoreClient?
    @ObservationIgnored private var didTeardown: Bool = false
    @ObservationIgnored var engineOwnerToken: UInt64 = 0
    @ObservationIgnored var isDismissing: Bool = false
    @ObservationIgnored var isSpeculativeWarmMountInFlight: Bool = false
    @ObservationIgnored var pendingStopSnapshot: PendingStopSnapshot?
    @ObservationIgnored var pendingHandedOverSessionId: String?
    @ObservationIgnored var pendingInflightPrepareTask: Task<TvPrepareResponse?, Never>?
    @ObservationIgnored var pendingInflightPrepareToken: String?
    @ObservationIgnored var activeResolveId: String?
    @ObservationIgnored var onUnauthorized: (() -> Void)?

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        transport: any PlayerTransportControlling,
        audioActivator: any NativeAudioActivating
    ) {
        self.engine = engine
        self.comfort = comfort
        self.transport = transport
        self.audioActivator = audioActivator
    }

    func bindHost(_ host: PlayerViewModel) { self.host = host }
    func markAlternativesLoaded(forSessionId sessionId: String) { alternativesSessionId = sessionId }
    var isTeardownCompleted: Bool { didTeardown }

    var isPictureReadyForReveal: Bool {
        PlaybackCurtainWatchdog.isPictureReadyForReveal(
            hasFatalError: fatalError != nil,
            isSwitchingSource: isSwitchingSource,
            isResolving: isResolving,
            isRestoringFromBackground: host?.restoreController.isRestoringFromBackground ?? false,
            needsForegroundVideoRestore: transport.needsForegroundVideoRestore,
            firstFrameFallbackUnlocked: firstFrameFallbackUnlocked,
            hasFirstFrameReadyForDisplay: hasFirstFrameReadyForDisplay,
            isAwaitingDisplaySwitch: isAwaitingDisplaySwitch
        )
    }

    var effectiveDurationSeconds: Double {
        let dur = host?.trackController.durationSeconds ?? 0
        if dur > 0 { return dur }
        return activeSession?.stream.declaredDurationSeconds ?? activeSession?.item.runtimeSeconds ?? 0
    }

    func configurePreviewPlayback(
        request: PlaybackLaunchRequest,
        session: TvPlaybackSession,
        client: LunaCoreClient?,
        audioOptions: [PlayerDrawerAudioOption],
        subtitleOptions: [PlayerDrawerSubtitleOption],
        candidates: [TvCandidateInfo]
    ) {
        guard let host else { return }
        host.bindEnginePublishersIfNeeded()
        currentRequest = request
        activeSession = session
        activeClient = client
        fatalError = nil
        isResolving = false
        hasFirstFrameReadyForDisplay = true
        isAwaitingDisplaySwitch = false
        firstFrameFallbackUnlocked = true
        host.restoreController.isRestoringFromBackground = false
        host.qosReporter.configurePreviewStats(playbackPhase: .paused)
        let declared = session.stream.declaredDurationSeconds ?? session.item.runtimeSeconds ?? 6180
        host.trackController.durationSeconds = declared
        host.scrubController.previewPlayheadOverrideSeconds = request.startPositionSeconds ?? session.stream.startPositionSeconds ?? 1122
        host.trackController.previewAudioOptions = audioOptions
        host.trackController.previewSubtitleOptions = subtitleOptions
        host.trackController.activeAudioTrackIndex = audioOptions.first?.id
        host.trackController.activeSubtitleTrackIndex = subtitleOptions.first?.id
        alternatives = candidates
        alternativesSessionId = session.sessionId
        host.trackController.chapters = PlaybackChapter.mergeRaw(
            probeChapters: session.chapters ?? [],
            engineChapters: [],
            mediaDuration: declared
        )
    }

    func start(request: PlaybackLaunchRequest, client: LunaCoreClient?) {
        guard let host else { return }
        host.bindEnginePublishersIfNeeded()
        PlayerAudioSessionCoordinator.shared.sampleMenuRefreshRateIfIdle(hasActivePlayback: false)
        engineOwnerToken = PlayerAudioSessionCoordinator.shared.claimEngineOwnership()
        host.restoreController.resetTransientTransitionState()
        host.trackController.resetForNewLaunch(itemId: request.itemId)
        host.restoreController.lastForegroundPlaybackWasPlaying = false
        isDismissing = false
        pendingStopSnapshot = nil
        activeResolveId = nil
        pendingInflightPrepareTask?.cancel()
        pendingInflightPrepareTask = request.inflightPrepareTask
        pendingInflightPrepareToken = request.inflightPrepareToken
        pendingHandedOverSessionId = request.preparedSession?.sessionId ?? request.prepareToken
        if let preTok = request.preparedSession?.streamToken, preTok.count >= 8 {
            if let oldTok = registeredStreamToken, oldTok.count >= 8, oldTok != preTok {
                EngineLog.unregisterSecret(oldTok)
            }
            _ = EngineLog.registerSecret(preTok)
            registeredStreamToken = preTok
        }
        didTeardown = false
        fatalError = nil
        firstFrameFallbackUnlocked = false
        host.qosReporter.resetTelemetryForSession()
        currentRequest = request
        guard let client else {
            pendingInflightPrepareTask?.cancel()
            pendingInflightPrepareTask = nil
            pendingInflightPrepareToken = nil
            pendingHandedOverSessionId = nil
            fatalError = "Mangler tilkobling til LunaCore."
            isResolving = false
            return
        }
        activeClient = client
        alternatives = []
        alternativesSessionId = nil
        resolveTask?.cancel()
        resolveTask = Task { @MainActor [weak self] in
            await self?.runResolveAndLoad(request: request, client: client)
        }
    }

    func playNextEpisode(_ next: TvNextEpisodeSummary) {
        guard let host, let client = activeClient, let current = activeSession else { return }
        host.restoreController.resetTransientTransitionState()
        resolveTask?.cancel()
        activeResolveId = nil
        pendingInflightPrepareTask?.cancel()
        pendingInflightPrepareTask = nil
        pendingInflightPrepareToken = nil
        let handoff = host.qosReporter.consumePrewarmForNextEpisode(itemId: next.itemId)
        pendingHandedOverSessionId = handoff.matchedSessionId
        if let nextTok = handoff.streamToken, nextTok.count >= 8 {
            if handoff.matchedSessionId != nil {
                if let oldTok = registeredStreamToken, oldTok.count >= 8, oldTok != nextTok {
                    EngineLog.unregisterSecret(oldTok)
                }
                registeredStreamToken = nextTok
            } else {
                EngineLog.unregisterSecret(nextTok)
            }
        }
        switchSourceTask?.cancel()
        switchSourceTask = nil
        host.qosReporter.cancelHeartbeatOnly()

        let seriesName = current.item.seriesTitle
        let cleanNextTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            next.title, seriesTitle: seriesName, season: next.season, episode: next.episode
        ) ?? ""
        let req = PlaybackLaunchRequest(
            itemId: next.itemId, title: cleanNextTitle, seriesTitle: seriesName,
            season: next.season, episode: next.episode, startPositionSeconds: 0,
            prepareToken: handoff.matchedSessionId,
            backdropUrl: next.stillUrl ?? current.item.backdropUrl, logoUrl: current.item.logoUrl
        )
        currentRequest = req
        alternatives = []
        alternativesSessionId = nil
        host.trackController.resetForNewLaunch(itemId: next.itemId)
        startupState.resolveHeadline = nil
        startupState.resolvePercent = 12
        startupState.resolveStageLabel = "Starter neste episode…"
        isResolving = true
        hasFirstFrameReadyForDisplay = false
        firstFrameFallbackUnlocked = false

        let prevSessionId = current.sessionId
        let finalPos = max(0, transport.currentTime)
        let finalDur = max(0, effectiveDurationSeconds)
        let isCompleted = PlaybackSessionPolicy.isPlaybackCompleted(
            positionSeconds: finalPos, durationSeconds: finalDur,
            playbackEnded: host.qosReporter.playbackPhase == .ended,
            chapters: host.trackController.chapters
        )
        activeSession = nil
        transport.prepareForItemReplacement()

        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: prevSessionId, state: "stopped",
                positionSeconds: finalPos, durationSeconds: finalDur,
                completed: isCompleted ? true : nil
            )
        }
        resolveTask = Task { @MainActor [weak self] in
            await self?.runResolveAndLoad(request: req, client: client)
        }
    }

    func mountSessionInEngine(
        _ session: TvPlaybackSession,
        client: LunaCoreClient,
        overrideStartPosition: Double?,
        autoplay: Bool = true,
        trackIntent: PlaybackTrackIntent? = nil
    ) async throws {
        guard let host, let streamURL = client.buildAbsoluteURL(session.stream.url) else {
            throw LunaCoreError.invalidURL(session.stream.url)
        }
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        host.restoreController.cancelPendingPausedRestoreResume()
        host.scrubController.cancelPendingScrubCommit()
        host.scrubController.cancelRingHoldTask()
        host.restoreController.needsNativeAudioActivationAfterPausedRestore = false
        try Task.checkCancellation()

        let previousToken = registeredStreamToken
        if session.streamToken.count >= 8 { _ = EngineLog.registerSecret(session.streamToken) }
        // AE-G02: Disable forward subtitle prefetch while preserving 10 s delay history.
        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10

        let initialAudioDelayMs = host.trackController.prepareForEngineMount()
        let initialWirelessRoute = host.trackController.isWirelessAudioRouteActive
        let preferNorwegian = host.trackController.preferenceStore.preferNorwegianAudio(forItemId: session.item.itemId)
        host.trackController.preferNorwegianAudio = preferNorwegian

        let options = PlayerEngineConfigurator.buildLoadOptions(
            session: session, client: client, comfort: comfort,
            audioEnhancement: host.trackController.audioEnhancement,
            audioDelaySeconds: host.trackController.effectiveAudioDelaySecondsForActiveRoute(),
            autoplay: autoplay, suppressInitialSubtitleSelection: trackIntent != nil,
            preferNorwegianAudio: preferNorwegian
        )
        let startPos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
        do {
            try await transport.loadStream(url: streamURL, startPosition: startPos > 0.5 ? startPos : nil, options: options)
            try Task.checkCancellation()
            guard !didTeardown, !isDismissing else { throw CancellationError() }
            if autoplay {
                await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
                try Task.checkCancellation()
            } else {
                host.restoreController.needsNativeAudioActivationAfterPausedRestore =
                    PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: transport.videoRoute)
            }
        } catch {
            if session.streamToken.count >= 8, session.streamToken != previousToken {
                EngineLog.unregisterSecret(session.streamToken)
            }
            throw error
        }

        activeSession = session
        pendingHandedOverSessionId = nil
        pendingInflightPrepareTask = nil
        host.qosReporter.lastReportedServerState = autoplay ? "playing" : "paused"
        host.qosReporter.resetDolbyVisionFallback()
        registeredStreamToken = session.streamToken.count >= 8 ? session.streamToken : previousToken
        startupState.resolveHeadline = session.selectedCandidate.displayHeadline
        if let prev = previousToken, prev.count >= 8, prev != session.streamToken {
            EngineLog.unregisterSecret(prev)
        }
        host.trackController.completeEngineMount(
            session: session, initialAudioDelayMs: initialAudioDelayMs,
            initialWirelessRoute: initialWirelessRoute, trackIntent: trackIntent
        )
        PlayerNowPlayingCoordinator.publish(session: session, client: client, viewModel: host)
    }

    func armFirstFrameFallbackWatchdog() {
        firstFrameFallbackTask?.cancel()
        firstFrameFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if !self.isPictureReadyForReveal { self.firstFrameFallbackUnlocked = true }
        }
    }

    func cancelSessionTasks() {
        resolveTask?.cancel(); resolveTask = nil
        switchSourceTask?.cancel(); switchSourceTask = nil
        firstFrameFallbackTask?.cancel(); firstFrameFallbackTask = nil
        nowPlayingArtworkTask?.cancel(); nowPlayingArtworkTask = nil
    }

    func captureStopSnapshot() -> PendingStopSnapshot {
        let hasActive = activeSession != nil
        let finalPos = hasActive ? max(0, transport.currentTime) : 0
        let finalDur = hasActive ? max(0, effectiveDurationSeconds) : 0
        let isCompleted = hasActive && PlaybackSessionPolicy.isPlaybackCompleted(
            positionSeconds: finalPos, durationSeconds: finalDur,
            playbackEnded: host?.qosReporter.playbackPhase == .ended,
            chapters: host?.trackController.chapters ?? []
        )
        return PendingStopSnapshot(
            client: activeClient, sessionId: activeSession?.sessionId ?? pendingHandedOverSessionId,
            resolveId: hasActive ? nil : activeResolveId,
            cancelItemId: hasActive ? nil : currentRequest?.itemId,
            cancelPrepareToken: hasActive ? nil : pendingInflightPrepareToken,
            inflightPrepareTask: hasActive ? nil : pendingInflightPrepareTask,
            finalPos: finalPos, finalDur: finalDur, isCompleted: isCompleted,
            itemId: activeSession?.item.itemId ?? currentRequest?.itemId,
            mediaType: PlaybackSessionPolicy.inferredMediaType(
                sessionMediaType: activeSession?.item.mediaType,
                requestItemId: currentRequest?.itemId,
                requestSeason: currentRequest?.season, requestEpisode: currentRequest?.episode
            ),
            seasonNumber: activeSession?.item.season ?? currentRequest?.season,
            episodeNumber: activeSession?.item.episode ?? currentRequest?.episode,
            subtitleDelayMs: host?.trackController.subtitleDelayMs ?? 0
        )
    }

    func prepareForDismissal() {
        guard let host, !didTeardown, !isDismissing else { return }
        isDismissing = true
        host.cancelAllSessionTasks()
        host.scrubController.resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false
        pendingStopSnapshot = captureStopSnapshot()
        activeResolveId = nil
        pendingInflightPrepareTask?.cancel(); pendingInflightPrepareTask = nil
        pendingInflightPrepareToken = nil; pendingHandedOverSessionId = nil
        host.cancellables.removeAll()
        host.didBindEnginePublishers = false

        if PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(engineOwnerToken),
           PlayerEngineConfigurator.shouldPauseEngineOnDismiss(
               engineState: transport.state, playbackPhase: host.qosReporter.playbackPhase
           ) {
            transport.pause()
        }
    }

    func teardownAndStop(
        onComplete: (@MainActor @Sendable () -> Void)? = nil,
        onStopReceipt: (@MainActor @Sendable (PlaybackStopReceipt) -> Void)? = nil
    ) {
        guard let host, !didTeardown else { return }
        didTeardown = true
        host.cancelAllSessionTasks()
        host.scrubController.resetScrubStateOnSessionChange()
        UIApplication.shared.isIdleTimerDisabled = false

        let snapshot = pendingStopSnapshot ?? captureStopSnapshot()
        pendingStopSnapshot = nil; activeResolveId = nil
        pendingHandedOverSessionId = nil; pendingInflightPrepareTask = nil; pendingInflightPrepareToken = nil
        ArtworkPipeline.shared.exitPlaybackMemoryMode()
        host.cancellables.removeAll()
        host.didBindEnginePublishers = false

        if PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(engineOwnerToken) {
            PlayerNowPlayingCoordinator.clear(engine: engine)
            let resetOnExit = PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: comfort.menuDisplayMode,
                videoFormat: host.qosReporter.videoFormat,
                isForegroundActive: host.restoreController.isForegroundActive
            )
            transport.stop(resetDisplayCriteria: resetOnExit, finalTeardown: true)
            if resetOnExit {
                PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            } else {
                if comfort.menuDisplayMode == .preserveHDR60HzQMS {
                    PlayerAudioSessionCoordinator.shared.applyMenu60HzHDRCriteriaIfNeeded(videoFormat: host.qosReporter.videoFormat)
                }
                PlayerAudioSessionCoordinator.shared.holdDisplayCriteriaUntilBackground(engine: engine)
            }
        }

        if let tok = registeredStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            registeredStreamToken = nil
        }
        host.qosReporter.unregisterPrewarmSecretOnTeardown()
        PlayerResolvePipeline.dispatchTeardownNetworkAndReceipt(
            snapshot: snapshot, onComplete: onComplete, onStopReceipt: onStopReceipt
        )
    }
}
