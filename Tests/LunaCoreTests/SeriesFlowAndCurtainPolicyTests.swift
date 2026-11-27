import Foundation
import XCTest
@testable import LunaCore

final class SeriesFlowAndCurtainPolicyTests: XCTestCase {
    // MARK: - SeriesFlowPolicy Directional Matrix, Auto-Focus & 10s Countdown

    func testSeriesFlowDirectionalMatrixAutoFocusAndCountdown() {
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .playNext, direction: .right), .focusControl(.dismissNext))
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .playNext, direction: .left), .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: false))
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .playNext, direction: .down), .focusQuickActions(dismissResumeBanner: false))
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .left), .focusControl(.playNext))
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .right), .noOp)
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .skipIntro, direction: .right, hasActiveResumeBanner: true), .seekRelativeAndReturnToCanvas(seconds: 10, dismissResumeBanner: true))
        XCTAssertEqual(SeriesFlowPolicy.resolveMove(from: .restartFromBeginning, direction: .down), .silentReturnToCanvas(dismissResumeBanner: false))

        XCTAssertEqual(ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: true, hasActiveIntro: true, isResting: false), .nextEpisodeCard)
        XCTAssertEqual(ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: true, hasActiveIntro: true, isResting: true), .none)

        XCTAssertEqual(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none, newKind: .skipPrompt, isPlaying: true, isBottomBarVisible: false,
                isResting: false, isQuickPanelOpen: false, isQuickActionsModeActive: false, isScrubbing: false
            ),
            .skipIntro
        )
        XCTAssertNil(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none, newKind: .nextEpisodeCard, isPlaying: false, isBottomBarVisible: false,
                isResting: false, isQuickPanelOpen: false, isQuickActionsModeActive: false, isScrubbing: false
            )
        )

        var state = NextEpisodeCountdownState()
        state.beginIfNeeded(autoPlayEnabled: true)
        XCTAssertEqual(SeriesFlowPolicy.primaryNextButtonTitle(autoPlayEnabled: true, remainingSeconds: state.remainingSeconds), "Spill nå · 10 s")
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: false, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))
        for expected in stride(from: 9, through: 1, by: -1) {
            XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))
            XCTAssertEqual(state.remainingSeconds, expected)
        }
        XCTAssertTrue(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))

        state.cancelForSession()
        XCTAssertFalse(SeriesFlowPolicy.shouldAutoPlayNextEpisodeOnEnded(autoPlayEnabled: true, hasNextEpisode: true, activeSessionID: "s1", dismissedNextForSessionID: "s1"))
    }

    // MARK: - SeriesFlowEligibility: Duration, Resume Banner, Credits Prompt & Post-Credits Stingers

    func testSeriesFlowEligibilityDurationResumeCreditsAndStingers() throws {
        XCTAssertEqual(SeriesFlowEligibility.authoritativeStreamDurationSeconds(engineDurationSeconds: 2642.5, declaredStreamDurationSeconds: 2640.0), 2642.5)
        XCTAssertEqual(SeriesFlowEligibility.authoritativeStreamDurationSeconds(engineDurationSeconds: 0, declaredStreamDurationSeconds: 2640.0), 2640.0)
        XCTAssertEqual(SeriesFlowEligibility.authoritativeStreamDurationSeconds(engineDurationSeconds: -1, declaredStreamDurationSeconds: 0), 0)

        XCTAssertNil(SeriesFlowEligibility.initialResumeBannerSeconds(sessionId: nil, streamStartPositionSeconds: 1200, requestStartPositionSeconds: 1200, shownForSessionID: nil))
        XCTAssertNil(SeriesFlowEligibility.initialResumeBannerSeconds(sessionId: "s1", streamStartPositionSeconds: 10, requestStartPositionSeconds: nil, shownForSessionID: nil))
        XCTAssertEqual(SeriesFlowEligibility.initialResumeBannerSeconds(sessionId: "s1", streamStartPositionSeconds: 1390, requestStartPositionSeconds: 600, shownForSessionID: nil), 1390)
        XCTAssertNil(SeriesFlowEligibility.initialResumeBannerSeconds(sessionId: "s1", streamStartPositionSeconds: 1390, requestStartPositionSeconds: 1390, shownForSessionID: "s1"))

        // Multi-minute credits window & bogus early/mid credits rejection
        let longCredits: [PlaybackChapter] = [
            PlaybackChapter(id: "early", index: 0, title: "Outro", startSeconds: 45, endSeconds: 90, kind: .credits),
            PlaybackChapter(id: "mid", index: 1, title: "Outro", startSeconds: 1400, endSeconds: 1500, kind: .credits),
            PlaybackChapter(id: "main", index: 2, title: "End Credits", startSeconds: 2280, endSeconds: 2640, kind: .credits),
            PlaybackChapter(id: "stinger", index: 3, title: "Preview", startSeconds: 2640, endSeconds: 2700, kind: .chapter),
        ]
        XCTAssertFalse(SeriesFlowEligibility.shouldShowNextEpisodePrompt(hasNextEpisode: true, isDismissedForCurrentSession: false, currentTime: 1450, authoritativeDurationSeconds: 2700, chapters: longCredits))
        XCTAssertTrue(SeriesFlowEligibility.shouldShowNextEpisodePrompt(hasNextEpisode: true, isDismissedForCurrentSession: false, currentTime: 2280, authoritativeDurationSeconds: 2700, chapters: longCredits))
        XCTAssertFalse(SeriesFlowEligibility.shouldShowNextEpisodePrompt(hasNextEpisode: true, isDismissedForCurrentSession: false, currentTime: 2650, authoritativeDurationSeconds: 2700, chapters: longCredits))
        XCTAssertTrue(SeriesFlowEligibility.shouldShowNextEpisodePrompt(hasNextEpisode: true, isDismissedForCurrentSession: false, currentTime: 2685, authoritativeDurationSeconds: 2700, chapters: []))

        // Post-credits stinger skip: explicit trailing, overlapping mid-credits, implicit >= 25s tail & terminal credits
        let trailing = [
            PlaybackChapter(id: "cr", index: 0, title: "Rulletekst", startSeconds: 6000, endSeconds: 6240, kind: .credits),
            PlaybackChapter(id: "st", index: 1, title: "Etter rulletekst", startSeconds: 6240, endSeconds: 6310, kind: .postCredits),
        ]
        XCTAssertEqual(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6050, authoritativeDurationSeconds: 6320, chapters: trailing), 6240)
        XCTAssertNil(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6245, authoritativeDurationSeconds: 6320, chapters: trailing))

        let midStingerProbes = try JSONDecoder().decode([TvProbeChapter].self, from: Data(#"""
        [{"id":"m","title":"Ch 1","startSeconds":0,"endSeconds":6000,"kind":"chapter"},{"id":"cr","title":"End Credits","startSeconds":6000,"endSeconds":6320,"kind":"credits"},{"id":"ps","title":"Mid-Credits Stinger","startSeconds":6200,"endSeconds":6260,"kind":"post_credits"}]
        """#.utf8))
        let midMerged = PlaybackChapter.mergeRaw(probeChapters: midStingerProbes, engineChapters: [], mediaDuration: 6320)
        XCTAssertEqual(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6020, authoritativeDurationSeconds: 6320, chapters: midMerged), 6200)
        XCTAssertNil(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6200, authoritativeDurationSeconds: 6320, chapters: midMerged))

        let implicitTail = [PlaybackChapter(id: "imp", index: 0, title: "End Credits", startSeconds: 5900, endSeconds: 6150, kind: .credits)]
        XCTAssertEqual(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 5950, authoritativeDurationSeconds: 6175, chapters: implicitTail), 6150)
        XCTAssertNil(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 5950, authoritativeDurationSeconds: 6174.9, chapters: implicitTail))
        XCTAssertNil(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: .nan, authoritativeDurationSeconds: 6175, chapters: implicitTail))
    }

    // MARK: - SubtitleOverlayLayout, PlayerOSDVisibilityPolicy, PlayerStartupState & Curtain Watchdog

    @MainActor
    func testSubtitleLayoutOSDVisibilityStartupStateAndCurtainWatchdog() {
        let clean = SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: false, isQuickPanelOpen: false, isNerdHUDVisible: false, activeSeriesOverlay: .none)
        XCTAssertEqual(clean.bottomInset, 74)
        XCTAssertFalse(clean.relocateToTop)

        let skip = SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: false, isQuickPanelOpen: false, isNerdHUDVisible: false, activeSeriesOverlay: .skipPrompt)
        XCTAssertEqual(skip.bottomInset, 168)
        let next = SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: false, isQuickPanelOpen: false, isNerdHUDVisible: false, activeSeriesOverlay: .nextEpisodeCard)
        XCTAssertEqual(next.bottomInset, 300)

        let qpWithHud = SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: true, isQuickPanelOpen: true, isNerdHUDVisible: true, activeSeriesOverlay: .none)
        XCTAssertTrue(qpWithHud.relocateToTop)
        XCTAssertEqual(qpWithHud.leadingInset, 856)
        let corridor = SubtitleLayoutRect(
            x: Double(qpWithHud.leadingInset),
            y: Double(qpWithHud.topInset),
            width: 1920 - Double(qpWithHud.leadingInset) - Double(qpWithHud.trailingInset),
            height: 120
        )
        XCTAssertFalse(corridor.intersects(SubtitleOverlayLayout.nerdHUDProtectedLayoutRect))

        XCTAssertEqual(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds, 12.0)
        XCTAssertTrue(PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(isPaused: true, isPausedOSDResting: true, isScrubbing: false, isQuickPanelOpen: false))
        XCTAssertFalse(PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(isPaused: true, isPausedOSDResting: true, isScrubbing: false, isQuickPanelOpen: true))
        XCTAssertFalse(PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(hasFatalError: true, hasSuspendedFatalError: false, isPictureReadyForReveal: true))

        let startup = PlayerStartupState()
        startup.updateEngineStartupFraction(0.642)
        XCTAssertEqual(startup.engineStartupPercentBucket, 64)
        startup.updateEngineStartupFraction(1.4)
        XCTAssertEqual(startup.engineStartupPercentBucket, 100)
        startup.updateEngineStartupFraction(-0.2)
        XCTAssertEqual(startup.engineStartupPercentBucket, 0)

        // Curtain warm-start 180 ms grace vs immediate cold/HDMI display switch
        XCTAssertEqual(PlaybackCurtainPresentationPolicy.warmStartGraceMilliseconds, 180)
        XCTAssertTrue(PlaybackCurtainPresentationPolicy.shouldHoldSilentBlackGrace(hasWarmPreparedSession: true, isAwaitingDisplaySwitch: false, graceElapsed: false))
        XCTAssertTrue(PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(hasWarmPreparedSession: false, isAwaitingDisplaySwitch: false, graceElapsed: false))
        XCTAssertTrue(PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(hasWarmPreparedSession: true, isAwaitingDisplaySwitch: true, graceElapsed: false))

        // Curtain watchdog readiness & held-picture fallback bounds
        XCTAssertFalse(PlaybackCurtainWatchdog.isPictureReadyForReveal(hasFatalError: true, isSwitchingSource: true, isResolving: false, isRestoringFromBackground: false, needsForegroundVideoRestore: false, firstFrameFallbackUnlocked: true, hasFirstFrameReadyForDisplay: true, isAwaitingDisplaySwitch: false, isReplacingSourceItem: false, isHoldingOutgoingPicture: true))
        XCTAssertTrue(PlaybackCurtainWatchdog.isPictureReadyForReveal(hasFatalError: false, isSwitchingSource: true, isResolving: true, isRestoringFromBackground: false, needsForegroundVideoRestore: false, firstFrameFallbackUnlocked: false, hasFirstFrameReadyForDisplay: false, isAwaitingDisplaySwitch: true, isReplacingSourceItem: true, isHoldingOutgoingPicture: true))
        XCTAssertFalse(PlaybackCurtainWatchdog.isPictureReadyForReveal(hasFatalError: false, isSwitchingSource: true, isResolving: false, isRestoringFromBackground: false, needsForegroundVideoRestore: false, firstFrameFallbackUnlocked: false, hasFirstFrameReadyForDisplay: false, isAwaitingDisplaySwitch: false, isReplacingSourceItem: true, isHoldingOutgoingPicture: false))
        XCTAssertEqual(PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: 2.5), 2.5, accuracy: 0.001)
        XCTAssertEqual(PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: .nan), 5.0, accuracy: 0.001)
    }
}
