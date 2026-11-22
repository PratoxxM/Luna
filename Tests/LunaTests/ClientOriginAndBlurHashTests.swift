import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import Luna

private actor SourcePickerHeartbeatSignal {
    private var count = 0
    private var waiters: [(target: Int, cont: CheckedContinuation<Void, Never>)] = []

    func record() {
        count += 1
        var remaining: [(target: Int, cont: CheckedContinuation<Void, Never>)] = []
        for entry in waiters {
            if count >= entry.target {
                entry.cont.resume()
            } else {
                remaining.append(entry)
            }
        }
        waiters = remaining
    }

    func wait(untilAtLeast target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }
}

private final class MockSourcePickerSessionClient: SourcePickerSessionClient, @unchecked Sendable {
    let prepareGate = TestStepGate()
    let heartbeatSignal = SourcePickerHeartbeatSignal()
    let log = TestLockedBox<[String]>([])
    let stoppedSessions = TestLockedBox<[String]>([])
    let fetchAlternativesCount = TestLockedBox<Int>(0)
    let prepareCount = TestLockedBox<Int>(0)
    let sessionIdToReturn: String
    let prepareTokenToReturn: String
    let gatePrepare: Bool
    let failAlternativesOnce: Bool

    init(
        sessionIdToReturn: String = "sess-orphan-1",
        prepareTokenToReturn: String = "prep-tok-1",
        gatePrepare: Bool = true,
        failAlternativesOnce: Bool = false
    ) {
        self.sessionIdToReturn = sessionIdToReturn
        self.prepareTokenToReturn = prepareTokenToReturn
        self.gatePrepare = gatePrepare
        self.failAlternativesOnce = failAlternativesOnce
    }

    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?
    ) async throws -> TvPrepareResponse {
        let idx = prepareCount.withLock { count -> Int in
            count += 1
            return count
        }
        if gatePrepare {
            await prepareGate.wait(label: "prepare", log: log)
        }
        let sid = idx == 1 ? sessionIdToReturn : "\(sessionIdToReturn)-\(idx)"
        let tok = idx == 1 ? prepareTokenToReturn : "\(prepareTokenToReturn)-\(idx)"
        let json = """
        {
          "ok": true,
          "status": "ready",
          "prepareToken": "\(tok)",
          "playbackSession": {
            "sessionId": "\(sid)",
            "streamToken": "stream-placeholder-token",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512",
            "item": {
              "itemId": "\(itemId)",
              "mediaType": "movie",
              "ids": { "tmdb": 550 },
              "title": "\(title)"
            },
            "selectedCandidate": {
              "candidateId": "cand-1",
              "displayHeadline": "4K",
              "releaseTitle": "Movie.2024.2160p",
              "source": "nvme"
            },
            "stream": { "url": "/api/tv/v1/streams/\(sid)/master" },
            "aetherConfig": {
              "preferDualLayerDolbyVision": false,
              "dolbyVisionHandling": "baseLayerOnly",
              "matchContentEnabled": true,
              "audioBridgeMode": "lossless"
            }
          }
        }
        """
        return try JSONDecoder().decode(TvPrepareResponse.self, from: Data(json.utf8))
    }

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        let callIndex = fetchAlternativesCount.withLock { count -> Int in
            count += 1
            return count
        }
        if failAlternativesOnce && callIndex == 1 {
            throw LunaCoreError.serverMessage(404, "Expired session")
        }
        let json = """
        {
          "ok": true,
          "sessionId": "\(sessionId)",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "activeCandidateId": "cand-1",
          "alternatives": [
            {
              "candidateId": "cand-1",
              "displayHeadline": "4K",
              "releaseTitle": "Movie.2024.2160p",
              "source": "nvme",
              "isActive": true
            }
          ]
        }
        """
        return try JSONDecoder().decode(TvAlternativesResponse.self, from: Data(json.utf8))
    }

    func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?
    ) async throws -> TvHeartbeatResponse {
        if state == "stopped" {
            stoppedSessions.withLock { $0.append(sessionId) }
            await heartbeatSignal.record()
        }
        let json = """
        {
          "ok": true,
          "sessionId": "\(sessionId)",
          "state": "\(state)",
          "vfsLockActive": false
        }
        """
        return try JSONDecoder().decode(TvHeartbeatResponse.self, from: Data(json.utf8))
    }
}

final class ClientOriginAndBlurHashTests: XCTestCase {
    @MainActor
    func testNormalizeServerURLTrimsAddsSchemeAndRejectsEmpty() {
        XCTAssertEqual(
            AppSessionStore.normalizeServerURL("  https://tv.example.test:8920/api/tv/v1/ ")?.absoluteString,
            "https://tv.example.test:8920"
        )
        XCTAssertEqual(
            AppSessionStore.normalizeServerURL("lunacore.local:8090///")?.absoluteString,
            "http://lunacore.local:8090"
        )
        XCTAssertNil(AppSessionStore.normalizeServerURL("   "))
    }

    func testLunaCoreClientSameOriginChecks() throws {
        let tlsClient = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "https://tv.example.test:8920")),
            deviceID: "luna-test-device",
            deviceToken: "token-placeholder",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )

        XCTAssertTrue(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://tv.example.test:8920/api/tv/v1/img/1"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://image.tmdb.example.net/t/p/original/a.jpg"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://tv.example.test:8090/api/tv/v1/img/1"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "http://tv.example.test:8920/api/tv/v1/img/1"))))

        let defaultPortClient = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "https://cdn.example.net")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: false
        )
        XCTAssertTrue(defaultPortClient.isSameOrigin(try XCTUnwrap(URL(string: "https://cdn.example.net:443/poster.webp"))))
    }

    func testBlurHashDecodeAndCacheKeyDifferentiatesPunch() {
        let sampleHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

        let standard = BlurHashDecoder.decode(sampleHash, width: 32, height: 24, punch: 1.0)
        XCTAssertNotNil(standard)
        XCTAssertEqual(standard?.width, 32)
        XCTAssertEqual(standard?.height, 24)

        let punched = BlurHashDecoder.decode(sampleHash, width: 32, height: 24, punch: 1.4)
        XCTAssertNotNil(punched)

        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.0))
        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.4))

        XCTAssertNil(BlurHashDecoder.decode("short", width: 32, height: 24, punch: 1.0))
        XCTAssertNil(BlurHashDecoder.decode(nil, width: 32, height: 24, punch: 1.0))

        let defaultSized = BlurHashDecoder.decode(sampleHash)
        XCTAssertNotNil(defaultSized)
        XCTAssertEqual(defaultSized?.width, 32)
        XCTAssertEqual(defaultSized?.height, 18)

        let invalidCharset = "!EV6nWB2yk8pyo0adR*.7kCMdnj"
        XCTAssertNil(BlurHashDecoder.decode(invalidCharset, width: 32, height: 18, punch: 1.0))
    }

    func testBlurHashDecodeAsyncDeduplicatesConcurrentCallersAndPreservesActiveWaiterOnCancel() async throws {
        let sampleHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        BlurHashDecoder.clearCache()
        BlurHashDecoder.resetMetrics()
        defer { BlurHashDecoder.clearCache() }

        let invalid = await BlurHashDecoder.decodeAsync("bad", width: 64, height: 48)
        XCTAssertNil(invalid)
        let zeroDim = await BlurHashDecoder.decodeAsync(sampleHash, width: 0, height: 48)
        XCTAssertNil(zeroDim)

        let results = await withTaskGroup(of: CGImage?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await BlurHashDecoder.decodeAsync(sampleHash, width: 64, height: 48, punch: 1.0)
                }
            }
            var collected: [CGImage] = []
            for await item in group {
                if let item {
                    collected.append(item)
                }
            }
            return collected
        }

        XCTAssertEqual(results.count, 12)
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.width, 64)
        XCTAssertEqual(first.height, 48)
        for image in results {
            XCTAssertTrue(image === first, "Concurrent BlurHash callers should share one decoded CGImage")
        }
        let metrics = BlurHashDecoder.metricsSnapshot()
        XCTAssertEqual(metrics.actualDecodes, 1)
        XCTAssertEqual(metrics.coalescedWaiters + metrics.cacheHits, 11)

        // Cancelling one waiter while a peer is active must still deliver the decoded image to the peer.
        BlurHashDecoder.clearCache()
        BlurHashDecoder.resetMetrics()
        let cancelledTask = Task {
            await BlurHashDecoder.decodeAsync(sampleHash, width: 48, height: 36, punch: 1.0)
        }
        let activeTask = Task {
            await BlurHashDecoder.decodeAsync(sampleHash, width: 48, height: 36, punch: 1.0)
        }
        cancelledTask.cancel()
        _ = await cancelledTask.value
        let activeImage = await activeTask.value
        XCTAssertNotNil(activeImage)
        XCTAssertEqual(activeImage?.width, 48)
        XCTAssertEqual(activeImage?.height, 36)
        let cancelMetrics = BlurHashDecoder.metricsSnapshot()
        XCTAssertGreaterThanOrEqual(cancelMetrics.actualDecodes, 1)
        XCTAssertLessThanOrEqual(cancelMetrics.actualDecodes, 2)

        // Pre-cancelled caller returns nil deterministically without decoding.
        BlurHashDecoder.clearCache()
        BlurHashDecoder.resetMetrics()
        let preCancelled = Task { () -> CGImage? in
            while !Task.isCancelled {
                await Task.yield()
            }
            return await BlurHashDecoder.decodeAsync(sampleHash, width: 32, height: 24, punch: 1.0)
        }
        preCancelled.cancel()
        let cancelledResult = await preCancelled.value
        XCTAssertNil(cancelledResult)
        XCTAssertEqual(BlurHashDecoder.metricsSnapshot().actualDecodes, 0)
    }

    @MainActor
    func testResetAllConnectionSettingsClearsConfiguredTLSHostAndPolicy() throws {
        let suite = "luna.test.resetconnection.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSessionStore(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "https://media-box.example.test:8920"))
        store.completePairing(
            baseURL: url,
            token: "test-token-value-1234",
            pairedDevice: TvPairedDeviceInfo(
                deviceId: store.deviceID,
                deviceName: "Apple TV",
                roomName: "Stua",
                hardwareProfile: "hdr10-512",
                overrides: TvDeviceOverrides()
            )
        )
        XCTAssertEqual(store.appliedTLSConfiguredHost, "media-box.example.test")
        XCTAssertTrue(
            AppSessionStore.shouldTrustServerHost(
                "media-box.example.test",
                configuredHost: store.appliedTLSConfiguredHost,
                allowSelfSignedLanTLS: store.allowSelfSignedLanTLS
            )
        )

        store.resetAllConnectionSettings()

        XCTAssertNil(store.serverBaseURL)
        XCTAssertNil(store.deviceToken)
        XCTAssertNil(store.appliedTLSConfiguredHost)
        XCTAssertFalse(
            AppSessionStore.shouldTrustServerHost(
                "media-box.example.test",
                configuredHost: store.appliedTLSConfiguredHost,
                allowSelfSignedLanTLS: store.allowSelfSignedLanTLS
            )
        )
        XCTAssertTrue(
            AppSessionStore.shouldTrustServerHost(
                "lunacore.local",
                configuredHost: store.appliedTLSConfiguredHost,
                allowSelfSignedLanTLS: store.allowSelfSignedLanTLS
            )
        )
    }

    func testSourcePickerTokenPolicyClearsExpiredExistingPrepareTokenOnRetry() {
        XCTAssertEqual(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: " prep-tok-1 ",
                existingTokenFailed: false
            ),
            "prep-tok-1"
        )
        XCTAssertNil(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: "prep-tok-1",
                existingTokenFailed: true
            )
        )
        XCTAssertNil(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: "   ",
                existingTokenFailed: false
            )
        )
    }

    @MainActor
    func testSourcePickerCancellationDuringInFlightPrepareStopsOrphanSessionWithoutLeaking() async {
        let context = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club"
        )

        // 1. Sheet dismisses (.onDisappear + task cancel) while preparePlayback is in-flight:
        //    newly returned sessionId MUST be stopped immediately via sendHeartbeat(state: "stopped")
        //    and MUST NOT record createdOrphanSessionId or call fetchAlternatives.
        let cancelledClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-orphan-cancel-1",
            prepareTokenToReturn: "prep-cancel-1"
        )
        let vm = SourcePickerViewModel()
        let loadTask = Task { @MainActor in
            await vm.loadCandidates(context: context, client: cancelledClient, onUnauthorized: {})
        }

        await cancelledClient.prepareGate.waitUntilStarted()
        vm.handleDisappear(context: context, client: cancelledClient)
        loadTask.cancel()
        await cancelledClient.prepareGate.finish()
        await loadTask.value
        await cancelledClient.heartbeatSignal.wait(untilAtLeast: 1)

        XCTAssertEqual(cancelledClient.stoppedSessions.withLock { $0 }, ["sess-orphan-cancel-1"])
        XCTAssertEqual(cancelledClient.fetchAlternativesCount.withLock { $0 }, 0)
        XCTAssertNil(vm.createdOrphanSessionId)
        XCTAssertNil(vm.resolvedPrepareToken)
        XCTAssertTrue(vm.candidates.isEmpty)

        // 2. Non-cancelled load populates candidates & stops created session once on disappear.
        let activeClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-active-2",
            prepareTokenToReturn: "prep-active-2"
        )
        let activeVm = SourcePickerViewModel()
        let activeTask = Task { @MainActor in
            await activeVm.loadCandidates(context: context, client: activeClient, onUnauthorized: {})
        }
        await activeClient.prepareGate.waitUntilStarted()
        await activeClient.prepareGate.finish()
        await activeTask.value

        XCTAssertEqual(activeClient.fetchAlternativesCount.withLock { $0 }, 1)
        XCTAssertTrue(activeClient.stoppedSessions.withLock { $0 }.isEmpty)
        XCTAssertEqual(activeVm.createdOrphanSessionId, "sess-active-2")
        XCTAssertEqual(activeVm.resolvedPrepareToken, "prep-active-2")
        XCTAssertEqual(activeVm.candidates.count, 1)

        activeVm.handleDisappear(context: context, client: activeClient)
        await activeClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(activeClient.stoppedSessions.withLock { $0 }, ["sess-active-2"])
        XCTAssertNil(activeVm.createdOrphanSessionId)

        // 3. Existing token fails -> retry launches preparePlayback -> sheet dismissed before Task.cancel():
        //    isDismissed guard still stops the newly created session without leaking.
        let retryContext = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            existingPrepareToken: "stale-preresolve-tok"
        )
        let retryClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-retry-orphan-3",
            prepareTokenToReturn: "prep-retry-3",
            gatePrepare: true,
            failAlternativesOnce: true
        )
        let retryVm = SourcePickerViewModel()
        await retryVm.loadCandidates(context: retryContext, client: retryClient, onUnauthorized: {})
        XCTAssertTrue(retryVm.existingTokenFailed)
        XCTAssertEqual(retryClient.fetchAlternativesCount.withLock { $0 }, 1)

        let retryTask = Task { @MainActor in
            await retryVm.loadCandidates(context: retryContext, client: retryClient, onUnauthorized: {})
        }
        await retryClient.prepareGate.waitUntilStarted()
        retryVm.handleDisappear(context: retryContext, client: retryClient)
        await retryClient.prepareGate.finish()
        await retryTask.value
        await retryClient.heartbeatSignal.wait(untilAtLeast: 1)

        XCTAssertEqual(retryClient.stoppedSessions.withLock { $0 }, ["sess-retry-orphan-3"])
        XCTAssertEqual(retryClient.fetchAlternativesCount.withLock { $0 }, 1)
        XCTAssertNil(retryVm.createdOrphanSessionId)

        // 4. Non-cancellation fetchAlternatives failure stops created orphan session immediately before retry.
        let failAltClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-alt-fail",
            prepareTokenToReturn: "prep-alt-fail",
            gatePrepare: false,
            failAlternativesOnce: true
        )
        let failAltVm = SourcePickerViewModel()
        await failAltVm.loadCandidates(context: context, client: failAltClient, onUnauthorized: {})
        await failAltClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(failAltClient.stoppedSessions.withLock { $0 }, ["sess-alt-fail"])
        XCTAssertNil(failAltVm.createdOrphanSessionId)
        XCTAssertNotNil(failAltVm.errorMessage)

        await failAltVm.loadCandidates(context: context, client: failAltClient, onUnauthorized: {})
        XCTAssertNil(failAltVm.errorMessage)
        XCTAssertEqual(failAltVm.createdOrphanSessionId, "sess-alt-fail-2")
        failAltVm.handleDisappear(context: context, client: failAltClient)
        await failAltClient.heartbeatSignal.wait(untilAtLeast: 2)
        XCTAssertEqual(failAltClient.stoppedSessions.withLock { $0 }, ["sess-alt-fail", "sess-alt-fail-2"])

        // 5. Whitespace-only existingPrepareToken ("   ") is treated as nil on disappear
        //    so a newly created orphan session is still stopped cleanly on dismiss.
        let whitespaceContext = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            existingPrepareToken: "   "
        )
        let whitespaceClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-whitespace-orphan",
            prepareTokenToReturn: "prep-whitespace-1"
        )
        let whitespaceVm = SourcePickerViewModel()
        let whitespaceTask = Task { @MainActor in
            await whitespaceVm.loadCandidates(context: whitespaceContext, client: whitespaceClient, onUnauthorized: {})
        }
        await whitespaceClient.prepareGate.waitUntilStarted()
        await whitespaceClient.prepareGate.finish()
        await whitespaceTask.value
        whitespaceVm.handleDisappear(context: whitespaceContext, client: whitespaceClient)
        await whitespaceClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(whitespaceClient.stoppedSessions.withLock { $0 }, ["sess-whitespace-orphan"])
        XCTAssertNil(whitespaceVm.createdOrphanSessionId)
    }

    func testArtworkURLResolutionUpgradesFor4KWithoutDowngrading() {
        let client = LunaCoreClient(
            baseURL: URL(string: "https://media.example.invalid")!,
            deviceID: "dev-art",
            deviceToken: "tok-art",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: false
        )

        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w342/poster.jpg", target: .poster2x)?.absoluteString,
            "https://image.tmdb.org/t/p/w780/poster.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w780/backdrop.jpg", target: .landscape2x)?.absoluteString,
            "https://image.tmdb.org/t/p/w1280/backdrop.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w1280/hero.jpg", target: .hero4K)?.absoluteString,
            "https://image.tmdb.org/t/p/original/hero.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w1280/large.jpg", target: .poster2x)?.absoluteString,
            "https://image.tmdb.org/t/p/w1280/large.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v1/artwork?src=test&width=320", target: .hero4K)?.absoluteString,
            "https://media.example.invalid/api/tv/v1/artwork?src=test&width=3840"
        )
        XCTAssertNil(client.resolveArtworkURL("   ", target: .poster2x))
    }

    func testCanonicalSubjectIdentityBridgesTMDBAndQueryWidthVariantsAndGrayscaleDecodeFallback() async throws {
        let host = "artwork-gray-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            Task { await ArtworkPipeline.shared.clearAll() }
        }
        await ArtworkPipeline.shared.clearAll()

        let w1280URL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w1280/severance_hero.jpg"))
        let orig4KURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/original/severance_hero.jpg"))
        XCTAssertEqual(
            ArtworkPipeline.canonicalSubjectIdentity(for: w1280URL),
            ArtworkPipeline.canonicalSubjectIdentity(for: orig4KURL)
        )

        let lan1280 = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v1/artwork/backdrop?id=550&w=1280"))
        let lan3840 = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v1/artwork/backdrop?id=550&w=3840"))
        XCTAssertEqual(
            ArtworkPipeline.canonicalSubjectIdentity(for: lan1280),
            ArtworkPipeline.canonicalSubjectIdentity(for: lan3840)
        )

        let sampleCG = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 64, height: 36))
        ArtworkPipeline.shared.insertMemoryCachedImage(sampleCG, url: w1280URL, maxPixelSize: 1280)
        let bridgedHit = ArtworkPipeline.shared.anyMemoryCachedImage(for: orig4KURL, preferredMaxPixelSize: 3840)
        XCTAssertNotNil(bridgedHit, "4K original hero URL must immediately find cached w1280 shelf backdrop in 0 ms")
        XCTAssertTrue(bridgedHit?.image === sampleCG)

        // Verify 8-bit grayscale PNG decodes cleanly through `downsampleAndDecode` + `byPreparingForDisplay()` fallback
        let graySpace = CGColorSpaceCreateDeviceGray()
        var grayPixels = [UInt8](repeating: 180, count: 16 * 16)
        let grayCG: CGImage = try grayPixels.withUnsafeMutableBytes { rawBuf in
            let ctx = try XCTUnwrap(
                CGContext(
                    data: rawBuf.baseAddress,
                    width: 16,
                    height: 16,
                    bitsPerComponent: 8,
                    bytesPerRow: 16,
                    space: graySpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            )
            return try XCTUnwrap(ctx.makeImage())
        }
        let pngData = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, grayCG, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, pngData as Data)
        }
        let client = try MockURLProtocol.makeClient(host: host)
        let grayURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v1/img/grayscale.png"))
        let loadedGray = await ArtworkPipeline.shared.loadImage(url: grayURL, maxPixelSize: 256, client: client)
        XCTAssertNotNil(loadedGray, "Grayscale artwork must never be lost if byPreparingForDisplay() returns nil")
    }
}
