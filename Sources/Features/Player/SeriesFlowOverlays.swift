import SwiftUI
import AetherBridge

/// Isolated leaf view for series & movie continuity («Hopp over intro», «Hopp til etter rulletekst»,
/// «Neste episode» & «Start på nytt»).
///
/// - Automatically focuses newly revealed bottom-right prompts (`Hopp over intro` / `Neste episode`)
///   during normal playback for 1-click Center activation, while never auto-focusing `Start på nytt`.
/// - Keeps the `10 → 0 s` `Neste episode` countdown completely isolated inside `@State` (`0 Hz` on `PlayerContainerView`).
struct SeriesFlowOverlays: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    @FocusState var focusedPromptControl: SeriesPromptControl?
    @State var clockBox = SeriesFlowClockBox()
    @State var activeIntro: PlaybackChapter?
    @State var activeStingerChapter: PlaybackChapter?
    @State var activeStingerTargetSeconds: Double?
    @State var showNextButton: Bool = false
    @State var countdownState = NextEpisodeCountdownState()
    @State var lastOverlayKind: ActiveSeriesOverlayKind = .none
    @State var autoFocusTarget: SeriesPromptControl?
    @State var autoFocusNonce: Int = 0
    @State var dismissedIntroChapterIDs: Set<String> = []
    @State var handledResumeSessionID: String?
    @State var activeResumeStartSeconds: Double?
    @State var isResumeAutoHideArmed: Bool = false
    @State var resumeAutoHideNonce: Int = 0
    @State var resumeAutoHideSeconds: TimeInterval = 4.5

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
        let cardTransition: AnyTransition = reduceMotion
            ? .opacity
            : .scale(scale: 0.94).combined(with: .opacity)
        let activeSkip = activeIntro ?? activeStingerChapter

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
                    .animation(LunaFocusStyle.calmEaseOut(duration: 0.18, reduceMotion: reduceMotion), value: hasTopStatusToast)
                    .transition(cardTransition)
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
                        .transition(cardTransition)
                    } else if let skipChapter = activeSkip {
                        let stingerTarget = (activeStingerChapter?.id == skipChapter.id) ? activeStingerTargetSeconds : nil
                        SeriesSkipPromptPillView(
                            chapter: skipChapter,
                            isPromptFocused: focusedPromptControl == .skipIntro,
                            labelOverride: stingerTarget != nil ? LunaCopy.skipToPostCreditsTitle : nil,
                            focusBinding: $focusedPromptControl
                        ) {
                            let target = stingerTarget ?? max(chapterStartFloor(skipChapter), skipChapter.endSeconds - 0.15)
                            dismissedIntroChapterIDs.insert(skipChapter.id)
                            activeIntro = nil
                            activeStingerChapter = nil
                            activeStingerTargetSeconds = nil
                            focusedPromptControl = nil
                            syncOverlayAndPromptFlags()
                            onReturnFocusToCanvas()
                            viewModel.seekToPosition(target, exact: true)
                        }
                        .transition(cardTransition)
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.bottom, isBottomBarVisible ? 304 : 60)
            }
        }
        .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: showNextButton)
        .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: activeSkip?.id)
        .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: resumeSecs != nil)
        .opacity(isResting ? 0 : 1)
        .allowsHitTesting(!isResting)
        .disabled(isResting)
    }

    func chapterStartFloor(_ chapter: PlaybackChapter) -> Double {
        chapter.startSeconds + 1.0
    }

    func withPromptObservers<Content: View>(_ content: Content) -> some View {
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
            .onChange(of: (activeIntro ?? activeStingerChapter)?.id) { _, newID in
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
                guard viewModel.previewPlayheadOverrideSeconds == nil else { return }
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

    func withLifecycleObservers<Content: View>(_ content: Content) -> some View {
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
}

@MainActor
final class SeriesFlowClockBox {
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
