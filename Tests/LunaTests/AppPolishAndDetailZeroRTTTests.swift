import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

@MainActor
private final class Etappe6MockDetailSessionContext: MediaDetailSessionContext {
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var activePlaybackTarget: PlaybackLaunchRequest? = nil
    var keepDisplayModeInMenuAfterPlayback: Bool = false
    var client: LunaCoreClient?

    func makeClient() -> LunaCoreClient? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
}

private final class Etappe6ZeroRTTSourcePickerClient: SourcePickerSessionClient, @unchecked Sendable {
    let preparedSession: TvPlaybackSession
    let prepareToken: String
    let candidates: [TvCandidateInfo]
    let stoppedSessions = TestLockedBox<[String]>([])
    let prepareCalls = TestLockedBox<Int>(0)

    init(
        preparedSession: TvPlaybackSession,
        prepareToken: String,
        candidates: [TvCandidateInfo]
    ) {
        self.preparedSession = preparedSession
        self.prepareToken = prepareToken
        self.candidates = candidates
    }

    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        prepareToken: String?
    ) async throws -> TvPrepareResponse {
        prepareCalls.withLock { $0 += 1 }
        return TvPrepareResponse(
            ok: true,
            prepareToken: self.prepareToken,
            playbackSession: preparedSession
        )
    }

    func cancelInflightPlayback(
        sessionId: String?,
        resolveId: String?,
        itemId: String?,
        prepareToken: String?
    ) async throws {}

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        TvAlternativesResponse(
            ok: true,
            sessionId: sessionId,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            activeCandidateId: candidates.first?.candidateId,
            alternatives: candidates
        )
    }

    func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?
    ) async throws -> TvHeartbeatResponse {
        if state == "stopped" {
            stoppedSessions.withLock { $0.append(sessionId) }
        }
        return TvHeartbeatResponse(ok: true, sessionId: sessionId, state: state)
    }
}

final class AppPolishAndDetailZeroRTTTests: XCTestCase {
    @MainActor
    func testColdSeriesDetailWithoutInlineEpisodesFiresOnlySinglePreparePlaybackWithResolvedEpisodeProgress() async throws {
        let host = "etappe6-series-cold-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }

        // Detail response intentionally omits inline `episodes` and has coarse series-level progress (400s),
        // while `/seasons/3` returns exact episode progress (1710s). Only ONE `/playback/prepare` may fire!
        let detailJSON = #"""
        {
          "ok": true,
          "item": {
            "itemId": "series:tmdb:79291",
            "mediaType": "series",
            "ids": { "tmdb": 79291 },
            "title": "Lykkeland",
            "year": 2018,
            "inWatchlist": false,
            "watched": false,
            "monitored": true,
            "selectedSeason": 3,
            "nextUp": { "season": 3, "episode": 2 },
            "progress": { "positionSeconds": 400, "durationSeconds": 2940, "percent": 13.6, "season": 3, "episode": 2, "watched": false },
            "seasons": [
              { "seasonNumber": 3, "name": "Sesong 3", "episodeCount": 2 }
            ]
          }
        }
        """#

        let season3JSON = #"""
        {
          "ok": true,
          "tmdbId": 79291,
          "seasonNumber": 3,
          "title": "Sesong 3",
          "episodes": [
            {
              "itemId": "episode:tmdb:79291:s3:e1",
              "seasonNumber": 3,
              "episodeNumber": 1,
              "title": "Alexander Kielland",
              "watched": true
            },
            {
              "itemId": "episode:tmdb:79291:s3:e2",
              "seasonNumber": 3,
              "episodeNumber": 2,
              "title": "Etterdønninger",
              "watched": false,
              "progress": { "positionSeconds": 1710, "durationSeconds": 2940, "percent": 58.2, "season": 3, "episode": 2, "watched": false }
            }
          ]
        }
        """#

        let prepareBodies = TestLockedBox<[String]>([])
        let cancelledPrepareCount = TestLockedBox(0)

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let bodyData = MockURLProtocol.bodyData(for: request)
            let bodyStr = String(data: bodyData, encoding: .utf8) ?? ""
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            switch url.path {
            case "/api/tv/v1/items/series/series:tmdb:79291":
                return (resp, Data(detailJSON.utf8))
            case "/api/tv/v1/items/series/79291/seasons/3":
                return (resp, Data(season3JSON.utf8))
            case "/api/tv/v1/playback/prepare":
                prepareBodies.withLock { $0.append(bodyStr) }
                if Task.isCancelled {
                    cancelledPrepareCount.withLock { $0 += 1 }
                }
                return (resp, Data(#"{"ok":true,"status":"prepared","prepareToken":"tok-lykkeland-s3e2"}"#.utf8))
            case "/api/tv/v1/playback/heartbeat":
                if bodyStr.contains("\"cancelInflight\":true") {
                    cancelledPrepareCount.withLock { $0 += 1 }
                }
                return (resp, Data(#"{"ok":true}"#.utf8))
            default:
                return (resp, Data(#"{"ok":true}"#.utf8))
            }
        }

        let ctx = Etappe6MockDetailSessionContext()
        ctx.client = try MockURLProtocol.makeClient(host: host)
        let vm = MediaDetailViewModel(mediaType: "series", itemId: "series:tmdb:79291", initialTitle: "Lykkeland")

        await vm.handleTaskAppearance(scopeKey: "series#series:tmdb:79291#Stua#hdr10-512", sessionContext: ctx)
        for _ in 0..<40 where prepareBodies.withLock({ $0.isEmpty }) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let bodies = prepareBodies.withLock { $0 }
        XCTAssertEqual(bodies.count, 1, "Cold series detail without inline episodes must fire exactly ONE preparePlayback")
        XCTAssertEqual(cancelledPrepareCount.withLock { $0 }, 0)
        XCTAssertTrue(bodies.first?.contains("1710") == true)

        // Episode focus restoration advances to nextUp when the watched episode finished, otherwise keeps episode
        let keepUnwatched = MediaDetailViewModel.resolveRestoredEpisodeFocusID(
            lastFocusedEpisodeID: "episode:tmdb:79291:s3:e2",
            episodes: vm.episodes,
            nextUp: TvNextUpPointer(season: 3, episode: 2)
        )
        XCTAssertEqual(keepUnwatched, "episode:tmdb:79291:s3:e2")

        let advanceFromWatched = MediaDetailViewModel.resolveRestoredEpisodeFocusID(
            lastFocusedEpisodeID: "episode:tmdb:79291:s3:e1",
            episodes: vm.episodes,
            nextUp: TvNextUpPointer(season: 3, episode: 2)
        )
        XCTAssertEqual(advanceFromWatched, "episode:tmdb:79291:s3:e2")
    }

    @MainActor
    func testSourcePickerPreservesPreparedZeroRTTSessionWhenSelectingRecommendedEdition() async throws {
        let sessionJSON = #"""
        {
          "sessionId": "sess-0rtt-dune2",
          "streamToken": "tok-0rtt-stream-9911",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "movie:tmdb:693134",
            "mediaType": "movie",
            "ids": { "tmdb": 693134 },
            "title": "Dune: Part Two"
          },
          "selectedCandidate": {
            "candidateId": "cand-recommended",
            "displayHeadline": "4K HDR10+ · TrueHD Atmos",
            "releaseTitle": "Dune.Part.Two.2024.2160p.REMUX",
            "source": "nvme",
            "tier": "nvme",
            "isActive": true
          },
          "stream": { "url": "/api/tv/v1/stream/sess-0rtt-dune2/tok-0rtt-stream-9911/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let sampleSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        let altCandidate = TvCandidateInfo(
            candidateId: "cand-alt-1080p",
            displayHeadline: "1080p WEB-DL",
            releaseTitle: "Dune.Part.Two.2024.1080p.WEB-DL",
            source: "vfs",
            tier: "vfs",
            resolution: "1080p",
            videoRangeType: "SDR",
            dvProfile: nil,
            dvEnhancementLayer: nil,
            audioCodec: "DDP Atmos",
            sizeBytes: 5_368_709_120,
            tvScore: 920,
            isActive: false,
            explanationChips: ["Strømmes ved start"],
            releaseGroup: "FLUX",
            isNorwegian: true
        )
        let mockClient = Etappe6ZeroRTTSourcePickerClient(
            preparedSession: sampleSession,
            prepareToken: "prep-tok-0rtt-dune2",
            candidates: [sampleSession.selectedCandidate, altCandidate]
        )

        let pickerContext = SourcePickerContext(
            itemId: "movie:tmdb:693134",
            title: "Dune: Part Two",
            startPositionSeconds: 5640,
            existingPrepareToken: nil
        )
        let pickerVM = SourcePickerViewModel()
        await pickerVM.loadCandidates(context: pickerContext, client: mockClient, onUnauthorized: {})
        XCTAssertEqual(mockClient.prepareCalls.withLock { $0 }, 1)
        XCTAssertEqual(pickerVM.createdPreparedSession?.sessionId, "sess-0rtt-dune2")

        let detailContext = Etappe6MockDetailSessionContext()
        let detailVM = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:693134", initialTitle: "Dune: Part Two")
        detailVM.bind(sessionContext: detailContext)

        pickerVM.selectCandidate(
            sampleSession.selectedCandidate,
            isCurrent: true,
            context: pickerContext,
            client: mockClient
        ) { picked, reusedToken, createdPreparedSession in
            detailVM.launchSelectedSource(
                picked,
                reusedToken: reusedToken,
                createdPreparedSession: createdPreparedSession,
                context: pickerContext
            )
        }
        pickerVM.handleDisappear(context: pickerContext, client: mockClient)

        XCTAssertEqual(detailContext.activePlaybackTarget?.prepareToken, "prep-tok-0rtt-dune2")
        XCTAssertEqual(detailContext.activePlaybackTarget?.preparedSession?.sessionId, "sess-0rtt-dune2")
        XCTAssertNil(detailContext.activePlaybackTarget?.candidateId)
        XCTAssertTrue(mockClient.stoppedSessions.withLock { $0 }.isEmpty)
    }

    @MainActor
    func testSessionIsolatedSearchHistoryUpcomingPlayShortcutGuardAndEtappe6PolishConstants() throws {
        let suite = "luna.test.etappe6.search.\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolatedDefaults.removePersistentDomain(forName: suite) }

        let standardBefore = UserDefaults.standard.stringArray(forKey: SideloadSafeStorage.recentSearchesKey)
        let uniqueProbeTerm = "Etappe6Probe-\(UUID().uuidString.prefix(8))"

        let store = AppSessionStore(defaults: isolatedDefaults)
        XCTAssertEqual(store.loadRecentSearches(), [])
        store.recordRecentSearch(uniqueProbeTerm)
        XCTAssertEqual(store.loadRecentSearches(), [uniqueProbeTerm])
        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: SideloadSafeStorage.recentSearchesKey),
            standardBefore,
            "AppSessionStore search history must never leak into UserDefaults.standard"
        )
        store.clearRecentSearches()
        XCTAssertEqual(store.loadRecentSearches(), [])

        // Upcoming release must block Play/Pause shortcut while released card launches playback
        let upcomingCard = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance",
            availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet")
        )
        XCTAssertFalse(MediaCardMutator.canLaunchPlayback(for: upcomingCard))
        MediaCardMutator.launchPlayback(for: upcomingCard, sessionStore: store)
        XCTAssertNil(store.activePlaybackTarget)

        let readyCard = TvMediaCard(
            itemId: "movie:tmdb:693134",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 693134),
            title: "Dune: Part Two",
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        )
        XCTAssertTrue(MediaCardMutator.canLaunchPlayback(for: readyCard))
        MediaCardMutator.launchPlayback(for: readyCard, sessionStore: store)
        XCTAssertEqual(store.activePlaybackTarget?.itemId, "movie:tmdb:693134")

        // Etappe 6 player, shelf, filter-bar, decode-target & borderless resting constants
        XCTAssertEqual(PlayerQuickPanelView.maxScrollAreaHeight, 376)
        XCTAssertEqual(SubtitleOverlayLayout.skipPromptBottomInset, 168)
        XCTAssertEqual(SubtitleOverlayLayout.nextEpisodeBottomInset, 300)
        XCTAssertEqual(PosterCardView.shelfCaptionSpacing, 10)
        XCTAssertEqual(PosterCardView.shelfCaptionHeight, 52)
        XCTAssertEqual(CatalogFilterBarView.trailingMaskFadeWidth, 56)
        XCTAssertEqual(CatalogSortOption.allOptions.map(\.id), ["popular", "top_rated", "newest", "local_recent"])
        XCTAssertEqual(ArtworkDecodeTargets.posterCardMaxPixelSize, 820)
        XCTAssertEqual(ArtworkDecodeTargets.backdropCardMaxPixelSize, 1092)
        XCTAssertEqual(ArtworkDecodeTargets.episodeCardMaxPixelSize, 882)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .high2026), 2880)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .standard), 2400)

        let iconRestUI = UIColor(LunaIconButton.resolveBorderColor(isFocused: false, isSelected: false))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(iconRestUI.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(Double(a), 0.0, accuracy: 0.005)
    }
}
