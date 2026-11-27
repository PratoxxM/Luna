import SwiftUI
import AetherBridge

extension PlayerContainerView {
    @ViewBuilder
    func touchSurfaceLayer(isHUDResting: Bool) -> some View {
        SiriRemoteTouchSurface(
            isPlayingProvider: { viewModel.playbackPhase == .playing && viewModel.transport.state != .paused },
            isScrubbingProvider: { viewModel.isScrubbing },
            canLockHorizontalFocusProvider: {
                !osd.isSeriesPromptFocused && !osd.isQuickActionsModeActive && osd.activeQuickPanel == nil
            },
            durationSecondsProvider: { viewModel.effectiveDurationSeconds },
            focusRequestNonce: osd.canvasRestoreNonce,
            cancelHoldNonce: osd.ringHoldCancelNonce,
            onLightTouch: {
                if !viewModel.isScrubbing {
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                }
            },
            onScrubBegan: {
                osd.beginInteractiveScrub()
                viewModel.beginTouchScrub()
            },
            onScrubChanged: { deltaSeconds in
                viewModel.updateTouchScrub(deltaSeconds: deltaSeconds)
            },
            onSelectClick: {
                if viewModel.isScrubbing {
                    viewModel.commitTouchScrub()
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                } else {
                    viewModel.togglePlayPause()
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                }
            },
            onLeftClick: {
                if viewModel.isScrubbing {
                    viewModel.stepTouchScrub(by: -10)
                } else {
                    viewModel.coalesceRelativeSeek(delta: -10)
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                }
            },
            onRightClick: {
                if viewModel.isScrubbing {
                    viewModel.stepTouchScrub(by: 10)
                } else {
                    viewModel.coalesceRelativeSeek(delta: 10)
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                }
            },
            onRingHoldBegan: { direction in
                osd.beginInteractiveScrub()
                viewModel.beginRingHoldScrub(direction: direction)
            },
            onRingHoldEnded: { cancelled in
                viewModel.endRingHoldScrub(cancelled: cancelled)
                osd.revealBottomBarTemporarily(viewModel: viewModel)
            },
            onUpClick: {
                if !viewModel.isScrubbing {
                    if osd.hasSeriesPrompt && !isHUDResting {
                        osd.seriesPromptFocusNonce &+= 1
                    } else {
                        osd.revealBottomBarTemporarily(viewModel: viewModel)
                    }
                }
            },
            onDownClick: {
                if viewModel.isScrubbing {
                    viewModel.commitTouchScrubPaused()
                }
                osd.revealBottomBarAndFocusQuickActions(
                    target: .panel(osd.lastSelectedQuickTab),
                    viewModel: viewModel
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .focusEffectDisabled()
        .focused($isCanvasFocused)
        .prefersDefaultFocus(true, in: playerFocusNamespace)
        .zIndex(1.5)
    }

    @ViewBuilder
    func seriesFlowLayer(
        client: LunaCoreClient?,
        isBottomBarShown: Bool,
        isHUDResting: Bool,
        isQuickPanelOpen: Bool,
        statusToast: (message: String, tone: LunaToastTone, showsSpinner: Bool)?
    ) -> some View {
        @Bindable var osd = osd
        SeriesFlowOverlays(
            viewModel: viewModel,
            client: client,
            isBottomBarVisible: isBottomBarShown,
            isResting: isHUDResting,
            isQuickPanelOpen: isQuickPanelOpen,
            isQuickActionsModeActive: osd.isQuickActionsModeActive,
            hasTopStatusToast: statusToast != nil,
            activeOverlayKind: $osd.activeSeriesOverlay,
            hasActivePrompt: $osd.hasSeriesPrompt,
            isPromptFocused: $osd.isSeriesPromptFocused,
            dismissedNextForSessionID: $osd.dismissedNextForSessionID,
            dismissNonce: osd.seriesPromptDismissNonce,
            focusPromptNonce: osd.seriesPromptFocusNonce,
            onReturnFocusToCanvas: {
                osd.revealBottomBarTemporarily(viewModel: viewModel)
                osd.restoreCanvasFocusSoon()
            },
            onSilentReturnFocusToCanvas: {
                osd.restoreCanvasFocusSoon()
            },
            onFocusQuickActions: {
                osd.revealBottomBarAndFocusQuickActions(
                    target: .panel(.subtitles),
                    viewModel: viewModel
                )
            },
            onSeekRelative: { delta in
                viewModel.coalesceRelativeSeek(delta: delta)
                osd.revealBottomBarTemporarily(viewModel: viewModel)
                osd.restoreCanvasFocusSoon()
            }
        )
        .zIndex(4)
    }

    @ViewBuilder
    func bottomOverlayLayer(
        effectiveRequest: PlaybackLaunchRequest,
        isBottomBarShown: Bool,
        isQuickPanelOpen: Bool,
        statusToast: (message: String, tone: LunaToastTone, showsSpinner: Bool)?,
        panelTransition: AnyTransition
    ) -> some View {
        if isBottomBarShown {
            PlayerBottomBarView(
                viewModel: viewModel,
                fallbackRequest: effectiveRequest,
                activeQuickPanel: osd.activeQuickPanel,
                isQuickActionsModeActive: osd.isQuickActionsModeActive,
                suppressFloatingNextPill: osd.hasSeriesPrompt,
                focusRequestNonce: osd.bottomBarFocusRequestNonce,
                clearFocusNonce: osd.bottomBarClearFocusNonce,
                requestedAction: osd.requestedBottomBarAction,
                onOpenQuickPanel: { tab in osd.openQuickPanel(tab) },
                onPlayNextEpisode: { next in viewModel.playNextEpisode(next) },
                onFocusPresenceChanged: { isFocused in
                    if isFocused && !osd.isQuickActionsModeActive && osd.activeQuickPanel == nil {
                        osd.isQuickActionsModeActive = true
                    }
                },
                onUserNavigatedOSD: {
                    if osd.activeQuickPanel == nil {
                        osd.scheduleBottomBarAutoHide(viewModel: viewModel)
                    }
                },
                onReturnFocusToCanvas: {
                    osd.isQuickActionsModeActive = false
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                    osd.restoreCanvasFocusSoon()
                }
            )
            .transition(.opacity)
            .zIndex(5)
        }

        if let activeQuickPanel = osd.activeQuickPanel {
            PlayerQuickPanelView(
                viewModel: viewModel,
                comfort: comfort,
                tab: activeQuickPanel,
                triggerFrame: osd.quickActionFrames[activeQuickPanel],
                canSwitchTabs: osd.suspendedFatalErrorForPanel == nil,
                onSwitchTab: { direction in
                    osd.switchQuickPanelTab(
                        direction: direction,
                        hasChapters: !viewModel.chapters.isEmpty
                    )
                },
                onClose: { returnFocusToPill in
                    osd.closeQuickPanel(viewModel: viewModel, returnFocusToPill: returnFocusToPill)
                }
            )
            .transition(panelTransition)
            .zIndex(6)
        }

        if !isQuickPanelOpen {
            CoalescedSeekOverlayLeafView(viewModel: viewModel)
                .zIndex(5.5)
        }

        if let statusToast {
            PlayerStatusPill(
                message: statusToast.message,
                tone: statusToast.tone,
                showsSpinner: statusToast.showsSpinner
            )
            .transition(.opacity)
            .zIndex(5.6)
        }
    }

    @ViewBuilder
    func fatalErrorLayer(
        err: String,
        effectiveRequest: PlaybackLaunchRequest,
        client: LunaCoreClient?
    ) -> some View {
        PlayerFatalErrorOverlayView(
            message: err,
            canPickSource: viewModel.activeSession != nil,
            showsCurtainBackdrop: !viewModel.isPictureReadyForReveal,
            backdropURL: PlayerCurtainBackdropView.resolveBackdropURL(
                request: effectiveRequest,
                session: viewModel.activeSession,
                client: client
            ),
            client: client,
            onRetry: {
                osd.suspendedFatalErrorForPanel = nil
                let base = viewModel.currentRequest ?? initialRequest
                let retryRequest = PlaybackLaunchRequest(
                    itemId: base.itemId,
                    title: base.title,
                    seriesTitle: base.seriesTitle,
                    season: base.season,
                    episode: base.episode,
                    startPositionSeconds: base.startPositionSeconds,
                    candidateId: base.candidateId,
                    prepareToken: nil,
                    backdropUrl: base.backdropUrl,
                    logoUrl: base.logoUrl
                )
                viewModel.start(request: retryRequest, client: sessionStore.makeClient())
            },
            onPickSource: {
                osd.suspendedFatalErrorForPanel = err
                viewModel.fatalError = nil
                osd.openQuickPanel(.source)
            },
            onDismiss: {
                osd.suspendedFatalErrorForPanel = nil
                closePlayer()
            }
        )
        .zIndex(7)
    }

    func runAutoHideTask() async {
        guard osd.isAutoHideArmed, osd.autoHideNonce > 0 else { return }
        let delaySeconds = osd.isQuickActionsModeActive
            ? PlayerOSDVisibilityPolicy.playingQuickActionsAutoHideSeconds
            : PlayerOSDVisibilityPolicy.playingAutoHideSeconds
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        if viewModel.playbackPhase == .playing && !viewModel.isScrubbing && osd.activeQuickPanel == nil {
            if osd.isQuickActionsModeActive {
                osd.clearQuickActionFocusAndHideBarIfPlaying(viewModel: viewModel)
            } else {
                let anim = LunaFocusStyle.calmEaseOut(duration: 0.28, reduceMotion: reduceMotion)
                withAnimation(anim) { osd.showBottomBar = false }
            }
        }
    }

    func runPauseRestTask() async {
        guard osd.isPauseRestArmed, osd.pauseRestNonce > 0 else { return }
        let restNs = UInt64(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: restNs)
        guard !Task.isCancelled else { return }
        if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && osd.activeQuickPanel == nil {
            osd.enterPausedIdleRest()
        }
    }

    func runCanvasFocusRestoreTask() async {
        guard osd.canvasRestoreNonce > 0 else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        if shouldEnableCanvasAnchor && !osd.isSeriesPromptFocused && !osd.isQuickActionsModeActive && !isCanvasFocused {
            isCanvasFocused = true
        }
        if isCanvasFocused { return }
        for delayNs: UInt64 in [16_000_000, 48_000_000, 110_000_000] {
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            if shouldEnableCanvasAnchor && !osd.isSeriesPromptFocused && !osd.isQuickActionsModeActive && !isCanvasFocused {
                isCanvasFocused = true
            }
            if isCanvasFocused { return }
        }
    }

    func configureOnAppear(client: LunaCoreClient?) {
        viewModel.bindEnginePublishersIfNeeded()
        let store = sessionStore
        let vm = viewModel
        viewModel.onUnauthorized = { [weak vm] in
            vm?.prepareForDismissal()
            store.unpairDevice()
            onDismiss()
        }
        viewModel.updateInitialScenePhase(scenePhase)
        if isPreviewMode {
            configurePreviewState(client: client)
        } else {
            viewModel.start(request: initialRequest, client: client)
        }
    }

    private func configurePreviewState(client: LunaCoreClient?) {
        let targetScreen = previewScreenTarget ?? .playerSubtitles
        viewModel.configurePreviewPlayback(
            request: initialRequest,
            session: PreviewMockFixtures.playerSession(for: targetScreen),
            client: client
        )
        if let previewFatalError {
            viewModel.fatalError = previewFatalError
            viewModel.hasFirstFrameReadyForDisplay = false
            viewModel.isResolving = false
        } else if targetScreen == .playerCurtain {
            viewModel.sessionController.isResolving = true
            viewModel.sessionController.hasFirstFrameReadyForDisplay = false
            viewModel.sessionController.isAwaitingDisplaySwitch = false
            viewModel.sessionController.firstFrameFallbackUnlocked = false
            viewModel.sessionController.startupState.resolveStageLabel = "Klargjør Dolby Vision P7 FEL…"
            viewModel.sessionController.startupState.resolvePercent = 68
            viewModel.sessionController.startupState.resolveHeadline = "FraMeSToR · 4K Remux · På NVMe"
            osd.showBottomBar = false
        } else if targetScreen == .playerScrub {
            osd.beginInteractiveScrub()
            viewModel.configurePreviewScrub(
                originSeconds: 1122,
                targetSeconds: 2145,
                previewImage: PreviewMockURLProtocol.makeScrubPreviewImage()
            )
        } else if targetScreen == .playerSkipIntro {
            viewModel.playbackPhase = .playing
            viewModel.previewPlayheadOverrideSeconds = 68
            osd.showBottomBar = false
        } else if targetScreen == .playerNextEpisode {
            viewModel.playbackPhase = .playing
            viewModel.previewPlayheadOverrideSeconds = 3158
            osd.showBottomBar = false
        } else if previewFocusDirection == .up {
            osd.revealBottomBarAndFocusQuickActions(target: .panel(.subtitles), viewModel: viewModel)
        } else if let previewQuickPanel {
            osd.openQuickPanel(previewQuickPanel)
        } else {
            osd.revealBottomBarAndFocusQuickActions(target: .panel(.subtitles), viewModel: viewModel)
        }
        osd.disarmAllTimers()
    }

    func handleDisappear() {
        osd.disarmAllTimers()
        guard !isPreviewMode else { return }
        let store = sessionStore
        let invalidatedItemId = viewModel.activeSession?.item.itemId ?? initialRequest.itemId
        let invalidatedTmdbId = viewModel.activeSession?.item.ids.tmdb ?? initialRequest.preparedSession?.item.ids.tmdb
        let hadActiveSession = viewModel.activeSession != nil
        ItemDetailMemoryCache.invalidate(itemId: invalidatedItemId, tmdbId: invalidatedTmdbId)
        viewModel.teardownAndStop(
            onComplete: {
                if hadActiveSession {
                    ItemDetailMemoryCache.invalidate(itemId: invalidatedItemId, tmdbId: invalidatedTmdbId)
                }
                store.notifyContentMutated()
            },
            onStopReceipt: { receipt in
                store.recordPlaybackStopReceipt(receipt)
            }
        )
    }

    func closePlayer() {
        osd.disarmAllTimers()
        viewModel.prepareForDismissal()
        onDismiss()
    }
}
