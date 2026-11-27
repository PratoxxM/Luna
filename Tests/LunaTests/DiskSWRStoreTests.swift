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

    private func withCleanDiskSWRStore(_ body: () async throws -> Void) async throws {
        await DiskSWRStore.clearAllAsync()
        do {
            try await body()
        } catch {
            await DiskSWRStore.clearAllAsync()
            throw error
        }
        await DiskSWRStore.clearAllAsync()
    }

    func testMultiTabCatalogAndLibrarySWRPersistenceAndScopeIsolation() async throws {
        try await withCleanDiskSWRStore {
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

    private func makePaddedHomeData(roomName: String, marker: String, padLength: Int = 320) throws -> Data {
        let payload = TvHomeResponse(
            ok: true,
            roomName: roomName,
            hardwareProfile: "hdr10-512",
            rows: [
                TvShelfRow(
                    rowId: "row-\(marker)",
                    title: marker + "-" + String(repeating: "x", count: padLength),
                    rowStyle: "poster",
                    items: []
                )
            ]
        )
        return try JSONEncoder().encode(payload)
    }

    func testMultiRoomDiskCapPruningAndPairedFileEviction() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-tvos-prune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_100)
        for idx in 1...4 {
            let room = "Room\(idx)"
            let data = try makePaddedHomeData(roomName: room, marker: "m\(idx)")
            await actor.saveToDisk(rawPayloadData: data, etag: "\"e\(idx)\"", baseName: "home-host-\(room)")
            let mtime = Date(timeIntervalSince1970: 1_700_000_000 + Double(idx * 10))
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: tempDir.appendingPathComponent("home-host-\(room).json").path)
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: tempDir.appendingPathComponent("home-host-\(room).meta.json").path)
        }
        let latest = try makePaddedHomeData(roomName: "Room5", marker: "m5")
        await actor.saveToDisk(rawPayloadData: latest, etag: "\"e5\"", baseName: "home-host-Room5")

        let usage = await actor.diskUsageBytes()
        XCTAssertLessThanOrEqual(usage, 1_100)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(files.contains("home-host-Room1.json"))
        XCTAssertFalse(files.contains("home-host-Room1.meta.json"))
        let reloaded = await actor.loadFromDisk(baseName: "home-host-Room5", as: TvHomeResponse.self)
        XCTAssertEqual(reloaded?.etag, "\"e5\"")
    }

    func testReadTouchLRUPromotionOversizedProtectionAndPublicTrim() async throws {
        XCTAssertEqual(DiskSWRStore.defaultMaxBytes, 16 * 1024 * 1024)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-tvos-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataA = try makePaddedHomeData(roomName: "Stua", marker: "A")
        let dataB = try makePaddedHomeData(roomName: "Kjeller", marker: "B")
        let dataC = try makePaddedHomeData(roomName: "Kino", marker: "C")

        let writer = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 10_000)
        await writer.saveToDisk(rawPayloadData: dataA, etag: "\"eA\"", baseName: "home-a")
        await writer.saveToDisk(rawPayloadData: dataB, etag: "\"eB\"", baseName: "home-b")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        for ext in [".json", ".meta.json"] {
            try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: tempDir.appendingPathComponent("home-a\(ext)").path)
            try FileManager.default.setAttributes([.modificationDate: t1], ofItemAtPath: tempDir.appendingPathComponent("home-b\(ext)").path)
        }

        let reader = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_200)
        _ = await reader.loadFromDisk(baseName: "home-a", as: TvHomeResponse.self)
        await reader.saveToDisk(rawPayloadData: dataC, etag: "\"eC\"", baseName: "home-c")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains("home-a.json"))
        XCTAssertFalse(files.contains("home-b.json"))
        XCTAssertTrue(files.contains("home-c.json"))

        // Oversized newly written file is never self-deleted; maxBytes = 0 clears everything.
        let huge = try makePaddedHomeData(roomName: "Huge", marker: "H", padLength: 1_200)
        await reader.saveToDisk(rawPayloadData: huge, etag: "\"huge\"", baseName: "home-huge")
        let hugeLoaded = await reader.loadFromDisk(baseName: "home-huge", as: TvHomeResponse.self)
        XCTAssertNotNil(hugeLoaded)
        await reader.trimDiskCache(maxBytes: 0)
        let usageAfterZero = await reader.diskUsageBytes()
        XCTAssertEqual(usageAfterZero, 0)

        // Public facade trimDiskCacheAsync + maxDiskBytes background pruning
        await DiskSWRStore.clearAllAsync()
        let host = "swr-tvos-pub-\(UUID().uuidString.lowercased()).local"
        DiskSWRStore.saveHomeInBackground(rawPayloadData: dataA, etag: "\"pubA\"", serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
        await DiskSWRStore.drainPendingWrites()
        try await Task.sleep(nanoseconds: 15_000_000)
        DiskSWRStore.saveHomeInBackground(rawPayloadData: dataB, etag: "\"pubB\"", serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512", maxDiskBytes: 750)
        await DiskSWRStore.drainPendingWrites()
        DiskSWRStore.clearMemory()

        let pubRoomA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
        let pubRoomB = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
        XCTAssertNil(pubRoomA)
        XCTAssertEqual(pubRoomB?.etag, "\"pubB\"")
        await DiskSWRStore.clearAllAsync()
    }

    func testSingleActorSubHourReadTouchLRUPromotion() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-tvos-single-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dataA = try makePaddedHomeData(roomName: "Stua", marker: "sA", padLength: 300)
        let dataB = try makePaddedHomeData(roomName: "Kjeller", marker: "sB", padLength: 300)
        let dataC = try makePaddedHomeData(roomName: "Kino", marker: "sC", padLength: 300)

        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_200)
        await actor.saveToDisk(rawPayloadData: dataA, etag: "\"eA\"", baseName: "home-a")
        try await Task.sleep(nanoseconds: 25_000_000)
        await actor.saveToDisk(rawPayloadData: dataB, etag: "\"eB\"", baseName: "home-b")
        try await Task.sleep(nanoseconds: 25_000_000)

        let hitA = await actor.loadFromDisk(baseName: "home-a", as: TvHomeResponse.self)
        XCTAssertEqual(hitA?.etag, "\"eA\"")

        await actor.saveToDisk(rawPayloadData: dataC, etag: "\"eC\"", baseName: "home-c")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains("home-a.json"))
        XCTAssertTrue(files.contains("home-c.json"))
        XCTAssertFalse(files.contains("home-b.json"))
        XCTAssertFalse(files.contains("home-b.meta.json"))

        try await withCleanDiskSWRStore {
            let host = "swr-tvos-single-\(UUID().uuidString.lowercased()).local"
            DiskSWRStore.saveHomeInBackground(rawPayloadData: dataA, etag: "\"rA\"", serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 25_000_000)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: dataB, etag: "\"rB\"", serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 25_000_000)

            DiskSWRStore.clearMemory()
            let promotedRoomA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            XCTAssertEqual(promotedRoomA?.etag, "\"rA\"")

            DiskSWRStore.clearMemory()
            DiskSWRStore.saveHomeInBackground(rawPayloadData: dataC, etag: "\"rC\"", serverHost: host, roomName: "RoomC", hardwareProfile: "hdr10-512", maxDiskBytes: 1_200)
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            let finalRoomA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            let finalRoomB = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            let finalRoomC = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomC", hardwareProfile: "hdr10-512")
            XCTAssertEqual(finalRoomA?.etag, "\"rA\"")
            XCTAssertNil(finalRoomB)
            XCTAssertEqual(finalRoomC?.etag, "\"rC\"")
        }
    }
}
