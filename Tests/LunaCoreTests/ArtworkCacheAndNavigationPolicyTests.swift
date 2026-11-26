import Foundation
import XCTest
@testable import LunaCore

final class ArtworkCacheAndNavigationPolicyTests: XCTestCase {
    func testArtworkSubjectKeyNormalizationAndCacheKeys() throws {
        let lanHttp = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v2/img/card/tmdb/dune.jpg"))
        let lanHttps = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/img/backdrop/tmdb/dune.jpg"))
        let mediaV2 = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/media/v2/img/still/tmdb/dune.jpg"))
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
            ArtworkSubjectKey.canonicalSubjectIdentity(for: mediaV2),
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
}
