import Foundation
import SwiftUI
import XCTest
@testable import Luna

@MainActor
private final class DetailZeroRTTSessionContext: MediaDetailSessionContext {
    var roomName: String = "Kjellerstua"
    var hardwareProfile: String = "dv-fel-714"
    var homeRefreshNonce: Int = 1
    var activePlaybackTarget: PlaybackLaunchRequest?
    var keepDisplayModeInMenuAfterPlayback: Bool = false
    var client: LunaCoreClient?
    let stopReceiptStore = PlaybackStopReceiptStore()

    var lastPlaybackStopReceipt: PlaybackStopReceipt? { stopReceiptStore.lastReceipt }
    func makeClient() -> LunaCoreClient? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
    func awaitPlaybackStopReceipt(for itemId: String, timeout: Duration) async -> PlaybackStopReceipt? {
        await stopReceiptStore.awaitReceipt(for: itemId, timeout: timeout)
    }
    func awaitPlaybackStopReceipt(
        for itemId: String, timeout: Duration, recordedAfter: Date?, excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt? {
        await stopReceiptStore.awaitReceipt(for: itemId, timeout: timeout, recordedAfter: recordedAfter, excluding: preLaunchReceipt)
    }
}

private final class ZeroRTTSourcePickerClient: SourcePickerSessionClient, @unchecked Sendable {
    let preparedSession: TvPlaybackSession
    let prepareToken: String
    let stoppedSessions = TestLockedBox<[String]>([])

    init(preparedSession: TvPlaybackSession, prepareToken: String) {
        self.preparedSession = preparedSession
        self.prepareToken = prepareToken
    }

    func preparePlayback(itemId: String, title: String, seriesTitle: String?, startPositionSeconds: Double?, prepareToken: String?) async throws -> TvPrepareResponse {
        TvPrepareResponse(ok: true, prepareToken: self.prepareToken, playbackSession: preparedSession)
    }
    func cancelInflightPlayback(sessionId: String?, resolveId: String?, itemId: String?, prepareToken: String?) async throws {}
    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        TvAlternativesResponse(ok: true, sessionId: sessionId, roomName: "Stua", hardwareProfile: "hdr10-512", activeCandidateId: preparedSession.selectedCandidate.candidateId, alternatives: [preparedSession.selectedCandidate])
    }
    func sendHeartbeat(sessionId: String, state: String, positionSeconds: Double, durationSeconds: Double, completed: Bool?) async throws -> TvHeartbeatResponse {
        if state == "stopped" { stoppedSessions.withLock { $0.append(sessionId) } }
        return TvHeartbeatResponse(ok: true, sessionId: sessionId, state: state)
    }
}

final class HomeCatalogAndDetailViewsTests: XCTestCase {
    // MARK: - HomeView Dynamic Rows, Catalog Filter Bar & MediaCardMutator

    @MainActor
    func testHomeViewDynamicRowsTonightSpotlightCatalogFilterAndMediaCardMutator() throws {
        let basePayload = PreviewMockFixtures.homeResponse
        let rows = HomeView.prepareVisibleRows(from: basePayload)
        XCTAssertEqual(HomeView.effectiveDisplayRows(rows: rows, tonight: basePayload.tonight).count, rows.count)

        let spotlightCard = PreviewMockFixtures.dunePartTwoCard
        let coldTonight = TvTonightPayload(
            ok: true,
            reason: "new_on_nvme",
            reasonLabel: "Nytt på NVMe · Starter umiddelbart",
            item: spotlightCard
        )
        let nonContinueRows = rows.filter { $0.rowId != "medialogg-continue" && $0.sourceKind != "system_continue" }
        let augmented = HomeView.effectiveDisplayRows(rows: nonContinueRows, tonight: coldTonight)
        XCTAssertEqual(augmented.first?.rowId, "tonight-spotlight")
        XCTAssertEqual(augmented.first?.items.first?.itemId, spotlightCard.itemId)

        let filtered = HomeView.filterVisibleRows([
            TvShelfRow(rowId: "empty", title: "Tom", items: []),
            TvShelfRow(rowId: "upcoming-episodes", title: "Kommende", rowStyle: "upcoming_backdrop", sourceKind: "system_upcoming", items: [spotlightCard]),
        ])
        XCTAssertEqual(filtered.map(\.rowId), ["upcoming-episodes"])

        let chip = try JSONDecoder().decode(
            TvGenreChip.self,
            from: Data(#"{"slug":"drama","label":"Drama","browsePath":"/api/tv/v2/catalog/movie?genre=drama"}"#.utf8)
        )
        let filterBar = CatalogFilterBarView(
            categoryTitle: "Filmer", availableGenres: [chip],
            selectedSort: .constant("popular"), localOnly: .constant(false), unwatchedOnly: .constant(false),
            selectedGenreSlug: .constant(nil), selectedGenreLabel: .constant(nil),
            entryFocusNonce: 0, isEntryActive: true, onScrollToTop: {}, onMoveDown: {}
        )
        XCTAssertEqual(filterBar.categoryTitle, "Filmer")
        XCTAssertEqual(CatalogFilterBarView.trailingMaskFadeWidth, 56)

        let scope = try IsolatedDefaultsScope(prefix: "luna.test.mutator")
        defer { scope.cleanup() }
        let store = AppSessionStore(defaults: scope.defaults)

        let upcomingCard = TvMediaCard(
            itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396),
            title: "Severance", availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet")
        )
        XCTAssertFalse(MediaCardMutator.canLaunchPlayback(for: upcomingCard))
        MediaCardMutator.launchPlayback(for: upcomingCard, sessionStore: store)
        XCTAssertNil(store.activePlaybackTarget)

        let readyCard = TvMediaCard(
            itemId: "movie:tmdb:693134", mediaType: "movie", ids: TvMediaIds(tmdb: 693134),
            title: "Dune: Part Two", availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        )
        XCTAssertTrue(MediaCardMutator.canLaunchPlayback(for: readyCard))
        MediaCardMutator.launchPlayback(for: readyCard, sessionStore: store)
        XCTAssertEqual(store.activePlaybackTarget?.itemId, "movie:tmdb:693134")

        let continueSeriesCard = TvMediaCard(
            itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396),
            title: "Severance", episodeCode: "S01E04", episodeTitle: nil,
            directPlayTarget: TvDirectPlayTarget(
                itemId: "episode:tmdb:95396:s1:e4", mediaType: "episode", tmdbId: 95396,
                season: 1, episode: 4, startPositionSeconds: 120, mode: "resume"
            ),
            nextUp: TvNextUpPointer(season: 1, episode: 4)
        )
        let resolvedTarget = MediaCardMutator.resolvePlayTarget(for: continueSeriesCard)
        XCTAssertEqual(resolvedTarget.itemId, "episode:tmdb:95396:s1:e4")
        XCTAssertEqual(resolvedTarget.seriesTitle, "Severance")

        let base = try XCTUnwrap(URL(string: "http://lunacore.local:8090"))
        let client = LunaCoreClient(
            baseURL: base, deviceID: "tv-card-test", deviceToken: "tok",
            roomName: "Stua", hardwareProfile: "hdr10-512", allowSelfSignedLanTLS: false
        )
        let poster = PosterCardView(card: readyCard, client: client, showRestingTitle: true, onSelect: {})
        let backdrop = BackdropCardView(card: readyCard, client: client, variant: .continueWatching, onPrimaryAction: {})
        let episodeCard = EpisodeCardView(
            episode: TvEpisodeCard(itemId: "episode:tmdb:95396:s1:e1", seasonNumber: 1, episodeNumber: 1, title: "Good News About Hell", runtimeSeconds: 3420, watched: false),
            seriesTitle: "Severance", client: client, onPlay: {}, onPickSource: {}, onToggleWatched: {}
        )
        let shelf = ShelfRowView(
            row: augmented[0], tonightReasonLabel: coldTonight.reasonLabel, isDefaultFocusRow: true,
            mountedTracker: MountedEntryCardTracker(), entryCardKey: nil, entryFocusNonce: 0,
            focusNamespace: Namespace().wrappedValue, client: client,
            onSelectCard: { _ in }, onPlayContinueCard: { _ in }, onPickSourceForCard: { _ in },
            onToggleWatchlist: { _ in }, onMarkWatched: { _ in }, onRemoveFromOngoing: { _ in },
            onRemoveFromList: { _, _ in }, onSeeAllRow: { _ in }
        )
        let libHub = LibraryHubView(viewModel: LibraryViewModel(), isActiveTab: true)
        let searchView = SearchView(viewModel: SearchViewModel(initialQuery: "Dune", isRootTab: true), initialQuery: "Dune", isRootTab: true)
        let castSection = DetailCastSectionView(
            castMembers: [TvCastMember(name: "Timothée Chalamet", character: "Paul Atreides", profileUrl: "/preview-art/sand-poster.png")],
            client: client, detailGutter: LunaTheme.horizontalGutter, onSelectCastMember: { _ in }
        )
        let candRow = SourceCandidateRowView(
            candidate: makeCandidate(id: "cand-row-1", isActive: true), isRecommended: true, isSelected: true,
            activeStatusLabel: "Spilles nå", isFocused: true, compactForQuickPanel: false
        ) {}
        XCTAssertEqual(poster.card.itemId, readyCard.itemId)
        XCTAssertEqual(backdrop.variant, .continueWatching)
        XCTAssertEqual(episodeCard.episode.episodeNumber, 1)
        XCTAssertEqual(shelf.tonightReasonLabel, coldTonight.reasonLabel)
        XCTAssertTrue(searchView.isRootTab)
        XCTAssertEqual(castSection.castMembers.count, 1)
        XCTAssertEqual(candRow.candidate.candidateId, "cand-row-1")
        _ = libHub
    }

    // MARK: - Detail Hero, More/Overview Sheets, Seasons Section & SourcePickerSheetView

    @MainActor
    func testDetailHeroMoreOverviewSeasonsAndSourcePickerSheetPolicies() {
        XCTAssertEqual(DetailHeroHeaderView.heroMinHeight(for: "movie"), 760)
        XCTAssertEqual(DetailHeroHeaderView.heroMinHeight(for: "series"), 500)

        let richSeries = TvItemDetail(
            itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396),
            title: "Skille", originalTitle: "Severance", year: 2022, genres: ["Sci-Fi", "Drama"],
            imdbRating: 8.7, imdbVotes: 340_000, rottenTomatoesScore: 97, metacriticScore: 83,
            badges: ["På NVMe", " 4K HDR10+ ", "4k hdr10+", "TrueHD Atmos", "DV"],
            inWatchlist: true, watched: false,
            nextEpisode: TvNextEpisodeSummary(itemId: "episode:tmdb:95396:s2:e4", season: 2, episode: 4, title: "Woe's Hollow", runtimeSeconds: 3180)
        )
        XCTAssertEqual(DetailHeroHeaderView.displayedBadges(for: richSeries), ["4K HDR10+", "TrueHD Atmos", "DV"])
        XCTAssertEqual(DetailHeroHeaderView.distinctOriginalTitle(for: richSeries), "Severance")
        XCTAssertEqual(DetailHeroHeaderView.detailRatingsLine(for: richSeries), "RT 97 % · MC 83 · IMDb 340k stemmer")
        XCTAssertEqual(DetailHeroHeaderView.nextEpisodeCue(for: richSeries), "Neste episode: S2 · E4 · Woe's Hollow · 53 min")

        // DetailMoreSheetView & DetailOverviewSheetView
        let localMovie = makeDetail(mediaType: "movie", monitored: false, availability: TvAvailabilityInfo(state: "instant", tier: "nvme"))
        let remoteMovie = makeDetail(mediaType: "movie", monitored: true, availability: TvAvailabilityInfo(state: "remote", tier: "vfs"))
        let unmonitoredSeries = makeDetail(mediaType: "series", monitored: false)
        XCTAssertFalse(DetailMoreSheetView.shouldShowMonitorButton(item: localMovie))
        XCTAssertTrue(DetailMoreSheetView.shouldShowMonitorButton(item: remoteMovie))
        XCTAssertTrue(DetailMoreSheetView.shouldShowDeleteButton(item: localMovie, hasLocalEpisodes: false))
        XCTAssertFalse(DetailMoreSheetView.shouldShowDeleteButton(item: unmonitoredSeries, hasLocalEpisodes: false))
        XCTAssertTrue(DetailMoreSheetView.shouldShowDeleteButton(item: unmonitoredSeries, hasLocalEpisodes: true))

        let sentenceA = String(repeating: "a", count: 160)
        let sentenceB = String(repeating: "b", count: 160)
        XCTAssertEqual(DetailOverviewSheetView.makeFocusableChunks(from: "\(sentenceA). \(sentenceB)"), ["\(sentenceA).", sentenceB])
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 24), 96)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 980), 620)

        // DetailSeasonsSectionView: Specials (Season 0) ordering & next-episode scroll target
        XCTAssertFalse(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 6))
        XCTAssertTrue(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 7))
        let specialsFirst = [
            TvSeasonSummary(seasonNumber: 0, name: "Specials", episodeCount: 2, posterUrl: nil, airDate: nil),
            TvSeasonSummary(seasonNumber: 1, name: "Season 1", episodeCount: 9, posterUrl: nil, airDate: nil),
            TvSeasonSummary(seasonNumber: 2, name: "Season 2", episodeCount: 10, posterUrl: nil, airDate: nil),
        ]
        XCTAssertEqual(DetailSeasonsSectionView.orderedSeasons(specialsFirst).map(\.seasonNumber), [1, 2, 0])
        XCTAssertEqual(DetailSeasonsSectionView.selectedSeasonSummary(seasons: specialsFirst, selectedSeasonNumber: 99)?.seasonNumber, 1)
        XCTAssertEqual(DetailSeasonsSectionView.selectedSeasonSummary(seasons: specialsFirst, selectedSeasonNumber: 0)?.seasonNumber, 0)

        let episodes = [
            TvEpisodeCard(itemId: "ep-1", seasonNumber: 2, episodeNumber: 1, title: "E1", watched: true),
            TvEpisodeCard(itemId: "ep-2", seasonNumber: 2, episodeNumber: 2, title: "E2", isUpcoming: true, watched: false),
            TvEpisodeCard(itemId: "ep-3", seasonNumber: 2, episodeNumber: 3, title: "E3", isUpcoming: false, watched: false),
        ]
        let detailWithNextUp = makeDetail(mediaType: "series", nextUp: TvNextUpPointer(season: 2, episode: 3))
        XCTAssertEqual(DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: nil, detail: detailWithNextUp, episodes: episodes), "ep-3")
        XCTAssertNil(DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: "ep-1", detail: detailWithNextUp, episodes: episodes))
        XCTAssertEqual(DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: "ep-2", detail: detailWithNextUp, episodes: episodes), "ep-2")

        // SourcePickerSheetView focus & default candidate selection
        let c1 = makeCandidate(id: "cand-1", isActive: false)
        let c2 = makeCandidate(id: "cand-2", isActive: true)
        XCTAssertEqual(SourcePickerSheetView.preferredDefaultCandidateID(candidates: [c1, c2], activeCandidateId: nil), "cand-2")
        XCTAssertEqual(SourcePickerSheetView.preferredDefaultCandidateID(candidates: [c1], activeCandidateId: "missing"), "cand-1")
        XCTAssertTrue(SourcePickerSheetView.shouldTriggerDefaultFocus(wasLoading: true, isLoading: false, errorMessage: nil, candidates: [c1]))
        XCTAssertFalse(SourcePickerSheetView.shouldTriggerDefaultFocus(wasLoading: true, isLoading: false, errorMessage: "Nettverksfeil", candidates: [c1]))
    }

    // MARK: - Detail Zero-RTT Pre-Resolve Handoff, Early Click & SourcePicker Adoption

    @MainActor
    func testDetailZeroRTTHandoffEarlyClickInflightPreservationAndSourcePickerAdoption() async throws {
        let host = "detail-0rtt-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            ItemDetailMemoryCache.shared.clear()
        }
        ItemDetailMemoryCache.shared.clear()

        let preparedSession = PlayerTestFixtures.makeMovieSession(
            sessionId: "tvs_interstellar_1",
            streamToken: "secret_stream_token_1234",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            itemId: "movie:tmdb:157336",
            tmdbId: 157336,
            title: "Interstellar",
            canClientPrewarmBytes: false
        )
        let prepareRespData = try JSONEncoder().encode(
            TvPrepareResponse(ok: true, prepareToken: "tvs_interstellar_1", playbackSession: preparedSession)
        )
        let detailFetches = TestLockedBox(0)

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/items/movie/") {
                detailFetches.withLock { $0 += 1 }
                return (resp, Data(#"{"ok":true,"item":{"itemId":"movie:tmdb:157336","mediaType":"movie","ids":{"tmdb":157336},"title":"Interstellar","year":2014,"inWatchlist":false,"watched":false}}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/prepare" { return (resp, prepareRespData) }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let context = DetailZeroRTTSessionContext()
        context.roomName = "Stua"
        context.hardwareProfile = "hdr10-512"
        context.client = try MockURLProtocol.makeClient(host: host)
        let scopeKey = "movie#movie:tmdb:157336#Stua#hdr10-512"

        let vm1 = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:157336", initialTitle: "Interstellar")
        await vm1.handleTaskAppearance(scopeKey: scopeKey, sessionContext: context)
        for _ in 0..<40 where !vm1.preResolve.isPreResolvedReady { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(vm1.preResolve.isPreResolvedReady)

        let vm2 = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:157336", initialTitle: "Interstellar")
        await vm2.handleTaskAppearance(scopeKey: scopeKey, sessionContext: context)
        XCTAssertEqual(detailFetches.withLock { $0 }, 1)

        vm1.launchPrimaryPlayback()
        XCTAssertEqual(context.activePlaybackTarget?.prepareToken, "tvs_interstellar_1")
        XCTAssertEqual(context.activePlaybackTarget?.preparedSession?.sessionId, "tvs_interstellar_1")

        // Early click preserves matching in-flight prepare task without cancelling it
        let earlyHost = "detail-early-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: earlyHost) }
        let prepareGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let prepareCancelled = TestLockedBox(false)
        MockURLProtocol.registerAsync(host: earlyHost) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/items/movie/") {
                return (resp, Data(#"{"ok":true,"item":{"itemId":"movie:tmdb:603","mediaType":"movie","ids":{"tmdb":603},"title":"The Matrix","inWatchlist":false,"watched":false}}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/prepare" {
                await prepareGate.wait(label: "prep", log: gateLog)
                if Task.isCancelled { prepareCancelled.withLock { $0 = true } }
                return (resp, Data(#"{"ok":true,"status":"prepared","prepareToken":"tvs_matrix_inflight"}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let earlyCtx = DetailZeroRTTSessionContext()
        earlyCtx.client = try MockURLProtocol.makeClient(host: earlyHost)
        let earlyVM = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:603", initialTitle: "The Matrix")
        await earlyVM.handleTaskAppearance(scopeKey: "movie#movie:tmdb:603#Kjellerstua#dv-fel-714", sessionContext: earlyCtx)
        await prepareGate.waitUntilStarted()
        earlyVM.launchPrimaryPlayback()
        let handedTask = try XCTUnwrap(earlyCtx.activePlaybackTarget?.inflightPrepareTask)
        XCTAssertFalse(prepareCancelled.withLock { $0 })
        await prepareGate.finish()
        let completedPrep = await handedTask.value
        XCTAssertEqual(completedPrep?.prepareToken, "tvs_matrix_inflight")

        // SourcePicker zero-RTT adoption preserves prepared session without sending stopped heartbeat
        let sampleSession = PreviewMockFixtures.playerSession
        let mockZeroRTT = ZeroRTTSourcePickerClient(preparedSession: sampleSession, prepareToken: "prep-tok-0rtt")
        let pickerContext = SourcePickerContext(itemId: sampleSession.item.itemId, title: sampleSession.item.title, startPositionSeconds: 0, existingPrepareToken: nil)
        let pickerVM = SourcePickerViewModel()
        await pickerVM.loadCandidates(context: pickerContext, client: mockZeroRTT, onUnauthorized: {})

        let detailCtx = DetailZeroRTTSessionContext()
        let detailVM = MediaDetailViewModel(mediaType: "movie", itemId: sampleSession.item.itemId, initialTitle: sampleSession.item.title)
        detailVM.bind(sessionContext: detailCtx)
        pickerVM.selectCandidate(sampleSession.selectedCandidate, isCurrent: true, context: pickerContext, client: mockZeroRTT) { picked, reusedToken, createdSession in
            detailVM.launchSelectedSource(picked, reusedToken: reusedToken, createdPreparedSession: createdSession, context: pickerContext)
        }
        pickerVM.handleDisappear(context: pickerContext, client: mockZeroRTT)
        XCTAssertEqual(detailCtx.activePlaybackTarget?.prepareToken, "prep-tok-0rtt")
        XCTAssertEqual(detailCtx.activePlaybackTarget?.preparedSession?.sessionId, sampleSession.sessionId)
        XCTAssertTrue(mockZeroRTT.stoppedSessions.withLock { $0 }.isEmpty)
    }

    private func makeCandidate(id: String, isActive: Bool?) -> TvCandidateInfo {
        TvCandidateInfo(
            candidateId: id, displayHeadline: "4K HDR10", releaseTitle: "Example.2024.2160p",
            source: "nvme", tier: "nvme", resolution: "2160p", videoRangeType: "HDR10",
            dvProfile: nil, dvEnhancementLayer: nil, audioCodec: "Atmos", sizeBytes: 10_000_000_000,
            tvScore: 950, isActive: isActive, explanationChips: nil, releaseGroup: nil, isNorwegian: false
        )
    }

    private func makeDetail(
        mediaType: String,
        monitored: Bool? = nil,
        availability: TvAvailabilityInfo? = nil,
        nextUp: TvNextUpPointer? = nil
    ) -> TvItemDetail {
        TvItemDetail(
            itemId: "\(mediaType):tmdb:100",
            mediaType: mediaType,
            ids: TvMediaIds(tmdb: 100),
            title: "Eksempeltittel",
            inWatchlist: false,
            watched: false,
            monitored: monitored,
            availability: availability,
            nextUp: nextUp
        )
    }
}
