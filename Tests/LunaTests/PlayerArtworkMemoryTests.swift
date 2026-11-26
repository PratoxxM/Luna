import AetherBridge
import CoreGraphics
import Foundation
import MediaPlayer
import XCTest
@testable import Luna

/// Extracted artwork pipeline, NowPlaying bitmap, tab/BlurHash cache invalidation, and A19 memory-budget tests.
final class PlayerArtworkMemoryTests: XCTestCase {
    func testArtworkPipelineRawIdentityAndCacheKeyDeduplication() throws {
        let lanHostA = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v2/artwork/123?w=600"))
        let lanHostB = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/artwork/123?w=600"))
        XCTAssertEqual(ArtworkPipeline.rawIdentity(for: lanHostA), ArtworkPipeline.rawIdentity(for: lanHostB))
        XCTAssertNotEqual(
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 480),
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 960)
        )

        let extA = try XCTUnwrap(URL(string: "https://cdn-one.example.net/poster.jpg"))
        let extB = try XCTUnwrap(URL(string: "https://cdn-two.example.net/poster.jpg"))
        XCTAssertNotEqual(ArtworkPipeline.rawIdentity(for: extA), ArtworkPipeline.rawIdentity(for: extB))
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

        let sampleHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        XCTAssertNotNil(BlurHashDecoder.decode(sampleHash, width: 32, height: 24))
        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24))
        await ArtworkPipeline.shared.clearAll()
        XCTAssertNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24))
    }

    @MainActor
    func testEtappe3A19LoadOptionsHeavySoftwareClassificationAndAudioDelayFlushCancel() async throws {
        let suite = "luna.test.etappe3.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let high2026 = DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824, activeProcessorCount: 6)
        let standard = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 6)
        let comfort = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
        XCTAssertEqual(comfort.lowResUpscaleMode, .auto)

        let hdr10RemuxJson = #"""
        {
          "sessionId": "sess-a19-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:693134",
            "mediaType": "movie",
            "ids": { "tmdb": 693134 },
            "title": "Dune: Part Two"
          },
          "selectedCandidate": {
            "candidateId": "cand-remux",
            "displayHeadline": "4K HDR10 Remux",
            "releaseTitle": "Dune.Part.Two.2160p.UHD.BluRay.REMUX.HEVC.TrueHD.7.1.Atmos",
            "source": "ssd",
            "tier": "nvme",
            "resolution": "2160p",
            "videoRangeType": "HDR10",
            "videoCodec": "hevc",
            "sizeBytes": 64424509440
          },
          "stream": {
            "url": "/api/tv/v2/streams/sess-a19-1/master",
            "declaredDurationSeconds": 9960
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "foldsDolbyVisionFEL": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless",
            "objectAudioRendering": { "mode": "render", "layout": "5.1.2" }
          }
        }
        """#
        let hdr10Session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(hdr10RemuxJson.utf8))
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true
        )

        XCTAssertFalse(
            PlayerViewModel.isLikelyHeavySoftwareSession(
                hdr10Session,
                dualLayerOverride: .auto,
                lowResUpscaleMode: .auto,
                supportsHardwareAV1: true
            )
        )
        let hdr10OnlyCaps = DisplayCapabilities(
            supportsHDR: true,
            supportsDolbyVision: false,
            supportsHDR10: true,
            supportsHLG: true
        )
        let optsHigh = PlayerViewModel.buildLoadOptions(
            session: hdr10Session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            displayCapabilities: hdr10OnlyCaps,
            memoryProfile: high2026,
            availableMemoryBytes: 2_048 * 1_048_576
        )
        XCTAssertFalse(optsHigh.preferDualLayerDolbyVision)
        XCTAssertFalse(optsHigh.foldsDolbyVisionFEL)
        XCTAssertEqual(optsHigh.untaggedVideoColor, .hdr10)
        XCTAssertTrue(optsHigh.attemptsHDRMasterOnUnprovenPanel)
        XCTAssertTrue(optsHigh.preferHDR10PlusOverForcedDolbyVision)
        XCTAssertEqual(optsHigh.objectAudioRendering, .render(.l512))
        XCTAssertTrue(optsHigh.confirmAtmos)
        XCTAssertEqual(optsHigh.maxConcurrentSourceRequests, 8)
        XCTAssertEqual(optsHigh.forwardBufferSegments, 45)
        XCTAssertTrue(optsHigh.retainsSessionCacheAfterStop)
        XCTAssertEqual(optsHigh.sessionCacheByteBudget, 3 * 1_073_741_824)
        XCTAssertEqual(optsHigh.sessionCacheFreeReserveBytes, 4 * 1_073_741_824)
        XCTAssertTrue(optsHigh.upscalesLowResolutionVideo)
        XCTAssertEqual(optsHigh.upscaleScaler, .automatic)

        let optsStd = PlayerViewModel.buildLoadOptions(
            session: hdr10Session,
            client: client,
            comfort: ComfortPreferences(defaults: defaults, memoryTier: .standard),
            audioEnhancement: .reference,
            audioDelaySeconds: 0,
            memoryProfile: standard,
            availableMemoryBytes: 700 * 1_048_576
        )
        XCTAssertEqual(optsStd.maxConcurrentSourceRequests, 6)
        XCTAssertEqual(optsStd.forwardBufferSegments, 12)
        XCTAssertFalse(optsStd.retainsSessionCacheAfterStop)
        XCTAssertFalse(optsStd.confirmAtmos)

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport)
        vm.isResolving = false

        vm.adjustAudioDelay(byMs: 10)
        vm.adjustAudioDelay(byMs: 15)
        XCTAssertEqual(vm.audioDelayMs, 25)
        XCTAssertEqual(transport.events, [])
        vm.flushPendingAudioDelayCommitIfNeeded()
        XCTAssertEqual(transport.events, ["audioDelay(25ms)"])
        vm.flushPendingAudioDelayCommitIfNeeded()
        XCTAssertEqual(transport.events, ["audioDelay(25ms)"])

        vm.adjustAudioDelay(byMs: 10)
        try? await Task.sleep(nanoseconds: 290_000_000)
        XCTAssertEqual(transport.events, ["audioDelay(25ms)", "audioDelay(35ms)"])

        vm.adjustAudioDelay(byMs: 20)
        vm.teardownAndStop()
        try? await Task.sleep(nanoseconds: 280_000_000)
        XCTAssertFalse(transport.events.contains("audioDelay(55ms)"))
    }
}
