import Foundation
import XCTest
@testable import Luna

final class LunaCoreSessionPoolTests: XCTestCase {
    override func tearDown() {
        LunaCoreSessionPool.shared.invalidateAll()
        super.tearDown()
    }

    func testPoolReusesSessionsByLaneOriginAndTLSAndEvictsOnInvalidate() throws {
        let pool = LunaCoreSessionPool.shared
        pool.invalidateAll()

        let urlA = try XCTUnwrap(URL(string: "https://lunacore.local:8920"))
        let urlSameOriginUpper = try XCTUnwrap(URL(string: "HTTPS://LUNACORE.LOCAL:8920/api/tv/v1/home"))
        let urlDifferentPort = try XCTUnwrap(URL(string: "https://lunacore.local:8090"))

        let api1 = pool.session(for: urlA, allowSelfSignedLanTLS: true)
        let api2 = pool.session(for: urlSameOriginUpper, allowSelfSignedLanTLS: true)
        XCTAssertTrue(api1 === api2, "Same lane, scheme, host, port, and TLS flag must reuse URLSession")

        let art1 = pool.artworkSession(for: urlA, allowSelfSignedLanTLS: true)
        let ws1 = pool.webSocketSession(for: urlA, allowSelfSignedLanTLS: true)
        let ext1 = pool.externalArtworkSession()
        let ext2 = pool.externalArtworkSession()

        XCTAssertTrue(api1 !== art1)
        XCTAssertTrue(api1 !== ws1)
        XCTAssertTrue(art1 !== ws1)
        XCTAssertTrue(ext1 === ext2)
        XCTAssertTrue(art1 !== ext1)

        let strictTLS = pool.session(for: urlA, allowSelfSignedLanTLS: false)
        let otherPort = pool.session(for: urlDifferentPort, allowSelfSignedLanTLS: true)
        XCTAssertTrue(api1 !== strictTLS)
        XCTAssertTrue(api1 !== otherPort)

        pool.invalidateAll()
        let recreated = pool.session(for: urlA, allowSelfSignedLanTLS: true)
        XCTAssertTrue(api1 !== recreated)
    }

    func testPoolConcurrentAccessReturnsConsistentSessionInstances() async throws {
        let pool = LunaCoreSessionPool.shared
        pool.invalidateAll()
        let url = try XCTUnwrap(URL(string: "http://lunacore.local:8090"))

        let collected = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let s = pool.session(for: url, allowSelfSignedLanTLS: true)
                    return ObjectIdentifier(s)
                }
            }
            var ids = Set<ObjectIdentifier>()
            for await id in group {
                ids.insert(id)
            }
            return ids
        }

        XCTAssertEqual(collected.count, 1)
    }

    func testLanURLSessionDelegateTrustPolicy() {
        XCTAssertTrue(
            LanURLSessionDelegate.shouldTrustServer(
                host: "LunaCore.Example.Test",
                trustedHost: "lunacore.example.test",
                allowSelfSignedTLS: true
            )
        )
        XCTAssertTrue(
            LanURLSessionDelegate.shouldTrustServer(
                host: "nas-box.local",
                trustedHost: nil,
                allowSelfSignedTLS: true
            )
        )
        XCTAssertFalse(
            LanURLSessionDelegate.shouldTrustServer(
                host: "external.example.net",
                trustedHost: "lunacore.example.test",
                allowSelfSignedTLS: true
            )
        )
        XCTAssertFalse(
            LanURLSessionDelegate.shouldTrustServer(
                host: "nas-box.local",
                trustedHost: "nas-box.local",
                allowSelfSignedTLS: false
            )
        )
        XCTAssertFalse(
            LanURLSessionDelegate.shouldTrustServer(
                host: "",
                trustedHost: "",
                allowSelfSignedTLS: true
            )
        )
    }
}
