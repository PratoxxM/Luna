import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class M4AMockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])
    private static let requestsByHost = Mutex<[String: [URLRequest]]>([:])

    static func register(host: String, handler: @escaping Handler) {
        let key = host.lowercased()
        handlers.withLock { $0[key] = handler }
        requestsByHost.withLock { $0[key] = [] }
    }

    static func unregister(host: String) {
        let key = host.lowercased()
        _ = handlers.withLock { $0.removeValue(forKey: key) }
        _ = requestsByHost.withLock { $0.removeValue(forKey: key) }
    }

    static func requests(for host: String) -> [URLRequest] {
        requestsByHost.withLock { $0[host.lowercased()] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestsByHost.withLock { $0[host, default: []].append(request) }
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

    static func makeClient(host: String) -> LunaCoreClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [M4AMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LunaCoreClient(
            baseURL: URL(string: "http://\(host):8090")!,
            deviceID: "luna-m4a-linux",
            deviceToken: "tok-m4a-linux",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: true,
            session: session,
            imageSession: session,
            externalImageSession: session
        )
    }
}

private final class M4AMockSession: TabSessionContext, SearchSessionContext, @unchecked Sendable {
    var serverBaseURL: URL?
    var roomName: String = "Kjellerstua"
    var hardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    let client: LunaCoreClient
    var recent: [String] = []
    var unpairCalls = 0

    init(host: String) {
        self.serverBaseURL = URL(string: "http://\(host):8090")
        self.client = M4AMockURLProtocol.makeClient(host: host)
    }

    func makeHomeClient() -> (any HomeClientProviding)? { client }
    func makeCatalogClient() -> (any CatalogClientProviding)? { client }
    func makeLibraryClient() -> (any LibraryClientProviding)? { client }
    func makeSearchClient() -> (any SearchClientProviding)? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() { unpairCalls += 1 }
    func loadRecentSearches() -> [String] { recent }
    @discardableResult
    func recordRecentSearch(_ term: String) -> [String] {
        recent.removeAll { $0 == term }
        recent.insert(term, at: 0)
        return recent
    }
    func clearRecentSearches() { recent.removeAll() }
}

@MainActor
private final class M4ADetailContext: MediaDetailSessionContext {
    var roomName: String = "Kjellerstua"
    var hardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var activePlaybackTarget: PlaybackLaunchRequest?
    var keepDisplayModeInMenuAfterPlayback: Bool = false
    var client: LunaCoreClient?
    let store = PlaybackStopReceiptStore()

    var lastPlaybackStopReceipt: PlaybackStopReceipt? { store.lastReceipt }
    func makeClient() -> LunaCoreClient? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
    func awaitPlaybackStopReceipt(for itemId: String, timeout: Duration) async -> PlaybackStopReceipt? {
        await store.awaitReceipt(for: itemId, timeout: timeout)
    }
}

final class M4AClientParityAndModelsTests: XCTestCase {
    private static func makeSession(
        sessionId: String = "sess-1",
        source: String,
        tier: String?
    ) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: sessionId,
            streamToken: "tok-stream-1234",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            item: TvPlaybackItemContext(
                itemId: "movie:tmdb:550",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 550),
                title: "Fight Club"
            ),
            selectedCandidate: TvCandidateInfo(
                candidateId: "cand-1",
                displayHeadline: "4K DV P7 FEL",
                releaseTitle: "Fight.Club.2160p",
                source: source,
                tier: tier,
                resolution: "2160p",
                videoRangeType: "DolbyVision",
                dvProfile: 7,
                dvEnhancementLayer: "FEL",
                audioCodec: "TrueHD",
                sizeBytes: nil,
                tvScore: 1400,
                isActive: true,
                explanationChips: ["NVMe", "Dolby Vision"],
                releaseGroup: "FraMeSToR",
                isNorwegian: false
            ),
            stream: TvStreamEndpoint(url: "/api/tv/v2/stream/sess-1/tok/video.mkv"),
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: true,
                dolbyVisionHandling: "automatic",
                matchContentEnabled: true,
                audioBridgeMode: "lossless"
            )
        )
    }

    // MARK: - P3.5a Trickplay / Scrub-Frame

    func testTrickplayPolicyAndFetchScrubFrameEndpoint() async throws {
        XCTAssertEqual(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 14.9, durationSeconds: 3600), 10)
        XCTAssertEqual(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 3599.9, durationSeconds: 3600), 3595)
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: -1, durationSeconds: 3600))
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: .nan, durationSeconds: 3600))
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 1e30, durationSeconds: 0))

        XCTAssertFalse(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(
            session: Self.makeSession(source: "archive", tier: "archive")
        ))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(
            session: Self.makeSession(source: "infinidysk", tier: "vfs")
        ))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(
            session: Self.makeSession(source: "easynews", tier: "remote")
        ))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(
            session: Self.makeSession(source: "nvme", tier: "nvme")
        ))

        XCTAssertTrue(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 404, errorCode: "archive_spindown_protected"))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 404, errorCode: "scrub_source_unavailable"))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 410, errorCode: "session_ended"))
        XCTAssertFalse(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 404, errorCode: "scrub_frame_unavailable"))
        XCTAssertFalse(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 503, errorCode: "trickplay_busy"))

        let host = "m4a-scrub-\(UUID().uuidString.lowercased()).invalid"
        defer { M4AMockURLProtocol.unregister(host: host) }
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        M4AMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let t = comps?.queryItems?.first(where: { $0.name == "t" })?.value
            switch t {
            case "15":
                let resp = try XCTUnwrap(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "image/jpeg", "X-Trickplay-Cache": "HIT"]
                ))
                return (resp, jpegBytes)
            case "20":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":false,"code":"archive_spindown_protected","error":"Arkiv beskyttet"}"#.utf8))
            case "25":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":false,"code":"scrub_frame_unavailable","error":"Utilgjengelig"}"#.utf8))
            case "30":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":false,"code":"trickplay_busy","error":"Opptatt"}"#.utf8))
            default:
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":false,"error":"Unauthorized"}"#.utf8))
            }
        }

        let client = M4AMockURLProtocol.makeClient(host: host)
        let hit = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 18.4)
        XCTAssertEqual(hit, .image(data: jpegBytes, cacheHit: true))

        let archiveMiss = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 22.0)
        XCTAssertEqual(archiveMiss, .unavailable(statusCode: 404, code: "archive_spindown_protected"))

        let tempMiss = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 27.0)
        XCTAssertEqual(tempMiss, .unavailable(statusCode: 404, code: "scrub_frame_unavailable"))

        let busy = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 31.0)
        XCTAssertEqual(busy, .unavailable(statusCode: 503, code: "trickplay_busy"))

        do {
            _ = try await client.fetchScrubFrame(sessionId: "sess-1", atSeconds: 40.0)
            XCTFail("Expected unauthorized")
        } catch LunaCoreError.unauthorized {}

        let sentURLs = M4AMockURLProtocol.requests(for: host).compactMap { $0.url?.absoluteString }
        XCTAssertTrue(sentURLs.contains { $0.contains("/api/tv/v2/playback/sess-1/scrub-frame?t=15") })
    }

    // MARK: - P3.5b Embedded MKV Auto-Align

    func testEmbeddedAutoAlignTrackMatchingDecodingAndErrorMapping() async throws {
        let externals = [TvExternalSubtitle(id: "ext-1", url: "/sub/1.srt", language: "nob", name: "Norsk .srt")]
        let embeddedTrack = SmartTrackDescriptor(id: 0, name: "Norsk", codec: "subrip", language: "nob", isExternal: false)
        XCTAssertNil(PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(for: embeddedTrack, in: externals))

        let externalTrack = SmartTrackDescriptor(id: 5, name: "Norsk .srt", codec: "srt", language: "nob", isExternal: true)
        XCTAssertEqual(PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(for: externalTrack, in: externals)?.id, "ext-1")
        XCTAssertEqual(PlaybackSubtitleSyncActionPolicy.matchingExternalSubtitle(for: nil, in: externals)?.id, "ext-1")

        let embeddedMeta = [
            TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "subrip", language: "nob", displayTitle: "Norsk"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "hdmv_pgs_subtitle", language: "eng", displayTitle: "English PGS"),
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(
                for: embeddedTrack,
                embeddedSubtitles: embeddedMeta,
                allDescriptors: [embeddedTrack, externalTrack]
            ),
            2
        )

        // 3-track ordinal collision: embedded stream indices [2, 3, 4] vs 0-based descriptors [0, 1, 2]
        let threeEmbeddedMixed = [
            TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "hdmv_pgs_subtitle", language: "eng", displayTitle: "English"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "subrip", language: "swe", displayTitle: "Svenska"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 4, codec: "subrip", language: "nob", displayTitle: "Norsk"),
        ]
        let ordinalDescriptorsMixed = [
            SmartTrackDescriptor(id: 0, name: "English", codec: "hdmv_pgs_subtitle", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 1, name: "Svenska", codec: "subrip", language: "swe", isExternal: false),
            SmartTrackDescriptor(id: 2, name: "Norsk", codec: "subrip", language: "nob", isExternal: false),
            externalTrack,
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(
                for: ordinalDescriptorsMixed[2],
                embeddedSubtitles: threeEmbeddedMixed,
                allDescriptors: ordinalDescriptorsMixed
            ),
            4
        )

        // 3-track same-language ordinal collision: [2: eng, 3: eng, 4: eng] vs 0-based [0: eng, 1: eng, 2: eng]
        let threeEmbeddedSameLang = [
            TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "subrip", language: "eng", displayTitle: "English SDH"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "subrip", language: "eng", displayTitle: "English Commentary"),
            TvSessionEmbeddedSubtitleTrack(streamIndex: 4, codec: "subrip", language: "eng", displayTitle: "English Forced"),
        ]
        let ordinalDescriptorsSameLang = [
            SmartTrackDescriptor(id: 0, name: "English SDH", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 1, name: "English Commentary", codec: "subrip", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 2, name: "English Forced", codec: "subrip", language: "eng", isExternal: false),
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(
                for: ordinalDescriptorsSameLang[2],
                embeddedSubtitles: threeEmbeddedSameLang,
                allDescriptors: ordinalDescriptorsSameLang
            ),
            4
        )

        // 3-track global stream-indexed descriptors: [2: eng, 3: swe, 4: nob] vs [2: eng, 3: swe, 4: nob]
        let globalDescriptors = [
            SmartTrackDescriptor(id: 2, name: "English", codec: "hdmv_pgs_subtitle", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 3, name: "Svenska", codec: "subrip", language: "swe", isExternal: false),
            SmartTrackDescriptor(id: 4, name: "Norsk", codec: "subrip", language: "nob", isExternal: false),
        ]
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.resolvedEmbeddedTrackIndex(
                for: globalDescriptors[2],
                embeddedSubtitles: threeEmbeddedMixed,
                allDescriptors: globalDescriptors
            ),
            4
        )
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.friendlyAlignReasonMessage("invalid_extracted_srt"),
            "Kunne ikke lese innebygd undertekst"
        )
        XCTAssertEqual(
            PlaybackSubtitleSyncActionPolicy.friendlyAlignReasonMessage("bitmap_subtitle_not_supported"),
            "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk"
        )

        let embeddedResponseJSON = #"""
        {
          "ok": true,
          "requestId": "req-1",
          "sessionId": "sess-emb",
          "applied": true,
          "appliedToFile": false,
          "mode": "embedded_ffmpeg_silencedetect",
          "method": "embedded_ffmpeg_silencedetect",
          "reason": "audio_activity_aligned",
          "confidence": 0.78,
          "offsetMs": 1200,
          "scale": 1,
          "subtitleDelayMs": 1200,
          "subtitle": null,
          "embeddedTrack": { "streamIndex": 2, "codec": "subrip", "language": "nob" }
        }
        """#
        let decoded = try JSONDecoder().decode(TvSubtitleAutoAlignResponse.self, from: Data(embeddedResponseJSON.utf8))
        XCTAssertTrue(decoded.applied)
        XCTAssertEqual(decoded.appliedToFile, false)
        XCTAssertEqual(decoded.method, "embedded_ffmpeg_silencedetect")
        XCTAssertEqual(decoded.confidence, 0.78)
        XCTAssertNil(decoded.subtitle)
        XCTAssertEqual(decoded.embeddedTrack?.streamIndex, 2)
        XCTAssertEqual(decoded.embeddedTrack?.codec, "subrip")

        let unalignedJSON = #"{"ok":true,"sessionId":"sess-emb","applied":false,"appliedToFile":false,"reason":"align_unavailable"}"#
        let unaligned = try JSONDecoder().decode(TvSubtitleAutoAlignResponse.self, from: Data(unalignedJSON.utf8))
        XCTAssertFalse(unaligned.applied)
        XCTAssertEqual(unaligned.subtitleDelayMs, 0)

        let host = "m4a-align-\(UUID().uuidString.lowercased()).invalid"
        defer { M4AMockURLProtocol.unregister(host: host) }
        M4AMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"code":"bitmap_subtitle_not_supported","error":"Bitmap PGS"}"#.utf8))
        }
        let client = M4AMockURLProtocol.makeClient(host: host)
        do {
            _ = try await client.autoAlignSubtitles(sessionId: "sess-emb", trackIndex: 3, language: "eng", applyToFile: false)
            XCTFail("Expected 422 serverMessage")
        } catch let LunaCoreError.serverMessage(status, message) {
            XCTAssertEqual(status, 422)
            XCTAssertEqual(message, "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk")
        }
    }

    // MARK: - P3.5c ComfortPreferences Sync & /bootstrap Parity

    @MainActor
    func testComfortPreferencesSixKeySyncHigh2026NilPreservationAndBootstrapDevice() async throws {
        let suite = "luna.v1.test.m4a.comfort.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let highComfort = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
        let unsetOverrides = highComfort.toDeviceOverrides()
        XCTAssertNil(unsetOverrides.lowResUpscaleMode)
        XCTAssertNil(unsetOverrides.upscalesFullHDVideo)
        XCTAssertEqual(unsetOverrides.menuDisplayMode, "sdr_60hz")
        XCTAssertEqual(unsetOverrides.audioEnhancement, "reference")
        XCTAssertEqual(unsetOverrides.showNerdHUD, false)
        XCTAssertEqual(unsetOverrides.recognizesBitmapSubtitleText, false)

        var syncCalls: [TvDeviceOverrides] = []
        highComfort.onSyncRequested = { syncCalls.append($0) }

        // Adopting null lowResUpscaleMode / upscalesFullHDVideo must NOT clobber .high2026 defaults
        highComfort.adoptServerOverrides(
            TvDeviceOverrides(
                lowResUpscaleMode: nil,
                upscalesFullHDVideo: nil,
                menuDisplayMode: "hdr_60hz_qms",
                audioEnhancement: "dialogue_lift",
                showNerdHUD: true,
                recognizesBitmapSubtitleText: true
            )
        )
        XCTAssertTrue(syncCalls.isEmpty)
        XCTAssertEqual(highComfort.lowResUpscaleMode, .auto)
        XCTAssertTrue(highComfort.upscalesFullHDVideo)
        XCTAssertNil(defaults.object(forKey: SideloadSafeStorage.lowResUpscaleModeKey))
        XCTAssertNil(defaults.object(forKey: SideloadSafeStorage.fullHDUpscaleEnabledKey))
        XCTAssertEqual(highComfort.menuDisplayMode, .preserveHDR60HzQMS)
        XCTAssertEqual(highComfort.audioEnhancement, .dialogueLift)
        XCTAssertTrue(highComfort.showNerdHUD)
        XCTAssertTrue(highComfort.recognizesBitmapSubtitleText)

        // Alias normalization
        highComfort.adoptServerOverrides(
            TvDeviceOverrides(lowResUpscaleMode: "animeLineArt", audioEnhancement: "night_mode")
        )
        XCTAssertEqual(highComfort.lowResUpscaleMode, .animeLineArt)
        XCTAssertEqual(highComfort.audioEnhancement, .nightMode)
        XCTAssertTrue(syncCalls.isEmpty)

        // Mutating all 6 synced keys emits onSyncRequested; audioDelayMs remains local-only
        highComfort.lowResUpscaleMode = .off
        highComfort.upscalesFullHDVideo = false
        highComfort.menuDisplayMode = .preserveExactMatch
        highComfort.audioEnhancement = .reference
        highComfort.showNerdHUD = false
        highComfort.recognizesBitmapSubtitleText = false
        XCTAssertEqual(syncCalls.count, 6)
        XCTAssertEqual(syncCalls.last?.lowResUpscaleMode, "off")
        XCTAssertEqual(syncCalls.last?.upscalesFullHDVideo, false)

        highComfort.audioDelayMs = 250
        XCTAssertEqual(syncCalls.count, 6, "audioDelayMs must stay device-local")

        // Bootstrap device JSON decoding + ServerSessionCore.isHardwareProfileExplicit
        let bootJSON = #"""
        {
          "ok": true,
          "device": {
            "deviceId": "dev-1",
            "deviceName": "Kjellerstua TV",
            "roomName": "Kjellerstua",
            "roomUnassigned": false,
            "hardwareProfile": "dv-fel-714",
            "hardwareProfileExplicit": false,
            "speakerLayout": "7.1.4",
            "model": "AppleTV14,1",
            "osVersion": "tvOS 26.0",
            "appVersion": "3.0.0",
            "equipmentLabel": "LG OLED · Dolby Vision · Sonos 7.1.4",
            "atmosphere": "cinema",
            "overrides": {
              "lowResUpscaleMode": "auto",
              "upscalesFullHDVideo": true,
              "menuDisplayMode": "hdr_60hz_qms",
              "audioEnhancement": "dialogueLift",
              "showNerdHUD": true,
              "recognizesBitmapSubtitleText": true
            }
          }
        }
        """#
        let boot = try JSONDecoder().decode(TvBootstrapResponse.self, from: Data(bootJSON.utf8))
        XCTAssertEqual(boot.device.hardwareProfileExplicit, false)
        XCTAssertEqual(boot.device.model, "AppleTV14,1")
        XCTAssertEqual(boot.device.osVersion, "tvOS 26.0")
        XCTAssertEqual(boot.device.appVersion, "3.0.0")

        let sessionCore = ServerSessionCore(defaults: defaults)
        sessionCore.syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
        XCTAssertFalse(sessionCore.isHardwareProfileExplicit)
        XCTAssertTrue(sessionCore.comfort.showNerdHUD)
        XCTAssertTrue(sessionCore.comfort.recognizesBitmapSubtitleText)
    }

    // MARK: - P3.5d-core Season 0 Specials & P2.3-core Search kind

    @MainActor
    func testSeasonZeroSpecialsAndSearchKindFiltering() async throws {
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 0, episode: 1), "S00E01")
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:100:s0:e1")?.season, 0)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:100:s0:e1")?.episode, 1)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("S00E04")?.season, 0)
        XCTAssertEqual(EpisodeTitleFormatter.parseEpisodeCode("0x04")?.season, 0)
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle("S00E01 · Julegave", seriesTitle: "Show", season: 0, episode: 1),
            "Julegave"
        )
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("S00E01", seriesTitle: "Show", season: 0, episode: 1))
        XCTAssertEqual(LunaCopy.localizedSeasonTitle("Specials", seasonNumber: 0), "Spesialer")
        XCTAssertEqual(LunaCopy.formatListEpisodeCode(season: 0, episode: 2), "S0 · E2")

        let upcomingSpecialCard = TvMediaCard(
            itemId: "series:tmdb:100",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 100),
            title: "Show",
            nextUp: TvNextUpPointer(season: 0, episode: 2)
        )
        XCTAssertEqual(upcomingSpecialCard.cleanUpcomingSubtitle, "Spesialer · Episode 2")

        let host = "m4a-s0-search-\(UUID().uuidString.lowercased()).invalid"
        defer { M4AMockURLProtocol.unregister(host: host) }
        M4AMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/items/series/series:tmdb:100" {
                let body = #"""
                {
                  "ok": true,
                  "item": {
                    "itemId": "series:tmdb:100",
                    "mediaType": "series",
                    "ids": { "tmdb": 100 },
                    "title": "Specials Show",
                    "inWatchlist": false,
                    "watched": false,
                    "selectedSeason": 0,
                    "seasons": [{ "seasonNumber": 0, "name": "Specials", "episodeCount": 1 }],
                    "episodes": [{ "itemId": "episode:tmdb:100:s0:e1", "seasonNumber": 0, "episodeNumber": 1, "title": "Pilot Special", "watched": false }]
                  }
                }
                """#
                return (resp, Data(body.utf8))
            }
            if url.path == "/api/tv/v2/items/series/100/seasons/0" {
                let body = #"{"ok":true,"tmdbId":100,"seasonNumber":0,"title":"Spesialer","episodes":[{"itemId":"episode:tmdb:100:s0:e1","seasonNumber":0,"episodeNumber":1,"title":"Pilot Special","watched":false}]}"#
                return (resp, Data(body.utf8))
            }
            if url.path == "/api/tv/v2/search" {
                let kind = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "kind" })?.value ?? "all"
                let body = #"{"ok":true,"query":"dune","kind":"\#(kind)","localCount":1,"items":[{"itemId":"movie:tmdb:693134","mediaType":"movie","ids":{"tmdb":693134},"title":"Dune"}]}"#
                return (resp, Data(body.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let client = M4AMockURLProtocol.makeClient(host: host)
        _ = try await client.fetchItemDetail(mediaType: "series", itemId: "series:tmdb:100", seasonNumber: 0)
        let s0Eps = try await client.fetchSeasonEpisodes(tmdbId: 100, seasonNumber: 0)
        XCTAssertEqual(s0Eps.seasonNumber, 0)
        XCTAssertEqual(s0Eps.title, "Spesialer")

        let ctx = M4ADetailContext()
        ctx.client = client
        let detailVM = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:100", initialTitle: "Specials Show")
        detailVM.bind(sessionContext: ctx)
        await detailVM.handleTaskAppearance(scopeKey: detailVM.currentScopeKey, sessionContext: ctx)
        XCTAssertEqual(detailVM.selectedSeasonNumber, 0)
        let loadedItem = try XCTUnwrap(detailVM.detail)
        XCTAssertEqual(detailVM.primaryPlayLabel(loadedItem), "Spill S0 E1")
        XCTAssertEqual(detailVM.primaryTargetInfo(loadedItem).season, 0)

        await detailVM.markLocalMutationAndReload()
        XCTAssertEqual(detailVM.selectedSeasonNumber, 0)

        let reqPaths = M4AMockURLProtocol.requests(for: host).compactMap { req -> String? in
            guard let u = req.url else { return nil }
            return u.query.map { "\(u.path)?\($0)" } ?? u.path
        }
        XCTAssertTrue(reqPaths.contains { $0.contains("season=0") })
        XCTAssertTrue(reqPaths.contains("/api/tv/v2/items/series/100/seasons/0"))

        // P2.3 Search kind filter
        let session = M4AMockSession(host: host)
        let searchVM = SearchViewModel()
        searchVM.query = "dune"
        await searchVM.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(searchVM.lastCompletedKind, .all)

        searchVM.selectedKind = .series
        await searchVM.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(searchVM.lastCompletedKind, .series)
        let searchReqPaths = M4AMockURLProtocol.requests(for: host).compactMap { req -> String? in
            guard let u = req.url else { return nil }
            return u.query.map { "\(u.path)?\($0)" } ?? u.path
        }
        XCTAssertTrue(searchReqPaths.contains { $0.contains("/api/tv/v2/search") && $0.contains("kind=series") })
    }

    // MARK: - P3.2 Models & ViewModels

    @MainActor
    func testP32RichModelsOptimisticStopReceiptPreservationAndLibraryFilters() async throws {
        let detailJSON = #"""
        {
          "itemId": "series:tmdb:95396",
          "mediaType": "series",
          "ids": { "tmdb": 95396 },
          "title": "Severance",
          "originalTitle": "Severance",
          "tagline": "We're all different people.",
          "imdbRating": 8.7,
          "imdbVotes": 340000,
          "rottenTomatoesScore": 97,
          "metacriticScore": 83,
          "cast": ["Adam Scott"],
          "castMembers": [
            { "name": "Adam Scott", "character": "Mark Scout", "profileUrl": "/img/adam.jpg" },
            { "name": "Britt Lower", "character": "Helly Riggs", "profileUrl": null }
          ],
          "inWatchlist": true,
          "watched": false,
          "nextUp": { "season": 1, "episode": 1 },
          "nextEpisode": {
            "itemId": "episode:tmdb:95396:s1:e2",
            "season": 1,
            "episode": 2,
            "title": "Half Loop",
            "runtimeSeconds": 3300
          }
        }
        """#
        let decodedDetail = try JSONDecoder().decode(TvItemDetail.self, from: Data(detailJSON.utf8))
        XCTAssertEqual(decodedDetail.castMembers?.count, 2)
        XCTAssertNil(decodedDetail.castMembers?[1].profileUrl)
        XCTAssertEqual(decodedDetail.rottenTomatoesScore, 97)
        XCTAssertEqual(decodedDetail.metacriticScore, 83)
        XCTAssertEqual(decodedDetail.imdbVotes, 340000)
        XCTAssertEqual(decodedDetail.tagline, "We're all different people.")
        XCTAssertEqual(decodedDetail.nextEpisode?.runtimeSeconds, 3300)

        let seriesVM = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        seriesVM.detail = decodedDetail
        seriesVM.applyOptimisticStopReceipt(PlaybackStopReceipt(
            itemId: "episode:tmdb:95396:s1:e1", mediaType: "episode",
            seasonNumber: 1, episodeNumber: 1, positionSeconds: 1200, durationSeconds: 3000, completed: false
        ))
        XCTAssertEqual(seriesVM.detail?.castMembers?.count, 2)
        XCTAssertEqual(seriesVM.detail?.rottenTomatoesScore, 97)
        XCTAssertEqual(seriesVM.detail?.tagline, "We're all different people.")

        let movieVM = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:550", initialTitle: "Fight Club")
        movieVM.detail = TvItemDetail(
            itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club",
            originalTitle: "Fight Club", tagline: "Mischief. Mayhem. Soap.",
            imdbVotes: 2400000, rottenTomatoesScore: 80, metacriticScore: 67,
            cast: ["Brad Pitt"], castMembers: [TvCastMember(name: "Brad Pitt", character: "Tyler Durden")],
            inWatchlist: false, watched: false
        )
        movieVM.applyOptimisticStopReceipt(PlaybackStopReceipt(
            itemId: "movie:tmdb:550", mediaType: "movie",
            positionSeconds: 5000, durationSeconds: 5200, completed: true
        ))
        XCTAssertEqual(movieVM.detail?.rottenTomatoesScore, 80)
        XCTAssertEqual(movieVM.detail?.castMembers?.first?.name, "Brad Pitt")
        XCTAssertTrue(movieVM.detail?.watched == true)

        // TvSessionTracks + HomeViewModel.tonightReasonLabel + TvCandidateInfo chips
        let tracksJSON = #"""
        {
          "probeConfidence": "cached_ffprobe",
          "subtitleDelayMs": 0,
          "video": {
            "streamIndex": 0, "codec": "hevc", "width": 3840, "height": 2160,
            "frameRate": 23.976, "videoRangeType": "HDR10Plus", "hdr10Plus": true
          },
          "audio": [{
            "streamIndex": 1, "codec": "truehd", "spatialFormat": "DolbyAtmos",
            "channels": 8, "channelLayout": "7.1", "language": "eng", "displayTitle": "Atmos", "isDefault": true
          }],
          "embeddedSubtitles": [{
            "streamIndex": 2, "codec": "subrip", "language": "nob",
            "displayTitle": "Norsk", "isForced": false, "isDefault": true
          }]
        }
        """#
        let tracks = try JSONDecoder().decode(TvSessionTracks.self, from: Data(tracksJSON.utf8))
        XCTAssertEqual(tracks.video?.hdr10Plus, true)
        XCTAssertEqual(tracks.audio?.first?.spatialFormat, "DolbyAtmos")
        XCTAssertEqual(tracks.embeddedSubtitles?.first?.streamIndex, 2)

        let homeVM = HomeViewModel()
        XCTAssertNil(homeVM.tonightReasonLabel)
        let session = Self.makeSession(source: "nvme", tier: "nvme")
        XCTAssertEqual(session.selectedCandidate.explanationChips, ["NVMe", "Dolby Vision"])
        XCTAssertEqual(session.selectedCandidate.releaseGroup, "FraMeSToR")
        XCTAssertEqual(session.selectedCandidate.trimmedReleaseGroup, "FraMeSToR")
        XCTAssertEqual(
            session.selectedCandidate.deduplicatedExplanationChips(excluding: [], maxCount: 2),
            ["NVMe", "Dolby Vision"]
        )
        XCTAssertEqual(
            session.selectedCandidate.deduplicatedExplanationChips(excluding: ["på nvme"], maxCount: 2),
            ["Dolby Vision"]
        )
        let richMeta = session.selectedCandidate.richRowSubtitle(
            isRecommended: true,
            activeLabel: "Spilles nå",
            compactForQuickPanel: false
        )
        XCTAssertTrue(richMeta.contains("FraMeSToR"))
        XCTAssertTrue(richMeta.contains("Dolby Vision"))
        let tonight = TvTonightPayload(reason: "continue", reasonLabel: "Anbefalt for deg i kveld")
        XCTAssertEqual(tonight.reasonLabel, "Anbefalt for deg i kveld")

        // LibraryViewModel tier/sort filtering & DiskSWRStore bypass
        let host = "m4a-lib-\(UUID().uuidString.lowercased()).invalid"
        defer { M4AMockURLProtocol.unregister(host: host) }
        M4AMockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let tier = comps?.queryItems?.first(where: { $0.name == "tier" })?.value ?? "all"
            let sort = comps?.queryItems?.first(where: { $0.name == "sort" })?.value ?? "recent"
            let body = #"""
            {
              "ok": true,
              "section": "local",
              "activeFilters": { "tier": "\#(tier)", "mediaType": "movie", "sort": "\#(sort)" },
              "counts": { "watchlist": 1, "localTotal": 10, "localMovies": 6, "localSeries": 4, "nvme": 3, "archive": 5, "vfs": 2, "customLists": 0 },
              "watchlist": [],
              "localItems": [{ "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Fight Club" }],
              "localHasMore": false
            }
            """#
            let resp = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["ETag": "\"lib-\(tier)-\(sort)\""]
            ))
            return (resp, Data(body.utf8))
        }

        let libSession = M4AMockSession(host: host)
        let libVM = LibraryViewModel()
        libVM.selectedTier = .nvme
        libVM.selectedSort = .rating
        XCTAssertTrue(libVM.queryKey(for: libSession).contains("#nvme#rating#"))

        await libVM.loadLibrary(session: libSession)
        XCTAssertEqual(libVM.libraryPayload?.activeFilters?.tier, "nvme")
        XCTAssertEqual(libVM.libraryPayload?.activeFilters?.sort, "rating")
        XCTAssertEqual(libVM.count(for: .nvme), 3)
        XCTAssertEqual(libVM.count(for: .archive), 5)
        XCTAssertEqual(libVM.count(for: .vfs), 2)
        XCTAssertNil(
            DiskSWRStore.libraryMemorySnapshot(
                section: "local",
                mediaType: "movie",
                serverHost: host,
                roomName: libSession.roomName,
                hardwareProfile: libSession.hardwareProfile
            )
        )
    }
}
