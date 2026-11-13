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
        XCTAssertEqual(card.availability?.householdBadgeLabel, "Klar i VFS")
        XCTAssertEqual(card.progress?.percent ?? 0, 16.6, accuracy: 0.01)
    }

    func testDecodeItemDetailOverviewPriorityAndCastMembers() throws {
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
          "isFavorite": true,
          "watched": false,
          "castMembers": [
            { "name": "Skuespiller En", "character": "Kaptein", "profileUrl": "/api/tv/v1/img/cast-1" }
          ]
        }
        """#

        let detail = try JSONDecoder().decode(TvItemDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.preferredOverview, "Norsk beskrivelse først")
        XCTAssertTrue(detail.favoriteFlag)
        XCTAssertEqual(detail.castMembers?.first?.name, "Skuespiller En")
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
        XCTAssertEqual(session.selectedCandidate.capabilityBadges, [
            "På NVMe",
            "2160P",
            "DV P7 FEL",
            "TrueHD Atmos",
            "50.0 GB",
        ])
    }

    @MainActor
    func testComfortPreferencesDefaultsOverridesAndAudioShaping() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(comfort.subtitleBoxOpacity, .none)
        XCTAssertEqual(comfort.subtitleBoxOpacity.alpha, 0.0, accuracy: 0.001)
        XCTAssertEqual(comfort.hdrSubtitlePreset, .warm75)
        XCTAssertEqual(comfort.lowResUpscaleMode, .off)

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
        XCTAssertNil(stereoNight.lfeMixDB)

        comfort.speakerLayoutOverride = .auto
        let autoRef = comfort.buildAudioShaping(enhancement: .reference)
        XCTAssertNil(autoRef.maxChannels)
        XCTAssertNil(autoRef.lfeMixDB)
    }
}
