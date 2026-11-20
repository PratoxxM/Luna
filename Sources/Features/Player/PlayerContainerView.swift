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
    private enum FatalErrorAction: Hashable {
        case retry
        case pickSource
        case dismiss
    }

    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase

    let engine: AetherEngine
    @ObservedObject var comfort: ComfortPreferences
    let initialRequest: PlaybackLaunchRequest
    let isPreviewMode: Bool
    let previewFocusDirection: PreviewFocusDirection?
    let previewQuickPanel: PlayerQuickPanelTab?
    let previewFatalError: String?
    let onDismiss: () -> Void

    @StateObject private var viewModel: PlayerViewModel
    @State private var showBottomBar: Bool = false
    @State private var isPausedOSDResting: Bool = false
    @State private var activeQuickPanel: PlayerQuickPanelTab? = nil
    @State private var lastSelectedQuickTab: PlayerQuickPanelTab = .subtitles
    @State private var isQuickActionsModeActive: Bool = false
    @State private var bottomBarFocusRequestNonce: Int = 0
    @State private var bottomBarClearFocusNonce: Int = 0
    @State private var requestedBottomBarAction: PlayerBottomBarAction = .panel(.subtitles)
    @State private var hasSeriesPrompt: Bool = false
    @State private var isSeriesPromptFocused: Bool = false
    @State private var seriesPromptDismissNonce: Int = 0
    @State private var seriesPromptFocusNonce: Int = 0
    @State private var dismissedNextForSessionID: String?
    @State private var hideBottomBarTask: Task<Void, Never>?
    @State private var pauseRestTask: Task<Void, Never>?
    @State private var suspendedFatalErrorForPanel: String? = nil

    @FocusState private var isCanvasFocused: Bool
    @FocusState private var focusedFatalErrorButton: FatalErrorAction?
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
        _viewModel = StateObject(wrappedValue: PlayerViewModel(engine: engine, comfort: comfort))
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

            if isPreviewMode {
                previewCinemaStage(client: client, isBottomBarShown: isBottomBarShown)
                    .ignoresSafeArea()
                    .zIndex(0.5)
            }

            // 1. Leaf-isolated HDR/OLED Subtitle Overlay
            SubtitleOverlayView(
                engine: engine,
                comfort: comfort,
                isBottomBarVisible: isBottomBarShown
            )
            .ignoresSafeArea()
            .zIndex(1)

            // 1.5 Invisible UIKit Siri Remote Touch & Click Surface (`focusEffect = nil`)
            if shouldEnableCanvasAnchor {
                SiriRemoteTouchSurface(
                    isPlayingProvider: { viewModel.playbackPhase == .playing },
                    onLightTouch: {
                        if !viewModel.isScrubbing {
                            revealBottomBarTemporarily()
                        }
                    },
                    onScrubBegan: {
                        hideBottomBarTask?.cancel()
                        pauseRestTask?.cancel()
                        withAnimation(.easeOut(duration: 0.16)) {
                            isPausedOSDResting = false
                            showBottomBar = true
                        }
                        viewModel.beginTouchScrub()
                    },
                    onScrubChanged: { deltaSeconds in
                        viewModel.updateTouchScrub(deltaSeconds: deltaSeconds)
                    },
                    onScrubTouchLifted: {
                        // Keep scrub session parked so multi-swipe across a long movie works effortlessly
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
                            viewModel.cancelTouchScrub()
                        }
                        revealBottomBarAndFocusQuickActions(target: .panel(.subtitles))
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

            // 5. Classic Bottom OSD + Quick Actions + Floating Vertical Quick-List + Coalesced Seek Pill
            if viewModel.isPictureReadyForReveal && viewModel.fatalError == nil {
                if isBottomBarShown {
                    PlayerBottomBarView(
                        viewModel: viewModel,
                        fallbackRequest: effectiveRequest,
                        activeQuickPanel: activeQuickPanel,
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
                        onClose: { returnFocusToPill in
                            closeQuickPanel(returnFocusToPill: returnFocusToPill)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
                }

                if abs(viewModel.coalescedSeekDelta) >= 1 && !viewModel.isScrubbing && !isQuickPanelOpen {
                    coalescedSeekFeedbackPill
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(5.5)
                }

                if let banner = viewModel.transientBannerMessage {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(LunaTheme.Font.pillIcon)
                                .foregroundStyle(LunaTheme.warn)
                            Text(banner)
                                .font(LunaTheme.Font.subtitle)
                                .foregroundStyle(LunaTheme.linen)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(LunaTheme.cinemaGlass, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warn.opacity(0.50), lineWidth: 1))
                        .padding(.top, 42)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(5.6)
                }

                if let toast = viewModel.remoteCommandToastMessage {
                    VStack {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(LunaTheme.emerald)
                                .frame(width: 8, height: 8)
                            Text(toast)
                                .font(LunaTheme.Font.pillLabel)
                                .foregroundStyle(LunaTheme.linen)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(LunaTheme.cinemaGlass, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1))
                        .padding(.top, viewModel.transientBannerMessage == nil ? 42 : 102)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(5.7)
                }
            } else if let activeQuickPanel, viewModel.fatalError == nil {
                // Recovery case: "Velg kilde" opened from fatalErrorOverlay before first frame was revealed
                PlayerQuickPanelView(
                    viewModel: viewModel,
                    comfort: comfort,
                    tab: activeQuickPanel,
                    onClose: { returnFocusToPill in
                        closeQuickPanel(returnFocusToPill: returnFocusToPill)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
            }

            // 7. Fatal Error Recovery Overlay
            if let err = viewModel.fatalError {
                fatalErrorOverlay(err)
                    .zIndex(7)
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
                pauseRestTask?.cancel()
                pauseRestTask = nil
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
                hideBottomBarTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    showBottomBar = false
                }
                restoreCanvasFocusSoon()
            } else {
                closePlayer()
            }
        }
        .onAppear {
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
                    focusedFatalErrorButton = .retry
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
            hideBottomBarTask?.cancel()
            pauseRestTask?.cancel()
            guard !isPreviewMode else { return }
            let store = sessionStore
            viewModel.teardownAndStop {
                store.notifyContentMutated()
            }
        }
    }

    @ViewBuilder
    private func previewCinemaStage(client: LunaCoreClient?, isBottomBarShown: Bool) -> some View {
        ZStack {
            if let backdropURL = client?.resolveArtworkURL(initialRequest.backdropUrl) {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 960,
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
            VStack {
                Spacer()
                Text("Velkommen tilbake til Lumon. Avdelingen venter på dere.")
                    .font(LunaTheme.Font.subtitleCue(size: comfort.subtitleFontSize.pointSize))
                    .foregroundStyle(comfort.hdrSubtitlePreset.foregroundColor(isHDR: true))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.96), radius: 3, x: 0, y: 2)
                    .padding(.horizontal, 120)
                    .padding(.bottom, isBottomBarShown ? 290 : 80)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Focus, Auto-Hide & Quick Panel Coordination

    private func revealBottomBarAndFocusQuickActions(target: PlayerBottomBarAction) {
        hideBottomBarTask?.cancel()
        pauseRestTask?.cancel()
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
        hideBottomBarTask?.cancel()
        pauseRestTask?.cancel()
        isPausedOSDResting = false
        isQuickActionsModeActive = false
        lastSelectedQuickTab = tab
        requestedBottomBarAction = .panel(tab)
        bottomBarClearFocusNonce &+= 1
        withAnimation(LunaFocusStyle.focusSpring) {
            showBottomBar = true
            activeQuickPanel = tab
        }
        if tab == .source,
           viewModel.alternativesSessionId != viewModel.activeSession?.sessionId || viewModel.alternatives.isEmpty {
            Task { await viewModel.loadAlternatives() }
        }
    }

    private func closeQuickPanel(returnFocusToPill: Bool) {
        if returnFocusToPill {
            isQuickActionsModeActive = true
        } else {
            isQuickActionsModeActive = false
        }
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
        hideBottomBarTask?.cancel()
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
        hideBottomBarTask?.cancel()
        guard activeQuickPanel == nil else {
            pauseRestTask?.cancel()
            return
        }
        let delaySeconds = isQuickActionsModeActive
            ? PlayerOSDVisibilityPolicy.playingQuickActionsAutoHideSeconds
            : PlayerOSDVisibilityPolicy.playingAutoHideSeconds
        let autoHideNs = UInt64(delaySeconds * 1_000_000_000)
        hideBottomBarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoHideNs)
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
        if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && activeQuickPanel == nil {
            schedulePausedIdleRestTimer()
        }
    }

    private func schedulePausedIdleRestTimer() {
        pauseRestTask?.cancel()
        guard activeQuickPanel == nil else { return }
        let restNs = UInt64(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds * 1_000_000_000)
        pauseRestTask = Task { @MainActor in
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
    }

    private func restoreCanvasFocusSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if shouldEnableCanvasAnchor && !isSeriesPromptFocused && !isQuickActionsModeActive {
                isCanvasFocused = true
            }
        }
    }

    private func closePlayer() {
        hideBottomBarTask?.cancel()
        pauseRestTask?.cancel()
        viewModel.prepareForDismissal()
        onDismiss()
    }

    // MARK: - Coalesced Seek Pill & Fatal Error Overlay

    private var coalescedSeekFeedbackPill: some View {
        let secs = Int(viewModel.coalescedSeekDelta.rounded())
        let isForward = secs >= 0
        let displayText = isForward ? "+\(secs) s" : "−\(abs(secs)) s"

        return HStack(spacing: 12) {
            Image(systemName: isForward ? "goforward" : "gobackward")
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.moonlight)
            Text(displayText)
                .font(LunaTheme.Font.sectionTitle.monospacedDigit())
                .foregroundStyle(LunaTheme.linen)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func fatalErrorOverlay(_ message: String) -> some View {
        ZStack {
            LunaTheme.pureBlack.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(LunaTheme.Font.largeStatusIcon)
                    .foregroundStyle(LunaTheme.danger)

                Text("Avspilling kunne ikke starte")
                    .font(LunaTheme.Font.pageTitle)
                    .foregroundStyle(LunaTheme.linen)

                Text(message)
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)

                HStack(spacing: 20) {
                    LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .glassPill) {
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
                    }
                    .focused($focusedFatalErrorButton, equals: .retry)

                    if viewModel.activeSession != nil {
                        LunaPillButton("Velg kilde", systemImage: "arrow.triangle.2.circlepath", prominence: .glassPill) {
                            suspendedFatalErrorForPanel = message
                            viewModel.fatalError = nil
                            openQuickPanel(.source)
                        }
                        .focused($focusedFatalErrorButton, equals: .pickSource)
                    }

                    LunaPillButton("Avslutt", systemImage: "xmark", prominence: .subtleChip) {
                        suspendedFatalErrorForPanel = nil
                        closePlayer()
                    }
                    .focused($focusedFatalErrorButton, equals: .dismiss)
                }
                .padding(.top, 8)
            }
            .padding(60)
        }
        .onAppear {
            focusedFatalErrorButton = .retry
        }
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 24_000_000)
            guard !Task.isCancelled else { return }
            if focusedFatalErrorButton == nil {
                focusedFatalErrorButton = .retry
            }
        }
    }
}
