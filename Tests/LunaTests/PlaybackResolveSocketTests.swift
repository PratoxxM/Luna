import Foundation
import XCTest
@testable import Luna

final class PlaybackResolveSocketTests: XCTestCase {
    func testMakeWebSocketURLConversionAndEdgeCases() throws {
        let httpBase = try XCTUnwrap(URL(string: "http://lunacore.local:8090/"))
        let httpsBase = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920"))

        XCTAssertEqual(
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "/api/tv/v2/ws/resolve/abc")?.absoluteString,
            "ws://lunacore.local:8090/api/tv/v2/ws/resolve/abc"
        )
        XCTAssertEqual(
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpsBase, wsPath: "api/tv/v2/ws/resolve/abc?token=1")?.absoluteString,
            "wss://lunacore.example.test:8920/api/tv/v2/ws/resolve/abc?token=1"
        )
        XCTAssertEqual(
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "wss://direct.example.test/ws")?.absoluteString,
            "wss://direct.example.test/ws"
        )
        XCTAssertEqual(
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "ws://direct.example.test:8090/ws")?.absoluteString,
            "ws://direct.example.test:8090/ws"
        )
        XCTAssertEqual(
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "https://direct.example.test:8920/ws")?.absoluteString,
            "wss://direct.example.test:8920/ws"
        )
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "   "))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "/bad path with spaces"))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "ws://"))
        let hostlessBase = try XCTUnwrap(URL(string: "http:///"))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: hostlessBase, wsPath: "/api/tv/v2/ws/resolve/abc"))
    }

    func testEventsStreamThrowsInvalidURLImmediatelyForBlankPath() async throws {
        let base = try XCTUnwrap(URL(string: "http://lunacore.local:8090"))
        let socket = PlaybackResolveSocket(
            baseURL: base,
            wsPath: "  ",
            headers: [:],
            allowSelfSignedLanTLS: true
        )
        let provider: any PlaybackResolveSocketProviding = socket

        do {
            for try await _ in provider.events() {
                XCTFail("Expected invalidURL error")
            }
            XCTFail("Stream should have thrown invalidURL")
        } catch let error as LunaCoreError {
            guard case .invalidURL = error else {
                XCTFail("Expected LunaCoreError.invalidURL, got \(error)")
                return
            }
        }
    }

    func testParseMessageDecodesProgressReadyFailedAndRejectsMalformedJSON() throws {
        let progressText = #"""
        {"type":"resolve.progress","resolveId":"res-1","stage":"searching","percent":45,"winnerHeadline":"4K Remux","message":"Søker…"}
        """#
        let progressEvent = try XCTUnwrap(PlaybackResolveSocket.parseMessage(.string(progressText)))
        XCTAssertEqual(progressEvent.type, "resolve.progress")
        XCTAssertEqual(progressEvent.percent, 45)
        XCTAssertEqual(progressEvent.winnerHeadline, "4K Remux")
        XCTAssertFalse(PlaybackResolveSocket.isTerminalEvent(progressEvent))

        let failedData = Data(#"{"type":"resolve.failed","resolveId":"res-1","error":"Ingen kilder funnet"}"#.utf8)
        let failedEvent = try XCTUnwrap(PlaybackResolveSocket.parseMessage(.data(failedData)))
        XCTAssertEqual(failedEvent.type, "resolve.failed")
        XCTAssertEqual(failedEvent.error, "Ingen kilder funnet")
        XCTAssertTrue(PlaybackResolveSocket.isTerminalEvent(failedEvent))

        let readyText = #"""
        {
          "type": "resolve.ready",
          "resolveId": "res-1",
          "playbackSession": {
            "sessionId": "sess-1",
            "streamToken": "stream-placeholder-token",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512",
            "item": { "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": {"tmdb": 550}, "title": "Fight Club" },
            "selectedCandidate": { "candidateId": "c1", "displayHeadline": "4K", "releaseTitle": "Rel", "source": "nvme" },
            "stream": { "url": "/api/tv/v2/streams/sess-1/master" },
            "aetherConfig": {
              "preferDualLayerDolbyVision": false,
              "dolbyVisionHandling": "baseLayerOnly",
              "matchContentEnabled": true,
              "audioBridgeMode": "lossless"
            }
          }
        }
        """#
        let readyEvent = try XCTUnwrap(PlaybackResolveSocket.parseMessage(.string(readyText)))
        XCTAssertEqual(readyEvent.type, "resolve.ready")
        XCTAssertEqual(readyEvent.playbackSession?.sessionId, "sess-1")
        XCTAssertTrue(PlaybackResolveSocket.isTerminalEvent(readyEvent))

        XCTAssertThrowsError(try PlaybackResolveSocket.parseMessage(.string("{not json"))) { err in
            guard case LunaCoreError.decodingFailed = err else {
                XCTFail("Expected decodingFailed, got \(err)")
                return
            }
        }
    }
}
