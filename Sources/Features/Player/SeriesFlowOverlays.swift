import SwiftUI
import AetherBridge

/// Pure visibility & duration rules for series continuity overlays, isolated for unit testing.
internal enum SeriesFlowEligibility {
    static let maxNextEpisodeCreditsLeadSeconds: Double = 420.0
    static let passiveCreditsDisplayCapSeconds: TimeInterval = 18.0

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
/// Never steals Siri Remote focus automatically on startup or during credits (`T-M1`); explicit Up press
/// from `SiriRemoteTouchSurface` (`focusPromptNonce`) moves focus onto the active prompt button.
struct SeriesFlowOverlays: View {
    private enum PromptFocusTarget: Hashable {
        case restartFromBeginning
        case skipIntro
        case playNext
        case dismissNext
    }

    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    @ObservedObject var viewModel: PlayerViewModel
    let isBottomBarVisible: Bool
    var isResting: Bool = false
    @Binding var hasActivePrompt: Bool
    @Binding var isPromptFocused: Bool
    @Binding var dismissedNextForSessionID: String?
    let dismissNonce: Int
    var focusPromptNonce: Int = 0
    var onReturnFocusToCanvas: () -> Void = {}
    var onSilentReturnFocusToCanvas: () -> Void = {}
    var onFocusQuickActions: () -> Void = {}
    var onSeekRelative: (Double) -> Void = { _ in }

    @FocusState private var focusedPromptControl: PromptFocusTarget?
    @State private var currentTime: Double = 0
    @State private var enteredIntroAtWallTime: Date?
    @State private var trackedIntroChapterID: String?
    @State private var enteredCreditsAtWallTime: Date?
    @State private var dismissedIntroChapterIDs: Set<String> = []
    @State private var handledResumeSessionID: String?
    @State private var activeResumeStartSeconds: Double?
    @State private var resumeHideTask: Task<Void, Never>?

    var body: some View {
        let activeIntro = currentSkippableChapter
        let nextWindowEligible = isNextEpisodeWindowEligible
        let showNextButton = shouldShowNextEpisodeButton
        let resumeSecs = showNextButton ? nil : activeResumeStartSeconds

        ZStack {
            if let resumeSecs {
                VStack {
                    resumeBannerView(seconds: resumeSecs)
                        .padding(.top, 64)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    if showNextButton, let next = viewModel.activeSession?.nextEpisode {
                        nextEpisodeCard(next)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    } else if let intro = activeIntro {
                        skipIntroButton(intro)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.bottom, isBottomBarVisible ? 304 : 60)
            }
        }
        .animation(LunaFocusStyle.focusSpring, value: showNextButton)
        .animation(LunaFocusStyle.focusSpring, value: activeIntro?.id)
        .animation(LunaFocusStyle.focusSpring, value: resumeSecs != nil)
        .opacity(isResting ? 0 : 1)
        .allowsHitTesting(!isResting)
        .disabled(isResting)
        .onAppear {
            currentTime = viewModel.engine.currentTime
            armResumeBannerIfEligible()
            let intro = currentSkippableChapter
            if let intro {
                trackedIntroChapterID = intro.id
                enteredIntroAtWallTime = Date()
            }
            let nextEligible = isNextEpisodeWindowEligible
            if nextEligible && enteredCreditsAtWallTime == nil {
                enteredCreditsAtWallTime = Date()
            }
            syncActivePromptFlag(intro: intro, nextVisible: shouldShowNextEpisodeButton)
        }
        .onChange(of: focusedPromptControl) { _, newFocus in
            isPromptFocused = (newFocus != nil)
            if newFocus == .restartFromBeginning {
                scheduleResumeAutoHide(seconds: 6.0)
            }
        }
        .onChange(of: focusPromptNonce) { _, _ in
            guard !isResting else { return }
            if activeResumeStartSeconds != nil && !shouldShowNextEpisodeButton {
                focusedPromptControl = .restartFromBeginning
            } else if shouldShowNextEpisodeButton {
                focusedPromptControl = .playNext
            } else if currentSkippableChapter != nil {
                focusedPromptControl = .skipIntro
            }
        }
        .onChange(of: isResting) { _, resting in
            if resting {
                focusedPromptControl = nil
            }
        }
        .onChange(of: nextWindowEligible) { _, eligible in
            if eligible && enteredCreditsAtWallTime == nil {
                enteredCreditsAtWallTime = Date()
            } else if !eligible {
                enteredCreditsAtWallTime = nil
            }
        }
        .onChange(of: showNextButton) { _, visible in
            syncActivePromptFlag(intro: currentSkippableChapter, nextVisible: visible)
            if !visible, focusedPromptControl == .playNext {
                focusedPromptControl = nil
                onReturnFocusToCanvas()
            }
        }
        .onChange(of: activeIntro?.id) { _, newID in
            if let newID, newID != trackedIntroChapterID {
                trackedIntroChapterID = newID
                enteredIntroAtWallTime = Date()
            }
            syncActivePromptFlag(intro: activeIntro, nextVisible: showNextButton)
            if newID == nil && focusedPromptControl == .skipIntro {
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
                if activeResumeStartSeconds != nil {
                    hideResumeBanner(returningFocus: false)
                }
                focusedPromptControl = nil
                onFocusQuickActions()
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
                onSeekRelative(10)
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
            enteredCreditsAtWallTime = nil
            resumeHideTask?.cancel()
            resumeHideTask = nil
            activeResumeStartSeconds = nil
            focusedPromptControl = nil
            isPromptFocused = false
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
            isPromptFocused = false
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

        if focusedPromptControl != .skipIntro,
           !isBottomBarVisible,
           let entered = enteredIntroAtWallTime,
           Date().timeIntervalSince(entered) > 14.0 {
            return nil
        }
        return ch
    }

    // MARK: - Next Episode Window (Final 30s or End Credits, auto-rested during long credits)

    private var isNextEpisodeWindowEligible: Bool {
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

    private var shouldShowNextEpisodeButton: Bool {
        guard isNextEpisodeWindowEligible, let session = viewModel.activeSession else {
            return false
        }
        let authoritativeDuration = SeriesFlowEligibility.authoritativeStreamDurationSeconds(
            engineDurationSeconds: viewModel.durationSeconds,
            declaredStreamDurationSeconds: session.stream.declaredDurationSeconds
        )
        let remaining = authoritativeDuration - currentTime
        if remaining > 30.0,
           focusedPromptControl != .playNext,
           !isBottomBarVisible,
           let entered = enteredCreditsAtWallTime,
           Date().timeIntervalSince(entered) > SeriesFlowEligibility.passiveCreditsDisplayCapSeconds {
            return false
        }
        return true
    }

    // MARK: - Subviews

    private func skipIntroButton(_ chapter: PlaybackChapter) -> some View {
        let baseLabel = chapter.kind == .recap ? "Hopp over sammendrag" : "Hopp over intro"
        return HStack(spacing: 10) {
            Image(systemName: "chevron.up")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
                .frame(width: 24)

            LunaPillButton(
                baseLabel,
                systemImage: "forward.end.fill",
                prominence: .glassPill
            ) {
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
    }

    private func nextEpisodeCard(_ next: TvNextEpisodeSummary) -> some View {
        let epLabel = "Neste episode · S\(next.season) E\(next.episode)"
        let cleanTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            next.title,
            seriesTitle: viewModel.activeSession?.item.seriesTitle,
            season: next.season,
            episode: next.episode
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text(epLabel)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)

            if let cleanTitle, !cleanTitle.isEmpty {
                Text(cleanTitle)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 10) {
                LunaPillButton(
                    "Spill nå",
                    systemImage: "play.fill",
                    prominence: .primary,
                    size: .compact
                ) {
                    focusedPromptControl = nil
                    hasActivePrompt = false
                    viewModel.playNextEpisode(next)
                }
                .focused($focusedPromptControl, equals: .playNext)

                LunaPillButton(
                    "Skjul",
                    prominence: .glassPill,
                    size: .compact
                ) {
                    dismissCurrentPrompt()
                }
                .focused($focusedPromptControl, equals: .dismissNext)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                .fill(LunaTheme.cinemaGlass)
        )
        .lunaTopLightEdge(
            cornerRadius: LunaTokens.Radius.panel,
            topColor: LunaTokens.Edge.top3,
            sideColor: LunaTokens.Edge.top1,
            lineWidth: LunaTokens.Layout.hairlineWidth
        )
        .shadow(
            color: roomAtmosphere.lampColor.opacity(0.14),
            radius: 24,
            x: 0,
            y: 10
        )
        .focusSection()
    }

    // MARK: - Dismissal & Resume Banner Helpers

    private func resumeBannerView(seconds: Double) -> some View {
        let timeText = TimelineScrubberLeafView.formatSeconds(seconds)
        return HStack(spacing: 20) {
            Text("Fortsetter fra \(timeText)")
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.linen)

            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                    .frame(width: 20)

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
        }
        .padding(.leading, 26)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .lunaTopLightEdge(
            cornerRadius: LunaTokens.Radius.pill,
            topColor: LunaTokens.Edge.top3,
            sideColor: LunaTokens.Edge.top1,
            lineWidth: LunaTokens.Layout.hairlineWidth
        )
        .shadow(
            color: roomAtmosphere.lampColor.opacity(0.14),
            radius: 20,
            x: 0,
            y: 8
        )
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
        scheduleResumeAutoHide(seconds: 4.5)
    }

    private func scheduleResumeAutoHide(seconds: TimeInterval) {
        resumeHideTask?.cancel()
        let ns = UInt64(seconds * 1_000_000_000)
        resumeHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            let wasFocused = (focusedPromptControl == .restartFromBeginning)
            hideResumeBanner(returningFocus: wasFocused, silentFocusReturn: true)
        }
    }

    private func hideResumeBanner(returningFocus: Bool, silentFocusReturn: Bool = false) {
        resumeHideTask?.cancel()
        resumeHideTask = nil
        activeResumeStartSeconds = nil
        if focusedPromptControl == .restartFromBeginning {
            focusedPromptControl = nil
        }
        let intro = currentSkippableChapter
        let nextVisible = shouldShowNextEpisodeButton
        syncActivePromptFlag(intro: intro, nextVisible: nextVisible)
        if returningFocus {
            if silentFocusReturn {
                onSilentReturnFocusToCanvas()
            } else {
                onReturnFocusToCanvas()
            }
        }
    }

    private func syncActivePromptFlag(intro: PlaybackChapter?, nextVisible: Bool) {
        hasActivePrompt = nextVisible || activeResumeStartSeconds != nil || intro != nil
    }

    private func dismissCurrentPrompt() {
        if activeResumeStartSeconds != nil {
            hideResumeBanner(returningFocus: true)
            return
        }
        if shouldShowNextEpisodeButton, let sid = viewModel.activeSession?.sessionId {
            dismissedNextForSessionID = sid
        } else if let intro = currentSkippableChapter {
            dismissedIntroChapterIDs.insert(intro.id)
        }
        focusedPromptControl = nil
        hasActivePrompt = false
        onReturnFocusToCanvas()
    }
}
