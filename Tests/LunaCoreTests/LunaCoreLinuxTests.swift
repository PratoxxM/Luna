import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

// MARK: - Linux-Safe URLProtocol Test Double

private final class CoreURLProtocolMock: URLProtocol {
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

// MARK: - Pure Swift Linux Test Suite

final class LunaCoreLinuxTests: XCTestCase {
    private func makeSampleSession(
        sessionId: String = "sess-1",
        streamPath: String = "/api/tv/v1/stream/sess-1/video.mkv",
        tier: String = "nvme",
        canPrewarm: Bool = true,
        startSeconds: Double = 120
    ) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: sessionId,
            streamToken: "stream-secret-token-1234",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            item: TvPlaybackItemContext(
                itemId: "movie:693134",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 693134, imdb: "tt15239678", tvdb: nil),
                title: "Dune: Part Two",
                seriesTitle: nil,
                season: nil,
                episode: nil,
                year: 2024,
                runtimeSeconds: 9960,
                posterUrl: "/art/dune2-poster.jpg",
                backdropUrl: "/art/dune2-backdrop.jpg",
                logoUrl: nil
            ),
            selectedCandidate: TvCandidateInfo(
                candidateId: "cand-\(tier)",
                displayHeadline: "4K Remux · DV P7 FEL · TrueHD Atmos",
                releaseTitle: "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.HEVC.TrueHD.7.1.Atmos",
                source: tier,
                tier: tier,
                resolution: "2160p",
                videoRangeType: "DolbyVision",
                dvProfile: 7,
                dvEnhancementLayer: "FEL",
                audioCodec: "TrueHD Atmos",
                sizeBytes: 68_719_476_736,
                tvScore: 980,
                isActive: true,
                explanationChips: ["På NVMe", "DV P7 FEL"],
                releaseGroup: "CiNE",
                isNorwegian: true
            ),
            stream: TvStreamEndpoint(
                url: streamPath,
                container: "mkv",
                supportsByteRanges: true,
                zeroCopyMode: "206",
                canClientPrewarmBytes: canPrewarm,
                startPositionSeconds: startSeconds,
                declaredDurationSeconds: 9960
            ),
            tracks: nil,
            chapters: nil,
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: true,
                foldsDolbyVisionFEL: true,
                dolbyVisionHandling: "automatic",
                matchContentEnabled: true,
                attemptsHDRMasterOnUnprovenPanel: false,
                objectAudioRendering: TvObjectAudioConfig(mode: "render", layout: "7.1.4"),
                audioBridgeMode: "surroundCompat",
                preferredAudioLanguages: ["nob", "eng"],
                preferredSubtitleLanguages: ["nob", "eng"],
                skipsContainerAttachments: true,
                generatesBackgroundScrubPreviews: false,
                serveIFramePlaylist: false,
                confirmAtmos: false,
                maxConcurrentSourceRequests: 2,
                declaredDurationSeconds: 9960
            ),
            heartbeatIntervalSeconds: 10,
            nextEpisode: nil
        )
    }

    func testPlaybackCurtainWatchdogReadinessAndFallbackDeadline() {
        let session = makeSampleSession(sessionId: "nvme-1", tier: "nvme", canPrewarm: true)
        XCTAssertEqual(session.sessionId, "nvme-1")
        XCTAssertEqual(PlaybackCurtainWatchdog.defaultFallbackTimeoutSeconds, 5.0, accuracy: 0.001)

        func reveal(
            fatal: Bool = false,
            switching: Bool = false,
            resolving: Bool = false,
            restoring: Bool = false,
            needsRestore: Bool = false,
            fallbackUnlocked: Bool = false,
            firstFrame: Bool = true,
            awaitingSwitch: Bool = false
        ) -> Bool {
            PlaybackCurtainWatchdog.isPictureReadyForReveal(
                hasFatalError: fatal,
                isSwitchingSource: switching,
                isResolving: resolving,
                isRestoringFromBackground: restoring,
                needsForegroundVideoRestore: needsRestore,
                firstFrameFallbackUnlocked: fallbackUnlocked,
                hasFirstFrameReadyForDisplay: firstFrame,
                isAwaitingDisplaySwitch: awaitingSwitch
            )
        }

        XCTAssertFalse(reveal(resolving: true, fallbackUnlocked: true))
        XCTAssertFalse(reveal(restoring: true, fallbackUnlocked: true))
        XCTAssertFalse(reveal(needsRestore: true, fallbackUnlocked: true))
        XCTAssertFalse(reveal(fatal: true, switching: true, fallbackUnlocked: true))
        XCTAssertFalse(reveal(firstFrame: true, awaitingSwitch: true))
        XCTAssertFalse(reveal(firstFrame: false, awaitingSwitch: false))
        XCTAssertTrue(reveal(firstFrame: true, awaitingSwitch: false))
        XCTAssertTrue(reveal(fallbackUnlocked: true, firstFrame: true, awaitingSwitch: true))
        XCTAssertTrue(reveal(switching: true, resolving: true, firstFrame: false, awaitingSwitch: true))
    }

    func testCatalogShelfIndexerPrioritizesPhoneHandoffAndSuppressesDuplicateShelves() {
        let phoneCard = TvMediaCard(
            itemId: "movie:1",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 1),
            title: "Blade Runner 2049",
            year: 2017,
            imdbRating: 8.1,
            origin: "phone",
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        )
        let tonightCard = TvMediaCard(
            itemId: "series:2",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 2),
            title: "Severance",
            year: 2022,
            imdbRating: 8.7,
            origin: "tonight",
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        )
        let regularCard = TvMediaCard(
            itemId: "movie:3",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 3),
            title: "Nosferatu",
            year: 2024,
            imdbRating: 7.6,
            availability: TvAvailabilityInfo(state: "stream", tier: "vfs")
        )

        let payload = TvHomeResponse(
            ok: true,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            tonight: TvTonightPayload(preparedFromPhone: phoneCard),
            rows: [
                TvShelfRow(
                    rowId: "medialogg-watchlist",
                    title: "Huskeliste",
                    rowStyle: "poster",
                    sourceKind: "watchlist",
                    listMode: nil,
                    hasMore: false,
                    nextPath: nil,
                    items: [regularCard]
                ),
                TvShelfRow(
                    rowId: "new-4k",
                    title: "Nye filmer i 4K",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    listMode: nil,
                    hasMore: true,
                    nextPath: nil,
                    items: [regularCard, phoneCard]
                ),
                TvShelfRow(
                    rowId: "medialogg-continue",
                    title: "Fortsett å se",
                    rowStyle: "continue_backdrop",
                    sourceKind: "system_continue",
                    listMode: "smart",
                    hasMore: false,
                    nextPath: nil,
                    items: [regularCard, tonightCard]
                ),
            ]
        )

        let visible = CatalogShelfIndexer.prepareVisibleRows(from: payload)
        XCTAssertEqual(visible.map(\.rowId), ["medialogg-continue", "new-4k"])
        XCTAssertEqual(visible[0].title, "Fortsett")
        XCTAssertEqual(visible[0].items.map(\.itemId), ["movie:1", "series:2", "movie:3"])

        let upcomingRow = TvShelfRow(
            rowId: "upcoming-episodes",
            title: "Kommende episoder",
            rowStyle: "upcoming_backdrop",
            sourceKind: "system_upcoming",
            listMode: "smart",
            hasMore: false,
            nextPath: nil,
            items: [regularCard]
        )
        let filteredUpcoming = CatalogShelfIndexer.filterVisibleRows([upcomingRow])
        XCTAssertEqual(filteredUpcoming.map(\.rowId), ["upcoming-episodes"])

        let orderedWithoutHandoff = CatalogShelfIndexer.prepareVisibleRows(
            from: TvHomeResponse(
                ok: true,
                roomName: "Stua",
                hardwareProfile: "hdr10-512",
                rows: [upcomingRow, payload.rows[2]]
            )
        )
        XCTAssertEqual(orderedWithoutHandoff.map(\.rowId), ["upcoming-episodes", "medialogg-continue"])
        XCTAssertEqual(orderedWithoutHandoff[1].title, "Fortsett")
    }

    func testLunaCoreClientHTTPTransportConditionalHomeAndSocketHelpers() async throws {
        let host = "linux-core-test.invalid"
        defer { CoreURLProtocolMock.unregister(host: host) }

        CoreURLProtocolMock.register(host: host) { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "X-Device-Id"), "luna-linux-ci")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer token-xyz")
            let url = try XCTUnwrap(req.url)
            if req.value(forHTTPHeaderField: "If-None-Match") == "\"etag-v1\"" {
                let resp = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 304, httpVersion: "HTTP/1.1", headerFields: nil)
                )
                return (resp, Data())
            }
            let body = #"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#
            let resp = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["ETag": "\"etag-v1\""]
                )
            )
            return (resp, Data(body.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CoreURLProtocolMock.self]
        let session = URLSession(configuration: config)
        let baseURL = try XCTUnwrap(URL(string: "https://\(host):8920"))
        let client = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-linux-ci",
            deviceToken: "token-xyz",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true,
            appVersion: "2.11.0",
            osVersion: "Linux-CI",
            session: session
        )

        let first = try await client.fetchHomeConditional(ifNoneMatch: nil)
        guard case .updated(let payload, let etag, _) = first else {
            return XCTFail("Expected updated 200 payload")
        }
        XCTAssertEqual(payload.roomName, "Stua")
        XCTAssertEqual(etag, "\"etag-v1\"")

        let cached = try await client.fetchHomeConditional(ifNoneMatch: "\"etag-v1\"")
        guard case .notModified = cached else {
            return XCTFail("Expected 304 Not Modified")
        }

        let wsURL = PlaybackResolveSocket.makeWebSocketURL(
            baseURL: baseURL,
            wsPath: "/api/tv/v1/ws/playback/res-42"
        )
        XCTAssertEqual(wsURL?.absoluteString, "wss://\(host):8920/api/tv/v1/ws/playback/res-42")
        let evt = try PlaybackResolveSocket.decodeEventData(
            Data(#"{"type":"resolve.ready","resolveId":"res-42","percent":100}"#.utf8)
        )
        XCTAssertTrue(PlaybackResolveSocket.isTerminalEvent(evt))
        XCTAssertTrue(LanURLSessionDelegate.shouldTrustServer(host: "lunacore.local", trustedHost: nil, allowSelfSignedTLS: true))
        XCTAssertFalse(LanURLSessionDelegate.shouldTrustServer(host: "lunacore.local", trustedHost: nil, allowSelfSignedTLS: false))
    }

    func testSmartTrackRulesChaptersCopyAndSideloadSafeStorageOnLinux() {
        let engAudio = SmartTrackDescriptor(id: 1, name: "TrueHD 7.1 Atmos", codec: "truehd", language: "eng")
        let subs = [
            SmartTrackDescriptor(id: 10, name: "Norsk (SDH)", codec: "srt", language: "nob", isHearingImpaired: true),
            SmartTrackDescriptor(id: 11, name: "Norsk Bokmål", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 12, name: "English", codec: "pgs", language: "eng"),
        ]
        XCTAssertEqual(SmartTrackRuleEngine.evaluate(activeAudio: engAudio, subtitleTracks: subs), .selectTrack(11))

        let merged = PlaybackChapter.mergeRaw(
            probeChapters: [
                TvProbeChapter(index: 0, idString: "intro", title: "Opening Credits", startSeconds: 45, endSeconds: 115, kind: "intro")
            ],
            engineChapters: [
                RawEngineChapter(id: 0, name: "Prologue", startSeconds: 0, durationSeconds: 45),
                RawEngineChapter(id: 1, name: "Main Feature", startSeconds: 115, durationSeconds: 1200),
            ],
            mediaDuration: 1500
        )
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[1].kind, .intro)

        XCTAssertEqual(LunaCopy.plural(1, "episode", "episoder"), "1 episode")
        XCTAssertEqual(LunaCopy.plural(4, "episode", "episoder"), "4 episoder")
        XCTAssertEqual(LunaCopy.formatGigabytes(64.25, decimals: 1), "64,2 GB")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 2, episode: 4), "S02E04")
        XCTAssertEqual(LunaCopy.localizedSeasonTitle("Season 28", seasonNumber: 28), "Sesong 28")
        XCTAssertEqual(LunaCopy.localizedSeasonTitle("Specials", seasonNumber: 0), "Spesialer")
        XCTAssertEqual(LunaCopy.localizedLanguageName("swe"), "Svensk")
        XCTAssertEqual(LunaCopy.localizedLanguageName("nob"), "Norsk")
        XCTAssertEqual(LunaCopy.localizedLanguageName("ara"), "Arabisk")

        let cand = TvCandidateInfo(
            candidateId: "cand-playweb",
            displayHeadline: "1080p · WEB-DL · DDP Atmos 5.1 · playWEB",
            releaseTitle: "Show.2026.1080p.WEB-DL.DDP5.1.Atmos-playWEB",
            source: "infinidysk",
            tier: "vfs",
            resolution: "1080p",
            videoRangeType: "SDR",
            dvProfile: nil,
            dvEnhancementLayer: nil,
            audioCodec: "DDP Atmos",
            sizeBytes: 5_476_083_302,
            tvScore: 980,
            isActive: true,
            explanationChips: nil,
            releaseGroup: "playWEB",
            isNorwegian: true
        )
        let title = cand.quickRowTitle(roomName: "Stua", isRecommended: true)
        XCTAssertEqual(title, "Anbefalt for Stua · 1080p Dolby Atmos")
        XCTAssertFalse(title.contains("playWEB"))
        XCTAssertFalse(title.contains("NORVINE"))
        let sub = cand.quickRowMetadata(activeLabel: "Spilles nå")
        XCTAssertEqual(sub, "Strømmes ved start · 5,1 GB · Spilles nå")
        XCTAssertFalse(sub.contains("InfiniDysk"))

        let suite = UserDefaults(suiteName: "luna.v1.linux.tests.\(UUID().uuidString)")!
        let devId = SideloadSafeStorage.ensurePersistentDeviceID(defaults: suite)
        XCTAssertTrue(devId.hasPrefix("luna-"))
        SideloadSafeStorage.saveDeviceToken("tok-sideload-safe", defaults: suite)
        XCTAssertEqual(SideloadSafeStorage.loadDeviceToken(defaults: suite), "tok-sideload-safe")
        SideloadSafeStorage.deleteDeviceToken(defaults: suite)
        XCTAssertNil(SideloadSafeStorage.loadDeviceToken(defaults: suite))
    }

    func testPreviewLaunchConfigurationParsesScreensAndFocusDirections() {
        XCTAssertNil(PreviewLaunchConfiguration.parse(arguments: ["Luna"]))
        let homeCfg = PreviewLaunchConfiguration.parse(
            arguments: ["Luna", "--preview-screen", "home", "--preview-focus", "right"]
        )
        XCTAssertEqual(homeCfg?.screen, .home)
        XCTAssertEqual(homeCfg?.focusDirection, .right)

        let playerCfg = PreviewLaunchConfiguration.parse(
            arguments: ["Luna", "--preview-screen=player", "--preview-focus=down"]
        )
        XCTAssertEqual(playerCfg?.screen, .playerSubtitles)
        XCTAssertEqual(playerCfg?.focusDirection, .down)

        let subtitlesCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-subtitles"])
        XCTAssertEqual(subtitlesCfg?.screen, .playerSubtitles)

        let errorCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-error"])
        XCTAssertEqual(errorCfg?.screen, .playerError)
        XCTAssertEqual(errorCfg?.screen.isPlayerScreen, true)

        let posterCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "home-poster"])
        XCTAssertEqual(posterCfg?.screen, .homePoster)

        let libCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "library"])
        XCTAssertEqual(libCfg?.screen, .library)

        let searchCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "search"])
        XCTAssertEqual(searchCfg?.screen, .search)
        XCTAssertEqual(searchCfg?.screen.isPlayerScreen, false)

        let settingsCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "settings"])
        XCTAssertEqual(settingsCfg?.screen, .settings)

        let audioCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-audio"])
        XCTAssertEqual(audioCfg?.screen, .playerAudio)
        XCTAssertEqual(audioCfg?.screen.isPlayerScreen, true)

        let sourceCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-source"])
        XCTAssertEqual(sourceCfg?.screen, .playerSource)

        let pictureCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-picture"])
        XCTAssertEqual(pictureCfg?.screen, .playerPicture)
        XCTAssertEqual(pictureCfg?.screen.isPlayerScreen, true)

        let chaptersCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-chapters"])
        XCTAssertEqual(chaptersCfg?.screen, .playerChapters)
        XCTAssertEqual(chaptersCfg?.screen.isPlayerScreen, true)

        let detailCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "details"])
        XCTAssertEqual(detailCfg?.screen, .details)
        XCTAssertNil(detailCfg?.focusDirection)
    }

    func testRemoteScrubMathDeviceCapabilitiesAndLibraryModels() throws {
        // 1. RemoteScrubMath v2.9.0: paused-only activation, 20 pt breakaway, 3-zone adaptive scaling & ring hold
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 80,
                dy: 0,
                isPlaying: true,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )
        XCTAssertTrue(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 20,
                dy: 0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 40,
                dy: 45,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )
        XCTAssertGreaterThan(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 3.8), 2500)

        // 2. DeviceHardwareCapabilities RAM tier rounding
        XCTAssertEqual(DeviceHardwareCapabilities.roundedGigabytes(for: 4 * 1_073_741_824), 4)
        XCTAssertEqual(DeviceHardwareCapabilities.roundedGigabytes(for: 8 * 1_073_741_824), 8)
        XCTAssertFalse(DeviceHardwareCapabilities.isHighMemory(physicalMemoryBytes: 4 * 1_073_741_824))
        XCTAssertTrue(DeviceHardwareCapabilities.isHighMemory(physicalMemoryBytes: 8 * 1_073_741_824))

        // 3. TvLibraryCounts localMovies / localSeries + TvCandidateInfo extended fields
        let countsJson = #"{"localTotal":396,"localMovies":312,"localSeries":84,"favorites":10,"watchlist":24,"nvme":350,"archive":46,"vfs":0,"customLists":2}"#
        let counts = try JSONDecoder().decode(TvLibraryCounts.self, from: Data(countsJson.utf8))
        XCTAssertEqual(counts.localMovies, 312)
        XCTAssertEqual(counts.localSeries, 84)

        let cand = TvCandidateInfo(
            candidateId: "local:sqlite:42",
            displayHeadline: "4K HDR10+ · TrueHD Atmos",
            releaseTitle: "Film.2026.2160p.UHD.BluRay.Remux",
            source: "ssd",
            tier: "nvme",
            resolution: "2160p",
            videoRangeType: "HDR10Plus",
            dvProfile: nil,
            dvEnhancementLayer: nil,
            audioCodec: "TrueHD Atmos",
            sizeBytes: 64_424_509_440,
            tvScore: 1500,
            isActive: false,
            explanationChips: nil,
            releaseGroup: nil,
            isNorwegian: false,
            videoCodec: "hevc",
            sourceQuality: "Bluray-2160p",
            channels: "7.1"
        )
        XCTAssertEqual(cand.quickRowMetadata(activeLabel: nil), "På NVMe · HEVC · Bluray-2160p · 60,0 GB")
        XCTAssertEqual(cand.quickRowTitle(roomName: "Stua", isRecommended: true), "Anbefalt for Stua · 4K HDR10+ TrueHD Atmos")

        // Numeric channel regression from live SQLite probe
        let numericChannelJson = #"""
        {
          "candidateId": "cand-num-ch",
          "displayHeadline": "1080p WEB-DL",
          "releaseTitle": "Movie.2026.1080p.WEB-DL",
          "source": "nvme",
          "tier": "nvme",
          "resolution": "1080p",
          "audioCodec": "aac",
          "channels": 2,
          "sizeBytes": 2147483648.0,
          "tvScore": 850.0,
          "isNorwegian": 0
        }
        """#
        let numCand = try JSONDecoder().decode(TvCandidateInfo.self, from: Data(numericChannelJson.utf8))
        XCTAssertEqual(numCand.channels, "2.0")
        XCTAssertEqual(numCand.sizeBytes, 2_147_483_648)
        XCTAssertEqual(numCand.tvScore, 850)
        XCTAssertEqual(numCand.isNorwegian, false)

        // 4. Transport excludes legacy split-brain X-Room-Name / X-Hardware-Profile headers
        let client = LunaCoreClient(
            baseURL: URL(string: "http://127.0.0.1:8090")!,
            deviceID: "luna-test",
            deviceToken: "tok-1",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )
        let headers = client.streamHTTPHeaders()
        XCTAssertNil(headers["X-Room-Name"])
        XCTAssertNil(headers["X-Hardware-Profile"])
        XCTAssertNotNil(headers["X-Supports-HW-AV1"])
        XCTAssertNotNil(headers["X-Physical-Memory-GB"])

        // 5. @2x / 4K artwork URL upgrading without downgrading larger URLs
        let posterURL = client.resolveArtworkURL("https://image.tmdb.org/t/p/w500/abc.jpg", target: .poster2x)
        XCTAssertEqual(posterURL?.absoluteString, "https://image.tmdb.org/t/p/w780/abc.jpg")
        let heroURL = client.resolveArtworkURL("https://image.tmdb.org/t/p/w500/abc.jpg", target: .hero4K)
        XCTAssertEqual(heroURL?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
        let noDowngrade = client.resolveArtworkURL("https://image.tmdb.org/t/p/w1280/abc.jpg", target: .poster2x)
        XCTAssertEqual(noDowngrade?.absoluteString, "https://image.tmdb.org/t/p/w1280/abc.jpg")
        let relUpgraded = client.resolveArtworkURL("/api/tv/v1/artwork?src=a&w=320", target: .landscape2x)
        XCTAssertEqual(relUpgraded?.absoluteString, "http://127.0.0.1:8090/api/tv/v1/artwork?src=a&w=1280")
        let relWidthHero = client.resolveArtworkURL("/api/tv/v1/artwork?src=a&width=780", target: .hero4K)
        XCTAssertEqual(relWidthHero?.absoluteString, "http://127.0.0.1:8090/api/tv/v1/artwork?src=a&width=3840")
        let preserved = client.resolveArtworkURL("/api/tv/v1/artwork?src=a&w=320", target: .preserve)
        XCTAssertEqual(preserved?.absoluteString, "http://127.0.0.1:8090/api/tv/v1/artwork?src=a&w=320")
    }

    func testSteg42SameOriginEasynewsArtworkUpgradeAndTokenCancelContract() async throws {
        // 1. :8090 <-> :8920 dual-listener same-origin recognition + foreign-origin token stripping
        let tlsClient = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "https://lunacore.local:8920")),
            deviceID: "luna-tv-stua",
            deviceToken: "tok-same-origin",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )
        let lanHttpStream = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v1/stream/s1/tok/video.mkv"))
        let lanHttpsImg = try XCTUnwrap(URL(string: "https://lunacore.local:8920/api/tv/v1/img/poster/tmdb/p.jpg"))
        let roguePort = try XCTUnwrap(URL(string: "http://lunacore.local:9999/api/tv/v1/stream/s1/tok/video.mkv"))
        let foreignHost = try XCTUnwrap(URL(string: "https://cdn.example.net:8920/video.mkv"))

        XCTAssertTrue(tlsClient.isSameOrigin(lanHttpStream))
        XCTAssertTrue(tlsClient.isSameOrigin(lanHttpsImg))
        XCTAssertFalse(tlsClient.isSameOrigin(roguePort))
        XCTAssertFalse(tlsClient.isSameOrigin(foreignHost))

        let lanStreamHeaders = tlsClient.streamHTTPHeaders(for: lanHttpStream)
        XCTAssertEqual(lanStreamHeaders["Authorization"], "Bearer tok-same-origin")
        XCTAssertEqual(lanStreamHeaders["X-Device-Id"], "luna-tv-stua")

        let foreignHeaders = tlsClient.streamHTTPHeaders(for: foreignHost)
        XCTAssertNil(foreignHeaders["Authorization"])
        XCTAssertNil(foreignHeaders["X-Device-Id"])

        // 2. Easynews HTTPS candidate badge & /api/tv/v1/img/{card,still}/ -> /backdrop/ hero4K upgrade
        let easynewsCand = try JSONDecoder().decode(
            TvCandidateInfo.self,
            from: Data(#"{"candidateId":"easy-1","displayHeadline":"4K WEB-DL","releaseTitle":"Example.2026.2160p","source":"easynews","tier":"ssd"}"#.utf8)
        )
        XCTAssertEqual(easynewsCand.sourceBadgeLabel, "Arkiv-strøm (HTTPS)")

        XCTAssertEqual(
            tlsClient.resolveArtworkURL("/api/tv/v1/img/card/tmdb/hero.jpg", target: .hero4K)?.absoluteString,
            "https://lunacore.local:8920/api/tv/v1/img/backdrop/tmdb/hero.jpg"
        )
        XCTAssertEqual(
            tlsClient.resolveArtworkURL("/api/tv/v1/img/still/tmdb/ep.jpg", target: .hero4K)?.absoluteString,
            "https://lunacore.local:8920/api/tv/v1/img/backdrop/tmdb/ep.jpg"
        )
        XCTAssertEqual(
            tlsClient.resolveArtworkURL("/api/tv/v1/img/card/tmdb/hero.jpg", target: .landscape2x)?.absoluteString,
            "https://lunacore.local:8920/api/tv/v1/img/card/tmdb/hero.jpg"
        )

        // 3. Stua Sonos 5.1.2 copy & TvPairedDeviceInfo.roomUnassigned decoding
        XCTAssertEqual(
            LunaCopy.roomEquipmentLabel(hardwareProfile: "hdr10-512"),
            "Samsung Frame Pro · HDR10+ · Sonos 5.1.2"
        )
        XCTAssertEqual(
            LunaCopy.roomEquipmentLabel(hardwareProfile: "dv-fel-714"),
            "LG OLED · Dolby Vision · Sonos 7.1.4"
        )
        let unassignedDevice = try JSONDecoder().decode(
            TvPairedDeviceInfo.self,
            from: Data(#"{"deviceId":"d1","deviceName":"TV","roomName":"Stua","roomUnassigned":true,"hardwareProfile":"hdr10-512"}"#.utf8)
        )
        XCTAssertEqual(unassignedDevice.roomUnassigned, true)

        // 4. prepareToken wire payload, cancelInflightPlayback wire payload, removeFromList removed:false, and shared GET coalescing
        let host = "steg42-linux.invalid"
        defer { CoreURLProtocolMock.unregister(host: host) }
        let capturedBodies = Mutex<[String: String]>([:])
        let homeGetCount = Mutex<Int>(0)

        @Sendable func readBody(_ req: URLRequest) -> String {
            if let data = req.httpBody, let str = String(data: data, encoding: .utf8) {
                return str
            }
            guard let stream = req.httpBodyStream else { return "" }
            stream.open()
            defer { stream.close() }
            var out = Data()
            var buf = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                out.append(buf, count: n)
            }
            return String(data: out, encoding: .utf8) ?? ""
        }

        CoreURLProtocolMock.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let bodyStr = readBody(req)
            capturedBodies.withLock { $0[url.path] = bodyStr }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            switch url.path {
            case "/api/tv/v1/home":
                homeGetCount.withLock { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.03)
                return (resp, Data(#"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#.utf8))
            case "/api/tv/v1/playback/prepare":
                return (resp, Data(#"{"ok":true,"status":"prepared","prepareToken":"tvs-prep-1"}"#.utf8))
            case "/api/tv/v1/rows/custom:test/remove":
                let removed = bodyStr.contains("550")
                return (resp, Data(#"{"ok":true,"removed":\#(removed)}"#.utf8))
            default:
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let baseURL = try XCTUnwrap(URL(string: "https://\(host):8920"))
        let prodClient1 = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-prod",
            deviceToken: "tok-xyz",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )
        let prodClient2 = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-prod",
            deviceToken: "tok-xyz",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )
        XCTAssertTrue(
            prodClient1.inflightGETRequests === prodClient2.inflightGETRequests,
            "Production LunaCoreClient instances must share LunaCoreSessionPool.shared.inflightGETRequests"
        )

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CoreURLProtocolMock.self]
        let session = URLSession(configuration: config)
        let clientA = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-ci-a",
            deviceToken: "tok-xyz",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true,
            session: session
        )

        async let h1 = clientA.fetchHomeConditional(ifNoneMatch: nil)
        async let h2 = clientA.fetchHomeConditional(ifNoneMatch: nil)
        _ = try await (h1, h2)
        XCTAssertEqual(homeGetCount.withLock { $0 }, 1, "Concurrent fetchHomeConditional GETs must coalesce")

        _ = try await clientA.preparePlayback(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            prepareToken: "prep-uuid-42"
        )
        try await clientA.cancelInflightPlayback(
            sessionId: nil,
            resolveId: "res-77",
            itemId: "movie:tmdb:550",
            prepareToken: "prep-uuid-42"
        )
        let prepBody = capturedBodies.withLock { $0["/api/tv/v1/playback/prepare"] ?? "" }
        let cancelBody = capturedBodies.withLock { $0["/api/tv/v1/playback/heartbeat"] ?? "" }
        XCTAssertTrue(prepBody.contains("\"prepareToken\":\"prep-uuid-42\""))
        XCTAssertTrue(cancelBody.contains("\"cancelInflight\":true"))
        XCTAssertTrue(cancelBody.contains("\"resolveId\":\"res-77\""))
        XCTAssertTrue(cancelBody.contains("\"prepareToken\":\"prep-uuid-42\""))

        let didRemove550 = try await clientA.removeFromList(
            rowId: "custom:test",
            mediaType: "movie",
            itemId: "movie:tmdb:550",
            ids: TvMediaIds(tmdb: 550),
            title: "Fight Club"
        )
        let didRemove999 = try await clientA.removeFromList(
            rowId: "custom:test",
            mediaType: "movie",
            itemId: "movie:tmdb:999",
            ids: TvMediaIds(tmdb: 999),
            title: "Other"
        )
        XCTAssertTrue(didRemove550)
        XCTAssertFalse(didRemove999)
    }
}
