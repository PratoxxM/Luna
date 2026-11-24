import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Offline URLProtocol interceptor and fast CoreGraphics Lampelys cinema artwork generator for preview mode.
final class PreviewMockURLProtocol: URLProtocol {
    private static let installed = Mutex(false)
    private static let cachedArtworkPNGs = Mutex<[String: Data]>([:])

    static func installIfNeeded() {
        installed.withLock { flag in
            guard !flag else { return }
            URLProtocol.registerClass(PreviewMockURLProtocol.self)
            flag = true
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.lowercased() == PreviewMockFixtures.previewHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path
        let responseData: Data
        let contentType: String

        if path.hasPrefix("/preview-art/") {
            responseData = Self.artworkPNG(named: path)
            contentType = "image/png"
        } else {
            contentType = "application/json"
            responseData = Self.routeJSON(for: url)
        }

        if let http = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ) {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Route Dispatch

    private static func routeJSON(for url: URL) -> Data {
        let path = url.path
        if path == "/api/tv/v1/bootstrap" {
            let boot = TvBootstrapResponse(
                ok: true,
                device: TvPairedDeviceInfo(
                    deviceId: "luna-preview-appletv",
                    deviceName: "Apple TV 4K",
                    roomName: PreviewMockFixtures.previewRoomName,
                    hardwareProfile: PreviewMockFixtures.previewHardwareProfile,
                    equipmentLabel: LunaCopy.roomEquipmentLabel(hardwareProfile: PreviewMockFixtures.previewHardwareProfile),
                    atmosphere: "living",
                    overrides: nil
                ),
                defaultRooms: HardwareProfilePreset.fallbackRooms
            )
            return (try? LunaCoreClient.encodeJSON(boot)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/home" {
            return (try? LunaCoreClient.encodeJSON(PreviewMockFixtures.homeResponse)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/library" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let mediaType = comps?.queryItems?.first(where: { $0.name == "mediaType" })?.value ?? "movie"
            return (try? LunaCoreClient.encodeJSON(PreviewMockFixtures.libraryResponse(mediaType: mediaType))) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/search" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value ?? "Dune"
            let searchRes = TvSearchResponse(
                ok: true,
                query: q,
                localCount: 5,
                items: PreviewMockFixtures.catalogMovies
            )
            return (try? LunaCoreClient.encodeJSON(searchRes)) ?? Data("{}".utf8)
        }
        if path.hasPrefix("/api/tv/v1/catalog/") {
            let isSeries = path.hasSuffix("/series")
            let cat = TvCatalogResponse(
                ok: true,
                mediaType: isSeries ? "series" : "movie",
                title: isSeries ? "Serier" : "Filmer",
                genre: nil,
                sort: "popular",
                localOnly: false,
                unwatchedOnly: false,
                page: 1,
                limit: 24,
                hasMore: false,
                availableGenres: PreviewMockFixtures.genreChips,
                items: isSeries ? PreviewMockFixtures.seriesCards : PreviewMockFixtures.catalogMovies
            )
            return (try? LunaCoreClient.encodeJSON(cat)) ?? Data("{}".utf8)
        }
        if path.contains("/seasons/") {
            let seasonRes = TvSeasonDetailResponse(
                ok: true,
                tmdbId: 246810,
                seasonNumber: 28,
                title: "Sesong 28",
                episodes: PreviewMockFixtures.luksusfellenSeason28Episodes
            )
            return (try? LunaCoreClient.encodeJSON(seasonRes)) ?? Data("{}".utf8)
        }
        if path.hasPrefix("/api/tv/v1/items/") {
            let isMovie = path.contains("/movie/") || path.contains("693134")
            let detail = isMovie ? PreviewMockFixtures.duneMovieDetail : PreviewMockFixtures.luksusfellenDetail
            let res = TvItemDetailResponse(ok: true, item: detail)
            return (try? LunaCoreClient.encodeJSON(res)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/playback/prepare" {
            let prep = TvPrepareResponse(
                ok: true,
                prepareToken: "preview-prep-token",
                playbackSession: PreviewMockFixtures.playerSession
            )
            return (try? LunaCoreClient.encodeJSON(prep)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/playback/resolve" {
            let start = TvResolveStartResponse(
                ok: true,
                resolveId: "preview-resolve-1",
                wsPath: nil,
                playbackSession: PreviewMockFixtures.playerSession,
                error: nil
            )
            return (try? LunaCoreClient.encodeJSON(start)) ?? Data("{}".utf8)
        }
        if path.hasSuffix("/alternatives") || path == "/api/tv/v1/playback/candidates" {
            let alt = TvAlternativesResponse(
                ok: true,
                sessionId: PreviewMockFixtures.playerSession.sessionId,
                roomName: PreviewMockFixtures.previewRoomName,
                hardwareProfile: PreviewMockFixtures.previewHardwareProfile,
                activeCandidateId: PreviewMockFixtures.playerSession.selectedCandidate.candidateId,
                alternatives: PreviewMockFixtures.previewCandidates
            )
            return (try? LunaCoreClient.encodeJSON(alt)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/playback/heartbeat" {
            let hb = TvHeartbeatResponse(
                ok: true,
                sessionId: PreviewMockFixtures.playerSession.sessionId,
                state: "paused",
                pendingCommand: nil,
                vfsTelemetry: TvVfsTelemetry(streamSource: "På NVMe")
            )
            return (try? LunaCoreClient.encodeJSON(hb)) ?? Data("{}".utf8)
        }
        return Data(#"{"ok":true}"#.utf8)
    }

    // MARK: - Fast CoreGraphics Cinema Artwork & Scrub Frame Generator (< 2 ms in Debug)

    static func makeScrubPreviewImage(width: Int = 640, height: Int = 360) -> CGImage? {
        renderSceneCGImage(slug: "teal-backdrop", width: width, height: height)
    }

    private static func artworkPNG(named slug: String) -> Data {
        if let hit = cachedArtworkPNGs.withLock({ $0[slug] }) {
            return hit
        }
        let isBackdrop = slug.contains("backdrop")
        let isHeroBackdrop = slug.contains("sand-backdrop") || slug.contains("cinema-stage")
        let width = isHeroBackdrop ? 1920 : (isBackdrop ? 1280 : 640)
        let height = isHeroBackdrop ? 1080 : (isBackdrop ? 720 : 960)

        let out = NSMutableData()
        if let cg = renderSceneCGImage(slug: slug, width: width, height: height),
           let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }

        let built = out as Data
        cachedArtworkPNGs.withLock { $0[slug] = built }
        return built
    }

    private static func renderSceneCGImage(slug: String, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let w = CGFloat(width)
        let h = CGFloat(height)

        if slug.contains("cinema-stage") {
            drawSplitCinemaStage(in: ctx, width: w, height: h, colorSpace: colorSpace)
            return ctx.makeImage()
        }

        let palette = scenePalette(for: slug)
        if let skyGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: palette.top)!,
                CGColor(colorSpace: colorSpace, components: palette.mid)!,
                CGColor(colorSpace: colorSpace, components: palette.bottom)!,
            ] as CFArray,
            locations: [0.0, 0.56, 1.0]
        ) {
            ctx.drawLinearGradient(
                skyGrad,
                start: CGPoint(x: w * 0.5, y: h),
                end: CGPoint(x: w * 0.5, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        if let sunGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: palette.sunCore)!,
                CGColor(colorSpace: colorSpace, components: palette.sunHalo)!,
                CGColor(colorSpace: colorSpace, components: [palette.sunHalo[0], palette.sunHalo[1], palette.sunHalo[2], 0.0])!,
            ] as CFArray,
            locations: [0.0, 0.34, 1.0]
        ) {
            let sunCenter = CGPoint(x: w * 0.70, y: h * 0.64)
            ctx.drawRadialGradient(
                sunGrad,
                startCenter: sunCenter,
                startRadius: 0,
                endCenter: sunCenter,
                endRadius: max(w, h) * 0.52,
                options: [.drawsAfterEndLocation]
            )
        }

        let ridgeBack = CGMutablePath()
        ridgeBack.move(to: CGPoint(x: 0, y: 0))
        ridgeBack.addLine(to: CGPoint(x: 0, y: h * 0.38))
        ridgeBack.addCurve(
            to: CGPoint(x: w * 0.56, y: h * 0.46),
            control1: CGPoint(x: w * 0.20, y: h * 0.50),
            control2: CGPoint(x: w * 0.38, y: h * 0.34)
        )
        ridgeBack.addCurve(
            to: CGPoint(x: w, y: h * 0.36),
            control1: CGPoint(x: w * 0.74, y: h * 0.56),
            control2: CGPoint(x: w * 0.88, y: h * 0.42)
        )
        ridgeBack.addLine(to: CGPoint(x: w, y: 0))
        ridgeBack.closeSubpath()
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: palette.ridgeBack)!)
        ctx.addPath(ridgeBack)
        ctx.fillPath()

        let ridgeFront = CGMutablePath()
        ridgeFront.move(to: CGPoint(x: 0, y: 0))
        ridgeFront.addLine(to: CGPoint(x: 0, y: h * 0.24))
        ridgeFront.addCurve(
            to: CGPoint(x: w, y: h * 0.20),
            control1: CGPoint(x: w * 0.34, y: h * 0.32),
            control2: CGPoint(x: w * 0.68, y: h * 0.12)
        )
        ridgeFront.addLine(to: CGPoint(x: w, y: 0))
        ridgeFront.closeSubpath()
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: palette.ridgeFront)!)
        ctx.addPath(ridgeFront)
        ctx.fillPath()

        return ctx.makeImage()
    }

    /// Split dark-left / sunlit-cream-right 16:9 test frame exposing subtitle contrast,
    /// glass panel edges, and focus rings over both deep OLED shadows and bright highlights.
    private static func drawSplitCinemaStage(
        in ctx: CGContext,
        width w: CGFloat,
        height h: CGFloat,
        colorSpace: CGColorSpace
    ) {
        if let darkGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: [0.06, 0.08, 0.12, 1.0])!,
                CGColor(colorSpace: colorSpace, components: [0.13, 0.16, 0.22, 1.0])!,
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: w * 0.5, height: h))
            ctx.drawLinearGradient(
                darkGrad,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: w * 0.5, y: h),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            ctx.restoreGState()
        }

        if let brightGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: [0.95, 0.91, 0.82, 1.0])!,
                CGColor(colorSpace: colorSpace, components: [0.84, 0.77, 0.64, 1.0])!,
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: w * 0.5, y: 0, width: w * 0.5, height: h))
            ctx.drawLinearGradient(
                brightGrad,
                start: CGPoint(x: w * 0.5, y: h),
                end: CGPoint(x: w, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            ctx.restoreGState()
        }

        ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.55, 0.48, 0.38, 0.35])!)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: w * 0.5, y: 0))
        ctx.addLine(to: CGPoint(x: w * 0.5, y: h))
        ctx.strokePath()
    }

    private struct ScenePalette {
        let top: [CGFloat]
        let mid: [CGFloat]
        let bottom: [CGFloat]
        let sunCore: [CGFloat]
        let sunHalo: [CGFloat]
        let ridgeBack: [CGFloat]
        let ridgeFront: [CGFloat]
    }

    private static func scenePalette(for slug: String) -> ScenePalette {
        if slug.contains("sand") {
            return ScenePalette(
                top: [0.92, 0.78, 0.54, 1.0],
                mid: [0.80, 0.55, 0.28, 1.0],
                bottom: [0.36, 0.22, 0.11, 1.0],
                sunCore: [1.0, 0.95, 0.80, 0.92],
                sunHalo: [0.96, 0.72, 0.36, 0.55],
                ridgeBack: [0.58, 0.37, 0.18, 0.88],
                ridgeFront: [0.28, 0.17, 0.09, 0.96]
            )
        }
        if slug.contains("navy") {
            return ScenePalette(
                top: [0.18, 0.28, 0.44, 1.0],
                mid: [0.34, 0.48, 0.66, 1.0],
                bottom: [0.10, 0.16, 0.26, 1.0],
                sunCore: [0.92, 0.96, 1.0, 0.75],
                sunHalo: [0.52, 0.68, 0.88, 0.40],
                ridgeBack: [0.16, 0.24, 0.36, 0.92],
                ridgeFront: [0.08, 0.13, 0.21, 0.97]
            )
        }
        if slug.contains("teal") {
            return ScenePalette(
                top: [0.14, 0.34, 0.32, 1.0],
                mid: [0.22, 0.48, 0.44, 1.0],
                bottom: [0.08, 0.18, 0.17, 1.0],
                sunCore: [0.90, 0.94, 0.84, 0.68],
                sunHalo: [0.42, 0.72, 0.64, 0.38],
                ridgeBack: [0.11, 0.25, 0.24, 0.92],
                ridgeFront: [0.06, 0.14, 0.14, 0.97]
            )
        }
        if slug.contains("crimson") {
            return ScenePalette(
                top: [0.38, 0.14, 0.18, 1.0],
                mid: [0.56, 0.22, 0.24, 1.0],
                bottom: [0.16, 0.07, 0.09, 1.0],
                sunCore: [0.98, 0.78, 0.58, 0.72],
                sunHalo: [0.82, 0.34, 0.28, 0.42],
                ridgeBack: [0.24, 0.09, 0.12, 0.92],
                ridgeFront: [0.12, 0.05, 0.07, 0.97]
            )
        }
        if slug.contains("aubergine") {
            return ScenePalette(
                top: [0.28, 0.18, 0.36, 1.0],
                mid: [0.42, 0.28, 0.50, 1.0],
                bottom: [0.12, 0.08, 0.18, 1.0],
                sunCore: [0.94, 0.88, 0.98, 0.68],
                sunHalo: [0.64, 0.46, 0.76, 0.38],
                ridgeBack: [0.18, 0.12, 0.25, 0.92],
                ridgeFront: [0.09, 0.06, 0.14, 0.97]
            )
        }
        return ScenePalette(
            top: [0.44, 0.28, 0.16, 1.0],
            mid: [0.64, 0.42, 0.22, 1.0],
            bottom: [0.18, 0.11, 0.07, 1.0],
            sunCore: [0.98, 0.86, 0.62, 0.78],
            sunHalo: [0.84, 0.56, 0.28, 0.44],
            ridgeBack: [0.28, 0.18, 0.10, 0.92],
            ridgeFront: [0.14, 0.09, 0.05, 0.97]
        )
    }
}
