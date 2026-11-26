import Foundation
import XCTest
@testable import Luna

final class MediaDetailPreResolveAndReceiptTests: XCTestCase {
    @MainActor
    func testDetailMemoryCacheHitMutationInvalidationAndPreparedSessionHandoff() async throws {
        let host = "detail-cache-handoff-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let movieJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "movie:tmdb:157336",
            "mediaType": "movie",
            "ids": { "tmdb": 157336 },
            "title": "Interstellar",
            "year": 2014,
            "inWatchlist": false,
            "watched": false
          }
        }
        """#
        let prepareJSON = #"""
        {
          "ok": true,
          "status": "prepared",
          "prepareToken": "tvs_interstellar_1",
          "canClientPrewarmBytes": false,
          "playbackSession": {
            "sessionId": "tvs_interstellar_1",
            "streamToken": "secret_stream_token_1234",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512",
            "item": {
              "itemId": "movie:tmdb:157336",
              "mediaType": "movie",
              "ids": { "tmdb": 157336 },
              "title": "Interstellar",
              "backdropUrl": "/art/interstellar-backdrop.jpg",
              "logoUrl": "/art/interstellar-logo.png"
            },
            "selectedCandidate": {
              "candidateId": "cand-1",
              "displayHeadline": "4K UHD · HDR10 · TrueHD 7.1",
              "releaseTitle": "Interstellar.2014.2160p",
              "source": "local",
              "tier": "ssd"
            },
            "stream": {
              "url": "/api/tv/v2/stream/tvs_interstellar_1/secret_stream_token_1234/Interstellar.mkv",
              "canClientPrewarmBytes": false
            },
            "aetherConfig": {
              "preferDualLayerDolbyVision": false,
              "dolbyVisionHandling": "auto",
              "matchContentEnabled": true,
              "audioBridgeMode": "passthrough"
            }
          }
        }
        """#

        let detailFetches = TestLockedBox(0)
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/items/movie/") {
                detailFetches.withLock { $0 += 1 }
                return (resp, Data(movieJSON.utf8))
            }
            if url.path == "/api/tv/v2/playback/prepare" {
                return (resp, Data(prepareJSON.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = MockDetailSessionContext()
        context.roomName = "Stua"
        context.hardwareProfile = "hdr10-512"
        context.client = try MockURLProtocol.makeClient(host: host)
        let scope = "movie#movie:tmdb:157336#Stua#hdr10-512"

        let vm1 = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:157336", initialTitle: "Interstellar")
        await vm1.handleTaskAppearance(scopeKey: scope, sessionContext: context)
        XCTAssertEqual(detailFetches.withLock { $0 }, 1)

        // Wait briefly for 0 ms immediate preparePlayback to finish
        for _ in 0..<40 where !vm1.preResolve.isPreResolvedReady {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm1.preResolve.isPreResolvedReady)

        // Re-opening same title in a fresh ViewModel hits ItemDetailMemoryCache with 0 extra HTTP fetches!
        let vm2 = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:157336", initialTitle: "Interstellar")
        await vm2.handleTaskAppearance(scopeKey: scope, sessionContext: context)
        XCTAssertEqual(detailFetches.withLock { $0 }, 1)
        XCTAssertEqual(vm2.detail?.title, "Interstellar")

        // Launch primary playback from vm1 transfers both prepareToken AND preparedSession into PlaybackLaunchRequest
        vm1.launchPrimaryPlayback()
        XCTAssertEqual(context.activePlaybackTarget?.prepareToken, "tvs_interstellar_1")
        XCTAssertEqual(context.activePlaybackTarget?.preparedSession?.sessionId, "tvs_interstellar_1")
        XCTAssertEqual(context.activePlaybackTarget?.preparedSession?.item.logoUrl, "/art/interstellar-logo.png")
        XCTAssertEqual(ItemDetailMemoryCache.shared.entryCount, 0, "Launching playback must invalidate ItemDetailMemoryCache")

        vm1.handleDisappear(sessionContext: context)
        vm2.handleDisappear(sessionContext: context)
    }

    @MainActor
    func testEarlyClickPreservesMatchingInflightPrepareWithoutCancellingNetworkCall() async throws {
        let host = "detail-early-click-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let movieJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "movie:tmdb:603",
            "mediaType": "movie",
            "ids": { "tmdb": 603 },
            "title": "The Matrix",
            "inWatchlist": false,
            "watched": false
          }
        }
        """#

        let prepareGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let prepareCancelled = TestLockedBox(false)

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/items/movie/") {
                return (resp, Data(movieJSON.utf8))
            }
            if url.path == "/api/tv/v2/playback/prepare" {
                await prepareGate.wait(label: "prep", log: gateLog)
                if Task.isCancelled {
                    prepareCancelled.withLock { $0 = true }
                }
                return (resp, Data(#"{"ok":true,"status":"prepared","prepareToken":"tvs_matrix_inflight"}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:603", initialTitle: "The Matrix")
        await vm.handleTaskAppearance(scopeKey: "movie#movie:tmdb:603#Kjellerstua#dv-fel-714", sessionContext: context)

        await prepareGate.waitUntilStarted()
        // User clicks Spill av BEFORE /playback/prepare finishes!
        vm.launchPrimaryPlayback()
        let handedTask = try XCTUnwrap(context.activePlaybackTarget?.inflightPrepareTask)
        XCTAssertFalse(prepareCancelled.withLock { $0 }, "Early click must NOT cancel matching in-flight preparePlayback")

        await prepareGate.finish()
        let completedPrep = await handedTask.value
        XCTAssertEqual(completedPrep?.prepareToken, "tvs_matrix_inflight")
        XCTAssertFalse(prepareCancelled.withLock { $0 })
    }

    @MainActor
    func testSeasonErrorRollbackSingleOptimisticMutationsAndScopedPrepareTokenCancel() async throws {
        let host = "detail-steg42-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let detailJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "series:tmdb:95396",
            "mediaType": "series",
            "ids": { "tmdb": 95396 },
            "title": "Severance",
            "inWatchlist": false,
            "watched": false,
            "monitored": false,
            "selectedSeason": 1,
            "nextUp": { "season": 1, "episode": 1 },
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

        let detailGetCount = TestLockedBox(0)
        let prepareGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let sentPrepareTokens = TestLockedBox<[String]>([])
        let sentCancelTokens = TestLockedBox<[String]>([])

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let bodyData = MockURLProtocol.bodyData(for: request)
            let bodyStr = String(data: bodyData, encoding: .utf8) ?? ""
            switch url.path {
            case "/api/tv/v2/items/series/series:tmdb:95396":
                detailGetCount.withLock { $0 += 1 }
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(detailJSON.utf8))
            case "/api/tv/v2/items/series/95396/seasons/2":
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"error":"Sesong utilgjengelig"}"#.utf8))
            case "/api/tv/v2/playback/prepare":
                if let data = bodyStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tok = obj["prepareToken"] as? String {
                    sentPrepareTokens.withLock { $0.append(tok) }
                }
                await prepareGate.wait(label: "prep", log: gateLog)
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true,"status":"prepared","prepareToken":"tvs_s1e1"}"#.utf8))
            case "/api/tv/v2/playback/heartbeat":
                if let data = bodyStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   obj["cancelInflight"] as? Bool == true,
                   let tok = obj["prepareToken"] as? String {
                    sentCancelTokens.withLock { $0.append(tok) }
                }
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true}"#.utf8))
            default:
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(#"{"ok":true,"monitored":true,"monitorMode":"unwatched"}"#.utf8))
            }
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)
        await prepareGate.waitUntilStarted()
        XCTAssertEqual(detailGetCount.withLock { $0 }, 1)

        // Failed season fetch rolls back selectedSeasonNumber to 1 and sets banner
        await vm.selectSeason(2)
        XCTAssertEqual(vm.selectedSeasonNumber, 1)
        XCTAssertTrue(vm.mutationErrorBanner?.contains("Sesong utilgjengelig") == true)

        // Optimistic watchlist & monitor mutations do NOT trigger a redundant GET /items/series/...
        await vm.toggleWatchlist()
        await vm.toggleMonitor()
        XCTAssertEqual(vm.detail?.inWatchlist, true)
        XCTAssertEqual(vm.detail?.isMonitoredFlag, true)
        XCTAssertEqual(detailGetCount.withLock { $0 }, 1)

        // Disappear while prepare is in-flight sends token-scoped cancelInflightPlayback matching prepareToken
        vm.handleDisappear(sessionContext: context)
        await prepareGate.finish()
        for _ in 0..<40 where sentCancelTokens.withLock({ $0.isEmpty }) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let prepTokens = sentPrepareTokens.withLock { $0 }
        let cancelTokens = sentCancelTokens.withLock { $0 }
        XCTAssertEqual(prepTokens.count, 1)
        XCTAssertEqual(cancelTokens, prepTokens)
    }

    @MainActor
    func testZeroDelayStopReceiptWakesPostPlaybackRefreshImmediately() async throws {
        let host = "detail-stop-receipt-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let detailFetchCount = TestLockedBox(0)
        let beforeJSON = #"{"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":1},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":false},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}"#
        let afterJSON = #"{"ok":true,"item":{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":false,"watched":false,"selectedSeason":1,"nextUp":{"season":1,"episode":2},"seasons":[{"seasonNumber":1,"name":"Sesong 1","episodeCount":2}],"episodes":[{"itemId":"episode:tmdb:95396:s1:e1","seasonNumber":1,"episodeNumber":1,"title":"E1","watched":true},{"itemId":"episode:tmdb:95396:s1:e2","seasonNumber":1,"episodeNumber":2,"title":"E2","watched":false}]}}"#

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/items/series/") {
                let count = detailFetchCount.withLock { c -> Int in
                    c += 1
                    return c
                }
                return (resp, Data((count == 1 ? beforeJSON : afterJSON).utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = MockDetailSessionContext()
        context.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:95396", initialTitle: "Severance")
        vm.stopReceiptTimeout = .seconds(3)
        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:95396#Kjellerstua#dv-fel-714", sessionContext: context)
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 1))

        let launched = PlaybackLaunchRequest(itemId: "episode:tmdb:95396:s1:e1", title: "E1", seriesTitle: "Severance", season: 1, episode: 1)
        context.activePlaybackTarget = launched
        vm.handlePlaybackTargetChange(oldTarget: nil, newTarget: launched)

        context.stopReceiptStore.record(
            PlaybackStopReceipt(
                itemId: "episode:tmdb:95396:s1:e1",
                mediaType: "episode",
                seasonNumber: 1,
                episodeNumber: 1,
                positionSeconds: 2800,
                durationSeconds: 2800,
                completed: true
            )
        )
        context.activePlaybackTarget = nil
        let start = Date()
        vm.handlePlaybackTargetChange(oldTarget: launched, newTarget: nil)
        await vm.postPlaybackReloadFallbackTask?.value
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.8, "Stop receipt must wake detail refresh immediately without 2.2 s sleep")
        XCTAssertEqual(vm.detail?.nextUp, TvNextUpPointer(season: 1, episode: 2))
    }
}
