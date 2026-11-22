import SwiftUI
import AetherBridge

internal enum PlayerOSDVisibilityPolicy {
    nonisolated static let playingAutoHideSeconds: TimeInterval = 4.0
    nonisolated static let playingQuickActionsAutoHideSeconds: TimeInterval = 7.0
    nonisolated static let pausedIdleRestSeconds: TimeInterval = 12.0

    nonisolated static func shouldShowBottomBar(
        isPictureReadyForReveal: Bool,
        isQuickPanelOpen: Bool,
        hasFatalError: Bool,
        isScrubbing: Bool,
        showBottomBar: Bool,
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool
    ) -> Bool {
        guard isPictureReadyForReveal, !hasFatalError else {
            return false
        }
        if isQuickPanelOpen || isScrubbing || showBottomBar {
            return true
        }
        return playbackPhase == .paused && !isPausedOSDResting
    }

    nonisolated static func shouldRestAmbientPlayerHUD(
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool,
        isScrubbing: Bool,
        isQuickPanelOpen: Bool
    ) -> Bool {
        playbackPhase == .paused && isPausedOSDResting && !isScrubbing && !isQuickPanelOpen
    }
}

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
    @State private var showBottomBar: Bool = false
    @State private var isPausedOSDResting: Bool = false
    @State private var activeQuickPanel: PlayerQuickPanelTab? = nil
    @State private var lastSelectedQuickTab: PlayerQuickPanelTab = .subtitles
    @State private var quickActionFrames: [PlayerQuickPanelTab: CGRect] = [:]
    @State private var isQuickActionsModeActive: Bool = false
    @State private var bottomBarFocusRequestNonce: Int = 0
    @State private var bottomBarClearFocusNonce: Int = 0
    @State private var requestedBottomBarAction: PlayerBottomBarAction = .panel(.subtitles)
    @State private var hasSeriesPrompt: Bool = false
    @State private var isSeriesPromptFocused: Bool = false
    @State private var seriesPromptDismissNonce: Int = 0
    @State private var seriesPromptFocusNonce: Int = 0
    @State private var dismissedNextForSessionID: String?
    @State private var isAutoHideArmed: Bool = false
    @State private var autoHideNonce: Int = 0
    @State private var isPauseRestArmed: Bool = false
    @State private var pauseRestNonce: Int = 0
    @State private var canvasRestoreNonce: Int = 0
    @State private var suspendedFatalErrorForPanel: String? = nil

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
        viewModel.isPictureReadyForReveal &&
            viewModel.fatalError == nil &&
            activeQuickPanel == nil &&
            !isQuickActionsModeActive
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let effectiveRequest = viewModel.currentRequest ?? initialRequest
        let isQuickPanelOpen = (activeQuickPanel != nil)
        let isBottomBarShown = PlayerOSDVisibilityPolicy.shouldShowBottomBar(
            isPictureReadyForReveal: viewModel.isPictureReadyForReveal,
            isQuickPanelOpen: isQuickPanelOpen,
            hasFatalError: viewModel.fatalError != nil,
            isScrubbing: viewModel.isScrubbing,
            showBottomBar: showBottomBar,
            playbackPhase: viewModel.playbackPhase,
            isPausedOSDResting: isPausedOSDResting
        )
        let isHUDResting = PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
            playbackPhase: viewModel.playbackPhase,
            isPausedOSDResting: isPausedOSDResting,
            isScrubbing: viewModel.isScrubbing,
            isQuickPanelOpen: isQuickPanelOpen
        )

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            // 0. Hardware / Dual-Layer FEL Video Surface (always mounted behind curtain)
            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()
                .zIndex(0)

            if isPreviewMode && viewModel.fatalError == nil {
                previewCinemaStage(
                    client: client,
                    isBottomBarShown: isBottomBarShown,
                    isQuickPanelOpen: isQuickPanelOpen
                )
                .ignoresSafeArea()
                .zIndex(0.5)
            }

            // 1. Leaf-isolated HDR/OLED Subtitle Overlay (never mounted behind fatal error)
            if viewModel.fatalError == nil {
                SubtitleOverlayView(
                    engine: engine,
                    comfort: comfort,
                    isBottomBarVisible: isBottomBarShown,
                    isQuickPanelOpen: isQuickPanelOpen,
                    isNerdHUDVisible: comfort.showNerdHUD
                )
                .opacity(activeQuickPanel == nil || activeQuickPanel == .subtitles ? 1 : 0)
                .ignoresSafeArea()
                .zIndex(1)
            }

            // 1.5 Invisible UIKit Siri Remote Touch & Click Surface (`focusEffect = nil`)
            if shouldEnableCanvasAnchor {
                SiriRemoteTouchSurface(
                    isPlayingProvider: { viewModel.playbackPhase == .playing },
                    durationSecondsProvider: { viewModel.effectiveDurationSeconds },
                    onLightTouch: {
                        if !viewModel.isScrubbing {
                            revealBottomBarTemporarily()
                        }
                    },
                    onScrubBegan: {
                        isAutoHideArmed = false
                        isPauseRestArmed = false
                        withAnimation(.easeOut(duration: 0.16)) {
                            isPausedOSDResting = false
                            showBottomBar = true
                        }
                        viewModel.beginTouchScrub()
                    },
                    onScrubChanged: { deltaSeconds in
                        viewModel.updateTouchScrub(deltaSeconds: deltaSeconds)
                    },
                    onSelectClick: {
                        if viewModel.isScrubbing {
                            viewModel.commitTouchScrub()
                            revealBottomBarTemporarily()
                        } else {
                            viewModel.togglePlayPause()
                            revealBottomBarTemporarily()
                        }
                    },
                    onLeftClick: {
                        if viewModel.isScrubbing {
                            viewModel.stepTouchScrub(by: -10)
                        } else {
                            viewModel.coalesceRelativeSeek(delta: -10)
                            revealBottomBarTemporarily()
                        }
                    },
                    onRightClick: {
                        if viewModel.isScrubbing {
                            viewModel.stepTouchScrub(by: 10)
                        } else {
                            viewModel.coalesceRelativeSeek(delta: 10)
                            revealBottomBarTemporarily()
                        }
                    },
                    onRingHoldBegan: { direction in
                        isAutoHideArmed = false
                        isPauseRestArmed = false
                        withAnimation(.easeOut(duration: 0.16)) {
                            isPausedOSDResting = false
                            showBottomBar = true
                        }
                        viewModel.beginRingHoldScrub(direction: direction)
                    },
                    onRingHoldEnded: { cancelled in
                        viewModel.endRingHoldScrub(cancelled: cancelled)
                        revealBottomBarTemporarily()
                    },
                    onUpClick: {
                        if !viewModel.isScrubbing {
                            if hasSeriesPrompt && !isHUDResting {
                                seriesPromptFocusNonce &+= 1
                            }
                            revealBottomBarTemporarily()
                        }
                    },
                    onDownClick: {
                        if viewModel.isScrubbing {
                            viewModel.commitTouchScrubPaused()
                        }
                        revealBottomBarAndFocusQuickActions(target: .panel(lastSelectedQuickTab))
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
                    isBottomBarVisible: isBottomBarShown,
                    isResting: isHUDResting,
                    hasActivePrompt: $hasSeriesPrompt,
                    isPromptFocused: $isSeriesPromptFocused,
                    dismissedNextForSessionID: $dismissedNextForSessionID,
                    dismissNonce: seriesPromptDismissNonce,
                    focusPromptNonce: seriesPromptFocusNonce,
                    onReturnFocusToCanvas: {
                        revealBottomBarTemporarily()
                        restoreCanvasFocusSoon()
                    },
                    onSilentReturnFocusToCanvas: {
                        restoreCanvasFocusSoon()
                    },
                    onFocusQuickActions: {
                        revealBottomBarAndFocusQuickActions(target: .panel(.subtitles))
                    },
                    onSeekRelative: { delta in
                        viewModel.coalesceRelativeSeek(delta: delta)
                        revealBottomBarTemporarily()
                        restoreCanvasFocusSoon()
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
                        activeQuickPanel: activeQuickPanel,
                        suppressFloatingNextPill: hasSeriesPrompt,
                        focusRequestNonce: bottomBarFocusRequestNonce,
                        clearFocusNonce: bottomBarClearFocusNonce,
                        requestedAction: requestedBottomBarAction,
                        onOpenQuickPanel: { tab in
                            openQuickPanel(tab)
                        },
                        onPlayNextEpisode: { next in
                            viewModel.playNextEpisode(next)
                        },
                        onFocusPresenceChanged: { isFocused in
                            if isFocused && !isQuickActionsModeActive && activeQuickPanel == nil {
                                isQuickActionsModeActive = true
                            }
                        },
                        onUserNavigatedOSD: {
                            if activeQuickPanel == nil {
                                scheduleBottomBarAutoHide()
                            }
                        },
                        onReturnFocusToCanvas: {
                            isQuickActionsModeActive = false
                            revealBottomBarTemporarily()
                            restoreCanvasFocusSoon()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(5)
                }

                if let activeQuickPanel {
                    PlayerQuickPanelView(
                        viewModel: viewModel,
                        comfort: comfort,
                        tab: activeQuickPanel,
                        triggerFrame: quickActionFrames[activeQuickPanel],
                        onClose: { returnFocusToPill in
                            closeQuickPanel(returnFocusToPill: returnFocusToPill)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
                }

                if !isQuickPanelOpen {
                    CoalescedSeekOverlayLeafView(viewModel: viewModel)
                        .zIndex(5.5)
                }

                if let statusToast = activeTopStatusToast {
                    PlayerStatusPill(
                        message: statusToast.message,
                        tone: statusToast.tone,
                        showsSpinner: statusToast.showsSpinner
                    )
                    .transition(.opacity)
                    .zIndex(5.6)
                }
            } else if let activeQuickPanel, viewModel.fatalError == nil {
                // Recovery case: "Velg kilde" opened from fatalErrorOverlay before first frame was revealed
                PlayerQuickPanelView(
                    viewModel: viewModel,
                    comfort: comfort,
                    tab: activeQuickPanel,
                    triggerFrame: quickActionFrames[activeQuickPanel],
                    onClose: { returnFocusToPill in
                        closeQuickPanel(returnFocusToPill: returnFocusToPill)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
            }

            // 7. Fatal Error Recovery Overlay (100% opaque Lampelys card)
            if let err = viewModel.fatalError {
                PlayerFatalErrorOverlayView(
                    message: err,
                    canPickSource: viewModel.activeSession != nil,
                    onRetry: {
                        suspendedFatalErrorForPanel = nil
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
                        suspendedFatalErrorForPanel = err
                        viewModel.fatalError = nil
                        openQuickPanel(.source)
                    },
                    onDismiss: {
                        suspendedFatalErrorForPanel = nil
                        closePlayer()
                    }
                )
                .zIndex(7)
            }
        }
        .coordinateSpace(name: "playerOSD")
        .onPreferenceChange(QuickActionAnchorFramesKey.self) { frames in
            if !frames.isEmpty && frames != quickActionFrames {
                quickActionFrames = frames
            }
        }
        .focusScope(playerFocusNamespace)
        .animation(.easeOut(duration: 0.28), value: viewModel.isPictureReadyForReveal)
        .onChange(of: viewModel.isPictureReadyForReveal) { _, ready in
            if ready && activeQuickPanel == nil && !isQuickActionsModeActive {
                revealBottomBarTemporarily()
                restoreCanvasFocusSoon()
            }
        }
        .onChange(of: shouldEnableCanvasAnchor) { _, enabled in
            if enabled {
                restoreCanvasFocusSoon()
            }
        }
        .onChange(of: viewModel.playbackPhase) { oldPhase, phase in
            if phase == .paused {
                isPausedOSDResting = false
                if activeQuickPanel == nil {
                    schedulePausedIdleRestTimer()
                }
            } else {
                isPauseRestArmed = false
                if isPausedOSDResting {
                    isPausedOSDResting = false
                }
                if oldPhase == .paused && phase == .playing && viewModel.isPictureReadyForReveal && activeQuickPanel == nil {
                    revealBottomBarTemporarily()
                }
            }
            guard phase == .ended,
                  !viewModel.isResolving,
                  !viewModel.isSwitchingSource,
                  !viewModel.isRestoringFromBackground else {
                return
            }
            if let next = viewModel.activeSession?.nextEpisode,
               comfort.autoPlayNextEpisode {
                viewModel.playNextEpisode(next)
            } else {
                closePlayer()
            }
        }
        .onPlayPauseCommand {
            guard !viewModel.isResolving else { return }
            if activeQuickPanel != nil {
                closeQuickPanel(returnFocusToPill: false)
            }
            if viewModel.isScrubbing {
                viewModel.commitTouchScrub()
            } else {
                viewModel.togglePlayPause()
            }
            revealBottomBarTemporarily()
        }
        .onExitCommand {
            if activeQuickPanel != nil {
                closeQuickPanel(returnFocusToPill: true)
            } else if viewModel.isScrubbing {
                viewModel.cancelTouchScrub()
                revealBottomBarTemporarily()
            } else if hasSeriesPrompt && !isHUDResting {
                seriesPromptDismissNonce &+= 1
                restoreCanvasFocusSoon()
            } else if isQuickActionsModeActive {
                clearQuickActionFocusAndHideBarIfPlaying()
            } else if showBottomBar && viewModel.playbackPhase == .playing {
                isAutoHideArmed = false
                withAnimation(.easeOut(duration: 0.2)) {
                    showBottomBar = false
                }
                restoreCanvasFocusSoon()
            } else {
                closePlayer()
            }
        }
        .task(id: isAutoHideArmed ? autoHideNonce : 0) {
            guard isAutoHideArmed, autoHideNonce > 0 else { return }
            let delaySeconds = isQuickActionsModeActive
                ? PlayerOSDVisibilityPolicy.playingQuickActionsAutoHideSeconds
                : PlayerOSDVisibilityPolicy.playingAutoHideSeconds
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .playing && !viewModel.isScrubbing && activeQuickPanel == nil {
                if isQuickActionsModeActive {
                    clearQuickActionFocusAndHideBarIfPlaying()
                } else {
                    withAnimation(.easeOut(duration: 0.28)) {
                        showBottomBar = false
                    }
                }
            }
        }
        .task(id: isPauseRestArmed ? pauseRestNonce : 0) {
            guard isPauseRestArmed, pauseRestNonce > 0 else { return }
            let restNs = UInt64(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: restNs)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && activeQuickPanel == nil {
                isQuickActionsModeActive = false
                bottomBarClearFocusNonce &+= 1
                withAnimation(.easeInOut(duration: 0.65)) {
                    showBottomBar = false
                    isPausedOSDResting = true
                }
                restoreCanvasFocusSoon()
            }
        }
        .task(id: canvasRestoreNonce) {
            guard canvasRestoreNonce > 0 else { return }
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            if shouldEnableCanvasAnchor && !isSeriesPromptFocused && !isQuickActionsModeActive {
                isCanvasFocused = true
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
                    viewModel.isResolving = false
                } else if previewFocusDirection == .up {
                    revealBottomBarAndFocusQuickActions(target: .panel(.subtitles))
                } else if let previewQuickPanel {
                    openQuickPanel(previewQuickPanel)
                } else {
                    revealBottomBarTemporarily()
                }
            } else {
                viewModel.start(request: initialRequest, client: client)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleScenePhaseChange(phase)
        }
        .onChange(of: viewModel.isRestoringFromBackground) { _, restoring in
            if restoring, activeQuickPanel != nil, suspendedFatalErrorForPanel == nil {
                activeQuickPanel = nil
            }
        }
        .onDisappear {
            isAutoHideArmed = false
            isPauseRestArmed = false
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

    private var activeTopStatusToast: (message: String, tone: LunaToastTone, showsSpinner: Bool)? {
        if viewModel.isSwitchingSource {
            return ("Bytter kilde…", .ok, true)
        }
        switch viewModel.playbackPhase {
        case .rebuffering, .stalled:
            return ("Bufrer…", .warn, true)
        default:
            break
        }
        if let banner = viewModel.transientBannerMessage, !banner.isEmpty {
            return (banner, .warn, false)
        }
        if let toast = viewModel.remoteCommandToastMessage, !toast.isEmpty {
            return (toast, .ok, false)
        }
        return nil
    }

    @ViewBuilder
    private func previewCinemaStage(
        client: LunaCoreClient?,
        isBottomBarShown: Bool,
        isQuickPanelOpen: Bool
    ) -> some View {
        let placement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: isBottomBarShown,
            isQuickPanelOpen: isQuickPanelOpen,
            isNerdHUDVisible: comfort.showNerdHUD
        )

        ZStack {
            if let backdropURL = client?.resolveArtworkURL(initialRequest.backdropUrl, target: .hero4K) {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 3840,
                    placeholderSymbol: "film",
                    contentMode: .fill,
                    reuseAnyCachedSize: true
                )
            }
            LinearGradient(
                colors: [
                    LunaTheme.pureBlack.opacity(0.45),
                    Color.clear,
                    LunaTheme.pureBlack.opacity(0.68),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            if activeQuickPanel == nil || activeQuickPanel == .subtitles {
                VStack {
                    if !placement.relocateToTop {
                        Spacer()
                    }
                    Text("Velkommen tilbake til Lumon. Avdelingen venter på dere.")
                        .font(LunaTheme.Font.subtitleCue(size: comfort.subtitleFontSize.pointSize))
                        .foregroundStyle(comfort.hdrSubtitlePreset.foregroundColor(isHDR: true))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.96), radius: 3, x: 0, y: 2)
                        .padding(.horizontal, 120)
                        .padding(.top, placement.relocateToTop ? placement.topInset : 0)
                        .padding(.bottom, placement.relocateToTop ? 0 : placement.bottomInset)
                    if placement.relocateToTop {
                        Spacer()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Focus, Auto-Hide & Quick Panel Coordination

    private func revealBottomBarAndFocusQuickActions(target: PlayerBottomBarAction) {
        isAutoHideArmed = false
        isPauseRestArmed = false
        isPausedOSDResting = false
        isQuickActionsModeActive = true
        requestedBottomBarAction = target
        withAnimation(.easeOut(duration: 0.16)) {
            showBottomBar = true
        }
        bottomBarFocusRequestNonce &+= 1
        scheduleBottomBarAutoHide()
    }

    private func openQuickPanel(_ tab: PlayerQuickPanelTab) {
        isAutoHideArmed = false
        isPauseRestArmed = false
        isPausedOSDResting = false
        isQuickActionsModeActive = false
        lastSelectedQuickTab = tab
        requestedBottomBarAction = .panel(tab)
        bottomBarClearFocusNonce &+= 1
        withAnimation(LunaFocusStyle.focusSpring) {
            showBottomBar = true
            activeQuickPanel = tab
        }
    }

    private func closeQuickPanel(returnFocusToPill: Bool) {
        isQuickActionsModeActive = returnFocusToPill
        withAnimation(.easeOut(duration: 0.18)) {
            activeQuickPanel = nil
        }
        if let suspended = suspendedFatalErrorForPanel {
            suspendedFatalErrorForPanel = nil
            isQuickActionsModeActive = false
            if !viewModel.isSwitchingSource && viewModel.fatalError == nil {
                viewModel.fatalError = suspended
                return
            }
        }
        if returnFocusToPill {
            revealBottomBarAndFocusQuickActions(target: .panel(lastSelectedQuickTab))
        } else {
            bottomBarClearFocusNonce &+= 1
            revealBottomBarTemporarily()
            restoreCanvasFocusSoon()
        }
    }

    private func clearQuickActionFocusAndHideBarIfPlaying() {
        isAutoHideArmed = false
        isQuickActionsModeActive = false
        bottomBarClearFocusNonce &+= 1
        if viewModel.playbackPhase == .playing {
            withAnimation(.easeOut(duration: 0.2)) {
                showBottomBar = false
            }
        }
        restoreCanvasFocusSoon()
    }

    private func revealBottomBarTemporarily() {
        withAnimation(.easeOut(duration: 0.16)) {
            isPausedOSDResting = false
            showBottomBar = true
        }
        scheduleBottomBarAutoHide()
    }

    private func scheduleBottomBarAutoHide() {
        guard activeQuickPanel == nil else {
            isAutoHideArmed = false
            isPauseRestArmed = false
            return
        }
        isAutoHideArmed = true
        autoHideNonce &+= 1
        if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && activeQuickPanel == nil {
            schedulePausedIdleRestTimer()
        }
    }

    private func schedulePausedIdleRestTimer() {
        guard activeQuickPanel == nil else {
            isPauseRestArmed = false
            return
        }
        isPauseRestArmed = true
        pauseRestNonce &+= 1
    }

    private func restoreCanvasFocusSoon() {
        canvasRestoreNonce &+= 1
    }

    private func closePlayer() {
        isAutoHideArmed = false
        isPauseRestArmed = false
        viewModel.prepareForDismissal()
        onDismiss()
    }
}

private struct CoalescedSeekOverlayLeafView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        if abs(viewModel.coalescedSeekDelta) >= 1 && !viewModel.isScrubbing {
            CoalescedSeekFeedbackPillView(deltaSeconds: viewModel.coalescedSeekDelta)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}
