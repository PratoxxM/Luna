import Foundation
import SwiftUI
import XCTest
@testable import Luna

final class DetailViewsAndSheetsTests: XCTestCase {
    // MARK: - K-2 (5/7): DetailHeroHeaderView

    func testDetailHeroHeaderFormattingAndBadgeDeduplication() {
        XCTAssertEqual(DetailHeroHeaderView.heroMinHeight(for: "movie"), 760)
        XCTAssertEqual(DetailHeroHeaderView.heroMinHeight(for: "series"), 500)

        let seriesDetail = makeDetail(
            mediaType: "series",
            year: 2022,
            genres: ["Sci-Fi", "Drama", "Thriller"],
            imdbRating: 8.7,
            badges: ["På NVMe", " 4K HDR10+ ", "4k hdr10+", "TrueHD Atmos", "Kommer: I morgen", "DV", "Ekstra"],
            nextAirDateBadge: "I morgen",
            seasons: [
                TvSeasonSummary(seasonNumber: 0, name: "Specials", episodeCount: 2, posterUrl: nil, airDate: nil),
                TvSeasonSummary(seasonNumber: 1, name: "Season 1", episodeCount: 9, posterUrl: nil, airDate: nil),
                TvSeasonSummary(seasonNumber: 2, name: "Season 2", episodeCount: 10, posterUrl: nil, airDate: nil),
            ]
        )

        let seriesMeta = DetailHeroHeaderView.detailMetadataLine(for: seriesDetail)
        XCTAssertEqual(
            seriesMeta,
            "2022 · Sci-Fi, Drama · \(LunaCopy.seasonsCount(2)) · ★ 8,7 · Ny episode I morgen"
        )
        XCTAssertEqual(
            DetailHeroHeaderView.displayedBadges(for: seriesDetail),
            ["4K HDR10+", "TrueHD Atmos", "DV"]
        )
        XCTAssertNil(DetailHeroHeaderView.distinctOriginalTitle(for: seriesDetail))
        XCTAssertNil(DetailHeroHeaderView.detailRatingsLine(for: seriesDetail))
        XCTAssertNil(DetailHeroHeaderView.nextEpisodeCue(for: seriesDetail))

        let movieDetail = makeDetail(
            mediaType: "movie",
            year: 2024,
            runtimeSeconds: 9960,
            genres: ["Sci-Fi"],
            imdbRating: 8.5,
            badges: ["Klar i VFS", "I Arkiv", "Strømmes ved start", "Starter umiddelbart", "Kommer", "HDR10"]
        )
        XCTAssertEqual(
            DetailHeroHeaderView.detailMetadataLine(for: movieDetail),
            "2024 · Sci-Fi · 2 t 46 min · ★ 8,5"
        )
        XCTAssertEqual(DetailHeroHeaderView.displayedBadges(for: movieDetail), ["HDR10"])
    }

    func testDetailHeroHeaderRichP32RatingsOriginalTitleTaglineAndNextEpisode() {
        let richSeries = TvItemDetail(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Skille",
            originalTitle: "Severance",
            tagline: "We're all different people.",
            imdbRating: 8.7,
            imdbVotes: 340_000,
            rottenTomatoesScore: 97,
            metacriticScore: 83,
            castMembers: [
                TvCastMember(name: "Adam Scott", character: "Mark Scout", profileUrl: "/preview-art/navy-poster.png"),
                TvCastMember(name: "Britt Lower", character: "Helly Riggs", profileUrl: nil),
            ],
            inWatchlist: true,
            watched: false,
            nextEpisode: TvNextEpisodeSummary(
                itemId: "episode:tmdb:95396:s2:e4",
                season: 2,
                episode: 4,
                title: "Woe's Hollow",
                stillUrl: nil,
                runtimeSeconds: 3180
            )
        )

        XCTAssertEqual(DetailHeroHeaderView.distinctOriginalTitle(for: richSeries), "Severance")
        XCTAssertEqual(
            DetailHeroHeaderView.detailRatingsLine(for: richSeries),
            "RT 97 % · MC 83 · IMDb 340k stemmer"
        )
        XCTAssertEqual(
            DetailHeroHeaderView.nextEpisodeCue(for: richSeries),
            "Neste episode: S2 · E4 · Woe's Hollow · 53 min"
        )

        let sameOriginal = makeDetail(mediaType: "movie", originalTitle: "eksempeltittel", imdbVotes: 2_400_000)
        XCTAssertNil(DetailHeroHeaderView.distinctOriginalTitle(for: sameOriginal))
        XCTAssertEqual(DetailHeroHeaderView.detailRatingsLine(for: sameOriginal), "IMDb 2,4M stemmer")
    }

    @MainActor
    func testDetailCastSectionViewAndMediaDetailSheetVariantsConstruct() {
        let cast = [
            TvCastMember(name: "Timothée Chalamet", character: "Paul Atreides", profileUrl: "/preview-art/sand-poster.png"),
            TvCastMember(name: "Zendaya", character: "Chani", profileUrl: "/preview-art/ochre-poster.png"),
        ]
        var tappedName: String?
        let castSection = DetailCastSectionView(
            castMembers: cast,
            client: nil,
            detailGutter: LunaTheme.horizontalGutter
        ) { member in
            tappedName = member.name
        }
        XCTAssertEqual(castSection.castMembers.count, 2)
        castSection.onSelectCastMember?(cast[0])
        XCTAssertEqual(tappedName, "Timothée Chalamet")

        let seasonsView = MediaDetailView(
            mediaType: "series",
            itemId: "series:tmdb:246810",
            initialTitle: "Luksusfellen",
            previewAutoOpenSheet: .seasons
        )
        let overviewView = MediaDetailView(
            mediaType: "movie",
            itemId: "movie:tmdb:693134",
            initialTitle: "Dune: Part Two",
            previewAutoOpenSheet: .overview
        )
        XCTAssertEqual(seasonsView.previewAutoOpenSheet, .seasons)
        XCTAssertEqual(overviewView.previewAutoOpenSheet, .overview)
    }

    // MARK: - K-2 (6/7): DetailMoreAndOverviewSheets

    func testDetailMoreSheetActionsAndOverviewChunking() {
        XCTAssertEqual(DetailMoreSheetView.defaultAction(canReadOverview: true), .readOverview)
        XCTAssertEqual(DetailMoreSheetView.defaultAction(canReadOverview: false), .toggleWatched)

        let localMovie = makeDetail(
            mediaType: "movie",
            monitored: false,
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        )
        let remoteMovie = makeDetail(
            mediaType: "movie",
            monitored: true,
            availability: TvAvailabilityInfo(state: "remote", tier: "vfs")
        )
        let unmonitoredRemoteMovie = makeDetail(
            mediaType: "movie",
            monitored: false,
            availability: TvAvailabilityInfo(state: "remote", tier: "usenet")
        )
        let monitoredSeries = makeDetail(mediaType: "series", monitored: true)
        let unmonitoredSeries = makeDetail(mediaType: "series", monitored: false)

        XCTAssertFalse(DetailMoreSheetView.shouldShowMonitorButton(item: localMovie))
        XCTAssertTrue(DetailMoreSheetView.shouldShowMonitorButton(item: remoteMovie))
        XCTAssertTrue(DetailMoreSheetView.shouldShowMonitorButton(item: unmonitoredSeries))

        XCTAssertTrue(DetailMoreSheetView.shouldShowDeleteButton(item: localMovie, hasLocalEpisodes: false))
        XCTAssertTrue(DetailMoreSheetView.shouldShowDeleteButton(item: remoteMovie, hasLocalEpisodes: false))
        XCTAssertTrue(DetailMoreSheetView.shouldShowDeleteButton(item: unmonitoredSeries, hasLocalEpisodes: true))
        XCTAssertFalse(DetailMoreSheetView.shouldShowDeleteButton(item: unmonitoredSeries, hasLocalEpisodes: false))

        XCTAssertEqual(DetailMoreSheetView.monitorTitle(item: monitoredSeries), "Slutt å følge serien")
        XCTAssertEqual(DetailMoreSheetView.monitorIcon(item: monitoredSeries), "bell.fill")
        XCTAssertEqual(DetailMoreSheetView.monitorTitle(item: unmonitoredSeries), "Følg serien")
        XCTAssertEqual(DetailMoreSheetView.monitorIcon(item: unmonitoredSeries), "bell")
        XCTAssertEqual(DetailMoreSheetView.monitorTitle(item: remoteMovie), "Avbryt klargjøring")
        XCTAssertEqual(DetailMoreSheetView.monitorIcon(item: remoteMovie), "arrow.down.circle.fill")
        XCTAssertEqual(DetailMoreSheetView.monitorTitle(item: unmonitoredRemoteMovie), "Gjør klar på forhånd")
        XCTAssertEqual(DetailMoreSheetView.monitorIcon(item: unmonitoredRemoteMovie), "arrow.down.circle")

        XCTAssertEqual(DetailMoreSheetView.deleteTitle(mediaType: "series"), "Slett fra samlingen")
        XCTAssertEqual(DetailMoreSheetView.deleteTitle(mediaType: "movie"), "Slett filmen fra samlingen")
        XCTAssertEqual(DetailMoreSheetView.deleteSeasonTitle(seasonNumber: 0), "Slett Spesialer")
        XCTAssertEqual(DetailMoreSheetView.deleteSeasonTitle(seasonNumber: 2), "Slett sesong 2")

        let specialsDeleteTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: "series:tmdb:100",
            title: "Eksempel",
            scope: .season,
            season: 0
        )
        XCTAssertEqual(specialsDeleteTarget.dialogHeading, "Slett Spesialer")

        XCTAssertEqual(DetailOverviewSheetView.makeFocusableChunks(from: "   \n  "), ["   \n  "])
        XCTAssertEqual(
            DetailOverviewSheetView.makeFocusableChunks(from: "Første avsnitt.\n\nAndre avsnitt."),
            ["Første avsnitt.", "Andre avsnitt."]
        )
        let sentenceA = String(repeating: "a", count: 160)
        let sentenceB = String(repeating: "b", count: 160)
        let longOverview = "\(sentenceA). \(sentenceB)"
        let splitChunks = DetailOverviewSheetView.makeFocusableChunks(from: longOverview)
        XCTAssertEqual(splitChunks, ["\(sentenceA).", sentenceB])

        XCTAssertEqual(DetailOverviewSheetView.maxScrollAreaHeight, 620)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 24), 96)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 96), 96)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 340), 340)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 620), 620)
        XCTAssertEqual(DetailOverviewSheetView.resolvedScrollHeight(contentHeight: 980), 620)
    }

    // MARK: - K-2 (7/7): DetailSeasonsSectionView & Season 0 Specials

    func testDetailSeasonsSelectionOrderSpecialsAndScrollTargeting() {
        XCTAssertFalse(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 6))
        XCTAssertTrue(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 7))
        XCTAssertEqual(DetailSeasonPickerSheetView.gridColumnCount, 3)
        XCTAssertGreaterThanOrEqual(DetailSeasonPickerSheetView.minimumColumnWidth, 280)
        XCTAssertEqual(
            DetailSeasonPickerSheetView.preferredGridWidth,
            LunaTokens.Layout.sheetWideW - LunaTokens.Layout.sheetPadding * 2
        )

        let seasons = [
            TvSeasonSummary(seasonNumber: 1, name: "Season 1", episodeCount: 9, posterUrl: nil, airDate: nil),
            TvSeasonSummary(seasonNumber: 2, name: "Season 2", episodeCount: 10, posterUrl: nil, airDate: nil),
        ]
        XCTAssertEqual(
            DetailSeasonsSectionView.selectedSeasonSummary(seasons: seasons, selectedSeasonNumber: 2)?.seasonNumber,
            2
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.selectedSeasonSummary(seasons: seasons, selectedSeasonNumber: 99)?.seasonNumber,
            1
        )
        XCTAssertNil(DetailSeasonsSectionView.selectedSeasonSummary(seasons: [], selectedSeasonNumber: 1))

        let specialsFirst = [
            TvSeasonSummary(seasonNumber: 0, name: "Specials", episodeCount: 2, posterUrl: nil, airDate: nil),
            TvSeasonSummary(seasonNumber: 1, name: "Season 1", episodeCount: 9, posterUrl: nil, airDate: nil),
            TvSeasonSummary(seasonNumber: 2, name: "Season 2", episodeCount: 10, posterUrl: nil, airDate: nil),
        ]
        XCTAssertEqual(
            DetailSeasonsSectionView.orderedSeasons(specialsFirst).map(\.seasonNumber),
            [1, 2, 0]
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.selectedSeasonSummary(seasons: specialsFirst, selectedSeasonNumber: 99)?.seasonNumber,
            1
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.selectedSeasonSummary(seasons: specialsFirst, selectedSeasonNumber: 0)?.seasonNumber,
            0
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.seasonPickerTrailingMeta(for: specialsFirst),
            "\(LunaCopy.seasonsCount(2)) · inkl. Spesialer"
        )
        let specialsOnly = [specialsFirst[0]]
        XCTAssertEqual(
            DetailSeasonsSectionView.selectedSeasonSummary(seasons: specialsOnly, selectedSeasonNumber: 99)?.seasonNumber,
            0
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.seasonPickerTrailingMeta(for: specialsOnly),
            "Spesialer"
        )

        let ep1 = TvEpisodeCard(itemId: "ep-1", seasonNumber: 2, episodeNumber: 1, title: "E1", watched: true)
        let ep2 = TvEpisodeCard(itemId: "ep-2", seasonNumber: 2, episodeNumber: 2, title: "E2", isUpcoming: true, watched: false)
        let ep3 = TvEpisodeCard(itemId: "ep-3", seasonNumber: 2, episodeNumber: 3, title: "E3", isUpcoming: false, watched: false)
        let episodes = [ep1, ep2, ep3]

        let detailWithNextUp = makeDetail(
            mediaType: "series",
            nextUp: TvNextUpPointer(season: 2, episode: 3)
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.nextEpisodeTargetID(detail: detailWithNextUp, episodes: episodes),
            "ep-3"
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: nil, detail: detailWithNextUp, episodes: episodes),
            "ep-3"
        )
        XCTAssertNil(
            DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: "ep-1", detail: detailWithNextUp, episodes: episodes)
        )
        XCTAssertNil(
            DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: "missing", detail: detailWithNextUp, episodes: episodes)
        )
        XCTAssertEqual(
            DetailSeasonsSectionView.scrollTargetEpisodeID(overrideID: "ep-2", detail: detailWithNextUp, episodes: episodes),
            "ep-2"
        )

        let detailWithoutNextUp = makeDetail(mediaType: "series", nextUp: nil)
        XCTAssertEqual(
            DetailSeasonsSectionView.nextEpisodeTargetID(detail: detailWithoutNextUp, episodes: episodes),
            "ep-3"
        )
        XCTAssertNil(
            DetailSeasonsSectionView.nextEpisodeTargetID(detail: detailWithoutNextUp, episodes: [ep1, ep2])
        )
    }

    // MARK: - SourcePickerSheetView

    @MainActor
    func testSourcePickerDefaultCandidateAndFocusTriggerPolicies() {
        let c1 = makeCandidate(id: "cand-1", isActive: false)
        let c2 = makeCandidate(id: "cand-2", isActive: true)
        let c3 = makeCandidate(id: "cand-3", isActive: false)

        XCTAssertNil(SourcePickerSheetView.preferredDefaultCandidateID(candidates: [], activeCandidateId: "cand-1"))
        XCTAssertEqual(
            SourcePickerSheetView.preferredDefaultCandidateID(candidates: [c1, c2, c3], activeCandidateId: "cand-3"),
            "cand-3"
        )
        XCTAssertEqual(
            SourcePickerSheetView.preferredDefaultCandidateID(candidates: [c1, c2, c3], activeCandidateId: nil),
            "cand-2"
        )
        XCTAssertEqual(
            SourcePickerSheetView.preferredDefaultCandidateID(candidates: [c1, c3], activeCandidateId: "missing"),
            "cand-1"
        )

        XCTAssertTrue(
            SourcePickerSheetView.shouldTriggerDefaultFocus(
                wasLoading: true,
                isLoading: false,
                errorMessage: nil,
                candidates: [c1]
            )
        )
        XCTAssertFalse(
            SourcePickerSheetView.shouldTriggerDefaultFocus(
                wasLoading: false,
                isLoading: false,
                errorMessage: nil,
                candidates: [c1]
            )
        )
        XCTAssertFalse(
            SourcePickerSheetView.shouldTriggerDefaultFocus(
                wasLoading: true,
                isLoading: true,
                errorMessage: nil,
                candidates: [c1]
            )
        )
        XCTAssertFalse(
            SourcePickerSheetView.shouldTriggerDefaultFocus(
                wasLoading: true,
                isLoading: false,
                errorMessage: "Nettverksfeil",
                candidates: [c1]
            )
        )
        XCTAssertFalse(
            SourcePickerSheetView.shouldTriggerDefaultFocus(
                wasLoading: true,
                isLoading: false,
                errorMessage: nil,
                candidates: []
            )
        )

        let pickerSheet = SourcePickerSheetView(
            context: SourcePickerContext(itemId: "movie:tmdb:693134", title: "Dune: Part Two"),
            onSelectCandidate: { _, _, _ in },
            onCancel: {}
        )
        XCTAssertEqual(pickerSheet.context.itemId, "movie:tmdb:693134")
    }

    private func makeCandidate(id: String, isActive: Bool?) -> TvCandidateInfo {
        TvCandidateInfo(
            candidateId: id,
            displayHeadline: "4K HDR10",
            releaseTitle: "Example.2024.2160p",
            source: "nvme",
            tier: "nvme",
            resolution: "2160p",
            videoRangeType: "HDR10",
            dvProfile: nil,
            dvEnhancementLayer: nil,
            audioCodec: "Atmos",
            sizeBytes: 10_000_000_000,
            tvScore: 950,
            isActive: isActive,
            explanationChips: nil,
            releaseGroup: nil,
            isNorwegian: false
        )
    }

    private func makeDetail(
        mediaType: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        runtimeSeconds: Double? = nil,
        genres: [String]? = nil,
        imdbRating: Double? = nil,
        imdbVotes: Int? = nil,
        badges: [String]? = nil,
        nextAirDateBadge: String? = nil,
        monitored: Bool? = nil,
        availability: TvAvailabilityInfo? = nil,
        nextUp: TvNextUpPointer? = nil,
        seasons: [TvSeasonSummary]? = nil
    ) -> TvItemDetail {
        TvItemDetail(
            itemId: "\(mediaType):tmdb:100",
            mediaType: mediaType,
            ids: TvMediaIds(tmdb: 100),
            title: "Eksempeltittel",
            originalTitle: originalTitle,
            year: year,
            runtimeSeconds: runtimeSeconds,
            genres: genres,
            imdbRating: imdbRating,
            imdbVotes: imdbVotes,
            badges: badges,
            nextAirDateBadge: nextAirDateBadge,
            inWatchlist: false,
            watched: false,
            monitored: monitored,
            availability: availability,
            nextUp: nextUp,
            seasons: seasons
        )
    }
}
