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
    @State private var hideBottomBarTask: Task<Void, Never>?

    @FocusState private var isCanvasFocused: Bool

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
            !isTopDrawerOpen &&
            viewModel.playbackPhase != .paused &&
            !hasSeriesPrompt
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let roomBadge = "\(sessionStore.roomName) · \(sessionStore.activePreset.shortBadgeLabel)"

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            // 0. Hardware / Dual-Layer FEL Video Surface (always mounted behind curtain)
            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()
                .zIndex(0)

            // 1. Leaf-isolated HDR/OLED Subtitle Overlay
            SubtitleOverlayView(engine: engine, comfort: comfort)
                .ignoresSafeArea()
                .zIndex(1)

            // 1.5 Tactile Siri Remote Focus Anchor (active only during clean playback)
            if shouldEnableCanvasAnchor {
                Button {
                    if showBottomBar {
                        hideBottomBarTask?.cancel()
                        withAnimation(.easeOut(duration: 0.22)) {
                            showBottomBar = false
                        }
                    } else {
                        revealBottomBarTemporarily()
                    }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($isCanvasFocused)
                .onMoveCommand { direction in
                    handleCanvasMoveCommand(direction)
                }
                .zIndex(1.5)
            }

            // 2. Opaque Resolving Curtain (locked until hasFirstFrameReadyForDisplay == true)
            if !viewModel.isPictureReadyForReveal && viewModel.fatalError == nil {
                ResolvingCurtainView(
                    viewModel: viewModel,
                    initialRequest: initialRequest,
                    client: client,
                    roomBadgeText: roomBadge,
                    onCancel: closePlayer
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
            if viewModel.isPictureReadyForReveal && !isTopDrawerOpen && viewModel.fatalError == nil {
                SeriesFlowOverlays(
                    viewModel: viewModel,
                    comfort: comfort,
                    client: client,
                    isBottomBarVisible: showBottomBar || viewModel.playbackPhase == .paused,
                    hasActivePrompt: $hasSeriesPrompt,
                    dismissNonce: seriesPromptDismissNonce
                )
                .zIndex(4)
            }

            // 5. Minimalist Bottom Bar + Coalesced Tactile Seek Pill
            if viewModel.isPictureReadyForReveal && !isTopDrawerOpen && viewModel.fatalError == nil {
                if showBottomBar || viewModel.playbackPhase == .paused {
                    PlayerBottomBarView(
                        viewModel: viewModel,
                        fallbackTitle: initialRequest.title,
                        onOpenTopDrawer: { openTopDrawer() },
                        onUserInteraction: { revealBottomBarTemporarily() }
                    )
                    .transition(.opacity)
                    .zIndex(5)
                }

                if abs(viewModel.coalescedSeekDelta) >= 1 {
                    coalescedSeekFeedbackPill
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(5.5)
                }
            }

            // 6. Swipe-Down 4-Tab Liquid Glass Top Drawer
            if isTopDrawerOpen && viewModel.fatalError == nil {
                PlayerTopDrawerView(
                    viewModel: viewModel,
                    comfort: comfort,
                    client: client,
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
        .onPlayPauseCommand {
            guard !viewModel.isResolving else { return }
            if isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.2)) {
                    isTopDrawerOpen = false
                }
            }
            engine.togglePlayPause()
            revealBottomBarTemporarily()
        }
        .onExitCommand {
            if isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.22)) {
                    isTopDrawerOpen = false
                }
                restoreCanvasFocusSoon()
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
            viewModel.teardownAndStop()
        }
    }

    // MARK: - Siri Remote Tactile Gestures

    private func handleCanvasMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .down:
            openTopDrawer()
        case .up:
            revealBottomBarTemporarily()
        case .left:
            viewModel.coalesceRelativeSeek(delta: -10)
            revealBottomBarTemporarily()
        case .right:
            viewModel.coalesceRelativeSeek(delta: 30)
            revealBottomBarTemporarily()
        @unknown default:
            break
        }
    }

    private func openTopDrawer(tab: PlayerTopDrawerTab? = nil) {
        hideBottomBarTask?.cancel()
        if let tab {
            selectedDrawerTab = tab
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
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
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .playing && !isTopDrawerOpen {
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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 8)
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
                        viewModel.start(request: initialRequest, client: sessionStore.makeClient())
                    }

                    if viewModel.activeSession != nil {
                        LunaPillButton("Velg annen kilde", systemImage: "arrow.triangle.2.circlepath", prominence: .glassPill) {
                            viewModel.fatalError = nil
                            openTopDrawer(tab: .sources)
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
