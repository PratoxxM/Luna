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
            AppSessionStore.normalizeServerURL("mediaos.local:8090///")?.absoluteString,
            "http://mediaos.local:8090"
        )
        XCTAssertNil(AppSessionStore.normalizeServerURL("   "))
    }

    func testMediaOSClientSameOriginChecks() throws {
        let tlsClient = MediaOSClient(
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

        let defaultPortClient = MediaOSClient(
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
    }
}
