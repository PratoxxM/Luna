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

/// Isolated leaf view for series continuity («Hopp over intro», «Neste episode» & «Start på nytt»).
///
/// - Automatically focuses newly revealed bottom-right series prompts (`Hopp over intro` / `Neste episode`)
///   during normal playback for 1-click Center activation, while never auto-focusing `Start på nytt`.
/// - Keeps the `10 → 0 s` `Neste episode` countdown completely isolated inside `@State` (`0 Hz` on `PlayerContainerView`).
struct SeriesFlowOverlays: View {
    let viewModel: PlayerViewModel
    var client: LunaCoreClient? = nil
    let isBottomBarVisible: Bool
    var isResting: Bool = false
    var isQuickPanelOpen: Bool = false
    var isQuickActionsModeActive: Bool = false
    var hasTopStatusToast: Bool = false
    @Binding var activeOverlayKind: ActiveSeriesOverlayKind
    @Binding var hasActivePrompt: Bool
    @Binding var isPromptFocused: Bool
    @Binding var dismissedNextForSessionID: String?
    let dismissNonce: Int
    var focusPromptNonce: Int = 0
    var onReturnFocusToCanvas: () -> Void = {}
    var onSilentReturnFocusToCanvas: () -> Void = {}
    var onFocusQuickActions: () -> Void = {}
    var onSeekRelative: (Double) -> Void = { _ in }

    @FocusState private var focusedPromptControl: SeriesPromptControl?
    @State private var clockBox = SeriesFlowClockBox()
    @State private var activeIntro: PlaybackChapter?
    @State private var showNextButton: Bool = false
    @State private var countdownState = NextEpisodeCountdownState()
    @State private var lastOverlayKind: ActiveSeriesOverlayKind = .none
    @State private var autoFocusTarget: SeriesPromptControl?
    @State private var autoFocusNonce: Int = 0
    @State private var dismissedIntroChapterIDs: Set<String> = []
    @State private var handledResumeSessionID: String?
    @State private var activeResumeStartSeconds: Double?
    @State private var isResumeAutoHideArmed: Bool = false
    @State private var resumeAutoHideNonce: Int = 0
    @State private var resumeAutoHideSeconds: TimeInterval = 4.5

    var body: some View {
        withLifecycleObservers(
            withPromptObservers(overlayCanvas)
        )
    }

    @ViewBuilder
    private var overlayCanvas: some View {
        let resumeSecs = showNextButton ? nil : activeResumeStartSeconds
        let resumeTopPad = hasTopStatusToast
            ? SeriesResumeBannerView.shiftedBelowStatusToastTopPadding
            : SeriesResumeBannerView.standardTopPadding

        ZStack {
            if let resumeSecs {
                VStack {
                    SeriesResumeBannerView(
                        seconds: resumeSecs,
                        focusBinding: $focusedPromptControl
                    ) {
                        hideResumeBanner(returningFocus: true)
                        viewModel.seekToPosition(0, exact: true)
                    }
                    .padding(.top, resumeTopPad)
                    .animation(.easeOut(duration: 0.18), value: hasTopStatusToast)
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
                        SeriesNextEpisodeCardView(
                            next: next,
                            seriesTitle: viewModel.activeSession?.item.seriesTitle,
                            client: client ?? viewModel.activeClient,
                            autoPlayEnabled: viewModel.comfort.autoPlayNextEpisode,
                            remainingCountdownSeconds: countdownState.remainingSeconds,
                            focusBinding: $focusedPromptControl,
                            onPlayNow: {
                                triggerPlayNextEpisode(next)
                            },
                            onDismiss: {
                                dismissCurrentPrompt()
                            }
                        )
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    } else if let intro = activeIntro {
                        SeriesSkipPromptPillView(
                            chapter: intro,
                            isPromptFocused: focusedPromptControl == .skipIntro,
                            focusBinding: $focusedPromptControl
                        ) {
                            let target = max(chapterStartFloor(intro), intro.endSeconds - 0.15)
                            dismissedIntroChapterIDs.insert(intro.id)
                            activeIntro = nil
                            focusedPromptControl = nil
                            syncOverlayAndPromptFlags()
                            onReturnFocusToCanvas()
                            viewModel.seekToPosition(target, exact: true)
                        }
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
    }

    private func chapterStartFloor(_ chapter: PlaybackChapter) -> Double {
        chapter.startSeconds + 1.0
    }

    private func withPromptObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: focusedPromptControl) { _, newFocus in
                isPromptFocused = (newFocus != nil)
                if newFocus == .restartFromBeginning {
                    scheduleResumeAutoHide(seconds: 6.0)
                }
                evaluateContinuityState(at: clockBox.currentTime)
            }
            .onChange(of: focusPromptNonce) { _, _ in
                handleFocusPromptRequest()
            }
            .onChange(of: isResting) { _, resting in
                if resting {
                    autoFocusTarget = nil
                    focusedPromptControl = nil
                }
                syncOverlayAndPromptFlags()
            }
            .onChange(of: showNextButton) { _, visible in
                if visible {
                    countdownState.beginIfNeeded(autoPlayEnabled: viewModel.comfort.autoPlayNextEpisode)
                } else {
                    countdownState.hideWithoutCancellingSession()
                    if focusedPromptControl == .playNext || focusedPromptControl == .dismissNext {
                        autoFocusTarget = nil
                        focusedPromptControl = nil
                        onReturnFocusToCanvas()
                    }
                }
                syncOverlayAndPromptFlags()
            }
            .onChange(of: viewModel.comfort.autoPlayNextEpisode) { _, enabled in
                if showNextButton {
                    countdownState.beginIfNeeded(autoPlayEnabled: enabled)
                }
            }
            .onChange(of: activeIntro?.id) { _, newID in
                if newID == nil && focusedPromptControl == .skipIntro {
                    autoFocusTarget = nil
                    focusedPromptControl = nil
                    onReturnFocusToCanvas()
                }
                syncOverlayAndPromptFlags()
            }
            .onMoveCommand(perform: handleMoveCommand)
            .onChange(of: dismissNonce) { _, _ in
                dismissCurrentPrompt()
            }
            .task(id: autoFocusNonce) {
                guard autoFocusNonce > 0, let target = autoFocusTarget, !isResting else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if isTargetStillMounted(target), focusedPromptControl != target {
                    focusedPromptControl = target
                }
                for delayNs: UInt64 in [16_000_000, 48_000_000] {
                    try? await Task.sleep(nanoseconds: delayNs)
                    guard !Task.isCancelled, autoFocusTarget == target, isTargetStillMounted(target) else { return }
                    if focusedPromptControl != target {
                        focusedPromptControl = target
                    } else {
                        return
                    }
                }
            }
            .task(id: showNextButton ? "\(viewModel.activeSession?.sessionId ?? "")#\(viewModel.comfort.autoPlayNextEpisode)" : "off") {
                guard showNextButton, viewModel.comfort.autoPlayNextEpisode else { return }
                countdownState.beginIfNeeded(autoPlayEnabled: true)
                while !Task.isCancelled && showNextButton {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, showNextButton, let next = viewModel.activeSession?.nextEpisode else {
                        return
                    }
                    let shouldAdvance = countdownState.tickOneSecond(
                        autoPlayEnabled: viewModel.comfort.autoPlayNextEpisode,
                        isPlaying: viewModel.playbackPhase == .playing,
                        isQuickPanelOpen: isQuickPanelOpen,
                        isScrubbing: viewModel.isScrubbing,
                        isQuickActionsModeActive: isQuickActionsModeActive,
                        isSwitchingSource: viewModel.isSwitchingSource
                    )
                    if shouldAdvance {
                        triggerPlayNextEpisode(next)
                        return
                    }
                }
            }
    }

    private func withLifecycleObservers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                clockBox.currentTime = viewModel.previewPlayheadOverrideSeconds ?? max(0, viewModel.engine.currentTime)
                armResumeBannerIfEligible()
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
            .onChange(of: viewModel.activeSession?.sessionId) { _, _ in
                resetForNewSession()
            }
            .task(id: isResumeAutoHideArmed ? resumeAutoHideNonce : 0) {
                guard isResumeAutoHideArmed, resumeAutoHideNonce > 0 else { return }
                let ns = UInt64(resumeAutoHideSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                let wasFocused = (focusedPromptControl == .restartFromBeginning)
                hideResumeBanner(returningFocus: wasFocused, silentFocusReturn: true)
            }
            .onReceive(viewModel.engine.clock.$currentTime, perform: handleClockTick)
            .onDisappear {
                isResumeAutoHideArmed = false
                activeResumeStartSeconds = nil
                autoFocusTarget = nil
                focusedPromptControl = nil
                isPromptFocused = false
                hasActivePrompt = false
                activeOverlayKind = .none
            }
    }

    private func isTargetStillMounted(_ target: SeriesPromptControl) -> Bool {
        switch target {
        case .skipIntro:
            return activeIntro != nil && !showNextButton && !isResting
        case .playNext, .dismissNext:
            return showNextButton && viewModel.activeSession?.nextEpisode != nil && !isResting
        case .restartFromBeginning:
            return activeResumeStartSeconds != nil && !showNextButton && !isResting
        }
    }

    private func triggerPlayNextEpisode(_ next: TvNextEpisodeSummary) {
        autoFocusTarget = nil
        focusedPromptControl = nil
        showNextButton = false
        hasActivePrompt = false
        activeOverlayKind = .none
        viewModel.playNextEpisode(next)
    }

    private func handleFocusPromptRequest() {
        guard !isResting else { return }
        if activeResumeStartSeconds != nil && !showNextButton {
            requestPromptFocus(.restartFromBeginning)
        } else if showNextButton {
            requestPromptFocus(.playNext)
        } else if activeIntro != nil {
            requestPromptFocus(.skipIntro)
        }
    }

    private func requestPromptFocus(_ target: SeriesPromptControl) {
        isPromptFocused = true
        autoFocusTarget = target
        focusedPromptControl = target
        autoFocusNonce &+= 1
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard let currentControl = focusedPromptControl else { return }
        let mappedDirection: SeriesPromptMoveDirection
        switch direction {
        case .up: mappedDirection = .up
        case .down: mappedDirection = .down
        case .left: mappedDirection = .left
        case .right: mappedDirection = .right
        @unknown default: return
        }

        let outcome = SeriesFlowPolicy.resolveMove(
            from: currentControl,
            direction: mappedDirection,
            hasActiveResumeBanner: activeResumeStartSeconds != nil && !showNextButton
        )

        switch outcome {
        case .focusControl(let nextControl):
            autoFocusTarget = nextControl
            focusedPromptControl = nextControl

        case .silentReturnToCanvas(let dismissResumeBanner):
            autoFocusTarget = nil
            if dismissResumeBanner {
                hideResumeBanner(returningFocus: false)
            }
            focusedPromptControl = nil
            onSilentReturnFocusToCanvas()

        case .focusQuickActions(let dismissResumeBanner):
            autoFocusTarget = nil
            if dismissResumeBanner {
                hideResumeBanner(returningFocus: false)
            }
            focusedPromptControl = nil
            onFocusQuickActions()

        case .seekRelativeAndReturnToCanvas(let seconds, let dismissResumeBanner):
            autoFocusTarget = nil
            if dismissResumeBanner {
                hideResumeBanner(returningFocus: false)
            }
            focusedPromptControl = nil
            onSeekRelative(seconds)

        case .noOp:
            break
        }
    }

    private func resetForNewSession() {
        clockBox.reset(initialTime: viewModel.previewPlayheadOverrideSeconds ?? max(0, viewModel.engine.currentTime))
        dismissedNextForSessionID = nil
        dismissedIntroChapterIDs.removeAll()
        countdownState.resetForNewSession()
        lastOverlayKind = .none
        autoFocusTarget = nil
        isResumeAutoHideArmed = false
        activeResumeStartSeconds = nil
        activeIntro = nil
        showNextButton = false
        focusedPromptControl = nil
        isPromptFocused = false
        hasActivePrompt = false
        activeOverlayKind = .none
        armResumeBannerIfEligible()
        evaluateContinuityState(at: clockBox.currentTime)
    }

    private func handleClockTick(_ t: Double) {
        guard viewModel.previewPlayheadOverrideSeconds == nil else { return }
        let hasContinuityTargets = viewModel.activeSession?.nextEpisode != nil ||
            viewModel.chapters.contains(where: { $0.kind == .intro || $0.kind == .recap || $0.kind == .credits })
        guard hasContinuityTargets else { return }
        guard abs(t - clockBox.currentTime) >= 0.5 || t < 1.0 else { return }
        clockBox.currentTime = t
        evaluateContinuityState(at: t)
    }

    // MARK: - Continuity Evaluation

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
        syncOverlayAndPromptFlags()
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
        let isNextCardFocused = (focusedPromptControl == .playNext || focusedPromptControl == .dismissNext)
        if remaining > 30.0,
           !viewModel.comfort.autoPlayNextEpisode,
           !isNextCardFocused,
           !isBottomBarVisible,
           let entered = clockBox.enteredCreditsAtWallTime,
           Date().timeIntervalSince(entered) > SeriesFlowEligibility.passiveCreditsDisplayCapSeconds {
            return false
        }
        return true
    }

    // MARK: - Dismissal & Auto-Focus Sync

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
        syncOverlayAndPromptFlags()
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
        syncOverlayAndPromptFlags()
        if returningFocus {
            if silentFocusReturn {
                onSilentReturnFocusToCanvas()
            } else {
                onReturnFocusToCanvas()
            }
        }
    }

    private func syncOverlayAndPromptFlags() {
        let nextKind = ActiveSeriesOverlayKind.resolve(
            showNextEpisodeCard: showNextButton && viewModel.activeSession?.nextEpisode != nil,
            hasActiveIntro: activeIntro != nil,
            isResting: isResting
        )
        let prevKind = lastOverlayKind
        if activeOverlayKind != nextKind {
            activeOverlayKind = nextKind
        }
        if prevKind != nextKind {
            lastOverlayKind = nextKind
            if let target = SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: prevKind,
                newKind: nextKind,
                isPlaying: viewModel.playbackPhase == .playing,
                isBottomBarVisible: isBottomBarVisible,
                isResting: isResting,
                isQuickPanelOpen: isQuickPanelOpen,
                isQuickActionsModeActive: isQuickActionsModeActive,
                isScrubbing: viewModel.isScrubbing
            ) {
                requestPromptFocus(target)
            }
        }

        let nextActive = showNextButton || activeResumeStartSeconds != nil || activeIntro != nil
        if hasActivePrompt != nextActive {
            hasActivePrompt = nextActive
        }
    }

    private func dismissCurrentPrompt() {
        autoFocusTarget = nil
        if activeResumeStartSeconds != nil && !showNextButton {
            hideResumeBanner(returningFocus: true)
            return
        }
        if showNextButton, let sid = viewModel.activeSession?.sessionId {
            countdownState.cancelForSession()
            dismissedNextForSessionID = sid
            showNextButton = false
        } else if let intro = activeIntro {
            dismissedIntroChapterIDs.insert(intro.id)
            activeIntro = nil
        }
        focusedPromptControl = nil
        syncOverlayAndPromptFlags()
        onSilentReturnFocusToCanvas()
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
