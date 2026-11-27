import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import XCTest
@testable import LunaCore

actor DiskSWRTestGate {
    static let shared = DiskSWRTestGate()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        while isLocked {
            await withCheckedContinuation { waiters.append($0) }
        }
        isLocked = true
        defer {
            isLocked = false
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
        let lockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-diskswr-test.lock")
            .path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 {
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try await operation()
    }
}

final class DiskSWRStoreMultiTabLinuxTests: XCTestCase {
    func testMultiTabDiskSWRPersistenceRaceAndClearAll() async throws {
        try await DiskSWRTestGate.shared.withLock {
            try await Self.runMultiTabDiskSWRChecks()
        }
    }

    private static func runMultiTabDiskSWRChecks() async throws {
        await DiskSWRStore.clearAllAsync()

        let host = "swr-linux-\(UUID().uuidString.lowercased()).local"
        let homePayload = TvHomeResponse(
            ok: true,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            rows: [
                TvShelfRow(
                    rowId: "popular-movies",
                    title: "Populære filmer",
                    rowStyle: "poster",
                    items: [TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club")]
                )
            ]
        )
        let moviesPayload = TvCatalogResponse(
            ok: true,
            mediaType: "movie",
            title: "Filmer",
            sort: "popular",
            localOnly: false,
            unwatchedOnly: false,
            page: 1,
            limit: 24,
            hasMore: true,
            availableGenres: [
                TvGenreChip(slug: "drama", label: "Drama", icon: nil, accentColor: nil, tmdbGenreIds: [18], browsePath: "/api/tv/v2/catalog/movies?genre=drama", catalogPath: nil)
            ],
            items: [TvMediaCard(itemId: "movie:tmdb:693134", mediaType: "movie", ids: TvMediaIds(tmdb: 693134), title: "Dune: Part Two")]
        )
        let seriesPayload = TvCatalogResponse(
            ok: true,
            mediaType: "series",
            title: "Serier",
            sort: "popular",
            localOnly: false,
            unwatchedOnly: false,
            page: 1,
            limit: 24,
            hasMore: false,
            items: [TvMediaCard(itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396), title: "Severance")]
        )
        let libraryListsPayload = TvLibraryResponse(
            ok: true,
            section: "lists",
            counts: TvLibraryCounts(watchlist: 1, localTotal: 2, localMovies: 1, localSeries: 1, nvme: 2, archive: 0, vfs: 0, customLists: 2, customListsCount: 2),
            watchlist: [],
            localItems: [],
            customLists: [
                TvLibraryCustomList(id: "custom:nordic", name: "Nordisk", itemCount: 5, browsePath: "/api/tv/v2/rows/custom%3Anordic")
            ]
        )

        DiskSWRStore.saveHomeInBackground(
            rawPayloadData: try JSONEncoder().encode(homePayload),
            etag: "\"home-etag\"",
            serverHost: host,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            decodedPayload: homePayload
        )
        DiskSWRStore.saveCatalogInBackground(
            rawPayloadData: try JSONEncoder().encode(moviesPayload),
            etag: "\"movies-etag\"",
            kind: "movie",
            serverHost: host,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            decodedPayload: moviesPayload
        )
        DiskSWRStore.saveCatalogInBackground(
            rawPayloadData: try JSONEncoder().encode(seriesPayload),
            etag: "\"series-etag\"",
            kind: "series",
            serverHost: host,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            decodedPayload: seriesPayload
        )
        DiskSWRStore.saveLibraryInBackground(
            rawPayloadData: try JSONEncoder().encode(libraryListsPayload),
            etag: "\"lib-lists-etag\"",
            section: "lists",
            mediaType: "all",
            serverHost: host,
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            decodedPayload: libraryListsPayload
        )

        XCTAssertEqual(DiskSWRStore.memorySnapshot(serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"home-etag\"")
        XCTAssertEqual(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"movies-etag\"")
        XCTAssertEqual(DiskSWRStore.catalogMemorySnapshot(kind: "series", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"series-etag\"")
        XCTAssertEqual(DiskSWRStore.libraryMemorySnapshot(section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"lib-lists-etag\"")

        // Scope isolation by room/host
        XCTAssertNil(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512"))
        XCTAssertNil(DiskSWRStore.libraryMemorySnapshot(section: "local", mediaType: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714"))

        await DiskSWRStore.drainPendingWrites()
        let bytes = await DiskSWRStore.diskUsageBytesAsync()
        XCTAssertGreaterThan(bytes, 0)

        DiskSWRStore.clearMemory()
        XCTAssertNil(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714"))
        XCTAssertNil(DiskSWRStore.libraryMemorySnapshot(section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714"))

        let loadedMovies = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
        let loadedSeries = await DiskSWRStore.loadCatalogAsync(kind: "series", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
        let loadedLibrary = await DiskSWRStore.loadLibraryAsync(section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")

        XCTAssertEqual(loadedMovies?.etag, "\"movies-etag\"")
        XCTAssertEqual(loadedMovies?.payload.items.first?.title, "Dune: Part Two")
        XCTAssertEqual(loadedSeries?.etag, "\"series-etag\"")
        XCTAssertEqual(loadedSeries?.payload.items.first?.title, "Severance")
        XCTAssertEqual(loadedLibrary?.etag, "\"lib-lists-etag\"")
        XCTAssertEqual(loadedLibrary?.payload.resolvedCustomLists.first?.name, "Nordisk")

        // Verify concurrent load + clearAllAsync never resurrects memory or disk files
        await DiskSWRStore.clearAllAsync()
        let raceHost = "swr-race-\(UUID().uuidString.lowercased()).local"
        let catData = try JSONEncoder().encode(moviesPayload)
        let libData = try JSONEncoder().encode(libraryListsPayload)

        for _ in 0..<6 {
            DiskSWRStore.saveCatalogInBackground(rawPayloadData: catData, etag: "\"c1\"", kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            DiskSWRStore.saveLibraryInBackground(rawPayloadData: libData, etag: "\"l1\"", section: "local", mediaType: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
                }
                group.addTask {
                    _ = await DiskSWRStore.loadLibraryAsync(section: "local", mediaType: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
                }
                group.addTask {
                    await DiskSWRStore.clearAllAsync()
                }
            }

            XCTAssertNil(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512"))
            XCTAssertNil(DiskSWRStore.libraryMemorySnapshot(section: "local", mediaType: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512"))
            let diskBytes = await DiskSWRStore.diskUsageBytesAsync()
            XCTAssertEqual(diskBytes, 0)
        }
    }

    private static func makePaddedHomeData(roomName: String, marker: String, padLength: Int = 320) throws -> Data {
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

    func testMultiRoomAndServerPruningEvictsOldestPairedEntriesOnWrite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-prune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let d1 = try Self.makePaddedHomeData(roomName: "Stua", marker: "s1")
        let d2 = try Self.makePaddedHomeData(roomName: "Kjellerstua", marker: "s2")
        let d3 = try Self.makePaddedHomeData(roomName: "Soverom", marker: "s3")
        let d4 = try Self.makePaddedHomeData(roomName: "Kino", marker: "s4")

        // Each entry is ~450-500 B (.json + .meta.json). maxBytes = 1100 triggers prune to <= 880 B.
        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_100)
        let scopes = [
            ("home-server_a-stua-hdr10-512", d1, "\"e1\""),
            ("home-server_a-kjellerstua-hdr10-512", d2, "\"e2\""),
            ("home-server_b-soverom-hdr10-512", d3, "\"e3\""),
            ("home-server_c-kino-hdr10-512", d4, "\"e4\""),
        ]
        for (idx, item) in scopes.enumerated() {
            await actor.saveToDisk(rawPayloadData: item.1, etag: item.2, baseName: item.0)
            let mtime = Date(timeIntervalSince1970: 1_700_000_000 + Double(idx * 10))
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: tempDir.appendingPathComponent("\(item.0).json").path)
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: tempDir.appendingPathComponent("\(item.0).meta.json").path)
        }
        // Trigger prune via final write
        let d5 = try Self.makePaddedHomeData(roomName: "Kontor", marker: "s5")
        await actor.saveToDisk(rawPayloadData: d5, etag: "\"e5\"", baseName: "home-server_d-kontor-hdr10-512")

        let usage = await actor.diskUsageBytes()
        XCTAssertLessThanOrEqual(usage, 1_100)

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(files.contains("home-server_a-stua-hdr10-512.json"))
        XCTAssertFalse(files.contains("home-server_a-stua-hdr10-512.meta.json"), "Paired .meta.json must be removed with .json")

        let newest = await actor.loadFromDisk(baseName: "home-server_d-kontor-hdr10-512", as: TvHomeResponse.self)
        XCTAssertEqual(newest?.etag, "\"e5\"")
        XCTAssertEqual(newest?.payload.roomName, "Kontor")
    }

    func testReadTouchLRUPromotionPreventsEvictionOfActiveScope() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dA = try Self.makePaddedHomeData(roomName: "Stua", marker: "scopeA")
        let dB = try Self.makePaddedHomeData(roomName: "Kjellerstua", marker: "scopeB")
        let dC = try Self.makePaddedHomeData(roomName: "Kino", marker: "scopeC")

        let writer = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 10_000)
        await writer.saveToDisk(rawPayloadData: dA, etag: "\"eA\"", baseName: "home-scope-a")
        await writer.saveToDisk(rawPayloadData: dB, etag: "\"eB\"", baseName: "home-scope-b")

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        for ext in [".json", ".meta.json"] {
            try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: tempDir.appendingPathComponent("home-scope-a\(ext)").path)
            try FileManager.default.setAttributes([.modificationDate: t1], ofItemAtPath: tempDir.appendingPathComponent("home-scope-b\(ext)").path)
        }

        // Fresh actor (cold-launch read) touches scope A, promoting its mtime past scope B.
        // Each entry is ~450 B; 3 entries = ~1350 B > 1200 B (target 960 B), keeping 2 entries (~900 B).
        let reader = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_200)
        let hitA = await reader.loadFromDisk(baseName: "home-scope-a", as: TvHomeResponse.self)
        XCTAssertEqual(hitA?.etag, "\"eA\"")

        await reader.saveToDisk(rawPayloadData: dC, etag: "\"eC\"", baseName: "home-scope-c")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains("home-scope-a.json"), "Read-promoted scope A must survive LRU pruning")
        XCTAssertFalse(files.contains("home-scope-b.json"), "Oldest untouched scope B must be evicted")
        XCTAssertFalse(files.contains("home-scope-b.meta.json"))
        XCTAssertTrue(files.contains("home-scope-c.json"))
    }

    func testSingleActorSubHourReadTouchLRUPreventsEvictionOfActiveScope() async throws {
        // Part A: Isolated single DiskSWRStorageActor within 3600s DiskTouchTracker window
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-single-lru-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dA = try Self.makePaddedHomeData(roomName: "Stua", marker: "sA", padLength: 300)
        let dB = try Self.makePaddedHomeData(roomName: "Kjeller", marker: "sB", padLength: 300)
        let dC = try Self.makePaddedHomeData(roomName: "Kino", marker: "sC", padLength: 300)

        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_200)
        await actor.saveToDisk(rawPayloadData: dA, etag: "\"eA\"", baseName: "home-a")
        try await Task.sleep(nanoseconds: 25_000_000)
        await actor.saveToDisk(rawPayloadData: dB, etag: "\"eB\"", baseName: "home-b")
        try await Task.sleep(nanoseconds: 25_000_000)

        // Read on the SAME actor within 3600s (DiskTouchTracker suppresses disk mtime touch)
        let hitA = await actor.loadFromDisk(baseName: "home-a", as: TvHomeResponse.self)
        XCTAssertEqual(hitA?.etag, "\"eA\"")

        await actor.saveToDisk(rawPayloadData: dC, etag: "\"eC\"", baseName: "home-c")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains("home-a.json"), "Single-actor sub-hour read must protect home-a from eviction")
        XCTAssertTrue(files.contains("home-c.json"))
        XCTAssertFalse(files.contains("home-b.json"), "Untouched home-b must be evicted instead of MRU home-a")
        XCTAssertFalse(files.contains("home-b.meta.json"))

        // Part B: Public DiskSWRStore singleton facade under DiskSWRTestGate
        try await DiskSWRTestGate.shared.withLock {
            await DiskSWRStore.clearAllAsync()
            let host = "swr-single-facade-\(UUID().uuidString.lowercased()).local"
            let fA = try Self.makePaddedHomeData(roomName: "RoomA", marker: "fA", padLength: 300)
            let fB = try Self.makePaddedHomeData(roomName: "RoomB", marker: "fB", padLength: 300)
            let fC = try Self.makePaddedHomeData(roomName: "RoomC", marker: "fC", padLength: 300)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: fA, etag: "\"rA\"", serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 25_000_000)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: fB, etag: "\"rB\"", serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 25_000_000)

            DiskSWRStore.clearMemory()
            let loadedA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            XCTAssertEqual(loadedA?.etag, "\"rA\"")

            DiskSWRStore.clearMemory()
            DiskSWRStore.saveHomeInBackground(rawPayloadData: fC, etag: "\"rC\"", serverHost: host, roomName: "RoomC", hardwareProfile: "hdr10-512", maxDiskBytes: 1_200)
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            let afterA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            let afterB = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            let afterC = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomC", hardwareProfile: "hdr10-512")
            XCTAssertEqual(afterA?.etag, "\"rA\"")
            XCTAssertNil(afterB)
            XCTAssertEqual(afterC?.etag, "\"rC\"")
            await DiskSWRStore.clearAllAsync()
        }
    }

    func testOversizedNewEntryIsProtectedAndOrphanMetaAndZeroTrimAreHandled() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-edge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let smallData = try Self.makePaddedHomeData(roomName: "Stua", marker: "small", padLength: 40)
        let hugeData = try Self.makePaddedHomeData(roomName: "Kino", marker: "huge", padLength: 800)

        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 300)
        await actor.saveToDisk(rawPayloadData: smallData, etag: "\"small\"", baseName: "home-small")
        // Plant an orphan .meta.json
        try Data(#"{"etag":"\"orphan\""}"#.utf8).write(to: tempDir.appendingPathComponent("orphan.meta.json"))

        await actor.saveToDisk(rawPayloadData: hugeData, etag: "\"huge\"", baseName: "home-huge")

        let filesAfterHuge = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(filesAfterHuge.contains("orphan.meta.json"), "Orphan .meta.json must be cleaned up when pruning")
        XCTAssertFalse(filesAfterHuge.contains("home-small.json"))
        XCTAssertTrue(filesAfterHuge.contains("home-huge.json"), "Newly written oversized entry must never delete itself")
        let loadedHuge = await actor.loadFromDisk(baseName: "home-huge", as: TvHomeResponse.self)
        XCTAssertEqual(loadedHuge?.etag, "\"huge\"")

        await actor.trimDiskCache(maxBytes: 0)
        let usageAfterZero = await actor.diskUsageBytes()
        XCTAssertEqual(usageAfterZero, 0)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPublicTrimDiskCacheAsyncAndDefaultMaxBytesUnderGate() async throws {
        try await DiskSWRTestGate.shared.withLock {
            XCTAssertEqual(DiskSWRStore.defaultMaxBytes, 16 * 1024 * 1024)
            await DiskSWRStore.clearAllAsync()

            let host = "swr-public-trim-\(UUID().uuidString.lowercased()).local"
            let dataA = try Self.makePaddedHomeData(roomName: "RoomA", marker: "rA", padLength: 300)
            let dataB = try Self.makePaddedHomeData(roomName: "RoomB", marker: "rB", padLength: 300)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: dataA, etag: "\"rA\"", serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 15_000_000)

            DiskSWRStore.saveHomeInBackground(rawPayloadData: dataB, etag: "\"rB\"", serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()

            let beforeTrim = await DiskSWRStore.diskUsageBytesAsync()
            XCTAssertGreaterThan(beforeTrim, 700)

            // Each entry is ~445 B; 2 entries = ~890 B > 750 B (target 600 B), leaving newest ~445 B.
            await DiskSWRStore.trimDiskCacheAsync(maxBytes: 750)
            DiskSWRStore.clearMemory()

            let evictedA = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomA", hardwareProfile: "hdr10-512")
            let keptB = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "RoomB", hardwareProfile: "hdr10-512")
            XCTAssertNil(evictedA)
            XCTAssertEqual(keptB?.etag, "\"rB\"")
            await DiskSWRStore.clearAllAsync()
        }
    }
}
