import Foundation

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
            appVersion: "2.9.0",
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
        itemId: "series:79291",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 79291, imdb: "tt8177564"),
        title: "Lykkeland",
        year: 2018,
        overview: "Stavanger, 1970-tallet. Oljen er funnet, og byen forandres for alltid.",
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
            itemId: "episode:79291:s4:e6",
            mediaType: "episode",
            tmdbId: 79291,
            season: 4,
            episode: 6,
            startPositionSeconds: 1390,
            mode: "resume",
            title: "Søndagsbarn",
            seriesTitle: "Lykkeland"
        ),
        nextUp: TvNextUpPointer(season: 4, episode: 6),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 1390, durationSeconds: 3120, percent: 44.5, season: 4, episode: 6, watched: false)
    )

    static let dunePartTwoCard = TvMediaCard(
        itemId: "movie:693134",
        mediaType: "movie",
        ids: TvMediaIds(tmdb: 693134, imdb: "tt15239678"),
        title: "Dune: Part Two",
        year: 2024,
        overview: "Paul Atreides slår seg sammen med Chani og fremenerne på Arrakis.",
        posterUrl: "/preview-art/sand-poster.png",
        backdropUrl: "/preview-art/sand-backdrop.png",
        cardBackdropUrl: "/preview-art/sand-backdrop.png",
        dominantColor: "#2a1c10",
        imdbRating: 8.5,
        badges: ["4K", "HDR10+", "TrueHD Atmos"],
        inWatchlist: true,
        contextSubtitle: "1 t 12 min igjen",
        directPlayTarget: TvDirectPlayTarget(
            itemId: "movie:693134",
            mediaType: "movie",
            tmdbId: 693134,
            startPositionSeconds: 5640,
            mode: "resume",
            title: "Dune: Part Two"
        ),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 5640, durationSeconds: 9960, percent: 56.6, watched: false)
    )

    static let severanceCard = TvMediaCard(
        itemId: "series:95396",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 95396, imdb: "tt11280740"),
        title: "Severance",
        year: 2022,
        overview: "Mark leder et team på Lumon Industries der jobb- og privatminner er kirurgisk adskilt.",
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
            itemId: "episode:95396:s2:e4",
            mediaType: "episode",
            tmdbId: 95396,
            season: 2,
            episode: 4,
            startPositionSeconds: 1122,
            mode: "resume",
            title: "Woe's Hollow",
            seriesTitle: "Severance"
        ),
        nextUp: TvNextUpPointer(season: 2, episode: 4),
        availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
        progress: TvWatchProgress(positionSeconds: 1122, durationSeconds: 3180, percent: 35.3, season: 2, episode: 4, watched: false)
    )

    static let luksusfellenCard = TvMediaCard(
        itemId: "series:246810",
        mediaType: "series",
        ids: TvMediaIds(tmdb: 246810, imdb: "tt1298765"),
        title: "Luksusfellen",
        year: 2008,
        overview: "Norske familier får hjelp av erfarne økonomer til å snu gjeldskrise til trygg hverdag.",
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
            itemId: "movie:426063",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 426063, imdb: "tt5040012"),
            title: "Nosferatu",
            year: 2024,
            overview: "Gotisk fortelling om besettelse og mørke skygger over Wisborg.",
            posterUrl: "/preview-art/aubergine-poster.png",
            backdropUrl: "/preview-art/aubergine-backdrop.png",
            dominantColor: "#22182b",
            imdbRating: 7.7,
            badges: ["4K", "HDR10+"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:335984",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 335984, imdb: "tt1856101"),
            title: "Blade Runner 2049",
            year: 2017,
            overview: "En ung blade runner avdekker en lenge begravd hemmelighet.",
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 8.0,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:872585",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 872585, imdb: "tt15398776"),
            title: "Oppenheimer",
            year: 2023,
            overview: "Historien om J. Robert Oppenheimer og Manhattan-prosjektet.",
            posterUrl: "/preview-art/ochre-poster.png",
            backdropUrl: "/preview-art/ochre-backdrop.png",
            dominantColor: "#2a1c10",
            imdbRating: 8.3,
            badges: ["4K", "HDR10"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:539972",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 539972, imdb: "tt1160419"),
            title: "Verdens verste menneske",
            year: 2021,
            overview: "Fire år i livet til Julie i Oslo gjennom kjærlighet og veivalg.",
            posterUrl: "/preview-art/crimson-poster.png",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            dominantColor: "#2a1216",
            imdbRating: 7.8,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:157336",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 157336, imdb: "tt0816692"),
            title: "Interstellar",
            year: 2014,
            overview: "En gruppe oppdagere reiser gjennom et ormehull i rommet.",
            posterUrl: "/preview-art/navy-poster.png",
            backdropUrl: "/preview-art/navy-backdrop.png",
            dominantColor: "#141d2e",
            imdbRating: 8.7,
            badges: ["4K", "HDR10"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:27205",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 27205),
            title: "Kon-Tiki",
            year: 2012,
            overview: "Thor Heyerdahls dramatiske ferd over Stillehavet på en balsaflåte.",
            posterUrl: "/preview-art/sand-poster.png",
            backdropUrl: "/preview-art/sand-backdrop.png",
            dominantColor: "#2d1d12",
            imdbRating: 7.2,
            badges: ["4K", "Norsk"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:301337",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 301337),
            title: "Bølgen",
            year: 2015,
            overview: "Geologen Kristian varsler om fjellskred over Geiranger.",
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 6.7,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "movie:414906",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 414906),
            title: "The Batman",
            year: 2022,
            overview: "Etter to år i skyggene avdekker Bruce Wayne korrupsjon i Gotham.",
            posterUrl: "/preview-art/aubergine-poster.png",
            backdropUrl: "/preview-art/aubergine-backdrop.png",
            dominantColor: "#22182b",
            imdbRating: 7.8,
            badges: ["4K", "Dolby Vision"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
        TvMediaCard(
            itemId: "movie:329865",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 329865),
            title: "Arrival",
            year: 2016,
            overview: "En lingvist forsøker å tyde språket til utenomjordiske gjester.",
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
            itemId: "series:83867",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 83867, imdb: "tt9253284"),
            title: "Andor",
            year: 2022,
            overview: "Cassian Andors vei inn i opprøret mot Imperiet.",
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            dominantColor: "#152726",
            imdbRating: 8.4,
            badges: ["4K", "Dolby Vision"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:126308",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 126308),
            title: "Shōgun",
            year: 2024,
            overview: "Maktkamp og ære i føydale Japan.",
            posterUrl: "/preview-art/crimson-poster.png",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            dominantColor: "#2a1216",
            imdbRating: 8.6,
            badges: ["4K", "Atmos"],
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme")
        ),
        TvMediaCard(
            itemId: "series:136315",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 136315),
            title: "The Bear",
            year: 2022,
            overview: "En ung stjernekokk vender hjem til Chicago for å drive familiestedet.",
            posterUrl: "/preview-art/ochre-poster.png",
            backdropUrl: "/preview-art/ochre-backdrop.png",
            dominantColor: "#2d1d12",
            imdbRating: 8.5,
            badges: ["4K", "HDR10+"],
            availability: TvAvailabilityInfo(state: "instant", tier: "archive")
        ),
    ]

    static let libraryLocalMovies: [TvMediaCard] = Array(catalogMovies.prefix(8))
    static let libraryLocalSeries: [TvMediaCard] = Array(seriesCards.prefix(3))
    static let libraryLocalCards: [TvMediaCard] = libraryLocalMovies + libraryLocalSeries

    static var genreChips: [TvGenreChip] {
        [
            TvGenreChip(slug: "norsk", label: "Norsk", icon: nil, accentColor: nil, tmdbGenreIds: nil, browsePath: "/api/tv/v1/catalog/movies?genre=norsk", catalogPath: nil),
            TvGenreChip(slug: "drama", label: "Drama", icon: nil, accentColor: nil, tmdbGenreIds: [18], browsePath: "/api/tv/v1/catalog/movies?genre=drama", catalogPath: nil),
            TvGenreChip(slug: "komedie", label: "Komedie", icon: nil, accentColor: nil, tmdbGenreIds: [35], browsePath: "/api/tv/v1/catalog/movies?genre=komedie", catalogPath: nil),
            TvGenreChip(slug: "sci-fi", label: "Sci-Fi & Fantasy", icon: nil, accentColor: nil, tmdbGenreIds: [878], browsePath: "/api/tv/v1/catalog/movies?genre=sci-fi", catalogPath: nil),
            TvGenreChip(slug: "thriller", label: "Thriller & Spenning", icon: nil, accentColor: nil, tmdbGenreIds: [53], browsePath: "/api/tv/v1/catalog/movies?genre=thriller", catalogPath: nil),
            TvGenreChip(slug: "action", label: "Action & Eventyr", icon: nil, accentColor: nil, tmdbGenreIds: [28], browsePath: "/api/tv/v1/catalog/movies?genre=action", catalogPath: nil),
            TvGenreChip(slug: "krim", label: "Krim & Mysterier", icon: nil, accentColor: nil, tmdbGenreIds: [80], browsePath: "/api/tv/v1/catalog/movies?genre=krim", catalogPath: nil),
        ]
    }

    static var homeResponse: TvHomeResponse {
        let upcomingGhost = TvMediaCard(
            itemId: "series:upcoming-1",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 99901),
            title: "Kommende tittel",
            year: 2026,
            backdropUrl: "/preview-art/navy-backdrop.png",
            episodeCode: "S02E04",
            airDateBadge: "På søndag",
            availability: TvAvailabilityInfo(state: "upcoming", tier: "usenet", benefitLabel: "Kommer")
        )
        return TvHomeResponse(
            ok: true,
            generatedAt: "2026-11-20T00:00:00Z",
            layout: "lampelys-v2",
            layoutMode: "calm",
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
                    items: [lykkelandCard, dunePartTwoCard, severanceCard],
                    genres: nil
                ),
                TvShelfRow(
                    rowId: "upcoming-episodes",
                    title: "Kommende episoder",
                    rowStyle: "upcoming_backdrop",
                    sourceKind: "system_upcoming",
                    listMode: "smart",
                    hasMore: false,
                    nextPath: nil,
                    items: [upcomingGhost],
                    genres: nil
                ),
                TvShelfRow(
                    rowId: "new-episodes",
                    title: "Nye episoder",
                    rowStyle: "poster",
                    sourceKind: "active_series",
                    listMode: "curated",
                    hasMore: true,
                    nextPath: "/api/tv/v1/catalog/series",
                    items: seriesCards,
                    genres: nil
                ),
                TvShelfRow(
                    rowId: "atmospheric-films",
                    title: "Populært nå",
                    rowStyle: "poster",
                    sourceKind: "catalog",
                    listMode: "curated",
                    hasMore: true,
                    nextPath: "/api/tv/v1/catalog/movies",
                    items: catalogMovies,
                    genres: nil
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
        return TvLibraryResponse(
            ok: true,
            section: "local",
            activeFilters: TvLibraryActiveFilters(tier: "all", mediaType: mediaType, sort: "recent"),
            counts: TvLibraryCounts(
                favorites: 2,
                watchlist: 2,
                localTotal: libraryLocalCards.count,
                localMovies: libraryLocalMovies.count,
                localSeries: libraryLocalSeries.count,
                nvme: 6,
                archive: 2,
                vfs: 0,
                customLists: 0
            ),
            favorites: [],
            watchlist: [dunePartTwoCard, lykkelandCard],
            localItems: items,
            localHasMore: false,
            customLists: []
        )
    }

    static var luksusfellenSeason28Episodes: [TvEpisodeCard] {
        [
            TvEpisodeCard(
                itemId: "episode:246810:s28:e1",
                seasonNumber: 28,
                episodeNumber: 1,
                title: "Ny start i Drammen",
                overview: "Hallgeir og Cecilie møter en småbarnsfamilie som har mistet oversikten over forbrukslån.",
                stillUrl: "/preview-art/teal-backdrop.png",
                airDate: "2026-09-03",
                isUpcoming: false,
                airDateBadge: nil,
                voteAverage: 7.9,
                runtimeSeconds: 2700,
                watched: false,
                availability: TvAvailabilityInfo(state: "instant", tier: "nvme"),
                progress: nil
            ),
            TvEpisodeCard(
                itemId: "episode:246810:s28:e2",
                seasonNumber: 28,
                episodeNumber: 2,
                title: "Drømmebilen som sprakk",
                overview: "Billån og impulsive nettkjøp truer boligdrømmen på Sørlandet.",
                stillUrl: "/preview-art/ochre-backdrop.png",
                airDate: "2026-09-10",
                isUpcoming: false,
                airDateBadge: nil,
                voteAverage: 7.7,
                runtimeSeconds: 2640,
                watched: true,
                availability: TvAvailabilityInfo(state: "instant", tier: "nvme"),
                progress: TvWatchProgress(positionSeconds: 2640, durationSeconds: 2640, percent: 100, season: 28, episode: 2, watched: true)
            ),
            TvEpisodeCard(
                itemId: "episode:246810:s28:e3",
                seasonNumber: 28,
                episodeNumber: 3,
                title: "Budsjettjakt i Bergen",
                overview: "Småutgifter og abonnementer avsløres på tavla når økonomene går gjennom kontoutskriftene.",
                stillUrl: "/preview-art/navy-backdrop.png",
                airDate: "2026-09-17",
                isUpcoming: false,
                airDateBadge: nil,
                voteAverage: 8.0,
                runtimeSeconds: 2760,
                watched: false,
                availability: TvAvailabilityInfo(state: "instant", tier: "nvme"),
                progress: nil
            ),
        ]
    }

    static var luksusfellenSeasons: [TvSeasonSummary] {
        var list = [
            TvSeasonSummary(
                seasonNumber: 0,
                name: "Specials",
                episodeCount: 2,
                posterUrl: "/preview-art/teal-poster.png",
                airDate: "2008-01-10"
            )
        ]
        for number in 1...28 {
            list.append(
                TvSeasonSummary(
                    seasonNumber: number,
                    name: "Season \(number)",
                    episodeCount: 10,
                    posterUrl: "/preview-art/teal-poster.png",
                    airDate: "2008-03-01"
                )
            )
        }
        return list
    }

    static var luksusfellenDetail: TvItemDetail {
        TvItemDetail(
            itemId: "series:246810",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 246810, imdb: "tt1298765"),
            title: "Luksusfellen",
            originalTitle: "Luksusfellen",
            tagline: "Veien tilbake til økonomisk balanse.",
            overview: "Erfarne økonomieksperter hjelper vanlige mennesker med å ta tilbake styringen over gjeld, forbruk og hverdagsliv før problemene vokser over hodet på dem.",
            overviewNo: nil,
            overviewEn: nil,
            year: 2008,
            status: "Returning Series",
            runtimeSeconds: 2700,
            genres: ["Reality", "Dokumentar"],
            voteAverage: 7.8,
            rating: 7.8,
            imdbRating: 7.8,
            imdbVotes: 14_200,
            rottenTomatoesScore: nil,
            metacriticScore: nil,
            posterUrl: "/preview-art/teal-poster.png",
            backdropUrl: "/preview-art/teal-backdrop.png",
            cardBackdropUrl: "/preview-art/teal-backdrop.png",
            logoUrl: nil,
            dominantColor: "#152726",
            blurHash: nil,
            badges: ["4K", "Dolby Vision", "HDR10+", "Atmos"],
            nextAirDateBadge: nil,
            inWatchlist: true,
            watched: false,
            monitored: true,
            monitorMode: "all",
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
            progress: nil,
            selectedSeason: 1,
            nextUp: TvNextUpPointer(season: 28, episode: 1),
            seasons: luksusfellenSeasons,
            episodes: luksusfellenSeason28Episodes,
            network: "TV3 · Viaplay"
        )
    }

    static var playerLaunchRequest: PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            itemId: "movie:preview-jul",
            title: "Bara till jul",
            seriesTitle: nil,
            season: nil,
            episode: nil,
            startPositionSeconds: 1840,
            candidateId: "cand-playweb-atmos",
            prepareToken: "preview-prep-token",
            backdropUrl: "/preview-art/crimson-backdrop.png",
            logoUrl: nil
        )
    }

    static var previewAudioOptions: [PlayerDrawerAudioOption] {
        [
            PlayerDrawerAudioOption(
                id: 0,
                languageCode: "swe",
                rawTitle: "Svensk",
                codec: "eac3",
                channelLayout: "7.1.4",
                channels: 8,
                isAtmos: true
            ),
            PlayerDrawerAudioOption(
                id: 1,
                languageCode: "eng",
                rawTitle: "Original",
                codec: "eac3",
                channelLayout: "5.1",
                channels: 6,
                isAtmos: false
            ),
        ]
    }

    static var previewSubtitleOptions: [PlayerDrawerSubtitleOption] {
        [
            PlayerDrawerSubtitleOption(id: 10, languageCode: "swe", rawTitle: "Svensk", isForced: true),
            PlayerDrawerSubtitleOption(id: 11, languageCode: "nob", rawTitle: "Norsk"),
        ]
    }

    static var previewCandidates: [TvCandidateInfo] {
        [
            TvCandidateInfo(
                candidateId: "cand-playweb-atmos",
                displayHeadline: "1080p · WEB-DL · DDP Atmos 5.1 · playWEB",
                releaseTitle: "Bara.till.jul.2026.1080p.WEB-DL.DDP5.1.Atmos-playWEB",
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
                explanationChips: ["Strømmes ved start", "DDP Atmos"],
                releaseGroup: "playWEB",
                isNorwegian: true
            ),
            TvCandidateInfo(
                candidateId: "cand-flux-atmos",
                displayHeadline: "1080p · WEB-DL · DDP Atmos 5.1 · FLUX",
                releaseTitle: "Bara.till.jul.2026.1080p.WEB-DL.DDP5.1.Atmos-FLUX",
                source: "infinidysk",
                tier: "vfs",
                resolution: "1080p",
                videoRangeType: "SDR",
                dvProfile: nil,
                dvEnhancementLayer: nil,
                audioCodec: "DDP Atmos",
                sizeBytes: 5_368_709_120,
                tvScore: 940,
                isActive: false,
                explanationChips: ["Strømmes ved start", "DDP Atmos"],
                releaseGroup: "FLUX",
                isNorwegian: true
            ),
            TvCandidateInfo(
                candidateId: "cand-norvine-std",
                displayHeadline: "1080p · WEB-DL · NORVINE",
                releaseTitle: "Bara.till.jul.2026.1080p.WEB-DL-NORVINE",
                source: "infinidysk",
                tier: "vfs",
                resolution: "1080p",
                videoRangeType: "SDR",
                dvProfile: nil,
                dvEnhancementLayer: nil,
                audioCodec: "AAC",
                sizeBytes: 3_221_225_472,
                tvScore: 860,
                isActive: false,
                explanationChips: ["Strømmes ved start"],
                releaseGroup: "NORVINE",
                isNorwegian: true
            ),
        ]
    }

    static var playerSession: TvPlaybackSession {
        let primaryCandidate = previewCandidates[0]
        let probeChapters = [
            TvProbeChapter(index: 0, idString: "ch-0", title: "Prolog", startSeconds: 0, endSeconds: 240, kind: "chapter"),
            TvProbeChapter(index: 1, idString: "ch-1", title: "Introduksjon", startSeconds: 240, endSeconds: 320, kind: "intro"),
            TvProbeChapter(index: 2, idString: "ch-2", title: "Hjemreise", startSeconds: 320, endSeconds: 5600, kind: "chapter"),
            TvProbeChapter(index: 3, idString: "ch-3", title: "Rulletekst", startSeconds: 5600, endSeconds: 6180, kind: "credits"),
        ]
        return TvPlaybackSession(
            sessionId: "preview-session-jul",
            streamToken: "preview-stream-token-0001",
            roomName: previewRoomName,
            hardwareProfile: previewHardwareProfile,
            item: TvPlaybackItemContext(
                itemId: "movie:preview-jul",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 99912),
                title: "Bara till jul",
                seriesTitle: nil,
                season: nil,
                episode: nil,
                year: 2026,
                runtimeSeconds: 6180,
                posterUrl: "/preview-art/crimson-poster.png",
                backdropUrl: "/preview-art/crimson-backdrop.png",
                logoUrl: nil
            ),
            selectedCandidate: primaryCandidate,
            stream: TvStreamEndpoint(
                url: "/preview-stream/jul.mkv",
                container: "mkv",
                supportsByteRanges: true,
                zeroCopyMode: "206",
                canClientPrewarmBytes: false,
                startPositionSeconds: 1840,
                declaredDurationSeconds: 6180
            ),
            tracks: TvSessionTracks(probeConfidence: "high", externalSubtitles: nil, chapters: probeChapters),
            chapters: probeChapters,
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: false,
                dualLayerRoute: "direct",
                foldsDolbyVisionFEL: false,
                dolbyVisionHandling: "automatic",
                panelPresentsDolbyVision: false,
                panelIsInHDRMode: false,
                matchContentEnabled: true,
                displayCriteriaOwner: "engine",
                attemptsHDRMasterOnUnprovenPanel: false,
                objectAudioRendering: TvObjectAudioConfig(mode: "render", layout: "7.1.4"),
                audioBridgeMode: "surroundCompat",
                preferredAudioLanguages: ["swe", "nob", "eng"],
                preferredSubtitleLanguages: ["nob", "eng"],
                autoPlayNextEpisode: true,
                smartNordicSubtitleRule: true,
                skipsContainerAttachments: true,
                generatesBackgroundScrubPreviews: false,
                serveIFramePlaylist: false,
                confirmAtmos: false,
                maxConcurrentSourceRequests: 2,
                declaredDurationSeconds: 6180
            ),
            heartbeatIntervalSeconds: 30,
            nextEpisode: nil
        )
    }
}
