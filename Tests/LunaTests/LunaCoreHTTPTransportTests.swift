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
        XCTAssertEqual(patchReq?.value(forHTTPHeaderField: "X-Room-Name"), "Stua")
    }
}
