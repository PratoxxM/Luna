import Foundation
import XCTest
@testable import LunaCore

final class ModelDecodingAndContractsTests: XCTestCase {
    // MARK: - Home, Tonight, Front-Page Cards & Availability

    func testDecodeHomeResponseTonightHandoffAndFrontPageCardFormatting() throws {
        let json = #"""
        {
          "ok": true,
          "layout": "rows_first",
          "layoutMode": "evening_4_row",
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
        XCTAssertEqual(decoded.layout, "rows_first")
        XCTAssertEqual(decoded.atmosphere, "cinema")
        XCTAssertEqual(decoded.equipmentLabel, "LG OLED · Dolby Vision · 7.1.4")

        let phoneCard = try XCTUnwrap(decoded.tonight?.preparedFromPhone)
        XCTAssertEqual(phoneCard.origin, "phone")
        XCTAssertEqual(phoneCard.originLabel, "Fra iPhone")
        XCTAssertEqual(phoneCard.directPlayTarget?.prepareToken, "prep-phone-42")
        XCTAssertEqual(phoneCard.availability?.resolvedBenefitLabel, "Starter umiddelbart")

        let vfsCard = try XCTUnwrap(decoded.rows.first?.items.first)
        XCTAssertEqual(vfsCard.availability?.isLocalVfs, true)
        XCTAssertEqual(vfsCard.availability?.isPhysicalLocal, false)
        XCTAssertEqual(vfsCard.availability?.householdBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(vfsCard.progress?.percent ?? 0, 16.6, accuracy: 0.01)

        let nvmeAvail = TvAvailabilityInfo(state: "instant", tier: "nvme")
        XCTAssertTrue(nvmeAvail.isPhysicalLocal)
        XCTAssertEqual(nvmeAvail.householdBadgeLabel, "På NVMe")

        // Front-page continue & upcoming subtitle formatting
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

        let namedContinue = TvMediaCard(
            itemId: "series:tmdb:103",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 103),
            title: "Kompani Lauritzen",
            episodeCode: "S05E13",
            episodeTitle: "Finaleuke",
            nextUp: TvNextUpPointer(season: 5, episode: 13)
        )
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

        let specialUpcoming = TvMediaCard(
            itemId: "series:tmdb:100",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 100),
            title: "Show",
            nextUp: TvNextUpPointer(season: 0, episode: 2)
        )
        XCTAssertEqual(specialUpcoming.cleanUpcomingSubtitle, "Spesialer · Episode 2")
    }

    // MARK: - Detail, Cast, Ratings, Heartbeat, Library & Delete Models

    func testDecodeItemDetailHeartbeatLibraryAlternativesAndDeleteModels() throws {
        let detailJSON = #"""
        {
          "itemId": "series:tmdb:95396",
          "mediaType": "series",
          "ids": { "tmdb": 95396, "imdb": "tt11280740" },
          "title": "Severance",
          "originalTitle": "Severance",
          "tagline": "We're all different people.",
          "overview": "Fallback overview",
          "overviewNo": "Norsk beskrivelse først",
          "overviewEn": "English overview",
          "voteAverage": 8.3,
          "imdbRating": 8.7,
          "imdbVotes": 340000,
          "rottenTomatoesScore": 97,
          "metacriticScore": 83,
          "cast": ["Adam Scott"],
          "castMembers": [
            { "name": "Adam Scott", "character": "Mark Scout", "profileUrl": "/img/adam.jpg" },
            { "name": "Britt Lower", "character": "Helly Riggs", "profileUrl": null }
          ],
          "inWatchlist": true,
          "watched": false,
          "monitored": true,
          "monitorMode": "all",
          "nextUp": { "season": 1, "episode": 1 },
          "nextEpisode": {
            "itemId": "episode:tmdb:95396:s1:e2",
            "season": 1,
            "episode": 2,
            "title": "Half Loop",
            "runtimeSeconds": 3300
          }
        }
        """#
        let detail = try JSONDecoder().decode(TvItemDetail.self, from: Data(detailJSON.utf8))
        XCTAssertEqual(detail.preferredOverview, "Norsk beskrivelse først")
        XCTAssertTrue(detail.inWatchlist)
        XCTAssertTrue(detail.isMonitoredFlag)
        XCTAssertEqual(detail.displayRating?.value, 8.7)
        XCTAssertEqual(detail.displayRating?.isImdb, true)
        XCTAssertEqual(detail.castMembers?.count, 2)
        XCTAssertNil(detail.castMembers?[1].profileUrl)
        XCTAssertEqual(detail.rottenTomatoesScore, 97)
        XCTAssertEqual(detail.metacriticScore, 83)
        XCTAssertEqual(detail.imdbVotes, 340000)
        XCTAssertEqual(detail.tagline, "We're all different people.")
        XCTAssertEqual(detail.nextEpisode?.runtimeSeconds, 3300)

        let hbJSON = #"""
        {
          "ok": true,
          "sessionId": "tvs_active",
          "state": "playing",
          "nextEpisodePrewarm": {
            "itemId": "episode:tmdb:95396:s1:e2",
            "sessionId": "tvs_next85",
            "streamToken": "0123456789abcdef0123456789abcdef",
            "streamUrl": "/api/tv/v2/stream/tvs_next85/sig/Severance.S01E02.mkv",
            "canClientPrewarmBytes": true,
            "nextEpisode": { "itemId": "episode:tmdb:95396:s1:e2", "season": 1, "episode": 2, "title": "Half Loop" }
          }
        }
        """#
        let hb = try JSONDecoder().decode(TvHeartbeatResponse.self, from: Data(hbJSON.utf8))
        XCTAssertEqual(hb.nextEpisodePrewarm?.sessionId, "tvs_next85")
        XCTAssertEqual(hb.nextEpisodePrewarm?.canClientPrewarmBytes, true)
        XCTAssertEqual(hb.nextEpisodePrewarm?.nextEpisode?.title, "Half Loop")

        let nextCmd = try JSONDecoder().decode(TvPendingCommand.self, from: Data(#"{"type":"next_episode","issuedAt":"2026-11-19T19:00:00Z"}"#.utf8))
        let subsCmd = try JSONDecoder().decode(TvPendingCommand.self, from: Data(#"{"type":"subtitles_on","language":"no"}"#.utf8))
        XCTAssertEqual(nextCmd.type, "next_episode")
        XCTAssertEqual(subsCmd.language, "no")

        let libJSON = #"""
        {"ok":true,"section":"lists","counts":{"watchlist":2,"localTotal":396,"localMovies":312,"localSeries":84,"nvme":350,"archive":46,"vfs":0,"customListsCount":1},"watchlist":[],"localItems":[],"customLists":[{"id":"custom:nordic","name":"Nordisk","itemCount":5,"browsePath":"/api/tv/v2/rows/custom:nordic"}]}
        """#
        let lib = try JSONDecoder().decode(TvLibraryResponse.self, from: Data(libJSON.utf8))
        XCTAssertEqual(lib.counts.localMovies, 312)
        XCTAssertEqual(lib.counts.localSeries, 84)
        XCTAssertEqual(lib.counts.resolvedCustomListsCount, 1)
        XCTAssertEqual(lib.resolvedCustomLists.first?.name, "Nordisk")

        let altNullSession = try JSONDecoder().decode(
            TvAlternativesResponse.self,
            from: Data(#"{"ok":true,"sessionId":null,"roomName":"Stua","hardwareProfile":"hdr10-512","activeCandidateId":"cand-1","alternatives":[]}"#.utf8)
        )
        XCTAssertEqual(altNullSession.sessionId, "")
        XCTAssertEqual(altNullSession.activeCandidateId, "cand-1")

        let unassigned = try JSONDecoder().decode(
            TvPairedDeviceInfo.self,
            from: Data(#"{"deviceId":"d1","deviceName":"TV","roomName":"Stua","roomUnassigned":true,"hardwareProfile":"hdr10-512"}"#.utf8)
        )
        XCTAssertEqual(unassigned.roomUnassigned, true)

        let rowPage = try JSONDecoder().decode(
            TvRowPageResponse.self,
            from: Data(#"{"ok":true,"rowId":"custom:mine-pagaende-serier","sourceKind":"active_series","title":"Mine pågående serier","offset":0,"limit":36,"hasMore":false,"items":[]}"#.utf8)
        )
        XCTAssertEqual(rowPage.sourceKind, "active_series")

        // Delete preflight & target headings
        let preflightJSON = #"""
        {
          "checkedAt": "2026-11-18T00:10:00Z",
          "preflightId": "pf_abc123456789",
          "target": { "kind": "series", "scope": "season", "season": 2, "title": "Severance", "monitored": true, "canRemoveFromLibrary": false },
          "files": { "count": 10, "logicalBytes": 53687091200, "physicalBytes": 53687091200, "ssdBytes": 53687091200, "archiveBytes": 0, "vfsCount": 0 },
          "blockers": [{ "code": "active_playback", "message": "Opptatt i Stua", "sessionId": "sess-9", "roomName": "Stua" }]
        }
        """#
        let preflight = try JSONDecoder().decode(TvDeletePreflightResponse.self, from: Data(preflightJSON.utf8))
        XCTAssertEqual(preflight.preflightId, "pf_abc123456789")
        XCTAssertEqual(preflight.files.freedDisplayBytes, 53_687_091_200)
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: preflight.files.freedDisplayBytes), "50,00 GB")
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: 42 * 1_048_576), "42 MB")
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: 0), "0 GB")
        XCTAssertEqual(preflight.blockers.first?.code, "active_playback")

        XCTAssertEqual(TvDeleteRequestTarget(kind: "movie", itemId: "m1", tmdbId: 550, title: "Fight Club", scope: .title).dialogHeading, "Slett filmen")
        XCTAssertEqual(TvDeleteRequestTarget(kind: "series", itemId: "e1", tmdbId: 1399, title: "GoT", scope: .episode, season: 1, episode: 2).dialogHeading, "Slett episode")
        XCTAssertEqual(TvDeleteRequestTarget(kind: "series", itemId: "s1", tmdbId: 1399, title: "GoT", scope: .season, season: 3).dialogHeading, "Slett sesong 3")
        XCTAssertEqual(TvDeleteRequestTarget(kind: "series", itemId: "s1", tmdbId: 1399, title: "GoT", scope: .series).dialogHeading, "Slett hele serien")
    }

    // MARK: - Playback Session, Candidate Badges, Hardware Routing & Extreme Numeric Bounds

    func testCandidateBadgesHardwareRoutingSessionTracksAndExtremeNumericBounds() throws {
        let sessionJSON = #"""
        {
          "sessionId": "sess-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": { "itemId": "tmdb:movie:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Eksempelfilm" },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K Remux DV FEL",
            "releaseTitle": "Eksempelfilm.2024.2160p.UHD.BluRay.REMUX",
            "source": "nvme",
            "tier": "nvme",
            "resolution": "2160p",
            "videoCodec": "hevc",
            "dvProfile": 7,
            "dvEnhancementLayer": "fel",
            "audioCodec": "TrueHD Atmos",
            "sizeBytes": 53687091200,
            "explanationChips": ["På NVMe", "Dolby Vision"],
            "releaseGroup": "FraMeSToR"
          },
          "stream": { "url": "/api/tv/v2/streams/sess-1/master", "supportsByteRanges": true, "canClientPrewarmBytes": true },
          "tracks": {
            "probeConfidence": "cached_ffprobe",
            "subtitleDelayMs": 0,
            "video": { "streamIndex": 0, "codec": "hevc", "width": 3840, "height": 2160, "frameRate": 23.976, "videoRangeType": "HDR10Plus", "hdr10Plus": true },
            "audio": [{ "streamIndex": 1, "codec": "truehd", "spatialFormat": "DolbyAtmos", "channels": 8, "channelLayout": "7.1", "language": "eng", "displayTitle": "Atmos", "isDefault": true }],
            "embeddedSubtitles": [{ "streamIndex": 2, "codec": "subrip", "language": "nob", "displayTitle": "Norsk", "isForced": false, "isDefault": true }]
          },
          "aetherConfig": { "preferDualLayerDolbyVision": true, "dolbyVisionHandling": "fel", "matchContentEnabled": true, "audioBridgeMode": "objectAudio" }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        XCTAssertEqual(session.stream.canClientPrewarmBytes, true)
        XCTAssertEqual(session.tracks?.video?.hdr10Plus, true)
        XCTAssertEqual(session.tracks?.audio?.first?.spatialFormat, "DolbyAtmos")
        XCTAssertEqual(session.tracks?.embeddedSubtitles?.first?.streamIndex, 2)
        XCTAssertEqual(session.selectedCandidate.quickRowTitle(isRecommended: true), "Anbefalt · 4K Dolby Vision P7 FEL TrueHD Atmos")
        XCTAssertEqual(session.selectedCandidate.quickRowMetadata(activeLabel: nil), "På NVMe · HEVC · 50,0 GB")
        XCTAssertEqual(session.selectedCandidate.deduplicatedExplanationChips(excluding: ["på nvme"], maxCount: 2), ["Dolby Vision"])
        XCTAssertTrue(session.selectedCandidate.richRowSubtitle(isRecommended: true, activeLabel: "Spilles nå", compactForQuickPanel: false).contains("FraMeSToR"))
        XCTAssertTrue(session.selectedCandidate.canCarryDualLayerDolbyVision)
        XCTAssertTrue(session.selectedCandidate.allowsDualLayerDolbyVisionWhenForced)
        XCTAssertFalse(session.selectedCandidate.requiresSoftwareVideoDecode(supportsHardwareAV1: true))

        // Source badges & resilient numeric decoding
        let tiersJSON = #"""
        [
          { "candidateId": "v1", "source": "infinidysk", "tier": "vfs" },
          { "candidateId": "u1", "source": "usenet", "tier": "usenet" },
          { "candidateId": "e1", "source": "easynews", "tier": "ssd" },
          { "candidateId": "n2", "source": "nvme", "tier": "nvme", "resolution": "1080p", "videoRangeType": "SDR", "videoCodec": "av1", "channels": 2, "sizeBytes": 3221225472.0, "tvScore": 910.4, "isNorwegian": 1 },
          { "candidateId": "n6", "source": "ssd", "tier": "nvme", "resolution": "2160p", "videoRangeType": "HDR10Plus", "videoCodec": "vp9", "audioCodec": "EAC3", "channels": 6, "tvScore": "980" }
        ]
        """#
        let cands = try JSONDecoder().decode([TvCandidateInfo].self, from: Data(tiersJSON.utf8))
        XCTAssertEqual(cands[0].sourceBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(cands[1].sourceBadgeLabel, "Strømmes ved start")
        XCTAssertEqual(cands[2].sourceBadgeLabel, "Arkiv-strøm (HTTPS)")
        XCTAssertEqual(cands[3].channels, "2.0")
        XCTAssertEqual(cands[3].sizeBytes, 3_221_225_472)
        XCTAssertEqual(cands[3].tvScore, 910)
        XCTAssertEqual(cands[3].isNorwegian, true)
        XCTAssertTrue(cands[3].isLikelyFullHDSDRForUpscale)
        XCTAssertFalse(cands[3].requiresSoftwareVideoDecode(supportsHardwareAV1: true))
        XCTAssertTrue(cands[3].requiresSoftwareVideoDecode(supportsHardwareAV1: false))
        XCTAssertEqual(cands[4].channels, "5.1")
        XCTAssertEqual(cands[4].tvScore, 980)
        XCTAssertEqual(cands[4].quickRowTitle(isRecommended: true), "Anbefalt · 4K HDR10+ Dolby Digital+ 5.1")
        XCTAssertTrue(cands[4].requiresSoftwareVideoDecode(supportsHardwareAV1: true))

        // Out-of-range finite Doubles in decodeFlexInt & formatters never trap
        for rawNum in ["1e30", "-1e30", "9223372036854775808.0"] {
            let payload = #"{"candidateId":"cand-extreme","source":"nvme","dvProfile":\#(rawNum),"sizeBytes":\#(rawNum),"tvScore":\#(rawNum),"channels":\#(rawNum)}"#
            let extremeCand = try JSONDecoder().decode(TvCandidateInfo.self, from: Data(payload.utf8))
            XCTAssertNil(extremeCand.dvProfile)
            XCTAssertNil(extremeCand.sizeBytes)
            XCTAssertNil(extremeCand.tvScore)
            XCTAssertNil(extremeCand.channels)
        }
        let epExtreme = TvEpisodeCard(itemId: "ep1", seasonNumber: 1, episodeNumber: 1, title: "T", runtimeSeconds: 1e30, watched: false)
        XCTAssertNil(epExtreme.formattedRuntime)
        let cardExtreme = TvMediaCard(itemId: "m1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "T", progress: TvWatchProgress(positionSeconds: 20, durationSeconds: 1e30, percent: 1))
        XCTAssertEqual(cardExtreme.cleanContinueSubtitle, "Film")
    }

    // MARK: - LunaCopy, DeviceHardwareCapabilities & PreviewLaunchConfiguration

    func testLunaCopyLocalizationHardwareCapabilitiesAndPreviewCLI() {
        XCTAssertEqual(LunaCopy.plural(0, "mediefil", "mediefiler"), "0 mediefiler")
        XCTAssertEqual(LunaCopy.plural(1, "mediefil", "mediefiler"), "1 mediefil")
        XCTAssertEqual(LunaCopy.plural(3, "mediefil", "mediefiler"), "3 mediefiler")
        XCTAssertEqual(LunaCopy.plural(Int.min, "treff", "treff"), "\(Int.min) treff")
        XCTAssertEqual(LunaCopy.plural(-1, "treff", "treff"), "-1 treff")
        XCTAssertTrue(LunaCopy.searchHits(Int.min).contains("\(Int.min)"))
        XCTAssertTrue(LunaCopy.episodesCount(Int.min).contains("\(Int.min)"))
        XCTAssertTrue(LunaCopy.seasonsCount(Int.min).contains("\(Int.min)"))
        XCTAssertTrue(LunaCopy.mediaFilesCount(Int.min).contains("\(Int.min)"))

        XCTAssertEqual(LunaCopy.searchHits(1), "1 treff")
        XCTAssertEqual(LunaCopy.episodesCount(6), "6 episoder")
        XCTAssertEqual(LunaCopy.seasonsCount(3), "3 sesonger")
        XCTAssertEqual(LunaCopy.formatListEpisodeCode("S28E06"), "S28 · E6")
        XCTAssertEqual(LunaCopy.formatListEpisodeCode(season: 0, episode: 2), "S0 · E2")
        XCTAssertEqual(LunaCopy.formatDecimal(7.9), "7,9")
        XCTAssertEqual(LunaCopy.formatRating(8.4), "★ 8,4")
        XCTAssertEqual(LunaCopy.formatGigabytes(64.25, decimals: 1), "64,2 GB")
        XCTAssertEqual(LunaCopy.formatMegabytes(12.3), "12,3 MB")
        XCTAssertEqual(LunaCopy.localizedSeasonTitle("Season 28", seasonNumber: 28), "Sesong 28")
        XCTAssertEqual(LunaCopy.localizedSeasonTitle("Specials", seasonNumber: 0), "Spesialer")
        XCTAssertEqual(LunaCopy.localizedLanguageName("swe"), "Svensk")
        XCTAssertEqual(LunaCopy.localizedLanguageName("nob"), "Norsk")
        XCTAssertEqual(LunaCopy.localizedLanguageName("ara"), "Arabisk")

        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "nvme"), "Starter umiddelbart")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "archive"), "Fra arkivet")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "vfs"), "Strømmes ved start")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "usenet", state: "upcoming"), "Kommer")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "dv-fel-714"), "LG OLED · Dolby Vision · Sonos 7.1.4")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "hdr10-512"), "Samsung Frame Pro · HDR10+ · Sonos 5.1.2")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "custom", roomName: "Gjestestue"), "Apple TV 4K · Direkte avspilling")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "dv-fel-714", roomName: "Kjellerstua", serverLabel: "Egen kino"), "Egen kino")

        XCTAssertEqual(LunaCopy.friendlyErrorMessage(LunaCoreError.serverMessage(503, "Database opptatt")), "Database opptatt")
        XCTAssertEqual(LunaCopy.friendlyErrorMessage(URLError(.timedOut)), "LunaCore svarte ikke i tide. Prøv igjen om et øyeblikk.")
        XCTAssertEqual(
            LunaCopy.friendlyEngineErrorMessage("Source refused the session's credentials (HTTP 401) (code 401)"),
            "Strømmen utløp eller ble avvist (HTTP 401). Prøv på nytt eller velg en annen utgave."
        )
        XCTAssertEqual(LunaCopy.friendlyEngineErrorMessage("HTTP 404 Not Found"), "Fant ikke videostrømmen på serveren (HTTP 404). Prøv en annen utgave.")
        XCTAssertEqual(LunaCopy.friendlyEngineErrorMessage("Request timed out"), "Tidsavbrudd mot videokilden. Prøv på nytt eller velg en annen utgave.")
        XCTAssertEqual(LunaCopy.friendlyEngineErrorMessage("   "), "Avspillingsfeil i strømmen.")

        XCTAssertEqual(DeviceHardwareCapabilities.roundedGigabytes(for: 4 * 1_073_741_824), 4)
        XCTAssertEqual(DeviceHardwareCapabilities.roundedGigabytes(for: 8 * 1_073_741_824), 8)
        XCTAssertFalse(DeviceHardwareCapabilities.isHighMemory(physicalMemoryBytes: 4 * 1_073_741_824))
        XCTAssertTrue(DeviceHardwareCapabilities.isHighMemory(physicalMemoryBytes: 8 * 1_073_741_824))

        // Preview CLI parsing across all targets and aliases
        XCTAssertNil(PreviewLaunchConfiguration.parse(arguments: ["Luna"]))
        let homeCfg = PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "home", "--preview-focus", "right"])
        XCTAssertEqual(homeCfg?.screen, .home)
        XCTAssertEqual(homeCfg?.focusDirection, .right)
        XCTAssertEqual(PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen=player", "--preview-focus=down"])?.screen, .playerSubtitles)
        XCTAssertEqual(PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "settings-advanced"])?.screen, .settingsAudio)
        XCTAssertEqual(PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", "settings-system"])?.screen, .settingsDiagnostics)
        for target in PreviewScreenTarget.allCases {
            XCTAssertEqual(PreviewLaunchConfiguration.parse(arguments: ["Luna", "--preview-screen", target.rawValue])?.screen, target)
        }
    }
}
