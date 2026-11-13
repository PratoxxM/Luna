import SwiftUI
import AetherBridge

/// Isolated 10 Hz leaf view for series continuity («Hopp over intro» & «Spill neste episode»).
struct SeriesFlowOverlays: View {
    private enum PromptFocusTarget: Hashable {
        case skipIntro
        case playNext
        case watchCredits
    }

    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var comfort: ComfortPreferences
    let client: MediaOSClient?
    let isBottomBarVisible: Bool
    @Binding var hasActivePrompt: Bool
    @Binding var dismissedNextForSessionID: String?
    let dismissNonce: Int
    var onReturnFocusToCanvas: () -> Void = {}
    var onOpenTopDrawer: () -> Void = {}
    var onSeekRelative: (Double) -> Void = { _ in }

    @FocusState private var focusedPromptControl: PromptFocusTarget?
    @State private var currentTime: Double = 0
    @State private var enteredIntroAtWallTime: Date?
    @State private var trackedIntroChapterID: String?
    @State private var dismissedIntroChapterIDs: Set<String> = []

    @State private var autoAdvanceRemaining: Int?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        let activeIntro = currentSkippableChapter
        let showNextCard = shouldShowNextEpisodeCard

        VStack {
            Spacer()
            HStack {
                Spacer()

                if showNextCard, let next = viewModel.activeSession?.nextEpisode {
                    nextEpisodeCard(next)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if let intro = activeIntro {
                    skipIntroButton(intro)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, isBottomBarVisible ? 195 : 58)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showNextCard)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: activeIntro?.id)
        }
        .onChange(of: showNextCard) { _, visible in
            syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: visible)
            if visible {
                startCountdownIfEnabled()
                focusedPromptControl = .playNext
            } else {
                stopCountdown()
                if focusedPromptControl == .playNext || focusedPromptControl == .watchCredits {
                    focusedPromptControl = nil
                }
            }
        }
        .onChange(of: activeIntro?.id) { _, newID in
            if let newID, newID != trackedIntroChapterID {
                trackedIntroChapterID = newID
                enteredIntroAtWallTime = Date()
            }
            syncActivePromptFlag(intro: activeIntro, nextVisible: showNextCard)
            if newID != nil && !showNextCard {
                focusedPromptControl = .skipIntro
            } else if newID == nil && focusedPromptControl == .skipIntro {
                focusedPromptControl = nil
                onReturnFocusToCanvas()
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                focusedPromptControl = nil
                onReturnFocusToCanvas()
            case .down:
                focusedPromptControl = nil
                onOpenTopDrawer()
            case .left:
                if focusedPromptControl == .watchCredits {
                    focusedPromptControl = .playNext
                } else {
                    focusedPromptControl = nil
                    onSeekRelative(-10)
                }
            case .right:
                if focusedPromptControl == .playNext {
                    focusedPromptControl = .watchCredits
                } else {
                    focusedPromptControl = nil
                    onSeekRelative(30)
                }
            @unknown default:
                break
            }
        }
        .onChange(of: dismissNonce) { _, _ in
            dismissCurrentPrompt()
        }
        .onChange(of: viewModel.activeSession?.sessionId) { _, _ in
            stopCountdown()
            dismissedIntroChapterIDs.removeAll()
            enteredIntroAtWallTime = nil
            trackedIntroChapterID = nil
            focusedPromptControl = nil
        }
        .onDisappear {
            stopCountdown()
        }
        .onReceive(viewModel.engine.clock.$currentTime) { t in
            let hasContinuityTargets = viewModel.activeSession?.nextEpisode != nil ||
                viewModel.chapters.contains(where: { $0.kind == .intro || $0.kind == .recap || $0.kind == .credits })
            guard hasContinuityTargets else { return }
            guard abs(t - currentTime) >= 0.5 || t < 1.0 else { return }
            currentTime = t
            if let tracked = trackedIntroChapterID,
               let ch = viewModel.chapters.first(where: { $0.id == tracked }),
               (t < ch.startSeconds || t >= ch.endSeconds - 1.5) {
                trackedIntroChapterID = nil
                enteredIntroAtWallTime = nil
            }
        }
    }

    // MARK: - Intro Detection

    private var currentSkippableChapter: PlaybackChapter? {
        guard let ch = viewModel.chapters.first(where: {
            ($0.kind == .intro || $0.kind == .recap) &&
            $0.durationSeconds >= 8 &&
            currentTime >= $0.startSeconds &&
            currentTime < ($0.endSeconds - 2.0)
        }) else {
            return nil
        }
        guard !dismissedIntroChapterIDs.contains(ch.id) else { return nil }

        // Auto-hide after 14s unless bottom bar is shown
        if !isBottomBarVisible, let entered = enteredIntroAtWallTime, Date().timeIntervalSince(entered) > 14.0 {
            return nil
        }
        return ch
    }

    // MARK: - Next Episode Window (Final 45s or End Credits)

    private var shouldShowNextEpisodeCard: Bool {
        guard let session = viewModel.activeSession,
              session.nextEpisode != nil,
              dismissedNextForSessionID != session.sessionId else {
            return false
        }
        let dur = viewModel.effectiveDurationSeconds
        guard dur > 90, currentTime > 30 else { return false }
        let remaining = dur - currentTime
        if remaining <= 45.0 && (remaining >= 0 || countdownTask != nil) {
            return true
        }
        if remaining <= 95.0,
           let ch = viewModel.chapters.first(where: { currentTime >= $0.startSeconds && currentTime < $0.endSeconds }),
           ch.kind == .credits {
            return true
        }
        return false
    }

    // MARK: - Subviews

    private func skipIntroButton(_ chapter: PlaybackChapter) -> some View {
        let label = chapter.kind == .recap ? "Hopp over sammendrag" : "Hopp over intro"
        return LunaPillButton(label, systemImage: "forward.fill", prominence: .primaryAmber) {
            let target = max(chapter.startSeconds + 1.0, chapter.endSeconds - 0.15)
            dismissedIntroChapterIDs.insert(chapter.id)
            focusedPromptControl = nil
            hasActivePrompt = false
            onReturnFocusToCanvas()
            Task {
                await viewModel.engine.seek(to: target, exact: true)
            }
        }
        .focused($focusedPromptControl, equals: .skipIntro)
    }

    private func nextEpisodeCard(_ next: TvNextEpisodeSummary) -> some View {
        let epLabel = String(format: "S%02dE%02d", next.season, next.episode)
        let playLabel: String = {
            if let rem = autoAdvanceRemaining, comfort.autoPlayNextEpisode {
                return "Spill nå (\(rem)s)"
            }
            return "Spill neste"
        }()

        return HStack(spacing: 20) {
            if let rawStill = next.stillUrl, let stillURL = client?.buildAbsoluteURL(rawStill) {
                CachedArtworkView(
                    url: stillURL,
                    client: client,
                    maxPixelSize: 480,
                    placeholderSymbol: "tv",
                    contentMode: .fill
                )
                .frame(width: 196, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("NESTE EPISODE · \(epLabel)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LunaTheme.amber)

                    if viewModel.nextEpisodePrewarmReady {
                        Text("Klar i VFS ⚡")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LunaTheme.emerald)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(LunaTheme.emerald.opacity(0.16), in: Capsule())
                    }
                }

                Text(next.title ?? epLabel)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 360, alignment: .leading)

                HStack(spacing: 12) {
                    LunaPillButton(playLabel, systemImage: "play.fill", prominence: .primaryAmber) {
                        stopCountdown()
                        focusedPromptControl = nil
                        hasActivePrompt = false
                        viewModel.playNextEpisode(next)
                    }
                    .focused($focusedPromptControl, equals: .playNext)

                    LunaPillButton("Se ferdig", prominence: .subtleChip) {
                        dismissCurrentPrompt()
                        onReturnFocusToCanvas()
                    }
                    .focused($focusedPromptControl, equals: .watchCredits)
                }
            }
        }
        .padding(18)
        .background(LunaTheme.cinemaGlass, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LunaTheme.amber.opacity(0.42), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.65), radius: 24, x: 0, y: 10)
    }

    // MARK: - Countdown & Dismissal

    private func syncActivePromptFlag(intro: PlaybackChapter?, nextVisible: Bool) {
        hasActivePrompt = (intro != nil) || nextVisible
    }

    private func dismissCurrentPrompt() {
        stopCountdown()
        focusedPromptControl = nil
        if shouldShowNextEpisodeCard, let sid = viewModel.activeSession?.sessionId {
            dismissedNextForSessionID = sid
        } else if let intro = currentSkippableChapter {
            dismissedIntroChapterIDs.insert(intro.id)
        }
        hasActivePrompt = false
    }

    private func startCountdownIfEnabled() {
        stopCountdown()
        guard comfort.autoPlayNextEpisode, let next = viewModel.activeSession?.nextEpisode else { return }
        var remaining = 10
        autoAdvanceRemaining = remaining
        countdownTask = Task { @MainActor in
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard viewModel.playbackPhase == .playing, !viewModel.isScrubbing else {
                    continue
                }
                remaining -= 1
                autoAdvanceRemaining = remaining
            }
            guard !Task.isCancelled else { return }
            hasActivePrompt = false
            viewModel.playNextEpisode(next)
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        autoAdvanceRemaining = nil
    }
}
