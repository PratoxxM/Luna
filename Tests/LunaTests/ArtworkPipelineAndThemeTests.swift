import CoreGraphics
import Foundation
import ImageIO
import MediaPlayer
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class ArtworkPipelineAndThemeTests: XCTestCase {
    // MARK: - BlurHashImageCache & ArtworkPipeline (CoreGraphics / ImageIO / MediaPlayer)

    func testBlurHashImageCacheCoalescingCancellationAndPipelineClearAll() async throws {
        let sampleHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        BlurHashDecoder.clearCache()
        defer { BlurHashDecoder.clearCache() }

        let standard = BlurHashDecoder.decode(sampleHash, width: 32, height: 24, punch: 1.0)
        XCTAssertEqual(standard?.width, 32)
        XCTAssertEqual(standard?.height, 24)
        XCTAssertNotNil(BlurHashDecoder.decode(sampleHash, width: 32, height: 24, punch: 1.4))
        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.0))
        XCTAssertNotNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.4))
        XCTAssertNil(BlurHashDecoder.decode("short", width: 32, height: 24, punch: 1.0))
        XCTAssertNil(BlurHashDecoder.decode(nil, width: 32, height: 24, punch: 1.0))

        BlurHashDecoder.clearCache()
        let invalid = await BlurHashDecoder.decodeAsync("bad", width: 64, height: 48)
        XCTAssertNil(invalid)
        let zeroDim = await BlurHashDecoder.decodeAsync(sampleHash, width: 0, height: 48)
        XCTAssertNil(zeroDim)

        let results = await withTaskGroup(of: CGImage?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await BlurHashDecoder.decodeAsync(sampleHash, width: 64, height: 48, punch: 1.0)
                }
            }
            var collected: [CGImage] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }
        XCTAssertEqual(results.count, 12)
        let first = try XCTUnwrap(results.first)
        for image in results {
            XCTAssertTrue(image === first, "Concurrent BlurHash callers must share one decoded CGImage")
        }

        BlurHashDecoder.clearCache()
        let preCancelled = Task { () -> CGImage? in
            while !Task.isCancelled { await Task.yield() }
            return await BlurHashDecoder.decodeAsync(sampleHash, width: 32, height: 24, punch: 1.0)
        }
        preCancelled.cancel()
        let cancelledImage = await preCancelled.value
        XCTAssertNil(cancelledImage)
        XCTAssertNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24, punch: 1.0))

        XCTAssertNotNil(BlurHashDecoder.decode(sampleHash, width: 32, height: 24))
        await ArtworkPipeline.shared.clearAll()
        XCTAssertNil(BlurHashDecoder.cachedImage(sampleHash, width: 32, height: 24))
    }

    func testArtworkPipelineSubjectBridgingGrayscaleDecodeAndOffMainNowPlayingArtwork() async throws {
        let host = "artwork-gray-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let lanHostA = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v2/artwork/123?w=600"))
            let lanHostB = try XCTUnwrap(URL(string: "https://lunacore.example.test:8920/api/tv/v2/artwork/123?w=600"))
            XCTAssertEqual(ArtworkPipeline.rawIdentity(for: lanHostA), ArtworkPipeline.rawIdentity(for: lanHostB))
            XCTAssertNotEqual(
                ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 480),
                ArtworkPipeline.cacheKey(for: lanHostA, maxPixelSize: 960)
            )

            let w1280URL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w1280/severance_hero.jpg"))
            let orig4KURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/original/severance_hero.jpg"))
            let sampleCG = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 64, height: 36))
            ArtworkPipeline.shared.insertMemoryCachedImage(sampleCG, url: w1280URL, maxPixelSize: 1280)
            let bridgedHit = ArtworkPipeline.shared.anyMemoryCachedImage(for: orig4KURL, preferredMaxPixelSize: 3840)
            XCTAssertTrue(bridgedHit?.image === sampleCG)

            struct UncheckedArtworkBox: @unchecked Sendable {
                let artwork: MPMediaItemArtwork
            }
            let box = await MainActor.run {
                UncheckedArtworkBox(artwork: NowPlayingArtworkFactory.makeArtwork(cgImage: sampleCG))
            }
            let renderedSize = await Task.detached(priority: .userInitiated) {
                box.artwork.image(at: CGSize(width: 64, height: 36))?.size
            }.value
            XCTAssertEqual(renderedSize, CGSize(width: 64, height: 36))

            let graySpace = CGColorSpaceCreateDeviceGray()
            var grayPixels = [UInt8](repeating: 180, count: 16 * 16)
            let grayCG: CGImage = try grayPixels.withUnsafeMutableBytes { rawBuf in
                let ctx = try XCTUnwrap(
                    CGContext(
                        data: rawBuf.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                        bytesPerRow: 16, space: graySpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
                    )
                )
                return try XCTUnwrap(ctx.makeImage())
            }
            let pngData = NSMutableData()
            let dest = try XCTUnwrap(CGImageDestinationCreateWithData(pngData as CFMutableData, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, grayCG, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            let pngBytes = pngData as Data

            MockURLProtocol.register(host: host) { request in
                let url = try XCTUnwrap(request.url)
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, pngBytes)
            }
            let client = try MockURLProtocol.makeClient(host: host)
            let grayURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/grayscale.png"))
            let loadedGray = await ArtworkPipeline.shared.loadImage(url: grayURL, maxPixelSize: 1920, client: client)
            XCTAssertEqual(loadedGray?.width, 16)
            XCTAssertEqual(loadedGray?.height, 16)
        }
    }

    func testArtworkPipelineCorruptDiskEvictionHTTP200GuardCancellationAndRollover() async throws {
        let host = "artwork-resilience-\(UUID().uuidString.lowercased()).local"
        try await withCleanArtworkPipeline(host: host) {
            let validPNG = try PlayerTestFixtures.makeImageData(utType: "public.png", width: 16, height: 16)
            let requestCount = TestLockedBox(0)
            MockURLProtocol.register(host: host) { request in
                let reqURL = try XCTUnwrap(request.url)
                let resp = try XCTUnwrap(HTTPURLResponse(url: reqURL, statusCode: 200, httpVersion: nil, headerFields: nil))
                if reqURL.path.hasSuffix("corrupt_http.png") {
                    let attempt = requestCount.withLock { count -> Int in count += 1; return count }
                    if attempt == 1 {
                        return (resp, Data("<html>502 Bad Gateway</html>".utf8))
                    }
                }
                return (resp, validPNG)
            }
            let client = try MockURLProtocol.makeClient(host: host)

            // 1. Corrupt disk file is evicted synchronously and recovered on next load
            let diskCorruptURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/corrupt_disk.png"))
            let diskFileURL = ArtworkPipeline.diskFileURL(for: diskCorruptURL)
            try FileManager.default.createDirectory(at: ArtworkPipeline.imageCacheDirectoryURL, withIntermediateDirectories: true)
            try Data("corrupt-bytes-not-an-image".utf8).write(to: diskFileURL, options: .atomic)

            let firstLoad = await ArtworkPipeline.shared.loadImage(url: diskCorruptURL, maxPixelSize: 480, client: client)
            XCTAssertNil(firstLoad)
            XCTAssertFalse(FileManager.default.fileExists(atPath: diskFileURL.path))

            let secondLoad = await ArtworkPipeline.shared.loadImage(url: diskCorruptURL, maxPixelSize: 480, client: client)
            XCTAssertEqual(secondLoad?.width, 16)
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: diskFileURL.path) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(try Data(contentsOf: diskFileURL), validPNG)

            // 2. Corrupt HTTP 200 payload is never persisted to disk and recovers on retry
            let httpCorruptURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/corrupt_http.png"))
            let httpDiskURL = ArtworkPipeline.diskFileURL(for: httpCorruptURL)
            let badLoad = await ArtworkPipeline.shared.loadImage(url: httpCorruptURL, maxPixelSize: 480, client: client)
            XCTAssertNil(badLoad)
            try? await Task.sleep(nanoseconds: 40_000_000)
            XCTAssertFalse(FileManager.default.fileExists(atPath: httpDiskURL.path))
            let recoveredLoad = await ArtworkPipeline.shared.loadImage(url: httpCorruptURL, maxPixelSize: 480, client: client)
            XCTAssertEqual(recoveredLoad?.width, 16)

            // 3. Cancelled loadImage preserves valid cached disk file
            let cancelURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/valid_cancel.png"))
            let cancelDiskURL = ArtworkPipeline.diskFileURL(for: cancelURL)
            try validPNG.write(to: cancelDiskURL, options: .atomic)
            let cancelledTask = Task { () -> CGImage? in
                while !Task.isCancelled { await Task.yield() }
                return await ArtworkPipeline.shared.loadImage(url: cancelURL, maxPixelSize: 780, client: client)
            }
            cancelledTask.cancel()
            let cancelledRes = await cancelledTask.value
            XCTAssertNil(cancelledRes)
            XCTAssertEqual(try Data(contentsOf: cancelDiskURL), validPNG)

            // 4. Truncated PNG rejection & stale generation guard
            let truncatedPNG = Data(validPNG.prefix(40))
            XCTAssertTrue(ArtworkPipeline.isDecodableImagePayload(validPNG))
            XCTAssertFalse(ArtworkPipeline.isDecodableImagePayload(truncatedPNG))

            let truncURL = try XCTUnwrap(URL(string: "http://\(host):8090/api/tv/v2/img/poster/tmdb/truncated.png"))
            let rawKey = ArtworkPipeline.rawIdentity(for: truncURL)
            let truncDiskURL = ArtworkPipeline.diskFileURL(for: truncURL)
            let pin = ArtworkPipeline.shared.diskMutation.pin(key: rawKey)
            withExtendedLifetime(pin.lease) {
                ArtworkPipeline.shared.evictCorruptDiskFile(
                    at: truncDiskURL, rawKey: rawKey, clearEpoch: pin.clearEpoch, expectedGeneration: pin.generation
                )
            }
            XCTAssertNotEqual(ArtworkPipeline.shared.diskMutation.generation(for: rawKey), pin.generation)
            ArtworkPipeline.shared.scheduleDiskWrite(
                data: truncatedPNG, to: truncDiskURL, rawKey: rawKey,
                clearEpoch: pin.clearEpoch, expectedGeneration: pin.generation, lease: pin.lease
            )
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertFalse(FileManager.default.fileExists(atPath: truncDiskURL.path))
        }

        // 5. DiskMutationCoordinator 2048-key rollover pins active key lease
        let coordinator = ArtworkPipeline.DiskMutationCoordinator()
        var activeLease: ArtworkPipeline.DiskKeyLease?
        let pinnedGeneration: UInt64
        do {
            let pin = coordinator.pin(key: "active-key")
            pinnedGeneration = pin.generation
            activeLease = pin.lease
        }
        withExtendedLifetime(activeLease) {
            for i in 0..<2_500 { _ = coordinator.advanceGeneration(for: "idle-\(i)") }
            XCTAssertLessThanOrEqual(coordinator.trackedKeyCount, 2048)
            XCTAssertEqual(coordinator.generation(for: "active-key"), pinnedGeneration)
        }
        let updatedGen = coordinator.advanceGeneration(for: "active-key")
        activeLease = nil
        for i in 2_500..<5_000 { _ = coordinator.advanceGeneration(for: "idle-\(i)") }
        XCTAssertLessThanOrEqual(coordinator.trackedKeyCount, 2048)
        XCTAssertGreaterThan(coordinator.generation(for: "active-key"), updatedGen)
    }

    // MARK: - LunaTheme, Tokens, WCAG Contrast & Warm Lampelys Surfaces

    func testTokensTypographyFloorWarmPaletteContrastAndAssetHygiene() throws {
        XCTAssertEqual(
            LunaTokens.tokensSha256,
            "26ba103abc2b298cbfd78c197316256e7b5c900b273e9e064f6fef8242e5f26d"
        )
        XCTAssertEqual(6.0 * LunaTokens.Layout.gridPosterW + 5.0 * LunaTokens.Layout.gridCardGap, 1740.0)
        XCTAssertGreaterThanOrEqual(LunaTheme.Font.minimumPointSizeFloor, 22.0)
        XCTAssertFalse(LunaTheme.Font.allFixedPointSizes.isEmpty)
        for (role, size) in LunaTheme.Font.allFixedPointSizes {
            XCTAssertGreaterThanOrEqual(size, LunaTheme.Font.minimumPointSizeFloor, "Role \(role) below 22 pt floor")
        }

        XCTAssertEqual(LunaRoomAtmosphere.resolve(atmosphere: nil, hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"), .cinema)
        XCTAssertEqual(LunaRoomAtmosphere.resolve(atmosphere: nil, hardwareProfile: "hdr10-512", roomName: "Stua"), .living)

        try assertRGB(LunaTheme.canvas, r: 10, g: 9, b: 8)
        try assertRGB(LunaTheme.surface, r: 20, g: 17, b: 15)
        try assertRGB(LunaTheme.surfaceRaised, r: 30, g: 25, b: 22)
        try assertRGB(LunaTheme.linen, r: 245, g: 240, b: 232)
        try assertRGB(LunaTheme.moonlight, r: 200, g: 191, b: 182)
        try assertRGB(LunaTheme.muted, r: 160, g: 150, b: 140)
        try assertRGB(LunaTheme.amber, r: 196, g: 140, b: 58)
        try assertRGB(LunaTheme.warn, r: 224, g: 168, b: 75)
        try assertRGB(LunaTheme.danger, r: 217, g: 107, b: 82)
        try assertRGB(LunaTheme.statusOk, r: 94, g: 191, b: 142)

        let glass = try rgbaComponents(LunaTheme.cinemaGlass)
        XCTAssertEqual(glass.a, 0.92, accuracy: 0.01)
        XCTAssertEqual(try rgbaComponents(LunaTheme.warmBorder).a, 0.14, accuracy: 0.01)

        for warmToken in [
            LunaTheme.canvas, LunaTheme.surface, LunaTheme.surfaceRaised, LunaTheme.surfaceSelected,
            LunaTheme.linen, LunaTheme.moonlight, LunaTheme.muted, LunaTheme.amber, LunaTheme.warn, LunaTheme.danger,
        ] {
            let c = try rgbaComponents(warmToken)
            XCTAssertGreaterThanOrEqual(c.r + 0.002, c.g)
            XCTAssertGreaterThanOrEqual(c.g + 0.002, c.b)
        }

        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.linen, background: LunaTheme.canvas), 15.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.moonlight, background: LunaTheme.surfaceRaised), 8.5)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.muted, background: LunaTheme.canvas), 6.2)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.amber), 6.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.danger, background: LunaTheme.canvas), 5.0)

        XCTAssertNil(UIImage(named: "MascotCatsDuo"))
        XCTAssertNil(UIImage(named: "LunaMoonCrescent"))
        XCTAssertNil(UIImage(named: "LunaMoonCatsEmblem"))
        let accentUI = try XCTUnwrap(UIColor(named: "AccentColor"))
        let resolved = accentUI.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(Double(r), 0.769, accuracy: 0.015)
        XCTAssertEqual(Double(g), 0.549, accuracy: 0.015)
        XCTAssertEqual(Double(b), 0.227, accuracy: 0.015)
    }

    @MainActor
    func testLampelysControlsCachedArtworkMemoAndDarkTextFieldSurfaces() throws {
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .card, isFocused: true), 1.05, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .listRow, isFocused: true), 1.0, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .control, isFocused: true), 1.04, accuracy: 0.001)

        try assertRGB(LunaPillButton.resolveIconForeground(isFocused: false, isSelected: true, prominence: .glassPill, accent: .amber), r: 196, g: 140, b: 58)
        try assertRGB(LunaPillButton.resolveLabelForeground(isFocused: true, isSelected: false, prominence: .glassPill, accent: .amber), r: 10, g: 9, b: 8)
        XCTAssertEqual(LunaPillButton.resolveTrailingDotColor(isFocused: false), LunaTheme.moonlight)
        XCTAssertEqual(LunaPillButton.resolveTrailingDotColor(isFocused: true), LunaTokens.Text.onAccent)
        XCTAssertEqual(LunaListRow.resolveLeadingIconColor(isDestructive: true, isFocused: false), LunaTheme.coral)
        XCTAssertEqual(LunaListRow.resolveTitleColor(isDestructive: false, dimUnfocusedTitle: true, isFocused: true, isSelected: false), LunaTheme.linen)

        let crescentPoints = LunaCrescentGeometry.crescentPoints(side: 100, center: CGPoint(x: 50, y: 50))
        XCTAssertGreaterThan(crescentPoints.count, 100)
        XCTAssertFalse(crescentPoints.contains(where: { $0.x > 64 && $0.y < 33 }))

        XCTAssertTrue(TopBarTabPillButton.shouldShowRestingActiveIndicator(isActive: true, isFocused: false, isBarFocused: false))
        XCTAssertFalse(TopBarTabPillButton.shouldShowRestingActiveIndicator(isActive: true, isFocused: false, isBarFocused: true))
        XCTAssertEqual(TopBarTabPillButton.resolveTextColor(isActive: true, isFocused: false, isBarFocused: true), LunaTheme.muted)

        XCTAssertFalse(LunaCardProgressBar(percent: 2.0, trackWidth: 400).isVisible)
        XCTAssertTrue(LunaCardProgressBar(percent: 50.0, trackWidth: 400).isVisible)
        XCTAssertFalse(LunaCardProgressBar(percent: 95.0, trackWidth: 400).isVisible)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: TvAvailabilityInfo(state: "instant", tier: "nvme")), .nvme)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: TvAvailabilityInfo(state: "instant", tier: "archive")), .archive)
        XCTAssertEqual(LunaTierDotView.resolveIndicatorStyle(for: TvAvailabilityInfo(state: "remote", tier: "vfs")), .none)

        // CachedArtworkView key-matched image selection, epoch skip policy & URL memoization
        let staleImg = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 8, height: 12))
        let freshImg = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 16, height: 9))
        defer { BlurHashDecoder.clearCache() }

        XCTAssertTrue(
            CachedArtworkView.selectKeyMatchedImage(
                expectedKey: "movie-A#px750", stateKey: "movie-A#px750", stateImage: staleImg, memoryFallback: { nil }
            ) === staleImg
        )
        XCTAssertTrue(
            CachedArtworkView.selectKeyMatchedImage(
                expectedKey: "movie-B#px750", stateKey: "movie-A#px750", stateImage: staleImg, memoryFallback: { freshImg }
            ) === freshImg
        )
        XCTAssertTrue(CachedArtworkView.shouldSkipAsyncLoad(
            targetImageKey: "movie-1#px820", currentMemoryEpoch: 4, retainDuringPlayback: true,
            loadedKey: "movie-1#px820", loadedIsExact: true, loadedEpoch: 3,
            syncHitKey: nil, syncHitIsExact: false, syncHitEpoch: 0
        ))
        XCTAssertFalse(CachedArtworkView.shouldSkipAsyncLoad(
            targetImageKey: "movie-1#px820", currentMemoryEpoch: 4, retainDuringPlayback: false,
            loadedKey: "movie-1#px820", loadedIsExact: true, loadedEpoch: 3,
            syncHitKey: "movie-1#px820", syncHitIsExact: true, syncHitEpoch: 3
        ))

        let memo = ArtworkURLMemoBox()
        let baseA = try XCTUnwrap(URL(string: "http://lunacore-a.local:8090"))
        var resolverCalls = 0
        _ = memo.resolve(path: "/api/tv/v2/img/card/1", baseURL: baseA, target: .poster2x) {
            resolverCalls += 1
            return URL(string: "http://lunacore-a.local:8090/api/tv/v2/img/card/1")
        }
        _ = memo.resolve(path: "/api/tv/v2/img/card/1", baseURL: baseA, target: .poster2x) {
            resolverCalls += 1
            return nil
        }
        XCTAssertEqual(resolverCalls, 1)

        // Focused LunaTextField stays dark espresso and hidden keyboard host is non-focusable
        let focusedSurface = UIColor(LunaTextField.resolveSurfaceColor(isFocused: true))
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        XCTAssertTrue(focusedSurface.getRed(&fr, green: &fg, blue: &fb, alpha: &fa))
        XCTAssertLessThan(Double(fr), 0.30)
        XCTAssertLessThan(Double(fg), 0.25)
        XCTAssertLessThan(Double(fb), 0.25)

        let hiddenTF = NonFocusableTVTextField(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertFalse(hiddenTF.canBecomeFocused)
    }

    private func withCleanArtworkPipeline(host: String, _ body: () async throws -> Void) async throws {
        await ArtworkPipeline.shared.clearAll()
        do {
            try await body()
        } catch {
            MockURLProtocol.unregister(host: host)
            await ArtworkPipeline.shared.clearAll()
            throw error
        }
        MockURLProtocol.unregister(host: host)
        await ArtworkPipeline.shared.clearAll()
    }

    private func assertRGB(_ color: Color, r: Double, g: Double, b: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try rgbaComponents(color)
        XCTAssertEqual(c.r, r / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.g, g / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.b, b / 255.0, accuracy: 0.01, file: file, line: line)
    }

    private func rgbaComponents(_ color: Color) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            throw NSError(domain: "ColorTest", code: 1)
        }
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func relativeLuminance(_ color: Color) throws -> Double {
        let (r, g, b, _) = try rgbaComponents(color)
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(foreground: Color, background: Color) throws -> Double {
        let l1 = try relativeLuminance(foreground)
        let l2 = try relativeLuminance(background)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
