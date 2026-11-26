import Foundation
import XCTest
@testable import Luna

final class DiskSWRStoreTests: XCTestCase {
    func testMemorySnapshotDiskPersistenceAndScopeIsolation() async throws {
        await DiskSWRStore.clearAllAsync()
        let testHost = "swr-host-\(UUID().uuidString.lowercased()).local"
        let jsonA = #"""
        {
          "ok": true,
          "layoutMode": "evening_4_row",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "rows": [
            {
              "rowId": "popular-movies",
              "title": "Populære filmer",
              "rowStyle": "poster",
              "items": [
                {
                  "itemId": "movie:tmdb:550",
                  "mediaType": "movie",
                  "ids": { "tmdb": 550 },
                  "title": "Fight Club"
                }
              ]
            }
          ]
        }
        """#
        let rawDataA = Data(jsonA.utf8)
        let decodedA = try JSONDecoder().decode(TvHomeResponse.self, from: rawDataA)

        DiskSWRStore.saveHomeInBackground(
            rawPayloadData: rawDataA,
            etag: "\"etag-v1\"",
            serverHost: testHost,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            decodedPayload: decodedA
        )

        // Immediate 0 ms memory snapshot hit
        let memHit = DiskSWRStore.memorySnapshot(
            serverHost: testHost,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714"
        )
        XCTAssertEqual(memHit?.etag, "\"etag-v1\"")
        XCTAssertEqual(memHit?.payload.roomName, "Kjellerstua")

        // Distinct room/profile or serverHost must stay isolated
        XCTAssertNil(
            DiskSWRStore.memorySnapshot(
                serverHost: testHost,
                roomName: "Stua",
                hardwareProfile: "hdr10-512"
            )
        )
        XCTAssertNil(
            DiskSWRStore.memorySnapshot(
                serverHost: "other-\(testHost)",
                roomName: "Kjellerstua",
                hardwareProfile: "dv-fel-714"
            )
        )

        // Drain detached utility write and verify disk bytes
        await DiskSWRStore.drainPendingWrites()
        let diskBytes = await DiskSWRStore.diskUsageBytesAsync()
        XCTAssertGreaterThan(diskBytes, 0)

        // Clear RAM cache and verify reload from disk restores payload + ETag
        DiskSWRStore.clearMemory()
        XCTAssertNil(
            DiskSWRStore.memorySnapshot(
                serverHost: testHost,
                roomName: "Kjellerstua",
                hardwareProfile: "dv-fel-714"
            )
        )

        let diskReloaded = await DiskSWRStore.loadHomeAsync(
            serverHost: testHost,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714"
        )
        XCTAssertEqual(diskReloaded?.etag, "\"etag-v1\"")
        XCTAssertEqual(diskReloaded?.payload.rows.first?.items.first?.title, "Fight Club")

        // Memory cache is repopulated after disk hit
        XCTAssertNotNil(
            DiskSWRStore.memorySnapshot(
                serverHost: testHost,
                roomName: "Kjellerstua",
                hardwareProfile: "dv-fel-714"
            )
        )

        // Hostless saves stay isolated under the fallback scope and never bleed into a fresh serverHost
        DiskSWRStore.saveHomeInBackground(
            rawPayloadData: rawDataA,
            etag: "\"legacy-etag\"",
            serverHost: nil,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            decodedPayload: nil
        )
        await DiskSWRStore.drainPendingWrites()
        DiskSWRStore.clearMemory()
        let freshHostLoaded = await DiskSWRStore.loadHomeAsync(
            serverHost: "fresh-host-\(UUID().uuidString).local",
            roomName: "Stua",
            hardwareProfile: "hdr10-512"
        )
        XCTAssertNil(freshHostLoaded)
        let hostlessLoaded = await DiskSWRStore.loadHomeAsync(
            serverHost: nil,
            roomName: "Stua",
            hardwareProfile: "hdr10-512"
        )
        XCTAssertEqual(hostlessLoaded?.etag, "\"legacy-etag\"")

        await DiskSWRStore.clearAllAsync()
        let afterClear = await DiskSWRStore.diskUsageBytesAsync()
        XCTAssertEqual(afterClear, 0)
    }

    func testClearAllAsyncCancelsPendingBackgroundWriteWithoutResurrectingSnapshot() async throws {
        await DiskSWRStore.clearAllAsync()
        let host = "swr-cancel-\(UUID().uuidString.lowercased()).local"
        let rawData = Data(#"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#.utf8)

        DiskSWRStore.saveHomeInBackground(
            rawPayloadData: rawData,
            etag: "\"etag-cancel\"",
            serverHost: host,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            decodedPayload: nil
        )
        await DiskSWRStore.clearAllAsync()
        await DiskSWRStore.drainPendingWrites()

        XCTAssertNil(DiskSWRStore.memorySnapshot(serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512"))
        let usageAfterClear = await DiskSWRStore.diskUsageBytesAsync()
        XCTAssertEqual(usageAfterClear, 0)
    }

    func testConcurrentMemoryReadsAndWritesUnderMutex() async throws {
        await DiskSWRStore.clearAllAsync()
        let host = "swr-race-\(UUID().uuidString.lowercased()).local"
        let json = #"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TvHomeResponse.self, from: data)

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<24 {
                group.addTask {
                    DiskSWRStore.saveHomeInBackground(
                        rawPayloadData: data,
                        etag: "\"e-\(idx)\"",
                        serverHost: host,
                        roomName: "Stua",
                        hardwareProfile: "hdr10-512",
                        decodedPayload: decoded
                    )
                    _ = DiskSWRStore.memorySnapshot(
                        serverHost: host,
                        roomName: "Stua",
                        hardwareProfile: "hdr10-512"
                    )
                }
            }
        }

        let snap = DiskSWRStore.memorySnapshot(
            serverHost: host,
            roomName: "Stua",
            hardwareProfile: "hdr10-512"
        )
        XCTAssertEqual(snap?.payload.roomName, "Stua")
        await DiskSWRStore.drainPendingWrites()
        await DiskSWRStore.clearAllAsync()
    }

    func testLoadHomeAsyncConcurrentWithClearAllAsyncNeverResurrectsMemorySnapshot() async throws {
        await DiskSWRStore.clearAllAsync()
        let host = "swr-loadclear-\(UUID().uuidString.lowercased()).local"
        let rawData = Data(#"{"ok":true,"roomName":"Stua","hardwareProfile":"hdr10-512","rows":[]}"#.utf8)

        for _ in 0..<8 {
            DiskSWRStore.saveHomeInBackground(
                rawPayloadData: rawData,
                etag: "\"etag-load-clear\"",
                serverHost: host,
                roomName: "Stua",
                hardwareProfile: "hdr10-512",
                decodedPayload: nil
            )
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = await DiskSWRStore.loadHomeAsync(
                        serverHost: host,
                        roomName: "Stua",
                        hardwareProfile: "hdr10-512"
                    )
                }
                group.addTask {
                    await DiskSWRStore.clearAllAsync()
                }
            }

            XCTAssertNil(DiskSWRStore.memorySnapshot(serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512"))
            let diskAfter = await DiskSWRStore.diskUsageBytesAsync()
            XCTAssertEqual(diskAfter, 0)
        }
    }

    func testMultiTabCatalogAndLibrarySWRPersistenceAndScopeIsolation() async throws {
        await DiskSWRStore.clearAllAsync()
        defer { Task { await DiskSWRStore.clearAllAsync() } }

        let host = "swr-multitab-\(UUID().uuidString.lowercased()).local"
        let movieCatalog = TvCatalogResponse(
            ok: true,
            mediaType: "movie",
            title: "Filmer",
            sort: "popular",
            localOnly: false,
            unwatchedOnly: false,
            page: 1,
            limit: 24,
            hasMore: true,
            items: [
                TvMediaCard(itemId: "movie:tmdb:693134", mediaType: "movie", ids: TvMediaIds(tmdb: 693134), title: "Dune: Part Two")
            ]
        )
        let catalogData = try JSONEncoder().encode(movieCatalog)
        DiskSWRStore.saveCatalogInBackground(
            rawPayloadData: catalogData,
            etag: "\"cat-movies-1\"",
            kind: "movie",
            serverHost: host,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            decodedPayload: movieCatalog
        )

        let libResp = TvLibraryResponse(
            ok: true,
            section: "lists",
            counts: TvLibraryCounts(watchlist: 1, localTotal: 2, localMovies: 1, localSeries: 1, nvme: 2, archive: 0, vfs: 0, customLists: 1, customListsCount: 1),
            watchlist: [],
            localItems: [],
            customLists: [
                TvLibraryCustomList(id: "custom:nordic", name: "Nordisk", itemCount: 4, browsePath: "/api/tv/v2/rows/custom%3Anordic")
            ]
        )
        let libData = try JSONEncoder().encode(libResp)
        DiskSWRStore.saveLibraryInBackground(
            rawPayloadData: libData,
            etag: "\"lib-lists-1\"",
            section: "lists",
            mediaType: "all",
            serverHost: host,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            decodedPayload: libResp
        )

        XCTAssertEqual(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")?.etag, "\"cat-movies-1\"")
        XCTAssertNil(DiskSWRStore.catalogMemorySnapshot(kind: "series", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512"))
        XCTAssertEqual(DiskSWRStore.libraryMemorySnapshot(section: "lists", mediaType: "all", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")?.payload.resolvedCustomLists.first?.name, "Nordisk")

        await DiskSWRStore.drainPendingWrites()
        DiskSWRStore.clearMemory()

        let reloadedCatalog = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
        let reloadedLibrary = await DiskSWRStore.loadLibraryAsync(section: "lists", mediaType: "all", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512")
        XCTAssertEqual(reloadedCatalog?.etag, "\"cat-movies-1\"")
        XCTAssertEqual(reloadedCatalog?.payload.items.first?.title, "Dune: Part Two")
        XCTAssertEqual(reloadedLibrary?.etag, "\"lib-lists-1\"")
        XCTAssertEqual(reloadedLibrary?.payload.resolvedCustomLists.count, 1)
    }
}
