import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

/// Offline URLProtocol interceptor for preview mode (`--preview-screen`) and unit tests.
final class PreviewMockURLProtocol: URLProtocol {
    private static let installed = Mutex(false)

    static func installIfNeeded() {
        installed.withLock { flag in
            guard !flag else { return }
            _ = URLProtocol.registerClass(PreviewMockURLProtocol.self)
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
            #if canImport(CoreGraphics) && canImport(ImageIO)
            responseData = PreviewMockArtworkRenderer.artworkPNG(named: path)
            #else
            responseData = Data()
            #endif
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
        if path == "/api/tv/v2/pair/request" {
            let reqRes = TvPairingRequestResponse(
                ok: true,
                pairingCode: "preview-pair-1",
                displayCode: "482 917",
                expiresAt: "2026-12-31T23:59:59Z",
                pollIntervalSeconds: 60
            )
            return (try? LunaCoreClient.encodeJSON(reqRes)) ?? Data("{}".utf8)
        }
        if path.hasPrefix("/api/tv/v2/pair/poll/") {
            let pollRes = TvPairingPollResponse(
                ok: true,
                status: "pending",
                deviceToken: nil,
                device: nil,
                error: nil
            )
            return (try? LunaCoreClient.encodeJSON(pollRes)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v2/bootstrap" {
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
        if path == "/api/tv/v2/home" {
            return (try? LunaCoreClient.encodeJSON(PreviewMockFixtures.homeResponse)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v2/library" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let mediaType = comps?.queryItems?.first(where: { $0.name == "mediaType" })?.value ?? "movie"
            let tier = comps?.queryItems?.first(where: { $0.name == "tier" })?.value ?? "all"
            let sort = comps?.queryItems?.first(where: { $0.name == "sort" })?.value ?? "recent"
            var response = PreviewMockFixtures.libraryResponse(mediaType: mediaType)
            if tier != "all" || sort != "recent" {
                var filtered = response.localItems
                if tier != "all" {
                    filtered = filtered.filter { card in
                        let cardTier = (card.availability?.tier ?? "").lowercased()
                        return cardTier == tier.lowercased()
                    }
                }
                if sort == "rating" {
                    filtered.sort { ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) }
                } else if sort == "title" {
                    filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                }
                response = TvLibraryResponse(
                    ok: response.ok,
                    section: response.section,
                    activeFilters: TvLibraryActiveFilters(tier: tier, mediaType: mediaType, sort: sort),
                    counts: response.counts,
                    watchlist: response.watchlist,
                    localItems: filtered,
                    localHasMore: false,
                    customLists: response.customLists
                )
            }
            return (try? LunaCoreClient.encodeJSON(response)) ?? Data("{}".utf8)
        }
        if path.hasPrefix("/api/tv/v2/rows/") {
            let rowRes = TvRowPageResponse(
                ok: true,
                rowId: "custom:nordic-noir",
                sourceKind: "custom",
                title: "Nordisk spenning",
                offset: 0,
                limit: 36,
                totalEstimate: PreviewMockFixtures.seriesCards.count,
                hasMore: false,
                nextPath: nil,
                items: PreviewMockFixtures.seriesCards
            )
            return (try? LunaCoreClient.encodeJSON(rowRes)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v2/delete/preflight" {
            let preflightJSON = #"""
            {
              "preflightId": "preview-pf-1",
              "target": {
                "kind": "movie",
                "scope": "title",
                "season": null,
                "episode": null,
                "title": "Dune: Part Two",
                "year": 2024,
                "monitored": true
              },
              "files": {
                "count": 1,
                "logicalBytes": 53687091200,
                "physicalBytes": 53687091200
              },
              "blockers": [],
              "warnings": []
            }
            """#
            return Data(preflightJSON.utf8)
        }
        if path == "/api/tv/v2/search" {
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
        if path.hasPrefix("/api/tv/v2/catalog/") {
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
            let isSpecials = path.hasSuffix("/seasons/0")
            let seasonNum = isSpecials ? 0 : 28
            let episodes = isSpecials
                ? [
                    TvEpisodeCard(
                        itemId: "episode:tmdb:246810:s0:e1",
                        seasonNumber: 0,
                        episodeNumber: 1,
                        title: "Tilbakeblikk",
                        overview: "Høydepunkter og oppfølging fra tidligere sesonger.",
                        stillUrl: "/preview-art/teal-backdrop.png",
                        airDate: "2025-12-20",
                        isUpcoming: false,
                        airDateBadge: nil,
                        voteAverage: 7.5,
                        runtimeSeconds: 2520,
                        watched: false,
                        availability: TvAvailabilityInfo(state: "instant", tier: "nvme"),
                        progress: nil
                    )
                ]
                : PreviewMockFixtures.luksusfellenSeason28Episodes
            let seasonRes = TvSeasonDetailResponse(
                ok: true,
                tmdbId: 246810,
                seasonNumber: seasonNum,
                title: LunaCopy.localizedSeasonTitle(nil, seasonNumber: seasonNum),
                episodes: episodes
            )
            return (try? LunaCoreClient.encodeJSON(seasonRes)) ?? Data("{}".utf8)
        }
        if path.hasPrefix("/api/tv/v2/items/") {
            let isMovie = path.contains("/movie/") || path.contains("693134")
            let detail = isMovie ? PreviewMockFixtures.duneMovieDetail : PreviewMockFixtures.luksusfellenDetail
            let res = TvItemDetailResponse(ok: true, item: detail)
            return (try? LunaCoreClient.encodeJSON(res)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v2/playback/prepare" {
            let prep = TvPrepareResponse(
                ok: true,
                prepareToken: "preview-prep-token",
                playbackSession: PreviewMockFixtures.playerSession
            )
            return (try? LunaCoreClient.encodeJSON(prep)) ?? Data("{}".utf8)
        }
        if path == "/api/tv/v2/playback/resolve" {
            let start = TvResolveStartResponse(
                ok: true,
                resolveId: "preview-resolve-1",
                wsPath: nil,
                playbackSession: PreviewMockFixtures.playerSession,
                error: nil
            )
            return (try? LunaCoreClient.encodeJSON(start)) ?? Data("{}".utf8)
        }
        if path.hasSuffix("/alternatives") || path == "/api/tv/v2/playback/candidates" {
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
        if path == "/api/tv/v2/playback/heartbeat" {
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
}
