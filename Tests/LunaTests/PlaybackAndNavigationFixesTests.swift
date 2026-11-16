import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PlaybackAndNavigationFixesTests: XCTestCase {
    func testBuildRowRequestPathReplacesExistingOffsetAndMapsCatalogPages() {
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "sci-fi", offset: 36, limit: 36),
            "/api/tv/v1/rows/sci-fi?offset=36&limit=36"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/rows/custom?offset=0&limit=24",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v1/rows/custom?offset=48&limit=24"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/catalog/movies?sort=popular",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v1/catalog/movies?sort=popular&page=3&limit=24"
        )
    }

    func testTvHomeResponseSemanticEqualityIgnoresGeneratedAtOnly() {
        let row = TvShelfRow(
            rowId: "medialogg-continue",
            title: "Fortsett å se",
            rowStyle: "continue_backdrop",
            sourceKind: "system_continue",
            listMode: "smart",
            hasMore: false,
            nextPath: nil,
            items: [],
            genres: nil
        )

        let first = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:00:00Z",
            layoutMode: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let refreshedSameContent = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layoutMode: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let changedRoom = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layoutMode: "rows_first",
            roomName: "Loft",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )

        XCTAssertTrue(first.isSemanticallyEqual(to: refreshedSameContent))
        XCTAssertFalse(first.isSemanticallyEqual(to: changedRoom))
    }

    @MainActor
    func testDetailPreResolveControllerConsumeAndDiscardResetSafely() {
        let controller = DetailPreResolveController()
        XCTAssertNil(controller.consumeForPlayback(itemId: "tmdb:movie:1", client: nil))
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)

        controller.discardPreparedSession(client: nil)
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)
    }

    func testNativeAudioSessionActivationOnlyAppliesToNativeRoutes() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .loopback))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .remoteBypass))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .software))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .audio))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .none))
    }

    func testDeferredDisplayCriteriaResetStatePredicate() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .idle))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .loading))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .playing))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .paused))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .seeking))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .ended))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .error("err")))
    }

    @MainActor
    func testDeferredDisplayCriteriaResetSchedulesCancelsAndFlushesSafely() async {
        final class ResetCounter {
            var count = 0
        }

        let coordinator = PlayerAudioSessionCoordinator()
        let counter = ResetCounter()

        // Cancelled deferred reset must never fire
        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 30_000_000,
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        coordinator.cancelDeferredDisplayCriteriaReset()
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(counter.count, 0)

        // When engine state is no longer eligible (e.g. resolving/playing), deferred reset skips execution
        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 25_000_000,
            shouldExecute: { false },
            performReset: { counter.count += 1 }
        )
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(counter.count, 0)

        // Eligible idle reset executes cleanly after delay
        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 25_000_000,
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(counter.count, 1)

        // Immediate flush executes pending eligible reset once
        coordinator.scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: 1_000_000_000,
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        coordinator.flushPendingDeferredResetIfEligibleForTesting()
        XCTAssertEqual(counter.count, 2)
        coordinator.flushPendingDeferredResetIfEligibleForTesting()
        XCTAssertEqual(counter.count, 2)
    }

    func testAuthoritativeStreamDurationIgnoresFallbackMetadataRuntime() {
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 2642.5,
                declaredStreamDurationSeconds: 2640.0
            ),
            2642.5
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 0,
                declaredStreamDurationSeconds: 2640.0
            ),
            2640.0
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: 0,
                declaredStreamDurationSeconds: nil
            ),
            0
        )
        XCTAssertEqual(
            SeriesFlowEligibility.authoritativeStreamDurationSeconds(
                engineDurationSeconds: -1,
                declaredStreamDurationSeconds: 0
            ),
            0
        )
    }

    func testNextEpisodePromptEligibilityWindowAndCredits() {
        let totalDuration: Double = 2400
        let chapters: [PlaybackChapter] = [
            PlaybackChapter(
                id: "credits-1",
                index: 1,
                title: "Credits",
                startSeconds: 2290,
                endSeconds: 2340,
                kind: .credits
            ),
            PlaybackChapter(
                id: "epilogue-1",
                index: 2,
                title: "Post Credits",
                startSeconds: 2340,
                endSeconds: 2400,
                kind: .chapter
            ),
        ]

        // 45s remaining without credits must NOT show prematurely
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2355,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )

        // Final 30s window (including slight audio overrun up to -5s) MUST show
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2370,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2404.5,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2406,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )

        // Credits chapter within final 120s shows pill; non-credits epilogue at 55s left hides; final 30s reappears
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2305, // 95s remaining, inside .credits
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2345, // 55s remaining, inside .chapter epilogue
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2375, // 25s remaining
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )

        // Guard conditions: dismissed, missing next episode, short/unknown duration, early playback
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: true,
                currentTime: 2385,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: false,
                isDismissedForCurrentSession: false,
                currentTime: 2385,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 60,
                authoritativeDurationSeconds: 90,
                chapters: []
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 30,
                authoritativeDurationSeconds: 100,
                chapters: []
            )
        )
    }

    func testNextEpisodePromptShowsAcrossLongMultiMinuteCreditsChapters() {
        let totalDuration: Double = 2700 // 45-minute episode
        let longCredits: [PlaybackChapter] = [
            PlaybackChapter(
                id: "false-early",
                index: 0,
                title: "Outro",
                startSeconds: 45,
                endSeconds: 90,
                kind: .credits
            ),
            PlaybackChapter(
                id: "main-credits",
                index: 1,
                title: "End Credits",
                startSeconds: 2340, // 6 minutes before end
                endSeconds: 2640,
                kind: .credits
            ),
            PlaybackChapter(
                id: "stinger",
                index: 2,
                title: "Preview",
                startSeconds: 2640,
                endSeconds: 2700,
                kind: .chapter
            ),
        ]

        // 5.5 minutes remaining inside genuine multi-minute credits MUST show Next Episode pill
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2370,
                authoritativeDurationSeconds: totalDuration,
                chapters: longCredits
            )
        )

        // Post-credits non-credits chapter with 50s remaining still hides until final 30s
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2650,
                authoritativeDurationSeconds: totalDuration,
                chapters: longCredits
            )
        )

        // Erroneous early chapter in first half (> 120s remaining) stays suppressed
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 60,
                authoritativeDurationSeconds: totalDuration,
                chapters: longCredits
            )
        )
    }

    func testForegroundRestoreDecisionAndTransportIntentPreservation() {
        XCTAssertTrue(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: false,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: false,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: true,
                hasFatalError: false,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: true,
                didTeardown: false
            )
        )
        XCTAssertFalse(
            PlayerViewModel.shouldAttemptForegroundVideoRestore(
                needsForegroundVideoRestore: true,
                hasActiveSession: true,
                isResolving: false,
                isSwitchingSource: false,
                isRestoringFromBackground: false,
                hasFatalError: false,
                didTeardown: true
            )
        )

        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .playing, engineState: .playing))
        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .rebuffering, engineState: .playing))
        XCTAssertTrue(PlayerViewModel.isActiveTransportIntent(playbackPhase: .loading, engineState: .playing))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .loading, engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .paused, engineState: .paused))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .ended, engineState: .ended))
        XCTAssertFalse(PlayerViewModel.isActiveTransportIntent(playbackPhase: .error("x"), engineState: .error("x")))

        // Preserves paused vs playing across restore, and lets explicit user toggle win
        XCTAssertFalse(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: false, userOverride: nil))
        XCTAssertTrue(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: true, userOverride: nil))
        XCTAssertTrue(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: false, userOverride: true))
        XCTAssertFalse(PlayerViewModel.resolvedPostRestorePlayingIntent(defaultShouldPlay: true, userOverride: false))
    }

    func testHomeRefreshPolicySkipsRevalidationDuringActivePlayback() {
        XCTAssertFalse(
            HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: true,
                isActiveTab: true,
                hasActivePlayback: true,
                secondsSinceLastValidation: 120
            )
        )
        XCTAssertFalse(
            HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: false,
                isActiveTab: true,
                hasActivePlayback: false,
                secondsSinceLastValidation: 120
            )
        )
        XCTAssertFalse(
            HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: true,
                isActiveTab: false,
                hasActivePlayback: false,
                secondsSinceLastValidation: 120
            )
        )
        XCTAssertFalse(
            HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: true,
                isActiveTab: true,
                hasActivePlayback: false,
                secondsSinceLastValidation: 9.9
            )
        )
        XCTAssertTrue(
            HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: true,
                isActiveTab: true,
                hasActivePlayback: false,
                secondsSinceLastValidation: 10.0
            )
        )
    }

    @MainActor
    func testBuildLoadOptionsForwardsAutoplayFlag() throws {
        let suite = "luna.test.loadoptions.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = #"""
        {
          "sessionId": "sess-autoplay-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "tmdb:movie:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K DV FEL",
            "releaseTitle": "Eksempelfilm.2024.2160p.REMUX",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": {
            "url": "/api/tv/v1/streams/sess-autoplay-1/master"
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#

        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(json.utf8))
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true
        )
        let comfort = ComfortPreferences(defaults: defaults)

        let defaultOptions = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0
        )
        XCTAssertTrue(defaultOptions.autoplay)

        let pausedOptions = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            autoplay: false
        )
        XCTAssertFalse(pausedOptions.autoplay)
    }

    func testForegroundRestoreNativeAudioActivationPredicate() {
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: false, videoRoute: .loopback))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: false, videoRoute: .remoteBypass))
        XCTAssertTrue(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .loopback))
        XCTAssertTrue(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .remoteBypass))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .software))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .audio))
        XCTAssertFalse(PlayerViewModel.shouldActivateNativeAudioDuringRestore(shouldPlay: true, videoRoute: .none))
    }

    @MainActor
    func testForegroundRestoreTogglePlayPauseAndCurtainRevealGate() throws {
        let suite = "luna.test.restorevm.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let comfort = ComfortPreferences(defaults: defaults)
        let viewModel = PlayerViewModel(engine: engine, comfort: comfort)
        viewModel.isResolving = false
        viewModel.hasFirstFrameReadyForDisplay = true
        viewModel.isAwaitingDisplaySwitch = false
        viewModel.isRestoringFromBackground = true
        viewModel.lastForegroundPlaybackWasPlaying = false

        // Curtain stays closed while restore is in flight even if first-frame flag is true.
        XCTAssertFalse(viewModel.isPictureReadyForReveal)

        // Play/Pause during restore captures user override without dropping intent.
        viewModel.togglePlayPause()
        XCTAssertEqual(viewModel.userDesiredPlayingDuringRestore, true)
        XCTAssertTrue(viewModel.lastForegroundPlaybackWasPlaying)

        viewModel.togglePlayPause()
        XCTAssertEqual(viewModel.userDesiredPlayingDuringRestore, false)
        XCTAssertFalse(viewModel.lastForegroundPlaybackWasPlaying)

        // Clearing restore flag before network heartbeat unlocks picture reveal immediately.
        viewModel.isRestoringFromBackground = false
        viewModel.userDesiredPlayingDuringRestore = nil
        XCTAssertTrue(viewModel.isPictureReadyForReveal)

        viewModel.needsNativeAudioActivationAfterPausedRestore = true
        viewModel.teardownAndStop()
        XCTAssertFalse(viewModel.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertFalse(viewModel.isRestoringFromBackground)
        XCTAssertNil(viewModel.userDesiredPlayingDuringRestore)
    }

    func testAetherBridgePinnedVersionMatchesUpgrade() {
        XCTAssertEqual(AetherBridgeInfo.pinnedAetherEngineVersion, "7.69.0")
    }
}
