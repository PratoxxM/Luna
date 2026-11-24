import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LunaCore

/// Extracted Linux-native shelf indexing, sideload-safe storage, preview CLI, and model/decode target tests.
final class CatalogShelfAndStorageLinuxTests: XCTestCase {
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

        let seriesCatCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "catalog-series"])
        XCTAssertEqual(seriesCatCfg?.screen, .catalogSeries)
        XCTAssertEqual(seriesCatCfg?.screen.isPlayerScreen, false)

        let movieDetailCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "detail-movie"])
        XCTAssertEqual(movieDetailCfg?.screen, .detailMovie)
        XCTAssertEqual(movieDetailCfg?.screen.isPlayerScreen, false)

        let sourcePickerCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "detail-source-picker"])
        XCTAssertEqual(sourcePickerCfg?.screen, .detailSourcePicker)
        XCTAssertEqual(sourcePickerCfg?.screen.isPlayerScreen, false)

        let osdCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-osd"])
        XCTAssertEqual(osdCfg?.screen, .playerOsd)
        XCTAssertEqual(osdCfg?.screen.isPlayerScreen, true)

        let scrubCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-scrub"])
        XCTAssertEqual(scrubCfg?.screen, .playerScrub)
        XCTAssertEqual(scrubCfg?.screen.isPlayerScreen, true)

        let skipIntroCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-skip-intro"])
        XCTAssertEqual(skipIntroCfg?.screen, .playerSkipIntro)
        XCTAssertEqual(skipIntroCfg?.screen.isPlayerScreen, true)

        let nextEpCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "player-next-episode"])
        XCTAssertEqual(nextEpCfg?.screen, .playerNextEpisode)
        XCTAssertEqual(nextEpCfg?.screen.isPlayerScreen, true)

        for target in PreviewScreenTarget.allCases {
            let roundtrip = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", target.rawValue])
            XCTAssertEqual(roundtrip?.screen, target)
        }
    }

    func testCrossRowSeriesDeduplicationHidesEmptyActiveSeriesShelfAndPreservesDiscoveryShelves() {
        let lykkelandContinue = TvMediaCard(
            itemId: "episode:tmdb:79291:s4:e6",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 79291),
            title: "Lykkeland",
            origin: "phone",
            directPlayTarget: TvDirectPlayTarget(
                itemId: "episode:tmdb:79291:s4:e6",
                mediaType: "episode",
                tmdbId: 79291,
                season: 4,
                episode: 6
            )
        )
        let severanceUpcoming = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance"
        )
        let lykkelandActive = TvMediaCard(
            itemId: "series:tmdb:79291",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 79291),
            title: "Lykkeland"
        )
        let severanceActive = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance"
        )
        let andorActive = TvMediaCard(
            itemId: "series:tmdb:83867",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 83867),
            title: "Andor"
        )
        let duneMovie = TvMediaCard(
            itemId: "movie:tmdb:693134",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 693134),
            title: "Dune: Part Two"
        )

        XCTAssertEqual(CatalogShelfIndexer.seriesDeduplicationKey(for: lykkelandContinue), "series:tmdb:79291")
        XCTAssertEqual(CatalogShelfIndexer.seriesDeduplicationKey(for: lykkelandActive), "series:tmdb:79291")
        XCTAssertNil(CatalogShelfIndexer.seriesDeduplicationKey(for: duneMovie))

        // 1. Mixed active_series row filters out Lykkeland & Severance (already in Fortsett/Kommende), keeping Andor
        let partialPayload = TvHomeResponse(
            ok: true,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            rows: [
                TvShelfRow(
                    rowId: "medialogg-continue",
                    title: "Fortsett å se",
                    rowStyle: "continue_backdrop",
                    sourceKind: "system_continue",
                    items: [lykkelandContinue, duneMovie]
                ),
                TvShelfRow(
                    rowId: "upcoming-episodes",
                    title: "Kommende episoder",
                    rowStyle: "upcoming_backdrop",
                    sourceKind: "system_upcoming",
                    items: [severanceUpcoming]
                ),
                TvShelfRow(
                    rowId: "new-episodes",
                    title: "Nye episoder",
                    rowStyle: "poster",
                    sourceKind: "active_series",
                    items: [lykkelandActive, severanceActive, andorActive]
                ),
                TvShelfRow(
                    rowId: "atmospheric-films",
                    title: "Populært nå",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    items: [duneMovie, severanceActive]
                ),
            ]
        )

        let partialRows = CatalogShelfIndexer.prepareVisibleRows(from: partialPayload)
        XCTAssertEqual(partialRows.map(\.rowId), ["medialogg-continue", "upcoming-episodes", "new-episodes", "atmospheric-films"])
        XCTAssertEqual(partialRows[2].items.map(\.itemId), ["series:tmdb:83867"])
        // Discovery row "Populært nå" stays untouched
        XCTAssertEqual(partialRows[3].items.map(\.itemId), ["movie:tmdb:693134", "series:tmdb:95396"])

        // 2. When all items in Nye episoder are already shown in Fortsett / Kommende, the empty row is dropped
        let fullyOverlappingPayload = TvHomeResponse(
            ok: true,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            rows: [
                TvShelfRow(
                    rowId: "medialogg-continue",
                    title: "Fortsett",
                    rowStyle: "continue_backdrop",
                    sourceKind: "system_continue",
                    items: [lykkelandContinue]
                ),
                TvShelfRow(
                    rowId: "upcoming-episodes",
                    title: "Kommende episoder",
                    rowStyle: "upcoming_backdrop",
                    sourceKind: "system_upcoming",
                    items: [severanceUpcoming]
                ),
                TvShelfRow(
                    rowId: "new-episodes",
                    title: "Nye episoder",
                    rowStyle: "poster",
                    sourceKind: "active_series",
                    items: [lykkelandActive, severanceActive]
                ),
                TvShelfRow(
                    rowId: "atmospheric-films",
                    title: "Populært nå",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    items: [duneMovie]
                ),
            ]
        )

        let collapsedRows = CatalogShelfIndexer.prepareVisibleRows(from: fullyOverlappingPayload)
        XCTAssertEqual(collapsedRows.map(\.rowId), ["medialogg-continue", "upcoming-episodes", "atmospheric-films"])
    }

    func testHardwareCalibratedArtworkDecodeTargetsAndIsolatedRecentSearches() {
        XCTAssertEqual(ArtworkDecodeTargets.posterCardMaxPixelSize, 820)
        XCTAssertEqual(ArtworkDecodeTargets.backdropCardMaxPixelSize, 1092)
        XCTAssertEqual(ArtworkDecodeTargets.episodeCardMaxPixelSize, 882)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .high2026), 2880)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .standard), 2400)

        let suiteA = "luna.v1.search.a.\(UUID().uuidString)"
        let suiteB = "luna.v1.search.b.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsA), [])
        _ = SideloadSafeStorage.recordRecentSearch("  Dune  ", defaults: defaultsA)
        _ = SideloadSafeStorage.recordRecentSearch("Lykkeland", defaults: defaultsA)
        let deduped = SideloadSafeStorage.recordRecentSearch("dune", defaults: defaultsA)
        XCTAssertEqual(deduped, ["dune", "Lykkeland"])
        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsB), [])

        SideloadSafeStorage.clearRecentSearches(defaults: defaultsA)
        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsA), [])
    }
}
