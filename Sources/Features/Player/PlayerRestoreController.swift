import Foundation
import Observation
import SwiftUI
import UIKit
import AetherBridge

/// Owns foreground/background video surface restore (`transport.reloadAtCurrentPosition`),
/// paused-restore native audio activation ordering, `togglePlayPause()`, and `isIdleTimerDisabled`.
@MainActor
@Observable
final class PlayerRestoreController {
    var isRestoringFromBackground: Bool = false

    @ObservationIgnored private weak var host: PlayerViewModel?
    @ObservationIgnored let comfort: ComfortPreferences
    @ObservationIgnored let transport: any PlayerTransportControlling
    @ObservationIgnored let audioActivator: any NativeAudioActivating

    @ObservationIgnored var foregroundRestoreTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pausedRestoreResumeTask: Task<Void, Never>?
    @ObservationIgnored private var pausedRestoreResumeToken: UInt64 = 0
    @ObservationIgnored var isForegroundActive: Bool = true
    @ObservationIgnored var lastForegroundPlaybackWasPlaying: Bool = false
    @ObservationIgnored var userDesiredPlayingDuringRestore: Bool?
    @ObservationIgnored var needsNativeAudioActivationAfterPausedRestore: Bool = false

    init(
        comfort: ComfortPreferences,
        transport: any PlayerTransportControlling,
        audioActivator: any NativeAudioActivating
    ) {
        self.comfort = comfort
        self.transport = transport
        self.audioActivator = audioActivator
    }

    func bindHost(_ host: PlayerViewModel) {
        self.host = host
    }

    // MARK: - Static Predicates

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
        PlaybackSessionPolicy.resolvedPostRestorePlayingIntent(
            defaultShouldPlay: defaultShouldPlay,
            userOverride: userOverride
        )
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
        needsForegroundVideoRestore &&
            hasActiveSession &&
            !isResolving &&
            !isSwitchingSource &&
            !isRestoringFromBackground &&
            !hasFatalError &&
            !didTeardown
    }

    nonisolated static func shouldActivateNativeAudioBeforePlayOnResume(
        wasPlaying: Bool,
        needsNativeAudioActivationAfterPausedRestore: Bool
    ) -> Bool {
        !wasPlaying && needsNativeAudioActivationAfterPausedRestore
    }

    // MARK: - Paused-Restore Native Audio & Play/Pause

    func resetTransientTransitionState() {
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        host?.scrubController.cancelPendingScrubCommit()
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        needsNativeAudioActivationAfterPausedRestore = false
        host?.trackController.cancelTasks()
    }

    func cancelPendingPausedRestoreResume() {
        pausedRestoreResumeToken &+= 1
        pausedRestoreResumeTask?.cancel()
        pausedRestoreResumeTask = nil
    }

    func activateNativeAudioForPendingResumeIfNeeded() async {
        guard needsNativeAudioActivationAfterPausedRestore else { return }
        await audioActivator.activateNativePlaybackIfNeeded(videoRoute: transport.videoRoute)
    }

    private func beginPausedRestoreResumeWithNativeAudioActivation() {
        guard let host else { return }
        host.scrubController.cancelPendingScrubCommit()
        cancelPendingPausedRestoreResume()
        pausedRestoreResumeToken &+= 1
        let resumeToken = pausedRestoreResumeToken
        let expectedSessionId = host.sessionController.activeSession?.sessionId

        if isForegroundActive && !transport.needsForegroundVideoRestore {
            lastForegroundPlaybackWasPlaying = true
        }

        pausedRestoreResumeTask = Task { @MainActor [weak self] in
            guard let self, let host = self.host else { return }
            await self.activateNativeAudioForPendingResumeIfNeeded()
            if self.pausedRestoreResumeToken == resumeToken {
                self.pausedRestoreResumeTask = nil
            }
            guard !Task.isCancelled,
                  self.pausedRestoreResumeToken == resumeToken,
                  !host.sessionController.isTeardownCompleted,
                  host.sessionController.fatalError == nil,
                  !host.sessionController.isResolving,
                  !host.sessionController.isSwitchingSource,
                  !self.isRestoringFromBackground,
                  !host.scrubController.isScrubbing,
                  self.isForegroundActive,
                  !self.transport.needsForegroundVideoRestore,
                  host.sessionController.activeSession?.sessionId == expectedSessionId else {
                return
            }
            self.needsNativeAudioActivationAfterPausedRestore = false
            if self.transport.state == .paused || self.transport.state == .loading {
                self.transport.play()
            }
            if self.isForegroundActive && !self.transport.needsForegroundVideoRestore {
                self.lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                    playbackPhase: self.transport.playbackPhase,
                    engineState: self.transport.state
                )
            }
        }
    }

    func togglePlayPause() {
        guard let host else { return }
        if isRestoringFromBackground {
            let currentTarget = userDesiredPlayingDuringRestore ?? lastForegroundPlaybackWasPlaying
            let nextTarget = !currentTarget
            userDesiredPlayingDuringRestore = nextTarget
            lastForegroundPlaybackWasPlaying = nextTarget
            return
        }
        if pausedRestoreResumeTask != nil || host.scrubController.scrubCommitTask != nil {
            cancelPendingPausedRestoreResume()
            host.scrubController.cancelPendingScrubCommit()
            if isForegroundActive && !transport.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = false
            }
            return
        }
        let wasPlaying = Self.isActiveTransportIntent(
            playbackPhase: transport.playbackPhase,
            engineState: transport.state
        )
        if Self.shouldActivateNativeAudioBeforePlayOnResume(
            wasPlaying: wasPlaying,
            needsNativeAudioActivationAfterPausedRestore: needsNativeAudioActivationAfterPausedRestore
        ) {
            beginPausedRestoreResumeWithNativeAudioActivation()
            return
        }
        transport.togglePlayPause()
        if isForegroundActive && !transport.needsForegroundVideoRestore {
            lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                playbackPhase: transport.playbackPhase,
                engineState: transport.state
            )
        }
    }

    // MARK: - Scene Lifecycle & Foreground Restore

    func updateInitialScenePhase(_ phase: ScenePhase) {
        isForegroundActive = (phase == .active)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard let host else { return }
        if phase == .active {
            isForegroundActive = true
            attemptForegroundRecoveryIfNeeded()
        } else if phase == .inactive || phase == .background {
            if phase == .background {
                cancelPendingPausedRestoreResume()
                host.scrubController.cancelPendingScrubCommit()
            }
            if isForegroundActive,
               !isRestoringFromBackground,
               !host.sessionController.isResolving,
               !host.sessionController.isSwitchingSource,
               !transport.needsForegroundVideoRestore {
                lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                    playbackPhase: host.qosReporter.playbackPhase,
                    engineState: transport.state
                )
            }
            isForegroundActive = false
        }
    }

    func attemptForegroundRecoveryIfNeeded() {
        guard let host, isForegroundActive else { return }
        guard Self.shouldAttemptForegroundVideoRestore(
            needsForegroundVideoRestore: transport.needsForegroundVideoRestore,
            hasActiveSession: host.sessionController.activeSession != nil,
            isResolving: host.sessionController.isResolving,
            isSwitchingSource: host.sessionController.isSwitchingSource,
            isRestoringFromBackground: isRestoringFromBackground,
            hasFatalError: host.sessionController.fatalError != nil,
            didTeardown: host.sessionController.isTeardownCompleted
        ) else {
            return
        }

        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        cancelPendingPausedRestoreResume()
        host.scrubController.cancelPendingScrubCommit()
        let wasPlayingBeforeBackground = lastForegroundPlaybackWasPlaying
        let savedResumePosition = max(0, transport.currentTime)
        userDesiredPlayingDuringRestore = nil
        isRestoringFromBackground = true
        host.sessionController.hasFirstFrameReadyForDisplay = false
        host.sessionController.firstFrameFallbackUnlocked = false
        host.sessionController.startupState.resolveStageLabel = "Gjenoppretter avspilling…"
        host.sessionController.startupState.resolvePercent = 90
        updateIdleTimer(for: host.qosReporter.playbackPhase)

        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = Task { @MainActor [weak self] in
            await self?.performForegroundRestore(
                defaultShouldPlay: wasPlayingBeforeBackground,
                fallbackPositionSeconds: savedResumePosition
            )
        }
    }

    private func performForegroundRestore(
        defaultShouldPlay: Bool,
        fallbackPositionSeconds: Double
    ) async {
        guard let host else { return }
        defer {
            if isRestoringFromBackground {
                isRestoringFromBackground = false
            }
            userDesiredPlayingDuringRestore = nil
            updateIdleTimer(for: host.qosReporter.playbackPhase)
        }

        do {
            host.trackController.isWirelessAudioRouteActive = PlayerAudioSessionCoordinator.currentOutputUsesWirelessCompensation()
            let snapshot = PlayerEngineConfigurator.captureReloadComfortSnapshot(
                comfort: comfort,
                audioEnhancement: host.trackController.audioEnhancement,
                audioDelaySeconds: host.trackController.effectiveAudioDelaySecondsForActiveRoute()
            )
            let currentSession = host.sessionController.activeSession
            host.engine.maximumSubtitleAdvanceSeconds = 0
            host.engine.maximumSubtitleDelaySeconds = 10
            try await transport.reloadAtCurrentPosition { options in
                options.autoplay = defaultShouldPlay
                PlayerEngineConfigurator.applyRestoreDisplayAndUpscaleOptions(snapshot, session: currentSession, to: &options)
            }
            guard !Task.isCancelled, !host.sessionController.isTeardownCompleted else { return }
            if host.trackController.subtitleDelayMs != 0 {
                transport.setSoftwareSubtitleDelay(host.trackController.subtitleDelaySeconds)
            }

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
                guard !Task.isCancelled, !host.sessionController.isTeardownCompleted else { return }
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
                    guard !Task.isCancelled, !host.sessionController.isTeardownCompleted else { return }
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
            host.sessionController.armFirstFrameFallbackWatchdog()
            updateIdleTimer(for: host.qosReporter.playbackPhase)
            if host.sessionController.activeSession != nil {
                await host.qosReporter.sendHeartbeatOnce(overrideState: finalShouldPlay ? "playing" : "paused")
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !host.sessionController.isTeardownCompleted else { return }
            let capturedShouldPlay = Self.resolvedPostRestorePlayingIntent(
                defaultShouldPlay: defaultShouldPlay,
                userOverride: userDesiredPlayingDuringRestore
            )
            if let client = host.sessionController.activeClient, let baseReq = host.sessionController.currentRequest {
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
                    candidateId: host.sessionController.activeSession?.selectedCandidate.id ?? baseReq.candidateId,
                    prepareToken: nil,
                    backdropUrl: baseReq.backdropUrl,
                    logoUrl: baseReq.logoUrl
                )
                host.sessionController.currentRequest = retryReq
                await host.sessionController.runResolveAndLoad(
                    request: retryReq,
                    client: client,
                    autoplay: capturedShouldPlay
                )
                guard !Task.isCancelled, !host.sessionController.isTeardownCompleted,
                      host.sessionController.fatalError == nil else {
                    return
                }
                if !capturedShouldPlay && transport.state != .paused {
                    transport.pause()
                }
                lastForegroundPlaybackWasPlaying = capturedShouldPlay
            } else {
                isRestoringFromBackground = false
                userDesiredPlayingDuringRestore = nil
                host.sessionController.fatalError = LunaCopy.friendlyErrorMessage(error)
            }
        }
    }

    func updateIdleTimer(for phase: PlaybackPhase) {
        let isResolving = host?.sessionController.isResolving ?? false
        let isScrubbing = host?.scrubController.isScrubbing ?? false
        switch phase {
        case .playing, .loading, .seeking, .rebuffering, .stalled:
            UIApplication.shared.isIdleTimerDisabled = true
        case .paused, .idle, .ended, .error:
            UIApplication.shared.isIdleTimerDisabled = isResolving || isScrubbing || isRestoringFromBackground
        }
    }

    func cancelTasks() {
        cancelPendingPausedRestoreResume()
        foregroundRestoreTask?.cancel()
        foregroundRestoreTask = nil
        isRestoringFromBackground = false
        userDesiredPlayingDuringRestore = nil
        needsNativeAudioActivationAfterPausedRestore = false
    }
}
