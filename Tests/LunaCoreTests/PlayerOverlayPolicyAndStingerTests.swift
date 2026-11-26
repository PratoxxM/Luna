import Foundation
import Testing
@testable import LunaCore

@Suite("M3 Stinger Eligibility, Subtitle Layout, OSD Visibility & Startup State")
struct PlayerOverlayPolicyAndStingerTests {
    @Test("SeriesFlowEligibility.postCreditsSkipTargetSeconds handles explicit postCredits, >=25s tail, and terminal credits")
    func postCreditsSkipEligibilityMatrix() {
        #expect(SeriesFlowEligibility.minPostCreditsTailSeconds == 25.0)

        let explicitChapters = [
            PlaybackChapter(id: "cr", index: 0, title: "Rulletekst", startSeconds: 6000, endSeconds: 6240, kind: .credits),
            PlaybackChapter(id: "stinger", index: 1, title: "Etter rulletekst", startSeconds: 6240, endSeconds: 6310, kind: .postCredits),
        ]
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 6050,
                authoritativeDurationSeconds: 6320,
                chapters: explicitChapters
            ) == 6240
        )
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5900,
                authoritativeDurationSeconds: 6320,
                chapters: explicitChapters
            ) == nil
        )
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 6245,
                authoritativeDurationSeconds: 6320,
                chapters: explicitChapters
            ) == nil
        )

        // Implicit >= 25 s post-credits tail when only .credits chapter is marked
        let implicitTail = [
            PlaybackChapter(id: "cr-imp", index: 0, title: "End Credits", startSeconds: 5900, endSeconds: 6150, kind: .credits),
        ]
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5950,
                authoritativeDurationSeconds: 6175,
                chapters: implicitTail
            ) == 6150
        )

        // < 25 s remaining after credits -> no stinger jump
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5950,
                authoritativeDurationSeconds: 6174.9,
                chapters: implicitTail
            ) == nil
        )

        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: .nan,
                authoritativeDurationSeconds: 6175,
                chapters: implicitTail
            ) == nil
        )
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5950,
                authoritativeDurationSeconds: .infinity,
                chapters: implicitTail
            ) == nil
        )
    }

    @Test("SubtitleOverlayLayout computes collision-free insets across OSD, series cards, quick-panel, and NerdHUD")
    func subtitleOverlayLayoutCombinations() {
        #expect(SubtitleOverlayLayout.skipPromptBottomInset == 168)
        #expect(SubtitleOverlayLayout.nextEpisodeBottomInset == 300)

        let clean = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .none
        )
        #expect(!clean.relocateToTop)
        #expect(clean.bottomInset == 74)

        let skip = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .skipPrompt
        )
        #expect(!skip.relocateToTop)
        #expect(skip.bottomInset == 168)

        let next = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .nextEpisodeCard
        )
        #expect(!next.relocateToTop)
        #expect(next.bottomInset == 300)

        let osdAndNextWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: false,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .nextEpisodeCard
        )
        #expect(osdAndNextWithHud.relocateToTop)
        #expect(osdAndNextWithHud.topInset == 340)
        #expect(Double(osdAndNextWithHud.topInset) > SubtitleOverlayLayout.nerdHUDProtectedLayoutRect.maxY)

        let quickPanelWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: true,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .none
        )
        #expect(quickPanelWithHud.relocateToTop)
        #expect(quickPanelWithHud.leadingInset == 856)
        let corridor = SubtitleLayoutRect(
            x: Double(quickPanelWithHud.leadingInset),
            y: Double(quickPanelWithHud.topInset),
            width: 1920 - Double(quickPanelWithHud.leadingInset) - Double(quickPanelWithHud.trailingInset),
            height: 120
        )
        #expect(!corridor.intersects(SubtitleOverlayLayout.nerdHUDProtectedLayoutRect))
    }

    @Test("PlayerOSDVisibilityPolicy enforces 12s OLED pause rest, quick-panel lock, and subtitle visibility")
    func osdVisibilityAndPauseRestRules() {
        #expect(PlayerOSDVisibilityPolicy.playingAutoHideSeconds == 4.0)
        #expect(PlayerOSDVisibilityPolicy.playingQuickActionsAutoHideSeconds == 7.0)
        #expect(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds == 12.0)

        #expect(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: false,
                isPaused: true,
                isPausedOSDResting: false
            )
        )
        #expect(
            !PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: false,
                isPaused: true,
                isPausedOSDResting: true
            )
        )
        #expect(
            PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
                isPaused: true,
                isPausedOSDResting: true,
                isScrubbing: false,
                isQuickPanelOpen: false
            )
        )
        #expect(
            !PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
                isPaused: true,
                isPausedOSDResting: true,
                isScrubbing: false,
                isQuickPanelOpen: true
            )
        )
        #expect(
            PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                hasFatalError: false,
                hasSuspendedFatalError: false,
                isPictureReadyForReveal: false,
                isPreviewMode: true
            )
        )
        #expect(
            !PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                hasFatalError: true,
                hasSuspendedFatalError: false,
                isPictureReadyForReveal: true
            )
        )
    }

    @Test("PlayerStartupState quantizes startup progress into whole percent buckets")
    @MainActor
    func playerStartupStateQuantization() {
        let state = PlayerStartupState()
        #expect(state.resolvePercent == 12)
        #expect(state.engineStartupPercentBucket == 50)
        #expect(state.engineStartupFraction == 0.5)

        state.updateEngineStartupFraction(0.642)
        #expect(state.engineStartupPercentBucket == 64)
        #expect(state.engineStartupFraction == 0.64)

        state.updateEngineStartupFraction(1.4)
        #expect(state.engineStartupPercentBucket == 100)
        state.updateEngineStartupFraction(-0.2)
        #expect(state.engineStartupPercentBucket == 0)
    }
}
