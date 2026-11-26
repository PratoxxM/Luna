import SwiftUI

extension SeriesFlowOverlays {
    func isTargetStillMounted(_ target: SeriesPromptControl) -> Bool {
        switch target {
        case .skipIntro:
            return (activeIntro != nil || activeStingerChapter != nil) && !showNextButton && !isResting
        case .playNext, .dismissNext:
            return showNextButton && viewModel.activeSession?.nextEpisode != nil && !isResting
        case .restartFromBeginning:
            return activeResumeStartSeconds != nil && !showNextButton && !isResting
        }
    }

    func triggerPlayNextEpisode(_ next: TvNextEpisodeSummary) {
        autoFocusTarget = nil
        focusedPromptControl = nil
        showNextButton = false
        hasActivePrompt = false
        activeOverlayKind = .none
        viewModel.playNextEpisode(next)
    }

    func handleFocusPromptRequest() {
        guard !isResting else { return }
        if activeResumeStartSeconds != nil && !showNextButton {
            requestPromptFocus(.restartFromBeginning)
        } else if showNextButton {
            requestPromptFocus(.playNext)
        } else if activeIntro != nil || activeStingerChapter != nil {
            requestPromptFocus(.skipIntro)
        }
    }

    func requestPromptFocus(_ target: SeriesPromptControl) {
        isPromptFocused = true
        autoFocusTarget = target
        focusedPromptControl = target
        autoFocusNonce &+= 1
    }

    func handleMoveCommand(_ direction: MoveCommandDirection) {
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
            if dismissResumeBanner { hideResumeBanner(returningFocus: false) }
            focusedPromptControl = nil
            onSilentReturnFocusToCanvas()

        case .focusQuickActions(let dismissResumeBanner):
            autoFocusTarget = nil
            if dismissResumeBanner { hideResumeBanner(returningFocus: false) }
            focusedPromptControl = nil
            onFocusQuickActions()

        case .seekRelativeAndReturnToCanvas(let seconds, let dismissResumeBanner):
            autoFocusTarget = nil
            if dismissResumeBanner { hideResumeBanner(returningFocus: false) }
            focusedPromptControl = nil
            onSeekRelative(seconds)

        case .noOp:
            break
        }
    }

    func resetForNewSession() {
        clockBox.reset(initialTime: viewModel.previewPlayheadOverrideSeconds ?? max(0, viewModel.engine.currentTime))
        dismissedNextForSessionID = nil
        dismissedIntroChapterIDs.removeAll()
        countdownState.resetForNewSession()
        lastOverlayKind = .none
        autoFocusTarget = nil
        isResumeAutoHideArmed = false
        activeResumeStartSeconds = nil
        activeIntro = nil
        activeStingerChapter = nil
        activeStingerTargetSeconds = nil
        showNextButton = false
        focusedPromptControl = nil
        isPromptFocused = false
        hasActivePrompt = false
        activeOverlayKind = .none
        armResumeBannerIfEligible()
        evaluateContinuityState(at: clockBox.currentTime)
    }

    func handleClockTick(_ t: Double) {
        guard viewModel.previewPlayheadOverrideSeconds == nil else { return }
        let hasContinuityTargets = viewModel.activeSession?.nextEpisode != nil ||
            viewModel.chapters.contains(where: {
                $0.kind == .intro || $0.kind == .recap || $0.kind == .credits || $0.kind == .postCredits
            })
        guard hasContinuityTargets else { return }
        guard abs(t - clockBox.currentTime) >= 0.5 || t < 1.0 else { return }
        clockBox.currentTime = t
        evaluateContinuityState(at: t)
    }

    // MARK: - Continuity & Stinger Evaluation

    func evaluateContinuityState(at t: Double) {
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

        let stingerEval = computePostCreditsStinger(at: t)
        let eligible = computeNextEpisodeWindowEligible(at: t)
        if eligible && clockBox.enteredCreditsAtWallTime == nil {
            clockBox.enteredCreditsAtWallTime = Date()
        } else if !eligible {
            clockBox.enteredCreditsAtWallTime = nil
        }

        var nextVisible = computeShouldShowNextEpisodeButton(at: t, isWindowEligible: eligible)
        let hasExplicitPostCredits = viewModel.chapters.contains { $0.kind == .postCredits }
        if let stinger = stingerEval,
           (viewModel.activeSession?.nextEpisode == nil || hasExplicitPostCredits) {
            nextVisible = false
            if stinger.chapter.id != clockBox.trackedIntroChapterID {
                clockBox.trackedIntroChapterID = stinger.chapter.id
                clockBox.enteredIntroAtWallTime = Date()
            }
            if activeStingerChapter != stinger.chapter || activeStingerTargetSeconds != stinger.target {
                activeStingerChapter = stinger.chapter
                activeStingerTargetSeconds = stinger.target
            }
        } else if activeStingerChapter != nil || activeStingerTargetSeconds != nil {
            activeStingerChapter = nil
            activeStingerTargetSeconds = nil
        }

        if showNextButton != nextVisible {
            showNextButton = nextVisible
        }
        syncOverlayAndPromptFlags()
    }

    func computeSkippableChapter(at timeSeconds: Double) -> PlaybackChapter? {
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

    private func computePostCreditsStinger(at timeSeconds: Double) -> (chapter: PlaybackChapter, target: Double)? {
        let authoritativeDuration = SeriesFlowEligibility.authoritativeStreamDurationSeconds(
            engineDurationSeconds: viewModel.durationSeconds,
            declaredStreamDurationSeconds: viewModel.activeSession?.stream.declaredDurationSeconds
        )
        guard let target = SeriesFlowEligibility.postCreditsSkipTargetSeconds(
            currentTime: timeSeconds,
            authoritativeDurationSeconds: authoritativeDuration,
            chapters: viewModel.chapters
        ),
        let creditsChapter = viewModel.chapters.first(where: {
            $0.kind == .credits && timeSeconds >= $0.startSeconds && timeSeconds < ($0.endSeconds - 1.5)
        }),
        !dismissedIntroChapterIDs.contains(creditsChapter.id) else {
            return nil
        }
        if focusedPromptControl != .skipIntro,
           !isBottomBarVisible,
           let entered = clockBox.enteredIntroAtWallTime,
           clockBox.trackedIntroChapterID == creditsChapter.id,
           Date().timeIntervalSince(entered) > 14.0 {
            return nil
        }
        return (creditsChapter, target)
    }

    func computeNextEpisodeWindowEligible(at timeSeconds: Double) -> Bool {
        guard let session = viewModel.activeSession else { return false }
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

    func computeShouldShowNextEpisodeButton(at timeSeconds: Double, isWindowEligible: Bool) -> Bool {
        guard isWindowEligible, let session = viewModel.activeSession else { return false }
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

    func armResumeBannerIfEligible() {
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

    func scheduleResumeAutoHide(seconds: TimeInterval) {
        resumeAutoHideSeconds = seconds
        isResumeAutoHideArmed = true
        resumeAutoHideNonce &+= 1
    }

    func hideResumeBanner(returningFocus: Bool, silentFocusReturn: Bool = false) {
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

    func syncOverlayAndPromptFlags() {
        let hasSkip = (activeIntro != nil || activeStingerChapter != nil)
        let nextKind = ActiveSeriesOverlayKind.resolve(
            showNextEpisodeCard: showNextButton && viewModel.activeSession?.nextEpisode != nil,
            hasActiveIntro: hasSkip,
            isResting: isResting
        )
        let prevKind = lastOverlayKind
        if activeOverlayKind != nextKind { activeOverlayKind = nextKind }
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

        let nextActive = showNextButton || activeResumeStartSeconds != nil || hasSkip
        if hasActivePrompt != nextActive { hasActivePrompt = nextActive }
    }

    func dismissCurrentPrompt() {
        autoFocusTarget = nil
        if activeResumeStartSeconds != nil && !showNextButton {
            hideResumeBanner(returningFocus: true)
            return
        }
        if showNextButton, let sid = viewModel.activeSession?.sessionId {
            countdownState.cancelForSession()
            dismissedNextForSessionID = sid
            showNextButton = false
        } else if let skip = activeIntro ?? activeStingerChapter {
            dismissedIntroChapterIDs.insert(skip.id)
            activeIntro = nil
            activeStingerChapter = nil
            activeStingerTargetSeconds = nil
        }
        focusedPromptControl = nil
        syncOverlayAndPromptFlags()
        onSilentReturnFocusToCanvas()
    }
}
