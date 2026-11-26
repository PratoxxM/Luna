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
}
