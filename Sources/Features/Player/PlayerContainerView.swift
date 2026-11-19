import SwiftUI
import AetherBridge

internal enum PlayerOSDVisibilityPolicy {
    nonisolated static let playingAutoHideSeconds: TimeInterval = 4.0
    nonisolated static let pausedIdleRestSeconds: TimeInterval = 12.0

    nonisolated static func shouldShowBottomBar(
        isPictureReadyForReveal: Bool,
        isTopDrawerOpen: Bool,
        hasFatalError: Bool,
        isScrubbing: Bool,
        showBottomBar: Bool,
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool
    ) -> Bool {
        guard isPictureReadyForReveal, !isTopDrawerOpen, !hasFatalError else {
            return false
        }
        if isScrubbing || showBottomBar {
            return true
        }
        return playbackPhase == .paused && !isPausedOSDResting
    }

    nonisolated static func shouldRestAmbientPlayerHUD(
        playbackPhase: PlaybackPhase,
        isPausedOSDResting: Bool,
        isScrubbing: Bool,
        isTopDrawerOpen: Bool
    ) -> Bool {
        playbackPhase == .paused && isPausedOSDResting && !isScrubbing && !isTopDrawerOpen
    }
}

struct PlayerContainerView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase

    let engine: AetherEngine
    @ObservedObject var comfort: ComfortPreferences
    let initialRequest: PlaybackLaunchRequest
    let onDismiss: () -> Void

    @StateObject private var viewModel: PlayerViewModel
    @State private var showBottomBar: Bool = false
    @State private var isPausedOSDResting: Bool = false
    @State private var isTopDrawerOpen: Bool = false
    @State private var selectedDrawerTab: PlayerTopDrawerTab = .audioAndSubtitles
    @State private var hasSeriesPrompt: Bool = false
    @State private var seriesPromptDismissNonce: Int = 0
    @State private var dismissedNextForSessionID: String?
    @State private var hideBottomBarTask: Task<Void, Never>?
    @State private var pauseRestTask: Task<Void, Never>?
    @State private var suspendedFatalErrorForDrawer: String? = nil

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
        let isBottomBarShown = PlayerOSDVisibilityPolicy.shouldShowBottomBar(
            isPictureReadyForReveal: viewModel.isPictureReadyForReveal,
            isTopDrawerOpen: isTopDrawerOpen,
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
            isTopDrawerOpen: isTopDrawerOpen
        )

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
                isBottomBarVisible: isBottomBarShown
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
                        pauseRestTask?.cancel()
                        withAnimation(.easeOut(duration: 0.16)) {
                            isPausedOSDResting = false
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

            // 3. Optional 1 Hz Isolated Nerd-HUD (top-left, also dims during 12s OLED pause rest)
            if comfort.showNerdHUD && viewModel.isPictureReadyForReveal && !isTopDrawerOpen && !isHUDResting {
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
            if viewModel.isPictureReadyForReveal && !isTopDrawerOpen && !viewModel.isScrubbing && viewModel.fatalError == nil {
                SeriesFlowOverlays(
                    viewModel: viewModel,
                    isBottomBarVisible: isBottomBarShown,
                    isResting: isHUDResting,
                    hasActivePrompt: $hasSeriesPrompt,
                    dismissedNextForSessionID: $dismissedNextForSessionID,
                    dismissNonce: seriesPromptDismissNonce,
                    onReturnFocusToCanvas: {
                        revealBottomBarTemporarily()
                        restoreCanvasFocusSoon()
                    },
                    onSilentReturnFocusToCanvas: {
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
                        fallbackRequest: effectiveRequest
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
                                .foregroundStyle(LunaTheme.warn)
                            Text(banner)
                                .font(.callout.weight(.semibold))
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
                                .fill(LunaTheme.amber)
                                .frame(width: 8, height: 8)
                                .shadow(color: LunaTheme.amber.opacity(0.75), radius: 6, x: 0, y: 0)
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
            }

            // 6. Swipe-Down 4-Tab Dark Cinema Glass Top Drawer
            if isTopDrawerOpen && viewModel.fatalError == nil {
                PlayerTopDrawerView(
                    viewModel: viewModel,
                    comfort: comfort,
                    selectedTab: $selectedDrawerTab,
                    onClose: closeTopDrawer
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
        .onChange(of: viewModel.playbackPhase) { oldPhase, phase in
            if phase == .paused {
                isPausedOSDResting = false
                schedulePausedIdleRestTimer()
            } else {
                pauseRestTask?.cancel()
                pauseRestTask = nil
                if isPausedOSDResting {
                    isPausedOSDResting = false
                }
                if oldPhase == .paused && phase == .playing && viewModel.isPictureReadyForReveal && !isTopDrawerOpen {
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
            if isTopDrawerOpen {
                closeTopDrawer()
            }
            if viewModel.isScrubbing {
                viewModel.commitTouchScrub()
            } else {
                viewModel.togglePlayPause()
            }
            revealBottomBarTemporarily()
        }
        .onExitCommand {
            if isTopDrawerOpen {
                closeTopDrawer()
            } else if viewModel.isScrubbing {
                viewModel.cancelTouchScrub()
                revealBottomBarTemporarily()
            } else if hasSeriesPrompt && !isHUDResting {
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
            let store = sessionStore
            let vm = viewModel
            viewModel.onUnauthorized = { [weak vm] in
                vm?.prepareForDismissal()
                store.unpairDevice()
                onDismiss()
            }
            viewModel.updateInitialScenePhase(scenePhase)
            viewModel.start(request: initialRequest, client: client)
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleScenePhaseChange(phase)
        }
        .onChange(of: viewModel.isRestoringFromBackground) { _, restoring in
            if restoring, isTopDrawerOpen, suspendedFatalErrorForDrawer == nil {
                isTopDrawerOpen = false
            }
        }
        .onDisappear {
            hideBottomBarTask?.cancel()
            pauseRestTask?.cancel()
            let store = sessionStore
            viewModel.teardownAndStop {
                store.notifyContentMutated()
            }
        }
    }

    // MARK: - Focus, 4s Playing Auto-Hide & ~12s OLED/Gallery Pause Rest

    private func openTopDrawer(tab: PlayerTopDrawerTab? = nil) {
        hideBottomBarTask?.cancel()
        pauseRestTask?.cancel()
        isPausedOSDResting = false
        if let tab {
            selectedDrawerTab = tab
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
            showBottomBar = false
            isTopDrawerOpen = true
        }
    }

    private func closeTopDrawer() {
        withAnimation(.easeOut(duration: 0.22)) {
            isTopDrawerOpen = false
        }
        if let suspended = suspendedFatalErrorForDrawer {
            suspendedFatalErrorForDrawer = nil
            if !viewModel.isSwitchingSource && viewModel.fatalError == nil {
                viewModel.fatalError = suspended
                return
            }
        }
        if viewModel.playbackPhase == .paused {
            revealBottomBarTemporarily()
        }
        restoreCanvasFocusSoon()
    }

    private func revealBottomBarTemporarily() {
        withAnimation(.easeOut(duration: 0.16)) {
            isPausedOSDResting = false
            showBottomBar = true
        }
        hideBottomBarTask?.cancel()
        let autoHideNs = UInt64(PlayerOSDVisibilityPolicy.playingAutoHideSeconds * 1_000_000_000)
        hideBottomBarTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoHideNs)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .playing && !viewModel.isScrubbing && !isTopDrawerOpen {
                withAnimation(.easeOut(duration: 0.28)) {
                    showBottomBar = false
                }
            }
        }
        if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && !isTopDrawerOpen {
            schedulePausedIdleRestTimer()
        }
    }

    private func schedulePausedIdleRestTimer() {
        pauseRestTask?.cancel()
        let restNs = UInt64(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds * 1_000_000_000)
        pauseRestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: restNs)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .paused && !viewModel.isScrubbing && !isTopDrawerOpen {
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
            if shouldEnableCanvasAnchor && !hasSeriesPrompt {
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
        let sign = isForward ? "+" : ""

        return HStack(spacing: 12) {
            Image(systemName: isForward ? "goforward" : "gobackward")
                .font(.title2.weight(.bold))
                .foregroundStyle(LunaTheme.amber)
            Text("\(sign)\(secs) s")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(LunaTheme.linen)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.48), lineWidth: 1))
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
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(LunaTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)

                HStack(spacing: 20) {
                    LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .primaryAmber) {
                        suspendedFatalErrorForDrawer = nil
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

                    if viewModel.activeSession != nil {
                        LunaPillButton("Velg annen kilde", systemImage: "arrow.triangle.2.circlepath", prominence: .glassPill) {
                            suspendedFatalErrorForDrawer = message
                            viewModel.fatalError = nil
                            openTopDrawer(tab: .source)
                        }
                    }

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        suspendedFatalErrorForDrawer = nil
                        closePlayer()
                    }
                }
                .padding(.top, 8)
            }
            .padding(60)
        }
    }
}
