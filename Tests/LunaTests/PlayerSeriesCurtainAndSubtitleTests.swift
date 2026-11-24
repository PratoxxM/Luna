import AetherBridge
import CoreGraphics
import Foundation
import XCTest
@testable import Luna

final class PlayerSeriesCurtainAndSubtitleTests: XCTestCase {
    func testCollisionFreeSubtitleGeometryAcrossAllSeriesBottomBarPopoverAndNerdHUDCombinations() {
        // 1. Clean playback (.none, OSD hidden, popover closed)
        let clean = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .none
        )
        XCTAssertFalse(clean.relocateToTop)
        XCTAssertEqual(clean.bottomInset, 74)
        XCTAssertEqual(clean.topInset, 72)
        XCTAssertEqual(clean.leadingInset, 120)
        XCTAssertEqual(clean.trailingInset, 120)

        // 2. Skip Intro / Recap pill visible (OSD hidden) -> lifted gently to 168 pt
        let skipOnly = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .skipPrompt
        )
        XCTAssertFalse(skipOnly.relocateToTop)
        XCTAssertEqual(skipOnly.bottomInset, 168)

        // 3. Next Episode card visible (OSD hidden) -> lifted cleanly to 300 pt
        let nextOnly = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .nextEpisodeCard
        )
        XCTAssertFalse(nextOnly.relocateToTop)
        XCTAssertEqual(nextOnly.bottomInset, 300)

        // 4. Bottom OSD + active series card simultaneously -> relocates cleanly to top (84 pt, or 340 pt below NerdHUD)
        let osdAndNext = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .nextEpisodeCard
        )
        XCTAssertTrue(osdAndNext.relocateToTop)
        XCTAssertEqual(osdAndNext.topInset, 84)
        XCTAssertEqual(osdAndNext.bottomInset, 0)

        let osdAndNextWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: false,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .skipPrompt
        )
        XCTAssertTrue(osdAndNextWithHud.relocateToTop)
        XCTAssertEqual(osdAndNextWithHud.topInset, 340)
        XCTAssertGreaterThan(osdAndNextWithHud.topInset, SubtitleOverlayLayout.nerdHUDProtectedRect.maxY)

        // 5. Open QuickPanel + NerdHUD -> upper-right cinema corridor (x = 856..1830, y >= 72)
        let popoverWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: true,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .none
        )
        XCTAssertTrue(popoverWithHud.relocateToTop)
        XCTAssertEqual(popoverWithHud.topInset, 72)
        XCTAssertEqual(popoverWithHud.leadingInset, 856)
        XCTAssertEqual(popoverWithHud.trailingInset, 90)
        let subtitleCorridorRect = CGRect(
            x: popoverWithHud.leadingInset,
            y: popoverWithHud.topInset,
            width: 1920 - popoverWithHud.leadingInset - popoverWithHud.trailingInset,
            height: 120
        )
        XCTAssertFalse(
            subtitleCorridorRect.intersects(SubtitleOverlayLayout.nerdHUDProtectedRect),
            "Relocated top subtitle corridor must never overlap NerdHUDView (x=90..830, y=42..330)"
        )
    }

    @MainActor
    func testPGSBitmapLiftingOverSeriesCardsAndNerdHUDClearance() {
        let screen = CGSize(width: 1920, height: 1080)
        let baseBottomPGS = CGRect(x: 560, y: 900, width: 800, height: 96)

        // Lifts above Hopp over intro (168 pt -> maxY <= 912)
        let skipPlacement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .skipPrompt
        )
        let liftedForSkip = SubtitleOverlayView.adjustedBitmapRect(
            baseRect: baseBottomPGS,
            containerSize: screen,
            placement: skipPlacement,
            isNerdHUDVisible: false
        )
        XCTAssertLessThanOrEqual(liftedForSkip.maxY, 1080 - 168 + 0.01)

        // Lifts above Neste episode card (300 pt -> maxY <= 780)
        let nextPlacement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .nextEpisodeCard
        )
        let liftedForNext = SubtitleOverlayView.adjustedBitmapRect(
            baseRect: baseBottomPGS,
            containerSize: screen,
            placement: nextPlacement,
            isNerdHUDVisible: false
        )
        XCTAssertLessThanOrEqual(liftedForNext.maxY, 1080 - 300 + 0.01)

        // Relocated PGS with QuickPanel + NerdHUD stays clear of NerdHUDProtectedRect
        let hudPopoverPlacement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: true,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .none
        )
        let relocatedPGS = SubtitleOverlayView.adjustedBitmapRect(
            baseRect: baseBottomPGS,
            containerSize: screen,
            placement: hudPopoverPlacement,
            isNerdHUDVisible: true
        )
        XCTAssertFalse(relocatedPGS.intersects(SubtitleOverlayLayout.nerdHUDProtectedRect))
        XCTAssertGreaterThanOrEqual(relocatedPGS.minX, 856 - 0.01)
    }

    @MainActor
    func testDismissedNextEpisodePreventsForcedAutoAdvanceAtPlaybackEnded() throws {
        let sessionJSON = #"""
        {
          "sessionId": "sess-series-eof-1",
          "streamToken": "tok-series-eof-998877",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "episode:tmdb:95396:s2:e3",
            "mediaType": "episode",
            "ids": { "tmdb": 95396 },
            "title": "Who Is Alive?",
            "seriesTitle": "Severance",
            "season": 2,
            "episode": 3,
            "runtimeSeconds": 3180
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10+",
            "releaseTitle": "Severance.S02E03.2160p",
            "source": "nvme"
          },
          "stream": { "url": "/api/tv/v1/stream/sess-series-eof-1/tok-series-eof-998877/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          },
          "nextEpisode": {
            "itemId": "episode:tmdb:95396:s2:e4",
            "season": 2,
            "episode": 4,
            "title": "Woe's Hollow",
            "stillUrl": "/api/tv/v1/img/still/s2e4.jpg"
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))

        let suite = "luna.test.series.etappe4.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 3179)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: false)
        vm.activeSession = session
        vm.isResolving = false

        let osd = PlayerOSDCoordinator()
        osd.dismissedNextForSessionID = "sess-series-eof-1"

        var closeCount = 0
        osd.handlePlaybackPhaseChange(
            oldPhase: .playing,
            newPhase: .ended,
            viewModel: vm,
            autoPlayNextEpisode: true,
            onClosePlayer: { closeCount += 1 }
        )
        XCTAssertEqual(closeCount, 1, "Explicitly dismissing Neste episode must close cleanly at EOF instead of forcing episode advance")
        XCTAssertEqual(vm.activeSession?.sessionId, "sess-series-eof-1")
    }

    @MainActor
    func testNerdHUDSeriesCardsAndErrorCurtainConstants() {
        XCTAssertEqual(NerdHUDView.cardWidth, 740)
        XCTAssertEqual(NerdHUDView.keyColumnWidth, 184)
        XCTAssertEqual(
            NerdHUDView.standardRowKeys,
            [
                "Video",
                "HDR / Rute",
                "Dekoder",
                "Skalering",
                "Lydkjede",
                "Bitrate",
                "Nett / Buffer",
                "Utgave / Minne",
            ]
        )

        XCTAssertEqual(SeriesNextEpisodeCardView.cardWidth, 548)
        XCTAssertEqual(SeriesNextEpisodeCardView.thumbnailWidth, 152)
        XCTAssertEqual(SeriesNextEpisodeCardView.thumbnailHeight, 86)
        XCTAssertEqual(SeriesNextEpisodeCardView.shadowRadius, 14)
        XCTAssertEqual(SeriesNextEpisodeCardView.shadowY, 6)
        XCTAssertEqual(SeriesSkipPromptPillView.shadowRadius, 14)
        XCTAssertEqual(SeriesResumeBannerView.standardTopPadding, 64)
        XCTAssertEqual(SeriesResumeBannerView.shiftedBelowStatusToastTopPadding, 132)
        XCTAssertEqual(PlayerFatalErrorOverlayView.cardShadowRadius, 18)
        XCTAssertEqual(PlayerFatalErrorOverlayView.cardShadowY, 8)
        XCTAssertEqual(PlayerFatalErrorOverlayView.primaryRetryTitle, "Prøv på nytt")
    }
}
