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

    // MARK: - M2: Focus Performance, Memoization, Filter Bar & Card FocusSurface Compatibility

    @MainActor
    func testArtworkURLMemoBoxCachesRepeatedResolutionsAndInvalidatesOnInputChange() throws {
        let memo = ArtworkURLMemoBox()
        let baseA = try XCTUnwrap(URL(string: "http://lunacore-a.local:8090"))
        let baseB = try XCTUnwrap(URL(string: "http://lunacore-b.local:8090"))

        var resolverCalls = 0
        let first = memo.resolve(path: "/api/tv/v2/img/card/1", baseURL: baseA, target: .poster2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-a.local:8090/api/tv/v2/img/card/1")
        }
        let repeated = memo.resolve(path: "/api/tv/v2/img/card/1", baseURL: baseA, target: .poster2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-a.local:8090/api/tv/v2/img/card/unexpected")
        }
        XCTAssertEqual(resolverCalls, 1)
        XCTAssertEqual(first, repeated)

        _ = memo.resolve(path: "/api/tv/v2/img/card/2", baseURL: baseA, target: .poster2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-a.local:8090/api/tv/v2/img/card/2")
        }
        XCTAssertEqual(resolverCalls, 2)

        _ = memo.resolve(path: "/api/tv/v2/img/card/2", baseURL: baseB, target: .poster2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-b.local:8090/api/tv/v2/img/card/2")
        }
        XCTAssertEqual(resolverCalls, 3)

        _ = memo.resolve(path: "/api/tv/v2/img/card/2", baseURL: baseB, target: .landscape2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-b.local:8090/api/tv/v2/img/card/2")
        }
        XCTAssertEqual(resolverCalls, 4)

        let clientMemo = ArtworkURLMemoBox()
        XCTAssertNil(clientMemo.resolve(path: "/api/tv/v2/img/card/9", client: nil, target: .poster2x))

        let clientA = LunaCoreClient(
            baseURL: baseA,
            deviceID: "tv-m2-test",
            deviceToken: "tok",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: false
        )
        let clientB = LunaCoreClient(
            baseURL: baseB,
            deviceID: "tv-m2-test",
            deviceToken: "tok",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: false
        )
        let resolvedA = clientMemo.resolve(path: "/api/tv/v2/img/card/9", client: clientA, target: .poster2x)
        let resolvedARepeat = clientMemo.resolve(path: "/api/tv/v2/img/card/9", client: clientA, target: .poster2x)
        let resolvedB = clientMemo.resolve(path: "/api/tv/v2/img/card/9", client: clientB, target: .poster2x)
        XCTAssertEqual(resolvedA?.host, "lunacore-a.local")
        XCTAssertEqual(resolvedA, resolvedARepeat)
        XCTAssertEqual(resolvedB?.host, "lunacore-b.local")
    }

    func testCachedArtworkShouldSkipAsyncLoadRequiresExactEpochValidMatch() {
        XCTAssertTrue(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: "movie-1#px820",
                currentMemoryEpoch: 3,
                retainDuringPlayback: false,
                loadedKey: nil,
                loadedIsExact: false,
                loadedEpoch: 0,
                syncHitKey: "movie-1#px820",
                syncHitIsExact: true,
                syncHitEpoch: 3
            )
        )
        XCTAssertTrue(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: "movie-1#px820",
                currentMemoryEpoch: 3,
                retainDuringPlayback: false,
                loadedKey: "movie-1#px820",
                loadedIsExact: true,
                loadedEpoch: 3,
                syncHitKey: nil,
                syncHitIsExact: false,
                syncHitEpoch: 0
            )
        )
        XCTAssertFalse(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: nil,
                currentMemoryEpoch: 3,
                retainDuringPlayback: false,
                loadedKey: "movie-1#px820",
                loadedIsExact: true,
                loadedEpoch: 3,
                syncHitKey: "movie-1#px820",
                syncHitIsExact: true,
                syncHitEpoch: 3
            )
        )
        XCTAssertFalse(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: "movie-1#px820",
                currentMemoryEpoch: 4,
                retainDuringPlayback: false,
                loadedKey: "movie-1#px820",
                loadedIsExact: true,
                loadedEpoch: 3,
                syncHitKey: "movie-1#px820",
                syncHitIsExact: true,
                syncHitEpoch: 3
            )
        )
        XCTAssertTrue(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: "movie-1#px820",
                currentMemoryEpoch: 4,
                retainDuringPlayback: true,
                loadedKey: "movie-1#px820",
                loadedIsExact: true,
                loadedEpoch: 3,
                syncHitKey: nil,
                syncHitIsExact: false,
                syncHitEpoch: 0
            )
        )
        XCTAssertFalse(
            CachedArtworkView.shouldSkipAsyncLoad(
                targetImageKey: "movie-1#px820",
                currentMemoryEpoch: 3,
                retainDuringPlayback: false,
                loadedKey: nil,
                loadedIsExact: false,
                loadedEpoch: 0,
                syncHitKey: "movie-1#px820",
                syncHitIsExact: false,
                syncHitEpoch: 3
            )
        )
    }

    @MainActor
    func testCatalogFilterBarAndCardFocusSurfaceCompatibility() throws {
        XCTAssertEqual(CatalogFilterBarView.trailingMaskFadeWidth, 56)
        let genreJSON = Data(#"{"slug":"drama","label":"Drama","browsePath":"/api/tv/v2/catalog/movie?genre=drama"}"#.utf8)
        let chip = try JSONDecoder().decode(TvGenreChip.self, from: genreJSON)
        let filterBar = CatalogFilterBarView(
            categoryTitle: "Filmer",
            availableGenres: [chip],
            selectedSort: .constant("popular"),
            localOnly: .constant(false),
            unwatchedOnly: .constant(false),
            selectedGenreSlug: .constant(nil),
            selectedGenreLabel: .constant(nil),
            entryFocusNonce: 0,
            isEntryActive: true,
            onScrollToTop: {},
            onMoveDown: {}
        )
        XCTAssertEqual(filterBar.categoryTitle, "Filmer")

        let baseURL = try XCTUnwrap(URL(string: "http://lunacore.local:8090"))
        let client = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "tv-m2-test",
            deviceToken: "tok",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: false
        )
        let card = TvMediaCard(
            itemId: "movie:tmdb:693134",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 693134),
            title: "Dune: Part Two",
            year: 2024,
            posterUrl: "/api/tv/v2/img/card/693134",
            cardBackdropUrl: "/api/tv/v2/img/backdrop/693134"
        )
        let poster = PosterCardView(card: card, client: client, showRestingTitle: true, onSelect: {})
        let backdrop = BackdropCardView(card: card, client: client, variant: .continueWatching, onPrimaryAction: {})
        XCTAssertEqual(poster.card.itemId, "movie:tmdb:693134")
        XCTAssertEqual(backdrop.variant, .continueWatching)
        XCTAssertEqual(PosterCardView.shelfCaptionSpacing, 10)
        XCTAssertEqual(PosterCardView.shelfCaptionHeight, 52)
        XCTAssertEqual(PosterCardView.gridCaptionSpacing, 14)
        XCTAssertEqual(PosterCardView.gridCaptionHeight, 60)

        let _ = Color.clear.lunaCardLampGlow(isFocused: true)
        let _ = Color.clear.lunaCardLampGlow(isFocused: false, cornerRadius: LunaTheme.posterRadius)
        let _ = Color.clear.lunaFocusCaptionReveal(isVisible: true, isFocused: true)
        let _ = Color.clear.lunaFocusCaptionReveal(isVisible: true, isFocused: false, animate: false)
        let _ = Color.clear.lunaFocusSurface(.card, isFocused: true, cornerRadius: LunaTheme.cardRadius)
        let _ = Color.clear.lunaFocusSurface(.control, isFocused: true, cornerRadius: LunaTokens.Radius.pill)
        let _ = Color.clear.lunaFocusSurface(.control, isFocused: true, cornerRadius: LunaTokens.Radius.pill, accentColor: LunaTheme.coral)
        let _ = Color.clear.lunaFocusSurface(.listRow, isFocused: true)
    }
}
