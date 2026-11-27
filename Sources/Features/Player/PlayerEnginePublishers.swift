import Foundation
import AVFoundation
import Combine
import AetherBridge

extension PlayerViewModel {
    private func bindSessionEquatable<P: Publisher>(
        _ publisher: P,
        to keyPath: ReferenceWritableKeyPath<PlayerSessionController, P.Output>
    ) where P.Failure == Never, P.Output: Equatable {
        publisher
            .sink { [weak self] value in
                guard let self, self.sessionController[keyPath: keyPath] != value else { return }
                self.sessionController[keyPath: keyPath] = value
            }
            .store(in: &cancellables)
    }

    private func bindQoSEquatable<P: Publisher>(
        _ publisher: P,
        to keyPath: ReferenceWritableKeyPath<PlayerQoSReporter, P.Output>
    ) where P.Failure == Never, P.Output: Equatable {
        publisher
            .sink { [weak self] value in
                guard let self, self.qosReporter[keyPath: keyPath] != value else { return }
                self.qosReporter[keyPath: keyPath] = value
            }
            .store(in: &cancellables)
    }

    func bindEnginePublishers() {
        engine.$playbackPhase
            .sink { [weak self] phase in
                guard let self else { return }
                let previousPhase = self.qosReporter.lastObservedPhase
                self.qosReporter.lastObservedPhase = phase
                if self.qosReporter.playbackPhase != phase {
                    self.qosReporter.playbackPhase = phase
                }
                let isTransientTransition = self.sessionController.isResolving
                    || self.sessionController.isSwitchingSource
                    || self.sessionController.isReplacingSourceItem
                    || self.restoreController.isRestoringFromBackground
                    || self.sessionController.isDismissing
                    || self.sessionController.isTeardownCompleted
                self.qosReporter.recordPlaybackPhaseTransition(
                    from: previousPhase,
                    to: phase,
                    isTransientTransition: isTransientTransition
                )
                self.restoreController.updateIdleTimer(for: phase)
                if self.restoreController.isForegroundActive,
                   !self.restoreController.isRestoringFromBackground,
                   !self.sessionController.isResolving,
                   !self.sessionController.isSwitchingSource,
                   !self.transport.needsForegroundVideoRestore {
                    self.restoreController.lastForegroundPlaybackWasPlaying = PlayerRestoreController.isActiveTransportIntent(
                        playbackPhase: phase,
                        engineState: self.transport.state
                    )
                }
                if case .error(let errMsg) = phase {
                    guard !self.restoreController.isRestoringFromBackground,
                          !self.sessionController.isSpeculativeWarmMountInFlight else { return }
                    self.qosReporter.cancelHeartbeatOnly()
                    self.sessionController.isResolving = false
                    self.sessionController.isSwitchingSource = false
                    if self.sessionController.fatalError == nil {
                        self.sessionController.fatalError = PlayerEngineConfigurator.friendlyEngineErrorMessage(
                            rawMessage: errMsg,
                            errorInfo: self.engine.errorInfo
                        )
                    }
                    Task { @MainActor [weak self] in
                        guard let self, !self.sessionController.isDismissing, !self.sessionController.isTeardownCompleted else { return }
                        await self.qosReporter.sendHeartbeatOnce(overrideState: "stopped")
                    }
                } else if phase == .paused || phase == .ended {
                    guard !self.restoreController.isRestoringFromBackground,
                          !self.sessionController.isDismissing,
                          !self.sessionController.isTeardownCompleted else { return }
                    Task { @MainActor [weak self] in
                        guard let self, !self.sessionController.isDismissing, !self.sessionController.isTeardownCompleted else { return }
                        await self.qosReporter.sendHeartbeatOnce(
                            overrideState: phase == .ended ? "stopped" : "paused",
                            completed: phase == .ended
                        )
                    }
                } else if phase == .playing, previousPhase != .playing {
                    guard !self.restoreController.isRestoringFromBackground,
                          !self.sessionController.isDismissing,
                          !self.sessionController.isTeardownCompleted else { return }
                    if self.restoreController.needsNativeAudioActivationAfterPausedRestore {
                        self.restoreController.needsNativeAudioActivationAfterPausedRestore = false
                        let videoRoute = self.transport.videoRoute
                        let activator = self.audioActivator
                        Task {
                            await activator.activateNativePlaybackIfNeeded(videoRoute: videoRoute)
                        }
                    }
                    if self.qosReporter.lastReportedServerState != nil,
                       self.qosReporter.lastReportedServerState != "playing" {
                        Task { @MainActor [weak self] in
                            guard let self, !self.sessionController.isDismissing, !self.sessionController.isTeardownCompleted else { return }
                            await self.qosReporter.sendHeartbeatOnce(overrideState: "playing")
                        }
                    }
                }
            }
            .store(in: &cancellables)

        bindSessionEquatable(engine.$hasFirstFrameReadyForDisplay, to: \.hasFirstFrameReadyForDisplay)
        bindSessionEquatable(engine.$isAwaitingDisplaySwitch, to: \.isAwaitingDisplaySwitch)
        engine.$startupProgress
            .sink { [weak self] progress in
                self?.sessionController.startupState.updateEngineStartupFraction(progress?.fraction)
            }
            .store(in: &cancellables)

        engine.$duration
            .sink { [weak self] dur in
                guard let self, self.trackController.durationSeconds != dur else { return }
                self.trackController.durationSeconds = dur
                self.trackController.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        engine.$mediaChapters
            .sink { [weak self] ch in
                guard let self, self.trackController.engineChapters != ch else { return }
                self.trackController.engineChapters = ch
                self.trackController.rebuildMergedChapters()
            }
            .store(in: &cancellables)

        bindQoSEquatable(engine.$videoFormat, to: \.videoFormat)
        bindQoSEquatable(engine.$sourceDVProfile, to: \.sourceDVProfile)
        bindQoSEquatable(engine.$dolbyVisionConversion, to: \.dolbyVisionConversion)
        bindQoSEquatable(engine.$videoRoute, to: \.videoRoute)
        bindQoSEquatable(engine.$audioDelivery, to: \.audioDelivery)
        bindQoSEquatable(engine.$sourceVideoCodecName, to: \.sourceVideoCodecName)
        bindQoSEquatable(engine.$sourceVideoWidth, to: \.sourceVideoWidth)
        bindQoSEquatable(engine.$sourceVideoHeight, to: \.sourceVideoHeight)
        bindQoSEquatable(engine.$sourceVideoFrameRate, to: \.sourceVideoFrameRate)
        bindQoSEquatable(engine.$activeVideoDecoder, to: \.activeVideoDecoder)
        bindQoSEquatable(engine.$activeAudioDecoder, to: \.activeAudioDecoder)
        bindQoSEquatable(engine.$activeUpscale, to: \.activeUpscale)

        engine.diagnostics.$liveTelemetry
            .sink { [weak self] telemetry in
                self?.qosReporter.ingestDiagnosticsTelemetry(telemetry)
            }
            .store(in: &cancellables)

        engine.$audioTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                if self.trackController.audioTracks != tracks {
                    self.trackController.audioTracks = tracks
                }
                if self.comfort.smartNordicSubtitleRule && !self.sessionController.isSwitchingSource &&
                    !self.trackController.userManuallySelectedSubtitle && !self.trackController.subtitleTracks.isEmpty {
                    self.trackController.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex
            .sink { [weak self] idx in
                guard let self, self.trackController.activeAudioTrackIndex != idx else { return }
                self.trackController.activeAudioTrackIndex = idx
            }
            .store(in: &cancellables)

        engine.$subtitleTracks
            .sink { [weak self] tracks in
                guard let self else { return }
                if self.trackController.subtitleTracks != tracks {
                    self.trackController.subtitleTracks = tracks
                }
                if self.comfort.smartNordicSubtitleRule && !self.sessionController.isSwitchingSource &&
                    !self.trackController.userManuallySelectedSubtitle && !tracks.isEmpty {
                    self.trackController.applySmartSubtitleRule()
                }
            }
            .store(in: &cancellables)
        engine.$activeSubtitleTrackIndex
            .sink { [weak self] idx in
                guard let self, self.trackController.activeSubtitleTrackIndex != idx else { return }
                self.trackController.activeSubtitleTrackIndex = idx
            }
            .store(in: &cancellables)

        engine.$fontAttachments
            .sink { [weak self] attachments in
                guard let self,
                      !self.sessionController.isDismissing,
                      !self.sessionController.isTeardownCompleted else {
                    return
                }
                self.sessionController.embeddedFontRegistry.ingest(attachments: attachments)
            }
            .store(in: &cancellables)

        engine.systemCaptionRequest
            .sink { [weak self] request in
                self?.trackController.handleSystemCaptionRequest(request)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.trackController.handleAudioRouteChange()
                }
            }
            .store(in: &cancellables)
    }
}
