import CoreGraphics
import Foundation
import MediaPlayer
import XCTest
@testable import Luna

final class PlayerOverlayAndCacheTests: XCTestCase {
    func testArtworkPipelineRawIdentityAndCacheKeyDeduplication() throws {
        let lanHostA = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v1/artwork/123?w=600"))
        let lanHostB = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v1/artwork/123?w=600"))
        XCTAssertEqual(ArtworkPipeline.rawIdentity(for: lanHostA), ArtworkPipeline.rawIdentity(for: lanHostB))
        XCTAssertNotEqual(
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 480),
            ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 960)
        )

        let extA = try XCTUnwrap(URL(string: "https://cdn-one.example.net/poster.jpg"))
        let extB = try XCTUnwrap(URL(string: "https://cdn-two.example.net/poster.jpg"))
        XCTAssertNotEqual(ArtworkPipeline.rawIdentity(for: extA), ArtworkPipeline.rawIdentity(for: extB))
    }

    @MainActor
    func testComfortPreferencesSkipsDuplicateSetterSyncNotifications() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        var syncCount = 0
        comfort.onSyncRequested = { _ in
            syncCount += 1
        }

        // Re-assigning current value must not trigger redundant server syncs
        let initialPreset = comfort.hdrSubtitlePreset
        comfort.hdrSubtitlePreset = initialPreset
        XCTAssertEqual(syncCount, 0)

        comfort.hdrSubtitlePreset = .soft50
        XCTAssertEqual(syncCount, 1)

        // Assigning an identical override payload must be a complete no-op
        let snapshot = comfort.toDeviceOverrides()
        comfort.adoptServerOverrides(snapshot)
        XCTAssertEqual(syncCount, 1)
    }

    @MainActor
    func testSessionStoreSyncFromBootstrapUpdatesAvailableRoomsIdempotently() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSessionStore(defaults: defaults)
        let customRooms = [
            TvRoomDefinition(roomName: "Kino", hardwareProfile: "dv-fel-714", label: "Kino 7.1.4"),
            TvRoomDefinition(roomName: "Loft", hardwareProfile: "hdr10-512", label: "Loft 5.1.2"),
        ]
        let device = TvPairedDeviceInfo(
            deviceId: store.deviceID,
            deviceName: "Living Room Apple TV",
            roomName: "Kino",
            hardwareProfile: "dv-fel-714",
            overrides: TvDeviceOverrides(hdrSubtitlePreset: "warm_75")
        )

        store.syncFromBootstrap(device, defaultRooms: customRooms)
        XCTAssertEqual(store.roomName, "Kino")
        XCTAssertEqual(store.hardwareProfile, "dv-fel-714")
        XCTAssertEqual(store.availableRooms, customRooms)
    }

    func testNowPlayingArtworkRequestHandlerIsSafeOffMainActor() async throws {
        struct UncheckedArtworkBox: @unchecked Sendable {
            let artwork: MPMediaItemArtwork
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 16,
            height: 24,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            XCTFail("Failed to allocate test CGImage")
            return
        }

        let box = await MainActor.run {
            UncheckedArtworkBox(artwork: NowPlayingArtworkFactory.makeArtwork(cgImage: cgImage))
        }

        let renderedSize = await Task.detached(priority: .userInitiated) {
            box.artwork.image(at: CGSize(width: 16, height: 24))?.size
        }.value

        XCTAssertEqual(renderedSize?.width, 16)
        XCTAssertEqual(renderedSize?.height, 24)
    }

    @MainActor
    func testComfortPreferencesAudioDelayPersistenceAndClamping() {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        var syncCount = 0
        comfort.onSyncRequested = { _ in
            syncCount += 1
        }

        XCTAssertEqual(comfort.audioDelayMs, 0)
        XCTAssertEqual(comfort.audioDelaySeconds, 0, accuracy: 0.0001)
        XCTAssertEqual(comfort.formattedAudioDelayLabel, "0 ms")

        comfort.adjustAudioDelay(byMs: -25)
        comfort.adjustAudioDelay(byMs: -10)
        XCTAssertEqual(comfort.audioDelayMs, -35)
        XCTAssertEqual(comfort.audioDelaySeconds, -0.035, accuracy: 0.0001)
        XCTAssertEqual(comfort.formattedAudioDelayLabel, "-35 ms")
        XCTAssertEqual(syncCount, 0)

        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.audioDelayMs, -35)
        XCTAssertEqual(reloaded.audioDelaySeconds, -0.035, accuracy: 0.0001)
        XCTAssertEqual(reloaded.formattedAudioDelayLabel, "-35 ms")

        reloaded.adoptServerOverrides(TvDeviceOverrides(hdrSubtitlePreset: "soft_50"))
        XCTAssertEqual(reloaded.audioDelayMs, -35)

        reloaded.audioDelayMs = -5000
        XCTAssertEqual(reloaded.audioDelayMs, -2000)
        reloaded.audioDelayMs = 5000
        XCTAssertEqual(reloaded.audioDelayMs, 2000)

        reloaded.resetAudioDelay()
        XCTAssertEqual(reloaded.audioDelayMs, 0)
        XCTAssertEqual(reloaded.formattedAudioDelayLabel, "0 ms")
        XCTAssertEqual(syncCount, 0)
    }

    @MainActor
    func testBuildLoadOptionsForwardsPersistedNegativeAudioDelay() throws {
        let suite = "luna.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Failed to allocate isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let json = #"""
        {
          "sessionId": "sess-sync-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "tmdb:movie:550",
            "mediaType": "movie",
            "ids": { "tmdb": 550 },
            "title": "Eksempelfilm"
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10+ WEB-DL",
            "releaseTitle": "Eksempelfilm.2024.2160p.WEB-DL",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": {
            "url": "/api/tv/v1/streams/sess-sync-1/master"
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#

        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(json.utf8))
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "luna-test-device",
            deviceToken: nil,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )

        let comfort = ComfortPreferences(defaults: defaults)
        comfort.audioDelayMs = -45

        let options = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: comfort.audioDelaySeconds
        )
        XCTAssertEqual(options.audioDelaySeconds, -0.045, accuracy: 0.0001)
    }
}
