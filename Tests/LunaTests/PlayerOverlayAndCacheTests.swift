import CoreGraphics
import Foundation
import MediaPlayer
import Observation
import XCTest
@testable import Luna

final class PlayerOverlayAndCacheTests: XCTestCase {
    func testArtworkPipelineRawIdentityAndCacheKeyDeduplication() throws {
        let lanHostA = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v1/artwork/123?w=600"))
        let lanHostB = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v1/artwork/123?w=600"))
        XCTAssertEqual(ArtworkPipeline.rawIdentity(for: lanHostA), ArtworkPipeline.rawIdentity(for: lanHostB))
        XCTAssertNotEqual(
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 480),
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 960)
        )

        let extA = try XCTUnwrap(URL(string: "https://cdn-one.example.net/poster.jpg"))
        let extB = try XCTUnwrap(URL(string: "https://cdn-two.example.net/poster.jpg"))
        XCTAssertNotEqual(ArtworkPipeline.rawIdentity(for: extA), ArtworkPipeline.rawIdentity(for: extB))
    }

    @MainActor
    func testComfortPreferencesSkipsDuplicateSetterSyncNotifications() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        var syncCount = 0
        comfort.onSyncRequested = { _ in
            syncCount += 1
        }

        // Re-assigning current value must not trigger redundant server syncs
        let initialPreset = comfort.hdrSubtitlePreset
        comfort.hdrSubtitlePreset = initialPreset
        XCTAssertEqual(syncCount, 0)

        comfort.hdrSubtitlePreset = .soft50
        XCTAssertEqual(syncCount, 1)

        // Assigning an identical override payload must be a complete no-op
        let snapshot = comfort.toDeviceOverrides()
        comfort.adoptServerOverrides(snapshot)
        XCTAssertEqual(syncCount, 1)
    }

    @MainActor
    func testSessionStoreSyncFromBootstrapUpdatesAvailableRoomsIdempotently() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSessionStore(defaults: defaults)
        let customRooms = [
            TvRoomDefinition(roomName: "Kino", hardwareProfile: "dv-fel-714", label: "Kino 7.1.4"),
            TvRoomDefinition(roomName: "Loft", hardwareProfile: "hdr10-512", label: "Loft 7.1.4"),
        ]
        let device = TvPairedDeviceInfo(
            deviceId: store.deviceID,
            deviceName: "Living Room Apple TV",
            roomName: "Kino",
            hardwareProfile: "dv-fel-714",
            overrides: TvDeviceOverrides(hdrSubtitlePreset: "warm_75")
        )

        store.syncFromBootstrap(device, defaultRooms: customRooms)
        XCTAssertEqual(store.roomName, "Kino")
        XCTAssertEqual(store.hardwareProfile, "dv-fel-714")
        XCTAssertEqual(store.availableRooms, customRooms)
    }

    func testNowPlayingArtworkRequestHandlerIsSafeOffMainActor() async throws {
        struct UncheckedArtworkBox: @unchecked Sendable {
            let artwork: MPMediaItemArtwork
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 16,
            height: 24,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            XCTFail("Failed to allocate test CGImage")
            return
        }

        let box = await MainActor.run {
            UncheckedArtworkBox(artwork: NowPlayingArtworkFactory.makeArtwork(cgImage: cgImage))
        }

        let renderedSize = await Task.detached(priority: .userInitiated) {
            box.artwork.image(at: CGSize(width: 16, height: 24))?.size
        }.value

        XCTAssertEqual(renderedSize?.width, 16)
        XCTAssertEqual(renderedSize?.height, 24)
    }

    @MainActor
    func testComfortPreferencesAudioDelayPersistenceAndClamping() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        var syncCount = 0
        comfort.onSyncRequested = { _ in
            syncCount += 1
        }

        XCTAssertEqual(comfort.audioDelayMs, 0)
        XCTAssertEqual(comfort.audioDelaySeconds, 0, accuracy: 0.0001)
        XCTAssertEqual(comfort.formattedAudioDelayLabel, "0 ms")

        comfort.adjustAudioDelay(byMs: -25)
        comfort.adjustAudioDelay(byMs: -10)
        XCTAssertEqual(comfort.audioDelayMs, -35)
        XCTAssertEqual(comfort.audioDelaySeconds, -0.035, accuracy: 0.0001)
        XCTAssertEqual(comfort.formattedAudioDelayLabel, "-35 ms")
        XCTAssertEqual(syncCount, 0)

        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.audioDelayMs, -35)
        XCTAssertEqual(reloaded.audioDelaySeconds, -0.035, accuracy: 0.0001)
        XCTAssertEqual(reloaded.formattedAudioDelayLabel, "-35 ms")

        reloaded.adoptServerOverrides(TvDeviceOverrides(hdrSubtitlePreset: "soft_50"))
        XCTAssertEqual(reloaded.audioDelayMs, -35)

        reloaded.audioDelayMs = -5000
        XCTAssertEqual(reloaded.audioDelayMs, -2000)
        reloaded.audioDelayMs = 5000
        XCTAssertEqual(reloaded.audioDelayMs, 2000)

        reloaded.resetAudioDelay()
        XCTAssertEqual(reloaded.audioDelayMs, 0)
        XCTAssertEqual(reloaded.formattedAudioDelayLabel, "0 ms")
        XCTAssertEqual(syncCount, 0)
    }

    @MainActor
    func testBuildLoadOptionsForwardsPersistedNegativeAudioDelay() throws {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = #"""
        {
          "sessionId": "sess-sync-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "tmdb:movie:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10+ WEB-DL",
            "releaseTitle": "Eksempelfilm.2024.2160p.WEB-DL",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": {
            "url": "/api/tv/v1/streams/sess-sync-1/master"
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
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
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )

        let comfort = ComfortPreferences(defaults: defaults)
        comfort.audioDelayMs = -45

        let options = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: comfort.audioDelaySeconds
        )
        XCTAssertEqual(options.audioDelaySeconds, -0.045, accuracy: 0.0001)
    }

    func testPausedTwelveSecondOledRestPolicyAndTimelineClockBucketing() {
        XCTAssertEqual(PlayerOSDVisibilityPolicy.playingAutoHideSeconds, 4.0, accuracy: 0.001)
        XCTAssertEqual(PlayerOSDVisibilityPolicy.playingQuickActionsAutoHideSeconds, 7.0, accuracy: 0.001)
        XCTAssertEqual(PlayerOSDVisibilityPolicy.pausedIdleRestSeconds, 12.0, accuracy: 0.001)

        XCTAssertFalse(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: false,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: true,
                playbackPhase: .paused,
                isPausedOSDResting: false
            )
        )
        // Open quick panel keeps bottom OSD anchored even while idle resting would otherwise trigger
        XCTAssertTrue(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: true,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: false,
                playbackPhase: .paused,
                isPausedOSDResting: true
            )
        )

        // Paused before 12s idle -> bottom bar visible
        XCTAssertTrue(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: false,
                playbackPhase: .paused,
                isPausedOSDResting: false
            )
        )
        XCTAssertFalse(
            PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
                playbackPhase: .paused,
                isPausedOSDResting: false,
                isScrubbing: false,
                isQuickPanelOpen: false
            )
        )

        // Paused after ~12s without remote touch -> UI rests completely on LG OLED / Frame Pro
        XCTAssertFalse(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: false,
                playbackPhase: .paused,
                isPausedOSDResting: true
            )
        )
        XCTAssertTrue(
            PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
                playbackPhase: .paused,
                isPausedOSDResting: true,
                isScrubbing: false,
                isQuickPanelOpen: false
            )
        )

        // Open quick panel suppresses ambient pause rest
        XCTAssertFalse(
            PlayerOSDVisibilityPolicy.shouldRestAmbientPlayerHUD(
                playbackPhase: .paused,
                isPausedOSDResting: true,
                isScrubbing: false,
                isQuickPanelOpen: true
            )
        )

        // Scrubbing or remote touch immediately wakes bottom bar
        XCTAssertTrue(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: true,
                showBottomBar: false,
                playbackPhase: .paused,
                isPausedOSDResting: true
            )
        )
        XCTAssertTrue(
            PlayerOSDVisibilityPolicy.shouldShowBottomBar(
                isPictureReadyForReveal: true,
                isQuickPanelOpen: false,
                hasFatalError: false,
                isScrubbing: false,
                showBottomBar: true,
                playbackPhase: .paused,
                isPausedOSDResting: false
            )
        )

        // 0.5 s time buckets & 2.0 s buffer buckets
        XCTAssertEqual(TimelineClockBucketer.timeBucket(-1.0), -1)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(.nan), -1)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(0.0), 0)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(0.49), 0)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(0.50), 1)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(10.99), 21)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(11.00), 22)

        XCTAssertEqual(TimelineClockBucketer.bufferBucket(-0.5), -1)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(0.0), 0)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(1.95), 0)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(2.00), 1)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(15.9), 7)
    }

    @MainActor
    func testIsolatedPlayerStartupStateDoesNotInvalidatePlayerViewModelAndPreservesLunaV1Keys() throws {
        XCTAssertEqual(SideloadSafeStorage.serverURLKey, "luna.v1.server_url")
        XCTAssertEqual(SideloadSafeStorage.deviceIDKey, "luna.v1.device_id")
        XCTAssertEqual(SideloadSafeStorage.showCatCompanionsKey, "luna.v1.comfort.show_cat_companions")
        XCTAssertEqual(SideloadSafeStorage.keepDisplayModeInMenuAfterPlaybackKey, "luna.v1.comfort.keep_display_mode_in_menu")
        XCTAssertEqual(SideloadSafeStorage.didMigrateMenu60HzDefaultV240Key, "luna.v1.comfort.migrated_menu_60hz_v240")

        let suite = "luna.test.startup.isolation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(engine: engine, comfort: comfort)

        final class CounterBox: @unchecked Sendable {
            var count = 0
        }
        let vmBox = CounterBox()
        withObservationTracking {
            _ = vm.isResolving
            _ = vm.playbackPhase
            _ = vm.hasFirstFrameReadyForDisplay
        } onChange: {
            vmBox.count += 1
        }

        let startupBox = CounterBox()
        func armStartupObserver() {
            withObservationTracking {
                _ = vm.startupState.resolvePercent
                _ = vm.startupState.resolveStageLabel
                _ = vm.startupState.resolveHeadline
                _ = vm.startupState.engineStartupPercentBucket
            } onChange: {
                startupBox.count += 1
            }
        }

        armStartupObserver()
        vm.resolvePercent = 45
        XCTAssertEqual(startupBox.count, 1)

        armStartupObserver()
        vm.resolveStageLabel = "Buffrer segmenter…"
        XCTAssertEqual(startupBox.count, 2)

        armStartupObserver()
        vm.resolveHeadline = "4K DV P7 FEL · NVMe"
        XCTAssertEqual(startupBox.count, 3)

        armStartupObserver()
        vm.startupState.updateEngineStartupFraction(0.642)
        XCTAssertEqual(startupBox.count, 4)

        armStartupObserver()
        vm.startupState.updateEngineStartupFraction(0.644)

        XCTAssertEqual(vmBox.count, 0, "Startup progress ticks must not invalidate PlayerViewModel")
        XCTAssertEqual(startupBox.count, 4)
        XCTAssertEqual(vm.startupState.engineStartupPercentBucket, 64)
        XCTAssertEqual(vm.startupState.engineStartupFraction, 0.64, accuracy: 0.001)
    }

    @MainActor
    func testUnpairAndArtworkClearInvalidateAllInMemoryTabAndBlurHashCaches() async throws {
        let suite = "luna.test.tabcache.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer {
            CatalogBrowseMemoryCache.shared.clear()
            LibraryBrowseMemoryCache.shared.clear()
            BlurHashDecoder.clearCache()
            defaults.removePersistentDomain(forName: suite)
        }

        CatalogBrowseMemoryCache.shared.store(
            CatalogBrowseSnapshot(
                items: [TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Test")],
                availableGenres: [],
                selectedGenreLabel: nil,
                hasMore: false,
                currentPage: 1,
                fetchedAt: Date(),
                refreshNonce: 1
            ),
            for: "http://lunacore.local:8090#movie#all#popular#false#false#Stua#hdr10-512"
        )

        let libJson = #"""
        {
          "ok": true,
          "section": "watchlist",
          "counts": {
            "watchlist": 1,
            "favorites": 0,
            "localTotal": 0,
            "nvme": 0,
            "archive": 0,
            "vfs": 0,
            "customLists": 0
          },
          "favorites": [],
          "watchlist": [],
          "localItems": []
        }
        """#
        let libPayload = try JSONDecoder().decode(TvLibraryResponse.self, from: Data(libJson.utf8))
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(
                payload: libPayload,
                localItems: [],
                localOffset: 0,
                localHasMore: false,
                fetchedAt: Date(),
                refreshNonce: 1
            ),
            for: "http://lunacore.local:8090#watchlist#all#all#recent#Stua#hdr10-512"
        )

        XCTAssertEqual(CatalogBrowseMemoryCache.shared.entryCount, 1)
        XCTAssertEqual(LibraryBrowseMemoryCache.shared.entryCount, 1)

        let store = AppSessionStore(defaults: defaults)
        let prevNonce = store.homeRefreshNonce
        store.unpairDevice()

        XCTAssertEqual(CatalogBrowseMemoryCache.shared.entryCount, 0)
        XCTAssertEqual(LibraryBrowseMemoryCache.shared.entryCount, 0)
        XCTAssertNotEqual(store.homeRefreshNonce, prevNonce)

        // Verify ArtworkPipeline.clearAll() also clears BlurHashDecoder's RAM cache
        let sampleHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        XCTAssertNotNil(BlurHashDecoder.decode(sampleHash, width: 32, height: 24))
        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24))
        await ArtworkPipeline.shared.clearAll()
        XCTAssertNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24))
    }

    @MainActor
    func testMetalFXKveldslysLockQMSModeAndSpeakerMigration() throws {
        let suite = "luna.test.v282.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        // Legacy 5.1.2 speaker override migrates cleanly to .auto (7.1.4)
        defaults.set("5.1.2", forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(comfort.speakerLayoutOverride, .auto)
        XCTAssertEqual(SpeakerLayoutOverrideMode.allCases, [.auto, .stereo])

        // QMS MenuDisplayMode policy
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: .preserveHDR60HzQMS,
                videoFormat: .dolbyVision,
                isForegroundActive: true
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: .preserveHDR60HzQMS,
                videoFormat: .sdr,
                isForegroundActive: true
            )
        )

        // Kveldslys lock messages & honest MetalFX active status
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let vm = PlayerViewModel(engine: engine, comfort: comfort)
        XCTAssertFalse(vm.isMetalFXActive)
        XCTAssertNil(vm.activeMetalFXBadge)

        vm.activeSubtitleTrackIndex = nil
        XCTAssertEqual(vm.kveldslysLockReason, "Slå på undertekst for å justere")

        vm.videoFormat = .sdr
        vm.activeSubtitleTrackIndex = 1
        XCTAssertEqual(vm.kveldslysLockReason, "Kun aktiv på HDR-innhold")

        vm.videoFormat = .hdr10Plus
        XCTAssertNil(vm.kveldslysLockReason)

        vm.previewSubtitleOptions = [
            PlayerDrawerSubtitleOption(id: 1, languageCode: "nob", rawTitle: "Norsk", isForced: false, isHearingImpaired: false, isExternal: true),
        ]
        XCTAssertNil(vm.kveldslysLockReason)
    }

    @MainActor
    func testQuickPanelAnchoringAndCollisionFreeSubtitlePlacement() {
        // 1. Popover widths & button-anchored leading-X clamping inside 1920x1080 90 pt gutters
        XCTAssertEqual(PlayerQuickPanelView.panelWidth(for: .subtitles), 740)
        XCTAssertEqual(PlayerQuickPanelView.panelWidth(for: .source), 920)

        let sourceTrigger = CGRect(x: 412, y: 950, width: 130, height: 48)
        XCTAssertEqual(
            PlayerQuickPanelView.resolvedPanelLeadingX(triggerFrame: sourceTrigger, tab: .source),
            412,
            accuracy: 0.1
        )
        let farRightTrigger = CGRect(x: 1700, y: 950, width: 120, height: 48)
        XCTAssertEqual(
            PlayerQuickPanelView.resolvedPanelLeadingX(triggerFrame: farRightTrigger, tab: .source),
            910,
            accuracy: 0.1
        )
        XCTAssertGreaterThan(
            PlayerQuickPanelView.resolvedPanelLeadingX(triggerFrame: nil, tab: .source),
            300
        )

        // 2. Collision-free subtitle vertical zones (bottom 320 with OSD, top 84/168 with popover)
        let osdOnly = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: false,
            isNerdHUDVisible: false
        )
        XCTAssertFalse(osdOnly.relocateToTop)
        XCTAssertEqual(osdOnly.bottomInset, 320)

        let popoverOpen = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: true,
            isNerdHUDVisible: false
        )
        XCTAssertTrue(popoverOpen.relocateToTop)
        XCTAssertEqual(popoverOpen.topInset, 84)

        let popoverWithHud = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: true,
            isQuickPanelOpen: true,
            isNerdHUDVisible: true
        )
        XCTAssertTrue(popoverWithHud.relocateToTop)
        XCTAssertEqual(popoverWithHud.topInset, 168)
    }
}
