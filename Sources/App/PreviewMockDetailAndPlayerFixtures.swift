import Foundation

/// Deterministic 28-season detail, movie detail, and playback session fixtures extracted from `PreviewMockFixtures`.
extension PreviewMockFixtures {
    static var luksusfellenSeason28Episodes: [TvEpisodeCard] {
        [
            TvEpisodeCard(
                itemId: "episode:tmdb:246810:s28:e1",
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
                itemId: "episode:tmdb:246810:s28:e2",
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
                itemId: "episode:tmdb:246810:s28:e3",
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
            itemId: "series:tmdb:246810",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 246810, imdb: "tt1298765"),
            title: "Luksusfellen",
            originalTitle: "Luksusfellen",
            tagline: "Når hverdagsøkonomien tar overhånd.",
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
            imdbVotes: 1420,
            rottenTomatoesScore: 84,
            metacriticScore: nil,
            cast: ["Hallgeir Kvadsheim", "Cecilie Lynum", "Lene Drange", "Magne Gundersen"],
            castMembers: [
                TvCastMember(name: "Hallgeir Kvadsheim", character: "Økonomiekspert", profileUrl: "/preview-art/teal-poster.png"),
                TvCastMember(name: "Cecilie Lynum", character: "Psykolog og rådgiver", profileUrl: "/preview-art/ochre-poster.png"),
                TvCastMember(name: "Lene Drange", character: "Økonomiekspert", profileUrl: "/preview-art/navy-poster.png"),
                TvCastMember(name: "Magne Gundersen", character: "Forbrukerøkonom", profileUrl: "/preview-art/sand-poster.png"),
            ],
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
            nextEpisode: TvNextEpisodeSummary(
                itemId: "episode:tmdb:246810:s28:e1",
                season: 28,
                episode: 1,
                title: "Ny start i Drammen",
                stillUrl: "/preview-art/teal-backdrop.png",
                runtimeSeconds: 2700
            ),
            seasons: luksusfellenSeasons,
            episodes: luksusfellenSeason28Episodes
        )
    }

    static var duneMovieDetail: TvItemDetail {
        TvItemDetail(
            itemId: "movie:tmdb:693134",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 693134, imdb: "tt15239678"),
            title: "Dune: Part Two",
            originalTitle: "Dune: Part Two",
            tagline: "Lenge leve krigerne.",
            overview: "Paul Atreides forener krefter med Chani og fremenerne på ørkenplaneten Arrakis for å konfrontere konspirasjonen som utslettet familien hans, mens han tvinges til å velge mellom sitt livs kjærlighet og universets skjebne.\n\nSamtidig samler Harkonnen-huset sine styrker under ledelse av Feyd-Rautha, og Paul må navigere mellom gamle profetier og den uunngåelige krigen som truer hele imperiet.",
            overviewNo: nil,
            overviewEn: nil,
            year: 2024,
            status: "Released",
            runtimeSeconds: 9960,
            genres: ["Sci-Fi", "Eventyr"],
            voteAverage: 8.5,
            rating: 8.5,
            imdbRating: 8.5,
            imdbVotes: 580_000,
            rottenTomatoesScore: 92,
            metacriticScore: 79,
            cast: ["Timothée Chalamet", "Zendaya", "Rebecca Ferguson", "Javier Bardem", "Josh Brolin", "Austin Butler"],
            castMembers: [
                TvCastMember(name: "Timothée Chalamet", character: "Paul Atreides", profileUrl: "/preview-art/sand-poster.png"),
                TvCastMember(name: "Zendaya", character: "Chani", profileUrl: "/preview-art/ochre-poster.png"),
                TvCastMember(name: "Rebecca Ferguson", character: "Lady Jessica", profileUrl: "/preview-art/aubergine-poster.png"),
                TvCastMember(name: "Javier Bardem", character: "Stilgar", profileUrl: "/preview-art/teal-poster.png"),
                TvCastMember(name: "Josh Brolin", character: "Gurney Halleck", profileUrl: "/preview-art/navy-poster.png"),
                TvCastMember(name: "Austin Butler", character: "Feyd-Rautha", profileUrl: "/preview-art/crimson-poster.png"),
            ],
            posterUrl: "/preview-art/sand-poster.png",
            backdropUrl: "/preview-art/sand-backdrop.png",
            cardBackdropUrl: "/preview-art/sand-backdrop.png",
            logoUrl: nil,
            dominantColor: "#3b2614",
            blurHash: nil,
            badges: ["4K", "Dolby Vision P7 FEL", "TrueHD Atmos 7.1.4"],
            nextAirDateBadge: nil,
            inWatchlist: true,
            watched: false,
            monitored: true,
            monitorMode: "all",
            availability: TvAvailabilityInfo(state: "instant", tier: "nvme", benefitLabel: "Starter umiddelbart"),
            progress: TvWatchProgress(
                positionSeconds: 5640,
                durationSeconds: 9960,
                percent: 56.6,
                watched: false
            ),
            selectedSeason: nil,
            nextUp: nil,
            seasons: nil,
            episodes: nil
        )
    }

    static var playerLaunchRequest: PlaybackLaunchRequest {
        playerLaunchRequest(for: .playerSubtitles)
    }

    static func playerLaunchRequest(for screen: PreviewScreenTarget) -> PlaybackLaunchRequest {
        let startSeconds: Double? = {
            switch screen {
            case .playerSkipIntro, .playerNextEpisode:
                return 0
            default:
                return 1122
            }
        }()
        return PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s2:e4",
            title: "Woe's Hollow",
            seriesTitle: "Severance",
            season: 2,
            episode: 4,
            startPositionSeconds: startSeconds,
            candidateId: "cand-framestor-dv7",
            prepareToken: screen == .playerCurtain ? nil : "preview-prep-token",
            backdropUrl: "/preview-art/cinema-stage-backdrop.png",
            logoUrl: nil
        )
    }

    static var previewAudioOptions: [PlayerDrawerAudioOption] {
        [
            PlayerDrawerAudioOption(
                id: 0,
                languageCode: "eng",
                rawTitle: "Original",
                codec: "truehd",
                channelLayout: "7.1.4",
                channels: 8,
                isAtmos: true
            ),
            PlayerDrawerAudioOption(
                id: 1,
                languageCode: "nob",
                rawTitle: "Norsk",
                codec: "eac3",
                channelLayout: "5.1",
                channels: 6,
                isAtmos: false
            ),
        ]
    }

    static var previewSubtitleOptions: [PlayerDrawerSubtitleOption] {
        [
            PlayerDrawerSubtitleOption(id: 10, languageCode: "nob", rawTitle: "Norsk"),
            PlayerDrawerSubtitleOption(id: 11, languageCode: "eng", rawTitle: "Engelsk", isHearingImpaired: true),
            PlayerDrawerSubtitleOption(id: 12, languageCode: "swe", rawTitle: "Svensk"),
        ]
    }

    static var previewCandidates: [TvCandidateInfo] {
        [
            TvCandidateInfo(
                candidateId: "cand-framestor-dv7",
                displayHeadline: "4K · Remux · Dolby Vision P7 FEL · TrueHD Atmos 7.1.4 · FraMeSToR",
                releaseTitle: "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR.TrueHD.7.1.Atmos-FraMeSToR",
                source: "nvme",
                tier: "nvme",
                resolution: "2160p",
                videoRangeType: "Dolby Vision",
                dvProfile: 7,
                dvEnhancementLayer: "FEL",
                audioCodec: "TrueHD Atmos",
                sizeBytes: 77_738_909_696,
                tvScore: 1280,
                isActive: true,
                explanationChips: ["På NVMe", "DV P7 FEL", "TrueHD Atmos"],
                releaseGroup: "FraMeSToR",
                isNorwegian: true
            ),
            TvCandidateInfo(
                candidateId: "cand-flux-dv8",
                displayHeadline: "4K · WEB-DL · Dolby Vision P8 · DDP Atmos 5.1 · FLUX",
                releaseTitle: "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR-FLUX",
                source: "infinidysk",
                tier: "vfs",
                resolution: "2160p",
                videoRangeType: "Dolby Vision",
                dvProfile: 8,
                dvEnhancementLayer: nil,
                audioCodec: "DDP Atmos",
                sizeBytes: 26_628_797_235,
                tvScore: 1040,
                isActive: false,
                explanationChips: ["Strømmes ved start", "DDP Atmos"],
                releaseGroup: "FLUX",
                isNorwegian: true
            ),
            TvCandidateInfo(
                candidateId: "cand-ctrlhd-1080p",
                displayHeadline: "1080p · BluRay · DTS-HD MA 5.1 · CtrlHD",
                releaseTitle: "Dune.Part.Two.2024.1080p.BluRay.DTS-HD.MA.5.1-CtrlHD",
                source: "archive",
                tier: "archive",
                resolution: "1080p",
                videoRangeType: "SDR",
                dvProfile: nil,
                dvEnhancementLayer: nil,
                audioCodec: "DTS-HD MA",
                sizeBytes: 15_247_133_900,
                tvScore: 890,
                isActive: false,
                explanationChips: ["I arkiv", "Tapsfri lyd"],
                releaseGroup: "CtrlHD",
                isNorwegian: true
            ),
        ]
    }

    static var playerSession: TvPlaybackSession {
        playerSession(for: .playerSubtitles)
    }

    static func playerSession(for screen: PreviewScreenTarget) -> TvPlaybackSession {
        let primaryCandidate = previewCandidates[0]
        let startSeconds: Double = (screen == .playerSkipIntro || screen == .playerNextEpisode) ? 0 : 1122
        let probeChapters = [
            TvProbeChapter(index: 0, idString: "ch-0", title: "Sammendrag", startSeconds: 0, endSeconds: 45, kind: "recap"),
            TvProbeChapter(index: 1, idString: "ch-1", title: "Introduksjon", startSeconds: 45, endSeconds: 135, kind: "intro"),
            TvProbeChapter(index: 2, idString: "ch-2", title: "Woe's Hollow", startSeconds: 135, endSeconds: 2940, kind: "chapter"),
            TvProbeChapter(index: 3, idString: "ch-3", title: "Rulletekst", startSeconds: 2940, endSeconds: 3180, kind: "credits"),
        ]
        return TvPlaybackSession(
            sessionId: "preview-session-severance",
            streamToken: "preview-stream-token-0001",
            roomName: previewRoomName,
            hardwareProfile: previewHardwareProfile,
            item: TvPlaybackItemContext(
                itemId: "episode:tmdb:95396:s2:e4",
                mediaType: "episode",
                ids: TvMediaIds(tmdb: 95396),
                title: "Woe's Hollow",
                seriesTitle: "Severance",
                season: 2,
                episode: 4,
                year: 2025,
                runtimeSeconds: 3180,
                posterUrl: "/preview-art/navy-poster.png",
                backdropUrl: "/preview-art/cinema-stage-backdrop.png",
                logoUrl: nil
            ),
            selectedCandidate: primaryCandidate,
            stream: TvStreamEndpoint(
                url: "/preview-stream/severance-s02e04.mkv",
                container: "mkv",
                supportsByteRanges: true,
                zeroCopyMode: "206",
                canClientPrewarmBytes: false,
                startPositionSeconds: startSeconds,
                declaredDurationSeconds: 3180
            ),
            tracks: TvSessionTracks(probeConfidence: "high", externalSubtitles: nil, chapters: probeChapters),
            chapters: probeChapters,
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: true,
                foldsDolbyVisionFEL: false,
                dolbyVisionHandling: "automatic",
                matchContentEnabled: true,
                attemptsHDRMasterOnUnprovenPanel: false,
                objectAudioRendering: TvObjectAudioConfig(mode: "render", layout: "5.1.2"),
                audioBridgeMode: "lossless",
                preferredAudioLanguages: ["nob", "eng"],
                preferredSubtitleLanguages: ["nob", "eng"],
                skipsContainerAttachments: true,
                generatesBackgroundScrubPreviews: false,
                serveIFramePlaylist: false,
                confirmAtmos: false,
                maxConcurrentSourceRequests: 3,
                declaredDurationSeconds: 3180
            ),
            heartbeatIntervalSeconds: 15,
            nextEpisode: TvNextEpisodeSummary(
                itemId: "episode:tmdb:95396:s2:e5",
                season: 2,
                episode: 5,
                title: "Trojan's Horse",
                stillUrl: "/preview-art/teal-backdrop.png"
            )
        )
    }
}
