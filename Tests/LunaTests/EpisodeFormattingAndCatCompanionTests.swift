import Foundation
import MediaPlayer
import XCTest
@testable import Luna

final class EpisodeFormattingAndCatCompanionTests: XCTestCase {
    func testEpisodeCodeAndItemIdParsing() {
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 4), "S01E04")
        XCTAssertEqual(EpisodeTitleFormatter.formatEpisodeCode(season: 12, episode: 105), "S12E105")
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: 0, episode: 4))
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: 1, episode: 0))
        XCTAssertNil(EpisodeTitleFormatter.formatEpisodeCode(season: nil, episode: 4))

        let parsed = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s1:e4")
        XCTAssertEqual(parsed?.season, 1)
        XCTAssertEqual(parsed?.episode, 4)

        let upper = EpisodeTitleFormatter.parseEpisodeFromItemId("EPISODE:IMDB:tt123456:S04:E01")
        XCTAssertEqual(upper?.season, 4)
        XCTAssertEqual(upper?.episode, 1)

        let combined = EpisodeTitleFormatter.parseEpisodeFromItemId("episode:tmdb:95396:s01e04")
        XCTAssertEqual(combined?.season, 1)
        XCTAssertEqual(combined?.episode, 4)

        let fromCode = EpisodeTitleFormatter.parseEpisodeCode("S02E11")
        XCTAssertEqual(fromCode?.season, 2)
        XCTAssertEqual(fromCode?.episode, 11)

        let fromXCode = EpisodeTitleFormatter.parseEpisodeCode("1x04")
        XCTAssertEqual(fromXCode?.season, 1)
        XCTAssertEqual(fromXCode?.episode, 4)
        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeCode("4x4"))

        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeFromItemId("movie:tmdb:550"))
        XCTAssertNil(EpisodeTitleFormatter.parseEpisodeFromItemId("series:tmdb:95396"))
    }

    func testGenericEpisodeTitlesAreFilteredWhileRealAndNumericLeadingTitlesSurvive() {
        let genericCases: [String?] = [
            nil,
            "",
            "   ",
            "Episode 4",
            "Episode 4.",
            "Episode 4:",
            "episode 04",
            "Episode #4",
            "Ep 4",
            "Ep. 04",
            "Ep. 4.",
            "Ep.4",
            "Ep4",
            "Del 4",
            "Avsnitt 4",
            "E04",
            "E04.",
            "e4",
            "S01E04",
            "S01E04.",
            "S01 E04",
            "1x04",
            "1x04.",
            "s1e4",
            "4",
            "04",
            "#4",
            "#04",
            "4.",
            "#4.",
            "TBA",
            "TBA.",
            "TBD",
            "Ukjent",
            "Ukjent!",
            "unknown",
            "Severance",
            "severance",
            "Severance S01E04",
            "Severance · S01E04",
            "Severance · Episode 4",
            "Severance · Episode 4.",
            "Severance · 4",
            "Severance — Episode 4",
            "Severance - E04",
            "Severance (S01E04)",
            "Serie S01E04",
            "S01E04 · Episode 4",
            "S01E04 — Episode 4",
            "S01E04 · 4",
            "S01E04 Episode 4",
            "E04 Episode 4",
            "S01E04 - TBA",
            "1x04 - Episode 4",
            "1x04 — Episode 4",
            "01x04 - Episode 4.",
            "1x04 · 4",
        ]
        for raw in genericCases {
            XCTAssertNil(
                EpisodeTitleFormatter.nonGenericEpisodeTitle(
                    raw,
                    seriesTitle: "Severance",
                    season: 1,
                    episode: 4,
                    episodeCode: "S01E04"
                ),
                "Expected generic title '\(raw ?? "nil")' to return nil"
            )
        }

        // Preserve real numeric-leading titles and genuine titles
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 4,
                episode: 1,
                episodeCode: "S04E01"
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "24 Hours",
                seriesTitle: "ER",
                season: 1,
                episode: 1
            ),
            "24 Hours"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "101",
                seriesTitle: "Show",
                season: 1,
                episode: 1
            ),
            "101"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "4x4",
                seriesTitle: "Show",
                season: 4,
                episode: 4
            ),
            "4x4"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Epoch",
                seriesTitle: "Show",
                season: 1,
                episode: 4
            ),
            "Epoch"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Episode 4: A New Dawn",
                seriesTitle: "Show",
                season: 1,
                episode: 4
            ),
            "Episode 4: A New Dawn"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Severance: The Beginning",
                seriesTitle: "Severance",
                season: 1,
                episode: 1
            ),
            "Severance: The Beginning"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "Darkness Falls",
                seriesTitle: "Dark",
                season: 1,
                episode: 4
            ),
            "Darkness Falls"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S01E04 · The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S01E04 The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "S04E01 · 401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 4,
                episode: 1
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 · The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "01x04 · The You You Are",
                seriesTitle: "Severance"
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 The You You Are",
                seriesTitle: "Severance",
                season: 1,
                episode: 4
            ),
            "The You You Are"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "01x04 - The You You Are",
                seriesTitle: "Severance"
            ),
            "The You You Are"
        )
        XCTAssertNil(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 - Episode 4",
                seriesTitle: "Severance"
            )
        )
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 — The You You Are", seriesTitle: "Severance"), "The You You Are")
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04. The You You Are", seriesTitle: "Severance"), "The You You Are")
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 — Episode 4", seriesTitle: "Severance"))
        XCTAssertNil(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04 · 4", seriesTitle: "Severance"))
        XCTAssertEqual(EpisodeTitleFormatter.nonGenericEpisodeTitle("1x04.mp4", seriesTitle: "Show"), "1x04.mp4")
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1x04 · 401 Unauthorized",
                seriesTitle: "Mr. Robot",
                season: 1,
                episode: 4
            ),
            "401 Unauthorized"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "1917",
                seriesTitle: "Show",
                season: 1,
                episode: 1
            ),
            "1917"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "24 Hours",
                seriesTitle: "ER",
                season: 1,
                episode: 24
            ),
            "24 Hours"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "4",
                seriesTitle: "Show",
                season: 1,
                episode: 2
            ),
            "4"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "4",
                seriesTitle: "Show"
            ),
            "4"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "101.",
                seriesTitle: "Show",
                season: 1,
                episode: 1
            ),
            "101."
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "#101",
                seriesTitle: "Show",
                season: 1,
                episode: 1
            ),
            "#101"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "4x4 · Offroad",
                seriesTitle: "Show",
                season: 4,
                episode: 4
            ),
            "4x4 · Offroad"
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.nonGenericEpisodeTitle(
                "?",
                seriesTitle: "Show",
                season: 1,
                episode: 4
            ),
            "?"
        )
    }

    func testResolvingCurtainLabelsFromFrameZeroWithAndWithoutLogo() {
        // Frame 0, generic title, WITH logo -> only S01E04
        let withLogoGeneric = EpisodeTitleFormatter.curtainLabels(
            title: "Episode 4",
            seriesTitle: "Severance",
            itemId: "episode:tmdb:95396:s1:e4",
            season: nil,
            episode: nil,
            hasLogo: true
        )
        XCTAssertNil(withLogoGeneric.seriesLine)
        XCTAssertEqual(withLogoGeneric.mainLine, "S01E04")

        // Frame 0, generic title (or seriesTitle passed as title), WITHOUT logo -> seriesLine + S01E04
        let noLogoGeneric = EpisodeTitleFormatter.curtainLabels(
            title: "Severance",
            seriesTitle: "Severance",
            itemId: "episode:tmdb:95396:s1:e4",
            season: 1,
            episode: 4,
            hasLogo: false
        )
        XCTAssertEqual(noLogoGeneric.seriesLine, "Severance")
        XCTAssertEqual(noLogoGeneric.mainLine, "S01E04")

        // Real numeric-leading title, WITH and WITHOUT logo
        let withLogoNumeric = EpisodeTitleFormatter.curtainLabels(
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            itemId: "episode:tmdb:62560:s4:e1",
            season: 4,
            episode: 1,
            hasLogo: true
        )
        XCTAssertNil(withLogoNumeric.seriesLine)
        XCTAssertEqual(withLogoNumeric.mainLine, "S04E01 · 401 Unauthorized")

        let noLogoNumeric = EpisodeTitleFormatter.curtainLabels(
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            itemId: "episode:tmdb:62560:s4:e1",
            season: 4,
            episode: 1,
            hasLogo: false
        )
        XCTAssertEqual(noLogoNumeric.seriesLine, "Mr. Robot")
        XCTAssertEqual(noLogoNumeric.mainLine, "S04E01 · 401 Unauthorized")

        // Movie titles stay untouched (including numeric movie titles like "1917")
        let movieNoLogo = EpisodeTitleFormatter.curtainLabels(
            title: "1917",
            seriesTitle: nil,
            itemId: "movie:tmdb:530915",
            season: nil,
            episode: nil,
            hasLogo: false
        )
        XCTAssertNil(movieNoLogo.seriesLine)
        XCTAssertEqual(movieNoLogo.mainLine, "1917")
    }

    func testBottomBarLabelsPreventDuplicateEpisodeCodes() {
        let genericRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "",
            seriesTitle: "Severance",
            season: 1,
            episode: 4
        )
        let genericItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:95396:s1:e4",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 95396),
            title: "Episode 4",
            seriesTitle: "Severance",
            season: 1,
            episode: 4,
            year: 2022,
            runtimeSeconds: 2700,
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil
        )
        let genericLabels = EpisodeTitleFormatter.bottomBarLabels(
            sessionItem: genericItem,
            request: genericRequest
        )
        XCTAssertEqual(genericLabels.seriesLine, "Severance")
        XCTAssertEqual(genericLabels.titleLine, "S01E04")

        let namedItem = TvPlaybackItemContext(
            itemId: "episode:tmdb:62560:s4:e1",
            mediaType: "episode",
            ids: TvMediaIds(tmdb: 62560),
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            season: 4,
            episode: 1,
            year: 2019,
            runtimeSeconds: 2800,
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil
        )
        let namedLabels = EpisodeTitleFormatter.bottomBarLabels(
            sessionItem: namedItem,
            request: genericRequest
        )
        XCTAssertEqual(namedLabels.seriesLine, "Mr. Robot · S04E01")
        XCTAssertEqual(namedLabels.titleLine, "401 Unauthorized")
    }

    func testDetailEpisodeCardAndSourcePickerFormatting() {
        let genericEp = TvEpisodeCard(
            itemId: "episode:tmdb:95396:s1:e4",
            seasonNumber: 1,
            episodeNumber: 4,
            title: "Episode 4",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(genericEp.displayCardTitle, "Episode 4")

        let e04Ep = TvEpisodeCard(
            itemId: "episode:tmdb:95396:s1:e4",
            seasonNumber: 1,
            episodeNumber: 4,
            title: "E04",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(e04Ep.displayCardTitle, "Episode 4")

        let namedEp = TvEpisodeCard(
            itemId: "episode:tmdb:62560:s4:e1",
            seasonNumber: 4,
            episodeNumber: 1,
            title: "401 Unauthorized",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(namedEp.displayCardTitle, "E01 · 401 Unauthorized")

        let genericPicker = SourcePickerContext(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "Episode 4",
            seriesTitle: "Severance"
        )
        XCTAssertEqual(genericPicker.displaySubject, "Severance · S01E04")
        XCTAssertEqual(genericPicker.apiTitle, "")

        let namedPicker = SourcePickerContext(
            itemId: "episode:tmdb:62560:s4:e1",
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            season: 4,
            episode: 1
        )
        XCTAssertEqual(namedPicker.displaySubject, "Mr. Robot · S04E01 · 401 Unauthorized")
        XCTAssertEqual(namedPicker.apiTitle, "401 Unauthorized")
    }

    @MainActor
    func testNowPlayingMetadataAndPlaybackLaunchApiFallbackNeverDuplicateOrSendSeriesTitle() throws {
        let genericSessionJson = #"""
        {
          "sessionId": "sess-np-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "episode:tmdb:95396:s1:e4",
            "mediaType": "episode",
            "ids": { "tmdb": 95396 },
            "title": "S01E04",
            "seriesTitle": "Severance",
            "season": 1,
            "episode": 4
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K WEB-DL",
            "releaseTitle": "Severance.S01E04.2160p",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": { "url": "/api/tv/v1/streams/sess-np-1/master" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let genericSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(genericSessionJson.utf8))
        let genericNowPlaying = PlayerNowPlayingCoordinator.makeBaseInfo(for: genericSession)
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyTitle] as? String, "S01E04")
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyArtist] as? String, "Severance")
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyAlbumTitle] as? String, "Severance")

        let namedSessionJson = genericSessionJson.replacingOccurrences(of: "\"S01E04\"", with: "\"401 Unauthorized\"")
        let namedSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(namedSessionJson.utf8))
        let namedNowPlaying = PlayerNowPlayingCoordinator.makeBaseInfo(for: namedSession)
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyTitle] as? String, "401 Unauthorized")
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyArtist] as? String, "Severance")
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyAlbumTitle] as? String, "Severance · S01E04")

        // Card launch fallback must NEVER put seriesTitle or generic episodeTitle into request title
        let cardNoEpisodeTitle = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance",
            episodeCode: "S01E04",
            episodeTitle: nil,
            directPlayTarget: TvDirectPlayTarget(
                itemId: "episode:tmdb:95396:s1:e4",
                mediaType: "episode",
                tmdbId: 95396,
                season: 1,
                episode: 4,
                startPositionSeconds: 120,
                mode: "resume",
                title: nil,
                seriesTitle: "Severance"
            ),
            nextUp: TvNextUpPointer(season: 1, episode: 4)
        )
        let target = MediaCardMutator.resolvePlayTarget(for: cardNoEpisodeTitle)
        XCTAssertEqual(target.itemId, "episode:tmdb:95396:s1:e4")
        XCTAssertEqual(target.title, "")
        XCTAssertEqual(target.seriesTitle, "Severance")
        XCTAssertEqual(target.season, 1)
        XCTAssertEqual(target.episode, 4)

        let badRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "Severance",
            seriesTitle: "Severance"
        )
        XCTAssertEqual(badRequest.season, 1)
        XCTAssertEqual(badRequest.episode, 4)
        XCTAssertEqual(badRequest.formattedEpisodeCode, "S01E04")
        XCTAssertEqual(badRequest.apiTitle, "")

        let numericRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:62560:s4:e1",
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot"
        )
        XCTAssertEqual(numericRequest.apiTitle, "401 Unauthorized")

        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "Severance",
                seriesTitle: "Severance",
                itemId: "episode:tmdb:95396:s1:e4",
                season: nil,
                episode: nil
            ),
            ""
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "Ukjent",
                seriesTitle: "Severance",
                itemId: "episode:tmdb:95396:s1:e4",
                season: 1,
                episode: 4
            ),
            ""
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "1917",
                seriesTitle: nil,
                itemId: "movie:tmdb:530915",
                season: nil,
                episode: nil
            ),
            "1917"
        )

        let nextUpCard = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance",
            episodeCode: "S01E04",
            episodeTitle: "Episode 4",
            nextUp: TvNextUpPointer(season: 1, episode: 4)
        )
        let nextUpTarget = MediaCardMutator.resolvePlayTarget(for: nextUpCard)
        XCTAssertEqual(nextUpTarget.title, "")
        XCTAssertEqual(nextUpTarget.seriesTitle, "Severance")
        XCTAssertEqual(nextUpTarget.season, 1)
        XCTAssertEqual(nextUpTarget.episode, 4)

        let bareSeriesCard = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance"
        )
        let bareSeriesTarget = MediaCardMutator.resolvePlayTarget(for: bareSeriesCard)
        XCTAssertEqual(bareSeriesTarget.title, "")
        XCTAssertEqual(bareSeriesTarget.seriesTitle, "Severance")

        let movieCard = TvMediaCard(
            itemId: "movie:tmdb:530915",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 530915),
            title: "1917"
        )
        let movieTarget = MediaCardMutator.resolvePlayTarget(for: movieCard)
        XCTAssertEqual(movieTarget.title, "1917")
        XCTAssertNil(movieTarget.seriesTitle)
    }

    @MainActor
    func testComfortPreferencesCatCompanionsDefaultAndSideloadSafePersistence() {
        let suite = "luna.test.cats.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertTrue(comfort.showCatCompanions)

        var syncCalls = 0
        comfort.onSyncRequested = { _ in syncCalls += 1 }
        comfort.showCatCompanions = false
        XCTAssertEqual(syncCalls, 0)
        XCTAssertEqual(defaults.object(forKey: SideloadSafeStorage.showCatCompanionsKey) as? Bool, false)

        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.showCatCompanions)
    }

    func testLoadingSprintInterpolatorAndPauseCatLifecycle() {
        // Fast pre-resolved jump triggers bounded smooth sprint and settles into pounce crouch
        var sprint = LoadingSprintInterpolator.makeInitial(targetFraction: 0.16, now: 100.0)
        XCTAssertGreaterThanOrEqual(sprint.duration, 0.32)
        sprint.updateGoal(0.95, now: 100.05)
        XCTAssertGreaterThanOrEqual(sprint.duration, 0.32)
        XCTAssertLessThanOrEqual(sprint.duration, 0.70)
        XCTAssertTrue(sprint.isAdvancing(at: 100.20))
        XCTAssertEqual(sprint.pounceBlend(at: 100.20, isPreparingReveal: true), 0.0, accuracy: 0.001)

        let mid = sprint.fraction(at: 100.05 + sprint.duration * 0.5)
        XCTAssertGreaterThan(mid, 0.5)
        XCTAssertLessThan(mid, 0.95)

        let finishTime = 100.05 + sprint.duration
        XCTAssertEqual(sprint.fraction(at: finishTime), 0.95, accuracy: 0.001)
        XCTAssertFalse(sprint.isAdvancing(at: finishTime + 0.05))
        XCTAssertEqual(sprint.pounceBlend(at: finishTime + 0.30, isPreparingReveal: true), 1.0, accuracy: 0.001)
        XCTAssertEqual(sprint.pounceBlend(at: finishTime + 0.30, isPreparingReveal: false), 0.0, accuracy: 0.001)

        // Pause-katt lifecycle: hidden -> stroll -> stretch -> nap (zZz) -> scamper off
        XCTAssertEqual(PauseCatLifecycle.idleThresholdSeconds, 20.0)
        XCTAssertNil(PauseCatLifecycle.visualSnapshot(phase: .hidden, at: 10))

        let active = PauseCatPhase.active(enteredAt: 500.0)
        let strolling = PauseCatLifecycle.visualSnapshot(phase: active, at: 500.8)
        XCTAssertNotNil(strolling)
        XCTAssertGreaterThan(strolling?.xOffset ?? 0, 0)
        XCTAssertEqual(strolling?.facingRight, false)
        XCTAssertNil(strolling?.zzzElapsed)

        let stretching = PauseCatLifecycle.visualSnapshot(phase: active, at: 502.5)
        XCTAssertEqual(stretching?.xOffset ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(stretching?.facingRight, false)
        if case .stretching = stretching?.pose {} else {
            XCTFail("Expected stretching pose after stroll")
        }

        let napping = PauseCatLifecycle.visualSnapshot(phase: active, at: 504.5)
        XCTAssertNotNil(napping?.zzzElapsed)
        XCTAssertEqual(napping?.facingRight, false)
        if case .curledSleeping = napping?.pose {} else {
            XCTFail("Expected curledSleeping pose after stretch")
        }

        let reduceMotionNap = PauseCatLifecycle.visualSnapshot(phase: active, at: 500.1, reduceMotion: true)
        if case .curledSleeping = reduceMotionNap?.pose {} else {
            XCTFail("Expected static curledSleeping pose when Reduce Motion is enabled")
        }

        let scamper = PauseCatPhase.scamperingOff(startedAt: 600.0)
        let perked = PauseCatLifecycle.visualSnapshot(phase: scamper, at: 600.1)
        XCTAssertEqual(perked?.isAlertBadgeVisible, true)
        XCTAssertEqual(perked?.facingRight, false)
        let fleeing = PauseCatLifecycle.visualSnapshot(phase: scamper, at: 600.55)
        XCTAssertGreaterThan(fleeing?.xOffset ?? 0, 0)
        XCTAssertEqual(fleeing?.facingRight, true)
        XCTAssertNil(PauseCatLifecycle.visualSnapshot(phase: scamper, at: 601.0))

        XCTAssertEqual(PauseCatLifecycle.activeAnimationInterval, 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(PauseCatLifecycle.sleepingAnimationInterval, 1.0 / 12.0, accuracy: 0.0001)
        XCTAssertEqual(
            PauseCatLifecycle.timelineMinimumInterval(phase: active, at: 500.8),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PauseCatLifecycle.timelineMinimumInterval(phase: active, at: 502.5),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PauseCatLifecycle.timelineMinimumInterval(phase: active, at: 504.5),
            1.0 / 12.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PauseCatLifecycle.timelineMinimumInterval(phase: scamper, at: 600.2),
            1.0 / 30.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PauseCatLifecycle.timelineMinimumInterval(phase: .hidden, at: 0),
            1.0 / 12.0,
            accuracy: 0.0001
        )
    }
}
