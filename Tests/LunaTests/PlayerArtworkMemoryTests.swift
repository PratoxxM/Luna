import AetherBridge
import CoreGraphics
import Foundation
import ImageIO
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

    @MainActor
    func testFullHDLanczosUpscaleDeferredAttachmentsAndSingleWarmEnterPlaybackMemoryMode() async throws {
        let host = "warm-memory-mode-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.test.lanczos.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            ArtworkPipeline.shared.exitPlaybackMemoryMode()
            defaults.removePersistentDomain(forName: suite)
        }

        let high2026 = DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824, activeProcessorCount: 6)
        let standard = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 6)

        let sdr1080JSON = #"""
        {
          "sessionId": "sess-1080p-1",
          "streamToken": "stream-1080p-token-1234",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:603",
            "mediaType": "movie",
            "ids": { "tmdb": 603 },
            "title": "The Matrix"
          },
          "selectedCandidate": {
            "candidateId": "cand-1080p",
            "displayHeadline": "1080p BluRay",
            "releaseTitle": "The.Matrix.1999.1080p.BluRay.x264",
            "source": "nvme",
            "tier": "nvme",
            "resolution": "1080p",
            "videoRangeType": "SDR",
            "videoCodec": "h264"
          },
          "stream": { "url": "/api/tv/v2/streams/sess-1080p-1/master" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sdr1080JSON.utf8))
        let client = try MockURLProtocol.makeClient(host: host)

        // 1. Default high2026 enables upscalesFullHDVideo = true; standard disables it
        let highComfort = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
        let optsHigh = PlayerViewModel.buildLoadOptions(
            session: session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: high2026
        )
        XCTAssertTrue(optsHigh.upscalesLowResolutionVideo)
        XCTAssertEqual(optsHigh.upscaleScaler, .automatic)
        XCTAssertTrue(optsHigh.upscalesFullHDVideo)
        XCTAssertFalse(optsHigh.skipsContainerAttachments, "Nil server flag must defer ASS attachments instead of skipping")
        XCTAssertFalse(optsHigh.readsContainerAttachmentsAtOpen)

        highComfort.lowResUpscaleMode = .off
        let optsLanczosOnly = PlayerViewModel.buildLoadOptions(
            session: session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: high2026
        )
        XCTAssertFalse(optsLanczosOnly.upscalesLowResolutionVideo)
        XCTAssertEqual(optsLanczosOnly.upscaleScaler, .lanczos)
        XCTAssertTrue(optsLanczosOnly.upscalesFullHDVideo)

        highComfort.lowResUpscaleMode = .animeLineArt
        let optsAnime = PlayerViewModel.buildLoadOptions(
            session: session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: high2026
        )
        XCTAssertTrue(optsAnime.upscalesLowResolutionVideo)
        XCTAssertEqual(optsAnime.upscaleScaler, .lineArt)
        XCTAssertFalse(optsAnime.upscalesFullHDVideo)

        let stdSuite = "luna.test.lanczos.std.\(UUID().uuidString)"
        let stdDefaults = try XCTUnwrap(UserDefaults(suiteName: stdSuite))
        defer { stdDefaults.removePersistentDomain(forName: stdSuite) }
        let stdComfort = ComfortPreferences(defaults: stdDefaults, memoryTier: .standard)
        let optsStd = PlayerViewModel.buildLoadOptions(
            session: session, client: client, comfort: stdComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: standard
        )
        XCTAssertFalse(optsStd.upscalesFullHDVideo)

        // Heavy-session predicate for 1080p SDR reflects upscalesFullHDVideo
        XCTAssertFalse(
            PlayerViewModel.isLikelyHeavySoftwareSession(
                session, dualLayerOverride: .auto, lowResUpscaleMode: .auto,
                upscalesFullHDVideo: false, supportsHardwareAV1: true
            )
        )
        XCTAssertTrue(
            PlayerViewModel.isLikelyHeavySoftwareSession(
                session, dualLayerOverride: .auto, lowResUpscaleMode: .auto,
                upscalesFullHDVideo: true, supportsHardwareAV1: true
            )
        )

        // 2. Pure memory-mode upgrade policy covers warm-prepared, cold-upgrade, already-heavy, and non-heavy cases
        XCTAssertFalse(
            PlayerEngineConfigurator.shouldUpgradePlaybackMemoryMode(
                alreadyHadPreparedSession: true,
                initialHeavyStream: false,
                resolvedHeavyStream: true
            )
        )
        XCTAssertFalse(
            PlayerEngineConfigurator.shouldUpgradePlaybackMemoryMode(
                alreadyHadPreparedSession: true,
                initialHeavyStream: true,
                resolvedHeavyStream: true
            )
        )
        XCTAssertTrue(
            PlayerEngineConfigurator.shouldUpgradePlaybackMemoryMode(
                alreadyHadPreparedSession: false,
                initialHeavyStream: false,
                resolvedHeavyStream: true
            )
        )
        XCTAssertFalse(
            PlayerEngineConfigurator.shouldUpgradePlaybackMemoryMode(
                alreadyHadPreparedSession: false,
                initialHeavyStream: true,
                resolvedHeavyStream: true
            )
        )
        XCTAssertFalse(
            PlayerEngineConfigurator.shouldUpgradePlaybackMemoryMode(
                alreadyHadPreparedSession: false,
                initialHeavyStream: false,
                resolvedHeavyStream: false
            )
        )

        // 3. Warm launch activates playback memory mode and triggers at most a single purge notification
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                return (resp, Data(#"{"ok":true,"resolveId":"res-warm","playbackSession":\#(sdr1080JSON)}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let purgeCount = TestLockedBox(0)
        let observer = NotificationCenter.default.addObserver(
            forName: ArtworkPipeline.didPurgeMemoryNotification,
            object: nil,
            queue: .main
        ) { _ in
            purgeCount.withLock { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let warmComfort = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
        warmComfort.lowResUpscaleMode = .off
        warmComfort.upscalesFullHDVideo = true
        let transport = MockPlayerTransport(state: .idle, playbackPhase: .idle)
        let vm = PlayerViewModel(
            engine: engine, comfort: warmComfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false
        )
        let req = PlaybackLaunchRequest(
            itemId: "movie:tmdb:603",
            title: "The Matrix",
            startPositionSeconds: 0,
            prepareToken: "sess-1080p-1",
            preparedSession: session
        )
        vm.start(request: req, client: client)
        await vm.sessionController.resolveTask?.value
        XCTAssertTrue(ArtworkPipeline.shared.isPlaybackActive)
        vm.teardownAndStop()
        for _ in 0..<3 {
            await Task.yield()
        }
        XCTAssertLessThanOrEqual(
            purgeCount.withLock { $0 },
            1,
            "Warm launch must trigger enterPlaybackMemoryMode at most once"
        )
    }

    private func makeValidPNGData(width: Int = 16, height: Int = 16) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        ctx.setFillColor(CGColor(red: 0.85, green: 0.65, blue: 0.35, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(ctx.makeImage())

        let pngData = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return pngData as Data
    }

    private func withCleanArtworkPipeline(host: String, _ body: () async throws -> Void) async throws {
        await ArtworkPipeline.shared.clearAll()
        do {
            try await body()
        } catch {
            MockURLProtocol.unregister(host: host)
            await ArtworkPipeline.shared.clearAll()
            throw error
        }
        MockURLProtocol.unregister(host: host)
        await ArtworkPipeline.shared.clearAll()
    }

    func testArtworkPipelineEvictsCorruptCachedDiskFileAndRecoversOnNextLoad() async throws {
        let host = "artwork-corrupt-disk-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let validPNG = try makeValidPNGData(width: 16, height: 16)
            let url = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/corrupt_disk.png"))
            let diskFileURL = ArtworkPipeline.diskFileURL(for: url)
            try FileManager.default.createDirectory(at: ArtworkPipeline.imageCacheDirectoryURL, withIntermediateDirectories: true)
            try Data("corrupt-bytes-not-an-image".utf8).write(to: diskFileURL, options: .atomic)
            XCTAssertTrue(FileManager.default.fileExists(atPath: diskFileURL.path))

            MockURLProtocol.register(host: host) { request in
                let reqURL = try XCTUnwrap(request.url)
                let resp = try XCTUnwrap(HTTPURLResponse(url: reqURL, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, validPNG)
            }
            let client = try MockURLProtocol.makeClient(host: host)

            // First load hits corrupt disk file, fails decode, and evicts corrupt file synchronously.
            let firstLoad = await ArtworkPipeline.shared.loadImage(url: url, maxPixelSize: 480, client: client)
            XCTAssertNil(firstLoad)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: diskFileURL.path),
                "Corrupt disk cache file must be deleted synchronously when downsampleAndDecode fails"
            )

            // Second load fetches valid PNG from network, decodes, and persists valid bytes on disk.
            let secondLoad = await ArtworkPipeline.shared.loadImage(url: url, maxPixelSize: 480, client: client)
            XCTAssertNotNil(secondLoad)
            XCTAssertEqual(secondLoad?.width, 16)
            XCTAssertEqual(secondLoad?.height, 16)

            for _ in 0..<100 where !FileManager.default.fileExists(atPath: diskFileURL.path) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: diskFileURL.path))
            let persistedBytes = try Data(contentsOf: diskFileURL)
            XCTAssertEqual(persistedBytes, validPNG)
        }
    }

    func testArtworkPipelineDoesNotPersistCorruptHTTP200PayloadAndRecovers() async throws {
        let host = "artwork-corrupt-http-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let validPNG = try makeValidPNGData(width: 16, height: 16)
            let requestCount = TestLockedBox(0)
            MockURLProtocol.register(host: host) { request in
                let reqURL = try XCTUnwrap(request.url)
                let attempt = requestCount.withLock { count -> Int in
                    count += 1
                    return count
                }
                let resp = try XCTUnwrap(HTTPURLResponse(url: reqURL, statusCode: 200, httpVersion: nil, headerFields: nil))
                if attempt == 1 {
                    return (resp, Data("<html>502 Bad Gateway</html>".utf8))
                }
                return (resp, validPNG)
            }

            let client = try MockURLProtocol.makeClient(host: host)
            let url = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/corrupt_http.png"))
            let diskFileURL = ArtworkPipeline.diskFileURL(for: url)

            let firstLoad = await ArtworkPipeline.shared.loadImage(url: url, maxPixelSize: 480, client: client)
            XCTAssertNil(firstLoad)
            try? await Task.sleep(nanoseconds: 40_000_000)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: diskFileURL.path),
                "Corrupt HTTP 200 payload must never be persisted to disk"
            )

            let secondLoad = await ArtworkPipeline.shared.loadImage(url: url, maxPixelSize: 480, client: client)
            XCTAssertNotNil(secondLoad)
            XCTAssertEqual(secondLoad?.width, 16)

            for _ in 0..<100 where !FileManager.default.fileExists(atPath: diskFileURL.path) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: diskFileURL.path))
        }
    }

    func testArtworkPipelineCancellationDoesNotDeleteValidDiskCacheFile() async throws {
        let host = "artwork-cancel-disk-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let validPNG = try makeValidPNGData(width: 16, height: 16)
            let url = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/valid_cancel.png"))
            let diskFileURL = ArtworkPipeline.diskFileURL(for: url)
            try FileManager.default.createDirectory(at: ArtworkPipeline.imageCacheDirectoryURL, withIntermediateDirectories: true)
            try validPNG.write(to: diskFileURL, options: .atomic)

            let client = try MockURLProtocol.makeClient(host: host)
            let cancelledTask = Task { () -> CGImage? in
                while !Task.isCancelled {
                    await Task.yield()
                }
                return await ArtworkPipeline.shared.loadImage(url: url, maxPixelSize: 780, client: client)
            }
            cancelledTask.cancel()
            let cancelledResult = await cancelledTask.value
            XCTAssertNil(cancelledResult)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: diskFileURL.path),
                "Cancelled loadImage must never delete a valid cached disk file"
            )
            XCTAssertEqual(try Data(contentsOf: diskFileURL), validPNG)
        }
    }

    func testArtworkPipelineRejectsTruncatedPNGAndEvictAdvancesGenerationWhenFileMissing() async throws {
        let host = "artwork-truncated-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let validPNG = try makeValidPNGData(width: 16, height: 16)
            let truncatedPNG = Data(validPNG.prefix(40))
            XCTAssertTrue(ArtworkPipeline.isDecodableImagePayload(validPNG))
            XCTAssertFalse(ArtworkPipeline.isDecodableImagePayload(truncatedPNG), "Truncated PNG header without image data must fail pixel decode")

            let url = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/truncated.png"))
            let rawKey = ArtworkPipeline.rawIdentity(for: url)
            let diskFileURL = ArtworkPipeline.diskFileURL(for: url)
            XCTAssertFalse(FileManager.default.fileExists(atPath: diskFileURL.path))

            let pin = ArtworkPipeline.shared.diskMutation.pin(key: rawKey)
            withExtendedLifetime(pin.lease) {
                ArtworkPipeline.shared.evictCorruptDiskFile(
                    at: diskFileURL,
                    rawKey: rawKey,
                    clearEpoch: pin.clearEpoch,
                    expectedGeneration: pin.generation
                )
            }
            XCTAssertNotEqual(
                ArtworkPipeline.shared.diskMutation.generation(for: rawKey),
                pin.generation,
                "evictCorruptDiskFile must advance generation even when disk file does not exist yet"
            )

            ArtworkPipeline.shared.scheduleDiskWrite(
                data: truncatedPNG,
                to: diskFileURL,
                rawKey: rawKey,
                clearEpoch: pin.clearEpoch,
                expectedGeneration: pin.generation,
                lease: pin.lease
            )
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: diskFileURL.path),
                "Queued scheduleDiskWrite with prior generation must abort after evictCorruptDiskFile"
            )
        }
    }

    func testDiskMutationCoordinator2048RolloverPinsActiveKey() {
        let coordinator = ArtworkPipeline.DiskMutationCoordinator()
        let pinnedGeneration: UInt64
        var activeLease: ArtworkPipeline.DiskKeyLease?
        do {
            let pin = coordinator.pin(key: "active-key")
            pinnedGeneration = pin.generation
            activeLease = pin.lease
        }
        XCTAssertEqual(pinnedGeneration, 0)
        XCTAssertEqual(coordinator.withLock { $0.activeCounts["active-key"] }, 1)

        withExtendedLifetime(activeLease) {
            for i in 0..<2_500 {
                _ = coordinator.advanceGeneration(for: "idle-\(i)")
            }
            XCTAssertLessThanOrEqual(coordinator.trackedKeyCount, 2048)
            XCTAssertEqual(
                coordinator.generation(for: "active-key"),
                pinnedGeneration,
                "Pinned active key generation must never be bumped by 2048-key rollover"
            )
        }

        let updatedGen = coordinator.advanceGeneration(for: "active-key")
        XCTAssertGreaterThan(updatedGen, 2_500)

        // After releasing lease, active-key becomes idle and future rollovers evict it while advancing minFloor past updatedGen.
        activeLease = nil
        XCTAssertNil(coordinator.withLock { $0.activeCounts["active-key"] })
        for i in 2_500..<5_000 {
            _ = coordinator.advanceGeneration(for: "idle-\(i)")
        }
        XCTAssertLessThanOrEqual(coordinator.trackedKeyCount, 2048)
        XCTAssertGreaterThan(coordinator.generation(for: "active-key"), updatedGen)
    }
}
