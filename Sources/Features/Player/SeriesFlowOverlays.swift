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

/// Isolated 0 Hz steady-state leaf view for series continuity («Hopp over intro», «Neste episode» & «Start på nytt»).
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

    let viewModel: PlayerViewModel
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
    @State private var clockBox = SeriesFlowClockBox()
    @State private var activeIntro: PlaybackChapter?
    @State private var showNextButton: Bool = false
    @State private var dismissedIntroChapterIDs: Set<String> = []
    @State private var handledResumeSessionID: String?
    @State private var activeResumeStartSeconds: Double?
    @State private var isResumeAutoHideArmed: Bool = false
    @State private var resumeAutoHideNonce: Int = 0
    @State private var resumeAutoHideSeconds: TimeInterval = 4.5

    var body: some View {
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
            clockBox.currentTime = max(0, viewModel.engine.currentTime)
            armResumeBannerIfEligible()
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .onChange(of: focusedPromptControl) { _, newFocus in
            isPromptFocused = (newFocus != nil)
            if newFocus == .restartFromBeginning {
                scheduleResumeAutoHide(seconds: 6.0)
            }
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .onChange(of: isBottomBarVisible) { _, _ in
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .onChange(of: viewModel.chapters) { _, _ in
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .onChange(of: viewModel.durationSeconds) { _, _ in
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .onChange(of: focusPromptNonce) { _, _ in
            guard !isResting else { return }
            if activeResumeStartSeconds != nil && !showNextButton {
                focusedPromptControl = .restartFromBeginning
            } else if showNextButton {
                focusedPromptControl = .playNext
            } else if activeIntro != nil {
                focusedPromptControl = .skipIntro
            }
        }
        .onChange(of: isResting) { _, resting in
            if resting {
                focusedPromptControl = nil
            }
        }
        .onChange(of: showNextButton) { _, visible in
            syncActivePromptFlag()
            if !visible, focusedPromptControl == .playNext {
                focusedPromptControl = nil
                onReturnFocusToCanvas()
            }
        }
        .onChange(of: activeIntro?.id) { _, newID in
            syncActivePromptFlag()
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
            clockBox.reset(initialTime: max(0, viewModel.engine.currentTime))
            dismissedNextForSessionID = nil
            dismissedIntroChapterIDs.removeAll()
            isResumeAutoHideArmed = false
            activeResumeStartSeconds = nil
            activeIntro = nil
            showNextButton = false
            focusedPromptControl = nil
            isPromptFocused = false
            hasActivePrompt = false
            armResumeBannerIfEligible()
            evaluateContinuityState(at: clockBox.currentTime)
        }
        .task(id: isResumeAutoHideArmed ? resumeAutoHideNonce : 0) {
            guard isResumeAutoHideArmed, resumeAutoHideNonce > 0 else { return }
            let ns = UInt64(resumeAutoHideSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            let wasFocused = (focusedPromptControl == .restartFromBeginning)
            hideResumeBanner(returningFocus: wasFocused, silentFocusReturn: true)
        }
        .onReceive(viewModel.engine.clock.$currentTime) { t in
            let hasContinuityTargets = viewModel.activeSession?.nextEpisode != nil ||
                viewModel.chapters.contains(where: { $0.kind == .intro || $0.kind == .recap || $0.kind == .credits })
            guard hasContinuityTargets else { return }
            guard abs(t - clockBox.currentTime) >= 0.5 || t < 1.0 else { return }
            clockBox.currentTime = t
            evaluateContinuityState(at: t)
        }
        .onDisappear {
            isResumeAutoHideArmed = false
            activeResumeStartSeconds = nil
            focusedPromptControl = nil
            isPromptFocused = false
            hasActivePrompt = false
        }
    }

    // MARK: - 0 Hz Steady-State Continuity Evaluation

    private func evaluateContinuityState(at t: Double) {
        if let tracked = clockBox.trackedIntroChapterID,
           let ch = viewModel.chapters.first(where: { $0.id == tracked }),
           (t < ch.startSeconds || t >= ch.endSeconds - 1.5) {
            clockBox.trackedIntroChapterID = nil
            clockBox.enteredIntroAtWallTime = nil
        }

        let nextIntro = computeSkippableChapter(at: t)
        if let nextIntro, nextIntro.id != clockBox.trackedIntroChapterID {
            clockBox.trackedIntroChapterID = nextIntro.id
            clockBox.enteredIntroAtWallTime = Date()
        }
        if activeIntro != nextIntro {
            activeIntro = nextIntro
        }

        let eligible = computeNextEpisodeWindowEligible(at: t)
        if eligible && clockBox.enteredCreditsAtWallTime == nil {
            clockBox.enteredCreditsAtWallTime = Date()
        } else if !eligible {
            clockBox.enteredCreditsAtWallTime = nil
        }

        let nextVisible = computeShouldShowNextEpisodeButton(at: t, isWindowEligible: eligible)
        if showNextButton != nextVisible {
            showNextButton = nextVisible
        }
        syncActivePromptFlag()
    }

    private func computeSkippableChapter(at timeSeconds: Double) -> PlaybackChapter? {
        guard let ch = viewModel.chapters.first(where: {
            ($0.kind == .intro || $0.kind == .recap) &&
            $0.durationSeconds >= 8 &&
            timeSeconds >= $0.startSeconds &&
            timeSeconds < ($0.endSeconds - 2.0)
        }) else {
            return nil
        }
        guard !dismissedIntroChapterIDs.contains(ch.id) else { return nil }

        if focusedPromptControl != .skipIntro,
           !isBottomBarVisible,
           let entered = clockBox.enteredIntroAtWallTime,
           clockBox.trackedIntroChapterID == ch.id,
           Date().timeIntervalSince(entered) > 14.0 {
            return nil
        }
        return ch
    }

    private func computeNextEpisodeWindowEligible(at timeSeconds: Double) -> Bool {
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
            currentTime: timeSeconds,
            authoritativeDurationSeconds: authoritativeDuration,
            chapters: viewModel.chapters
        )
    }

    private func computeShouldShowNextEpisodeButton(at timeSeconds: Double, isWindowEligible: Bool) -> Bool {
        guard isWindowEligible, let session = viewModel.activeSession else {
            return false
        }
        let authoritativeDuration = SeriesFlowEligibility.authoritativeStreamDurationSeconds(
            engineDurationSeconds: viewModel.durationSeconds,
            declaredStreamDurationSeconds: session.stream.declaredDurationSeconds
        )
        let remaining = authoritativeDuration - timeSeconds
        if remaining > 30.0,
           focusedPromptControl != .playNext,
           !isBottomBarVisible,
           let entered = clockBox.enteredCreditsAtWallTime,
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
                activeIntro = nil
                focusedPromptControl = nil
                hasActivePrompt = false
                onReturnFocusToCanvas()
                viewModel.seekToPosition(target, exact: true)
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
        .lunaCinemaGlassSurface(
            shadowColor: roomAtmosphere.lampColor.opacity(0.14),
            shadowRadius: 24,
            shadowY: 10
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
                    viewModel.seekToPosition(0, exact: true)
                }
                .focused($focusedPromptControl, equals: .restartFromBeginning)
            }
        }
        .padding(.leading, 26)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .lunaCinemaGlassSurface(
            cornerRadius: LunaTokens.Radius.pill,
            shadowColor: roomAtmosphere.lampColor.opacity(0.14),
            shadowRadius: 20,
            shadowY: 8
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
        syncActivePromptFlag()
        scheduleResumeAutoHide(seconds: 4.5)
    }

    private func scheduleResumeAutoHide(seconds: TimeInterval) {
        resumeAutoHideSeconds = seconds
        isResumeAutoHideArmed = true
        resumeAutoHideNonce &+= 1
    }

    private func hideResumeBanner(returningFocus: Bool, silentFocusReturn: Bool = false) {
        isResumeAutoHideArmed = false
        activeResumeStartSeconds = nil
        if focusedPromptControl == .restartFromBeginning {
            focusedPromptControl = nil
        }
        syncActivePromptFlag()
        if returningFocus {
            if silentFocusReturn {
                onSilentReturnFocusToCanvas()
            } else {
                onReturnFocusToCanvas()
            }
        }
    }

    private func syncActivePromptFlag() {
        let nextActive = showNextButton || activeResumeStartSeconds != nil || activeIntro != nil
        if hasActivePrompt != nextActive {
            hasActivePrompt = nextActive
        }
    }

    private func dismissCurrentPrompt() {
        if activeResumeStartSeconds != nil {
            hideResumeBanner(returningFocus: true)
            return
        }
        if showNextButton, let sid = viewModel.activeSession?.sessionId {
            dismissedNextForSessionID = sid
            showNextButton = false
        } else if let intro = activeIntro {
            dismissedIntroChapterIDs.insert(intro.id)
            activeIntro = nil
        }
        focusedPromptControl = nil
        hasActivePrompt = false
        onReturnFocusToCanvas()
    }
}

@MainActor
private final class SeriesFlowClockBox {
    var currentTime: Double = 0
    var enteredIntroAtWallTime: Date?
    var trackedIntroChapterID: String?
    var enteredCreditsAtWallTime: Date?

    func reset(initialTime: Double) {
        currentTime = initialTime
        enteredIntroAtWallTime = nil
        trackedIntroChapterID = nil
        enteredCreditsAtWallTime = nil
    }
}
