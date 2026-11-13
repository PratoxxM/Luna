import Foundation
import XCTest
@testable import Luna

final class PlayerOverlayAndCacheTests: XCTestCase {
    func testArtworkPipelineRawIdentityAndCacheKeyDeduplication() throws {
        let lanHostA = try XCTUnwrap(URL(string: "http://mediaos.local:8090/api/tv/v1/artwork/123?w=600"))
        let lanHostB = try XCTUnwrap(URL(string: "https://mediaos.example.test:8920/api/tv/v1/artwork/123?w=600"))
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
}
