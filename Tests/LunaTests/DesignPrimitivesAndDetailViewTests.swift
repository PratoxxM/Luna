import Foundation
import SwiftUI
import XCTest
@testable import Luna

final class DesignPrimitivesAndDetailViewTests: XCTestCase {
    // MARK: - F-D3-2: LunaPillButton trailing dot color

    func testPillButtonTrailingDotColorUsesMoonlightWhenUnfocusedAndOnAccentWhenFocused() {
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: false),
            LunaTheme.moonlight
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: false, prominence: .glassPill, accent: .emerald),
            LunaTheme.moonlight
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: false, prominence: .glassPill, accent: .warn),
            LunaTheme.warn
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: false, prominence: .glassPill, accent: .coral),
            LunaTheme.coral
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: true),
            LunaTokens.Text.onAccent
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: true, prominence: .glassPill, accent: .coral),
            LunaTheme.coral
        )
        XCTAssertEqual(
            LunaPillButton.resolveTrailingDotColor(isFocused: true, prominence: .primary, accent: .coral),
            LunaTokens.Text.onAccent
        )
    }

    // MARK: - K-2 (1/7): LunaBadges

    @MainActor
    func testLunaBadgesProgressBarAndTierDotBehavior() {
        let labelBadge = LunaArtBadge(label: "Fra iPhone", dotColor: LunaTheme.amber)
        XCTAssertEqual(labelBadge.label, "Fra iPhone")
        XCTAssertNil(labelBadge.systemImage)
        XCTAssertEqual(labelBadge.dotColor, LunaTheme.amber)
        XCTAssertEqual(labelBadge.iconColor, LunaTheme.linen)

        let watchedBadge = LunaArtBadge.watchedCheckmark()
        XCTAssertNil(watchedBadge.label)
        XCTAssertEqual(watchedBadge.systemImage, "checkmark")
        XCTAssertNil(watchedBadge.dotColor)
        XCTAssertEqual(watchedBadge.iconColor, LunaTheme.emerald)

        XCTAssertFalse(LunaCardProgressBar(percent: nil, trackWidth: 400).isVisible)
        XCTAssertFalse(LunaCardProgressBar(percent: 2.0, trackWidth: 400).isVisible)
        XCTAssertTrue(LunaCardProgressBar(percent: 2.1, trackWidth: 400).isVisible)
        XCTAssertTrue(LunaCardProgressBar(percent: 94.9, trackWidth: 400).isVisible)
        XCTAssertFalse(LunaCardProgressBar(percent: 95.0, trackWidth: 400).isVisible)

        let clampedBar = LunaCardProgressBar(percent: 140, trackWidth: -10)
        XCTAssertEqual(clampedBar.percent, 100)
        XCTAssertEqual(clampedBar.trackWidth, 0)
        XCTAssertEqual(LunaCardProgressBar.filledWidth(percent: 50, trackWidth: 480), 240, accuracy: 0.01)
        XCTAssertEqual(LunaCardProgressBar.filledWidth(percent: nil, trackWidth: 480), 0, accuracy: 0.01)
        XCTAssertEqual(LunaCardProgressBar.filledWidth(percent: 150, trackWidth: -20), 0, accuracy: 0.01)

        let nvmeAvail = TvAvailabilityInfo(state: "instant", tier: "nvme")
        let ssdAvail = TvAvailabilityInfo(state: "instant", tier: "ssd")
        let archiveAvail = TvAvailabilityInfo(state: "instant", tier: "archive")
        let vfsAvail = TvAvailabilityInfo(state: "remote", tier: "vfs")
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: nvmeAvail), .nvme)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: ssdAvail), .nvme)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: archiveAvail), .archive)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: vfsAvail), .none)
        let dotView = LunaTierDotView(availability: nvmeAvail)
        XCTAssertTrue(dotView.availability.isLocalNvme)
    }

    // MARK: - K-2 (2/7): LunaListRow

    @MainActor
    func testLunaListRowColorResolversAndRowPrimitives() {
        XCTAssertEqual(
            LunaListRow.resolveLeadingIconColor(isDestructive: true, isFocused: false),
            LunaTheme.coral
        )
        XCTAssertEqual(
            LunaListRow.resolveLeadingIconColor(isDestructive: false, isFocused: true),
            LunaTheme.linen
        )
        XCTAssertEqual(
            LunaListRow.resolveLeadingIconColor(isDestructive: false, isFocused: false),
            LunaTheme.moonlight
        )

        XCTAssertEqual(
            LunaListRow.resolveTitleColor(isDestructive: true, dimUnfocusedTitle: true, isFocused: false, isSelected: false),
            LunaTheme.coral
        )
        XCTAssertEqual(
            LunaListRow.resolveTitleColor(isDestructive: false, dimUnfocusedTitle: true, isFocused: false, isSelected: false),
            LunaTheme.moonlight
        )
        XCTAssertEqual(
            LunaListRow.resolveTitleColor(isDestructive: false, dimUnfocusedTitle: true, isFocused: false, isSelected: true),
            LunaTheme.linen
        )
        XCTAssertEqual(
            LunaListRow.resolveTitleColor(isDestructive: false, dimUnfocusedTitle: true, isFocused: true, isSelected: false),
            LunaTheme.linen
        )

        XCTAssertEqual(
            LunaListRow.resolveTrailingColor(trailingTextProminent: true, isDestructive: true, isFocused: false),
            LunaTheme.coral
        )
        XCTAssertEqual(
            LunaListRow.resolveTrailingColor(trailingTextProminent: true, isDestructive: false, isFocused: false),
            LunaTheme.linen
        )
        XCTAssertEqual(
            LunaListRow.resolveTrailingColor(trailingTextProminent: false, isDestructive: false, isFocused: true),
            LunaTheme.moonlight
        )
        XCTAssertEqual(
            LunaListRow.resolveTrailingColor(trailingTextProminent: false, isDestructive: false, isFocused: false),
            LunaTheme.muted
        )

        let header = LunaSectionHeader(title: "Seksjon", metaText: "4 titler")
        let plainHeader = LunaSectionHeader(title: "Enkel")
        let group = LunaListGroup(showsSurface: false) { EmptyView() }
        let divider = LunaListDivider()
        let info = LunaInfoRow(title: "Server", value: "lunacore.local")
        let control = LunaControlRow(title: "Lyd", subtitle: "TrueHD", axis: .vertical) { EmptyView() }
        let row = LunaListRow(title: "Valg", subtitle: "Detalj", isSelected: true, showsChevron: true) {}

        XCTAssertEqual(header.title, "Seksjon")
        XCTAssertEqual(plainHeader.title, "Enkel")
        XCTAssertFalse(group.showsSurface)
        let _ = divider
        XCTAssertEqual(info.title, "Server")
        XCTAssertEqual(control.axis, .vertical)
        XCTAssertTrue(row.isSelected)
    }

    // MARK: - K-2 (3/7): LunaSheetContainer

    @MainActor
    func testLunaSheetContainerWidthsTitleFontAndDefaults() {
        XCTAssertEqual(LunaSheetWidth.narrow.maxWidth, LunaTokens.Layout.sheetNarrowW)
        XCTAssertEqual(LunaSheetWidth.wide.maxWidth, LunaTokens.Layout.sheetWideW)
        XCTAssertEqual(
            LunaSheetContainer<EmptyView>.resolveTitleFont(usesSerif: true),
            LunaTheme.Font.titleSerif
        )
        XCTAssertEqual(
            LunaSheetContainer<EmptyView>.resolveTitleFont(usesSerif: false),
            LunaTheme.Font.pageTitle
        )

        var closed = false
        let sheet = LunaSheetContainer(
            title: "Velg sesong",
            titleUsesSerif: true,
            subtitle: "Severance",
            trailingMeta: "2 sesonger",
            width: .wide,
            maxHeight: 860,
            onClose: { closed = true }
        ) {
            EmptyView()
        }
        XCTAssertEqual(sheet.title, "Velg sesong")
        XCTAssertTrue(sheet.titleUsesSerif)
        XCTAssertEqual(sheet.width, .wide)
        XCTAssertEqual(sheet.maxHeight, 860)
        sheet.onClose?()
        XCTAssertTrue(closed)
    }

    // MARK: - K-2 (4/7): LunaInlineStateViews

    @MainActor
    func testLunaInlineStateViewsTonesAndDefaults() {
        XCTAssertEqual(LunaToastTone.ok.dotColor, LunaTheme.statusOk)
        XCTAssertEqual(LunaToastTone.warn.dotColor, LunaTheme.warn)
        XCTAssertEqual(LunaToastTone.danger.dotColor, LunaTheme.danger)

        XCTAssertFalse(LunaToast.shouldDisplayMessage(nil))
        XCTAssertFalse(LunaToast.shouldDisplayMessage(""))
        XCTAssertTrue(LunaToast.shouldDisplayMessage("Undertekst synkronisert"))

        let loading = LunaLoadingRow(message: "Henter episoder…")
        let empty = LunaEmptyState(headline: "Tomt", actionTitle: "Utforsk", actionSymbol: "film") {}
        let error = LunaInlineError(message: "Kunne ikke laste") {}
        let toast = LunaToast(message: "Lagret")
        let statusPill = PlayerStatusPill(message: "Norsk tale aktivert")

        XCTAssertEqual(loading.message, "Henter episoder…")
        XCTAssertEqual(empty.headline, "Tomt")
        XCTAssertEqual(empty.actionProminence, .glassPill)
        XCTAssertEqual(error.retryTitle, "Prøv igjen")
        XCTAssertEqual(toast.tone, .danger)
        XCTAssertEqual(statusPill.tone, .ok)
        XCTAssertFalse(statusPill.showsSpinner)
    }

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
    }

    // MARK: - K-2 (7/7): DetailSeasonsSectionView

    func testDetailSeasonsSelectionNextEpisodeAndScrollTargeting() {
        XCTAssertFalse(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 6))
        XCTAssertTrue(DetailSeasonsSectionView.usesSeasonPickerSheet(seasonCount: 7))

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

    private func makeDetail(
        mediaType: String,
        year: Int? = nil,
        runtimeSeconds: Double? = nil,
        genres: [String]? = nil,
        imdbRating: Double? = nil,
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
            year: year,
            runtimeSeconds: runtimeSeconds,
            genres: genres,
            imdbRating: imdbRating,
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
