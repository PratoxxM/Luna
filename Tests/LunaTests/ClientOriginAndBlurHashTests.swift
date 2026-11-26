import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import Luna

final class ClientOriginAndBlurHashTests: XCTestCase {
    @MainActor
    func testNormalizeServerURLTrimsAddsSchemeAndRejectsEmpty() {
        XCTAssertEqual(
            AppSessionStore.normalizeServerURL("  https://tv.example.test:8920/api/tv/v2/ ")?.absoluteString,
            "https://tv.example.test:8920"
        )
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

        XCTAssertTrue(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://tv.example.test:8920/api/tv/v2/img/1"))))
        XCTAssertTrue(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "http://tv.example.test:8090/api/tv/v2/stream/s1/tok/v.mkv"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://image.tmdb.example.net/t/p/original/a.jpg"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "http://tv.example.test:9999/api/tv/v2/img/1"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "https://tv.example.test:8090/api/tv/v2/img/1"))))
        XCTAssertFalse(tlsClient.isSameOrigin(try XCTUnwrap(URL(string: "http://tv.example.test:8920/api/tv/v2/img/1"))))

        let lanStreamURL = try XCTUnwrap(URL(string: "http://tv.example.test:8090/api/tv/v2/stream/s1/tok/v.mkv"))
        let foreignStreamURL = try XCTUnwrap(URL(string: "https://cdn.example.net/video.mkv"))
        XCTAssertEqual(tlsClient.streamHTTPHeaders(for: lanStreamURL)["Authorization"], "Bearer token-placeholder")
        XCTAssertNil(tlsClient.streamHTTPHeaders(for: foreignStreamURL)["Authorization"])
        XCTAssertNil(tlsClient.streamHTTPHeaders(for: foreignStreamURL)["X-Device-Id"])

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

        // Cancelling one waiter while a peer is active must still deliver the decoded image to the peer.
        BlurHashDecoder.clearCache()
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

        // Pre-cancelled caller returns nil deterministically without caching.
        BlurHashDecoder.clearCache()
        let preCancelled = Task { () -> CGImage? in
            while !Task.isCancelled {
                await Task.yield()
            }
            return await BlurHashDecoder.decodeAsync(sampleHash, width: 32, height: 24, punch: 1.0)
        }
        preCancelled.cancel()
        let cancelledResult = await preCancelled.value
        XCTAssertNil(cancelledResult)
        XCTAssertNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.0))
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
            client.resolveArtworkURL("/api/tv/v2/artwork?src=test&width=320", target: .hero4K)?.absoluteString,
            "https://media.example.invalid/api/tv/v2/artwork?src=test&width=3840"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v2/img/card/tmdb/hero.jpg", target: .hero4K)?.absoluteString,
            "https://media.example.invalid/api/tv/v2/img/backdrop/tmdb/hero.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v2/img/card/tmdb/hero.jpg", target: .landscape2x)?.absoluteString,
            "https://media.example.invalid/api/tv/v2/img/card/tmdb/hero.jpg"
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

        let lanCard = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/card/tmdb/severance_hero.jpg"))
        let lanBackdrop = try XCTUnwrap(URL(string: "https://\(host):8920/api/tv/v2/img/backdrop/tmdb/severance_hero.jpg"))
        XCTAssertEqual(
            ArtworkPipeline.canonicalSubjectIdentity(for: lanCard),
            ArtworkPipeline.canonicalSubjectIdentity(for: lanBackdrop)
        )

        let lan1280 = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/artwork/backdrop?id=550&w=1280"))
        let lan3840 = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/artwork/backdrop?id=550&w=3840"))
        XCTAssertEqual(
            ArtworkPipeline.canonicalSubjectIdentity(for: lan1280),
            ArtworkPipeline.canonicalSubjectIdentity(for: lan3840)
        )

        let sampleCG = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 64, height: 36))
        ArtworkPipeline.shared.insertMemoryCachedImage(sampleCG, url: w1280URL, maxPixelSize: 1280)
        let bridgedHit = ArtworkPipeline.shared.anyMemoryCachedImage(for: orig4KURL, preferredMaxPixelSize: 3840)
        XCTAssertNotNil(bridgedHit, "4K original hero URL must immediately find cached w1280 shelf backdrop in 0 ms")
        XCTAssertTrue(bridgedHit?.image === sampleCG)

        // Verify 8-bit grayscale PNG decodes cleanly through `downsampleAndDecode` + native-dimension clamping (16px requested at 1920px stays 16x16)
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
        let pngBytes = pngData as Data

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, pngBytes)
        }
        let client = try MockURLProtocol.makeClient(host: host)
        let grayURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/grayscale.png"))
        let loadedGray = await ArtworkPipeline.shared.loadImage(url: grayURL, maxPixelSize: 1920, client: client)
        XCTAssertNotNil(loadedGray, "Grayscale artwork must never be lost if byPreparingForDisplay() returns nil")
        XCTAssertEqual(loadedGray?.width, 16, "downsampleAndDecode must clamp maxPixelSize to native pixel dimensions")
        XCTAssertEqual(loadedGray?.height, 16)
    }
}
