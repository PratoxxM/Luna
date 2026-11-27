import Foundation
import AetherBridge

extension PlayerTrackController {
    var hasNorwegianAudioTrack: Bool {
        let descriptors = effectiveAudioDescriptors()
        guard !descriptors.isEmpty else { return false }
        return OriginalLanguageTrackSelector.containsNorwegianTrack(in: descriptors)
    }

    func togglePreferNorwegianAudio() {
        let next = !preferNorwegianAudio
        preferNorwegianAudio = next
        if let itemId = host?.sessionController.activeSession?.item.itemId ?? host?.sessionController.currentRequest?.itemId {
            preferenceStore.setPreferNorwegianAudio(next, forItemId: itemId)
        }
        let descriptors = effectiveAudioDescriptors()
        if let picked = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: descriptors,
            originalLanguage: host?.sessionController.activeSession?.item.originalLanguage,
            preferNorwegianAudio: next
        ) {
            userManuallySelectedSubtitle = false
            activeAudioTrackIndex = picked.id
            if previewAudioOptions.isEmpty {
                transport.selectAudioTrack(index: picked.id)
            }
            applySmartSubtitleRule()
        }
    }

    func searchAndAttachSubtitles() {
        let priorHDRTask = takeAndCancelPendingHDRSwitchTask()
        let priorUpscaleTask = takeAndCancelPendingUpscaleReloadTask()
        let priorSubtitleTask = takeAndCancelPendingSubtitleActionTask(clearBusyFlags: false)
        let expectedGeneration = subtitleActionGeneration
        subtitleActionTask = Task { @MainActor [weak self] in
            await priorHDRTask?.value
            await priorUpscaleTask?.value
            await priorSubtitleTask?.value
            guard !Task.isCancelled, let self, self.subtitleActionGeneration == expectedGeneration else { return }
            if priorSubtitleTask != nil {
                self.isSearchingSubtitles = false
                self.isAutoAligningSubtitles = false
            }
            _ = await self.performSearchAndAttachSubtitles(expectedGeneration: expectedGeneration)
            if self.subtitleActionGeneration == expectedGeneration {
                self.subtitleActionTask = nil
            }
        }
    }

    @discardableResult
    func performSearchAndAttachSubtitles(expectedGeneration: UInt64? = nil) async -> Bool {
        guard !Task.isCancelled,
              expectedGeneration == nil || subtitleActionGeneration == expectedGeneration,
              let host,
              let client = host.sessionController.activeClient,
              let session = host.sessionController.activeSession,
              !isSearchingSubtitles,
              !isAutoAligningSubtitles else {
            return false
        }
        isSearchingSubtitles = true
        subtitleActionStatusMessage = LunaCopy.searchingSubtitlesTitle
        defer {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                isSearchingSubtitles = false
                subtitleActionTask = nil
            }
        }

        do {
            let langs = PlaybackSubtitleSyncActionPolicy.preferredSearchLanguages(
                originalLanguage: session.item.originalLanguage
            )
            let res = try await client.searchAndAttachSubtitles(
                sessionId: session.sessionId,
                languages: langs,
                forced: false,
                cleanSdh: true
            )
            try Task.checkCancellation()
            guard expectedGeneration == nil || subtitleActionGeneration == expectedGeneration else {
                return false
            }
            let mergedExternals = PlaybackSubtitleSyncActionPolicy.mergedExternalSubtitles(
                existing: session.tracks?.externalSubtitles ?? [],
                response: res
            )
            guard res.attached || !mergedExternals.isEmpty else {
                subtitleActionStatusMessage = LunaCopy.noSubtitlesFoundStatus
                return false
            }
            let updatedSession = updatingSessionTracks(
                session,
                externalSubtitles: mergedExternals,
                subtitleDelayMs: res.subtitleDelayMs ?? session.subtitleDelayMs
            )
            host.sessionController.activeSession = updatedSession
            if let delayMs = res.subtitleDelayMs {
                applyAndPersistSubtitleDelayMs(delayMs)
            }
            try await reloadExternalSubtitlesInPlace(session: updatedSession, client: client)
            try Task.checkCancellation()
            guard expectedGeneration == nil || subtitleActionGeneration == expectedGeneration else {
                return false
            }
            if !engine.subtitleTracks.isEmpty { subtitleTracks = engine.subtitleTracks }
            let descriptors = effectiveSubtitleDescriptors()
            let targetID = SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "nob", in: descriptors)
                ?? descriptors.last(where: { $0.isExternal })?.id
                ?? descriptors.last?.id
            if let targetID {
                selectSubtitleManually(targetID)
            }
            subtitleActionStatusMessage = LunaCopy.subtitleAttachedStatus
            return true
        } catch where LunaCoreError.isCancellation(error) || Task.isCancelled {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                subtitleActionStatusMessage = nil
            }
            return false
        } catch {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                subtitleActionStatusMessage = LunaCopy.friendlyErrorMessage(error, fallback: LunaCopy.noSubtitlesFoundStatus)
            }
            return false
        }
    }

    func autoAlignActiveSubtitle() {
        let priorHDRTask = takeAndCancelPendingHDRSwitchTask()
        let priorUpscaleTask = takeAndCancelPendingUpscaleReloadTask()
        let priorSubtitleTask = takeAndCancelPendingSubtitleActionTask(clearBusyFlags: false)
        let expectedGeneration = subtitleActionGeneration
        subtitleActionTask = Task { @MainActor [weak self] in
            await priorHDRTask?.value
            await priorUpscaleTask?.value
            await priorSubtitleTask?.value
            guard !Task.isCancelled, let self, self.subtitleActionGeneration == expectedGeneration else { return }
            if priorSubtitleTask != nil {
                self.isSearchingSubtitles = false
                self.isAutoAligningSubtitles = false
            }
            _ = await self.performAutoAlignActiveSubtitle(expectedGeneration: expectedGeneration)
            if self.subtitleActionGeneration == expectedGeneration {
                self.subtitleActionTask = nil
            }
        }
    }

    @discardableResult
    func performAutoAlignActiveSubtitle(expectedGeneration: UInt64? = nil) async -> Bool {
        guard !Task.isCancelled,
              expectedGeneration == nil || subtitleActionGeneration == expectedGeneration,
              let host,
              let client = host.sessionController.activeClient,
              let session = host.sessionController.activeSession,
              !isAutoAligningSubtitles,
              !isSearchingSubtitles else {
            return false
        }
        let descriptors = effectiveSubtitleDescriptors()
        let activeSubID = activeSubtitleTrackIndex ?? transport.activeSubtitleTrackIndex
        let activeSub = descriptors.first(where: { $0.id == activeSubID })
        let matchedExt = PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(
            for: activeSub,
            in: session.tracks?.externalSubtitles ?? []
        )
        let resolvedTrackIndex: Int? = matchedExt != nil
            ? activeSub?.id
            : PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(
                for: activeSub,
                embeddedSubtitles: session.tracks?.embeddedSubtitles ?? [],
                allDescriptors: descriptors
            )
        isAutoAligningSubtitles = true
        subtitleActionStatusMessage = LunaCopy.autoAligningSubtitlesTitle
        defer {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                isAutoAligningSubtitles = false
                subtitleActionTask = nil
            }
        }

        do {
            let res = try await client.autoAlignSubtitles(
                sessionId: session.sessionId,
                subtitleId: matchedExt?.id,
                trackIndex: resolvedTrackIndex,
                language: activeSub?.language,
                subtitleDelayMs: nil,
                applyToFile: matchedExt != nil
            )
            try Task.checkCancellation()
            guard expectedGeneration == nil || subtitleActionGeneration == expectedGeneration else {
                return false
            }
            guard res.applied else {
                subtitleActionStatusMessage = PlaybackSubtitleSyncActionPolicy.friendlyAlignReasonMessage(res.reason)
                return false
            }
            applyAndPersistSubtitleDelayMs(res.subtitleDelayMs)
            if let updatedSub = res.subtitle, res.appliedToFile != false {
                let merged = PlaybackSubtitleSyncActionPolicy.mergedAlignedSubtitle(
                    existing: session.tracks?.externalSubtitles ?? [],
                    updated: updatedSub
                )
                let updatedSession = updatingSessionTracks(
                    session,
                    externalSubtitles: merged,
                    subtitleDelayMs: res.subtitleDelayMs
                )
                host.sessionController.activeSession = updatedSession
                try await reloadExternalSubtitlesInPlace(session: updatedSession, client: client)
                try Task.checkCancellation()
                guard expectedGeneration == nil || subtitleActionGeneration == expectedGeneration else {
                    return false
                }
            }
            let formattedOffset = PlaybackSyncTimingPolicy.formatSignedDelayMs(subtitleDelayMs)
            subtitleActionStatusMessage = "\(LunaCopy.subtitlesAlignedStatus) · \(formattedOffset)"
            return true
        } catch where LunaCoreError.isCancellation(error) || Task.isCancelled {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                subtitleActionStatusMessage = nil
            }
            return false
        } catch {
            if expectedGeneration == nil || subtitleActionGeneration == expectedGeneration {
                subtitleActionStatusMessage = LunaCopy.friendlyErrorMessage(error, fallback: LunaCopy.subtitlesAlignFailedStatus)
            }
            return false
        }
    }

    func switchToHDR10BaseLayer() {
        if hdrBaseLayerPreSwitchOverride == nil {
            hdrBaseLayerPreSwitchOverride = comfort.dualLayerOverride
        }
        if comfort.dualLayerOverride != .forceOff {
            comfort.dualLayerOverride = .forceOff
        }
        let priorUpscaleTask = takeAndCancelPendingUpscaleReloadTask()
        let priorSubtitleTask = takeAndCancelPendingSubtitleActionTask(clearBusyFlags: true)
        let priorHDRTask = takeAndCancelPendingHDRSwitchTask(clearPreSwitchOverride: false)
        let expectedGeneration = hdrBaseLayerSwitchGeneration
        hdrBaseLayerSwitchTask = Task { @MainActor [weak self] in
            await priorUpscaleTask?.value
            await priorHDRTask?.value
            await priorSubtitleTask?.value
            guard !Task.isCancelled, let self, self.hdrBaseLayerSwitchGeneration == expectedGeneration else { return }
            await self.performSwitchToHDR10BaseLayer(expectedGeneration: expectedGeneration)
        }
    }

    func performSwitchToHDR10BaseLayer(expectedGeneration: UInt64? = nil) async {
        let fallbackPrevious = comfort.dualLayerOverride
        let previousOverride = hdrBaseLayerPreSwitchOverride ?? fallbackPrevious
        if comfort.dualLayerOverride != .forceOff {
            comfort.dualLayerOverride = .forceOff
        }
        defer {
            if expectedGeneration == nil || hdrBaseLayerSwitchGeneration == expectedGeneration {
                hdrBaseLayerPreSwitchOverride = nil
                hdrBaseLayerSwitchTask = nil
            }
        }
        guard let host,
              !host.sessionController.isResolving,
              !host.sessionController.isSwitchingSource,
              !host.sessionController.isDismissing,
              !host.sessionController.isTeardownCompleted else {
            return
        }
        let session = host.sessionController.activeSession
        let client = host.sessionController.activeClient
        let snapshot = PlayerEngineConfigurator.captureReloadComfortSnapshot(
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: effectiveAudioDelaySecondsForActiveRoute(),
            binauralAudioActive: isBinauralAudioRouteActive,
            session: session
        )
        let extSubs: [ExternalSubtitleTrack]? = (session != nil && client != nil)
            ? PlayerEngineConfigurator.externalSubtitleTracks(for: session!, client: client!)
            : nil

        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10
        do {
            try await transport.reloadAtCurrentPosition { options in
                PlayerEngineConfigurator.applyRestoreDisplayAndUpscaleOptions(snapshot, session: session, to: &options)
                if let extSubs { options.externalSubtitles = extSubs }
            }
            guard !Task.isCancelled,
                  expectedGeneration == nil || hdrBaseLayerSwitchGeneration == expectedGeneration else {
                return
            }
            host.qosReporter.resetDolbyVisionFallback()
            if subtitleDelayMs != 0 {
                transport.setSoftwareSubtitleDelay(self.subtitleDelaySeconds)
            }
            host.qosReporter.showTransientBanner(LunaCopy.switchToHDR10BaseLayerTitle)
        } catch where LunaCoreError.isCancellation(error) || Task.isCancelled {
            if expectedGeneration == nil || hdrBaseLayerSwitchGeneration == expectedGeneration {
                comfort.dualLayerOverride = previousOverride
            }
            return
        } catch {
            if expectedGeneration == nil || hdrBaseLayerSwitchGeneration == expectedGeneration {
                comfort.dualLayerOverride = previousOverride
            }
            guard !Task.isCancelled,
                  expectedGeneration == nil || hdrBaseLayerSwitchGeneration == expectedGeneration else {
                return
            }
            host.qosReporter.showTransientBanner(
                PlayerEngineConfigurator.friendlyEngineFailure(
                    error,
                    engineErrorInfo: engine.errorInfo,
                    fallback: "Kunne ikke bytte til HDR10-baselag."
                )
            )
        }
    }

    private func reloadExternalSubtitlesInPlace(session: TvPlaybackSession, client: LunaCoreClient) async throws {
        let extTracks = PlayerEngineConfigurator.externalSubtitleTracks(for: session, client: client)
        let snapshot = PlayerEngineConfigurator.captureReloadComfortSnapshot(
            comfort: comfort,
            audioEnhancement: audioEnhancement,
            audioDelaySeconds: effectiveAudioDelaySecondsForActiveRoute(),
            binauralAudioActive: isBinauralAudioRouteActive,
            session: session
        )

        engine.maximumSubtitleAdvanceSeconds = 0
        engine.maximumSubtitleDelaySeconds = 10
        try await transport.reloadAtCurrentPosition { options in
            options.externalSubtitles = extTracks
            PlayerEngineConfigurator.applyRestoreDisplayAndUpscaleOptions(snapshot, session: session, to: &options)
        }
        try Task.checkCancellation()
        if subtitleDelayMs != 0 {
            transport.setSoftwareSubtitleDelay(self.subtitleDelaySeconds)
        }
    }

    private func updatingSessionTracks(
        _ session: TvPlaybackSession,
        externalSubtitles: [TvExternalSubtitle],
        subtitleDelayMs: Int?
    ) -> TvPlaybackSession {
        let updatedTracks = TvSessionTracks(
            probeConfidence: session.tracks?.probeConfidence,
            video: session.tracks?.video,
            audio: session.tracks?.audio,
            embeddedSubtitles: session.tracks?.embeddedSubtitles,
            externalSubtitles: externalSubtitles,
            chapters: session.tracks?.chapters,
            subtitleDelayMs: subtitleDelayMs ?? session.tracks?.subtitleDelayMs
        )
        return TvPlaybackSession(
            sessionId: session.sessionId,
            streamToken: session.streamToken,
            roomName: session.roomName,
            hardwareProfile: session.hardwareProfile,
            item: session.item,
            selectedCandidate: session.selectedCandidate,
            stream: session.stream,
            tracks: updatedTracks,
            chapters: session.chapters,
            subtitleDelayMs: subtitleDelayMs ?? session.subtitleDelayMs,
            aetherConfig: session.aetherConfig,
            heartbeatIntervalSeconds: session.heartbeatIntervalSeconds,
            nextEpisode: session.nextEpisode
        )
    }

    func effectiveAudioDescriptors() -> [PlaybackAudioTrackDescriptor] {
        let live = transport.audioTrackDescriptors
        if !live.isEmpty { return live }
        return drawerAudioOptions.map {
            PlaybackAudioTrackDescriptor(
                id: $0.id, name: $0.rawTitle, codec: $0.codec, language: $0.languageCode,
                channels: $0.channels, isAtmos: $0.isAtmos, isDTSX: $0.isDTSX, isCommentary: $0.isCommentary
            )
        }
    }

    func effectiveSubtitleDescriptors() -> [SmartTrackDescriptor] {
        let live = transport.subtitleTrackDescriptors
        if !live.isEmpty { return live }
        return drawerSubtitleOptions.map {
            SmartTrackDescriptor(
                id: $0.id, name: $0.rawTitle, codec: "srt", language: $0.languageCode,
                isForced: $0.isForced, isHearingImpaired: $0.isHearingImpaired, isExternal: $0.isExternal
            )
        }
    }

    func captureCurrentTrackIntent() -> PlaybackTrackIntent {
        PlaybackTrackIntent.capture(
            audioTracks: effectiveAudioDescriptors(),
            activeAudioTrackID: activeAudioTrackIndex ?? transport.activeAudioTrackIndex,
            subtitleTracks: effectiveSubtitleDescriptors(),
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
            audioTracks: liveAudio, currentActiveAudioID: currentAudioID,
            subtitleTracks: liveSubtitles, smartNordicRuleEnabled: comfort.smartNordicSubtitleRule
        )
        if let targetAudioID = resolution.selectedAudioTrackID {
            if currentAudioID != targetAudioID { transport.selectAudioTrack(index: targetAudioID) }
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
}
