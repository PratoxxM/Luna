import XCTest
@testable import Luna

final class ModelDecodingTests: XCTestCase {
    func testDecodeHomeResponseAndVfsAvailability() throws {
        let json = #"""
        {
          "ok": true,
          "layoutMode": "evening_4_row",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "rows": [
            {
              "rowId": "continue_watching",
              "title": "Fortsett å se",
              "rowStyle": "landscape",
              "hasMore": false,
              "items": [
                {
                  "itemId": "tmdb:movie:550",
                  "mediaType": "movie",
                  "ids": { "tmdb": 550, "imdb": "tt0137523" },
                  "title": "Eksempelfilm",
                  "year": 2024,
                  "availability": { "state": "instant", "tier": "vfs" },
                  "progress": { "positionSeconds": 1200, "durationSeconds": 7200, "percent": 16.6, "watched": false }
                }
              ]
            }
          ]
        }
        """#

        let decoded = try JSONDecoder().decode(TvHomeResponse.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.rows.count, 1)
        let card = try XCTUnwrap(decoded.rows.first?.items.first)
        XCTAssertEqual(card.availability?.isLocalVfs, true)
        XCTAssertEqual(card.availability?.isPhysicalLocal, false)
        XCTAssertEqual(card.availability?.householdBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(card.progress?.percent ?? 0, 16.6, accuracy: 0.01)
    }

    func testDecodeItemDetailOverviewPriority() throws {
        let json = #"""
        {
          "itemId": "tmdb:movie:999",
          "mediaType": "movie",
          "ids": { "tmdb": 999 },
          "title": "Nordlys",
          "overview": "Fallback overview",
          "overviewNo": "Norsk beskrivelse først",
          "overviewEn": "English overview",
          "inWatchlist": true,
          "watched": false,
          "monitored": true,
          "monitorMode": "all"
        }
        """#

        let detail = try JSONDecoder().decode(TvItemDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.preferredOverview, "Norsk beskrivelse først")
        XCTAssertTrue(detail.inWatchlist)
        XCTAssertTrue(detail.isMonitoredFlag)
    }

    func testDecodePlaybackSessionAndCandidateBadges() throws {
        let json = #"""
        {
          "sessionId": "sess-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "tmdb:movie:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K Remux DV FEL",
            "releaseTitle": "Eksempelfilm.2024.2160p.UHD.BluRay.REMUX",
            "source": "nvme",
            "tier": "nvme",
            "resolution": "2160p",
            "dvProfile": 7,
            "dvEnhancementLayer": "fel",
            "audioCodec": "TrueHD Atmos",
            "sizeBytes": 53687091200
          },
          "stream": {
            "url": "/api/tv/v1/streams/sess-1/master",
            "supportsByteRanges": true,
            "canClientPrewarmBytes": true
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "dolbyVisionHandling": "fel",
            "matchContentEnabled": true,
            "audioBridgeMode": "objectAudio"
          }
        }
        """#

        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.stream.canClientPrewarmBytes, true)
        XCTAssertEqual(
            session.selectedCandidate.quickRowTitle(roomName: "Kjellerstua", isRecommended: true),
            "Anbefalt for Kjellerstua · 4K Dolby Vision FEL TrueHD Atmos"
        )
        XCTAssertEqual(session.selectedCandidate.quickRowMetadata(activeLabel: nil), "På NVMe · 50,0 GB")
    }

    func testVfsCandidateSourceBadgeAndPhysicalAvailability() throws {
        let vfsJson = #"""
        [
          {
            "candidateId": "vfs-1",
            "displayHeadline": "4K WEB-DL",
            "releaseTitle": "Example.2026.2160p",
            "source": "local",
            "tier": "infinidysk"
          },
          {
            "candidateId": "vfs-2",
            "displayHeadline": "1080p WEB-DL",
            "releaseTitle": "Example.2026.1080p",
            "source": "infinidysk",
            "tier": "vfs"
          }
        ]
        """#
        let candidates = try JSONDecoder().decode([TvCandidateInfo].self, from: Data(vfsJson.utf8))
        XCTAssertEqual(candidates.map(\.sourceBadgeLabel), ["Strømmes ved start", "Strømmes ved start"])

        let nvmeAvail = TvAvailabilityInfo(state: "instant", tier: "nvme")
        XCTAssertTrue(nvmeAvail.isPhysicalLocal)
        XCTAssertEqual(nvmeAvail.householdBadgeLabel, "På NVMe")

        let vfsAvail = TvAvailabilityInfo(state: "on_demand", tier: "vfs")
        XCTAssertFalse(vfsAvail.isPhysicalLocal)
        XCTAssertTrue(vfsAvail.isLocalVfs)
        XCTAssertEqual(vfsAvail.householdBadgeLabel, "Strømmes ved start")
    }

    @MainActor
    func testComfortPreferencesDefaultsOverridesAndAudioShaping() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults, memoryTier: .standard)
        XCTAssertEqual(comfort.subtitleBoxOpacity, .none)
        XCTAssertEqual(comfort.subtitleBoxOpacity.alpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(comfort.hdrSubtitlePreset, .warm75)
        XCTAssertEqual(comfort.lowResUpscaleMode, .off)
        XCTAssertNil(defaults.string(forKey: SideloadSafeStorage.lowResUpscaleModeKey))

        let highComfort = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
        XCTAssertEqual(highComfort.lowResUpscaleMode, .auto)
        XCTAssertNil(defaults.string(forKey: SideloadSafeStorage.lowResUpscaleModeKey))
        XCTAssertEqual(LowResUpscaleMode.allCases.map(\.displayTitle), ["Av", "Auto", "Animasjon"])
        XCTAssertEqual(LowResUpscaleMode.allCases.map(\.rawValue), ["off", "auto", "line_art"])

        highComfort.lowResUpscaleMode = .off
        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.lowResUpscaleModeKey), "off")
        XCTAssertEqual(ComfortPreferences(defaults: defaults, memoryTier: .high2026).lowResUpscaleMode, .off)

        defaults.set("line_art", forKey: SideloadSafeStorage.lowResUpscaleModeKey)
        XCTAssertEqual(ComfortPreferences(defaults: defaults, memoryTier: .high2026).lowResUpscaleMode, .animeLineArt)

        var syncCalls = 0
        comfort.onSyncRequested = { _ in
            syncCalls += 1
        }
        comfort.adoptServerOverrides(
            TvDeviceOverrides(
                dualLayerOverride: "force_on",
                speakerLayoutOverride: "2.0",
                hdrSubtitlePreset: "soft_50",
                subtitleFontScale: 1.2,
                subtitleBoxOpacity: 0.35,
                autoPlayNextEpisode: false,
                smartNordicSubtitleRule: false
            )
        )
        XCTAssertEqual(syncCalls, 0)
        XCTAssertEqual(comfort.dualLayerOverride, .forceOn)
        XCTAssertEqual(comfort.speakerLayoutOverride, .stereo)
        XCTAssertEqual(comfort.hdrSubtitlePreset, .soft50)
        XCTAssertEqual(comfort.subtitleFontSize, .large)
        XCTAssertEqual(comfort.subtitleBoxOpacity, .subtle35)
        XCTAssertFalse(comfort.autoPlayNextEpisode)
        XCTAssertFalse(comfort.smartNordicSubtitleRule)

        let stereoRef = comfort.buildAudioShaping(enhancement: .reference)
        XCTAssertEqual(stereoRef.maxChannels, 2)
        XCTAssertEqual(stereoRef.lfeMixDB, -6.0)

        let stereoDialogue = comfort.buildAudioShaping(enhancement: .dialogueLift)
        XCTAssertEqual(stereoDialogue.maxChannels, 2)
        XCTAssertEqual(stereoDialogue.lfeMixDB, -6.0)

        let stereoNight = comfort.buildAudioShaping(enhancement: .nightMode)
        XCTAssertEqual(stereoNight.maxChannels, 2)
        XCTAssertEqual(stereoNight.loudnessTargetLUFS, -20.0)
        XCTAssertEqual(stereoNight.lfeMixDB, -6.0)

        comfort.speakerLayoutOverride = .auto
        let autoRef = comfort.buildAudioShaping(enhancement: .reference)
        XCTAssertNil(autoRef.maxChannels)
        XCTAssertNil(autoRef.lfeMixDB)

        let autoNight = comfort.buildAudioShaping(enhancement: .nightMode)
        XCTAssertNil(autoNight.maxChannels)
        XCTAssertNil(autoNight.lfeMixDB)
    }

    func testFrontPageCardCleanSubtitlesAndUpcomingPills() {
        let genericContinue = TvMediaCard(
            itemId: "series:tmdb:100",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 100),
            title: "Kompani Lauritzen",
            episodeCode: "S05E13",
            episodeTitle: "Episode 13",
            nextUp: TvNextUpPointer(season: 5, episode: 13)
        )
        XCTAssertNil(genericContinue.nonGenericEpisodeTitle)
        XCTAssertEqual(genericContinue.cleanContinueSubtitle, "Neste · S5 · E13")

        let epAliasCard = TvMediaCard(
            itemId: "series:tmdb:101",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 101),
            title: "Eksempelserie",
            episodeCode: "S01E05",
            episodeTitle: "Ep 5",
            nextUp: TvNextUpPointer(season: 1, episode: 5)
        )
        XCTAssertNil(epAliasCard.nonGenericEpisodeTitle)

        let delAliasCard = TvMediaCard(
            itemId: "series:tmdb:102",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 102),
            title: "Eksempelserie",
            episodeCode: "S01E02",
            episodeTitle: "Del 2",
            nextUp: TvNextUpPointer(season: 1, episode: 2)
        )
        XCTAssertNil(delAliasCard.nonGenericEpisodeTitle)

        let namedContinue = TvMediaCard(
            itemId: "series:tmdb:103",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 103),
            title: "Kompani Lauritzen",
            episodeCode: "S05E13",
            episodeTitle: "Finaleuke",
            nextUp: TvNextUpPointer(season: 5, episode: 13)
        )
        XCTAssertEqual(namedContinue.nonGenericEpisodeTitle, "Finaleuke")
        XCTAssertEqual(namedContinue.cleanContinueSubtitle, "Neste · S5 · E13 · Finaleuke")

        let inProgressSeries = TvMediaCard(
            itemId: "series:tmdb:104",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 104),
            title: "Luksusfellen",
            episodeCode: "S28E05",
            episodeTitle: "Episode 5",
            nextUp: TvNextUpPointer(season: 28, episode: 5),
            progress: TvWatchProgress(positionSeconds: 900, durationSeconds: 2700, percent: 33.3, season: 28, episode: 5, watched: false)
        )
        XCTAssertEqual(inProgressSeries.cleanContinueSubtitle, "S28 · E5 · 30 min igjen")

        let upcomingGeneric = TvMediaCard(
            itemId: "series:tmdb:105",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 105),
            title: "Dexter: Resurrection",
            daysUntil: 2,
            episodeCode: "S02E03",
            episodeTitle: "Episode 3",
            airDateBadge: "På søndag · S02E03",
            nextUp: TvNextUpPointer(season: 2, episode: 3)
        )
        XCTAssertEqual(upcomingGeneric.upcomingPillText, "På søndag")
        XCTAssertFalse(upcomingGeneric.isUrgentUpcoming)
        XCTAssertEqual(upcomingGeneric.cleanUpcomingSubtitle, "Sesong 2 · Episode 3")

        let upcomingUrgent = TvMediaCard(
            itemId: "series:tmdb:106",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 106),
            title: "Dexter: Resurrection",
            daysUntil: 1,
            episodeCode: "S02E06",
            episodeTitle: "Finaleuke",
            airDateBadge: "I morgen · S02E06",
            nextUp: TvNextUpPointer(season: 2, episode: 6)
        )
        XCTAssertEqual(upcomingUrgent.upcomingPillText, "I morgen")
        XCTAssertTrue(upcomingUrgent.isUrgentUpcoming)
        XCTAssertEqual(upcomingUrgent.cleanUpcomingSubtitle, "S2 · E6 · Finaleuke")
    }

    func testDetailRatingsAndHeartbeatPrewarmReadyDecoding() throws {
        let detailJson = """
        {
          "itemId": "movie:tmdb:1184918",
          "mediaType": "movie",
          "ids": {"tmdb": 1184918, "imdb": "tt29623480"},
          "title": "Den ville roboten",
          "voteAverage": 8.3,
          "rating": 8.6,
          "imdbRating": 8.5,
          "imdbVotes": 145000,
          "rottenTomatoesScore": 97,
          "metacriticScore": 85,
          "inWatchlist": false,
          "watched": false
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(TvItemDetail.self, from: detailJson)
        XCTAssertEqual(detail.imdbRating, 8.5)
        XCTAssertEqual(detail.displayRating?.value, 8.5)
        XCTAssertEqual(detail.displayRating?.isImdb, true)

        let hbJson = """
        {
          "ok": true,
          "sessionId": "sess-1",
          "state": "playing",
          "nextEpisodePrewarm": {
            "itemId": "episode:tmdb:95396:s1:e2",
            "sessionId": "tvs_next",
            "streamUrl": "/api/tv/v1/stream/tvs_next/sig/ep2.mkv",
            "canClientPrewarmBytes": true,
            "nextEpisode": {
              "itemId": "episode:tmdb:95396:s1:e2",
              "season": 1,
              "episode": 2,
              "title": "Episode 2"
            }
          }
        }
        """.data(using: .utf8)!

        let hb = try JSONDecoder().decode(TvHeartbeatResponse.self, from: hbJson)
        XCTAssertEqual(hb.sessionId, "sess-1")
        XCTAssertEqual(hb.state, "playing")
        XCTAssertEqual(hb.nextEpisodePrewarm?.sessionId, "tvs_next")
        XCTAssertEqual(hb.nextEpisodePrewarm?.canClientPrewarmBytes, true)
        XCTAssertEqual(hb.nextEpisodePrewarm?.nextEpisode?.episode, 2)
    }

    func testDecodeM7aPhoneOriginBenefitLabelAndNorwegianCandidateTiers() throws {
        let json = #"""
        {
          "ok": true,
          "layout": "rows_first",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "equipmentLabel": "LG OLED · Dolby Vision · 7.1.4",
          "atmosphere": "cinema",
          "tonight": {
            "ok": true,
            "reason": "next_episode",
            "reasonLabel": "Neste klare episode",
            "preparedFromPhone": {
              "itemId": "series:tmdb:95396",
              "mediaType": "series",
              "ids": { "tmdb": 95396 },
              "title": "Severance",
              "origin": "phone",
              "originLabel": "Fra iPhone",
              "preparedSessionId": "prep-phone-42",
              "availability": {
                "state": "instant",
                "tier": "ssd",
                "benefitLabel": "Starter umiddelbart"
              },
              "directPlayTarget": {
                "itemId": "episode:tmdb:95396:s2:e4",
                "mediaType": "episode",
                "season": 2,
                "episode": 4,
                "startPositionSeconds": 1390,
                "mode": "resume",
                "prepareToken": "prep-phone-42"
              }
            }
          },
          "rows": []
        }
        """#

        let decoded = try JSONDecoder().decode(TvHomeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.layout, "rows_first")
        XCTAssertEqual(decoded.atmosphere, "cinema")
        XCTAssertEqual(decoded.equipmentLabel, "LG OLED · Dolby Vision · 7.1.4")
        let phoneCard = try XCTUnwrap(decoded.tonight?.preparedFromPhone)
        XCTAssertEqual(phoneCard.origin, "phone")
        XCTAssertEqual(phoneCard.originLabel, "Fra iPhone")
        XCTAssertEqual(phoneCard.directPlayTarget?.prepareToken, "prep-phone-42")
        XCTAssertEqual(phoneCard.availability?.resolvedBenefitLabel, "Starter umiddelbart")

        let candJson = #"""
        [
          {
            "candidateId": "u-1",
            "displayHeadline": "4K WEB-DL",
            "releaseTitle": "Example.2026.2160p",
            "source": "usenet",
            "tier": "usenet"
          },
          {
            "candidateId": "r-1",
            "displayHeadline": "1080p",
            "releaseTitle": "Example.2026.1080p",
            "source": "remote"
          },
          {
            "candidateId": "e-1",
            "displayHeadline": "1080p Easynews",
            "releaseTitle": "Example.2026.1080p.Easynews",
            "source": "easynews",
            "tier": "ssd"
          }
        ]
        """#
        let cands = try JSONDecoder().decode([TvCandidateInfo].self, from: Data(candJson.utf8))
        XCTAssertEqual(cands[0].sourceBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(cands[1].sourceBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(cands[2].sourceBadgeLabel, "Arkiv-strøm (HTTPS)")
        XCTAssertFalse(cands.map(\.sourceBadgeLabel).contains("USENET"))
        XCTAssertFalse(cands.map(\.sourceBadgeLabel).contains("REMOTE"))
    }

    func testDecodeLibraryWithoutFavoritesAndPendingRemoteCommands() throws {
        let minimalLibraryJson = #"""
        {
          "ok": true,
          "section": "watchlist",
          "counts": {
            "watchlist": 2,
            "localTotal": 5,
            "nvme": 4,
            "archive": 1,
            "vfs": 0,
            "customLists": 1
          },
          "watchlist": [],
          "localItems": []
        }
        """#
        let lib = try JSONDecoder().decode(TvLibraryResponse.self, from: Data(minimalLibraryJson.utf8))
        XCTAssertEqual(lib.counts.watchlist, 2)
        XCTAssertEqual(lib.counts.localTotal, 5)

        let nextCmdJson = #"{"type":"next_episode","issuedAt":"2026-11-19T19:00:00Z"}"#
        let nextCmd = try JSONDecoder().decode(TvPendingCommand.self, from: Data(nextCmdJson.utf8))
        XCTAssertEqual(nextCmd.type, "next_episode")
        XCTAssertEqual(nextCmd.issuedAt, "2026-11-19T19:00:00Z")

        let subsCmdJson = #"{"type":"subtitles_on","language":"no"}"#
        let subsCmd = try JSONDecoder().decode(TvPendingCommand.self, from: Data(subsCmdJson.utf8))
        XCTAssertEqual(subsCmd.type, "subtitles_on")
        XCTAssertEqual(subsCmd.language, "no")
    }

    func testTvCandidateInfoResilientNumericAndChannelDecoding() throws {
        let json = #"""
        [
          {
            "candidateId": "num-2ch",
            "displayHeadline": "1080p WEB-DL",
            "releaseTitle": "Example.1080p.WEB-DL",
            "source": "nvme",
            "tier": "nvme",
            "resolution": "1080p",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "channels": 2,
            "sizeBytes": 3221225472.0,
            "tvScore": 910.4,
            "isNorwegian": 1
          },
          {
            "candidateId": "num-6ch",
            "displayHeadline": "4K HDR10+",
            "releaseTitle": "Example.2160p.HDR10P",
            "source": "ssd",
            "tier": "nvme",
            "resolution": "2160p",
            "videoRangeType": "HDR10Plus",
            "audioCodec": "EAC3",
            "channels": 6,
            "tvScore": "980"
          }
        ]
        """#

        let decoded = try JSONDecoder().decode([TvCandidateInfo].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].channels, "2.0")
        XCTAssertEqual(decoded[0].sizeBytes, 3_221_225_472)
        XCTAssertEqual(decoded[0].tvScore, 910)
        XCTAssertEqual(decoded[0].isNorwegian, true)
        XCTAssertEqual(decoded[1].channels, "5.1")
        XCTAssertEqual(decoded[1].tvScore, 980)
        XCTAssertEqual(decoded[1].quickRowTitle(roomName: "Stua", isRecommended: true), "Anbefalt for Stua · 4K HDR10+ Dolby Digital+ 5.1")
    }
}
