import SwiftUI
import AetherBridge

struct PlayerContainerView: View {
    @Environment(AppSessionStore.self) var sessionStore
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let engine: AetherEngine
    let comfort: ComfortPreferences
    let initialRequest: PlaybackLaunchRequest
    let isPreviewMode: Bool
    let previewScreenTarget: PreviewScreenTarget?
    let previewFocusDirection: PreviewFocusDirection?
    let previewQuickPanel: PlayerQuickPanelTab?
    let previewFatalError: String?
    let onDismiss: () -> Void

    @State var viewModel: PlayerViewModel
    @State var osd = PlayerOSDCoordinator()

    @FocusState var isCanvasFocused: Bool
    @Namespace var playerFocusNamespace

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        initialRequest: PlaybackLaunchRequest,
        isPreviewMode: Bool = false,
        previewScreenTarget: PreviewScreenTarget? = nil,
        previewFocusDirection: PreviewFocusDirection? = nil,
        previewQuickPanel: PlayerQuickPanelTab? = nil,
        previewFatalError: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.engine = engine
        self.comfort = comfort
        self.initialRequest = initialRequest
        self.isPreviewMode = isPreviewMode
        self.previewScreenTarget = previewScreenTarget
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

    var shouldEnableCanvasAnchor: Bool {
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
        let panelTransition: AnyTransition = reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)

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
                    activeSeriesOverlay: effectiveSeriesOverlay,
                    isScrubbing: viewModel.isScrubbing
                )
                .ignoresSafeArea()
                .zIndex(0.5)
            }

            // 1. Leaf-isolated Lampelys Subtitle Overlay
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
                    activeSeriesOverlay: effectiveSeriesOverlay,
                    isScrubbing: viewModel.isScrubbing
                )
                .ignoresSafeArea()
                .zIndex(1)
            }

            // 1.5 Invisible UIKit Siri Remote Touch & Click Surface (`focusEffect = nil`)
            if shouldEnableCanvasAnchor {
                touchSurfaceLayer(isHUDResting: isHUDResting)
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
                .padding(.top, LunaTokens.Layout.safeTop)
                .transition(.opacity)
                .zIndex(3)
            }

            // 4. Series Continuity Overlays
            if viewModel.isPictureReadyForReveal && !isQuickPanelOpen && !viewModel.isScrubbing && viewModel.fatalError == nil {
                seriesFlowLayer(
                    client: client,
                    isBottomBarShown: isBottomBarShown,
                    isHUDResting: isHUDResting,
                    isQuickPanelOpen: isQuickPanelOpen,
                    statusToast: statusToast
                )
            }

            // 5. Classic Bottom OSD + Quick Actions + Floating Button-Anchored Popover + Status Pill
            if viewModel.isPictureReadyForReveal && viewModel.fatalError == nil {
                bottomOverlayLayer(
                    effectiveRequest: effectiveRequest,
                    isBottomBarShown: isBottomBarShown,
                    isQuickPanelOpen: isQuickPanelOpen,
                    statusToast: statusToast,
                    panelTransition: panelTransition
                )
            } else if let activeQuickPanel = osd.activeQuickPanel, viewModel.fatalError == nil {
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
                .transition(panelTransition)
                .zIndex(6)
            }

            // 7. Fatal Error Recovery Overlay
            if let err = viewModel.fatalError {
                fatalErrorLayer(err: err, effectiveRequest: effectiveRequest, client: client)
            }
        }
        .coordinateSpace(name: "playerOSD")
        .onPreferenceChange(QuickActionAnchorFramesKey.self) { frames in
            if !frames.isEmpty && frames != osd.quickActionFrames {
                osd.quickActionFrames = frames
            }
        }
        .focusScope(playerFocusNamespace)
        .animation(LunaFocusStyle.calmEaseOut(duration: 0.28, reduceMotion: reduceMotion), value: viewModel.isPictureReadyForReveal)
        .onChange(of: viewModel.isPictureReadyForReveal) { _, ready in
            if !isPreviewMode && ready && osd.activeQuickPanel == nil && !osd.isQuickActionsModeActive {
                osd.revealBottomBarTemporarily(viewModel: viewModel)
                osd.restoreCanvasFocusSoon()
            }
        }
        .onChange(of: shouldEnableCanvasAnchor) { _, enabled in
            if !isPreviewMode && enabled {
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
        .onPlayPauseCommand { osd.handlePlayPauseCommand(viewModel: viewModel) }
        .onExitCommand { osd.handleExitCommand(viewModel: viewModel) { closePlayer() } }
        .task(id: osd.isAutoHideArmed ? osd.autoHideNonce : 0) {
            await runAutoHideTask()
        }
        .task(id: osd.isPauseRestArmed ? osd.pauseRestNonce : 0) {
            await runPauseRestTask()
        }
        .task(id: osd.canvasRestoreNonce) {
            await runCanvasFocusRestoreTask()
        }
        .onAppear { configureOnAppear(client: client) }
        .onChange(of: scenePhase) { _, phase in viewModel.handleScenePhaseChange(phase) }
        .onChange(of: viewModel.isRestoringFromBackground) { _, restoring in
            if restoring, osd.activeQuickPanel != nil, osd.suspendedFatalErrorForPanel == nil {
                viewModel.flushPendingAudioDelayCommitIfNeeded()
                osd.activeQuickPanel = nil
            }
        }
        .onDisappear { handleDisappear() }
    }
}
