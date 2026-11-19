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

    static func initialResumeBannerSeconds(
        sessionId: String?,
        streamStartPositionSeconds: Double?,
        requestStartPositionSeconds: Double?,
        shownForSessionID: String?
    ) -> Double? {
        guard let sid = sessionId, !sid.isEmpty, shownForSessionID != sid else {
            return nil
        }
        let startPos = streamStartPositionSeconds ?? requestStartPositionSeconds ?? 0
        return startPos > 15.0 ? startPos : nil
    }
}

/// Isolated 2 Hz leaf view for series continuity («Hopp over intro», «Neste episode» & «Start på nytt»).
struct SeriesFlowOverlays: View {
    private enum PromptFocusTarget: Hashable {
        case restartFromBeginning
        case skipIntro
        case playNext
    }

    @ObservedObject var viewModel: PlayerViewModel
    let isBottomBarVisible: Bool
    var isResting: Bool = false
    @Binding var hasActivePrompt: Bool
    @Binding var dismissedNextForSessionID: String?
    let dismissNonce: Int
    var onReturnFocusToCanvas: () -> Void = {}
    var onSilentReturnFocusToCanvas: () -> Void = {}
    var onOpenTopDrawer: () -> Void = {}
    var onSeekRelative: (Double) -> Void = { _ in }

    @FocusState private var focusedPromptControl: PromptFocusTarget?
    @State private var currentTime: Double = 0
    @State private var enteredIntroAtWallTime: Date?
    @State private var trackedIntroChapterID: String?
    @State private var dismissedIntroChapterIDs: Set<String> = []
    @State private var handledResumeSessionID: String?
    @State private var activeResumeStartSeconds: Double?
    @State private var resumeHideTask: Task<Void, Never>?

    var body: some View {
        let activeIntro = currentSkippableChapter
        let showNextButton = shouldShowNextEpisodeButton
        let resumeSecs = showNextButton ? nil : activeResumeStartSeconds

        VStack {
            Spacer()
            HStack {
                if let resumeSecs {
                    Spacer()
                    resumeBannerView(seconds: resumeSecs)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    Spacer()
                } else {
                    Spacer()

                    if showNextButton, let next = viewModel.activeSession?.nextEpisode {
                        nextEpisodeButton(next)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    } else if let intro = activeIntro {
                        skipIntroButton(intro)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, isBottomBarVisible ? 226 : 58)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showNextButton)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: activeIntro?.id)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: resumeSecs != nil)
        }
        .opacity(isResting ? 0 : 1)
        .allowsHitTesting(!isResting)
        .disabled(isResting)
        .onAppear {
            currentTime = viewModel.engine.currentTime
            armResumeBannerIfEligible()
            let intro = currentSkippableChapter
            let nextVisible = shouldShowNextEpisodeButton
            if activeResumeStartSeconds != nil, !nextVisible {
                if !isResting {
                    focusedPromptControl = .restartFromBeginning
                }
            } else if let intro, !nextVisible {
                trackedIntroChapterID = intro.id
                enteredIntroAtWallTime = Date()
                if !isResting {
                    focusedPromptControl = .skipIntro
                }
            } else if nextVisible, !isResting {
                focusedPromptControl = .playNext
            }
            syncActivePromptFlag(intro: intro, nextVisible: nextVisible)
        }
        .onChange(of: isResting) { _, resting in
            if resting {
                focusedPromptControl = nil
            } else if shouldShowNextEpisodeButton {
                focusedPromptControl = .playNext
            } else if activeResumeStartSeconds != nil {
                focusedPromptControl = .restartFromBeginning
            } else if currentSkippableChapter != nil {
                focusedPromptControl = .skipIntro
            }
        }
        .onChange(of: showNextButton) { _, visible in
            syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: visible)
            if visible && !isResting {
                focusedPromptControl = .playNext
            } else if !visible, focusedPromptControl == .playNext {
                focusedPromptControl = nil
                if activeResumeStartSeconds == nil && currentSkippableChapter == nil {
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
            if activeResumeStartSeconds == nil && newID != nil && !showNextButton && !isResting {
                focusedPromptControl = .skipIntro
            } else if newID == nil && focusedPromptControl == .skipIntro {
                focusedPromptControl = nil
                if activeResumeStartSeconds == nil {
                    onReturnFocusToCanvas()
                }
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                if activeResumeStartSeconds != nil {
                    hideResumeBanner(returningFocus: true)
                } else {
                    focusedPromptControl = nil
                    onReturnFocusToCanvas()
                }
            case .down:
                if activeResumeStartSeconds != nil {
                    hideResumeBanner(returningFocus: false)
                }
                focusedPromptControl = nil
                onOpenTopDrawer()
            case .left:
                if activeResumeStartSeconds != nil {
                    hideResumeBanner(returningFocus: false)
                }
                focusedPromptControl = nil
                onSeekRelative(-10)
            case .right:
                if activeResumeStartSeconds != nil {
                    hideResumeBanner(returningFocus: false)
                }
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
            resumeHideTask?.cancel()
            resumeHideTask = nil
            activeResumeStartSeconds = nil
            focusedPromptControl = nil
            hasActivePrompt = false
            armResumeBannerIfEligible()
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
        .onDisappear {
            resumeHideTask?.cancel()
            resumeHideTask = nil
            activeResumeStartSeconds = nil
            focusedPromptControl = nil
            hasActivePrompt = false
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
        let isFocused = (focusedPromptControl == .skipIntro)
        return Button {
            let target = max(chapter.startSeconds + 1.0, chapter.endSeconds - 0.15)
            dismissedIntroChapterIDs.insert(chapter.id)
            focusedPromptControl = nil
            hasActivePrompt = false
            onReturnFocusToCanvas()
            Task {
                await viewModel.engine.seek(to: target, exact: true)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "forward.end.fill")
                    .font(LunaTheme.Font.primaryPlayIcon)
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.amber)
                Text(label)
                    .font(LunaTheme.Font.pillLabel.weight(.semibold))
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.linen)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                if isFocused {
                    Capsule()
                        .fill(LunaTheme.focusGoldGradient)
                } else {
                    Capsule()
                        .fill(LunaTheme.cinemaGlass)
                }
            }
            .lunaFocusSurface(.secondaryPill, isFocused: isFocused, cornerRadius: 999)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
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

    // MARK: - Dismissal & Resume Banner Helpers

    private func resumeBannerView(seconds: Double) -> some View {
        let timeText = TimelineScrubberLeafView.formatSeconds(seconds)
        return HStack(spacing: 20) {
            Text("Fortsetter fra \(timeText)")
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.linen)

            LunaPillButton(
                "Start på nytt",
                systemImage: "arrow.counterclockwise",
                prominence: .glassPill,
                size: .compact
            ) {
                hideResumeBanner(returningFocus: true)
                Task {
                    await viewModel.transport.seek(to: 0, exact: true)
                }
            }
            .focused($focusedPromptControl, equals: .restartFromBeginning)
        }
        .padding(.leading, 26)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(LunaTheme.warmBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 10)
    }

    private func armResumeBannerIfEligible() {
        guard !viewModel.isSwitchingSource else { return }
        let sid = viewModel.activeSession?.sessionId
        guard let seconds = SeriesFlowEligibility.initialResumeBannerSeconds(
            sessionId: sid,
            streamStartPositionSeconds: viewModel.activeSession?.stream.startPositionSeconds,
            requestStartPositionSeconds: viewModel.currentRequest?.startPositionSeconds,
            shownForSessionID: handledResumeSessionID
        ) else {
            return
        }
        handledResumeSessionID = sid
        activeResumeStartSeconds = seconds
        syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: shouldShowNextEpisodeButton)
        if !isResting && !shouldShowNextEpisodeButton {
            focusedPromptControl = .restartFromBeginning
        }
        resumeHideTask?.cancel()
        resumeHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            hideResumeBanner(returningFocus: true, silentFocusReturn: true)
        }
    }

    private func hideResumeBanner(returningFocus: Bool, silentFocusReturn: Bool = false) {
        resumeHideTask?.cancel()
        resumeHideTask = nil
        let hadBanner = activeResumeStartSeconds != nil
        activeResumeStartSeconds = nil
        syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: shouldShowNextEpisodeButton)
        if focusedPromptControl == .restartFromBeginning {
            focusedPromptControl = nil
        }
        if hadBanner && returningFocus {
            if let intro = currentSkippableChapter, !shouldShowNextEpisodeButton, !isResting {
                focusedPromptControl = .skipIntro
            } else if silentFocusReturn {
                onSilentReturnFocusToCanvas()
            } else {
                onReturnFocusToCanvas()
            }
        }
    }

    private func syncActivePromptFlag(intro: PlaybackChapter?, nextVisible: Bool) {
        hasActivePrompt = (intro != nil) || nextVisible || (activeResumeStartSeconds != nil)
    }

    private func dismissCurrentPrompt() {
        focusedPromptControl = nil
        if shouldShowNextEpisodeButton, let sid = viewModel.activeSession?.sessionId {
            dismissedNextForSessionID = sid
        } else if activeResumeStartSeconds != nil {
            hideResumeBanner(returningFocus: false)
        } else if let intro = currentSkippableChapter {
            dismissedIntroChapterIDs.insert(intro.id)
        }
        syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: shouldShowNextEpisodeButton)
    }
}
