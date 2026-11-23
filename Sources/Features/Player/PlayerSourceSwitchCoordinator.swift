import Foundation
import AetherBridge

@MainActor
extension PlayerViewModel {
    // MARK: - Alternatives & Track-Intent-Preserving Edition Switch

    func triggerSourceSwitch(to candidateId: String) {
        guard !isSwitchingSource,
              activeSession?.selectedCandidate.candidateId != candidateId else {
            return
        }
        switchSourceTask?.cancel()
        switchSourceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.switchSource(to: candidateId)
        }
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
        } catch {
            // Keep existing list if already loaded
        }
    }

    func captureCurrentTrackIntent() -> PlaybackTrackIntent {
        let audioDescriptors: [PlaybackAudioTrackDescriptor] = {
            let live = transport.audioTrackDescriptors
            if !live.isEmpty { return live }
            return drawerAudioOptions.map {
                PlaybackAudioTrackDescriptor(
                    id: $0.id,
                    name: $0.rawTitle,
                    codec: $0.codec,
                    language: $0.languageCode,
                    channels: $0.channels,
                    isAtmos: $0.isAtmos,
                    isDTSX: $0.isDTSX,
                    isCommentary: $0.isCommentary
                )
            }
        }()

        let subtitleDescriptors: [SmartTrackDescriptor] = {
            let live = transport.subtitleTrackDescriptors
            if !live.isEmpty { return live }
            return drawerSubtitleOptions.map {
                SmartTrackDescriptor(
                    id: $0.id,
                    name: $0.rawTitle,
                    codec: "srt",
                    language: $0.languageCode,
                    isForced: $0.isForced,
                    isHearingImpaired: $0.isHearingImpaired,
                    isExternal: $0.isExternal
                )
            }
        }()

        return PlaybackTrackIntent.capture(
            audioTracks: audioDescriptors,
            activeAudioTrackID: activeAudioTrackIndex ?? transport.activeAudioTrackIndex,
            subtitleTracks: subtitleDescriptors,
            activeSubtitleTrackID: activeSubtitleTrackIndex ?? transport.activeSubtitleTrackIndex,
            userManuallySelectedSubtitle: userManuallySelectedSubtitle,
            subtitleDelayMs: subtitleDelayMs,
            audioDelayMs: comfort.audioDelayMs
        )
    }

    func applyResolvedTrackIntent(_ intent: PlaybackTrackIntent) {
        let liveAudio = transport.audioTrackDescriptors
        let currentAudioID = transport.activeAudioTrackIndex ?? activeAudioTrackIndex
        let liveSubtitles = transport.subtitleTrackDescriptors

        let resolution = intent.resolve(
            audioTracks: liveAudio,
            currentActiveAudioID: currentAudioID,
            subtitleTracks: liveSubtitles,
            smartNordicRuleEnabled: comfort.smartNordicSubtitleRule
        )

        if let targetAudioID = resolution.selectedAudioTrackID {
            if currentAudioID != targetAudioID {
                transport.selectAudioTrack(index: targetAudioID)
            }
            activeAudioTrackIndex = targetAudioID
        }

        switch resolution.subtitleResolution {
        case .clear:
            transport.clearSubtitle()
            activeSubtitleTrackIndex = nil
        case .select(let targetSubID):
            if (transport.activeSubtitleTrackIndex ?? activeSubtitleTrackIndex) != targetSubID {
                transport.selectSubtitleTrack(index: targetSubID)
            }
            activeSubtitleTrackIndex = targetSubID
        case .keepCurrent:
            activeSubtitleTrackIndex = transport.activeSubtitleTrackIndex ?? activeSubtitleTrackIndex
        }

        userManuallySelectedSubtitle = resolution.preserveManualSubtitleLock
        subtitleDelayMs = intent.subtitleDelayMs
        transport.setSoftwareSubtitleDelay(subtitleDelaySeconds)
    }

    func switchSource(to candidateId: String) async {
        guard let client = activeClient, let session = activeSession else {
            isSwitchingSource = false
            return
        }
        flushPendingAudioDelayCommitIfNeeded()
        let capturedIntent = captureCurrentTrackIntent()
        resetScrubStateOnSessionChange()
        let currentPos = max(0, transport.currentTime)
        isSwitchingSource = true
        resolveStageLabel = "Bytter utgave sømløst på samme tidskode…"
        resolvePercent = 70

        do {
            let updatedSession = try await client.switchCandidate(
                sessionId: session.sessionId,
                candidateId: candidateId,
                positionSeconds: currentPos
            )
            // Freeze current decoded frame via HeldStillPresenter so there is zero black blink
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
            showTransientBanner("Utgavebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }

    func applyServerSwitchedSession(
        _ switchedSession: TvPlaybackSession,
        client: LunaCoreClient,
        fallbackPosition: Double
    ) async {
        guard !isSwitchingSource, !isResolving else { return }
        flushPendingAudioDelayCommitIfNeeded()
        let capturedIntent = captureCurrentTrackIntent()
        resetScrubStateOnSessionChange()
        isSwitchingSource = true
        resolveStageLabel = "Bytter utgave valgt fra iPhone…"
        resolvePercent = 75
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
            showTransientBanner("Utgavebytte feilet: \(LunaCopy.friendlyErrorMessage(error))")
        }
    }

    // MARK: - 15s Pause-Safe VFS Heartbeat & Remote Switch Commands

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
            if let vfs = hb.vfsTelemetry, lastVfsTelemetry != vfs {
                lastVfsTelemetry = vfs
            }
            if let prewarmInfo = hb.nextEpisodePrewarm {
                if let fallbackNext = prewarmInfo.nextEpisode,
                   let cur = activeSession,
                   cur.nextEpisode == nil {
                    activeSession = TvPlaybackSession(
                        sessionId: cur.sessionId,
                        streamToken: cur.streamToken,
                        roomName: cur.roomName,
                        hardwareProfile: cur.hardwareProfile,
                        item: cur.item,
                        selectedCandidate: cur.selectedCandidate,
                        stream: cur.stream,
                        tracks: cur.tracks,
                        chapters: cur.chapters,
                        aetherConfig: cur.aetherConfig,
                        heartbeatIntervalSeconds: cur.heartbeatIntervalSeconds,
                        nextEpisode: fallbackNext
                    )
                }
                if prewarmInfo.canClientPrewarmBytes == true,
                   let relPath = prewarmInfo.streamUrl,
                   let streamURL = client.buildAbsoluteURL(relPath),
                   prewarmedNextEpisodeURL != streamURL {
                    prewarmedNextEpisodeURL = streamURL
                    prewarmedNextEpisodeItemId = prewarmInfo.itemId ?? prewarmInfo.nextEpisode?.itemId ?? activeSession?.nextEpisode?.itemId
                    prewarmedNextEpisodeSessionId = prewarmInfo.sessionId
                    if let tok = prewarmInfo.streamToken, tok.count >= 8 {
                        if let oldTok = prewarmedNextEpisodeStreamToken, oldTok.count >= 8, oldTok != tok {
                            EngineLog.unregisterSecret(oldTok)
                        }
                        _ = EngineLog.registerSecret(tok)
                        prewarmedNextEpisodeStreamToken = tok
                    }
                    if DeviceHardwareCapabilities.availableMemoryBytes() > 512 * 1024 * 1024 {
                        let headers = client.streamHTTPHeaders(for: streamURL)
                        nextEpisodePrewarmTask?.cancel()
                        nextEpisodePrewarmTask = Task.detached(priority: .utility) {
                            guard !Task.isCancelled else { return }
                            if !AetherEngine.isPrewarmed(url: streamURL) {
                                _ = await AetherEngine.prewarm(
                                    url: streamURL,
                                    httpHeaders: headers,
                                    byteBudget: 8 * 1024 * 1024
                                )
                            }
                        }
                    }
                }
            }
            if overrideState == nil,
               !isResolving,
               !isSwitchingSource,
               let cmd = hb.pendingCommand {
                await handleHeartbeatPendingCommand(cmd, client: client, currentPosition: pos)
            }
        } catch LunaCoreError.unauthorized {
            onUnauthorized?()
        } catch let LunaCoreError.serverMessage(statusCode, _) where statusCode == 410 || statusCode == 404 {
            heartbeatTask?.cancel()
            heartbeatTask = nil
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
            showRemoteCommandToast("Byttet utgave fra iPhone")
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
}
