import SwiftUI
import AetherBridge

struct PlayerContainerView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.scenePhase) private var scenePhase

    let engine: AetherEngine
    let comfort: ComfortPreferences
    let initialRequest: PlaybackLaunchRequest
    let isPreviewMode: Bool
    let previewFocusDirection: PreviewFocusDirection?
    let previewQuickPanel: PlayerQuickPanelTab?
    let previewFatalError: String?
    let onDismiss: () -> Void

    @State private var viewModel: PlayerViewModel
    @State private var osd = PlayerOSDCoordinator()

    @FocusState private var isCanvasFocused: Bool
    @Namespace private var playerFocusNamespace

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        initialRequest: PlaybackLaunchRequest,
        isPreviewMode: Bool = false,
        previewFocusDirection: PreviewFocusDirection? = nil,
        previewQuickPanel: PlayerQuickPanelTab? = nil,
        previewFatalError: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.engine = engine
        self.comfort = comfort
        self.initialRequest = initialRequest
        self.isPreviewMode = isPreviewMode
        self.previewFocusDirection = previewFocusDirection
        self.previewQuickPanel = previewQuickPanel
        self.previewFatalError = previewFatalError
        self.onDismiss = onDismiss
        _viewModel = State(
            initialValue: PlayerViewModel(
                engine: engine,
                comfort: comfort,
                bindOnInit: false
            )
        )
    }

    private var shouldEnableCanvasAnchor: Bool {
        osd.shouldEnableCanvasAnchor(viewModel: viewModel)
    }

    var body: some View {
        @Bindable var osd = osd
        let client = sessionStore.makeClient()
        let effectiveRequest = viewModel.currentRequest ?? initialRequest
        let isQuickPanelOpen = (osd.activeQuickPanel != nil)
        let isBottomBarShown = osd.isBottomBarShown(viewModel: viewModel)
        let isHUDResting = osd.isHUDResting(viewModel: viewModel)
        let statusToast = osd.activeTopStatusToast(viewModel: viewModel)
        let effectiveSeriesOverlay: ActiveSeriesOverlayKind =
            (viewModel.isPictureReadyForReveal && !isQuickPanelOpen && !viewModel.isScrubbing && viewModel.fatalError == nil)
            ? osd.activeSeriesOverlay
            : .none

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            // 0. Hardware / Dual-Layer FEL Video Surface (always mounted behind curtain)
            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()
                .zIndex(0)

            if isPreviewMode && viewModel.fatalError == nil {
                PlayerPreviewCinemaStageView(
                    client: client,
                    backdropPath: initialRequest.backdropUrl,
                    comfort: comfort,
                    activeQuickPanel: osd.activeQuickPanel,
                    isBottomBarShown: isBottomBarShown,
                    isQuickPanelOpen: isQuickPanelOpen,
                    activeSeriesOverlay: effectiveSeriesOverlay
                )
                .ignoresSafeArea()
                .zIndex(0.5)
            }

            // 1. Leaf-isolated Lampelys Subtitle Overlay (visible across all quick-panel tabs, relocated to top)
            if PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                hasFatalError: viewModel.fatalError != nil,
                hasSuspendedFatalError: osd.suspendedFatalErrorForPanel != nil,
                isPictureReadyForReveal: viewModel.isPictureReadyForReveal,
                isPreviewMode: isPreviewMode
            ) {
                SubtitleOverlayView(
                    engine: engine,
                    comfort: comfort,
                    subtitleDelaySeconds: viewModel.subtitleDelaySeconds,
                    isBottomBarVisible: isBottomBarShown,
                    isQuickPanelOpen: isQuickPanelOpen,
                    isNerdHUDVisible: comfort.showNerdHUD,
                    activeSeriesOverlay: effectiveSeriesOverlay
                )
                .ignoresSafeArea()
                .zIndex(1)
            }

            // 1.5 Invisible UIKit Siri Remote Touch & Click Surface (`focusEffect = nil`)
            if shouldEnableCanvasAnchor {
                SiriRemoteTouchSurface(
                    isPlayingProvider: { viewModel.playbackPhase == .playing },
                    durationSecondsProvider: { viewModel.effectiveDurationSeconds },
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

            // 2. Opaque Resolving Curtain (locked until hasFirstFrameReadyForDisplay == true)
            if !viewModel.isPictureReadyForReveal && viewModel.fatalError == nil {
                ResolvingCurtainView(
                    viewModel: viewModel,
                    initialRequest: effectiveRequest,
                    client: client
                )
                .transition(.opacity)
                .zIndex(2)
            }

            // 3. Optional 1 Hz Isolated Nerd-HUD (top-left, also dims during 12s OLED pause rest)
            if comfort.showNerdHUD && viewModel.isPictureReadyForReveal && !isHUDResting {
                VStack {
                    HStack {
                        NerdHUDView(engine: engine, viewModel: viewModel)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 42)
                .transition(.opacity)
                .zIndex(3)
            }

            // 4. Series Continuity Overlays («Hopp over intro» & «Neste episode»)
            if viewModel.isPictureReadyForReveal && !isQuickPanelOpen && !viewModel.isScrubbing && viewModel.fatalError == nil {
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

            // 5. Classic Bottom OSD + Quick Actions + Floating Button-Anchored Popover + Coalesced Seek Pill
            if viewModel.isPictureReadyForReveal && viewModel.fatalError == nil {
                if isBottomBarShown {
                    PlayerBottomBarView(
                        viewModel: viewModel,
                        fallbackRequest: effectiveRequest,
                        activeQuickPanel: osd.activeQuickPanel,
                        suppressFloatingNextPill: osd.hasSeriesPrompt,
                        focusRequestNonce: osd.bottomBarFocusRequestNonce,
                        clearFocusNonce: osd.bottomBarClearFocusNonce,
                        requestedAction: osd.requestedBottomBarAction,
                        onOpenQuickPanel: { tab in
                            osd.openQuickPanel(tab)
                        },
                        onPlayNextEpisode: { next in
                            viewModel.playNextEpisode(next)
                        },
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            } else if let activeQuickPanel = osd.activeQuickPanel, viewModel.fatalError == nil {
                // Recovery case: "Velg utgave" opened from fatalErrorOverlay before first frame was revealed
                PlayerQuickPanelView(
                    viewModel: viewModel,
                    comfort: comfort,
                    tab: activeQuickPanel,
                    triggerFrame: osd.quickActionFrames[activeQuickPanel],
                    canSwitchTabs: false,
                    onClose: { returnFocusToPill in
                        osd.closeQuickPanel(viewModel: viewModel, returnFocusToPill: returnFocusToPill)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
            }

            // 7. Fatal Error Recovery Overlay (reuses PlayerCurtainBackdropView before first frame)
            if let err = viewModel.fatalError {
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
        }
        .coordinateSpace(name: "playerOSD")
        .onPreferenceChange(QuickActionAnchorFramesKey.self) { frames in
            if !frames.isEmpty && frames != osd.quickActionFrames {
                osd.quickActionFrames = frames
            }
        }
        .focusScope(playerFocusNamespace)
        .animation(.easeOut(duration: 0.28), value: viewModel.isPictureReadyForReveal)
        .onChange(of: viewModel.isPictureReadyForReveal) { _, ready in
            if ready && osd.activeQuickPanel == nil && !osd.isQuickActionsModeActive {
                osd.revealBottomBarTemporarily(viewModel: viewModel)
                osd.restoreCanvasFocusSoon()
            }
        }
        .onChange(of: shouldEnableCanvasAnchor) { _, enabled in
            if enabled {
                osd.restoreCanvasFocusSoon()
            }
        }
        .onChange(of: viewModel.playbackPhase) { oldPhase, phase in
            osd.handlePlaybackPhaseChange(
                oldPhase: oldPhase,
                newPhase: phase,
                viewModel: viewModel,
                autoPlayNextEpisode: comfort.autoPlayNextEpisode,
                onClosePlayer: { closePlayer() }
            )
        }
        .onPlayPauseCommand {
            osd.handlePlayPauseCommand(viewModel: viewModel)
        }
        .onExitCommand {
            osd.handleExitCommand(viewModel: viewModel) {
                closePlayer()
            }
        }
        .task(id: osd.isAutoHideArmed ? osd.autoHideNonce : 0) {
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
                    withAnimation(.easeOut(duration: 0.28)) {
                        osd.showBottomBar = false
                    }
                }
            }
        }
        .task(id: osd.isPauseRestArmed ? osd.pauseRestNonce : 0) {
            guard osd.isPauseRestArmed, osd.pauseRestNonce > 0 else { return }
            let restNs = UInt64(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: restNs)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && osd.activeQuickPanel == nil {
                osd.enterPausedIdleRest()
            }
        }
        .task(id: osd.canvasRestoreNonce) {
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
                if isCanvasFocused {
                    return
                }
            }
        }
        .onAppear {
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
                viewModel.configurePreviewPlayback(
                    request: initialRequest,
                    session: PreviewMockFixtures.playerSession,
                    client: client
                )
                if let previewFatalError {
                    viewModel.fatalError = previewFatalError
                    viewModel.hasFirstFrameReadyForDisplay = false
                    viewModel.isResolving = false
                } else if previewFocusDirection == .up {
                    osd.revealBottomBarAndFocusQuickActions(
                        target: .panel(.subtitles),
                        viewModel: viewModel
                    )
                } else if let previewQuickPanel {
                    osd.openQuickPanel(previewQuickPanel)
                } else {
                    osd.revealBottomBarTemporarily(viewModel: viewModel)
                }
            } else {
                viewModel.start(request: initialRequest, client: client)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleScenePhaseChange(phase)
        }
        .onChange(of: viewModel.isRestoringFromBackground) { _, restoring in
            if restoring, osd.activeQuickPanel != nil, osd.suspendedFatalErrorForPanel == nil {
                viewModel.flushPendingAudioDelayCommitIfNeeded()
                osd.activeQuickPanel = nil
            }
        }
        .onDisappear {
            osd.disarmAllTimers()
            guard !isPreviewMode else { return }
            let store = sessionStore
            let invalidatedItemId = viewModel.activeSession?.item.itemId ?? initialRequest.itemId
            let invalidatedTmdbId = viewModel.activeSession?.item.ids.tmdb ?? initialRequest.preparedSession?.item.ids.tmdb
            ItemDetailMemoryCache.invalidate(itemId: invalidatedItemId, tmdbId: invalidatedTmdbId)
            viewModel.teardownAndStop {
                ItemDetailMemoryCache.invalidate(itemId: invalidatedItemId, tmdbId: invalidatedTmdbId)
                store.notifyContentMutated()
            }
        }
    }

    private func closePlayer() {
        osd.disarmAllTimers()
        viewModel.prepareForDismissal()
        onDismiss()
    }
}
