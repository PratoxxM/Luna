import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import LunaCore

private final class AdversarialURLProtocolMock: URLProtocol {
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

private func makeAdversarialClient(host: String) throws -> LunaCoreClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AdversarialURLProtocolMock.self]
    let session = URLSession(configuration: config)
    let baseURL = try #require(URL(string: "https://\(host):8920"))
    return LunaCoreClient(
        baseURL: baseURL,
        deviceID: "luna-adv-1",
        deviceToken: "tok-adv-device",
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

@Suite("Etappe 6 Tier 5 Adversarial Hardening")
struct Etappe6AdversarialHardeningTests {
    @Test("v2 negative HTTP envelopes (400/403/404/410/413/415/429) and non-JSON error fallbacks")
    func v2NegativeHTTPStatusAndNonJSONErrorEnvelopes() async throws {
        let host = "adv-neg-\(UUID().uuidString.lowercased()).invalid"
        defer { AdversarialURLProtocolMock.unregister(host: host) }

        AdversarialURLProtocolMock.register(host: host) { req in
            let url = try #require(req.url)
            func respond(_ status: Int, _ body: String) throws -> (HTTPURLResponse, Data) {
                let resp = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
                return (resp, Data(body.utf8))
            }
            switch url.path {
            case "/api/tv/v2/bootstrap":
                return try respond(403, #"{"error":"Enhet blokkert"}"#)
            case "/api/tv/v2/pair/poll/111111":
                return try respond(400, "not-json-bad-request")
            case "/api/tv/v2/pair/poll/222222":
                return try respond(404, "<html>not found</html>")
            case "/api/tv/v2/pair/poll/333333":
                return try respond(410, "")
            case "/api/tv/v2/pair/poll/444444":
                return try respond(429, "rate limited plain")
            case "/api/tv/v2/pair/poll/555555":
                return try respond(502, "bad gateway")
            case "/api/tv/v2/playback/resolve":
                return try respond(413, #"{"error":"Forespørsel for stor"}"#)
            case "/api/tv/v2/playback/heartbeat":
                return try respond(410, #"{"error":"session_ended"}"#)
            case "/api/tv/v2/playback/s-missing/subtitles/search-and-attach":
                return try respond(404, #"{"error":"Ukjent økt"}"#)
            case "/api/tv/v2/playback/s-bad/subtitles/auto-align":
                return try respond(415, "Unsupported Media Type")
            default:
                return try respond(400, #"{"error":"Ugyldig"}"#)
            }
        }

        let client = try makeAdversarialClient(host: host)

        do {
            _ = try await client.fetchBootstrap()
            Issue.record("Expected 403 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            #expect(status == 403 && msg == "Enhet blokkert")
        }

        let poll400 = try await client.pollPairingCode("111-111")
        #expect(poll400.httpStatus == 400 && !poll400.response.ok && poll400.response.status == "invalid")
        let poll404 = try await client.pollPairingCode("222222")
        #expect(poll404.httpStatus == 404 && !poll404.response.ok && poll404.response.status == "expired")
        let poll410 = try await client.pollPairingCode("333333")
        #expect(poll410.httpStatus == 410 && !poll410.response.ok && poll410.response.status == "expired")
        let poll429 = try await client.pollPairingCode("444444")
        #expect(poll429.httpStatus == 429 && !poll429.response.ok && poll429.response.status == "rate_limited")
        let poll502 = try await client.pollPairingCode("555555")
        #expect(poll502.httpStatus == 502 && !poll502.response.ok && poll502.response.status == "error")

        do {
            _ = try await client.resolvePlayback(itemId: "m1", title: "T", seriesTitle: nil, startPositionSeconds: nil, candidateId: nil)
            Issue.record("Expected 413 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            #expect(status == 413 && msg == "Forespørsel for stor")
        }

        do {
            _ = try await client.sendHeartbeat(sessionId: "s1", state: "playing", positionSeconds: 10, durationSeconds: 100)
            Issue.record("Expected 410 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            #expect(status == 410 && msg == "session_ended")
        }

        do {
            _ = try await client.searchAndAttachSubtitles(sessionId: "s-missing")
            Issue.record("Expected 404 serverMessage")
        } catch let LunaCoreError.serverMessage(status, msg) {
            #expect(status == 404 && msg == "Ukjent økt")
        }

        do {
            _ = try await client.autoAlignSubtitles(sessionId: "s-bad", subtitleDelayMs: 0, applyToFile: false)
            Issue.record("Expected 415 fallback message")
        } catch let LunaCoreError.serverMessage(status, msg) {
            #expect(status == 415 && msg == "HTTP 415")
        }
    }

    @Test("autoAlignSubtitles wire bounds vs player delay clamp and Int.max overflow-safe step arithmetic")
    func autoAlignWireBoundsAndOverflowSafeSyncTiming() async throws {
        let host = "adv-align-\(UUID().uuidString.lowercased()).invalid"
        defer { AdversarialURLProtocolMock.unregister(host: host) }

        AdversarialURLProtocolMock.register(host: host) { req in
            let url = try #require(req.url)
            let resp = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            return (resp, Data(#"{"ok":true,"sessionId":"s1","applied":true,"mode":"manual_delay","offsetMs":-600000,"subtitleDelayMs":-600000}"#.utf8))
        }

        let client = try makeAdversarialClient(host: host)
        let res = try await client.autoAlignSubtitles(
            sessionId: "s1",
            subtitleDelayMs: -600_000,
            applyToFile: false
        )
        #expect(res.subtitleDelayMs == -600_000)

        let suite = "luna.v1.adv.sync.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPreferenceStore(defaults: defaults)
        store.setSubtitleDelayMs(600_000, forCandidateId: "cand-max")
        #expect(store.subtitleDelayMs(forCandidateId: "cand-max") == 10_000)
        store.setSubtitleDelayMs(-600_000, forCandidateId: "cand-min")
        #expect(store.subtitleDelayMs(forCandidateId: "cand-min") == -5_000)

        #expect(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.max, deltaMs: 50) == 10_000)
        #expect(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.min, deltaMs: -50) == -5_000)
        #expect(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.max, deltaMs: Int.max) == 10_000)
        #expect(PlaybackSyncTimingPolicy.stepSubtitleDelayMs(from: Int.min, deltaMs: Int.min) == -5_000)

        #expect(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.max, deltaMs: 25) == 2_000)
        #expect(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.min, deltaMs: -25) == -2_000)
        #expect(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.max, deltaMs: Int.max) == 2_000)
        #expect(PlaybackSyncTimingPolicy.stepAudioDelayMs(from: Int.min, deltaMs: Int.min) == -2_000)
    }

    @Test("BlurHashDecoder handles non-finite punch, oversized dimensions, sizeFlag mismatch & multi-byte UTF-8 safely")
    func blurHashMalformedAndExtremeInputs() {
        let validHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

        #expect(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: .nan) == "\(validHash)#32x18#p100")
        #expect(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: .infinity) == "\(validHash)#32x18#p100")
        #expect(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: -.infinity) == "\(validHash)#32x18#p100")
        #expect(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: 1e30) == "\(validHash)#32x18#p1000")
        #expect(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: -5.0) == "\(validHash)#32x18#p0")

        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: .nan) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: .infinity) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: -.infinity) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: -0.1) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: -4, height: 18, punch: 1.0) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: -4, punch: 1.0) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 513, height: 18, punch: 1.0) == nil)
        #expect(BlurHashDecoder.decodePixels(validHash, width: 32, height: 513, punch: 1.0) == nil)

        #expect(BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdn", width: 32, height: 18) == nil)
        #expect(BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdnjX", width: 32, height: 18) == nil)
        #expect(BlurHashDecoder.decodePixels("🎬🎬🎬🎬🎬🎬", width: 32, height: 18) == nil)
        #expect(BlurHashDecoder.decodePixels("LEHV6n🎬B2yk8pyo0adR*.7kCMdnj", width: 32, height: 18) == nil)
    }

    @Test("DiskSWRStore recovers from 0-byte/corrupt files & ArtworkDiskCache handles 0-byte maxBytes=0 trim")
    func diskSWRCorruptRecoveryAndArtworkZeroTrim() async throws {
        try await DiskSWRTestGate.shared.withLock {
            await DiskSWRStore.clearAllAsync()
            defer { Task { await DiskSWRStore.clearAllAsync() } }

            let host = "adv-corrupt-\(UUID().uuidString.lowercased()).invalid"
            let homePayload = TvHomeResponse(ok: true, roomName: "Stua", hardwareProfile: "hdr10-512", rows: [])
            let catalogPayload = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 24, hasMore: false, items: [])
            let homeData = try JSONEncoder().encode(homePayload)
            let catData = try JSONEncoder().encode(catalogPayload)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"h-ok\"", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            DiskSWRStore.saveCatalogInBackground(rawPayloadData: catData, etag: "\"c-ok\"", kind: "movie", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let swrDir = cachesBase.appendingPathComponent("LunaV2/swr", isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: swrDir, includingPropertiesForKeys: nil)

            for file in files {
                if file.lastPathComponent.hasPrefix("home-") && file.lastPathComponent.hasSuffix(".json") && !file.lastPathComponent.hasSuffix(".meta.json") {
                    try Data().write(to: file)
                }
                if file.lastPathComponent.hasPrefix("catalog-") && file.lastPathComponent.hasSuffix(".meta.json") {
                    try Data("{broken-meta".utf8).write(to: file)
                }
            }

            let corruptHome = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            #expect(corruptHome == nil)

            let recoveredCatalog = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            #expect(recoveredCatalog != nil)
            #expect(recoveredCatalog?.etag == nil)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"h-healed\"", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()
            let healedHome = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
            #expect(healedHome?.etag == "\"h-healed\"")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-adv-art-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zeroFile = tempDir.appendingPathComponent("zero.img")
        let nonZeroFile = tempDir.appendingPathComponent("payload.img")
        try Data().write(to: zeroFile)
        try Data(repeating: 0x5A, count: 512).write(to: nonZeroFile)

        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: 0, directoryURL: tempDir)
        #expect(!FileManager.default.fileExists(atPath: nonZeroFile.path))
    }

    @Test("PlaybackStopReceiptStore enforces itemId isolation, cancellation cleanup, excluding & recordedAfter")
    @MainActor
    func stopReceiptIsolationCancellationAndFiltering() async {
        let store = PlaybackStopReceiptStore()
        let baseDate = Date()
        let oldReceipt = PlaybackStopReceipt(
            itemId: "movie:tmdb:10",
            mediaType: "movie",
            positionSeconds: 100,
            durationSeconds: 1000,
            completed: false,
            recordedAt: baseDate
        )
        store.record(oldReceipt)

        let excludedResult = await store.awaitReceipt(
            for: "movie:tmdb:10",
            timeout: .milliseconds(30),
            excluding: oldReceipt
        )
        #expect(excludedResult == nil)

        let futureCutoffResult = await store.awaitReceipt(
            for: "movie:tmdb:10",
            timeout: .milliseconds(30),
            recordedAfter: baseDate.addingTimeInterval(60)
        )
        #expect(futureCutoffResult == nil)

        let cancelledWaiter = Task { @MainActor in
            await store.awaitReceipt(for: "movie:tmdb:20", timeout: .seconds(10))
        }
        try? await Task.sleep(for: .milliseconds(10))
        cancelledWaiter.cancel()
        let cancelledOutcome = await cancelledWaiter.value
        #expect(cancelledOutcome == nil)

        let targetWaiter = Task { @MainActor in
            await store.awaitReceipt(for: "series:tmdb:50", timeout: .seconds(2))
        }
        try? await Task.sleep(for: .milliseconds(15))
        let unrelated = PlaybackStopReceipt(
            itemId: "movie:tmdb:999",
            mediaType: "movie",
            positionSeconds: 50,
            durationSeconds: 200,
            completed: false
        )
        store.record(unrelated)

        let matching = PlaybackStopReceipt(
            itemId: "series:tmdb:50",
            mediaType: "episode",
            seasonNumber: 1,
            episodeNumber: 3,
            positionSeconds: 900,
            durationSeconds: 1000,
            completed: true
        )
        store.record(matching)
        let received = await targetWaiter.value
        #expect(received == matching)
    }

    @Test("SideloadSafeStorage fallback persistence & 2.0 auto speaker layout stereo downmix")
    func sideloadFallbackKeysAndStereoAutoLayoutShaping() throws {
        let suite = "luna.v1.adv.sideload.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let devID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)
        #expect(devID.hasPrefix("luna-"))
        #expect(defaults.string(forKey: SideloadSafeStorage.deviceIDKey) == devID)
        #if !canImport(Security)
        #expect(defaults.string(forKey: "luna.v1.keychain_fallback.device_id") == devID)
        #endif

        SideloadSafeStorage.saveDeviceToken("tok-fallback-test", defaults: defaults)
        #if !canImport(Security)
        #expect(defaults.string(forKey: "luna.v1.keychain_fallback.device_bearer_token") == "tok-fallback-test")
        #endif
        #expect(SideloadSafeStorage.loadDeviceToken(defaults: defaults) == "tok-fallback-test")

        SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
        #expect(defaults.string(forKey: "luna.v1.keychain_fallback.device_bearer_token") == nil)
        #expect(SideloadSafeStorage.loadDeviceToken(defaults: defaults) == nil)

        let autoLayout = SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(
            speakerLayout: "2.0",
            equipmentLabel: "TV Stereo",
            hardwareProfile: "hdr10-512",
            roomName: "Soverom"
        )
        #expect(autoLayout == "2.0")

        let stereoRef = AudioEnhancementMode.reference.shapingParameters(effectiveSpeakerLayout: autoLayout)
        #expect(stereoRef.maxChannels == 2 && stereoRef.lfeMixDB == -6.0 && !stereoRef.usesNightCompressor)

        let stereoNight = AudioEnhancementMode.nightMode.shapingParameters(effectiveSpeakerLayout: autoLayout)
        #expect(stereoNight.maxChannels == 2 && stereoNight.lfeMixDB == -6.0 && stereoNight.usesNightCompressor && stereoNight.loudnessTargetLUFS == -20.0)

        let atmosRef = AudioEnhancementMode.reference.shapingParameters(effectiveSpeakerLayout: "7.1.4")
        #expect(atmosRef.maxChannels == nil && atmosRef.lfeMixDB == nil)
    }

    @Test("TvCandidateInfo.decodeFlexInt and Model formatters handle out-of-range finite Doubles without trapping")
    func candidateDecodeFlexIntAndModelFormattersExtremeDoubles() throws {
        let extremeValues = ["1e30", "-1e30", "9223372036854775808.0"]
        for rawNum in extremeValues {
            let payload = """
            {
              "candidateId": "cand-extreme",
              "displayHeadline": "Extreme",
              "releaseTitle": "Extreme.Test",
              "source": "nvme",
              "dvProfile": \(rawNum),
              "sizeBytes": \(rawNum),
              "tvScore": \(rawNum),
              "channels": \(rawNum)
            }
            """
            let candidate = try JSONDecoder().decode(TvCandidateInfo.self, from: Data(payload.utf8))
            #expect(candidate.candidateId == "cand-extreme")
            #expect(candidate.dvProfile == nil)
            #expect(candidate.sizeBytes == nil)
            #expect(candidate.tvScore == nil)
            #expect(candidate.channels == nil)
        }

        let validRoundPayload = #"{"candidateId":"c-ok","tvScore":87.6,"sizeBytes":1024.4,"dvProfile":7.0,"channels":6.0}"#
        let valid = try JSONDecoder().decode(TvCandidateInfo.self, from: Data(validRoundPayload.utf8))
        #expect(valid.tvScore == 88 && valid.sizeBytes == 1024 && valid.dvProfile == 7 && valid.channels == "5.1")

        let epExtreme = TvEpisodeCard(itemId: "ep1", seasonNumber: 1, episodeNumber: 1, title: "T", runtimeSeconds: 1e30, watched: false)
        #expect(epExtreme.formattedRuntime == nil)
        let cardExtreme = TvMediaCard(
            itemId: "m1",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 1),
            title: "T",
            progress: TvWatchProgress(positionSeconds: 20, durationSeconds: 1e30, percent: 1)
        )
        #expect(cardExtreme.cleanContinueSubtitle == "Film")
    }

    @Test("SeriesFlowEligibility.postCreditsSkipTargetSeconds supports overlapping mid-credits and trailing post_credits")
    func postCreditsOverlappingMidCreditsStinger() throws {
        let rawProbes = Data(#"""
        [
          {"id":"ch-main","title":"Chapter 1","startSeconds":0,"endSeconds":6000,"kind":"chapter"},
          {"id":"ch-cred","title":"End Credits","startSeconds":6000,"endSeconds":6320,"kind":"credits"},
          {"id":"ch-post","title":"Mid-Credits Stinger","startSeconds":6200,"endSeconds":6260,"kind":"post_credits"}
        ]
        """#.utf8)
        let probes = try JSONDecoder().decode([TvProbeChapter].self, from: rawProbes)
        let merged = PlaybackChapter.mergeRaw(probeChapters: probes, engineChapters: [], mediaDuration: 6320)

        #expect(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6020, authoritativeDurationSeconds: 6320, chapters: merged) == 6200.0)
        #expect(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6200, authoritativeDurationSeconds: 6320, chapters: merged) == nil)
        #expect(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6210, authoritativeDurationSeconds: 6320, chapters: merged) == nil)

        let trailing = [
            PlaybackChapter(id: "c-cr", index: 0, title: "Rulletekst", startSeconds: 6000, endSeconds: 6240, kind: .credits),
            PlaybackChapter(id: "c-st", index: 1, title: "Etter rulletekst", startSeconds: 6240, endSeconds: 6310, kind: .postCredits),
        ]
        #expect(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6050, authoritativeDurationSeconds: 6320, chapters: trailing) == 6240.0)
        #expect(SeriesFlowEligibility.postCreditsSkipTargetSeconds(currentTime: 6245, authoritativeDurationSeconds: 6320, chapters: trailing) == nil)
    }

    @Test("SmartTrackRuleEngine.selectBestSubtitleID matches ISO 639-1 and 639-2 B/T aliases")
    func smartTrackRuleEngineISO639Aliases() {
        let fra = SmartTrackDescriptor(id: 1, name: "Français", codec: "srt", language: "fra")
        let eng = SmartTrackDescriptor(id: 2, name: "English", codec: "srt", language: "eng")
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "fr", in: [fra, eng]) == 1)
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "fre", in: [fra, eng]) == 1)

        let ger = SmartTrackDescriptor(id: 1, name: "Deutsch", codec: "srt", language: "ger")
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "de", in: [ger, eng]) == 1)
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "deu", in: [ger, eng]) == 1)
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "ger", in: [ger, eng]) == 1)

        let jpn = SmartTrackDescriptor(id: 1, name: "Japanese", codec: "srt", language: "jpn")
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "ja", in: [jpn, eng]) == 1)
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "jpn", in: [jpn, eng]) == 1)

        let zho = SmartTrackDescriptor(id: 1, name: "Chinese", codec: "srt", language: "chi")
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "zh-CN", in: [zho, eng]) == 1)
        #expect(SmartTrackRuleEngine.selectBestSubtitleID(forLanguage: "zho", in: [zho, eng]) == 1)
    }
}
