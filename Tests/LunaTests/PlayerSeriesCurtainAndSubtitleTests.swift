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

        XCTAssertEqual(SubtitleOverlayLayout.nerdHUDProtectedRect.minY, 60)
        XCTAssertEqual(SubtitleOverlayLayout.nerdHUDProtectedRect.maxY, 428)

        let cleanWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: false,
            isQuickPanelOpen: false,
            isNerdHUDVisible: true,
            activeSeriesOverlay: .none
        )
        XCTAssertFalse(cleanWithHud.relocateToTop)
        XCTAssertEqual(cleanWithHud.topInset, 440)
        XCTAssertGreaterThan(cleanWithHud.topInset, SubtitleOverlayLayout.nerdHUDProtectedRect.maxY)

        // 4. Bottom OSD + active series card simultaneously -> relocates cleanly to top (84 pt, or 440 pt below NerdHUD)
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
        XCTAssertEqual(osdAndNextWithHud.topInset, 440)
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
            "Relocated top subtitle corridor must never overlap NerdHUDView (x=90..830, y=60..428)"
        )

        // 6. Interactive scrubbing relocates subtitles to top so ScrubPreviewBubbleView never overlaps cues
        let scrubbingPlacement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false,
            activeSeriesOverlay: .none,
            isScrubbing: true
        )
        XCTAssertTrue(scrubbingPlacement.relocateToTop)
        XCTAssertEqual(scrubbingPlacement.topInset, 84)
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
          "stream": { "url": "/api/tv/v2/stream/sess-series-eof-1/tok-series-eof-998877/video.mkv" },
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
            "stillUrl": "/api/tv/v2/img/still/s2e4.jpg"
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
        XCTAssertEqual(SeriesSkipPromptPillView.chevronWidth, 24)
        XCTAssertEqual(SeriesSkipPromptPillView.resolvedLabel(for: .postCredits), LunaCopy.skipToPostCreditsTitle)
        XCTAssertEqual(SeriesSkipPromptPillView.resolvedLabel(for: .credits), LunaCopy.skipToPostCreditsTitle)
        XCTAssertEqual(SeriesSkipPromptPillView.resolvedLabel(for: .recap), "Hopp over sammendrag")
        XCTAssertNil(NerdHUDView.formatSessionCacheLabel(.inactive))
        XCTAssertNil(NerdHUDView.formatSessionCacheBytes(2_621_440, isInactive: true))
        XCTAssertNil(NerdHUDView.formatSessionCacheBytes(0))
        XCTAssertEqual(
            NerdHUDView.formatSessionCacheBytes(2_621_440),
            "+2,5 MiB RAM-buffer"
        )
        XCTAssertEqual(SeriesResumeBannerView.standardTopPadding, 64)
        XCTAssertEqual(SeriesResumeBannerView.shiftedBelowStatusToastTopPadding, 132)
        XCTAssertEqual(PlayerFatalErrorOverlayView.cardShadowRadius, 18)
        XCTAssertEqual(PlayerFatalErrorOverlayView.cardShadowY, 8)
        XCTAssertEqual(PlayerFatalErrorOverlayView.primaryRetryTitle, "Prøv på nytt")

        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: 8, positionY: nil), .top)
        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: 5, positionY: nil), .center)
        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: 2, positionY: nil), .bottom)
        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: nil, positionY: 0.15), .top)
        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: nil, positionY: 0.85), .bottom)
        XCTAssertEqual(SubtitleOverlayView.resolveVerticalSlot(alignment: nil, positionY: nil), .bottom)
    }

    @MainActor
    func testNerdHUDUpscaleSummaryReflects1080pSub1080pHDRAnd4KModes() {
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                videoFormat: .sdr,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "Nativ (1080p-oppskalering av)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                videoFormat: .sdr,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "Nativ (Venter på < 1080p SDR)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false,
                videoFormat: .sdr,
                sourceVideoWidth: 0,
                sourceVideoHeight: 0
            ),
            "Nativ (Venter på < 1080p SDR)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .off,
                upscalesFullHDVideo: true,
                videoFormat: .sdr,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "Nativ (< 1080p-oppskalering av)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .off,
                upscalesFullHDVideo: true,
                videoFormat: .sdr,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "Nativ (Venter på 1080p SDR)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: true,
                videoFormat: .sdr,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "Nativ (Venter på ≤ 1080p SDR)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .animeLineArt,
                upscalesFullHDVideo: false,
                videoFormat: .sdr,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "Nativ (Venter på ≤ 1080p SDR)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .off,
                upscalesFullHDVideo: false,
                videoFormat: .sdr,
                sourceVideoWidth: 1280,
                sourceVideoHeight: 720
            ),
            "Nativ (Av)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: true,
                videoFormat: .hdr10,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "Nativ (HDR-fallback)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: true,
                videoFormat: .dolbyVision,
                sourceVideoWidth: 1920,
                sourceVideoHeight: 1080
            ),
            "Nativ (HDR-fallback)"
        )
        XCTAssertEqual(
            NerdHUDView.upscaleSummary(
                activeUpscale: nil,
                lowResUpscaleMode: .auto,
                upscalesFullHDVideo: true,
                videoFormat: .sdr,
                sourceVideoWidth: 3840,
                sourceVideoHeight: 2160
            ),
            "Nativ (4K-kilde)"
        )
    }

    @MainActor
    func testSendHeartbeatOnceSkipsPrewarmAndSecretRegistrationAfterDismissalOrTeardown() async throws {
        let sessionJSON = #"""
        {
          "sessionId": "sess-hb-teardown-1",
          "streamToken": "stream_secret_hb_teardown_1234",
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
            "candidateId": "cand-hb-1",
            "displayHeadline": "4K HDR10+",
            "releaseTitle": "Severance.S02E03.2160p",
            "source": "nvme",
            "tier": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/sess-hb-teardown-1/stream_secret_hb_teardown_1234/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let hbPrewarmBody = #"""
        {
          "ok": true,
          "sessionId": "sess-hb-teardown-1",
          "state": "playing",
          "vfsTelemetry": { "streamSource": "vfs" },
          "nextEpisodePrewarm": {
            "itemId": "episode:tmdb:95396:s2:e4",
            "sessionId": "sess-next-prewarm-1",
            "streamToken": "next_ep_secret_token_987654",
            "streamUrl": "/api/tv/v2/stream/sess-next-prewarm-1/next_ep_secret_token_987654/video.mkv",
            "canClientPrewarmBytes": true,
            "nextEpisode": {
              "itemId": "episode:tmdb:95396:s2:e4",
              "season": 2,
              "episode": 4,
              "title": "Woe's Hollow"
            }
          },
          "pendingCommand": {
            "type": "subtitles_on",
            "language": "nob"
          }
        }
        """#

        func runCase(triggerTeardownInsteadOfDismissal: Bool) async throws {
            let host = "hb-guard-\(UUID().uuidString.lowercased()).local"
            let suite = "luna.v1.test.hbguard.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer {
                MockURLProtocol.unregister(host: host)
                defaults.removePersistentDomain(forName: suite)
            }

            let gate = TestStepGate()
            let log = TestLockedBox<[String]>([])
            MockURLProtocol.registerAsync(host: host) { request in
                let url = try XCTUnwrap(request.url)
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let bodyStr = String(data: MockURLProtocol.bodyData(for: request), encoding: .utf8) ?? ""
                if url.path == "/api/tv/v2/playback/heartbeat", bodyStr.contains("\"state\":\"playing\"") {
                    await gate.wait(label: "hb", log: log)
                    return (resp, Data(hbPrewarmBody.utf8))
                }
                return (resp, Data(#"{"ok":true,"state":"stopped"}"#.utf8))
            }

            let comfort = ComfortPreferences(defaults: defaults)
            let engine = try LunaApp.makeSharedEngine()
            defer {
                PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
                engine.stop(resetDisplayCriteria: true)
            }
            let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 120)
            let client = try MockURLProtocol.makeClient(host: host)
            let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
            let vm = PlayerViewModel(
                engine: engine,
                comfort: comfort,
                transport: transport,
                audioActivator: MockNativeAudioActivator { _ in },
                preferenceStore: PlaybackPreferenceStore(suiteName: suite),
                bindOnInit: false
            )
            vm.activeClient = client
            vm.activeSession = session
            vm.isResolving = false
            vm.qosReporter.playbackPhase = .playing

            let hbTask = Task { @MainActor in
                await vm.qosReporter.sendHeartbeatOnce(overrideState: nil)
            }
            await gate.waitUntilStarted()

            if triggerTeardownInsteadOfDismissal {
                vm.sessionController.teardownAndStop()
            } else {
                vm.sessionController.prepareForDismissal()
            }
            await gate.finish()
            await hbTask.value

            XCTAssertNil(vm.qosReporter.prewarmedNextEpisodeStreamToken)
            XCTAssertNil(vm.qosReporter.prewarmedNextEpisodeURL)
            XCTAssertNil(vm.qosReporter.prewarmedNextEpisodeItemId)
            XCTAssertNil(vm.qosReporter.prewarmedNextEpisodeSessionId)
            XCTAssertNil(vm.qosReporter.nextEpisodePrewarmTask)
            XCTAssertNil(vm.qosReporter.lastVfsTelemetry)
            XCTAssertNil(vm.qosReporter.lastReportedServerState)
            XCTAssertNil(vm.activeSession?.nextEpisode)
            XCTAssertNil(vm.qosReporter.remoteCommandToastMessage)
        }

        try await runCase(triggerTeardownInsteadOfDismissal: false)
        try await runCase(triggerTeardownInsteadOfDismissal: true)
    }

    @MainActor
    func testNerdHUDAudioSummaryAndSubtitleOCRPromotion() {
        XCTAssertEqual(
            NerdHUDView.audioSummary(
                speakerLayoutOverride: .auto,
                sessionRoomAutoLayout: "7.1.4",
                audioFormatBadge: "7.1.4 Atmos",
                audioDecoderLabel: "bridged",
                audioEnhancement: .dialogueLift,
                audioDelayMs: -50,
                binauralStatus: .active
            ),
            "Auto 7.1.4 Atmos (bridged) · Binaural · Dialogløft · −50 ms"
        )
        XCTAssertEqual(
            NerdHUDView.audioSummary(
                speakerLayoutOverride: .stereo,
                sessionRoomAutoLayout: "7.1.4",
                audioFormatBadge: "Stereo 2.0",
                audioDecoderLabel: "decoded",
                audioEnhancement: .reference,
                audioDelayMs: 0,
                binauralStatus: .suppressedByStereo
            ),
            "Stereo 2.0 (decoded) · Binaural av (2.0)"
        )

        let bottomPos = CGRect(x: 0.25, y: 0.80, width: 0.50, height: 0.10)
        let goodLines = [SubtitleOCRLineInput(text: "Dialoglinje", confidence: 0.90)]
        let promotedBottom = SubtitleOverlayView.resolveOCRCuePlacement(
            recognizedText: "Dialoglinje",
            lines: goodLines,
            imagePosition: bottomPos,
            placementAlignment: nil,
            relocateToTop: false,
            useBitmapOCR: true
        )
        XCTAssertEqual(promotedBottom?.text, "Dialoglinje")
        XCTAssertEqual(promotedBottom?.slot, .bottom)

        let relocatedTop = SubtitleOverlayView.resolveOCRCuePlacement(
            recognizedText: "Dialoglinje",
            lines: goodLines,
            imagePosition: bottomPos,
            placementAlignment: nil,
            relocateToTop: true,
            useBitmapOCR: true
        )
        XCTAssertEqual(relocatedTop?.slot, .top)

        let lowConfidence = SubtitleOverlayView.resolveOCRCuePlacement(
            recognizedText: "Uklart",
            lines: [SubtitleOCRLineInput(text: "Uklart", confidence: 0.30)],
            imagePosition: bottomPos,
            placementAlignment: nil,
            relocateToTop: false,
            useBitmapOCR: true
        )
        XCTAssertNil(lowConfidence)

        let midSign = SubtitleOverlayView.resolveOCRCuePlacement(
            recognizedText: "SKILT",
            lines: [SubtitleOCRLineInput(text: "SKILT", confidence: 0.98)],
            imagePosition: CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.08),
            placementAlignment: nil,
            relocateToTop: false,
            useBitmapOCR: true
        )
        XCTAssertNil(midSign)

        // Typography floor check for font-descriptor subtitle cue builder
        let clampedNilFont = LunaTheme.Font.subtitleCue(descriptor: nil, size: 14, isBold: true, isItalic: true)
        XCTAssertEqual(
            clampedNilFont,
            LunaTheme.Font.subtitleCue(descriptor: nil, size: 22, isBold: true, isItalic: true)
        )
        XCTAssertGreaterThanOrEqual(LunaTheme.Font.minimumPointSizeFloor, 22.0)
    }
}
