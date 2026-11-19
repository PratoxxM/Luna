import Foundation
import SwiftUI
import AetherBridge

extension PlayerViewModel {
    // MARK: - Foreground Return Recovery

    nonisolated static func isActiveTransportIntent(
        playbackPhase: PlaybackPhase,
        engineState: PlaybackState
    ) -> Bool {
        if engineState == .paused || engineState == .idle || engineState == .ended {
            return false
        }
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
            if phase == .background {
                cancelPendingPausedRestoreResume()
                cancelPendingScrubCommit()
            }
            if isForegroundActive,
               !isRestoringFromBackground,
               !isResolving,
               !isSwitchingSource,
               !transport.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                    playbackPhase: playbackPhase,
                    engineState: transport.state
                )
            }
            isForegroundActive = false
        }
    }

    func attemptForegroundRecoveryIfNeeded() async {
        guard isForegroundActive else { return }
        guard Self.shouldAttemptForegroundVideoRestore(
            needsForegroundVideoRestore: transport.needsForegroundVideoRestore,
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
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        let wasPlayingBeforeBackground = lastForegroundPlaybackWasPlaying
        let savedResumePosition = max(0, transport.currentTime)
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
                videoRoute: transport.videoRoute
            ) {
                await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
                guard !Task.isCancelled, !isTeardownCompleted else { return }
            }

            let finalShouldPlay = Self.resolvedPostRestorePlayingIntent(
                defaultShouldPlay: defaultShouldPlay,
                userOverride: userDesiredPlayingDuringRestore
            )
            if finalShouldPlay {
                if Self.shouldActivateNativeAudioDuringRestore(
                    shouldPlay: true,
                    videoRoute: transport.videoRoute
                ) && !initialShouldPlay {
                    await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
                    guard !Task.isCancelled, !isTeardownCompleted else { return }
                }
                if transport.state != .playing {
                    transport.play()
                }
            } else {
                if transport.state != .paused {
                    transport.pause()
                }
                needsNativeAudioActivationAfterPausedRestore = PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(
                    for: transport.videoRoute
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
                let fallbackTime = max(fallbackPositionSeconds, max(0, transport.currentTime))
                let resumeAt = fallbackTime > 0.5 ? fallbackTime : baseReq.startPositionSeconds
                let retryReq = PlaybackLaunchRequest(
                    itemId: baseReq.itemId,
                    title: baseReq.title,
                    seriesTitle: baseReq.seriesTitle,
                    season: baseReq.season,
                    episode: baseReq.episode,
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
                if !capturedShouldPlay && transport.state != .paused {
                    transport.pause()
                }
                lastForegroundPlaybackWasPlaying = capturedShouldPlay
            } else {
                isRestoringFromBackground = false
                userDesiredPlayingDuringRestore = nil
                fatalError = LunaCopy.friendlyErrorMessage(error)
            }
        }
    }
}
