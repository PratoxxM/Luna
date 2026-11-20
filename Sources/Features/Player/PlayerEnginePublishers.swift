import Foundation
import Combine
import AetherBridge

extension PlayerViewModel {
    func bindEnginePublishers() {
        engine.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                let previousPhase = self.lastObservedPhase
                self.lastObservedPhase = phase
                self.playbackPhase = phase
                self.updateIdleTimer(for: phase)
                if self.isForegroundActive,
                   !self.isRestoringFromBackground,
                   !self.isResolving,
                   !self.isSwitchingSource,
                   !self.transport.needsForegroundVideoRestore {
                    self.lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
                        playbackPhase: phase,
                        engineState: self.transport.state
                    )
                }
                if case .error(let errMsg) = phase {
                    guard !self.isRestoringFromBackground else { return }
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
                    guard !self.isRestoringFromBackground, !self.isDismissing else { return }
                    Task { @MainActor [weak self] in
                        await self?.sendHeartbeatOnce(
                            overrideState: phase == .ended ? "stopped" : "paused",
                            completed: phase == .ended
                        )
                    }
                } else if phase == .playing, previousPhase != .playing {
                    guard !self.isRestoringFromBackground, !self.isDismissing else { return }
                    if self.needsNativeAudioActivationAfterPausedRestore {
                        self.needsNativeAudioActivationAfterPausedRestore = false
                        let videoRoute = self.transport.videoRoute
                        let activator = self.audioActivator
                        Task {
                            await activator.activateNativePlaybackIfNeeded(videoRoute: videoRoute)
                        }
                    }
                    if self.lastReportedServerState != nil,
                       self.lastReportedServerState != "playing" {
                        Task { @MainActor [weak self] in
                            guard let self, !self.isDismissing else { return }
                            await self.sendHeartbeatOnce(overrideState: "playing")
                        }
                    }
                }
            }
            .store(in: &cancellables)

        engine.$hasFirstFrameReadyForDisplay.assign(to: &$hasFirstFrameReadyForDisplay)
        engine.$isAwaitingDisplaySwitch.assign(to: &$isAwaitingDisplaySwitch)
        engine.$startupProgress
            .sink { [weak self] progress in
                self?.startupState.updateEngineStartupFraction(progress?.fraction)
            }
            .store(in: &cancellables)

        engine.$duration
            .sink { [weak self] dur in
                guard let self else { return }
                self.durationSeconds = dur
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$mediaChapters
            .sink { [weak self] ch in
                guard let self else { return }
                self.engineChapters = ch
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$videoFormat.assign(to: &$videoFormat)
        engine.$sourceDVProfile.assign(to: &$sourceDVProfile)
        engine.$dolbyVisionConversion.assign(to: &$dolbyVisionConversion)
        engine.$videoRoute.assign(to: &$videoRoute)
        engine.$audioDelivery.assign(to: &$audioDelivery)
        engine.$sourceVideoCodecName.assign(to: &$sourceVideoCodecName)
        engine.$sourceVideoWidth.assign(to: &$sourceVideoWidth)
        engine.$sourceVideoHeight.assign(to: &$sourceVideoHeight)
        engine.$sourceVideoFrameRate.assign(to: &$sourceVideoFrameRate)
        engine.$activeVideoDecoder.assign(to: &$activeVideoDecoder)
        engine.$activeAudioDecoder.assign(to: &$activeAudioDecoder)
        engine.$activeUpscale.assign(to: &$activeUpscale)

        engine.$audioTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                self.audioTracks = tracks
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !self.subtitleTracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex.assign(to: &$activeAudioTrackIndex)
        engine.$subtitleTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                self.subtitleTracks = tracks
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !tracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeSubtitleTrackIndex.assign(to: &$activeSubtitleTrackIndex)

        comfort.$audioDelayMs
            .sink { [weak self] updatedMs in
                guard let self, self.audioDelayMs != updatedMs else { return }
                self.audioDelayMs = updatedMs
            }
            .store(in: &cancellables)
    }
}
