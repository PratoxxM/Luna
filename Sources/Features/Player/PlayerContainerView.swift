import SwiftUI
import AetherBridge

struct PlayerContainerView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let engine: AetherEngine
    let initialRequest: PlaybackLaunchRequest
    let onDismiss: () -> Void

    @StateObject private var viewModel: PlayerViewModel
    @State private var showControls: Bool = true
    @State private var activeModal: PlayerSheetModal?
    @State private var hideControlsTask: Task<Void, Never>?

    init(
        engine: AetherEngine,
        initialRequest: PlaybackLaunchRequest,
        onDismiss: @escaping () -> Void
    ) {
        self.engine = engine
        self.initialRequest = initialRequest
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PlayerViewModel(engine: engine))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 1. Hardware / Dual-Layer FEL Video Surface
            AetherPlayerSurface(engine: engine)
                .ignoresSafeArea()

            // 2. Leaf-isolated Subtitle Overlay
            SubtitleOverlayView(engine: engine)
                .ignoresSafeArea()

            // 3. Cold Resolve / VFS Mount Overlay
            if viewModel.isResolving {
                resolveProgressOverlay
            } else if let err = viewModel.fatalError {
                fatalErrorOverlay(err)
            } else if showControls {
                transportOverlay
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .audio:
                AudioTrackSheetView(viewModel: viewModel) { activeModal = nil }
            case .subtitles:
                SubtitleTrackSheetView(viewModel: viewModel) { activeModal = nil }
            case .sources:
                SourceSwitcherSheetView(viewModel: viewModel) { activeModal = nil }
            case .diagnostics:
                DiagnosticsSheetView(viewModel: viewModel)
            }
        }
        .onPlayPauseCommand {
            guard !viewModel.isResolving else { return }
            engine.togglePlayPause()
            revealControlsTemporarily()
        }
        .onMoveCommand { direction in
            if !showControls {
                revealControlsTemporarily()
                return
            }
            revealControlsTemporarily()
            switch direction {
            case .left:
                Task { await engine.seek(to: max(0, engine.currentTime - 15)) }
            case .right:
                Task { await engine.seek(to: engine.currentTime + 30) }
            default:
                break
            }
        }
        .onExitCommand {
            if showControls && !viewModel.isResolving && viewModel.playbackPhase == .playing {
                showControls = false
            } else {
                closePlayer()
            }
        }
        .onAppear {
            viewModel.start(request: initialRequest, client: sessionStore.makeClient())
            revealControlsTemporarily()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            viewModel.teardownAndStop()
        }
    }

    private var resolveProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.4)

                Text(initialRequest.seriesTitle ?? initialRequest.title)
                    .font(.title.bold())

                Text(viewModel.resolveStageLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let headline = viewModel.resolveHeadline {
                    Text(headline)
                        .font(.callout.monospaced())
                        .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.42))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.77, blue: 0.42))
                            .frame(width: geo.size.width * CGFloat(Double(viewModel.resolvePercent) / 100.0))
                    }
                }
                .frame(width: 520, height: 8)

                Button("Avbryt") {
                    closePlayer()
                }
                .padding(.top, 12)
            }
            .padding(60)
        }
    }

    private func fatalErrorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.yellow)

                Text("Avspilling feilet")
                    .font(.title2.bold())

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)

                HStack(spacing: 24) {
                    Button("Prøv igjen") {
                        viewModel.start(request: initialRequest, client: sessionStore.makeClient())
                    }

                    if viewModel.activeSession != nil {
                        Button("Velg annen kilde") {
                            activeModal = .sources
                        }
                    }

                    Button("Lukk") {
                        closePlayer()
                    }
                }
            }
            .padding(60)
        }
    }

    private var transportOverlay: some View {
        VStack {
            // Top bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let series = viewModel.activeSession?.item.seriesTitle {
                        Text(series)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.activeSession?.item.title ?? initialRequest.title)
                        .font(.title2.bold())
                    if let headline = viewModel.resolveHeadline {
                        Text(headline)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.42))
                    }
                }

                Spacer()

                if let next = viewModel.activeSession?.nextEpisode, viewModel.nextEpisodePrewarmReady {
                    Button {
                        viewModel.playNextEpisode(next)
                    } label: {
                        Label(
                            String(format: "Neste: S%02dE%02d", next.season, next.episode),
                            systemImage: "forward.end.fill"
                        )
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.top, 44)

            Spacer()

            // Bottom transport & modal sheet triggers (NEVER SwiftUI Menu on tvOS 26!)
            VStack(spacing: 22) {
                PlayerScrubberBarView(
                    engine: engine,
                    duration: viewModel.durationSeconds > 0
                        ? viewModel.durationSeconds
                        : (viewModel.activeSession?.stream.declaredDurationSeconds ?? 0)
                )

                HStack(spacing: 20) {
                    Button {
                        engine.togglePlayPause()
                        revealControlsTemporarily()
                    } label: {
                        Label(
                            viewModel.playbackPhase == .playing ? "Pause" : "Spill",
                            systemImage: viewModel.playbackPhase == .playing ? "pause.fill" : "play.fill"
                        )
                    }

                    Button {
                        Task { await engine.seek(to: max(0, engine.currentTime - 15)) }
                        revealControlsTemporarily()
                    } label: {
                        Label("-15s", systemImage: "gobackward.15")
                    }

                    Button {
                        Task { await engine.seek(to: engine.currentTime + 30) }
                        revealControlsTemporarily()
                    } label: {
                        Label("+30s", systemImage: "goforward.30")
                    }

                    Spacer()

                    Button {
                        activeModal = .audio
                    } label: {
                        Label("Lyd", systemImage: "waveform")
                    }

                    Button {
                        activeModal = .subtitles
                    } label: {
                        Label("Tekst", systemImage: "captions.bubble")
                    }

                    Button {
                        activeModal = .sources
                    } label: {
                        Label("Kilde", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        activeModal = .diagnostics
                    } label: {
                        Label("Info", systemImage: "gauge.with.dots.needle.67percent")
                    }

                    Button {
                        closePlayer()
                    } label: {
                        Label("Lukk", systemImage: "xmark")
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 48)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func revealControlsTemporarily() {
        showControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if viewModel.playbackPhase == .playing && activeModal == nil {
                showControls = false
            }
        }
    }

    private func closePlayer() {
        hideControlsTask?.cancel()
        onDismiss()
    }
}
