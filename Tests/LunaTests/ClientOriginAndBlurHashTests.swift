import CoreGraphics
import XCTest
@testable import Luna

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
    }
}
