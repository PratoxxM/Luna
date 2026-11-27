import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

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

final class LunaCoreClientAndTransportTests: XCTestCase {
    override func tearDown() {
        LunaCoreSessionPool.shared.invalidateAll()
        super.tearDown()
    }

    // MARK: - /api/tv/v2 Endpoints, Conditional ETag/304 & Wire Payloads

    func testTvV2EndpointsConditionalETagSubtitlesAndMutationPayloads() async throws {
        let host = "v2-transport-\(UUID().uuidString.lowercased()).invalid"
        defer { LunaCoreMockURLProtocol.unregister(host: host) }

        let capturedBodies = CoreLockedBox<[String: String]>([:])
        let libraryJSON = #"""
        {"ok":true,"section":"lists","counts":{"watchlist":3,"localTotal":12,"localMovies":8,"localSeries":4,"nvme":10,"archive":2,"vfs":0,"customLists":2,"customListsCount":2},"watchlist":[],"localItems":[],"localHasMore":false,"customLists":[{"id":"nordic-noir","name":"Nordic Noir","mediaType":"series","sourceType":"custom","listMode":"curated","rowStyle":"poster","itemCount":6,"browsePath":"/api/tv/v2/rows/custom:nordic-noir"}]}
        """#
        let sessionJSON = #"""
        {"sessionId":"sess-v2-1","streamToken":"stream-sig-0123456789abcdef01234567","roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","subtitleDelayMs":-150,"item":{"itemId":"movie:tmdb:129","mediaType":"movie","ids":{"tmdb":129},"title":"Chihiro og heksene","originalLanguage":"ja"},"selectedCandidate":{"candidateId":"cand-jp","displayHeadline":"1080p Remux","releaseTitle":"Spirited.Away.1080p","source":"nvme","tier":"nvme"},"stream":{"url":"/api/tv/v2/stream/sess-v2-1/sig/movie.mkv","supportsByteRanges":true,"canClientPrewarmBytes":true},"tracks":{"subtitleDelayMs":-150,"chapters":[]},"aetherConfig":{"preferDualLayerDolbyVision":true,"dolbyVisionHandling":"automatic","matchContentEnabled":true,"audioBridgeMode":"lossless"}}
        """#

        LunaCoreMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let body = LunaCoreMockURLProtocol.bodyString(for: req)
            capturedBodies.withLock { $0[url.path] = body }
            func respond(_ status: Int, _ payload: String, headers: [String: String]? = nil) throws -> (HTTPURLResponse, Data) {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
                return (resp, Data(payload.utf8))
            }

            switch (req.httpMethod ?? "GET", url.path) {
            case ("POST", "/api/tv/v2/pair/request"):
                return try respond(201, #"{"ok":true,"pairingCode":"482910","displayCode":"482-910","deviceId":"luna-core-test-device","expiresAt":"2026-11-26T01:00:00Z","expiresInSeconds":600,"pollIntervalSeconds":3,"pollPath":"/api/tv/v2/pair/poll/482910"}"#)
            case ("GET", "/api/tv/v2/bootstrap"):
                return try respond(200, #"{"ok":true,"device":{"deviceId":"luna-core-test-device","deviceName":"Kjellerstua TV","roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","equipmentLabel":"LG OLED · Dolby Vision · Sonos 7.1.4","atmosphere":"cinema"},"defaultRooms":[{"roomName":"Stua","hardwareProfile":"hdr10-512","atmosphere":"living"}]}"#)
            case ("GET", "/api/tv/v2/home"):
                if req.value(forHTTPHeaderField: "If-None-Match") == "\"etag-home-v2\"" {
                    return try respond(304, "")
                }
                return try respond(200, #"{"ok":true,"roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","rows":[]}"#, headers: ["ETag": "\"etag-home-v2\""])
            case ("GET", "/api/tv/v2/library"):
                if req.value(forHTTPHeaderField: "If-None-Match") == "\"etag-lib-v2\"" {
                    return try respond(304, "")
                }
                return try respond(200, libraryJSON, headers: ["ETag": "\"etag-lib-v2\""])
            case ("POST", "/api/tv/v2/playback/resolve"):
                return try respond(202, #"{"ok":true,"status":"resolving","resolveId":"res-99","wsPath":"/api/tv/v2/ws/resolve/res-99"}"#)
            case ("POST", "/api/tv/v2/playback/prepare"):
                return try respond(200, #"{"ok":true,"prepareToken":"prep-v2","playbackSession":\#(sessionJSON)}"#)
            case ("POST", "/api/tv/v2/playback/heartbeat"):
                return try respond(200, #"{"ok":true,"sessionId":"sess-v2-1","state":"playing","watchCompleted":true,"subtitleDelayMs":-150}"#)
            case ("POST", "/api/tv/v2/playback/sess-v2-1/subtitles/search-and-attach"):
                return try respond(200, #"{"ok":true,"sessionId":"sess-v2-1","attached":true,"status":"attached","provider":"subdl","subtitleDelayMs":200,"externalSubtitles":[{"id":"ext-sub-nob-0","url":"/api/tv/v2/subtitles/sess-v2-1/sig/0/nob.srt","format":"srt","language":"nob","name":"Norsk"}]}"#)
            case ("POST", "/api/tv/v2/playback/sess-v2-1/subtitles/auto-align"):
                return try respond(200, #"{"ok":true,"sessionId":"sess-v2-1","applied":true,"mode":"reference_srt","offsetMs":-250,"scale":1.0,"subtitleDelayMs":-250}"#)
            case ("POST", "/api/tv/v2/rows/custom:test/remove"):
                let removed = body.contains("550")
                return try respond(200, #"{"ok":true,"removed":\#(removed)}"#)
            case ("PATCH", "/api/tv/v2/device/profile"):
                return try respond(200, #"{"ok":true}"#)
            default:
                return try respond(404, #"{"error":"Ukjent v2-rute"}"#)
            }
        }

        let client = LunaCoreMockURLProtocol.makeClient(host: host)

        let pairReq = try await client.requestPairingCode(model: "AppleTV14,1", osVersion: "tvOS 26.0")
        XCTAssertTrue(pairReq.ok)
        XCTAssertEqual(pairReq.pairingCode, "482910")

        let boot = try await client.fetchBootstrap()
        XCTAssertEqual(boot.device.hardwareProfile, "dv-fel-714")
        XCTAssertEqual(boot.defaultRooms?.first?.roomName, "Stua")

        let home200 = try await client.fetchHomeConditional(ifNoneMatch: nil)
        guard case .updated(let homePayload, let homeEtag, let rawHome) = home200 else {
            return XCTFail("Expected 200 updated home")
        }
        XCTAssertEqual(homePayload.roomName, "Kjellerstua")
        XCTAssertEqual(homeEtag, "\"etag-home-v2\"")
        XCTAssertFalse(rawHome.isEmpty)

        if case .notModified = try await client.fetchHomeConditional(ifNoneMatch: "\"etag-home-v2\"") {} else {
            XCTFail("Expected 304 Not Modified on /home")
        }

        let lib200 = try await client.fetchLibrary(section: .lists, ifNoneMatch: nil)
        guard case .updated(let libPayload, let libEtag, _) = lib200 else {
            return XCTFail("Expected 200 updated library")
        }
        XCTAssertEqual(libEtag, "\"etag-lib-v2\"")
        XCTAssertEqual(libPayload.counts.resolvedCustomListsCount, 2)
        XCTAssertEqual(libPayload.resolvedCustomLists.first?.name, "Nordic Noir")

        if case .notModified = try await client.fetchLibrary(section: .lists, ifNoneMatch: "\"etag-lib-v2\"") {} else {
            XCTFail("Expected 304 Not Modified on /library")
        }

        let (resolveStatus, resolveStart) = try await client.resolvePlayback(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            seriesTitle: nil,
            startPositionSeconds: 0,
            candidateId: nil
        )
        XCTAssertEqual(resolveStatus, 202)
        XCTAssertEqual(resolveStart.resolveId, "res-99")
        XCTAssertEqual(resolveStart.wsPath, "/api/tv/v2/ws/resolve/res-99")

        let prep = try await client.preparePlayback(
            itemId: "movie:tmdb:129",
            title: "Chihiro og heksene",
            prepareToken: "prep-uuid-42"
        )
        XCTAssertEqual(prep.playbackSession?.item.originalLanguage, "ja")
        XCTAssertEqual(prep.playbackSession?.subtitleDelayMs, -150)

        let hb = try await client.sendHeartbeat(
            sessionId: "sess-v2-1",
            state: "playing",
            positionSeconds: 1200,
            durationSeconds: 1300,
            completed: true,
            subtitleDelayMs: -150,
            qos: TvPlaybackQosPayload(videoRoute: "direct", forwardBufferSeconds: 24.5, droppedVideoFrames: 0, stallCount: 0)
        )
        XCTAssertEqual(hb.watchCompleted, true)
        XCTAssertEqual(hb.subtitleDelayMs, -150)

        try await client.cancelInflightPlayback(
            sessionId: nil,
            resolveId: "res-77",
            itemId: "movie:tmdb:550",
            prepareToken: "prep-uuid-42"
        )
        let prepBody = capturedBodies.withLock { $0["/api/tv/v2/playback/prepare"] ?? "" }
        let cancelBody = capturedBodies.withLock { $0["/api/tv/v2/playback/heartbeat"] ?? "" }
        XCTAssertTrue(prepBody.contains("\"prepareToken\":\"prep-uuid-42\""))
        XCTAssertTrue(cancelBody.contains("\"cancelInflight\":true"))
        XCTAssertTrue(cancelBody.contains("\"resolveId\":\"res-77\""))
        XCTAssertTrue(cancelBody.contains("\"prepareToken\":\"prep-uuid-42\""))

        let attached = try await client.searchAndAttachSubtitles(sessionId: "sess-v2-1")
        XCTAssertTrue(attached.attached)
        XCTAssertEqual(attached.externalSubtitles.count, 1)
        XCTAssertEqual(attached.subtitleDelayMs, 200)

        let aligned = try await client.autoAlignSubtitles(
            sessionId: "sess-v2-1",
            subtitleId: "ext-sub-nob-0",
            trackIndex: 0,
            language: "nob",
            subtitleDelayMs: nil,
            applyToFile: true
        )
        XCTAssertTrue(aligned.applied)
        XCTAssertEqual(aligned.offsetMs, -250)

        let didRemove550 = try await client.removeFromList(
            rowId: "custom:test",
            mediaType: "movie",
            itemId: "movie:tmdb:550",
            ids: TvMediaIds(tmdb: 550),
            title: "Fight Club"
        )
        let didRemove999 = try await client.removeFromList(
            rowId: "custom:test",
            mediaType: "movie",
            itemId: "movie:tmdb:999",
            ids: TvMediaIds(tmdb: 999),
            title: "Other"
        )
        XCTAssertTrue(didRemove550)
        XCTAssertFalse(didRemove999)

        try await client.updateDeviceProfile(roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
        let reqs = LunaCoreMockURLProtocol.requests(for: host)
        let patchReq = try XCTUnwrap(reqs.last)
        XCTAssertEqual(patchReq.httpMethod, "PATCH")
        XCTAssertEqual(patchReq.value(forHTTPHeaderField: "Authorization"), "Bearer tok-core-test-device")
        XCTAssertNil(patchReq.value(forHTTPHeaderField: "X-Room-Name"))
        XCTAssertNil(patchReq.value(forHTTPHeaderField: "X-Hardware-Profile"))
        XCTAssertNotNil(patchReq.value(forHTTPHeaderField: "X-Supports-HW-AV1"))
        XCTAssertNotNil(patchReq.value(forHTTPHeaderField: "X-Physical-Memory-GB"))
        XCTAssertTrue(reqs.compactMap { $0.url?.path }.allSatisfy { $0.hasPrefix("/api/tv/v2/") })
    }

    // MARK: - Negative HTTP Envelopes, Pairing Poll Statuses & Trickplay Scrub-Frame

    func testNegativeHTTPStatusEnvelopesPairingPollsAndScrubFrame() async throws {
        let host = "v2-errors-\(UUID().uuidString.lowercased()).invalid"
        defer { LunaCoreMockURLProtocol.unregister(host: host) }
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        LunaCoreMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            func respond(_ status: Int, _ body: String, headers: [String: String]? = nil) throws -> (HTTPURLResponse, Data) {
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
                return (resp, Data(body.utf8))
            }
            switch url.path {
            case "/api/tv/v2/bootstrap":
                return try respond(401, "")
            case "/api/tv/v2/library":
                return try respond(503, #"{"error":"Arkivet vedlikeholdes"}"#)
            case "/api/tv/v2/search":
                return try respond(200, "not-json")
            case "/api/tv/v2/catalog/movies":
                return try respond(403, #"{"error":"Enhet blokkert"}"#)
            case "/api/tv/v2/pair/poll/111111":
                return try respond(400, "not-json-bad-request")
            case "/api/tv/v2/pair/poll/222222":
                return try respond(404, #"{"error":"Kode utløpt"}"#)
            case "/api/tv/v2/pair/poll/333333":
                return try respond(410, "")
            case "/api/tv/v2/pair/poll/444444":
                return try respond(429, "rate limited plain")
            case "/api/tv/v2/pair/poll/555555":
                return try respond(502, "bad gateway")
            case "/api/tv/v2/pair/poll/666666":
                return try respond(200, #"{"ok":true,"status":"approved","deviceToken":"tok-123"}"#)
            case "/api/tv/v2/playback/resolve":
                return try respond(413, #"{"error":"Forespørsel for stor"}"#)
            case "/api/tv/v2/playback/heartbeat":
                return try respond(410, #"{"error":"session_ended"}"#)
            case "/api/tv/v2/playback/s-bad/subtitles/auto-align":
                return try respond(415, "Unsupported Media Type")
            case "/api/tv/v2/playback/s-pgs/subtitles/auto-align":
                return try respond(422, #"{"ok":false,"code":"bitmap_subtitle_not_supported","error":"Bitmap PGS"}"#)
            case "/api/tv/v2/playback/sess-1/scrub-frame":
                let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "t" })?.value
                switch t {
                case "15":
                    let resp = try XCTUnwrap(HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "image/jpeg", "X-Trickplay-Cache": "HIT"]
                    ))
                    return (resp, jpegBytes)
                case "20":
                    return try respond(404, #"{"ok":false,"code":"archive_spindown_protected","error":"Arkiv beskyttet"}"#)
                case "30":
                    return try respond(503, #"{"ok":false,"code":"trickplay_busy","error":"Opptatt"}"#)
                default:
                    return try respond(401, #"{"ok":false,"error":"Unauthorized"}"#)
                }
            default:
                return try respond(404, #"{"error":"Ukjent økt"}"#)
            }
        }

        let client = LunaCoreMockURLProtocol.makeClient(host: host)

        do {
            _ = try await client.fetchBootstrap()
            XCTFail("Expected 401 unauthorized")
        } catch LunaCoreError.unauthorized {}

        do {
            _ = try await client.fetchLibrary()
            XCTFail("Expected 503 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 503)
            XCTAssertEqual(msg, "Arkivet vedlikeholdes")
        }

        do {
            _ = try await client.searchFull(query: "dune")
            XCTFail("Expected decodingFailed")
        } catch LunaCoreError.decodingFailed {}

        do {
            _ = try await client.fetchCatalog(kind: "movies")
            XCTFail("Expected 403 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(msg, "Enhet blokkert")
        }

        let p400 = try await client.pollPairingCode("111-111")
        XCTAssertEqual(p400.httpStatus, 400)
        XCTAssertEqual(p400.response.status, "invalid")

        let p404 = try await client.pollPairingCode("222222")
        XCTAssertEqual(p404.httpStatus, 404)
        XCTAssertEqual(p404.response.status, "expired")
        XCTAssertEqual(p404.response.error, "Kode utløpt")

        let p410 = try await client.pollPairingCode("333333")
        XCTAssertEqual(p410.httpStatus, 410)
        XCTAssertEqual(p410.response.status, "expired")

        let p429 = try await client.pollPairingCode("444444")
        XCTAssertEqual(p429.httpStatus, 429)
        XCTAssertEqual(p429.response.status, "rate_limited")

        let p502 = try await client.pollPairingCode("555555")
        XCTAssertEqual(p502.httpStatus, 502)
        XCTAssertEqual(p502.response.status, "error")

        let p200 = try await client.pollPairingCode("666 666")
        XCTAssertEqual(p200.httpStatus, 200)
        XCTAssertEqual(p200.response.deviceToken, "tok-123")

        do {
            _ = try await client.resolvePlayback(itemId: "m1", title: "T", seriesTitle: nil, startPositionSeconds: nil, candidateId: nil)
            XCTFail("Expected 413")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 413)
            XCTAssertEqual(msg, "Forespørsel for stor")
        }

        do {
            _ = try await client.sendHeartbeat(sessionId: "s1", state: "playing", positionSeconds: 10, durationSeconds: 100)
            XCTFail("Expected 410")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 410)
            XCTAssertEqual(msg, "session_ended")
        }

        do {
            _ = try await client.autoAlignSubtitles(sessionId: "s-bad", subtitleDelayMs: 0, applyToFile: false)
            XCTFail("Expected 415")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 415)
            XCTAssertEqual(msg, "HTTP 415")
        }

        do {
            _ = try await client.autoAlignSubtitles(sessionId: "s-pgs", trackIndex: 3, language: "eng", applyToFile: false)
            XCTFail("Expected 422 bitmap error")
        } catch let LunaCoreError.serverMessage(status, msg) {
            XCTAssertEqual(status, 422)
            XCTAssertEqual(msg, "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk")
        }

        let scrubHit = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 18.4)
        XCTAssertEqual(scrubHit, .image(data: jpegBytes, cacheHit: true))
        let scrubArchive = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 22.0)
        XCTAssertEqual(scrubArchive, .unavailable(statusCode: 404, code: "archive_spindown_protected"))
        let scrubBusy = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 31.0)
        XCTAssertEqual(scrubBusy, .unavailable(statusCode: 503, code: "trickplay_busy"))
        do {
            _ = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 40.0)
            XCTFail("Expected 401 unauthorized")
        } catch LunaCoreError.unauthorized {}
    }

    // MARK: - Same-Origin Auth Stripping, Artwork URL Upgrading & Row Request Paths

    func testSameOriginImageAuthStrippingArtworkURLUpgradingAndRowPaths() async throws {
        let lanHost = "lan-img-\(UUID().uuidString.lowercased()).local"
        let cdnHost = "cdn-img-\(UUID().uuidString.lowercased()).example.net"
        defer {
            LunaCoreMockURLProtocol.unregister(host: lanHost)
            LunaCoreMockURLProtocol.unregister(host: cdnHost)
        }

        let sampleBytes = Data([0x52, 0x49, 0x46, 0x46])
        LunaCoreMockURLProtocol.register(host: lanHost) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, sampleBytes)
        }
        LunaCoreMockURLProtocol.register(host: cdnHost) { req in
            let url = try XCTUnwrap(req.url)
            let code = url.path.contains("fail") ? 404 : 200
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
            return (resp, code == 200 ? sampleBytes : Data())
        }

        let client = LunaCoreMockURLProtocol.makeClient(
            host: lanHost,
            scheme: "https",
            port: 8920,
            deviceID: "luna-tv-stua",
            deviceToken: "secret-lan-token"
        )

        // :8090 <-> :8920 dual-listener same-origin recognition + rogue port & foreign host rejection
        let lanHttpStream = try XCTUnwrap(URL(string: "http://\(lanHost):8090/api/tv/v2/stream/s1/tok/video.mkv"))
        let lanHttpsImg = try XCTUnwrap(URL(string: "https://\(lanHost):8920/api/tv/v2/img/poster/tmdb/p.jpg"))
        let roguePort = try XCTUnwrap(URL(string: "http://\(lanHost):9999/api/tv/v2/stream/s1/tok/video.mkv"))
        let foreignHost = try XCTUnwrap(URL(string: "https://\(cdnHost):8920/video.mkv"))

        XCTAssertTrue(client.isSameOrigin(lanHttpStream))
        XCTAssertTrue(client.isSameOrigin(lanHttpsImg))
        XCTAssertFalse(client.isSameOrigin(roguePort))
        XCTAssertFalse(client.isSameOrigin(foreignHost))

        let sameStreamHeaders = client.streamHTTPHeaders(for: lanHttpStream)
        XCTAssertEqual(sameStreamHeaders["Authorization"], "Bearer secret-lan-token")
        XCTAssertEqual(sameStreamHeaders["X-Device-Id"], "luna-tv-stua")
        let foreignHeaders = client.streamHTTPHeaders(for: foreignHost)
        XCTAssertNil(foreignHeaders["Authorization"])
        XCTAssertNil(foreignHeaders["X-Device-Id"])

        let (sameData, _) = try await client.fetchRawImageData(from: lanHttpsImg)
        XCTAssertEqual(sameData, sampleBytes)
        let lanReq = try XCTUnwrap(LunaCoreMockURLProtocol.requests(for: lanHost).last)
        XCTAssertEqual(lanReq.value(forHTTPHeaderField: "Authorization"), "Bearer secret-lan-token")

        let extURL = try XCTUnwrap(URL(string: "https://\(cdnHost)/poster.jpg"))
        let (extData, _) = try await client.fetchRawImageData(from: extURL)
        XCTAssertEqual(extData, sampleBytes)
        let extReq = try XCTUnwrap(LunaCoreMockURLProtocol.requests(for: cdnHost).last)
        XCTAssertNil(extReq.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(extReq.value(forHTTPHeaderField: "X-Device-Id"))

        do {
            _ = try await client.fetchRawImageData(from: try XCTUnwrap(URL(string: "https://\(cdnHost)/fail.jpg")))
            XCTFail("Expected 404")
        } catch let LunaCoreError.serverMessage(code, _) {
            XCTAssertEqual(code, 404)
        }

        // Artwork URL upgrading & case-insensitive scheme handling
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w500/abc.jpg", target: .poster2x)?.absoluteString,
            "https://image.tmdb.org/t/p/w780/abc.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w500/abc.jpg", target: .hero4K)?.absoluteString,
            "https://image.tmdb.org/t/p/original/abc.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("https://image.tmdb.org/t/p/w1280/abc.jpg", target: .poster2x)?.absoluteString,
            "https://image.tmdb.org/t/p/w1280/abc.jpg"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v2/artwork?src=a&w=320", target: .landscape2x)?.absoluteString,
            "https://\(lanHost):8920/api/tv/v2/artwork?src=a&w=1280"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v2/artwork?src=a&width=780", target: .hero4K)?.absoluteString,
            "https://\(lanHost):8920/api/tv/v2/artwork?src=a&width=3840"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("/api/tv/v2/artwork?src=a&w=320", target: .preserve)?.absoluteString,
            "https://\(lanHost):8920/api/tv/v2/artwork?src=a&w=320"
        )
        XCTAssertEqual(
            client.resolveArtworkURL("HtTpS://\(lanHost):8920/api/tv/v2/img/card/tmdb/hero.jpg?v=2", target: .hero4K)?.absoluteString,
            "HtTpS://\(lanHost):8920/api/tv/v2/img/backdrop4k/tmdb/hero.jpg?v=2"
        )
        let mediaV2Backdrop = try XCTUnwrap(URL(string: "https://media.example.invalid/api/media/v2/img/backdrop/tmdb/a.jpg"))
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(mediaV2Backdrop, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/media/v2/img/backdrop4k/tmdb/a.jpg"
        )
        let backdrop4kURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(backdrop4kURL, target: .landscape2x), backdrop4kURL)
        let posterURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/poster/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(posterURL, target: .hero4K), posterURL)
        let proxyURL = try XCTUnwrap(URL(string: "https://proxy.example.net/fetch?url=/api/tv/v2/img/card/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(proxyURL, target: .hero4K), proxyURL)
        XCTAssertEqual(
            client.buildAbsoluteURL("api/tv/v2/http://nested")?.absoluteString,
            "https://\(lanHost):8920/api/tv/v2/http://nested"
        )

        // buildRowRequestPath pagination, normalization & Int.max overflow safety
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "sci-fi", offset: 36, limit: 36),
            "/api/tv/v2/rows/sci-fi?offset=36&limit=36"
        )
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "/api/tv/v2/catalog/movies?sort=popular", offset: 48, limit: 24),
            "/api/tv/v2/catalog/movies?sort=popular&page=3&limit=24"
        )
        XCTAssertEqual(
            LunaCoreClient.buildRowRequestPath(pathOrRowId: "/api/tv/v1/rows/custom?offset=0&limit=24", offset: 24, limit: 24),
            "/api/tv/v2/rows/custom?offset=24&limit=24"
        )
        let maxPath = LunaCoreClient.buildRowRequestPath(pathOrRowId: "/api/tv/v2/catalog/movies", offset: Int.max, limit: 1)
        XCTAssertTrue(maxPath.contains("page=\(Int.max)"))
    }

    // MARK: - InflightTaskCoalescer & GET vs POST Coalescing

    func testInflightTaskCoalescerDisambiguationCancellationAndGETvsPOST() async throws {
        let host = "coalesce-\(UUID().uuidString.lowercased()).invalid"
        defer { LunaCoreMockURLProtocol.unregister(host: host) }

        struct ProbeA: Decodable, Sendable { let a: String }
        struct ProbeB: Decodable, Sendable { let b: Int }
        let getCount = CoreLockedBox(0)
        let postCount = CoreLockedBox(0)

        LunaCoreMockURLProtocol.register(host: host, background: true) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"v1\""]))
            if req.httpMethod == "GET" && url.path == "/api/tv/v2/bootstrap" {
                getCount.withLock { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.04)
                return (resp, Data(#"{"ok":true,"device":{"deviceId":"d1","deviceName":"TV","roomName":"Stua","hardwareProfile":"hdr10-512"}}"#.utf8))
            }
            if req.httpMethod == "POST" && url.path == "/api/tv/v2/watchlist" {
                postCount.withLock { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.02)
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
            Thread.sleep(forTimeInterval: 0.03)
            return (resp, Data(#"{"a":"ok","b":42}"#.utf8))
        }

        let baseURL = try XCTUnwrap(URL(string: "https://\(host):8920"))
        let prod1 = LunaCoreClient(baseURL: baseURL, deviceID: "d", deviceToken: "t", roomName: "Stua", hardwareProfile: "hdr10-512", allowSelfSignedLanTLS: true)
        let prod2 = LunaCoreClient(baseURL: baseURL, deviceID: "d", deviceToken: "t", roomName: "Stua", hardwareProfile: "hdr10-512", allowSelfSignedLanTLS: true)
        XCTAssertTrue(prod1.inflightGETRequests === prod2.inflightGETRequests)

        let client = LunaCoreMockURLProtocol.makeClient(host: host)

        let bootstraps = try await withThrowingTaskGroup(of: TvBootstrapResponse.self) { group in
            for _ in 0..<6 {
                group.addTask { try await client.fetchBootstrap() }
            }
            var out: [TvBootstrapResponse] = []
            for try await item in group { out.append(item) }
            return out
        }
        XCTAssertEqual(bootstraps.count, 6)
        XCTAssertEqual(getCount.get(), 1)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for idx in 0..<4 {
                group.addTask {
                    try await client.setWatchlist(listed: idx.isMultiple(of: 2), mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club", year: 1999)
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(postCount.get(), 4)

        // Response-type & ETag disambiguation
        async let resA: ProbeA = client.sendJSON(method: "GET", path: "/api/tv/v2/shared")
        async let resB: ProbeB = client.sendJSON(method: "GET", path: "/api/tv/v2/shared")
        let (a, b) = try await (resA, resB)
        XCTAssertEqual(a.a, "ok")
        XCTAssertEqual(b.b, 42)

        async let c1: ConditionalHTTPResult<ProbeA> = client.sendConditionalGET(path: "/api/tv/v2/shared", ifNoneMatch: "\"e1\"")
        async let c2: ConditionalHTTPResult<ProbeA> = client.sendConditionalGET(path: "/api/tv/v2/shared", ifNoneMatch: "\"e2\"")
        _ = try await (c1, c2)

        // Direct InflightTaskCoalescer waiter-cancellation isolation & last-waiter cancellation
        let coalescer = InflightTaskCoalescer<String, String>()
        let underlyingCancelled = CoreLockedBox(false)
        let startedGate = CoreLockedBox(false)

        let survivor = Task {
            try await coalescer.coalesce(key: "shared-key") {
                startedGate.set(true)
                do {
                    try await Task.sleep(nanoseconds: 80_000_000)
                    return "ok"
                } catch {
                    underlyingCancelled.set(true)
                    throw error
                }
            }
        }
        while !startedGate.get() { try await Task.sleep(nanoseconds: 2_000_000) }
        let cancelledWaiter = Task { try await coalescer.coalesce(key: "shared-key") { "bad" } }
        try await Task.sleep(nanoseconds: 8_000_000)
        cancelledWaiter.cancel()
        if case .success = await cancelledWaiter.result { XCTFail("Expected cancellation") }
        let survived = try await survivor.value
        XCTAssertEqual(survived.value, "ok")
        XCTAssertFalse(underlyingCancelled.get())
        XCTAssertEqual(coalescer.inflightCount, 0)

        let lastCancelObserved = CoreLockedBox(false)
        let ephemeralStarted = CoreLockedBox(false)
        let waiterA = Task {
            try await coalescer.coalesce(key: "ephemeral") {
                ephemeralStarted.set(true)
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return "7"
                } catch {
                    lastCancelObserved.set(true)
                    throw error
                }
            }
        }
        while !ephemeralStarted.get() { try await Task.sleep(nanoseconds: 2_000_000) }
        let waiterB = Task { try await coalescer.coalesce(key: "ephemeral") { "8" } }
        try await Task.sleep(nanoseconds: 8_000_000)
        waiterA.cancel()
        try await Task.sleep(nanoseconds: 12_000_000)
        XCTAssertFalse(lastCancelObserved.get())
        waiterB.cancel()
        _ = await waiterA.result
        _ = await waiterB.result
        for _ in 0..<50 where !lastCancelObserved.get() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(lastCancelObserved.get())
        XCTAssertEqual(coalescer.inflightCount, 0)

        XCTAssertTrue(LunaCoreError.isCancellation(CancellationError()))
        XCTAssertTrue(LunaCoreError.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(LunaCoreError.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(LunaCoreError.isCancellation(LunaCoreError.unauthorized))
    }

    // MARK: - LunaCoreSessionPool, TLS Trust & PlaybackResolveSocket

    func testSessionPoolLaneReuseProbeTimeoutBoundsAndPlaybackResolveSocket() async throws {
        let pool = LunaCoreSessionPool.shared
        pool.invalidateAll()

        let urlA = try XCTUnwrap(URL(string: "https://lunacore.local:8920"))
        let urlUpper = try XCTUnwrap(URL(string: "HTTPS://LUNACORE.LOCAL:8920/api/tv/v2/home"))
        let urlPort8090 = try XCTUnwrap(URL(string: "https://lunacore.local:8090"))

        let api1 = pool.session(for: urlA, allowSelfSignedLanTLS: true)
        let api2 = pool.session(for: urlUpper, allowSelfSignedLanTLS: true)
        XCTAssertTrue(api1 === api2)

        let art1 = pool.artworkSession(for: urlA, allowSelfSignedLanTLS: true)
        let ws1 = pool.webSocketSession(for: urlA, allowSelfSignedLanTLS: true)
        let ext1 = pool.externalArtworkSession()
        let ext2 = pool.externalArtworkSession()
        XCTAssertTrue(api1 !== art1 && api1 !== ws1 && art1 !== ws1 && ext1 === ext2 && art1 !== ext1)
        XCTAssertTrue(api1 !== pool.session(for: urlA, allowSelfSignedLanTLS: false))
        XCTAssertTrue(api1 !== pool.session(for: urlPort8090, allowSelfSignedLanTLS: true))

        pool.invalidateAll()
        XCTAssertTrue(api1 !== pool.session(for: urlA, allowSelfSignedLanTLS: true))

        let concurrentIDs = await withTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0..<16 {
                group.addTask { ObjectIdentifier(pool.session(for: urlA, allowSelfSignedLanTLS: true)) }
            }
            var ids = Set<ObjectIdentifier>()
            for await id in group { ids.insert(id) }
            return ids
        }
        XCTAssertEqual(concurrentIDs.count, 1)

        // Probe timeout bounds
        XCTAssertEqual(pool.probeSession(for: urlA, allowSelfSignedLanTLS: false, timeoutSeconds: 1e30).configuration.timeoutIntervalForRequest, 3600.0)
        XCTAssertEqual(pool.probeSession(for: urlA, allowSelfSignedLanTLS: false, timeoutSeconds: .nan).configuration.timeoutIntervalForRequest, 4.0)
        XCTAssertEqual(pool.probeSession(for: urlA, allowSelfSignedLanTLS: false, timeoutSeconds: .infinity).configuration.timeoutIntervalForRequest, 4.0)
        XCTAssertEqual(pool.probeSession(for: urlA, allowSelfSignedLanTLS: false, timeoutSeconds: -5.0).configuration.timeoutIntervalForRequest, 0.1)

        // LanURLSessionDelegate trust policy
        XCTAssertTrue(LanURLSessionDelegate.shouldTrustServer(host: "LunaCore.Example.Test", trustedHost: "lunacore.example.test", allowSelfSignedTLS: true))
        XCTAssertTrue(LanURLSessionDelegate.shouldTrustServer(host: "nas-box.local", trustedHost: nil, allowSelfSignedTLS: true))
        XCTAssertFalse(LanURLSessionDelegate.shouldTrustServer(host: "external.example.net", trustedHost: "lunacore.example.test", allowSelfSignedTLS: true))
        XCTAssertFalse(LanURLSessionDelegate.shouldTrustServer(host: "nas-box.local", trustedHost: "nas-box.local", allowSelfSignedTLS: false))
        XCTAssertFalse(LanURLSessionDelegate.shouldTrustServer(host: "", trustedHost: "", allowSelfSignedTLS: true))

        // PlaybackResolveSocket URL conversion, decodeEventData & blank-path error
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
            PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "https://direct.example.test:8920/ws")?.absoluteString,
            "wss://direct.example.test:8920/ws"
        )
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "   "))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "/bad path with spaces"))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: httpBase, wsPath: "ws://"))
        XCTAssertNil(PlaybackResolveSocket.makeWebSocketURL(baseURL: try XCTUnwrap(URL(string: "http:///")), wsPath: "/api/tv/v2/ws/resolve/abc"))

        let progressEvt = try PlaybackResolveSocket.decodeEventData(
            Data(#"{"type":"resolve.progress","resolveId":"res-1","stage":"searching","percent":45,"winnerHeadline":"4K Remux"}"#.utf8)
        )
        XCTAssertEqual(progressEvt.percent, 45)
        XCTAssertFalse(PlaybackResolveSocket.isTerminalEvent(progressEvt))

        let failedEvt = try PlaybackResolveSocket.decodeEventData(
            Data(#"{"type":"resolve.failed","resolveId":"res-1","error":"Ingen kilder funnet"}"#.utf8)
        )
        XCTAssertTrue(PlaybackResolveSocket.isTerminalEvent(failedEvt))

        let readyEvt = try PlaybackResolveSocket.decodeEventData(
            Data(#"{"type":"resolve.ready","resolveId":"res-1","percent":100}"#.utf8)
        )
        XCTAssertTrue(PlaybackResolveSocket.isTerminalEvent(readyEvt))
        XCTAssertThrowsError(try PlaybackResolveSocket.decodeEventData(Data("{not json".utf8)))

        let blankSocket = PlaybackResolveSocket(baseURL: httpBase, wsPath: "  ", headers: [:], allowSelfSignedLanTLS: true)
        do {
            for try await _ in blankSocket.events() { XCTFail("Expected invalidURL") }
            XCTFail("Expected throw")
        } catch LunaCoreError.invalidURL {}

        let mockSocket: any PlaybackResolveSocketProviding = MockResolveSocket(
            emitted: [progressEvt, readyEvt],
            failure: nil
        )
        var types: [String] = []
        for try await evt in mockSocket.events() { types.append(evt.type) }
        XCTAssertEqual(types, ["resolve.progress", "resolve.ready"])
    }
}
