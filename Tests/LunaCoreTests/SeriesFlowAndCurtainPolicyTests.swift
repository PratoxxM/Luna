import Foundation
import XCTest
@testable import LunaCore

final class SeriesFlowAndCurtainPolicyTests: XCTestCase {
    func testCompleteSeriesPromptDirectionalMatrix() {
        // 1. Neste episode: Spill nå (.playNext) -> Right MUST focus Skjul (.dismissNext), never seek +10s
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .playNext, direction: .right),
            .focusControl(.dismissNext)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .playNext, direction: .left),
            .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .playNext, direction: .up),
            .silentReturnToCanvas(dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .playNext, direction: .down),
            .focusQuickActions(dismissResumeBanner: false)
        )

        // 2. Neste episode: Skjul (.dismissNext) -> Left MUST focus Spill nå (.playNext); Right is no-op
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .left),
            .focusControl(.playNext)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .right),
            .noOp
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .up),
            .silentReturnToCanvas(dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .dismissNext, direction: .down),
            .focusQuickActions(dismissResumeBanner: false)
        )

        // 3. Hopp over intro (.skipIntro) -> Left/Right seek ±10s, Up returns silently, Down opens quick actions
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .skipIntro, direction: .left, hasActiveResumeBanner: false),
            .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .skipIntro, direction: .right, hasActiveResumeBanner: true),
            .seekRelativeAndReturnToCanvas(seconds: 10, dismissResumeBanner: true)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .skipIntro, direction: .up),
            .silentReturnToCanvas(dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .skipIntro, direction: .down, hasActiveResumeBanner: true),
            .focusQuickActions(dismissResumeBanner: true)
        )

        // 4. Start på nytt (.restartFromBeginning) -> Down returns silently to canvas; Left/Right seek ±10s
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .restartFromBeginning, direction: .up),
            .noOp
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .restartFromBeginning, direction: .down),
            .silentReturnToCanvas(dismissResumeBanner: false)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .restartFromBeginning, direction: .left),
            .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: true)
        )
        XCTAssertEqual(
            SeriesFlowPolicy.resolveMove(from: .restartFromBeginning, direction: .right),
            .seekRelativeAndReturnToCanvas(seconds: 10, dismissResumeBanner: true)
        )
    }

    func testOneClickAutoFocusOnSkipAndNextCardsWithoutStealingResumeBanner() {
        XCTAssertEqual(
            ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: false, hasActiveIntro: false, isResting: false),
            .none
        )
        XCTAssertEqual(
            ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: false, hasActiveIntro: true, isResting: false),
            .skipPrompt
        )
        XCTAssertEqual(
            ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: true, hasActiveIntro: true, isResting: false),
            .nextEpisodeCard
        )
        XCTAssertEqual(
            ActiveSeriesOverlayKind.resolve(showNextEpisodeCard: true, hasActiveIntro: true, isResting: true),
            .none
        )

        // Auto-focus activates 1-click primary button when revealing .skipPrompt or .nextEpisodeCard in clean playing state
        XCTAssertEqual(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none,
                newKind: .skipPrompt,
                isPlaying: true,
                isBottomBarVisible: false,
                isResting: false,
                isQuickPanelOpen: false,
                isQuickActionsModeActive: false,
                isScrubbing: false
            ),
            .skipIntro
        )
        XCTAssertEqual(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none,
                newKind: .nextEpisodeCard,
                isPlaying: true,
                isBottomBarVisible: false,
                isResting: false,
                isQuickPanelOpen: false,
                isQuickActionsModeActive: false,
                isScrubbing: false
            ),
            .playNext
        )

        // Never steals focus when paused, scrubbing, or navigating OSD / quick panel
        XCTAssertNil(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none,
                newKind: .nextEpisodeCard,
                isPlaying: false,
                isBottomBarVisible: false,
                isResting: false,
                isQuickPanelOpen: false,
                isQuickActionsModeActive: false,
                isScrubbing: false
            )
        )
        XCTAssertNil(
            SeriesFlowPolicy.autoFocusTargetOnOverlayTransition(
                previousKind: .none,
                newKind: .skipPrompt,
                isPlaying: true,
                isBottomBarVisible: true,
                isResting: false,
                isQuickPanelOpen: false,
                isQuickActionsModeActive: false,
                isScrubbing: false
            )
        )
    }

    func testTenSecondNextEpisodeCountdownFreezeCancelAndIdempotentZeroTrigger() {
        var state = NextEpisodeCountdownState()
        state.beginIfNeeded(autoPlayEnabled: true)
        XCTAssertEqual(state.remainingSeconds, 10)
        XCTAssertEqual(
            SeriesFlowPolicy.primaryNextButtonTitle(autoPlayEnabled: true, remainingSeconds: state.remainingSeconds),
            "Spill nå · 10 s"
        )
        XCTAssertEqual(
            SeriesFlowPolicy.primaryNextButtonTitle(autoPlayEnabled: false, remainingSeconds: state.remainingSeconds),
            "Spill nå"
        )

        // Frozen during pause, open quick panel, scrubbing, quick-action bar focus, or source switch
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: false, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))
        XCTAssertEqual(state.remainingSeconds, 10)
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: true, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))
        XCTAssertEqual(state.remainingSeconds, 10)
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: true, isQuickActionsModeActive: false, isSwitchingSource: false))
        XCTAssertEqual(state.remainingSeconds, 10)
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: true, isSwitchingSource: false))
        XCTAssertEqual(state.remainingSeconds, 10)

        // Active playback ticks 10 -> 1 without triggering early, then triggers ONCE at 0
        for expectedRemaining in stride(from: 9, through: 1, by: -1) {
            let fired = state.tickOneSecond(
                autoPlayEnabled: true,
                isPlaying: true,
                isQuickPanelOpen: false,
                isScrubbing: false,
                isQuickActionsModeActive: false,
                isSwitchingSource: false
            )
            XCTAssertFalse(fired)
            XCTAssertEqual(state.remainingSeconds, expectedRemaining)
        }
        XCTAssertEqual(
            SeriesFlowPolicy.primaryNextButtonTitle(autoPlayEnabled: true, remainingSeconds: state.remainingSeconds),
            "Spill nå · 1 s"
        )

        let zeroTrigger = state.tickOneSecond(
            autoPlayEnabled: true,
            isPlaying: true,
            isQuickPanelOpen: false,
            isScrubbing: false,
            isQuickActionsModeActive: false,
            isSwitchingSource: false
        )
        XCTAssertTrue(zeroTrigger)
        XCTAssertEqual(state.remainingSeconds, 0)
        XCTAssertTrue(state.didTriggerAutoAdvance)

        // Idempotent guard: subsequent ticks must NEVER trigger playNextEpisode a second time
        XCTAssertFalse(state.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))

        // Session cancellation via Skjul or Menu blocks countdown and EOF auto-advance for that session
        var cancelled = NextEpisodeCountdownState()
        cancelled.beginIfNeeded(autoPlayEnabled: true)
        cancelled.cancelForSession()
        XCTAssertTrue(cancelled.isCancelledForSession)
        XCTAssertNil(cancelled.remainingSeconds)
        cancelled.beginIfNeeded(autoPlayEnabled: true)
        XCTAssertNil(cancelled.remainingSeconds)
        XCTAssertFalse(cancelled.tickOneSecond(autoPlayEnabled: true, isPlaying: true, isQuickPanelOpen: false, isScrubbing: false, isQuickActionsModeActive: false, isSwitchingSource: false))

        XCTAssertFalse(
            SeriesFlowPolicy.shouldAutoPlayNextEpisodeOnEnded(
                autoPlayEnabled: true,
                hasNextEpisode: true,
                activeSessionID: "sess-ep4",
                dismissedNextForSessionID: "sess-ep4"
            )
        )
        XCTAssertTrue(
            SeriesFlowPolicy.shouldAutoPlayNextEpisodeOnEnded(
                autoPlayEnabled: true,
                hasNextEpisode: true,
                activeSessionID: "sess-ep4",
                dismissedNextForSessionID: "sess-other"
            )
        )
    }

    func testZeroRTTWarmStartCurtainGraceVsImmediateColdOrDisplaySwitch() {
        XCTAssertEqual(PlaybackCurtainPresentationPolicy.warmStartGraceMilliseconds, 180)
        XCTAssertEqual(PlaybackCurtainPresentationPolicy.warmStartGraceNanoseconds, 180_000_000)

        XCTAssertTrue(PlaybackCurtainPresentationPolicy.hasWarmPreparedSession(prepareToken: "tvs_warm_1", hasPreparedSession: false))
        XCTAssertTrue(PlaybackCurtainPresentationPolicy.hasWarmPreparedSession(prepareToken: nil, hasPreparedSession: true))
        XCTAssertFalse(PlaybackCurtainPresentationPolicy.hasWarmPreparedSession(prepareToken: "   ", hasPreparedSession: false))
        XCTAssertFalse(PlaybackCurtainPresentationPolicy.hasWarmPreparedSession(prepareToken: nil, hasPreparedSession: false))

        // Warm 0-RTT session without HDMI mode switch holds silent #000000 for 180 ms, then reveals curtain
        XCTAssertTrue(
            PlaybackCurtainPresentationPolicy.shouldHoldSilentBlackGrace(
                hasWarmPreparedSession: true,
                isAwaitingDisplaySwitch: false,
                graceElapsed: false
            )
        )
        XCTAssertFalse(
            PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(
                hasWarmPreparedSession: true,
                isAwaitingDisplaySwitch: false,
                graceElapsed: false
            )
        )
        XCTAssertTrue(
            PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(
                hasWarmPreparedSession: true,
                isAwaitingDisplaySwitch: false,
                graceElapsed: true
            )
        )

        // Cold start OR active HDMI display switch shows ResolvingCurtainView immediately at 0 ms
        XCTAssertTrue(
            PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(
                hasWarmPreparedSession: false,
                isAwaitingDisplaySwitch: false,
                graceElapsed: false
            )
        )
        XCTAssertTrue(
            PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(
                hasWarmPreparedSession: true,
                isAwaitingDisplaySwitch: true,
                graceElapsed: false
            )
        )
    }
}
