import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import LunaCore

// MARK: - Isolated Linux-Safe URLProtocol Double (Strict /api/tv/v2 Only)

private final class Etappe6URLProtocolMock: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])
    private static let capturedRequests = Mutex<[String: [URLRequest]]>([:])

    static func register(host: String, handler: @escaping Handler) {
        let key = host.lowercased()
        handlers.withLock { $0[key] = handler }
        capturedRequests.withLock { $0[key] = [] }
    }

    static func unregister(host: String) {
        let key = host.lowercased()
        _ = handlers.withLock { $0.removeValue(forKey: key) }
        _ = capturedRequests.withLock { $0.removeValue(forKey: key) }
    }

    static func requests(for host: String) -> [URLRequest] {
        capturedRequests.withLock { $0[host.lowercased()] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.capturedRequests.withLock { $0[host, default: []].append(request) }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeIsolatedClient(host: String) throws -> LunaCoreClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [Etappe6URLProtocolMock.self]
    let session = URLSession(configuration: config)
    let baseURL = try #require(URL(string: "https://\(host):8920"))
    return LunaCoreClient(
        baseURL: baseURL,
        deviceID: "luna-tv-e2e-1",
        deviceToken: "tok-e2e-device",
        roomName: "Kjellerstua",
        hardwareProfile: "dv-fel-714",
        allowSelfSignedLanTLS: true,
        appVersion: SideloadSafeStorage.currentAppVersionString(),
        osVersion: "tvOS 26.0",
        session: session,
        imageSession: session,
        externalImageSession: session
    )
}

@Suite("Etappe 6 /api/tv/v2 Contracts & Models")
struct Etappe6ContractAcceptanceTests {

    // MARK: - 1. /api/tv/v2/* Transport, Conditional ETag/304 & Error Mapping

    @Test("v2 endpoints route cleanly with ETag/304 on home & library and customLists decoding")
    func v2EndpointsConditionalLibraryAndErrorContracts() async throws {
        let host = "e2e-v2-\(UUID().uuidString.lowercased()).invalid"
        defer { Etappe6URLProtocolMock.unregister(host: host) }

        let libraryJSON = #"""
        {"ok":true,"section":"lists","counts":{"watchlist":3,"localTotal":12,"localMovies":8,"localSeries":4,"nvme":10,"archive":2,"vfs":0,"customLists":2,"customListsCount":2},"watchlist":[],"localItems":[],"localHasMore":false,"customLists":[{"id":"nordic-noir","name":"Nordic Noir","mediaType":"series","sourceType":"custom","listMode":"curated","rowStyle":"poster","itemCount":6,"browsePath":"/api/tv/v2/rows/custom:nordic-noir"}]}
        """#

        Etappe6URLProtocolMock.register(host: host) { req in
            let url = try #require(req.url)
            func respond(_ status: Int, _ body: String, headers: [String: String]? = nil) throws -> (HTTPURLResponse, Data) {
                let resp = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
                return (resp, Data(body.utf8))
            }

            switch (req.httpMethod ?? "GET", url.path) {
            case ("POST", "/api/tv/v2/pair/request"):
                return try respond(201, #"{"ok":true,"pairingCode":"482910","displayCode":"482-910","deviceId":"luna-tv-e2e-1","expiresAt":"2026-11-26T01:00:00Z","expiresInSeconds":600,"pollIntervalSeconds":3,"pollPath":"/api/tv/v2/pair/poll/482910"}"#)
            case ("GET", "/api/tv/v2/pair/poll/482910"):
                return try respond(429, #"{"ok":false,"status":"rate_limited","error":"For mange forsøk"}"#)
            case ("GET", "/api/tv/v2/bootstrap"):
                return try respond(200, #"{"ok":true,"device":{"deviceId":"luna-tv-e2e-1","deviceName":"Kjellerstua TV","roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","equipmentLabel":"LG OLED · Dolby Vision · Sonos 7.1.4","atmosphere":"cinema"},"defaultRooms":[{"roomName":"Stua","hardwareProfile":"hdr10-512","atmosphere":"living"}]}"#)
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
            case ("GET", "/api/tv/v2/search"):
                return try respond(401, #"{"error":"Utløpt token"}"#)
            case ("GET", "/api/tv/v2/catalog/movies"):
                return try respond(503, #"{"error":"Katalog utilgjengelig"}"#)
            case ("GET", "/api/tv/v2/catalog/series"):
                return try respond(200, "{broken-json")
            default:
                return try respond(404, #"{"error":"Ukjent v2-rute \#(url.path)"}"#)
            }
        }

        let client = try makeIsolatedClient(host: host)

        let pairReq = try await client.requestPairingCode(model: "AppleTV14,1", osVersion: "tvOS 26.0")
        #expect(pairReq.ok)
        #expect(pairReq.pairingCode == "482910")
        #expect(pairReq.displayCode == "482-910")
        let poll = try await client.pollPairingCode("482-910")
        #expect(poll.httpStatus == 429)
        #expect(poll.response.status == "rate_limited")

        let boot = try await client.fetchBootstrap()
        #expect(boot.device.hardwareProfile == "dv-fel-714")
        #expect(boot.defaultRooms?.first?.roomName == "Stua")

        let home200 = try await client.fetchHomeConditional(ifNoneMatch: nil)
        guard case .updated(let homePayload, let homeEtag, _) = home200 else {
            Issue.record("Expected 200 updated for /api/tv/v2/home")
            return
        }
        #expect(homePayload.roomName == "Kjellerstua")
        #expect(homeEtag == "\"etag-home-v2\"")

        let home304 = try await client.fetchHomeConditional(ifNoneMatch: "\"etag-home-v2\"")
        if case .notModified = home304 {} else {
            Issue.record("Expected 304 Not Modified on /api/tv/v2/home")
        }

        let lib200 = try await client.fetchLibrary(section: .lists, ifNoneMatch: nil)
        guard case .updated(let libPayload, let libEtag, _) = lib200 else {
            Issue.record("Expected 200 updated for /api/tv/v2/library?section=lists")
            return
        }
        #expect(libEtag == "\"etag-lib-v2\"")
        #expect(libPayload.counts.customLists == 2)
        #expect(libPayload.customLists?.first?.id == "nordic-noir")

        let lib304 = try await client.fetchLibrary(section: .lists, ifNoneMatch: "\"etag-lib-v2\"")
        if case .notModified = lib304 {} else {
            Issue.record("Expected 304 Not Modified on /api/tv/v2/library")
        }

        await #expect(throws: LunaCoreError.self) { _ = try await client.searchFull(query: "dune") }
        do {
            _ = try await client.fetchCatalog(kind: "movies")
            Issue.record("Expected 503 serverMessage")
        } catch let LunaCoreError.serverMessage(status, message) {
            #expect(status == 503)
            #expect(message == "Katalog utilgjengelig")
        }
        do {
            _ = try await client.fetchCatalog(kind: "series")
            Issue.record("Expected decodingFailed")
        } catch LunaCoreError.decodingFailed {}

        let sentPaths = Etappe6URLProtocolMock.requests(for: host).compactMap { $0.url?.path }
        #expect(!sentPaths.isEmpty)
        #expect(sentPaths.allSatisfy { $0.hasPrefix("/api/tv/v2/") })

        let heroImg = client.resolveArtworkURL("/api/tv/v2/img/card/tmdb/hero.jpg", target: .hero4K)
        #expect(heroImg?.absoluteString == "https://\(host):8920/api/tv/v2/img/backdrop/tmdb/hero.jpg")
        let wsURL = PlaybackResolveSocket.makeWebSocketURL(baseURL: client.baseURL, wsPath: "/api/tv/v2/ws/playback/res-v2")
        #expect(wsURL?.absoluteString == "wss://\(host):8920/api/tv/v2/ws/playback/res-v2")
    }

    @Test("v2 playback resolve, subtitle search-and-attach, auto-align & DTO fields")
    func v2PlaybackSubtitlesAndOriginalLanguageContract() async throws {
        let host = "e2e-v2-play-\(UUID().uuidString.lowercased()).invalid"
        defer { Etappe6URLProtocolMock.unregister(host: host) }

        let sessionJSON = #"""
        {
          "sessionId": "sess-v2-1",
          "streamToken": "stream-sig-0123456789abcdef01234567",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "subtitleDelayMs": -150,
          "item": {
            "itemId": "movie:tmdb:129",
            "mediaType": "movie",
            "ids": { "tmdb": 129 },
            "title": "Chihiro og heksene",
            "originalLanguage": "ja"
          },
          "selectedCandidate": {
            "candidateId": "cand-jp-remux",
            "displayHeadline": "1080p BluRay Remux",
            "releaseTitle": "Spirited.Away.2001.1080p.BluRay.REMUX",
            "source": "nvme",
            "tier": "nvme"
          },
          "stream": {
            "url": "/api/tv/v2/stream/sess-v2-1/0123456789abcdef0123456789abcdef/movie.mkv",
            "supportsByteRanges": true,
            "canClientPrewarmBytes": true
          },
          "tracks": {
            "subtitleDelayMs": -150,
            "chapters": []
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#

        let searchAttachJSON = #"""
        {
          "ok": true,
          "sessionId": "sess-v2-1",
          "attached": true,
          "status": "attached",
          "provider": "subdl",
          "written": true,
          "alignedNorwegian": false,
          "downloadedCount": 1,
          "subtitleDelayMs": 200,
          "externalSubtitles": [
            {
              "id": "ext-sub-nob-0",
              "url": "/api/tv/v2/subtitles/sess-v2-1/0123456789abcdef0123456789abcdef/0/nob.srt",
              "format": "srt",
              "language": "nob",
              "name": "Norsk (NVMe .srt)",
              "isForced": false,
              "isHearingImpaired": false,
              "isDefault": true
            }
          ]
        }
        """#

        let autoAlignJSON = #"{"ok":true,"sessionId":"sess-v2-1","applied":true,"mode":"reference_srt","offsetMs":-250,"scale":1.0,"subtitleDelayMs":0}"#

        Etappe6URLProtocolMock.register(host: host) { req in
            let url = try #require(req.url)
            let resp = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            switch url.path {
            case "/api/tv/v2/playback/prepare":
                return (resp, Data(#"{"ok":true,"prepareToken":"prep-v2","playbackSession":\#(sessionJSON)}"#.utf8))
            case "/api/tv/v2/playback/sess-v2-1/subtitles/search-and-attach":
                return (resp, Data(searchAttachJSON.utf8))
            case "/api/tv/v2/playback/sess-v2-1/subtitles/auto-align":
                return (resp, Data(autoAlignJSON.utf8))
            default:
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let client = try makeIsolatedClient(host: host)
        let prep = try await client.preparePlayback(itemId: "movie:tmdb:129", title: "Chihiro og heksene")
        #expect(prep.playbackSession?.item.originalLanguage == "ja")
        #expect(prep.playbackSession?.subtitleDelayMs == -150)
        #expect(prep.playbackSession?.tracks?.subtitleDelayMs == -150)

        let attached = try await client.searchAndAttachSubtitles(
            sessionId: "sess-v2-1",
            languages: ["nob", "eng"],
            forced: false,
            cleanSdh: true
        )
        #expect(attached.attached == true)
        #expect(attached.externalSubtitles.count == 1)
        #expect(attached.subtitleDelayMs == 200)

        let aligned = try await client.autoAlignSubtitles(
            sessionId: "sess-v2-1",
            subtitleId: "ext-sub-nob-0",
            trackIndex: 0,
            language: "nob",
            subtitleDelayMs: nil,
            applyToFile: true
        )
        #expect(aligned.applied == true)
        #expect(aligned.offsetMs == -250)
        #expect(aligned.subtitleDelayMs == 0)

        let paths = Etappe6URLProtocolMock.requests(for: host).compactMap { $0.url?.path }
        #expect(paths.contains("/api/tv/v2/playback/sess-v2-1/subtitles/search-and-attach"))
        #expect(paths.contains("/api/tv/v2/playback/sess-v2-1/subtitles/auto-align"))
    }

    // MARK: - 2. InflightTaskCoalescer Key Disambiguation

    @Test("InflightTaskCoalescer disambiguates identical paths across distinct Response types")
    func inflightTaskCoalescerDisambiguatesResponseTypes() async throws {
        let host = "e2e-coalesce-\(UUID().uuidString.lowercased()).invalid"
        defer { Etappe6URLProtocolMock.unregister(host: host) }

        Etappe6URLProtocolMock.register(host: host) { req in
            let url = try #require(req.url)
            Thread.sleep(forTimeInterval: 0.05)
            let resp = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            return (resp, Data(#"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[],"device":{"deviceId":"d1","deviceName":"TV","roomName":"Stua","hardwareProfile":"hdr10-512"}}"#.utf8))
        }

        let client = try makeIsolatedClient(host: host)
        async let asHome: TvHomeResponse = client.sendJSON(method: "GET", path: "/api/tv/v2/shared-shape")
        async let asBoot: TvBootstrapResponse = client.sendJSON(method: "GET", path: "/api/tv/v2/shared-shape")
        let (home, boot) = try await (asHome, asBoot)
        #expect(home.roomName == "Stua")
        #expect(boot.device.roomName == "Stua")
        #expect(Etappe6URLProtocolMock.requests(for: host).count == 2)

        async let homeA: TvHomeResponse = client.sendJSON(method: "GET", path: "/api/tv/v2/shared-shape")
        async let homeB: TvHomeResponse = client.sendJSON(method: "GET", path: "/api/tv/v2/shared-shape")
        let (hA, hB) = try await (homeA, homeB)
        #expect(hA.roomName == "Stua" && hB.roomName == "Stua")
        #expect(Etappe6URLProtocolMock.requests(for: host).count == 3)
    }

    // MARK: - Split Point for Optional 2-File Split (`Etappe6PolicyAcceptanceTests.swift`)

    // MARK: - 3. ChapterModels .postCredits & SeriesFlowEligibility Stinger Jump

    @Test("ChapterModels .postCredits normalization and SeriesFlowEligibility stinger skip")
    func postCreditsAndStingerSkipEligibility() throws {
        let rawProbes = Data(#"""
        [
          {"id":"c-cred","title":"Rulletekst","startSeconds":6000,"endSeconds":6240,"kind":"credits"},
          {"id":"c-post","title":"Etter rulletekst","startSeconds":6240,"endSeconds":6310,"kind":"post_credits"}
        ]
        """#.utf8)
        let probes = try JSONDecoder().decode([TvProbeChapter].self, from: rawProbes)
        let merged = PlaybackChapter.mergeRaw(probeChapters: probes, engineChapters: [], mediaDuration: 6320)

        #expect(merged.count == 2)
        #expect(merged[1].kind == .postCredits)
        #expect(TvChapterKind.postCredits.badgeLabel == "Etter rulletekst")
        #expect(TvChapterKind.classify(title: "After Credits Scene", startSeconds: 6200, durationSeconds: 6320) == .postCredits)

        let stingerTarget = SeriesFlowEligibility.postCreditsSkipTargetSeconds(
            currentTime: 6050,
            authoritativeDurationSeconds: 6320,
            chapters: merged
        )
        #expect(stingerTarget == 6240)

        let implicitCredits = [
            PlaybackChapter(id: "c1", index: 0, title: "Rulletekst", startSeconds: 5900, endSeconds: 6150, kind: .credits)
        ]
        let implicitTarget = SeriesFlowEligibility.postCreditsSkipTargetSeconds(
            currentTime: 5950,
            authoritativeDurationSeconds: 6200,
            chapters: implicitCredits
        )
        #expect(implicitTarget == 6150)

        let terminalCredits = [
            PlaybackChapter(id: "c2", index: 0, title: "Rulletekst", startSeconds: 5900, endSeconds: 6190, kind: .credits)
        ]
        #expect(
            SeriesFlowEligibility.postCreditsSkipTargetSeconds(
                currentTime: 5950,
                authoritativeDurationSeconds: 6200,
                chapters: terminalCredits
            ) == nil
        )
    }

    // MARK: - 4. OriginalLanguageTrackSelector, SmartTrackRuleEngine & PlaybackPreferenceStore

    @Test("OriginalLanguageTrackSelector + Norsk tale toggle + SmartTrackRuleEngine + PlaybackPreferenceStore")
    func originalLanguageNorwegianToggleAndPreferencePersistence() {
        let suite = "luna.v1.e2e.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let audioTracks = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Norsk 5.1", codec: "eac3", language: "nob", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese Commentary", codec: "aac", language: "ja", channels: 2, isCommentary: true),
            PlaybackAudioTrackDescriptor(id: 2, name: "Japanese TrueHD Atmos", codec: "truehd", language: "jpn", channels: 8, isAtmos: true),
            PlaybackAudioTrackDescriptor(id: 3, name: "English DTS-HD MA", codec: "dts-hd", language: "eng", channels: 8),
        ]
        let subs = [
            SmartTrackDescriptor(id: 10, name: "Norsk Bokmål", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
            SmartTrackDescriptor(id: 12, name: "English", codec: "srt", language: "eng"),
        ]

        let origAudio = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: audioTracks,
            originalLanguage: "ja",
            preferNorwegianAudio: false
        )
        #expect(origAudio?.id == 2)
        #expect(SmartTrackRuleEngine.evaluate(activeAudio: origAudio?.asSmartDescriptor, subtitleTracks: subs) == .selectTrack(10))

        let store = PlaybackPreferenceStore(defaults: defaults)
        store.setPreferNorwegianAudio(true, forItemId: "movie:tmdb:129")
        #expect(store.preferNorwegianAudio(forItemId: "movie:tmdb:129"))

        let norAudio = OriginalLanguageTrackSelector.selectPreferredAudioTrack(
            in: audioTracks,
            originalLanguage: "ja",
            preferNorwegianAudio: store.preferNorwegianAudio(forItemId: "movie:tmdb:129")
        )
        #expect(norAudio?.id == 0)
        #expect(SmartTrackRuleEngine.evaluate(activeAudio: norAudio?.asSmartDescriptor, subtitleTracks: subs) == .selectTrack(11))

        store.setSubtitleDelayMs(12_500, forCandidateId: "cand-jp-remux")
        #expect(store.subtitleDelayMs(forCandidateId: "cand-jp-remux") == 10_000)
        #expect(store.subtitleDelayMs(forCandidateId: "cand-other") == 0)
    }

    // MARK: - 5. DolbyVisionFallbackPolicy, PlaybackStopReceipt, ServerFailoverPolicy & ComfortPreferenceModels

    @Test("DolbyVisionFallbackPolicy, PlaybackStopReceipt, ServerFailoverPolicy & ComfortPreferenceModels")
    func dvFallbackStopReceiptFailoverAndComfortModels() throws {
        var dvPolicy = DolbyVisionFallbackPolicy()
        let dvNonFel = dvPolicy.recordTelemetrySample(droppedFrames: 30, isProfile7FEL: false, isBaseLayerForced: false)
        let dvLowDrop = dvPolicy.recordTelemetrySample(droppedFrames: 5, isProfile7FEL: true, isBaseLayerForced: false)
        let dvHighDrop = dvPolicy.recordTelemetrySample(droppedFrames: 35, isProfile7FEL: true, isBaseLayerForced: false)
        let dvForcedBase = dvPolicy.recordTelemetrySample(droppedFrames: 40, isProfile7FEL: true, isBaseLayerForced: true)
        #expect(!dvNonFel && !dvLowDrop && dvHighDrop && !dvForcedBase)

        let receipt = PlaybackStopReceipt(
            itemId: "episode:tmdb:95396:s1:e2",
            mediaType: "episode",
            seasonNumber: 1,
            episodeNumber: 2,
            positionSeconds: 1420,
            durationSeconds: 2800,
            completed: false,
            recordedAt: Date()
        )
        #expect(receipt.itemId == "episode:tmdb:95396:s1:e2")
        #expect(!receipt.completed)

        #expect(ServerFailoverPolicy.isFailoverEligibleError(URLError(.timedOut)))
        #expect(!ServerFailoverPolicy.isFailoverEligibleError(CancellationError()))
        let primary = try #require(URL(string: "https://media.example.test:8920"))
        let candidates = ServerFailoverPolicy.orderedFailoverCandidates(
            primary: primary,
            localHostnameURL: URL(string: "http://nas-tv.example.test:8090"),
            fallbackServerURL: URL(string: "https://backup.example.test:8920")
        )
        #expect(candidates.map(\.absoluteString) == [
            "http://media.example.test:8090",
            "http://nas-tv.example.test:8090",
            "https://backup.example.test:8920",
        ])

        #expect(DualLayerOverrideMode.forceOff.displayTitle == "Tving HDR10-baselag")
        #expect(SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "hdr10-512") == "Auto (5.1.2)")
        #expect(SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "dv-fel-714") == "Auto (7.1.4)")
        #expect(LowResUpscaleMode.defaultMode(for: .high2026) == .auto)
        #expect(LowResUpscaleMode.defaultMode(for: .standard) == .off)
    }
}
