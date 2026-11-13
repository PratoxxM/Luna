import SwiftUI
import AetherBridge

struct PlayerContainerView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let engine: AetherEngine
    @ObservedObject var comfort: ComfortPreferences
    let initialRequest: PlaybackLaunchRequest
    let onDismiss: () -> Void

    @StateObject private var viewModel: PlayerViewModel
    @State private var showBottomBar: Bool = false
    @State private var isTopDrawerOpen: Bool = false
    @State private var selectedDrawerTab: PlayerTopDrawerTab = .subtitles
    @State private var hasSeriesPrompt: Bool = false
    @State private var seriesPromptDismissNonce: Int = 0
    @State private var dismissedNextForSessionID: String?
    @State private var hideBottomBarTask: Task<Void, Never>?

    @FocusState private var isCanvasFocused: Bool
    @Namespace private var playerFocusNamespace

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        initialRequest: PlaybackLaunchRequest,
        onDismiss: @escaping () -> Void
    ) {
        self.engine = engine
        self.comfort = comfort
        self.initialRequest = initialRequest
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PlayerViewModel(engine: engine, comfort: comfort))
    }

    private var shouldEnableCanvasAnchor: Bool {
        viewModel.isPictureReadyForReveal &&
            viewModel.fatalError == nil &&
            !isTopDrawerOpen
    }

    var body: some View {
        let client = sessionStore.makeClient()

        let effectiveRequest = viewModel.currentRequest ?? initialRequest
        let isBottomBarShown = showBottomBar || viewModel.playbackPhase == .paused || viewModel.isScrubbing

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            // 0. Hardware / Dual-Layer FEL Video Surface (always mounted behind curtain)
            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()
                .zIndex(0)

            // 1. Leaf-isolated HDR/OLED Subtitle Overlay
            SubtitleOverlayView(
                engine: engine,
                comfort: comfort,
                isBottomBarVisible: viewModel.isPictureReadyForReveal && !isTopDrawerOpen && viewModel.fatalError == nil && isBottomBarShown
            )
            .ignoresSafeArea()
            .zIndex(1)

            // 1.5 Invisible UIKit Siri Remote Touch & Click Surface (`focusEffect = nil`)
            if shouldEnableCanvasAnchor {
                SiriRemoteTouchSurface(
                    onLightTouch: {
                        if !viewModel.isScrubbing {
                            revealBottomBarTemporarily()
                        }
                    },
                    onScrubBegan: {
                        hideBottomBarTask?.cancel()
                        withAnimation(.easeOut(duration: 0.16)) {
                            showBottomBar = true
                        }
                        viewModel.beginTouchScrub()
                    },
                    onScrubChanged: { deltaPoints, velocityPointsPerSec in
                        viewModel.updateTouchScrub(
                            deltaPoints: deltaPoints,
                            velocityPointsPerSec: velocityPointsPerSec
                        )
                    },
                    onScrubTouchLifted: {
                        // Keep scrub session parked so multi-swipe across a long movie works effortlessly
                    },
                    onSelectClick: {
                        if viewModel.isScrubbing {
                            viewModel.commitTouchScrub()
                            revealBottomBarTemporarily()
                        } else {
                            engine.togglePlayPause()
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
                            viewModel.coalesceRelativeSeek(delta: 30)
                            revealBottomBarTemporarily()
                        }
                    },
                    onUpClick: {
                        if !viewModel.isScrubbing {
                            revealBottomBarTemporarily()
                        }
                    },
                    onDownClick: {
                        if viewModel.isScrubbing {
                            viewModel.cancelTouchScrub()
                        }
                        openTopDrawer()
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

            // 3. Optional 1 Hz Isolated Nerd-HUD (top-left)
            if comfort.showNerdHUD && viewModel.isPictureReadyForReveal && !isTopDrawerOpen {
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

            // 4. Series Continuity Overlays («Hopp over intro» & «Spill neste episode»)
            if viewModel.isPictureReadyForReveal && !isTopDrawerOpen && !viewModel.isScrubbing && viewModel.fatalError == nil {
                SeriesFlowOverlays(
                    viewModel: viewModel,
                    comfort: comfort,
                    client: client,
                    isBottomBarVisible: showBottomBar || viewModel.playbackPhase == .paused,
                    hasActivePrompt: $hasSeriesPrompt,
                    dismissedNextForSessionID: $dismissedNextForSessionID,
                    dismissNonce: seriesPromptDismissNonce,
                    onReturnFocusToCanvas: {
                        revealBottomBarTemporarily()
                        restoreCanvasFocusSoon()
                    },
                    onOpenTopDrawer: {
                        openTopDrawer()
                    },
                    onSeekRelative: { delta in
                        viewModel.coalesceRelativeSeek(delta: delta)
                        revealBottomBarTemporarily()
                        restoreCanvasFocusSoon()
                    }
                )
                .zIndex(4)
            }

            // 5. Minimalist Bottom Bar + Coalesced Tactile Seek Pill
            if viewModel.isPictureReadyForReveal && !isTopDrawerOpen && viewModel.fatalError == nil {
                if isBottomBarShown {
                    PlayerBottomBarView(
                        viewModel: viewModel,
                        fallbackTitle: effectiveRequest.title
                    )
                    .transition(.opacity)
                    .zIndex(5)
                }

                if abs(viewModel.coalescedSeekDelta) >= 1 && !viewModel.isScrubbing {
                    coalescedSeekFeedbackPill
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(5.5)
                }

                if let banner = viewModel.transientBannerMessage {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(LunaTheme.amber)
                            Text(banner)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(LunaTheme.cinemaGlass, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.55), lineWidth: 1))
                        .padding(.top, 42)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(5.6)
                }
            }

            // 6. Swipe-Down 3-Tab Dark Cinema Glass Top Drawer
            if isTopDrawerOpen && viewModel.fatalError == nil {
                PlayerTopDrawerView(
                    viewModel: viewModel,
                    comfort: comfort,
                    selectedTab: $selectedDrawerTab,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.22)) {
                            isTopDrawerOpen = false
                        }
                        restoreCanvasFocusSoon()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
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
            if ready {
                revealBottomBarTemporarily()
                restoreCanvasFocusSoon()
            }
        }
        .onChange(of: shouldEnableCanvasAnchor) { _, enabled in
            if enabled {
                restoreCanvasFocusSoon()
            }
        }
        .onChange(of: viewModel.playbackPhase) { _, phase in
            guard phase == .ended, !viewModel.isResolving, !viewModel.isSwitchingSource else { return }
            if let next = viewModel.activeSession?.nextEpisode,
               comfort.autoPlayNextEpisode,
               dismissedNextForSessionID != viewModel.activeSession?.sessionId {
                viewModel.playNextEpisode(next)
            } else {
                closePlayer()
            }
        }
        .onPlayPauseCommand {
            guard !viewModel.isResolving else { return }
            if isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.2)) {
                    isTopDrawerOpen = false
                }
                restoreCanvasFocusSoon()
            }
            if viewModel.isScrubbing {
                viewModel.commitTouchScrub()
            } else {
                engine.togglePlayPause()
            }
            revealBottomBarTemporarily()
        }
        .onExitCommand {
            if isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.22)) {
                    isTopDrawerOpen = false
                }
                restoreCanvasFocusSoon()
            } else if viewModel.isScrubbing {
                viewModel.cancelTouchScrub()
                revealBottomBarTemporarily()
            } else if hasSeriesPrompt {
                seriesPromptDismissNonce &+= 1
                restoreCanvasFocusSoon()
            } else if showBottomBar && viewModel.playbackPhase == .playing {
                hideBottomBarTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    showBottomBar = false
                }
            } else {
                closePlayer()
            }
        }
        .onAppear {
            viewModel.start(request: initialRequest, client: client)
        }
        .onDisappear {
            hideBottomBarTask?.cancel()
            let store = sessionStore
            viewModel.teardownAndStop {
                store.notifyContentMutated()
            }
        }
    }

    // MARK: - Focus & OSD Timing

    private func openTopDrawer(tab: PlayerTopDrawerTab? = nil) {
        hideBottomBarTask?.cancel()
        if let tab {
            selectedDrawerTab = tab
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
            showBottomBar = false
            isTopDrawerOpen = true
        }
    }

    private func revealBottomBarTemporarily() {
        withAnimation(.easeOut(duration: 0.2)) {
            showBottomBar = true
        }
        hideBottomBarTask?.cancel()
        hideBottomBarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .playing && !viewModel.isScrubbing && !isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.28)) {
                    showBottomBar = false
                }
            }
        }
    }

    private func restoreCanvasFocusSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if shouldEnableCanvasAnchor {
                isCanvasFocused = true
            }
        }
    }

    private func closePlayer() {
        hideBottomBarTask?.cancel()
        let store = sessionStore
        viewModel.teardownAndStop {
            store.notifyContentMutated()
        }
        onDismiss()
    }

    // MARK: - Coalesced Seek Pill & Fatal Error Overlay

    private var coalescedSeekFeedbackPill: some View {
        let secs = Int(viewModel.coalescedSeekDelta.rounded())
        let isForward = secs >= 0
        let sign = isForward ? "+" : ""

        return HStack(spacing: 12) {
            Image(systemName: isForward ? "goforward" : "gobackward")
                .font(.title2.weight(.bold))
                .foregroundStyle(LunaTheme.amber)
            Text("\(sign)\(secs) s")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.65), radius: 20, x: 0, y: 8)
        .allowsHitTesting(false)
    }

    private func fatalErrorOverlay(_ message: String) -> some View {
        ZStack {
            LunaTheme.pureBlack.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(LunaTheme.amber)

                Text("Avspilling kunne ikke starte")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(LunaTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)

                HStack(spacing: 20) {
                    LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .primaryAmber) {
                        let base = viewModel.currentRequest ?? initialRequest
                        let retryRequest = PlaybackLaunchRequest(
                            itemId: base.itemId,
                            title: base.title,
                            seriesTitle: base.seriesTitle,
                            startPositionSeconds: base.startPositionSeconds,
                            candidateId: base.candidateId,
                            prepareToken: nil,
                            backdropUrl: base.backdropUrl,
                            logoUrl: base.logoUrl
                        )
                        viewModel.start(request: retryRequest, client: sessionStore.makeClient())
                    }

                    if viewModel.activeSession != nil {
                        LunaPillButton("Velg annen kilde", systemImage: "arrow.triangle.2.circlepath", prominence: .glassPill) {
                            viewModel.fatalError = nil
                            openTopDrawer(tab: .sourcesAndChapters)
                        }
                    }

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        closePlayer()
                    }
                }
                .padding(.top, 8)
            }
            .padding(60)
        }
    }
}
