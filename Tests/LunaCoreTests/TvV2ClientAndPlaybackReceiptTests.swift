import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class TvV2URLProtocolMock: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host.lowercased()] = handler }
    }

    static func unregister(host: String) {
        _ = handlers.withLock { $0.removeValue(forKey: host.lowercased()) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockResolveSocket: PlaybackResolveSocketProviding {
    let emitted: [TvResolveSocketEvent]
    let failure: (any Error)?

    func events() -> AsyncThrowingStream<TvResolveSocketEvent, Error> {
        let emitted = self.emitted
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            for evt in emitted {
                continuation.yield(evt)
            }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }
}

final class TvV2ClientAndPlaybackReceiptTests: XCTestCase {
    private func makeClient(host: String) throws -> LunaCoreClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TvV2URLProtocolMock.self]
        let session = URLSession(configuration: config)
        return LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "https://\(host):8920")),
            deviceID: "luna-linux-v2",
            deviceToken: "tok-v2",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true,
            appVersion: "3.0.0",
            osVersion: "tvOS 26.0",
            session: session
        )
    }

    func testInflightCoalescerDisambiguatesResponseTypesAndETags() async throws {
        let host = "coalesce-type-\(UUID().uuidString.lowercased()).example.test"
        defer { TvV2URLProtocolMock.unregister(host: host) }

        struct ProbeA: Decodable, Sendable { let a: String }
        struct ProbeB: Decodable, Sendable { let b: Int }
        let hitCount = Mutex(0)

        TvV2URLProtocolMock.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            hitCount.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.02)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"v1\""]))
            return (resp, Data(#"{"a":"ok","b":42}"#.utf8))
        }

        let client = try makeClient(host: host)
        async let resA: ProbeA = client.sendJSON(method: "GET", path: "/api/tv/v2/shared")
        async let resB: ProbeB = client.sendJSON(method: "GET", path: "/api/tv/v2/shared")
        let (a, b) = try await (resA, resB)
        XCTAssertEqual(a.a, "ok")
        XCTAssertEqual(b.b, 42)
        XCTAssertEqual(hitCount.withLock { $0 }, 2, "Distinct Response types on same path must not collide")

        async let c1: ConditionalHTTPResult<ProbeA> = client.sendConditionalGET(path: "/api/tv/v2/shared", ifNoneMatch: "\"e1\"")
        async let c2: ConditionalHTTPResult<ProbeA> = client.sendConditionalGET(path: "/api/tv/v2/shared", ifNoneMatch: "\"e2\"")
        _ = try await (c1, c2)
        XCTAssertEqual(hitCount.withLock { $0 }, 4, "Distinct If-None-Match values must not coalesce together")
    }

    func testTvV2EndpointsLibrary304SubtitlesAndSessionFields() async throws {
        let host = "tv-v2-api-\(UUID().uuidString.lowercased()).example.test"
        defer { TvV2URLProtocolMock.unregister(host: host) }
        let seenPaths = Mutex<[String]>([])

        TvV2URLProtocolMock.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            seenPaths.withLock { $0.append("\(req.httpMethod ?? "GET") \(url.path)") }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"lib-v2\""]))
            switch url.path {
            case "/api/tv/v2/bootstrap":
                return (resp, Data(#"{"ok":true,"device":{"deviceId":"d1","deviceName":"TV","roomName":"Stua","hardwareProfile":"hdr10-512"}}"#.utf8))
            case "/api/tv/v2/library":
                if req.value(forHTTPHeaderField: "If-None-Match") == "\"lib-v2\"" {
                    let r304 = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: nil))
                    return (r304, Data())
                }
                let body = #"""
                {
                  "ok": true,
                  "section": "lists",
                  "counts": {"watchlist": 1, "localTotal": 0, "nvme": 0, "archive": 0, "vfs": 0, "customListsCount": 2},
                  "watchlist": [],
                  "localItems": [],
                  "customLists": [{"id": "c1", "name": "Mine", "itemCount": 3, "browsePath": "/api/tv/v2/rows/c1"}]
                }
                """#
                return (resp, Data(body.utf8))
            case "/api/tv/v2/playback/heartbeat":
                let body = #"{"ok":true,"sessionId":"s1","state":"playing","watchCompleted":true,"subtitleDelayMs":-150}"#
                return (resp, Data(body.utf8))
            case "/api/tv/v2/playback/s1/subtitles/search-and-attach":
                let body = #"{"ok":true,"sessionId":"s1","attached":true,"status":"attached","provider":"subdl","externalSubtitles":[{"id":"sub1","url":"/api/tv/v2/subs/1.srt","language":"nob"}],"subtitleDelayMs":100}"#
                return (resp, Data(body.utf8))
            case "/api/tv/v2/playback/s1/subtitles/auto-align":
                let body = #"{"ok":true,"sessionId":"s1","applied":true,"mode":"ffsubsync","offsetMs":250,"subtitleDelayMs":250}"#
                return (resp, Data(body.utf8))
            default:
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let client = try makeClient(host: host)
        _ = try await client.fetchBootstrap()

        let libRes = try await client.fetchLibrary(section: .lists)
        guard case .updated(let lib, let etag, _) = libRes else {
            return XCTFail("Expected library .updated")
        }
        XCTAssertEqual(etag, "\"lib-v2\"")
        XCTAssertEqual(lib.counts.resolvedCustomListsCount, 2)
        XCTAssertEqual(lib.resolvedCustomLists.first?.name, "Mine")

        let lib304 = try await client.fetchLibrary(section: .lists, ifNoneMatch: "\"lib-v2\"")
        guard case .notModified = lib304 else {
            return XCTFail("Expected 304 .notModified")
        }

        let hb = try await client.sendHeartbeat(
            sessionId: "s1",
            state: "playing",
            positionSeconds: 1200,
            durationSeconds: 1300,
            completed: true,
            subtitleDelayMs: -150,
            qos: TvPlaybackQosPayload(videoRoute: "direct", forwardBufferSeconds: 24.5, droppedVideoFrames: 0, stallCount: 0)
        )
        XCTAssertEqual(hb.watchCompleted, true)
        XCTAssertEqual(hb.subtitleDelayMs, -150)

        let attach = try await client.searchAndAttachSubtitles(sessionId: "s1")
        XCTAssertTrue(attach.attached)
        XCTAssertEqual(attach.externalSubtitles.count, 1)

        let align = try await client.autoAlignSubtitles(sessionId: "s1", subtitleDelayMs: 250, applyToFile: true)
        XCTAssertTrue(align.applied)
        XCTAssertEqual(align.subtitleDelayMs, 250)

        let sessionJSON = #"""
        {
          "sessionId": "s1",
          "streamToken": "tok",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "subtitleDelayMs": -200,
          "item": {"itemId": "movie:1", "mediaType": "movie", "ids": {"tmdb": 1}, "title": "Sentimental Value", "originalLanguage": "nob"},
          "selectedCandidate": {"candidateId": "c1", "displayHeadline": "4K", "releaseTitle": "Rel", "source": "nvme"},
          "stream": {"url": "/api/tv/v2/stream/s1/tok/v.mkv"},
          "tracks": {"probeConfidence": "high", "subtitleDelayMs": -200},
          "aetherConfig": {"preferDualLayerDolbyVision": true, "dolbyVisionHandling": "automatic", "matchContentEnabled": true, "audioBridgeMode": "lossless"}
        }
        """#
        let decodedSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        XCTAssertEqual(decodedSession.item.originalLanguage, "nob")
        XCTAssertEqual(decodedSession.subtitleDelayMs, -200)
        XCTAssertEqual(decodedSession.tracks?.subtitleDelayMs, -200)

        let paths = seenPaths.withLock { $0 }
        XCTAssertTrue(paths.contains("GET /api/tv/v2/bootstrap"))
        XCTAssertTrue(paths.contains("GET /api/tv/v2/library"))
        XCTAssertTrue(paths.contains("POST /api/tv/v2/playback/heartbeat"))
        XCTAssertTrue(paths.contains("POST /api/tv/v2/playback/s1/subtitles/search-and-attach"))
        XCTAssertTrue(paths.contains("POST /api/tv/v2/playback/s1/subtitles/auto-align"))
    }

    func testPlaybackResolveSocketProtocolMockAndPostCreditsAndCopy() async throws {
        let mock: any PlaybackResolveSocketProviding = MockResolveSocket(
            emitted: [
                TvResolveSocketEvent(type: "resolve.progress", resolveId: "r1", percent: 50),
                TvResolveSocketEvent(type: "resolve.ready", resolveId: "r1", percent: 100),
            ],
            failure: nil
        )
        var collected: [String] = []
        for try await evt in mock.events() {
            collected.append(evt.type)
        }
        XCTAssertEqual(collected, ["resolve.progress", "resolve.ready"])

        let blankSocket = PlaybackResolveSocket(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8090")),
            wsPath: "  ",
            headers: [:],
            allowSelfSignedLanTLS: false
        )
        do {
            for try await _ in blankSocket.events() {
                XCTFail("Expected invalidURL")
            }
        } catch LunaCoreError.invalidURL {
            // expected
        }

        XCTAssertEqual(TvChapterKind.classify(title: "Etter rulletekst", startSeconds: 5000, durationSeconds: 5400), .postCredits)
        XCTAssertEqual(TvChapterKind.postCredits.badgeLabel, "Etter rulletekst")
        XCTAssertEqual(TvChapterKind.parse(rawKind: "post-credits"), .postCredits)
        XCTAssertEqual(LunaCopy.libraryListsSectionTitle, "Lister")
        XCTAssertEqual(LunaCopy.listsPillTitle(3), "Lister · 3")
        XCTAssertEqual(LunaCopy.norwegianAudioTitle, "Norsk tale")
        XCTAssertEqual(LunaCopy.skipToPostCreditsTitle, "Hopp til etter rulletekst")
    }

    @MainActor
    func testPlaybackStopReceiptStoreImmediateWakeupAndTimeout() async {
        let store = PlaybackStopReceiptStore()
        let receipt = PlaybackStopReceipt(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            seasonNumber: 2,
            episodeNumber: 4,
            positionSeconds: 1800,
            durationSeconds: 3000,
            completed: true
        )

        let waiter = Task { @MainActor in
            await store.awaitReceipt(for: "series:tmdb:95396", timeout: .seconds(2))
        }
        try? await Task.sleep(for: .milliseconds(25))
        store.record(receipt)
        let awaited = await waiter.value
        XCTAssertEqual(awaited, receipt)
        XCTAssertEqual(store.lastReceipt, receipt)

        let immediate = await store.awaitReceipt(for: "series:tmdb:95396", timeout: .milliseconds(50))
        XCTAssertEqual(immediate, receipt)

        let missed = await store.awaitReceipt(for: "movie:tmdb:999", timeout: .milliseconds(40))
        XCTAssertNil(missed)
    }

    func testChapterMergeRawGenericChapterAndLegacyCreditsRegression() {
        let engineMerged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "intro", title: "Intro", startSeconds: 45, endSeconds: 120, kind: "chapter"),
                TvProbeChapter(index: 12, idString: "stinger", title: "Post Credits Scene", startSeconds: 5100, endSeconds: 5220, kind: "chapter"),
            ],
            engineChapters: [
                RawEngineChapter(id: 1, name: "Intro", startSeconds: 45, durationSeconds: 75),
                RawEngineChapter(id: 12, name: "Post Credits Scene", startSeconds: 5100, durationSeconds: 120),
            ],
            mediaDuration: 5400
        )
        XCTAssertEqual(engineMerged.count, 2)
        XCTAssertEqual(engineMerged[0].kind, .intro)
        XCTAssertEqual(engineMerged[1].kind, .postCredits)

        let probeOnlyMerged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "op", title: "Intro", startSeconds: 30, endSeconds: 100, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "pc", title: "Etter rulletekst", startSeconds: 5100, endSeconds: 5220, kind: "credits"),
            ],
            engineChapters: [],
            mediaDuration: 5400
        )
        XCTAssertEqual(probeOnlyMerged.count, 2)
        XCTAssertEqual(probeOnlyMerged[0].kind, .intro)
        XCTAssertEqual(probeOnlyMerged[1].kind, .postCredits)

        XCTAssertEqual(
            TvChapterKind.resolve(rawKind: "credits", title: "Etter rulletekst", startSeconds: 5100, durationSeconds: 5400),
            .postCredits
        )
        XCTAssertEqual(
            TvChapterKind.resolve(rawKind: "chapter", title: "Post Credits Scene", startSeconds: 5100, durationSeconds: 5400),
            .postCredits
        )
    }

    func testCoincidentGenericMkvAndTheIntroDbSegmentsArePreserved() {
        let merged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "ch1", title: "Chapter 1", startSeconds: 0, endSeconds: 2000, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "tidb-intro", title: "Intro", startSeconds: 0, endSeconds: 90, kind: "intro", source: "theintrodb"),
                TvProbeChapter(index: 2, idString: "ch3", title: "Chapter 3", startSeconds: 5000, endSeconds: 5150, kind: "chapter"),
                TvProbeChapter(index: 3, idString: "tidb-credits", title: "Rulletekst", startSeconds: 5000, endSeconds: 5150, kind: "credits", source: "theintrodb"),
                TvProbeChapter(index: 4, idString: "ch4", title: "Chapter 4", startSeconds: 5150, endSeconds: 5260, kind: "chapter"),
                TvProbeChapter(index: 5, idString: "tidb-post-credits", title: "Etter rulletekst", startSeconds: 5150, endSeconds: 5260, kind: "post_credits", source: "theintrodb"),
            ],
            engineChapters: [
                RawEngineChapter(id: 0, name: "Chapter 1", startSeconds: 0, durationSeconds: 2000),
                RawEngineChapter(id: 1, name: "Chapter 2", startSeconds: 2000, durationSeconds: 3000),
                RawEngineChapter(id: 2, name: "Chapter 3", startSeconds: 5000, durationSeconds: 150),
                RawEngineChapter(id: 3, name: "Chapter 4", startSeconds: 5150, durationSeconds: 110),
            ],
            mediaDuration: 5260
        )

        XCTAssertEqual(merged.map(\.kind), [.intro, .chapter, .credits, .postCredits])
        XCTAssertEqual(merged[0].endSeconds, 90, accuracy: 0.1)
        XCTAssertEqual(merged[2].startSeconds, 5000, accuracy: 0.1)
        XCTAssertEqual(merged[3].startSeconds, 5150, accuracy: 0.1)

        // Coincident credits + post_credits within < 1.5 s of the same generic engine chapter must both survive.
        let stacked = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "ch3", title: "Chapter 3", startSeconds: 5000, endSeconds: 5260, kind: "chapter"),
                TvProbeChapter(index: 1, idString: "tidb-credits", title: "Rulletekst", startSeconds: 5000, endSeconds: 5150, kind: "credits", source: "theintrodb"),
                TvProbeChapter(index: 2, idString: "tidb-post-credits", title: "Etter rulletekst", startSeconds: 5001, endSeconds: 5260, kind: "post_credits", source: "theintrodb"),
            ],
            engineChapters: [
                RawEngineChapter(id: 2, name: "Chapter 3", startSeconds: 5000, durationSeconds: 260),
            ],
            mediaDuration: 5260
        )
        XCTAssertEqual(Set(stacked.map(\.kind)), [.credits, .postCredits])
    }
}
