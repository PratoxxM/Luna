import SwiftUI
import AetherBridge

/// Pure visibility & duration rules for series continuity overlays, isolated for unit testing.
internal enum SeriesFlowEligibility {
    static let maxNextEpisodeCreditsLeadSeconds: Double = 420.0

    static func authoritativeStreamDurationSeconds(
        engineDurationSeconds: Double,
        declaredStreamDurationSeconds: Double?
    ) -> Double {
        if engineDurationSeconds > 0 {
            return engineDurationSeconds
        }
        if let declared = declaredStreamDurationSeconds, declared > 0 {
            return declared
        }
        return 0
    }

    static func shouldShowNextEpisodePrompt(
        hasNextEpisode: Bool,
        isDismissedForCurrentSession: Bool,
        currentTime: Double,
        authoritativeDurationSeconds: Double,
        chapters: [PlaybackChapter]
    ) -> Bool {
        guard hasNextEpisode, !isDismissedForCurrentSession else {
            return false
        }
        guard authoritativeDurationSeconds > 90, currentTime > 30 else {
            return false
        }
        let remaining = authoritativeDurationSeconds - currentTime
        if remaining <= 30.0 && remaining >= -5.0 {
            return true
        }
        if remaining >= -5.0,
           remaining <= maxNextEpisodeCreditsLeadSeconds,
           currentTime >= authoritativeDurationSeconds * 0.5,
           chapters.contains(where: { $0.kind == .credits && currentTime >= $0.startSeconds && currentTime < $0.endSeconds }) {
            return true
        }
        return false
    }
}

/// Isolated 2 Hz leaf view for series continuity («Hopp over intro» & «Neste episode»).
struct SeriesFlowOverlays: View {
    private enum PromptFocusTarget: Hashable {
        case skipIntro
        case playNext
    }

    @ObservedObject var viewModel: PlayerViewModel
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

    var body: some View {
        let activeIntro = currentSkippableChapter
        let showNextButton = shouldShowNextEpisodeButton

        VStack {
            Spacer()
            HStack {
                Spacer()

                if showNextButton, let next = viewModel.activeSession?.nextEpisode {
                    nextEpisodeButton(next)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else if let intro = activeIntro {
                    skipIntroButton(intro)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, isBottomBarVisible ? 226 : 58)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showNextButton)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: activeIntro?.id)
        }
        .onAppear {
            currentTime = viewModel.engine.currentTime
            let intro = currentSkippableChapter
            let nextVisible = shouldShowNextEpisodeButton
            if let intro, !nextVisible {
                trackedIntroChapterID = intro.id
                enteredIntroAtWallTime = Date()
                focusedPromptControl = .skipIntro
            } else if nextVisible {
                focusedPromptControl = .playNext
            }
            syncActivePromptFlag(intro: intro, nextVisible: nextVisible)
        }
        .onChange(of: showNextButton) { _, visible in
            syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: visible)
            if visible {
                focusedPromptControl = .playNext
            } else if focusedPromptControl == .playNext {
                focusedPromptControl = nil
                if currentSkippableChapter == nil {
                    onReturnFocusToCanvas()
                }
            }
        }
        .onChange(of: activeIntro?.id) { _, newID in
            if let newID, newID != trackedIntroChapterID {
                trackedIntroChapterID = newID
                enteredIntroAtWallTime = Date()
            }
            syncActivePromptFlag(intro: activeIntro, nextVisible: showNextButton)
            if newID != nil && !showNextButton {
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
                focusedPromptControl = nil
                onSeekRelative(-10)
            case .right:
                focusedPromptControl = nil
                onSeekRelative(30)
            @unknown default:
                break
            }
        }
        .onChange(of: dismissNonce) { _, _ in
            dismissCurrentPrompt()
        }
        .onChange(of: viewModel.activeSession?.sessionId) { _, _ in
            currentTime = max(0, viewModel.engine.currentTime)
            dismissedNextForSessionID = nil
            dismissedIntroChapterIDs.removeAll()
            enteredIntroAtWallTime = nil
            trackedIntroChapterID = nil
            focusedPromptControl = nil
            hasActivePrompt = false
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

    // MARK: - Next Episode Window (Final 30s or End Credits)

    private var shouldShowNextEpisodeButton: Bool {
        guard let session = viewModel.activeSession else {
            return false
        }
        let authoritativeDuration = SeriesFlowEligibility.authoritativeStreamDurationSeconds(
            engineDurationSeconds: viewModel.durationSeconds,
            declaredStreamDurationSeconds: session.stream.declaredDurationSeconds
        )
        return SeriesFlowEligibility.shouldShowNextEpisodePrompt(
            hasNextEpisode: session.nextEpisode != nil,
            isDismissedForCurrentSession: dismissedNextForSessionID == session.sessionId,
            currentTime: currentTime,
            authoritativeDurationSeconds: authoritativeDuration,
            chapters: viewModel.chapters
        )
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

    private func nextEpisodeButton(_ next: TvNextEpisodeSummary) -> some View {
        let epLabel = String(format: "S%02dE%02d", next.season, next.episode)
        return LunaPillButton(
            "Neste episode",
            systemImage: "play.fill",
            badgeText: epLabel,
            prominence: .primaryAmber
        ) {
            focusedPromptControl = nil
            hasActivePrompt = false
            viewModel.playNextEpisode(next)
        }
        .focused($focusedPromptControl, equals: .playNext)
    }

    // MARK: - Dismissal

    private func syncActivePromptFlag(intro: PlaybackChapter?, nextVisible: Bool) {
        hasActivePrompt = (intro != nil) || nextVisible
    }

    private func dismissCurrentPrompt() {
        focusedPromptControl = nil
        if shouldShowNextEpisodeButton, let sid = viewModel.activeSession?.sessionId {
            dismissedNextForSessionID = sid
        } else if let intro = currentSkippableChapter {
            dismissedIntroChapterIDs.insert(intro.id)
        }
        hasActivePrompt = false
    }
}
