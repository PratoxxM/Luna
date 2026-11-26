import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deterministic offline Lampelys catalog, library, 28-season detail, and playback fixtures
/// used exclusively when `--preview-screen` is passed at launch.
enum PreviewMockFixtures {
    static let previewHost = "preview.luna.invalid"
    static let previewBaseURL = URL(string: "https://\(previewHost)")!
    static let previewRoomName = "Stua"
    static let previewHardwareProfile = HardwareProfilePreset.hdr10512.rawValue

    static func makeClient() -> LunaCoreClient {
        PreviewMockURLProtocol.installIfNeeded()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreviewMockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LunaCoreClient(
            baseURL: previewBaseURL,
            deviceID: "luna-preview-appletv",
            deviceToken: "preview-device-token",
            roomName: previewRoomName,
            hardwareProfile: previewHardwareProfile,
            allowSelfSignedLanTLS: true,
            appVersion: "3.0.0",
            osVersion: "tvOS 26.0",
            session: session,
            imageSession: session,
            externalImageSession: session
        )
    }

    static func prewarmHomeCache() {
        guard let raw = try? LunaCoreClient.encodeJSON(homeResponse) else { return }
        DiskSWRStore.saveHomeInBackground(
            rawPayloadData: raw,
            etag: "\"preview-home-v2\"",
            serverHost: previewHost,
            roomName: previewRoomName,
            hardwareProfile: previewHardwareProfile,
            decodedPayload: homeResponse
        )
    }

    // MARK: - Media Cards

    static let lykkelandCard = TvMediaCard(
        itemId: "series:tmdb:79291",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 79291, imdb: "tt8177564"),
        title: "Lykkeland",
        year: 2018,
        posterUrl: "/preview-art/ochre-poster.png",
        backdropUrl: "/preview-art/ochre-backdrop.png",
        cardBackdropUrl: "/preview-art/ochre-backdrop.png",
        dominantColor: "#2d1d12",
        imdbRating: 8.1,
        badges: ["4K", "Dolby Vision", "Atmos"],
        inWatchlist: true,
        episodeCode: "S04E06",
        episodeTitle: "Søndagsbarn",
        origin: "phone",
        originLabel: "Fra iPhone",
        directPlayTarget: TvDirectPlayTarget(
            itemId: "episode:tmdb:79291:s4:e6",
            mediaType: "episode",
            tmdbId: 79291,
            season: 4,
            episode: 6,
            startPositionSeconds: 1390,
            mode: "resume"
        ),
        nextUp: TvNextUpPointer(season: 4, episode: 6),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 1390, durationSeconds: 3120, percent: 44.5, season: 4, episode: 6, watched: false)
    )

    static let dunePartTwoCard = TvMediaCard(
        itemId: "movie:tmdb:693134",
        mediaType: "movie",
        ids: TvMediaIds(tmdb: 693134, imdb: "tt15239678"),
        title: "Dune: Part Two",
        year: 2024,
        posterUrl: "/preview-art/sand-poster.png",
        backdropUrl: "/preview-art/sand-backdrop.png",
        cardBackdropUrl: "/preview-art/sand-backdrop.png",
        dominantColor: "#2a1c10",
        imdbRating: 8.5,
        badges: ["4K", "HDR10+", "TrueHD Atmos"],
        inWatchlist: true,
        contextSubtitle: "1 t 12 min igjen",
        directPlayTarget: TvDirectPlayTarget(
            itemId: "movie:tmdb:693134",
            mediaType: "movie",
            tmdbId: 693134,
            startPositionSeconds: 5640,
            mode: "resume"
        ),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 5640, durationSeconds: 9960, percent: 56.6, watched: false)
    )

    static let severanceCard = TvMediaCard(
        itemId: "series:tmdb:95396",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 95396, imdb: "tt11280740"),
        title: "Severance",
        year: 2022,
        posterUrl: "/preview-art/navy-poster.png",
        backdropUrl: "/preview-art/navy-backdrop.png",
        cardBackdropUrl: "/preview-art/navy-backdrop.png",
        dominantColor: "#141d2e",
        imdbRating: 8.7,
        badges: ["4K", "Dolby Vision", "Atmos"],
        inWatchlist: true,
        episodeCode: "S02E04",
        episodeTitle: "Woe's Hollow",
        origin: "tonight",
        originLabel: "I kveld",
        directPlayTarget: TvDirectPlayTarget(
            itemId: "episode:tmdb:95396:s2:e4",
            mediaType: "episode",
            tmdbId: 95396,
            season: 2,
            episode: 4,
            startPositionSeconds: 1122,
            mode: "resume"
        ),
        nextUp: TvNextUpPointer(season: 2, episode: 4),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 1122, durationSeconds: 3180, percent: 35.3, season: 2, episode: 4, watched: false)
    )

    static let luksusfellenCard = TvMediaCard(
        itemId: "series:tmdb:246810",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 246810, imdb: "tt1298765"),
        title: "Luksusfellen",
        year: 2008,
        posterUrl: "/preview-art/teal-poster.png",
        backdropUrl: "/preview-art/teal-backdrop.png",
        cardBackdropUrl: "/preview-art/teal-backdrop.png",
        dominantColor: "#152726",
        imdbRating: 7.8,
        badges: ["4K", "Dolby Vision", "HDR10+", "Atmos"],
        inWatchlist: false,
        episodeCode: "S28E01",
        nextUp: TvNextUpPointer(season: 28, episode: 1),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart")
    )

    static let catalogMovies: [TvMediaCard] = [
        dunePartTwoCard,
        TvMediaCard(
            itemId: "movie:tmdb:426063",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 426063, imdb: "tt5040012"),
            title: "Nosferatu",
            year: 2024,
            posterUrl: "/preview-art/aubergine-poster.png",
            backdropUrl: "/preview-art/aubergine-backdrop.png",
            dominantColor: "#22182b",
            imdbRating: 7.7,
            badges: ["4K", "HDR10+"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:335984",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 335984, imdb: "tt1856101"),
            title: "Blade Runner 2049",
            year: 2017,
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 8.0,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:872585",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 872585, imdb: "tt15398776"),
            title: "Oppenheimer",
            year: 2023,
            posterUrl: "/preview-art/ochre-poster.png",
            backdropUrl: "/preview-art/ochre-backdrop.png",
            dominantColor: "#2a1c10",
            imdbRating: 8.3,
            badges: ["4K", "HDR10"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:539972",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 539972, imdb: "tt1160419"),
            title: "Verdens verste menneske",
            year: 2021,
            posterUrl: "/preview-art/crimson-poster.png",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            dominantColor: "#2a1216",
            imdbRating: 7.8,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:157336",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 157336, imdb: "tt0816692"),
            title: "Interstellar",
            year: 2014,
            posterUrl: "/preview-art/navy-poster.png",
            backdropUrl: "/preview-art/navy-backdrop.png",
            dominantColor: "#141d2e",
            imdbRating: 8.7,
            badges: ["4K", "HDR10"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:27205",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 27205),
            title: "Kon-Tiki",
            year: 2012,
            posterUrl: "/preview-art/sand-poster.png",
            backdropUrl: "/preview-art/sand-backdrop.png",
            dominantColor: "#2d1d12",
            imdbRating: 7.2,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:301337",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 301337),
            title: "Bølgen",
            year: 2015,
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 6.7,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:414906",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 414906),
            title: "The Batman",
            year: 2022,
            posterUrl: "/preview-art/aubergine-poster.png",
            backdropUrl: "/preview-art/aubergine-backdrop.png",
            dominantColor: "#22182b",
            imdbRating: 7.8,
            badges: ["4K", "Dolby Vision"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:tmdb:329865",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 329865),
            title: "Arrival",
            year: 2016,
            posterUrl: "/preview-art/navy-poster.png",
            backdropUrl: "/preview-art/navy-backdrop.png",
            dominantColor: "#141d2e",
            imdbRating: 7.9,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
    ]

    static let seriesCards: [TvMediaCard] = [
        lykkelandCard,
        severanceCard,
        luksusfellenCard,
        TvMediaCard(
            itemId: "series:tmdb:83867",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 83867, imdb: "tt9253284"),
            title: "Andor",
            year: 2022,
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 8.4,
            badges: ["4K", "Dolby Vision"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:tmdb:126308",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 126308),
            title: "Shōgun",
            year: 2024,
            posterUrl: "/preview-art/crimson-poster.png",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            dominantColor: "#2a1216",
            imdbRating: 8.6,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:tmdb:136315",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 136315),
            title: "The Bear",
            year: 2022,
            posterUrl: "/preview-art/ochre-poster.png",
            backdropUrl: "/preview-art/ochre-backdrop.png",
            dominantColor: "#2d1d12",
            imdbRating: 8.5,
            badges: ["4K", "HDR10+"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "series:tmdb:214592",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 214592),
            title: "Makta",
            year: 2023,
            posterUrl: "/preview-art/sand-poster.png",
            backdropUrl: "/preview-art/sand-backdrop.png",
            dominantColor: "#2d1d12",
            imdbRating: 8.3,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:tmdb:124834",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 124834),
            title: "Pørni",
            year: 2021,
            posterUrl: "/preview-art/crimson-poster.png",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            dominantColor: "#2a1216",
            imdbRating: 8.1,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:tmdb:76331",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 76331),
            title: "Succession",
            year: 2018,
            posterUrl: "/preview-art/navy-poster.png",
            backdropUrl: "/preview-art/navy-backdrop.png",
            dominantColor: "#141d2e",
            imdbRating: 8.8,
            badges: ["4K", "Dolby Vision", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:tmdb:87108",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 87108),
            title: "Chernobyl",
            year: 2019,
            posterUrl: "/preview-art/aubergine-poster.png",
            backdropUrl: "/preview-art/aubergine-backdrop.png",
            dominantColor: "#22182b",
            imdbRating: 9.3,
            badges: ["4K", "HDR10", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
    ]

    static let libraryLocalMovies: [TvMediaCard] = Array(catalogMovies.prefix(8))
    static let libraryLocalSeries: [TvMediaCard] = Array(seriesCards.prefix(3))
    static let libraryLocalCards: [TvMediaCard] = libraryLocalMovies + libraryLocalSeries

    static var genreChips: [TvGenreChip] {
        [
            TvGenreChip(slug: "norsk", label: "Norsk", icon: nil, accentColor: nil, tmdbGenreIds: nil, browsePath: "/api/tv/v2/catalog/movies?genre=norsk", catalogPath: nil),
            TvGenreChip(slug: "drama", label: "Drama", icon: nil, accentColor: nil, tmdbGenreIds: [18], browsePath: "/api/tv/v2/catalog/movies?genre=drama", catalogPath: nil),
            TvGenreChip(slug: "komedie", label: "Komedie", icon: nil, accentColor: nil, tmdbGenreIds: [35], browsePath: "/api/tv/v2/catalog/movies?genre=komedie", catalogPath: nil),
            TvGenreChip(slug: "sci-fi", label: "Sci-Fi & Fantasy", icon: nil, accentColor: nil, tmdbGenreIds: [878], browsePath: "/api/tv/v2/catalog/movies?genre=sci-fi", catalogPath: nil),
            TvGenreChip(slug: "thriller", label: "Thriller & Spenning", icon: nil, accentColor: nil, tmdbGenreIds: [53], browsePath: "/api/tv/v2/catalog/movies?genre=thriller", catalogPath: nil),
            TvGenreChip(slug: "action", label: "Action & Eventyr", icon: nil, accentColor: nil, tmdbGenreIds: [28], browsePath: "/api/tv/v2/catalog/movies?genre=action", catalogPath: nil),
            TvGenreChip(slug: "krim", label: "Krim & Mysterier", icon: nil, accentColor: nil, tmdbGenreIds: [80], browsePath: "/api/tv/v2/catalog/movies?genre=krim", catalogPath: nil),
        ]
    }

    static var homeResponse: TvHomeResponse {
        let upcomingCards: [TvMediaCard] = [
            TvMediaCard(
                itemId: "series:tmdb:95396",
                mediaType: "series",
                ids: TvMediaIds(tmdb: 95396, imdb: "tt11280740"),
                title: "Severance",
                year: 2022,
                backdropUrl: "/preview-art/navy-backdrop.png",
                dominantColor: "#16243a",
                daysUntil: 1,
                episodeCode: "S02E05",
                episodeTitle: "Trojan's Horse",
                airDateBadge: "I morgen · S02E05",
                nextUp: TvNextUpPointer(season: 2, episode: 5),
                availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet", benefitLabel: "Kommer")
            ),
            TvMediaCard(
                itemId: "series:tmdb:83867",
                mediaType: "series",
                ids: TvMediaIds(tmdb: 83867, imdb: "tt9253284"),
                title: "Andor",
                year: 2022,
                backdropUrl: "/preview-art/teal-backdrop.png",
                dominantColor: "#152726",
                daysUntil: 3,
                episodeCode: "S02E04",
                episodeTitle: "Ever Been to Ghorman?",
                airDateBadge: "På torsdag · S02E04",
                nextUp: TvNextUpPointer(season: 2, episode: 4),
                availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet", benefitLabel: "Kommer")
            ),
            TvMediaCard(
                itemId: "series:tmdb:126308",
                mediaType: "series",
                ids: TvMediaIds(tmdb: 126308),
                title: "Shōgun",
                year: 2024,
                backdropUrl: "/preview-art/crimson-backdrop.png",
                dominantColor: "#2a1216",
                daysUntil: 6,
                episodeCode: "S02E01",
                episodeTitle: "Episode 1",
                airDateBadge: "På søndag · S02E01",
                nextUp: TvNextUpPointer(season: 2, episode: 1),
                availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet", benefitLabel: "Kommer")
            ),
        ]
        return TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-20T00:00:00Z",
            layout: "lampelys-v2",
            roomName: previewRoomName,
            hardwareProfile: previewHardwareProfile,
            equipmentLabel: LunaCopy.roomEquipmentLabel(hardwareProfile: previewHardwareProfile),
            atmosphere: "living",
            tonight: TvTonightPayload(
                ok: true,
                roomName: previewRoomName,
                hardwareProfile: previewHardwareProfile,
                equipmentLabel: LunaCopy.roomEquipmentLabel(hardwareProfile: previewHardwareProfile),
                atmosphere: "living",
                reason: "phone_handoff",
                reasonLabel: "Fra iPhone",
                preparedFromPhone: lykkelandCard,
                item: dunePartTwoCard
            ),
            rows: [
                TvShelfRow(
                    rowId: "medialogg-continue",
                    title: "Fortsett å se",
                    rowStyle: "continue_backdrop",
                    sourceKind: "system_continue",
                    listMode: "smart",
                    hasMore: false,
                    nextPath: nil,
                    items: [lykkelandCard, dunePartTwoCard, severanceCard]
                ),
                TvShelfRow(
                    rowId: "upcoming-episodes",
                    title: "Kommende episoder",
                    rowStyle: "upcoming_backdrop",
                    sourceKind: "system_upcoming",
                    listMode: "smart",
                    hasMore: false,
                    nextPath: nil,
                    items: upcomingCards
                ),
                TvShelfRow(
                    rowId: "new-episodes",
                    title: "Nye episoder",
                    rowStyle: "poster",
                    sourceKind: "active_series",
                    listMode: "curated",
                    hasMore: true,
                    nextPath: "/api/tv/v2/catalog/series",
                    items: seriesCards
                ),
                TvShelfRow(
                    rowId: "atmospheric-films",
                    title: "Populært nå",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    listMode: "curated",
                    hasMore: true,
                    nextPath: "/api/tv/v2/catalog/movies",
                    items: catalogMovies
                ),
            ]
        )
    }

    static func libraryResponse(mediaType: String = "movie") -> TvLibraryResponse {
        let items: [TvMediaCard]
        switch mediaType {
        case "series":
            items = libraryLocalSeries
        case "movie":
            items = libraryLocalMovies
        default:
            items = libraryLocalCards
        }
        let sampleLists = [
            TvLibraryCustomList(
                id: "custom:nordic-noir",
                name: "Nordisk spenning",
                mediaType: "series",
                sourceType: "custom",
                listMode: "curated",
                rowStyle: "poster",
                itemCount: 4,
                browsePath: "/api/tv/v2/rows/custom%3Anordic-noir"
            ),
            TvLibraryCustomList(
                id: "custom:weekend-sci-fi",
                name: "Helgefilm · Sci-Fi",
                mediaType: "movie",
                sourceType: "custom",
                listMode: "curated",
                rowStyle: "poster",
                itemCount: 6,
                browsePath: "/api/tv/v2/rows/custom%3Aweekend-sci-fi"
            ),
        ]
        return TvLibraryResponse(
            ok: true,
            section: "local",
            counts: TvLibraryCounts(
                watchlist: 2,
                localTotal: libraryLocalCards.count,
                localMovies: libraryLocalMovies.count,
                localSeries: libraryLocalSeries.count,
                nvme: 6,
                archive: 2,
                vfs: 0,
                customLists: sampleLists.count,
                customListsCount: sampleLists.count
            ),
            watchlist: [dunePartTwoCard, lykkelandCard],
            localItems: items,
            localHasMore: false,
            customLists: sampleLists
        )
    }
}
