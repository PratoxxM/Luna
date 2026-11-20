import Foundation
import XCTest
@testable import Luna

@MainActor
private final class MockDetailSessionContext: MediaDetailSessionContext {
    var roomName: String = "Kjellerstua"
    var effectiveHardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var activePlaybackTarget: PlaybackLaunchRequest? = nil
    var keepDisplayModeInMenuAfterPlayback: Bool = false
    var client: LunaCoreClient?
    var mutateCalls: Int = 0
    var unpairCalls: Int = 0

    func makeClient() -> LunaCoreClient? { client }
    func notifyContentMutated() {
        homeRefreshNonce &+= 1
        mutateCalls += 1
    }
    func unpairDevice() {
        unpairCalls += 1
    }
}

final class MediaDetailViewModelTests: XCTestCase {
    @MainActor
    func testSeriesLoadSeasonSwitchOptimisticMutationsAndPlaybackLaunch() async throws {
        let host = "detail-vm-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let seriesDetailJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "series:tmdb:95396",
            "mediaType": "series",
            "ids": { "tmdb": 95396, "tvdb": 371980 },
            "title": "Severance",
            "year": 2022,
            "inWatchlist": false,
            "watched": false,
            "monitored": false,
            "selectedSeason": 1,
            "nextUp": { "season": 1, "episode": 2 },
            "seasons": [
              { "seasonNumber": 1, "name": "Sesong 1", "episodeCount": 2 },
              { "seasonNumber": 2, "name": "Sesong 2", "episodeCount": 1 }
            ],
            "episodes": [
              {
                "itemId": "episode:tmdb:95396:s1:e1",
                "seasonNumber": 1,
                "episodeNumber": 1,
                "title": "Good News About Hell",
                "watched": true
              },
              {
                "itemId": "episode:tmdb:95396:s1:e2",
                "seasonNumber": 1,
                "episodeNumber": 2,
                "title": "Half Loop",
                "watched": false,
                "progress": { "positionSeconds": 640, "durationSeconds": 2800, "percent": 22.8, "watched": false }
              }
            ]
          }
        }
        """#

        let season2JSON = #"""
        {
          "ok": true,
          "tmdbId": 95396,
          "seasonNumber": 2,
          "title": "Sesong 2",
          "episodes": [
            {
              "itemId": "episode:tmdb:95396:s2:e1",
              "seasonNumber": 2,
              "episodeNumber": 1,
              "title": "Hello, Ms. Cobel",
              "watched": false
            }
          ]
        }
        """#

        let monitoredState = TestLockedBox(false)

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/api/tv/v1/items/series/series:tmdb:95396":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let payload = monitoredState.withLock { $0 }
                    ? seriesDetailJSON
                        .replacingOccurrences(of: "\"monitored\": false", with: "\"monitored\": true,\n            \"monitorMode\": \"unwatched\"")
                    : seriesDetailJSON
                return (resp, Data(payload.utf8))
            case "/api/tv/v1/items/series/95396/seasons/2":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(season2JSON.utf8))
            case "/api/tv/v1/watchlist":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"error":"Database opptatt"}"#.utf8))
            case "/api/tv/v1/monitor":
                monitoredState.withLock { $0 = true }
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true,"monitored":true,"monitorMode":"unwatched"}"#.utf8))
            case "/api/tv/v1/playback/prepare":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true,"status":"ready","prepareToken":"prep-tok-1"}"#.utf8))
            default:
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)

        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)

        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.detail?.title, "Severance")
        XCTAssertEqual(vm.selectedSeasonNumber, 1)
        XCTAssertEqual(vm.episodes.count, 2)

        let detail = try XCTUnwrap(vm.detail)
        XCTAssertEqual(vm.primaryPlayLabel(detail), "Spill S1 E2")
        XCTAssertEqual(vm.heroPrimaryPlayTitle(detail), "Spill S1 E2")
        XCTAssertEqual(vm.watchedButtonTitle(detail), "Sett S1 E2")

        let target = vm.primaryTargetInfo(detail)
        XCTAssertEqual(target.itemId, "episode:tmdb:95396:s1:e2")
        XCTAssertEqual(target.title, "Half Loop")
        XCTAssertEqual(target.startPos ?? -1, 640, accuracy: 0.1)

        // Failed watchlist mutation rolls back optimistic toggle and shows banner
        await vm.toggleWatchlist()
        XCTAssertEqual(vm.detail?.inWatchlist, false)
        XCTAssertTrue(vm.mutationErrorBanner?.contains("Database opptatt") == true)

        // Successful monitor toggle updates state and notifies content mutation
        await vm.toggleMonitor()
        XCTAssertEqual(vm.detail?.isMonitoredFlag, true)
        XCTAssertEqual(vm.detail?.monitorMode, "unwatched")
        XCTAssertEqual(context.mutateCalls, 1)

        // Season switch updates selectedSeasonNumber and fetches season 2 episodes
        await vm.selectSeason(2)
        XCTAssertEqual(vm.selectedSeasonNumber, 2)
        XCTAssertEqual(vm.episodes.count, 1)
        XCTAssertEqual(vm.episodes.first?.title, "Hello, Ms. Cobel")

        // Launch episode playback sets activePlaybackTarget
        let ep2 = try XCTUnwrap(vm.episodes.first)
        vm.playEpisode(ep2)
        XCTAssertEqual(context.activePlaybackTarget?.itemId, "episode:tmdb:95396:s2:e1")
        XCTAssertEqual(context.activePlaybackTarget?.title, "Hello, Ms. Cobel")
        XCTAssertEqual(context.activePlaybackTarget?.seriesTitle, "Severance")

        // Delete target & cleanup
        vm.requestDeleteSeason(2)
        XCTAssertEqual(vm.pendingDeleteTarget?.scope, .season)
        XCTAssertEqual(vm.pendingDeleteTarget?.season, 2)
        let shouldDismiss = await vm.handleDeleted(target: try XCTUnwrap(vm.pendingDeleteTarget))
        XCTAssertFalse(shouldDismiss)

        vm.requestDeleteTitle()
        let wholeTitleDismiss = await vm.handleDeleted(target: try XCTUnwrap(vm.pendingDeleteTarget))
        XCTAssertTrue(wholeTitleDismiss)

        vm.handleDisappear()
    }

    @MainActor
    func testUnauthorizedDetailFetchUnpairsDevice() async throws {
        let host = "detail-unauth-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (resp, Data())
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)

        let vm = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:550", initialTitle: "Fight Club")
        await vm.handleTaskAppearance(scopeKey: "movie#movie:tmdb:550#Kjellerstua#dv-fel-714", sessionContext: context)

        XCTAssertEqual(context.unpairCalls, 1)
        XCTAssertNil(vm.detail)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func testOutOfOrderSeasonSwitchIgnoresStaleSeasonResponse() async throws {
        let host = "detail-season-race-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let seriesDetailJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "series:tmdb:95396",
            "mediaType": "series",
            "ids": { "tmdb": 95396 },
            "title": "Severance",
            "inWatchlist": false,
            "watched": false,
            "selectedSeason": 1,
            "seasons": [
              { "seasonNumber": 1, "name": "Sesong 1", "episodeCount": 1 },
              { "seasonNumber": 2, "name": "Sesong 2", "episodeCount": 1 }
            ],
            "episodes": [
              {
                "itemId": "episode:tmdb:95396:s1:e1",
                "seasonNumber": 1,
                "episodeNumber": 1,
                "title": "Good News About Hell",
                "watched": false
              }
            ]
          }
        }
        """#
        let season1JSON = #"""
        {
          "ok": true,
          "tmdbId": 95396,
          "seasonNumber": 1,
          "title": "Sesong 1",
          "episodes": [
            {
              "itemId": "episode:tmdb:95396:s1:e1",
              "seasonNumber": 1,
              "episodeNumber": 1,
              "title": "Good News About Hell",
              "watched": false
            }
          ]
        }
        """#
        let season2JSON = #"""
        {
          "ok": true,
          "tmdbId": 95396,
          "seasonNumber": 2,
          "title": "Sesong 2",
          "episodes": [
            {
              "itemId": "episode:tmdb:95396:s2:e1",
              "seasonNumber": 2,
              "episodeNumber": 1,
              "title": "Hello, Ms. Cobel",
              "watched": false
            }
          ]
        }
        """#

        let season2Gate = TestStepGate()
        let seasonLog = TestLockedBox<[String]>([])

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/api/tv/v1/items/series/series:tmdb:95396":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(seriesDetailJSON.utf8))
            case "/api/tv/v1/items/series/95396/seasons/2":
                await season2Gate.wait(label: "s2", log: seasonLog)
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(season2JSON.utf8))
            case "/api/tv/v1/items/series/95396/seasons/1":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(season1JSON.utf8))
            default:
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)

        let slowSeason2Task = Task { await vm.selectSeason(2) }
        await season2Gate.waitUntilStarted()
        XCTAssertEqual(vm.selectedSeasonNumber, 2)
        XCTAssertTrue(vm.isLoadingEpisodes)

        await vm.selectSeason(1)
        XCTAssertEqual(vm.selectedSeasonNumber, 1)
        XCTAssertEqual(vm.episodes.first?.title, "Good News About Hell")
        XCTAssertFalse(vm.isLoadingEpisodes)

        await season2Gate.finish()
        await slowSeason2Task.value

        XCTAssertEqual(vm.selectedSeasonNumber, 1)
        XCTAssertEqual(vm.episodes.first?.title, "Good News About Hell")
        XCTAssertFalse(vm.isLoadingEpisodes)
        XCTAssertEqual(seasonLog.withLock { $0 }, ["s2_start", "s2_end"])
    }

    @MainActor
    func testHeroPrimaryPlayTitleFormatsRemainingMinutesWhenResuming() throws {
        let resumedSeriesJson = #"""
        {
          "itemId": "series:tmdb:95396",
          "mediaType": "series",
          "ids": { "tmdb": 95396 },
          "title": "Severance",
          "inWatchlist": true,
          "watched": false,
          "nextUp": { "season": 2, "episode": 4 },
          "progress": {
            "positionSeconds": 1380,
            "durationSeconds": 2760,
            "percent": 50.0,
            "season": 2,
            "episode": 4
          }
        }
        """#
        let detail = try JSONDecoder().decode(TvItemDetail.self, from: Data(resumedSeriesJson.utf8))
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        XCTAssertEqual(vm.heroPrimaryPlayTitle(detail), "Fortsett S2 E4 · 23 min igjen")
    }

    @MainActor
    func testNextUpSeasonOverridesStaleSelectedSeasonOnInitialLoad() async throws {
        let host = "detail-s28-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let seriesDetailJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "series:tmdb:246810",
            "mediaType": "series",
            "ids": { "tmdb": 246810 },
            "title": "Luksusfellen",
            "year": 2008,
            "inWatchlist": true,
            "watched": false,
            "selectedSeason": 1,
            "nextUp": { "season": 28, "episode": 1 },
            "seasons": [
              { "seasonNumber": 0, "name": "Specials", "episodeCount": 2 },
              { "seasonNumber": 1, "name": "Season 1", "episodeCount": 10 },
              { "seasonNumber": 28, "name": "Season 28", "episodeCount": 1 }
            ],
            "episodes": [
              {
                "itemId": "episode:tmdb:246810:s1:e1",
                "seasonNumber": 1,
                "episodeNumber": 1,
                "title": "Pilot",
                "watched": true
              }
            ]
          }
        }
        """#

        let season28JSON = #"""
        {
          "ok": true,
          "tmdbId": 246810,
          "seasonNumber": 28,
          "title": "Season 28",
          "episodes": [
            {
              "itemId": "episode:tmdb:246810:s28:e1",
              "seasonNumber": 28,
              "episodeNumber": 1,
              "title": "Ny start i Drammen",
              "runtimeSeconds": 2700,
              "watched": false
            }
          ]
        }
        """#

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/seasons/28") {
                return (resp, Data(season28JSON.utf8))
            }
            if url.path.contains("/items/series/") {
                return (resp, Data(seriesDetailJSON.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:246810", initialTitle: "Luksusfellen")
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:246810#Stua#hdr10-512", sessionContext: context)

        XCTAssertEqual(vm.selectedSeasonNumber, 28)
        XCTAssertEqual(vm.episodes.first?.seasonNumber, 28)
        let loaded = try XCTUnwrap(vm.detail)
        XCTAssertEqual(vm.heroPrimaryPlayTitle(loaded), "Spill S28 E1 · 45 min")
    }
}
