import Foundation
import XCTest
@testable import LunaCore

final class ArtworkCacheAndNavigationPolicyTests: XCTestCase {
    func testArtworkSubjectKeyNormalizationAndCacheKeys() throws {
        let lanHttp = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v2/img/card/tmdb/dune.jpg"))
        let lanHttps = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/img/backdrop/tmdb/dune.jpg"))
        let lanBackdrop4K = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/img/backdrop4k/tmdb/dune.jpg"))
        let mediaV2 = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/media/v2/img/still/tmdb/dune.jpg"))
        let mediaV2Backdrop4K = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/media/v2/img/backdrop4k/tmdb/dune.jpg"))
        let legacyV1 = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v1/img/card/tmdb/dune.jpg"))

        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: lanHttp),
            "tvimg-landscape:tmdb/dune.jpg"
        )
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: lanHttps),
            "tvimg-landscape:tmdb/dune.jpg"
        )
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: lanBackdrop4K),
            "tvimg-landscape:tmdb/dune.jpg"
        )
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: mediaV2),
            "tvimg-landscape:tmdb/dune.jpg"
        )
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: mediaV2Backdrop4K),
            "tvimg-landscape:tmdb/dune.jpg"
        )
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: legacyV1),
            "tvimg-landscape:tmdb/dune.jpg"
        )

        let rawA = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v2/artwork?src=a&w=320"))
        let rawB = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/artwork?src=a&w=320"))
        XCTAssertEqual(ArtworkSubjectKey.rawIdentity(for: rawA), ArtworkSubjectKey.rawIdentity(for: rawB))
        XCTAssertEqual(ArtworkSubjectKey.cacheKey(for: rawA, maxPixelSize: 1280), "/api/tv/v2/artwork?src=a&w=320#px1280")

        let tmdbSmall = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w780/poster.jpg"))
        let tmdbOrig = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))
        XCTAssertEqual(
            ArtworkSubjectKey.canonicalSubjectIdentity(for: tmdbSmall),
            ArtworkSubjectKey.canonicalSubjectIdentity(for: tmdbOrig)
        )
    }

    func testArtworkDiskCacheTouchLRUTirmAndLegacyMigration() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-diskcache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        XCTAssertTrue(ArtworkDiskCache.imageCacheDirectoryURL.path.hasSuffix("/Luna/img"))

        // Legacy migration from LunaV2/img -> Luna/img preserves cached files
        let legacyDir = tempRoot.appendingPathComponent("LunaV2/img", isDirectory: true)
        let currentDir = tempRoot.appendingPathComponent("Luna/img", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let sampleLegacyFile = legacyDir.appendingPathComponent("abc.img")
        try Data("cached".utf8).write(to: sampleLegacyFile)

        ArtworkDiskCache.migrateLegacyDirectory(from: legacyDir, to: currentDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDir.appendingPathComponent("abc.img").path))

        // Deterministic SHA-256 diskFileURL across LAN origins
        let u1 = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v2/img/poster/tmdb/123.jpg"))
        let u2 = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/img/poster/tmdb/123.jpg"))
        let f1 = ArtworkDiskCache.diskFileURL(for: u1, directoryURL: currentDir)
        let f2 = ArtworkDiskCache.diskFileURL(for: u2, directoryURL: currentDir)
        XCTAssertEqual(f1, f2)
        XCTAssertEqual(f1.pathExtension, "img")

        // Read-touch LRU keeps touched file while evicting older untouched file
        let trimDir = tempRoot.appendingPathComponent("trim-test", isDirectory: true)
        try FileManager.default.createDirectory(at: trimDir, withIntermediateDirectories: true)
        let fileOldTouched = trimDir.appendingPathComponent("old_touched.img")
        let fileMidUntouched = trimDir.appendingPathComponent("mid_untouched.img")
        let payload = Data(repeating: 0xAB, count: 1024)
        try payload.write(to: fileOldTouched)
        try payload.write(to: fileMidUntouched)

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        let t2 = Date(timeIntervalSince1970: 1_700_005_000)
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: fileOldTouched.path)
        try FileManager.default.setAttributes([.modificationDate: t1], ofItemAtPath: fileMidUntouched.path)

        let tracker = DiskTouchTracker()
        XCTAssertTrue(
            ArtworkDiskCache.touchDiskFileIfNeeded(at: fileOldTouched, key: "k1", tracker: tracker, now: t2)
        )
        // Debounce blocks immediate repeat touch within 3600 s
        XCTAssertFalse(
            ArtworkDiskCache.touchDiskFileIfNeeded(at: fileOldTouched, key: "k1", tracker: tracker, now: t2.addingTimeInterval(60))
        )

        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: 1500, directoryURL: trimDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileOldTouched.path), "Read-touched file must survive LRU trim")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileMidUntouched.path), "Older untouched file must be evicted")
    }

    func testBlurHashDecoderPurePixelMath() {
        let valid = BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 18, punch: 1.0)
        XCTAssertNotNil(valid)
        XCTAssertEqual(valid?.width, 32)
        XCTAssertEqual(valid?.height, 18)
        XCTAssertEqual(valid?.rgbaBytes.count, 32 * 18 * 4)
        XCTAssertEqual(valid?.rgbaBytes[3], 255)

        let punched = BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 18, punch: 1.5)
        XCTAssertNotNil(punched)
        XCTAssertNotEqual(valid?.rgbaBytes, punched?.rgbaBytes)

        XCTAssertNotEqual(
            BlurHashDecoder.makeCacheKey("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 18, punch: 1.0),
            BlurHashDecoder.makeCacheKey("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 18, punch: 1.5)
        )

        XCTAssertNil(BlurHashDecoder.decodePixels(nil))
        XCTAssertNil(BlurHashDecoder.decodePixels("short"))
        XCTAssertNil(BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdn!", width: 32, height: 18))
        XCTAssertNil(BlurHashDecoder.decodePixels("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 0, height: 18))
    }

    @MainActor
    func testLunaNavigationBarVisibilityPoliciesAndStateMachine() {
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 10), .atTop)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 50), .midBand)
        XCTAssertEqual(ScrollTopZone.classify(scrolledOffsetY: 120), .scrolledDown)

        let s1 = ScrollTopSample.capture(scrolledOffsetY: 96)
        XCTAssertEqual(s1.zone, .scrolledDown)
        XCTAssertEqual(s1.downwardBucket, 2)

        XCTAssertTrue(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: false,
                hasActivePlayback: false,
                isShowingModalSheet: false
            )
        )
        XCTAssertFalse(
            SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: false,
                hasPushedChildDestination: true,
                hasActivePlayback: false
            )
        )

        let now = Date()
        XCTAssertTrue(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: now.addingTimeInterval(-30),
                now: now,
                cachedRefreshNonce: 2,
                currentRefreshNonce: 2
            )
        )
        XCTAssertFalse(
            TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: now.addingTimeInterval(-30),
                now: now,
                cachedRefreshNonce: 1,
                currentRefreshNonce: 2
            )
        )

        let vis = LunaNavigationBarVisibility()
        XCTAssertFalse(vis.isTopBarHidden)
        vis.reportScrollSample(nil, s1, for: .home, now: now)
        XCTAssertTrue(vis.isTopBarHidden)
        XCTAssertTrue(vis.shouldInterceptMenuPress(hasActivePlayback: false))
        vis.handleMenuPressToRevealTopBar(now: now)
        XCTAssertFalse(vis.isTopBarHidden)
        XCTAssertFalse(vis.shouldInterceptMenuPress(hasActivePlayback: false))

        let subpageToken = UUID()
        vis.enterSubpage(subpageToken)
        XCTAssertTrue(vis.isSubpageActive)
        XCTAssertTrue(vis.isTopBarHidden)
        vis.leaveSubpage(subpageToken)
        XCTAssertFalse(vis.isSubpageActive)
    }

    func testThreadSafeLRUMemoryCacheEvictionOrderAndReadPromotion() {
        let cache = ThreadSafeLRUMemoryCache<String>(totalCostLimit: 1_000, countLimit: 3)
        cache.insert("A", forKey: "kA", cost: 100)
        cache.insert("B", forKey: "kB", cost: 100)
        cache.insert("C", forKey: "kC", cost: 100)

        // Read hit on oldest entry promotes kA to MRU; kB becomes LRU victim.
        XCTAssertEqual(cache.image(forKey: "kA"), "A")
        cache.insert("D", forKey: "kD", cost: 100)

        XCTAssertEqual(cache.count, 3)
        XCTAssertEqual(cache.totalCost, 300)
        XCTAssertNil(cache.image(forKey: "kB"))
        XCTAssertEqual(cache.image(forKey: "kA"), "A")
        XCTAssertEqual(cache.image(forKey: "kC"), "C")
        XCTAssertEqual(cache.image(forKey: "kD"), "D")
    }

    func testThreadSafeLRUMemoryCacheOverwriteCostAndOversizedAndZeroCostEdges() {
        let cache = ThreadSafeLRUMemoryCache<String>(totalCostLimit: 100, countLimit: 10)
        cache.insert("zero", forKey: "k0", cost: 0)
        XCTAssertEqual(cache.totalCost, 1, "Zero/negative cost must clamp to 1")
        cache.insert("neg", forKey: "kNeg", cost: -42)
        XCTAssertEqual(cache.totalCost, 2)

        cache.insert("small", forKey: "k1", cost: 30)
        XCTAssertEqual(cache.totalCost, 32)

        // Overwrite existing key with larger then smaller cost
        cache.insert("bigger", forKey: "k1", cost: 60)
        XCTAssertEqual(cache.totalCost, 62)
        cache.insert("smaller", forKey: "k1", cost: 10)
        XCTAssertEqual(cache.totalCost, 12)
        XCTAssertEqual(cache.image(forKey: "k1"), "smaller")

        // Single oversized entry (> totalCostLimit) removes prior key and leaves other entries intact
        cache.insert("huge", forKey: "k1", cost: 500)
        XCTAssertNil(cache.image(forKey: "k1"))
        XCTAssertEqual(cache.image(forKey: "k0"), "zero")
        XCTAssertEqual(cache.image(forKey: "kNeg"), "neg")
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.totalCost, 2)

        // Brand-new oversized entry does not wipe existing cache
        cache.insert("brand-new-huge", forKey: "kHuge", cost: 500)
        XCTAssertNil(cache.image(forKey: "kHuge"))
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.totalCost, 2)

        // Lowering totalCostLimit evicts LRU entries down to new limit
        cache.insert("keep", forKey: "kKeep", cost: 50)
        XCTAssertEqual(cache.image(forKey: "kKeep"), "keep")
        cache.totalCostLimit = 51
        XCTAssertLessThanOrEqual(cache.totalCost, 51)
        XCTAssertEqual(cache.image(forKey: "kKeep"), "keep")

        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertNil(cache.image(forKey: "kKeep"))
    }

    func testThreadSafeLRUMemoryCacheBestImageForSubjectKeyAndEvictionFallback() {
        let cache = ThreadSafeLRUMemoryCache<String>(totalCostLimit: 10_000, countLimit: 3)
        cache.insert("low-res", forKey: "poster#480", subjectKey: "tmdb:dune", cost: 10, qualityRank: 480)
        cache.insert("high-res", forKey: "poster#1280", subjectKey: "tmdb:dune", cost: 20, qualityRank: 1280)

        XCTAssertEqual(cache.bestImage(forSubjectKey: "tmdb:dune"), "high-res")
        // Refresh low-res to MRU, then insert two entries to evict high-res (now LRU)
        XCTAssertEqual(cache.image(forKey: "poster#480"), "low-res")
        cache.insert("other-1", forKey: "other#1", subjectKey: "tmdb:other1", cost: 10, qualityRank: 500)
        cache.insert("other-2", forKey: "other#2", subjectKey: "tmdb:other2", cost: 10, qualityRank: 500)

        XCTAssertNil(cache.image(forKey: "poster#1280"))
        XCTAssertEqual(
            cache.bestImage(forSubjectKey: "tmdb:dune"),
            "low-res",
            "Evicting highest-rank variant must fall back to remaining lower-rank variant for same subjectKey"
        )

        // Overwriting a key with a different subjectKey cleans up the previous subjectBest
        cache.insert("reassigned", forKey: "poster#480", subjectKey: "tmdb:new", cost: 10, qualityRank: 780)
        XCTAssertNil(cache.bestImage(forSubjectKey: "tmdb:dune"))
        XCTAssertEqual(cache.bestImage(forSubjectKey: "tmdb:new"), "reassigned")

        // Overwriting a key with subjectKey == nil removes it from subjectBest
        cache.insert("no-subject", forKey: "poster#480", subjectKey: nil, cost: 10, qualityRank: 780)
        XCTAssertNil(cache.bestImage(forSubjectKey: "tmdb:new"))
    }

    func testThreadSafeLRUMemoryCacheRecomputesSubjectBestOnSameSubjectLowerRankOverwrite() {
        let cache = ThreadSafeLRUMemoryCache<String>(totalCostLimit: 10_000, countLimit: 4)
        cache.insert("low-res", forKey: "poster#480", subjectKey: "tmdb:dune", cost: 10, qualityRank: 480)
        cache.insert("high-res", forKey: "poster#1280", subjectKey: "tmdb:dune", cost: 20, qualityRank: 1280)
        XCTAssertEqual(cache.bestImage(forSubjectKey: "tmdb:dune"), "high-res")

        // Overwrite the active subjectBest slot with the same subjectKey and a lower qualityRank
        cache.insert("downgraded", forKey: "poster#1280", subjectKey: "tmdb:dune", cost: 10, qualityRank: 200)
        XCTAssertEqual(
            cache.bestImage(forSubjectKey: "tmdb:dune"),
            "low-res",
            "Downgrading the active subjectBest slot must recompute and promote the higher-ranked sibling"
        )
        XCTAssertEqual(cache.image(forKey: "poster#1280"), "downgraded")

        // Overwriting the promoted sibling with an even higher rank updates bestImage accordingly
        cache.insert("upgraded", forKey: "poster#480", subjectKey: "tmdb:dune", cost: 15, qualityRank: 900)
        XCTAssertEqual(cache.bestImage(forSubjectKey: "tmdb:dune"), "upgraded")
        XCTAssertEqual(cache.image(forKey: "poster#480"), "upgraded")
    }

    func testPreferredPosterPathPrefetchResolutionFallback() throws {
        let baseURL = try XCTUnwrap(URL(string: "http://192.0.2.10:8090"))
        let client = LunaCoreClient(
            baseURL: baseURL,
            deviceID: "dev-1",
            deviceToken: "tok-1",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: false,
            appVersion: "3.0.0",
            osVersion: "Linux-CI"
        )

        let cards = [
            TvMediaCard(
                itemId: "movie:1",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 1),
                title: "Anchor",
                posterUrl: "https://image.tmdb.org/t/p/w342/anchor.jpg"
            ),
            TvMediaCard(
                itemId: "movie:2",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 2),
                title: "CardBackdropOnly",
                posterUrl: nil,
                backdropUrl: "https://image.tmdb.org/t/p/w780/bd2.jpg",
                cardBackdropUrl: "https://image.tmdb.org/t/p/w500/cb2.jpg"
            ),
            TvMediaCard(
                itemId: "movie:3",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 3),
                title: "BackdropOnly",
                posterUrl: nil,
                backdropUrl: "https://image.tmdb.org/t/p/w500/bd3.jpg",
                cardBackdropUrl: nil
            ),
            TvMediaCard(
                itemId: "movie:4",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 4),
                title: "OutsideWindow",
                posterUrl: "https://image.tmdb.org/t/p/w342/p4.jpg"
            ),
        ]

        let posterURLs = ArtworkDiskCache.prefetchArtworkURLs(
            in: cards,
            afterIndex: 0,
            isBackdrop: false,
            window: 2,
            client: client
        )
        XCTAssertEqual(posterURLs.map(\.absoluteString), [
            "https://image.tmdb.org/t/p/w780/cb2.jpg",
            "https://image.tmdb.org/t/p/w780/bd3.jpg",
        ])

        let backdropURLs = ArtworkDiskCache.prefetchArtworkURLs(
            in: cards,
            afterIndex: 0,
            isBackdrop: true,
            window: 2,
            client: client
        )
        XCTAssertEqual(backdropURLs.map(\.absoluteString), [
            "https://image.tmdb.org/t/p/w1280/cb2.jpg",
            "https://image.tmdb.org/t/p/w1280/bd3.jpg",
        ])

        XCTAssertTrue(ArtworkDiskCache.prefetchArtworkURLs(in: cards, afterIndex: -1, isBackdrop: false, window: 2, client: client).isEmpty)
        XCTAssertTrue(ArtworkDiskCache.prefetchArtworkURLs(in: cards, afterIndex: cards.count - 1, isBackdrop: false, window: 2, client: client).isEmpty)
        XCTAssertTrue(ArtworkDiskCache.prefetchArtworkURLs(in: cards, afterIndex: 0, isBackdrop: false, window: 0, client: client).isEmpty)
    }
}
