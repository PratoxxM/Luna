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

    func testUpscaleSummaryFormatterCoversActiveAndInactiveCombinations() {
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1920,
                    sourceHeight: 1080,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .lanczos
                ),
                disabledReason: nil,
                lowResUpscaleMode: .off,
                upscalesFullHDVideo: true,
                isSDR: true,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "1920×1080 → 3840×2160 (Lanczos)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1280,
                    sourceHeight: 720,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .lineArt
                ),
                disabledReason: nil,
                lowResUpscaleMode: .animeLineArt,
                upscalesFullHDVideo: false,
                isSDR: true,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (Anime4K 2×)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1280,
                    sourceHeight: 720,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .automatic,
                    mlScale: 2.0,
                    isDegraded: false
                ),
                disabledReason: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                isSDR: true,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (ANE 2× + MetalFX)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1280,
                    sourceHeight: 720,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .automatic,
                    mlScale: 1.5,
                    isDegraded: false
                ),
                disabledReason: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                isSDR: true,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (ANE 1,5× + MetalFX)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1280,
                    sourceHeight: 720,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .automatic,
                    mlScale: 2.0,
                    isDegraded: true
                ),
                disabledReason: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                isSDR: true,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (ANE 2×)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(
                    sourceWidth: 1280,
                    sourceHeight: 720,
                    targetWidth: 3840,
                    targetHeight: 2160,
                    scaler: .automatic,
                    mlScale: nil,
                    isDegraded: false
                ),
                disabledReason: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                isSDR: true,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (MetalFX)"
        )

        func inactive(
            reason: String? = nil,
            mode: LowResUpscaleMode,
            fullHD: Bool,
            isSDR: Bool = true,
            w: Int,
            h: Int
        ) -> String {
            UpscaleSummaryFormatter.summary(
                activeUpscale: nil,
                disabledReason: reason,
                lowResUpscaleMode: mode,
                upscalesFullHDVideo: fullHD,
                isSDR: isSDR,
                sourceVideoWidth: w,
                sourceVideoHeight: h
            )
        }

        XCTAssertEqual(inactive(reason: "Ikke støttet", mode: .off, fullHD: false, w: 1920, h: 1080), "Nativ (Av)")
        XCTAssertEqual(inactive(reason: "Ikke støttet", mode: .auto, fullHD: true, w: 1920, h: 1080), "Nativ (Ikke støttet)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: true, isSDR: false, w: 1920, h: 1080), "Nativ (HDR-fallback)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: true, w: 3840, h: 2160), "Nativ (4K-kilde)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: true, w: 2560, h: 1080), "Nativ (4K-kilde)")

        // .auto + fullHD == false: 1080p SDR is disabled, while < 1080p / unknown waits for < 1080p SDR
        XCTAssertEqual(inactive(mode: .auto, fullHD: false, w: 1920, h: 1080), "Nativ (1080p-oppskalering av)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: false, w: 1920, h: 800), "Nativ (1080p-oppskalering av)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: false, w: 1280, h: 720), "Nativ (Venter på < 1080p SDR)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: false, w: 0, h: 0), "Nativ (Venter på < 1080p SDR)")

        // .off + fullHD == true: < 1080p SDR is disabled, while 1080p / unknown waits for 1080p SDR
        XCTAssertEqual(inactive(mode: .off, fullHD: true, w: 1280, h: 720), "Nativ (< 1080p-oppskalering av)")
        XCTAssertEqual(inactive(mode: .off, fullHD: true, w: 1920, h: 1080), "Nativ (Venter på 1080p SDR)")
        XCTAssertEqual(inactive(mode: .off, fullHD: true, w: 0, h: 0), "Nativ (Venter på 1080p SDR)")

        // .auto + fullHD == true and .animeLineArt cover <= 1080p SDR
        XCTAssertEqual(inactive(mode: .auto, fullHD: true, w: 1920, h: 1080), "Nativ (Venter på ≤ 1080p SDR)")
        XCTAssertEqual(inactive(mode: .auto, fullHD: true, w: 1280, h: 720), "Nativ (Venter på ≤ 1080p SDR)")
        XCTAssertEqual(inactive(mode: .animeLineArt, fullHD: false, w: 1920, h: 1080), "Nativ (Venter på ≤ 1080p SDR)")
        XCTAssertEqual(inactive(mode: .animeLineArt, fullHD: true, w: 1280, h: 720), "Nativ (Venter på ≤ 1080p SDR)")
    }

    func testPlaybackPrewarmBudgetPolicy() {
        let highProfile = DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824)
        let stdProfile = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824)
        XCTAssertEqual(highProfile.tier, .high2026)
        XCTAssertEqual(stdProfile.tier, .standard)

        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "nvme", tier: "nvme"))
        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "ssd", tier: nil))
        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "local", tier: "local"))
        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: nil, tier: nil))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "easynews", tier: "ssd"))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "vfs", tier: "vfs"))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "vfs", tier: ""))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "vfs", tier: "   "))
        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "nvme", tier: "   "))

        let highAvail: UInt64 = 2_000 * 1_048_576
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "nvme",
                tier: "nvme",
                memoryProfile: highProfile,
                availableMemoryBytes: highAvail
            ),
            16 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: nil,
                tier: nil,
                memoryProfile: highProfile,
                availableMemoryBytes: highAvail
            ),
            16 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "easynews",
                tier: "ssd",
                memoryProfile: highProfile,
                availableMemoryBytes: highAvail
            ),
            8 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "vfs",
                tier: "vfs",
                memoryProfile: highProfile,
                availableMemoryBytes: highAvail
            ),
            8 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "vfs",
                tier: "   ",
                memoryProfile: highProfile,
                availableMemoryBytes: highAvail
            ),
            8 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "nvme",
                tier: "nvme",
                memoryProfile: highProfile,
                availableMemoryBytes: 600 * 1_048_576
            ),
            0
        )

        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "nvme",
                tier: "nvme",
                memoryProfile: stdProfile,
                availableMemoryBytes: 800 * 1_048_576
            ),
            8 * 1024 * 1024
        )
        XCTAssertEqual(
            PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(
                source: "nvme",
                tier: "nvme",
                memoryProfile: stdProfile,
                availableMemoryBytes: 400 * 1_048_576
            ),
            0
        )
    }

    func testPlaybackCurtainWatchdogReplacingSourceItemAndHoldingOutgoingPicturePrecedence() {
        func reveal(
            fatal: Bool = false,
            switching: Bool = false,
            resolving: Bool = false,
            restoring: Bool = false,
            needsRestore: Bool = false,
            fallbackUnlocked: Bool = false,
            firstFrame: Bool = false,
            awaitingSwitch: Bool = false,
            replacingItem: Bool = false,
            holdingPicture: Bool = false
        ) -> Bool {
            PlaybackCurtainWatchdog.isPictureReadyForReveal(
                hasFatalError: fatal,
                isSwitchingSource: switching,
                isResolving: resolving,
                isRestoringFromBackground: restoring,
                needsForegroundVideoRestore: needsRestore,
                firstFrameFallbackUnlocked: fallbackUnlocked,
                hasFirstFrameReadyForDisplay: firstFrame,
                isAwaitingDisplaySwitch: awaitingSwitch,
                isReplacingSourceItem: replacingItem,
                isHoldingOutgoingPicture: holdingPicture
            )
        }

        // 1. Fatal error and foreground restore always take precedence over held still / switch
        XCTAssertFalse(reveal(fatal: true, switching: true, holdingPicture: true))
        XCTAssertFalse(reveal(switching: true, restoring: true, holdingPicture: true))
        XCTAssertFalse(reveal(switching: true, needsRestore: true, holdingPicture: true))

        // 2. Held outgoing still keeps reveal == true even during item replacement, resolving, or HDMI switch
        XCTAssertTrue(reveal(switching: true, resolving: true, awaitingSwitch: true, replacingItem: true, holdingPicture: true))
        XCTAssertTrue(reveal(resolving: true, firstFrame: false, replacingItem: true, holdingPicture: true))

        // 3. Pre-replacement switch keeps reveal == true; once replacing without held still, curtain covers until ready
        XCTAssertTrue(reveal(switching: true, replacingItem: false, holdingPicture: false))
        XCTAssertFalse(reveal(switching: true, firstFrame: false, replacingItem: true, holdingPicture: false))
        XCTAssertFalse(reveal(switching: true, firstFrame: true, awaitingSwitch: true, replacingItem: true, holdingPicture: false))
        XCTAssertTrue(reveal(switching: true, firstFrame: true, awaitingSwitch: false, replacingItem: true, holdingPicture: false))
        XCTAssertTrue(reveal(switching: true, fallbackUnlocked: true, replacingItem: true, holdingPicture: false))

        // 4. Held picture wait window bounds watchdog timeout safely <= 5.0 s
        XCTAssertEqual(
            PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: false, heldPictureFrameWaitSeconds: 2.0),
            5.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: 0),
            5.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: 2.5),
            2.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: 9.0),
            5.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlaybackCurtainWatchdog.effectiveFallbackTimeoutSeconds(isHoldingOutgoingPicture: true, heldPictureFrameWaitSeconds: .nan),
            5.0,
            accuracy: 0.001
        )
    }
}
