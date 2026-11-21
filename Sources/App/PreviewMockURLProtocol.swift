import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Offline URLProtocol interceptor and procedural Lampelys cinema artwork generator for preview mode.
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
                server: TvServerBootstrapInfo(name: "LunaCore Preview", version: "5.1.1", apiVersion: 1, featureLevel: 5, capabilities: ["dvFel": false]),
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
                availableSorts: nil,
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
            let res = TvItemDetailResponse(ok: true, item: PreviewMockFixtures.luksusfellenDetail)
            return (try? LunaCoreClient.encodeJSON(res)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/playback/prepare" {
            let prep = TvPrepareResponse(
                ok: true,
                status: "ready",
                reused: true,
                prepareToken: "preview-prep-token",
                canClientPrewarmBytes: false,
                playbackSession: PreviewMockFixtures.playerSession
            )
            return (try? LunaCoreClient.encodeJSON(prep)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v1/playback/resolve" {
            let start = TvResolveStartResponse(
                ok: true,
                status: "ready",
                preResolved: true,
                resolveId: "preview-resolve-1",
                wsPath: nil,
                playbackSession: PreviewMockFixtures.playerSession,
                error: nil
            )
            return (try? LunaCoreClient.encodeJSON(start)) ?? Data("{}".utf8)
        }
        if path.hasSuffix("/alternatives") {
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
                watchCompleted: false,
                vfsLockActive: true,
                leaseExpiresAt: nil,
                nextEpisodePrewarmStarted: false,
                nextEpisodePrewarmReady: true,
                pendingCommand: nil,
                vfsTelemetry: TvVfsTelemetry(streamSource: "Strømmes ved start", vfsMountFolder: nil)
            )
            return (try? LunaCoreClient.encodeJSON(hb)) ?? Data("{}".utf8)
        }
        return Data(#"{"ok":true}"#.utf8)
    }

    // MARK: - Procedural Lampelys Artwork PNG Generator

    private static func artworkPNG(named slug: String) -> Data {
        if let hit = cachedArtworkPNGs.withLock({ $0[slug] }) {
            return hit
        }
        let isBackdrop = slug.contains("backdrop")
        let width = isBackdrop ? 960 : 560
        let height = isBackdrop ? 540 : 840
        let topRGB: (Double, Double, Double)
        if slug.contains("navy") {
            topRGB = (0.10, 0.16, 0.27)
        } else if slug.contains("aubergine") {
            topRGB = (0.20, 0.12, 0.25)
        } else if slug.contains("teal") {
            topRGB = (0.11, 0.23, 0.21)
        } else if slug.contains("crimson") {
            topRGB = (0.25, 0.10, 0.13)
        } else if slug.contains("sand") {
            topRGB = (0.31, 0.20, 0.11)
        } else {
            topRGB = (0.26, 0.17, 0.10)
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let ty = Double(y) / Double(max(1, height - 1))
            for x in 0..<width {
                let tx = Double(x) / Double(max(1, width - 1))
                let glow = max(0, 1.0 - hypot(tx - 0.66, ty - 0.30) * 1.4)
                let horizon = max(0, 1.0 - abs(ty - 0.62) * 3.8) * 0.24
                let r = min(1.0, topRGB.0 * (1.0 - ty * 0.72) + 0.42 * glow * 0.45 + horizon * 0.35 + 0.04)
                let g = min(1.0, topRGB.1 * (1.0 - ty * 0.75) + 0.29 * glow * 0.40 + horizon * 0.22 + 0.03)
                let b = min(1.0, topRGB.2 * (1.0 - ty * 0.78) + 0.13 * glow * 0.30 + horizon * 0.10 + 0.03)
                let idx = (y * width + x) * 4
                pixels[idx] = UInt8((r * 255.0).rounded())
                pixels[idx + 1] = UInt8((g * 255.0).rounded())
                pixels[idx + 2] = UInt8((b * 255.0).rounded())
                pixels[idx + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let out = NSMutableData()
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cg = CGImage(
               width: width,
               height: height,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: width * 4,
               space: colorSpace,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: true,
               intent: .defaultIntent
           ),
           let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
        }

        let built = out as Data
        cachedArtworkPNGs.withLock { $0[slug] = built }
        return built
    }
}
