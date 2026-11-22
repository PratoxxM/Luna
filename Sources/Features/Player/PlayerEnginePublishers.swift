import Foundation
import Combine
import AetherBridge

extension PlayerViewModel {
    private func bindEquatable<P: Publisher>(
        _ publisher: P,
        to keyPath: ReferenceWritableKeyPath<PlayerViewModel, P.Output>
    ) where P.Failure == Never, P.Output: Equatable {
        publisher
            .sink { [weak self] value in
                guard let self, self[keyPath: keyPath] != value else { return }
                self[keyPath: keyPath] = value
            }
            .store(in: &cancellables)
    }

    func bindEnginePublishers() {
        engine.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                let previousPhase = self.lastObservedPhase
                self.lastObservedPhase = phase
                if self.playbackPhase != phase {
                    self.playbackPhase = phase
                }
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

        bindEquatable(engine.$hasFirstFrameReadyForDisplay, to: \.hasFirstFrameReadyForDisplay)
        bindEquatable(engine.$isAwaitingDisplaySwitch, to: \.isAwaitingDisplaySwitch)
        engine.$startupProgress
            .sink { [weak self] progress in
                self?.startupState.updateEngineStartupFraction(progress?.fraction)
            }
            .store(in: &cancellables)

        engine.$duration
            .sink { [weak self] dur in
                guard let self, self.durationSeconds != dur else { return }
                self.durationSeconds = dur
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$mediaChapters
            .sink { [weak self] ch in
                guard let self, self.engineChapters != ch else { return }
                self.engineChapters = ch
                self.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        bindEquatable(engine.$videoFormat, to: \.videoFormat)
        bindEquatable(engine.$sourceDVProfile, to: \.sourceDVProfile)
        bindEquatable(engine.$dolbyVisionConversion, to: \.dolbyVisionConversion)
        bindEquatable(engine.$videoRoute, to: \.videoRoute)
        bindEquatable(engine.$audioDelivery, to: \.audioDelivery)
        bindEquatable(engine.$sourceVideoCodecName, to: \.sourceVideoCodecName)
        bindEquatable(engine.$sourceVideoWidth, to: \.sourceVideoWidth)
        bindEquatable(engine.$sourceVideoHeight, to: \.sourceVideoHeight)
        bindEquatable(engine.$sourceVideoFrameRate, to: \.sourceVideoFrameRate)
        bindEquatable(engine.$activeVideoDecoder, to: \.activeVideoDecoder)
        bindEquatable(engine.$activeAudioDecoder, to: \.activeAudioDecoder)
        bindEquatable(engine.$activeUpscale, to: \.activeUpscale)

        engine.$audioTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                if self.audioTracks != tracks {
                    self.audioTracks = tracks
                }
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !self.subtitleTracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        bindEquatable(engine.$activeAudioTrackIndex, to: \.activeAudioTrackIndex)

        engine.$subtitleTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                if self.subtitleTracks != tracks {
                    self.subtitleTracks = tracks
                }
                if self.comfort.smartNordicSubtitleRule && !self.userManuallySelectedSubtitle && !tracks.isEmpty {
                    self.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        bindEquatable(engine.$activeSubtitleTrackIndex, to: \.activeSubtitleTrackIndex)

        engine.systemCaptionRequest
            .sink { [weak self] request in
                self?.handleSystemCaptionRequest(request)
            }
            .store(in: &cancellables)
    }
}
