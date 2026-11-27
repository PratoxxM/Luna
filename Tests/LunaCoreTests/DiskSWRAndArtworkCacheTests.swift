import Foundation
import XCTest
@testable import LunaCore

final class DiskSWRAndArtworkCacheTests: XCTestCase {
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

    // MARK: - DiskSWRStore Multi-Tab Persistence, Hostless Scope, Races & Corrupt Recovery

    func testDiskSWRStoreMultiTabPersistenceHostlessIsolationRacesAndCorruptRecovery() async throws {
        try await DiskSWRTestGate.shared.withLock {
            await DiskSWRStore.clearAllAsync()
            defer { Task { await DiskSWRStore.clearAllAsync() } }

            XCTAssertEqual(DiskSWRStore.defaultMaxBytes, 16 * 1024 * 1024)
            let host = "swr-core-\(UUID().uuidString.lowercased()).local"
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
            let homeData = try JSONEncoder().encode(homePayload)
            let moviesPayload = TvCatalogResponse(
                ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false,
                page: 1, limit: 24, hasMore: true,
                items: [TvMediaCard(itemId: "movie:tmdb:693134", mediaType: "movie", ids: TvMediaIds(tmdb: 693134), title: "Dune: Part Two")]
            )
            let seriesPayload = TvCatalogResponse(
                ok: true, mediaType: "series", title: "Serier", sort: "popular", localOnly: false, unwatchedOnly: false,
                page: 1, limit: 24, hasMore: false,
                items: [TvMediaCard(itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396), title: "Severance")]
            )
            let libraryListsPayload = TvLibraryResponse(
                ok: true, section: "lists",
                counts: TvLibraryCounts(watchlist: 1, localTotal: 2, localMovies: 1, localSeries: 1, nvme: 2, archive: 0, vfs: 0, customLists: 2, customListsCount: 2),
                watchlist: [], localItems: [],
                customLists: [TvLibraryCustomList(id: "custom:nordic", name: "Nordisk", itemCount: 5, browsePath: "/api/tv/v2/rows/custom%3Anordic")]
            )

            DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"home-etag\"", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", decodedPayload: homePayload)
            DiskSWRStore.saveCatalogInBackground(rawPayloadData: try JSONEncoder().encode(moviesPayload), etag: "\"movies-etag\"", kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", decodedPayload: moviesPayload)
            DiskSWRStore.saveCatalogInBackground(rawPayloadData: try JSONEncoder().encode(seriesPayload), etag: "\"series-etag\"", kind: "series", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", decodedPayload: seriesPayload)
            DiskSWRStore.saveLibraryInBackground(rawPayloadData: try JSONEncoder().encode(libraryListsPayload), etag: "\"lib-lists-etag\"", section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", decodedPayload: libraryListsPayload)

            XCTAssertEqual(DiskSWRStore.memorySnapshot(serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"home-etag\"")
            XCTAssertEqual(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"movies-etag\"")
            XCTAssertEqual(DiskSWRStore.catalogMemorySnapshot(kind: "series", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"series-etag\"")
            XCTAssertEqual(DiskSWRStore.libraryMemorySnapshot(section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.etag, "\"lib-lists-etag\"")
            XCTAssertNil(DiskSWRStore.memorySnapshot(serverHost: host, roomName: "Stua", hardwareProfile: "hdr10-512"))
            XCTAssertNil(DiskSWRStore.memorySnapshot(serverHost: "other-\(host)", roomName: "Kjellerstua", hardwareProfile: "dv-fel-714"))

            // Hostless saves stay isolated under fallback scope and never bleed into a fresh serverHost
            DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"legacy-etag\"", serverHost: nil, roomName: "Stua", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            let diskBytesAfterSave = await DiskSWRStore.diskUsageBytesAsync()
            XCTAssertGreaterThan(diskBytesAfterSave, 0)

            DiskSWRStore.clearMemory()
            let freshHostHome = await DiskSWRStore.loadHomeAsync(serverHost: "fresh-\(UUID().uuidString).local", roomName: "Stua", hardwareProfile: "hdr10-512")
            let hostlessHome = await DiskSWRStore.loadHomeAsync(serverHost: nil, roomName: "Stua", hardwareProfile: "hdr10-512")
            let reloadedHome = await DiskSWRStore.loadHomeAsync(serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
            let reloadedMovies = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
            let reloadedLibrary = await DiskSWRStore.loadLibraryAsync(section: "lists", mediaType: "all", serverHost: host, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
            XCTAssertNil(freshHostHome)
            XCTAssertEqual(hostlessHome?.etag, "\"legacy-etag\"")
            XCTAssertEqual(reloadedHome?.payload.rows.first?.items.first?.title, "Fight Club")
            XCTAssertEqual(reloadedMovies?.payload.items.first?.title, "Dune: Part Two")
            XCTAssertEqual(reloadedLibrary?.payload.resolvedCustomLists.first?.name, "Nordisk")

            // 24-task concurrent memory reads & writes under mutex
            let raceHost = "swr-race-\(UUID().uuidString.lowercased()).local"
            await withTaskGroup(of: Void.self) { group in
                for idx in 0..<24 {
                    group.addTask {
                        DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"e-\(idx)\"", serverHost: raceHost, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714", decodedPayload: homePayload)
                        _ = DiskSWRStore.memorySnapshot(serverHost: raceHost, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")
                    }
                }
            }
            XCTAssertEqual(DiskSWRStore.memorySnapshot(serverHost: raceHost, roomName: "Kjellerstua", hardwareProfile: "dv-fel-714")?.payload.roomName, "Kjellerstua")

            // Concurrent load + clearAllAsync never resurrects memory or disk files
            let catData = try JSONEncoder().encode(moviesPayload)
            for _ in 0..<4 {
                DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"h1\"", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
                DiskSWRStore.saveCatalogInBackground(rawPayloadData: catData, etag: "\"c1\"", kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512")
                await DiskSWRStore.drainPendingWrites()
                DiskSWRStore.clearMemory()

                await withTaskGroup(of: Void.self) { group in
                    group.addTask { _ = await DiskSWRStore.loadHomeAsync(serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512") }
                    group.addTask { _ = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512") }
                    group.addTask { await DiskSWRStore.clearAllAsync() }
                }
                XCTAssertNil(DiskSWRStore.memorySnapshot(serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512"))
                XCTAssertNil(DiskSWRStore.catalogMemorySnapshot(kind: "movie", serverHost: raceHost, roomName: "Stua", hardwareProfile: "hdr10-512"))
                let bytesAfterClear = await DiskSWRStore.diskUsageBytesAsync()
                XCTAssertEqual(bytesAfterClear, 0)
            }

            // Corrupt 0-byte payload & broken .meta.json recovery + public trimDiskCacheAsync
            let corruptHost = "swr-corrupt-\(UUID().uuidString.lowercased()).invalid"
            DiskSWRStore.saveHomeInBackground(rawPayloadData: homeData, etag: "\"h-ok\"", serverHost: corruptHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            DiskSWRStore.saveCatalogInBackground(rawPayloadData: catData, etag: "\"c-ok\"", kind: "movie", serverHost: corruptHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            DiskSWRStore.clearMemory()

            let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let swrDir = cachesBase.appendingPathComponent("LunaV2/swr", isDirectory: true)
            for file in try FileManager.default.contentsOfDirectory(at: swrDir, includingPropertiesForKeys: nil) {
                if file.lastPathComponent.hasPrefix("home-") && file.lastPathComponent.hasSuffix(".json") && !file.lastPathComponent.hasSuffix(".meta.json") {
                    try Data().write(to: file)
                }
                if file.lastPathComponent.hasPrefix("catalog-") && file.lastPathComponent.hasSuffix(".meta.json") {
                    try Data("{broken-meta".utf8).write(to: file)
                }
            }
            let corruptHome = await DiskSWRStore.loadHomeAsync(serverHost: corruptHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            XCTAssertNil(corruptHome)
            let recoveredCat = await DiskSWRStore.loadCatalogAsync(kind: "movie", serverHost: corruptHost, roomName: "Stua", hardwareProfile: "hdr10-512")
            XCTAssertNotNil(recoveredCat)
            XCTAssertNil(recoveredCat?.etag)

            await DiskSWRStore.clearAllAsync()
            let trimHost = "swr-trim-\(UUID().uuidString.lowercased()).local"
            let dA = try Self.makePaddedHomeData(roomName: "RoomA", marker: "rA", padLength: 300)
            let dB = try Self.makePaddedHomeData(roomName: "RoomB", marker: "rB", padLength: 300)
            DiskSWRStore.saveHomeInBackground(rawPayloadData: dA, etag: "\"rA\"", serverHost: trimHost, roomName: "RoomA", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            try await Task.sleep(nanoseconds: 15_000_000)
            DiskSWRStore.saveHomeInBackground(rawPayloadData: dB, etag: "\"rB\"", serverHost: trimHost, roomName: "RoomB", hardwareProfile: "hdr10-512")
            await DiskSWRStore.drainPendingWrites()
            await DiskSWRStore.trimDiskCacheAsync(maxBytes: 750)
            DiskSWRStore.clearMemory()
            let trimEvictedA = await DiskSWRStore.loadHomeAsync(serverHost: trimHost, roomName: "RoomA", hardwareProfile: "hdr10-512")
            let trimKeptB = await DiskSWRStore.loadHomeAsync(serverHost: trimHost, roomName: "RoomB", hardwareProfile: "hdr10-512")
            XCTAssertNil(trimEvictedA)
            XCTAssertEqual(trimKeptB?.etag, "\"rB\"")
            await DiskSWRStore.clearAllAsync()
        }
    }

    func testDiskSWRStorageActorLRUPruningReadTouchAndOversizedProtection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-swr-actor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dA = try Self.makePaddedHomeData(roomName: "Stua", marker: "sA", padLength: 300)
        let dB = try Self.makePaddedHomeData(roomName: "Kjeller", marker: "sB", padLength: 300)
        let dC = try Self.makePaddedHomeData(roomName: "Kino", marker: "sC", padLength: 300)

        // Single-actor sub-hour read touch promotes home-a past home-b
        let actor = DiskSWRStorageActor(directoryURL: tempDir, maxBytes: 1_200)
        await actor.saveToDisk(rawPayloadData: dA, etag: "\"eA\"", baseName: "home-a")
        try await Task.sleep(nanoseconds: 20_000_000)
        await actor.saveToDisk(rawPayloadData: dB, etag: "\"eB\"", baseName: "home-b")
        try await Task.sleep(nanoseconds: 20_000_000)
        let hitA = await actor.loadFromDisk(baseName: "home-a", as: TvHomeResponse.self)
        XCTAssertEqual(hitA?.etag, "\"eA\"")

        try Data(#"{"etag":"\"orphan\""}"#.utf8).write(to: tempDir.appendingPathComponent("orphan.meta.json"))
        await actor.saveToDisk(rawPayloadData: dC, etag: "\"eC\"", baseName: "home-c")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertTrue(files.contains("home-a.json"))
        XCTAssertTrue(files.contains("home-c.json"))
        XCTAssertFalse(files.contains("home-b.json"))
        XCTAssertFalse(files.contains("home-b.meta.json"))
        XCTAssertFalse(files.contains("orphan.meta.json"))

        // Oversized newly written file never self-deletes; trim(maxBytes: 0) empties cache
        let hugeData = try Self.makePaddedHomeData(roomName: "Huge", marker: "H", padLength: 1_200)
        await actor.saveToDisk(rawPayloadData: hugeData, etag: "\"huge\"", baseName: "home-huge")
        let loadedHuge = await actor.loadFromDisk(baseName: "home-huge", as: TvHomeResponse.self)
        XCTAssertEqual(loadedHuge?.etag, "\"huge\"")
        await actor.trimDiskCache(maxBytes: 0)
        let usageAfterZero = await actor.diskUsageBytes()
        XCTAssertEqual(usageAfterZero, 0)
    }

    // MARK: - ArtworkSubjectKey, ArtworkDiskCache, ArtworkDecodeTargets & BlurHashDecoder

    func testArtworkSubjectKeyDiskCacheMigrationTrimPrefetchAndBlurHashDecoder() throws {
        let lanHttp = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v2/img/card/tmdb/dune.jpg"))
        let lanHttps = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/img/backdrop4k/tmdb/dune.jpg"))
        let mediaV2 = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/media/v2/img/still/tmdb/dune.jpg"))
        let tmdbSmall = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w780/poster.jpg"))
        let tmdbOrig = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))

        XCTAssertEqual(ArtworkSubjectKey.canonicalSubjectIdentity(for: lanHttp), "tvimg-landscape:tmdb/dune.jpg")
        XCTAssertEqual(ArtworkSubjectKey.canonicalSubjectIdentity(for: lanHttps), "tvimg-landscape:tmdb/dune.jpg")
        XCTAssertEqual(ArtworkSubjectKey.canonicalSubjectIdentity(for: mediaV2), "tvimg-landscape:tmdb/dune.jpg")
        XCTAssertEqual(ArtworkSubjectKey.canonicalSubjectIdentity(for: tmdbSmall), ArtworkSubjectKey.canonicalSubjectIdentity(for: tmdbOrig))

        XCTAssertEqual(ArtworkDecodeTargets.posterCardMaxPixelSize, 820)
        XCTAssertEqual(ArtworkDecodeTargets.backdropCardMaxPixelSize, 1092)
        XCTAssertEqual(ArtworkDecodeTargets.episodeCardMaxPixelSize, 882)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .high2026), 2880)
        XCTAssertEqual(ArtworkDecodeTargets.detailHeroMaxPixelSize(for: .standard), 2400)

        // Legacy LunaV2/img -> Luna/img migration, read-touch LRU trim & 0-byte maxBytes=0 trim
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-artdisk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let legacyDir = tempRoot.appendingPathComponent("LunaV2/img", isDirectory: true)
        let currentDir = tempRoot.appendingPathComponent("Luna/img", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try Data("cached".utf8).write(to: legacyDir.appendingPathComponent("abc.img"))
        ArtworkDiskCache.migrateLegacyDirectory(from: legacyDir, to: currentDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDir.appendingPathComponent("abc.img").path))
        XCTAssertEqual(ArtworkDiskCache.diskFileURL(for: lanHttp, directoryURL: currentDir), ArtworkDiskCache.diskFileURL(for: lanHttp, directoryURL: currentDir))

        let trimDir = tempRoot.appendingPathComponent("trim", isDirectory: true)
        try FileManager.default.createDirectory(at: trimDir, withIntermediateDirectories: true)
        let oldTouched = trimDir.appendingPathComponent("old.img")
        let midUntouched = trimDir.appendingPathComponent("mid.img")
        try Data(repeating: 0xAB, count: 1024).write(to: oldTouched)
        try Data(repeating: 0xCD, count: 1024).write(to: midUntouched)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: oldTouched.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_100)], ofItemAtPath: midUntouched.path)

        let tracker = DiskTouchTracker()
        let now = Date(timeIntervalSince1970: 1_700_005_000)
        XCTAssertTrue(ArtworkDiskCache.touchDiskFileIfNeeded(at: oldTouched, key: "k1", tracker: tracker, now: now))
        XCTAssertFalse(ArtworkDiskCache.touchDiskFileIfNeeded(at: oldTouched, key: "k1", tracker: tracker, now: now.addingTimeInterval(60)))
        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: 1500, directoryURL: trimDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTouched.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: midUntouched.path))

        try Data().write(to: trimDir.appendingPathComponent("zero.img"))
        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: 0, directoryURL: trimDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldTouched.path))

        // Prefetch artwork URL window
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://192.0.2.10:8090")),
            deviceID: "dev-1", deviceToken: "tok-1", roomName: "Stua", hardwareProfile: "hdr10-512", allowSelfSignedLanTLS: false
        )
        let cards = [
            TvMediaCard(itemId: "m1", mediaType: "movie", ids: TvMediaIds(tmdb: 1), title: "A", posterUrl: "https://image.tmdb.org/t/p/w342/a.jpg"),
            TvMediaCard(itemId: "m2", mediaType: "movie", ids: TvMediaIds(tmdb: 2), title: "B", backdropUrl: "https://image.tmdb.org/t/p/w780/bd2.jpg", cardBackdropUrl: "https://image.tmdb.org/t/p/w500/cb2.jpg"),
            TvMediaCard(itemId: "m3", mediaType: "movie", ids: TvMediaIds(tmdb: 3), title: "C", backdropUrl: "https://image.tmdb.org/t/p/w500/bd3.jpg"),
        ]
        XCTAssertEqual(
            ArtworkDiskCache.prefetchArtworkURLs(in: cards, afterIndex: 0, isBackdrop: false, window: 2, client: client).map(\.absoluteString),
            ["https://image.tmdb.org/t/p/w780/cb2.jpg", "https://image.tmdb.org/t/p/w780/bd3.jpg"]
        )

        // BlurHashDecoder valid pixels & malformed/non-finite inputs
        let validHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        let valid = BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: 1.0)
        let punched = BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: 1.5)
        XCTAssertEqual(valid?.rgbaBytes.count, 32 * 18 * 4)
        XCTAssertNotEqual(valid?.rgbaBytes, punched?.rgbaBytes)
        XCTAssertEqual(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: .nan), "\(validHash)#32x18#p100")
        XCTAssertEqual(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: 1e30), "\(validHash)#32x18#p1000")
        XCTAssertEqual(BlurHashDecoder.makeCacheKey(validHash, width: 32, height: 18, punch: -5.0), "\(validHash)#32x18#p0")
        XCTAssertNil(BlurHashDecoder.decodePixels(nil))
        XCTAssertNil(BlurHashDecoder.decodePixels("short"))
        XCTAssertNil(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: .nan))
        XCTAssertNil(BlurHashDecoder.decodePixels(validHash, width: 32, height: 18, punch: .infinity))
        XCTAssertNil(BlurHashDecoder.decodePixels(validHash, width: -4, height: 18))
        XCTAssertNil(BlurHashDecoder.decodePixels(validHash, width: 513, height: 18))
        XCTAssertNil(BlurHashDecoder.decodePixels("🎬🎬🎬🎬🎬🎬", width: 32, height: 18))
    }

    // MARK: - DeviceMemoryProfile, Prewarm Budgets & LRU Memory Caches

    func testDeviceMemoryProfileBudgetsAndLRUCaches() async throws {
        let gib: UInt64 = 1_073_741_824
        let standard = DeviceMemoryProfile(physicalMemoryBytes: 4 * gib, activeProcessorCount: 5)
        let high2026 = DeviceMemoryProfile(physicalMemoryBytes: 8 * gib, activeProcessorCount: 6)

        XCTAssertEqual(standard.tier, .standard)
        XCTAssertEqual(high2026.tier, .high2026)
        XCTAssertEqual(standard.artworkMemoryBytes, 112 * 1024 * 1024)
        XCTAssertEqual(high2026.artworkMemoryBytes, 384 * 1024 * 1024)
        XCTAssertEqual(standard.sessionCacheByteBudget, Int(1 * gib))
        XCTAssertEqual(high2026.sessionCacheByteBudget, Int(3 * gib))
        XCTAssertFalse(standard.enableBackgroundCatalogMetadataWarmup)
        XCTAssertTrue(high2026.enableBackgroundCatalogMetadataWarmup)
        XCTAssertFalse(standard.retainsSessionCacheAfterStop(availableMemoryBytes: 2_000 * 1_048_576))
        XCTAssertTrue(high2026.retainsSessionCacheAfterStop(availableMemoryBytes: 1_000 * 1_048_576))
        XCTAssertEqual(high2026.forwardBufferSegments(availableMemoryBytes: 1_600 * 1_048_576), 45)
        XCTAssertEqual(standard.forwardBufferSegments(availableMemoryBytes: 400 * 1_048_576), 8)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 2), 8)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 1), 1)
        XCTAssertEqual(SideloadSafeStorage.currentAppVersionString(), "3.0.0")

        // PlaybackPrewarmBudgetPolicy
        XCTAssertTrue(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "nvme", tier: "nvme"))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "easynews", tier: "ssd"))
        XCTAssertFalse(PlaybackPrewarmBudgetPolicy.isFastLocalTier(source: "vfs", tier: "   "))
        XCTAssertEqual(PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(source: "nvme", tier: "nvme", memoryProfile: high2026, availableMemoryBytes: 2_000 * 1_048_576), 16 * 1024 * 1024)
        XCTAssertEqual(PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(source: "vfs", tier: "vfs", memoryProfile: high2026, availableMemoryBytes: 2_000 * 1_048_576), 8 * 1024 * 1024)
        XCTAssertEqual(PlaybackPrewarmBudgetPolicy.nextEpisodeByteBudget(source: "nvme", tier: "nvme", memoryProfile: stdProfile(4 * gib), availableMemoryBytes: 400 * 1_048_576), 0)

        // BoundedLRUMemoryCache & ItemDetailMemoryCache
        let series95396 = try JSONDecoder().decode(
            TvItemDetail.self,
            from: Data(#"{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":true,"watched":false}"#.utf8)
        )
        let movie550 = try JSONDecoder().decode(
            TvItemDetail.self,
            from: Data(#"{"itemId":"movie:tmdb:550","mediaType":"movie","ids":{"tmdb":550},"title":"Fight Club","inWatchlist":false,"watched":false}"#.utf8)
        )
        let base = try XCTUnwrap(URL(string: "http://luna-cache.local:8090"))
        await MainActor.run {
            let bounded = BoundedLRUMemoryCache<Int>(maxEntries: 2)
            bounded.store(1, for: "a")
            bounded.store(2, for: "b")
            _ = bounded.snapshot(for: "a")
            bounded.store(3, for: "c")
            XCTAssertNil(bounded.snapshot(for: "b"))
            XCTAssertEqual(bounded.snapshot(for: "a"), 1)

            ItemDetailMemoryCache.shared.clear()
            let kSeries = ItemDetailMemoryCache.makeKey(baseURL: base, mediaType: "series", itemId: "series:tmdb:95396", roomName: "Stua", hardwareProfile: "hdr10-512")
            let kMovie = ItemDetailMemoryCache.makeKey(baseURL: base, mediaType: "movie", itemId: "movie:tmdb:550", roomName: "Stua", hardwareProfile: "hdr10-512")
            ItemDetailMemoryCache.shared.store(ItemDetailSnapshot(detail: series95396, refreshNonce: 1), for: kSeries)
            ItemDetailMemoryCache.shared.store(ItemDetailSnapshot(detail: movie550, refreshNonce: 1), for: kMovie)
            ItemDetailMemoryCache.invalidate(itemId: "episode:tmdb:95396:s1:e2", tmdbId: nil)
            XCTAssertNil(ItemDetailMemoryCache.shared.snapshot(for: kSeries))
            XCTAssertNotNil(ItemDetailMemoryCache.shared.snapshot(for: kMovie))
            ItemDetailMemoryCache.shared.clear()
        }

        // ThreadSafeLRUMemoryCache subjectBest recomputation & 16-worker concurrent stress
        let subjCache = ThreadSafeLRUMemoryCache<String>(totalCostLimit: 10_000, countLimit: 4)
        subjCache.insert("low-res", forKey: "poster#480", subjectKey: "tmdb:dune", cost: 10, qualityRank: 480)
        subjCache.insert("high-res", forKey: "poster#1280", subjectKey: "tmdb:dune", cost: 20, qualityRank: 1280)
        XCTAssertEqual(subjCache.bestImage(forSubjectKey: "tmdb:dune"), "high-res")
        subjCache.insert("downgraded", forKey: "poster#1280", subjectKey: "tmdb:dune", cost: 10, qualityRank: 200)
        XCTAssertEqual(subjCache.bestImage(forSubjectKey: "tmdb:dune"), "low-res")
        subjCache.insert("zero", forKey: "k0", cost: -5)
        XCTAssertGreaterThanOrEqual(subjCache.totalCost, 1)

        let stressCache = ThreadSafeLRUMemoryCache<Int>(totalCostLimit: 256, countLimit: 24)
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<16 {
                group.addTask {
                    for iter in 0..<120 {
                        let key = "item-\((worker * 7 + iter) % 40)"
                        stressCache.insert(worker * 1000 + iter, forKey: key, subjectKey: "subj-\(iter % 8)", cost: ((iter % 5) + 1) * 8, qualityRank: 320 + iter)
                        _ = stressCache.image(forKey: key)
                        _ = stressCache.bestImage(forSubjectKey: "subj-\(iter % 8)")
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(stressCache.count, 24)
        XCTAssertLessThanOrEqual(stressCache.totalCost, 256)
    }

    private func stdProfile(_ bytes: UInt64) -> DeviceMemoryProfile {
        DeviceMemoryProfile(physicalMemoryBytes: bytes)
    }
}
