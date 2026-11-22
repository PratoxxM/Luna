import Foundation
import XCTest
@testable import Luna

final class LunaCoreHTTPTransportTests: XCTestCase {
    func testConditionalHomeReturns304NotModifiedAnd200UpdatedWithETag() async throws {
        let host = "transport-home-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let homeJSON = #"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"etag-home-1\"" {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: nil))
                return (resp, Data())
            }
            let resp = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"etag-home-1\"", "Content-Type": "application/json"]
                )
            )
            return (resp, Data(homeJSON.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)
        let first = try await client.fetchHomeConditional(ifNoneMatch: nil)
        switch first {
        case .updated(let payload, let etag, let rawData):
            XCTAssertEqual(etag, "\"etag-home-1\"")
            XCTAssertEqual(payload.roomName, "Stua")
            XCTAssertFalse(rawData.isEmpty)
        case .notModified:
            XCTFail("Expected .updated on initial home fetch")
        }

        let second = try await client.fetchHomeConditional(ifNoneMatch: "\"etag-home-1\"")
        switch second {
        case .notModified:
            break
        case .updated:
            XCTFail("Expected .notModified when server responds 304")
        }
    }

    func testUnifiedErrorMappingFor401ServerMessageAndMalformedJSON() async throws {
        let host = "transport-err-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/api/tv/v1/bootstrap":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
                return (resp, Data())
            case "/api/tv/v1/library":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"error":"Arkivet vedlikeholdes"}"#.utf8))
            default:
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data("not-json".utf8))
            }
        }

        let client = try MockURLProtocol.makeClient(host: host)

        do {
            _ = try await client.fetchBootstrap()
            XCTFail("Expected 401 unauthorized")
        } catch LunaCoreError.unauthorized {
            // expected
        }

        do {
            _ = try await client.fetchLibrary()
            XCTFail("Expected 503 serverMessage")
        } catch LunaCoreError.serverMessage(let status, let msg) {
            XCTAssertEqual(status, 503)
            XCTAssertEqual(msg, "Arkivet vedlikeholdes")
        }

        do {
            _ = try await client.searchFull(query: "dune")
            XCTFail("Expected decodingFailed")
        } catch LunaCoreError.decodingFailed {
            // expected
        }
    }

    func testPairingPollStatusesAndResolvePlaybackStatusPassthrough() async throws {
        let host = "transport-pair-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/111111") {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"error":"Kode utløpt"}"#.utf8))
            }
            if url.path.hasSuffix("/222222") {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil))
                return (resp, Data())
            }
            if url.path.hasSuffix("/333333") {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true,"status":"approved","deviceToken":"tok-123"}"#.utf8))
            }
            if url.path == "/api/tv/v1/playback/resolve" {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil))
                let body = #"{"ok":true,"status":"resolving","resolveId":"res-99","wsPath":"/api/tv/v1/ws/resolve/res-99"}"#
                return (resp, Data(body.utf8))
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)

        let expired = try await client.pollPairingCode("111-111")
        XCTAssertEqual(expired.httpStatus, 404)
        XCTAssertEqual(expired.response.status, "expired")
        XCTAssertEqual(expired.response.error, "Kode utløpt")

        let rateLimited = try await client.pollPairingCode("222222")
        XCTAssertEqual(rateLimited.httpStatus, 429)
        XCTAssertEqual(rateLimited.response.status, "rate_limited")

        let approved = try await client.pollPairingCode("333 333")
        XCTAssertEqual(approved.httpStatus, 200)
        XCTAssertEqual(approved.response.status, "approved")
        XCTAssertEqual(approved.response.deviceToken, "tok-123")

        let (resolveStatus, resolveStart) = try await client.resolvePlayback(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            seriesTitle: nil,
            startPositionSeconds: 0,
            candidateId: nil
        )
        XCTAssertEqual(resolveStatus, 202)
        XCTAssertEqual(resolveStart.resolveId, "res-99")
        XCTAssertEqual(resolveStart.wsPath, "/api/tv/v1/ws/resolve/res-99")

        try await client.updateDeviceProfile(roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
        let reqs = MockURLProtocol.requests(forHost: host)
        let patchReq = reqs.last
        XCTAssertEqual(patchReq?.httpMethod, "PATCH")
        XCTAssertEqual(patchReq?.value(forHTTPHeaderField: "Authorization"), "Bearer test-device-token")
        XCTAssertNil(patchReq?.value(forHTTPHeaderField: "X-Room-Name"))
        XCTAssertNil(patchReq?.value(forHTTPHeaderField: "X-Hardware-Profile"))
        XCTAssertNotNil(patchReq?.value(forHTTPHeaderField: "X-Supports-HW-AV1"))
        XCTAssertNotNil(patchReq?.value(forHTTPHeaderField: "X-Physical-Memory-GB"))
    }

    func testFetchRawImageDataSendsAuthOnlyToSameOriginAndExcludesRoomProfileHeaders() async throws {
        let lanHost = "transport-img-\(UUID().uuidString.lowercased()).local"
        let cdnHost = "cdn-img-\(UUID().uuidString.lowercased()).example.net"
        defer {
            MockURLProtocol.unregister(host: lanHost)
            MockURLProtocol.unregister(host: cdnHost)
        }

        let sampleBytes = Data([0x52, 0x49, 0x46, 0x46])
        MockURLProtocol.register(host: lanHost) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, sampleBytes)
        }
        MockURLProtocol.register(host: cdnHost) { request in
            let url = try XCTUnwrap(request.url)
            if url.path.contains("fail") {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                return (resp, Data())
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, sampleBytes)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let baseURL = try XCTUnwrap(URL(string: "http://\(lanHost):8090"))
        let client = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-test-device",
            deviceToken: "secret-lan-token",
            roomName: "Sør-Stua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true,
            appVersion: "2.7.0",
            osVersion: "tvOS 26.0",
            session: session,
            imageSession: session
        )

        let headers = client.streamHTTPHeaders()
        XCTAssertEqual(headers["Authorization"], "Bearer secret-lan-token")
        XCTAssertNil(headers["X-Room-Name"])
        XCTAssertNil(headers["X-Hardware-Profile"])
        XCTAssertNotNil(headers["X-Supports-HW-AV1"])
        XCTAssertNotNil(headers["X-Physical-Memory-GB"])

        let sameOriginURL = try XCTUnwrap(URL(string: "http://\(lanHost):8090/api/tv/v1/img/poster.webp"))
        let (sameData, _) = try await client.fetchRawImageData(from: sameOriginURL)
        XCTAssertEqual(sameData, sampleBytes)
        let lanReq = try XCTUnwrap(MockURLProtocol.requests(forHost: lanHost).last)
        XCTAssertEqual(lanReq.value(forHTTPHeaderField: "Authorization"), "Bearer secret-lan-token")
        XCTAssertEqual(lanReq.value(forHTTPHeaderField: "X-Device-Id"), "luna-test-device")

        let externalURL = try XCTUnwrap(URL(string: "https://\(cdnHost)/poster.jpg"))
        let (extData, _) = try await client.fetchRawImageData(from: externalURL)
        XCTAssertEqual(extData, sampleBytes)
        let extReq = try XCTUnwrap(MockURLProtocol.requests(forHost: cdnHost).last)
        XCTAssertNil(extReq.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(extReq.value(forHTTPHeaderField: "X-Device-Id"))

        let missingExternalURL = try XCTUnwrap(URL(string: "https://\(cdnHost)/fail.jpg"))
        do {
            _ = try await client.fetchRawImageData(from: missingExternalURL)
            XCTFail("Expected HTTP 404 serverMessage")
        } catch LunaCoreError.serverMessage(let code, _) {
            XCTAssertEqual(code, 404)
        }
    }

    func testConcurrentIdempotentGETRequestsCoalesceWhilePOSTMutationsNeverCoalesce() async throws {
        let host = "coalesce-transport-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let bootstrapJSON = #"""
        {
          "ok": true,
          "device": {
            "deviceId": "luna-test-device",
            "deviceName": "Stua TV",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512"
          },
          "defaultRooms": []
        }
        """#

        let getCount = TestLockedBox(0)
        let postCount = TestLockedBox(0)

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if request.httpMethod == "GET" && url.path == "/api/tv/v1/bootstrap" {
                getCount.withLock { $0 += 1 }
                try await Task.sleep(nanoseconds: 50_000_000)
                return (resp, Data(bootstrapJSON.utf8))
            }
            if request.httpMethod == "POST" && url.path == "/api/tv/v1/watchlist" {
                postCount.withLock { $0 += 1 }
                try await Task.sleep(nanoseconds: 40_000_000)
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)

        let bootstraps = try await withThrowingTaskGroup(of: TvBootstrapResponse.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await client.fetchBootstrap()
                }
            }
            var out: [TvBootstrapResponse] = []
            for try await item in group {
                out.append(item)
            }
            return out
        }
        XCTAssertEqual(bootstraps.count, 6)
        XCTAssertEqual(getCount.withLock { $0 }, 1, "6 concurrent identical GET /bootstrap calls must coalesce into 1 wire request")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for idx in 0..<4 {
                group.addTask {
                    try await client.setWatchlist(
                        listed: idx.isMultiple(of: 2),
                        mediaType: "movie",
                        ids: TvMediaIds(tmdb: 550),
                        title: "Fight Club",
                        year: 1999
                    )
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(postCount.withLock { $0 }, 4, "POST mutations must never coalesce")
    }
}
