import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

// MARK: - Linux-Safe PlaybackEngine & IOReader Test Doubles

actor MockPlaybackEngine: PlaybackEngine {
    var state: CorePlaybackState = .idle
    var phase: CorePlaybackPhase = .idle
    var currentTime: Double = 0
    var duration: Double = 7200
    var bufferedPosition: Double = 0
    var hasFirstFrameReadyForDisplay: Bool = false
    var isAwaitingDisplaySwitch: Bool = false
    var needsForegroundVideoRestore: Bool = false

    private(set) var events: [String] = []
    private(set) var loadedURLs: [URL] = []
    private(set) var lastHeaders: [String: String] = [:]
    var shouldFailNextLoad: Bool = false

    func configureDisplayState(firstFrame: Bool, awaitingSwitch: Bool) {
        hasFirstFrameReadyForDisplay = firstFrame
        isAwaitingDisplaySwitch = awaitingSwitch
    }

    func configurePhase(_ nextPhase: CorePlaybackPhase, atTime seconds: Double? = nil) {
        phase = nextPhase
        if let seconds {
            currentTime = seconds
        }
    }

    func setFailNextLoad(_ fail: Bool) {
        shouldFailNextLoad = fail
    }

    func load(
        url: URL,
        httpHeaders: [String: String],
        startPosition: Double?,
        autoplay: Bool
    ) async throws {
        if shouldFailNextLoad {
            shouldFailNextLoad = false
            state = .failed
            phase = .error("Simulated transport failure")
            throw LunaCoreError.serverMessage(502, "Simulated transport failure")
        }
        loadedURLs.append(url)
        lastHeaders = httpHeaders
        currentTime = startPosition ?? 0
        bufferedPosition = currentTime + 24
        state = autoplay ? .playing : .paused
        phase = autoplay ? .playing : .paused
        events.append("load(\(url.path),pos=\(Int(currentTime)),auto=\(autoplay))")
    }

    func prepareForItemReplacement() async {
        events.append("prepareForItemReplacement")
    }

    func play() async {
        state = .playing
        phase = .playing
        events.append("play")
    }

    func pause() async {
        state = .paused
        phase = .paused
        events.append("pause")
    }

    func togglePlayPause() async {
        if state == .playing {
            await pause()
        } else {
            await play()
        }
    }

    func seek(to seconds: Double, exact: Bool) async {
        currentTime = seconds
        events.append("seek(\(Int(seconds)),exact=\(exact))")
    }

    func stop(resetDisplayCriteria: Bool) async {
        state = .idle
        phase = .idle
        hasFirstFrameReadyForDisplay = false
        isAwaitingDisplaySwitch = false
        events.append("stop(reset=\(resetDisplayCriteria))")
    }
}

actor MockByteRangeIOReader: IOReader {
    private var prewarmed: Set<URL> = []
    private(set) var prewarmCallCount: Int = 0
    private(set) var lastBudget: Int = 0

    func isPrewarmed(url: URL) async -> Bool {
        prewarmed.contains(url)
    }

    @discardableResult
    func prewarm(url: URL, httpHeaders: [String: String], byteBudget: Int) async throws -> Int {
        _ = httpHeaders
        prewarmed.insert(url)
        prewarmCallCount += 1
        lastBudget = byteBudget
        return byteBudget
    }

    func readRange(url: URL, httpHeaders: [String: String], offset: Int64, length: Int) async throws -> Data {
        _ = url
        _ = httpHeaders
        _ = offset
        return Data(repeating: 0x42, count: max(0, length))
    }

    func discardPrewarmedSources() async {
        prewarmed.removeAll()
    }
}

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
                dualLayerRoute: "softwareHost",
                foldsDolbyVisionFEL: true,
                dolbyVisionHandling: "automatic",
                panelPresentsDolbyVision: false,
                panelIsInHDRMode: false,
                matchContentEnabled: true,
                displayCriteriaOwner: "engine",
                attemptsHDRMasterOnUnprovenPanel: false,
                objectAudioRendering: TvObjectAudioConfig(mode: "render", layout: "7.1.4"),
                audioBridgeMode: "surroundCompat",
                preferredAudioLanguages: ["nob", "eng"],
                preferredSubtitleLanguages: ["nob", "eng"],
                autoPlayNextEpisode: true,
                smartNordicSubtitleRule: true,
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

    func testPlaybackCoordinatorCurtainGateWatchdogAndSeamlessSwitch() async throws {
        let engine = MockPlaybackEngine()
        let reader = MockByteRangeIOReader()
        let coordinator = PlaybackCoordinatorStateMachine(engine: engine, ioReader: reader)
        let baseURL = try XCTUnwrap(URL(string: "https://luna.example.invalid"))
        let headers = ["X-Device-Id": "appletv-test"]

        // 1. Archive tier with canClientPrewarmBytes == false MUST NOT wake HDDs via IOReader
        let archiveSession = makeSampleSession(sessionId: "arch-1", tier: "archive", canPrewarm: false)
        let didPrewarmArchive = try await coordinator.prewarmIfAllowed(
            session: archiveSession,
            canClientPrewarmBytes: false,
            baseURL: baseURL,
            headers: headers
        )
        XCTAssertFalse(didPrewarmArchive)
        let archivePrewarmCalls = await reader.prewarmCallCount
        XCTAssertEqual(archivePrewarmCalls, 0)

        // 2. NVMe tier with canClientPrewarmBytes == true prewarms 8 MiB once and deduplicates
        let nvmeSession = makeSampleSession(sessionId: "nvme-1", tier: "nvme", canPrewarm: true)
        let firstPrewarm = try await coordinator.prewarmIfAllowed(
            session: nvmeSession,
            canClientPrewarmBytes: true,
            baseURL: baseURL,
            headers: headers
        )
        let duplicatePrewarm = try await coordinator.prewarmIfAllowed(
            session: nvmeSession,
            canClientPrewarmBytes: true,
            baseURL: baseURL,
            headers: headers
        )
        XCTAssertTrue(firstPrewarm)
        XCTAssertFalse(duplicatePrewarm)
        let nvmePrewarmCalls = await reader.prewarmCallCount
        let prewarmBudget = await reader.lastBudget
        XCTAssertEqual(nvmePrewarmCalls, 1)
        XCTAssertEqual(prewarmBudget, 8 * 1024 * 1024)

        // 3. Start session while HDMI display switch is in progress -> curtain stays closed
        await engine.configureDisplayState(firstFrame: true, awaitingSwitch: true)
        try await coordinator.startSession(
            nvmeSession,
            baseURL: baseURL,
            headers: headers,
            nowSeconds: 10.0
        )
        let earlyReveal = await coordinator.isPictureReadyForReveal(nowSeconds: 12.0)
        XCTAssertFalse(earlyReveal, "Curtain must hold while HDMI range/frame-rate switch is settling")

        // 4. 5-second watchdog unlocks picture if display-switch callback never arrives
        let watchdogReveal = await coordinator.isPictureReadyForReveal(nowSeconds: 15.1)
        XCTAssertTrue(watchdogReveal, "5-second fallback watchdog must unlock curtain")

        // 5. Seamless source switch calls prepareForItemReplacement() and preserves position
        await engine.seek(to: 945, exact: true)
        await engine.configureDisplayState(firstFrame: true, awaitingSwitch: false)
        let altSession = TvPlaybackSession(
            sessionId: nvmeSession.sessionId,
            streamToken: nvmeSession.streamToken,
            roomName: nvmeSession.roomName,
            hardwareProfile: nvmeSession.hardwareProfile,
            item: nvmeSession.item,
            selectedCandidate: nvmeSession.selectedCandidate,
            stream: TvStreamEndpoint(
                url: "/api/tv/v1/stream/nvme-1/alt.mkv",
                container: "mkv",
                supportsByteRanges: true,
                zeroCopyMode: "206",
                canClientPrewarmBytes: true,
                startPositionSeconds: nil,
                declaredDurationSeconds: 9960
            ),
            tracks: nil,
            chapters: nil,
            aetherConfig: nvmeSession.aetherConfig,
            heartbeatIntervalSeconds: 10,
            nextEpisode: nil
        )
        try await coordinator.switchSource(
            to: altSession,
            baseURL: baseURL,
            headers: headers,
            nowSeconds: 20.0
        )
        let resumedAt = await engine.currentTime
        XCTAssertEqual(resumedAt, 945, accuracy: 0.01)

        // 6. Stall watchdog ignores scrubbing, triggers seek+play recovery after 8s stall
        await engine.configurePhase(.stalled, atTime: 960)
        let scrubCheck = await coordinator.pollStallRecoveryIfNeeded(nowSeconds: 30.0, isScrubbing: true)
        XCTAssertFalse(scrubCheck)
        let armStall = await coordinator.pollStallRecoveryIfNeeded(nowSeconds: 31.0, isScrubbing: false)
        XCTAssertFalse(armStall)
        let recoverStall = await coordinator.pollStallRecoveryIfNeeded(nowSeconds: 39.2, isScrubbing: false)
        XCTAssertTrue(recoverStall)

        // 7. Teardown resets display criteria cleanly
        await coordinator.teardown(resetDisplayCriteria: true)
        let finalState = await engine.state
        let events = await engine.events
        XCTAssertEqual(finalState, .idle)
        XCTAssertTrue(events.contains("prepareForItemReplacement"))
        XCTAssertTrue(events.contains("stop(reset=true)"))
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
                    items: [regularCard],
                    genres: nil
                ),
                TvShelfRow(
                    rowId: "new-4k",
                    title: "Nye filmer i 4K",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    listMode: nil,
                    hasMore: true,
                    nextPath: nil,
                    items: [regularCard, phoneCard],
                    genres: nil
                ),
                TvShelfRow(
                    rowId: "medialogg-continue",
                    title: "Fortsett å se",
                    rowStyle: "continue_backdrop",
                    sourceKind: "system_continue",
                    listMode: "smart",
                    hasMore: false,
                    nextPath: nil,
                    items: [regularCard, tonightCard],
                    genres: nil
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
            listMode: nil,
            hasMore: false,
            nextPath: nil,
            items: [regularCard],
            genres: nil
        )
        let filteredUpcoming = CatalogShelfIndexer.filterVisibleRows([upcomingRow])
        XCTAssertTrue(filteredUpcoming.isEmpty)

        let tiers = CatalogShelfIndexer.indexByTier([phoneCard, tonightCard, regularCard, phoneCard])
        XCTAssertEqual(tiers.nvme.map(\.itemId), ["movie:1"])
        XCTAssertEqual(tiers.archive.map(\.itemId), ["series:2"])
        XCTAssertEqual(tiers.stream.map(\.itemId), ["movie:3"])

        let filtered = CatalogShelfIndexer.filterAndSortCards(
            [phoneCard, tonightCard, regularCard],
            localOnly: true,
            sort: "top_rated"
        )
        XCTAssertEqual(filtered.map(\.itemId), ["series:2", "movie:1"])
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
            appVersion: "2.9.0",
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
        let title = cand.humanDrawerTitle(roomName: "Stua", isRecommended: true, isActive: true)
        XCTAssertEqual(title, "Anbefalt for Stua · 1080p Dolby Atmos ✓")
        XCTAssertFalse(title.contains("playWEB"))
        XCTAssertFalse(title.contains("NORVINE"))
        let sub = cand.humanDrawerSubtitle(isActive: true)
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
        XCTAssertTrue(cand.capabilityBadges.contains("HEVC"))
        XCTAssertEqual(cand.humanDrawerSubtitle(isActive: false), "På NVMe · HEVC · Bluray-2160p · 60,0 GB")
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
}
