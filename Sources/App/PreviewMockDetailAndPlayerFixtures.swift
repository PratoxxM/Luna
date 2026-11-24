import Foundation

/// Deterministic 28-season detail and playback session fixtures extracted from `PreviewMockFixtures`.
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
            episodes: luksusfellenSeason28Episodes
        )
    }

    static var playerLaunchRequest: PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            itemId: "movie:tmdb:99912",
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
                channelLayout: "5.1.2",
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
                itemId: "movie:tmdb:99912",
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
                foldsDolbyVisionFEL: false,
                dolbyVisionHandling: "automatic",
                matchContentEnabled: true,
                attemptsHDRMasterOnUnprovenPanel: false,
                objectAudioRendering: TvObjectAudioConfig(mode: "render", layout: "5.1.2"),
                audioBridgeMode: "lossless",
                preferredAudioLanguages: ["swe", "nob", "eng"],
                preferredSubtitleLanguages: ["nob", "eng"],
                skipsContainerAttachments: true,
                generatesBackgroundScrubPreviews: false,
                serveIFramePlaylist: false,
                confirmAtmos: false,
                maxConcurrentSourceRequests: 3,
                declaredDurationSeconds: 6180
            ),
            heartbeatIntervalSeconds: 15,
            nextEpisode: nil
        )
    }
}
