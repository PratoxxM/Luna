import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class SeriesFlowAndHomePolicyTests: XCTestCase {
    func testBuildRowRequestPathReplacesExistingOffsetAndMapsCatalogPages() {
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "sci-fi", offset: 36, limit: 36),
            "/api/tv/v2/rows/sci-fi?offset=36&limit=36"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v2/rows/custom?offset=0&limit=24",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v2/rows/custom?offset=48&limit=24"
        )

        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v2/catalog/movies?sort=popular",
                offset: 48,
                limit: 24
            ),
            "/api/tv/v2/catalog/movies?sort=popular&page=3&limit=24"
        )

        // Legacy /api/tv/v1/ paths normalize cleanly to /api/tv/v2/
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(
                pathOrRowId: "/api/tv/v1/rows/custom?offset=0&limit=24",
                offset: 24,
                limit: 24
            ),
            "/api/tv/v2/rows/custom?offset=24&limit=24"
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
            items: []
        )

        let first = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:00:00Z",
            layout: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let refreshedSameContent = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layout: "rows_first",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            rows: [row]
        )
        let changedRoom = TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-13T10:05:00Z",
            layout: "rows_first",
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
        let handoff = controller.consumeHandoffForPlayback(
            itemId: "movie:tmdb:1",
            startPosition: nil,
            client: nil
        )
        XCTAssertNil(handoff.prepareToken)
        XCTAssertNil(handoff.preparedSession)
        XCTAssertNil(handoff.inflightPrepareTask)
        XCTAssertNil(handoff.inflightPrepareToken)
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)

        controller.discardPreparedSession(client: nil)
        XCTAssertFalse(controller.isPreResolvedReady)
        XCTAssertNil(controller.preparedToken)
        XCTAssertNil(controller.preparedForItemId)
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

    func testInitialResumeBannerEligibilityWindowAndOneShotSessionGuard() {
        XCTAssertNil(
            SeriesFlowEligibility.initialResumeBannerSeconds(
                sessionId: nil,
                streamStartPositionSeconds: 1200,
                requestStartPositionSeconds: 1200,
                shownForSessionID: nil
            )
        )
        XCTAssertNil(
            SeriesFlowEligibility.initialResumeBannerSeconds(
                sessionId: "sess-1",
                streamStartPositionSeconds: 10,
                requestStartPositionSeconds: nil,
                shownForSessionID: nil
            )
        )
        XCTAssertEqual(
            SeriesFlowEligibility.initialResumeBannerSeconds(
                sessionId: "sess-1",
                streamStartPositionSeconds: 1390,
                requestStartPositionSeconds: 600,
                shownForSessionID: nil
            ),
            1390
        )
        XCTAssertNil(
            SeriesFlowEligibility.initialResumeBannerSeconds(
                sessionId: "sess-1",
                streamStartPositionSeconds: 1390,
                requestStartPositionSeconds: 1390,
                shownForSessionID: "sess-1"
            )
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

        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2355,
                authoritativeDurationSeconds: totalDuration,
                chapters: []
            )
        )

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

        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2305,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertFalse(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2345,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )
        XCTAssertTrue(
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: 2375,
                authoritativeDurationSeconds: totalDuration,
                chapters: chapters
            )
        )

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
        let totalDuration: Double = 2700
        let longCredits: [PlaybackChapter] = [
            PlaybackChapter(id: "false-early", index: 0, title: "Outro", startSeconds: 45, endSeconds: 90, kind: .credits),
            PlaybackChapter(id: "bogus-mid", index: 1, title: "Outro", startSeconds: 1400, endSeconds: 1500, kind: .credits),
            PlaybackChapter(id: "main-credits", index: 2, title: "End Credits", startSeconds: 2280, endSeconds: 2640, kind: .credits),
            PlaybackChapter(id: "stinger", index: 3, title: "Preview", startSeconds: 2640, endSeconds: 2700, kind: .chapter),
        ]
        let check: (Double, Double, [PlaybackChapter]) -> Bool = { t, dur, ch in
            SeriesFlowEligibility.shouldShowNextEpisodePrompt(
                hasNextEpisode: true,
                isDismissedForCurrentSession: false,
                currentTime: t,
                authoritativeDurationSeconds: dur,
                chapters: ch
            )
        }

        XCTAssertTrue(check(2280, totalDuration, longCredits))
        XCTAssertTrue(check(2370, totalDuration, longCredits))

        let extendedCredits = [
            PlaybackChapter(id: "too-early-credits", index: 0, title: "End Credits", startSeconds: 2200, endSeconds: 2640, kind: .credits)
        ]
        XCTAssertFalse(check(2279, totalDuration, extendedCredits))
        XCTAssertFalse(check(1450, totalDuration, longCredits))
        XCTAssertFalse(check(2650, totalDuration, longCredits))
        XCTAssertFalse(check(60, totalDuration, longCredits))

        let shortChapters = [
            PlaybackChapter(id: "short-bogus", index: 0, title: "Credits", startSeconds: 200, endSeconds: 260, kind: .credits),
            PlaybackChapter(id: "short-real", index: 1, title: "End Credits", startSeconds: 480, endSeconds: 590, kind: .credits),
        ]
        XCTAssertFalse(check(220, 600, shortChapters))
        XCTAssertTrue(check(500, 600, shortChapters))

        let mergedCredits = PlaybackChapter.mergeRaw(
            probeChapters: [TvProbeChapter(index: 0, idString: "tidb-cr", title: "Rulletekst", startSeconds: 2400, endSeconds: 2700, kind: "credits")],
            engineChapters: [RawEngineChapter(id: 1, name: "Chapter 01", startSeconds: 0, durationSeconds: 2700)],
            mediaDuration: 2700
        )
        XCTAssertTrue(check(2460, totalDuration, mergedCredits))
        XCTAssertFalse(check(1450, totalDuration, mergedCredits))
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

    func testAetherBridgePinnedVersionMatchesUpgrade() {
        XCTAssertEqual(AetherBridgeInfo.pinnedAetherEngineVersion, "7.76.0")
    }

    @MainActor
    func testPlayerQuickPanelFiveTabsSmartSubtitleLookupAndRemoteCommandToast() async throws {
        XCTAssertEqual(
            PlayerQuickPanelTab.allCases.map(\.title),
            ["Tekst", "Lyd", "Utgave", "Bilde", "Kapitler"]
        )
        XCTAssertEqual(
            PlayerQuickPanelTab.visibleTabs(hasChapters: false).map(\.title),
            ["Tekst", "Lyd", "Utgave", "Bilde"]
        )
        XCTAssertEqual(PlayerQuickPanelTab.source.panelHeaderTitle, "Velg utgave")

        let tracks: [SmartTrackDescriptor] = [
            SmartTrackDescriptor(id: 0, name: "Norwegian SDH", codec: "srt", language: "nb", isHearingImpaired: true),
            SmartTrackDescriptor(id: 1, name: "Norwegian Forced", codec: "pgs", language: "nor", isForced: true),
            SmartTrackDescriptor(id: 2, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 3, name: "English", codec: "srt", language: "eng"),
        ]
        XCTAssertEqual(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "no", in: tracks), 2)
        XCTAssertEqual(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "fr", in: tracks), 2)
        XCTAssertEqual(
            SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "en", in: [tracks[0], tracks[3]]),
            3
        )

        let suite = "luna.test.remotecmd.\(UUID().uuidString)"
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
        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 120)
        )
        await vm.handleHeartbeatPendingCommand(
            TvPendingCommand(type: "subtitles_on", language: "no"),
            client: nil,
            currentPosition: 120
        )
        XCTAssertEqual(vm.remoteCommandToastMessage, "Ingen undertekster tilgjengelig")
        vm.cancelAllSessionTasks()
        XCTAssertNil(vm.remoteCommandToastMessage)
    }

    func testPostCreditsStingerSkipEligibilityDistinguishesStingerFromTerminalCredits() {
        let withPostCredits = [
            PlaybackChapter(id: "cr", index: 0, title: "Rulletekst", startSeconds: 5800, endSeconds: 6040, kind: .credits),
            PlaybackChapter(id: "st", index: 1, title: "Etter rulletekst", startSeconds: 6040, endSeconds: 6110, kind: .postCredits),
        ]
        XCTAssertEqual(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5850,
                authoritativeDurationSeconds: 6120,
                chapters: withPostCredits
            ),
            6040
        )

        let implicit25sTail = [
            PlaybackChapter(id: "cr-2", index: 0, title: "Credits", startSeconds: 5800, endSeconds: 6000, kind: .credits),
        ]
        XCTAssertEqual(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5840,
                authoritativeDurationSeconds: 6025,
                chapters: implicit25sTail
            ),
            6000
        )
        XCTAssertNil(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5840,
                authoritativeDurationSeconds: 6020,
                chapters: implicit25sTail
            )
        )
    }
}
