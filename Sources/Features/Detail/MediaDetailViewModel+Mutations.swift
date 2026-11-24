import Foundation

extension MediaDetailViewModel {
    // MARK: - Data Loading & Mutations

    func refreshedClient() -> LunaCoreClient? {
        let latest = sessionContext?.makeClient()
        if latest != nil || client != nil {
            setClient(latest)
        }
        return latest
    }

    var detailCacheKey: String {
        ItemDetailMemoryCache.makeKey(
            baseURL: client?.baseURL,
            mediaType: mediaType,
            itemId: itemId,
            roomName: sessionContext?.roomName ?? "",
            hardwareProfile: sessionContext?.hardwareProfile ?? ""
        )
    }

    func schedulePreResolve(for item: TvItemDetail, immediate: Bool = true) {
        let target = primaryTargetInfo(item)
        preResolve.schedule(
            targetItemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            startPos: target.startPos,
            immediate: immediate,
            client: refreshedClient()
        )
    }

    func launchSerializedDetailLoad(
        preserveSeason: Bool,
        expectedScope: String? = nil,
        bypassCache: Bool = false
    ) {
        detailLoadTask?.cancel()
        detailLoadGeneration &+= 1
        let generation = detailLoadGeneration
        let targetScope = expectedScope ?? currentScopeKey
        detailLoadTask = Task { @MainActor [weak self] in
            await self?.loadDetail(
                preserveSeason: preserveSeason,
                generation: generation,
                expectedScope: targetScope,
                bypassCache: bypassCache
            )
        }
    }

    func runSerializedDetailLoad(
        preserveSeason: Bool,
        expectedScope: String? = nil,
        bypassCache: Bool = false
    ) async {
        launchSerializedDetailLoad(
            preserveSeason: preserveSeason,
            expectedScope: expectedScope,
            bypassCache: bypassCache
        )
        await detailLoadTask?.value
    }

    private func resolveInitialTargetSeason(for loaded: TvItemDetail, preserveSeason: Bool) -> Int {
        if preserveSeason && selectedSeasonNumber > 0 {
            return selectedSeasonNumber
        }
        if let nextSeason = loaded.nextUp?.season,
           nextSeason >= 0,
           loaded.seasons?.contains(where: { $0.seasonNumber == nextSeason }) ?? true {
            return nextSeason
        }
        return loaded.selectedSeason
            ?? loaded.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
            ?? 1
    }

    private func persistDetailSnapshot(_ loaded: TvItemDetail, season: Int?, seasonEpisodes: [TvEpisodeCard]?) {
        let key = detailCacheKey
        var existingMap = ItemDetailMemoryCache.shared.snapshot(for: key)?.episodesBySeason ?? [:]
        if let season, let seasonEpisodes, !seasonEpisodes.isEmpty {
            existingMap[season] = seasonEpisodes
        }
        ItemDetailMemoryCache.shared.store(
            ItemDetailSnapshot(
                detail: loaded,
                episodesBySeason: existingMap,
                fetchedAt: Date(),
                refreshNonce: sessionContext?.homeRefreshNonce ?? 0
            ),
            for: key
        )
    }

    private func loadDetail(
        preserveSeason: Bool = false,
        generation: UInt64,
        expectedScope: String,
        bypassCache: Bool = false
    ) async {
        guard let client = refreshedClient() else {
            isLoading = false
            return
        }
        let cacheKey = detailCacheKey
        let currentNonce = sessionContext?.homeRefreshNonce ?? 0

        if !bypassCache, !preserveSeason, let cached = ItemDetailMemoryCache.shared.snapshot(for: cacheKey) {
            let targetSeason = resolveInitialTargetSeason(for: cached.detail, preserveSeason: false)
            let isFresh = TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: true,
                lastValidatedAt: cached.fetchedAt,
                cachedRefreshNonce: cached.refreshNonce,
                currentRefreshNonce: currentNonce,
                freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
            )
            let hasRequiredSeason = cached.detail.mediaType != "series" || cached.episodesBySeason[targetSeason] != nil
            if isFresh && hasRequiredSeason {
                loadedScopeKey = expectedScope
                detail = cached.detail
                if cached.detail.mediaType == "series" {
                    selectedSeasonNumber = targetSeason
                    episodes = cached.episodesBySeason[targetSeason] ?? []
                }
                errorMessage = nil
                isLoading = false
                isLoadingEpisodes = false
                if sessionContext?.activePlaybackTarget == nil {
                    schedulePreResolve(for: cached.detail, immediate: true)
                }
                return
            }
        }

        if detail == nil {
            isLoading = true
        }
        errorMessage = nil

        let requestedSeason: Int? = (preserveSeason && mediaType == "series") ? selectedSeasonNumber : nil

        do {
            let loaded = try await client.fetchItemDetail(
                mediaType: mediaType,
                itemId: itemId,
                seasonNumber: requestedSeason
            )
            guard !Task.isCancelled,
                  generation == detailLoadGeneration,
                  currentScopeKey == expectedScope else {
                return
            }
            loadedScopeKey = expectedScope
            detail = loaded

            if loaded.mediaType == "movie" {
                persistDetailSnapshot(loaded, season: nil, seasonEpisodes: nil)
                if !Task.isCancelled,
                   generation == detailLoadGeneration,
                   sessionContext?.activePlaybackTarget == nil {
                    schedulePreResolve(for: loaded, immediate: true)
                }
            }

            if loaded.mediaType == "series" {
                let targetSeason = resolveInitialTargetSeason(for: loaded, preserveSeason: preserveSeason)
                if !preserveSeason {
                    selectedSeasonNumber = targetSeason
                }
                if let inlineEpisodes = loaded.episodes,
                   !inlineEpisodes.isEmpty,
                   (loaded.selectedSeason == targetSeason || inlineEpisodes.first?.seasonNumber == targetSeason) {
                    seasonLoadGeneration &+= 1
                    isLoadingEpisodes = false
                    episodes = inlineEpisodes
                    persistDetailSnapshot(loaded, season: targetSeason, seasonEpisodes: inlineEpisodes)
                } else {
                    _ = await loadSeasonEpisodes(detail: loaded, seasonNumber: targetSeason, previousSeason: nil)
                }
                guard !Task.isCancelled,
                      generation == detailLoadGeneration,
                      currentScopeKey == expectedScope,
                      sessionContext?.activePlaybackTarget == nil else {
                    if generation == detailLoadGeneration {
                        isLoading = false
                    }
                    return
                }
                schedulePreResolve(for: loaded, immediate: true)
            }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            guard generation == detailLoadGeneration else { return }
            ItemDetailMemoryCache.shared.clear()
            sessionContext?.unpairDevice()
        } catch {
            guard generation == detailLoadGeneration else { return }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        if generation == detailLoadGeneration {
            isLoading = false
        }
    }

    @discardableResult
    func loadSeasonEpisodes(
        detail: TvItemDetail,
        seasonNumber: Int,
        previousSeason: Int? = nil
    ) async -> Bool {
        let cacheKey = detailCacheKey
        if let cached = ItemDetailMemoryCache.shared.snapshot(for: cacheKey),
           cached.refreshNonce == (sessionContext?.homeRefreshNonce ?? -1),
           let cachedSeasonEps = cached.episodesBySeason[seasonNumber],
           !cachedSeasonEps.isEmpty {
            seasonLoadGeneration &+= 1
            episodes = cachedSeasonEps
            isLoadingEpisodes = false
            return true
        }

        guard let client = refreshedClient(),
              let tmdbId = detail.ids.tmdb else { return false }
        seasonLoadGeneration &+= 1
        let generation = seasonLoadGeneration
        isLoadingEpisodes = true
        defer {
            if generation == seasonLoadGeneration {
                isLoadingEpisodes = false
            }
        }
        do {
            let seasonRes = try await client.fetchSeasonEpisodes(tmdbId: tmdbId, seasonNumber: seasonNumber)
            guard !Task.isCancelled,
                  generation == seasonLoadGeneration,
                  selectedSeasonNumber == seasonNumber else {
                return false
            }
            episodes = seasonRes.episodes
            persistDetailSnapshot(detail, season: seasonNumber, seasonEpisodes: seasonRes.episodes)
            return true
        } catch where LunaCoreError.isCancellation(error) {
            return false
        } catch {
            if generation == seasonLoadGeneration {
                if let previousSeason, previousSeason != seasonNumber {
                    selectedSeasonNumber = previousSeason
                }
                mutationErrorBanner = "Kunne ikke hente episoder for sesong \(seasonNumber): \(LunaCopy.friendlyErrorMessage(error))"
            }
            return false
        }
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func persistOptimisticDetailMutation() {
        if let sessionContext {
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce &+ 1
            sessionContext.notifyContentMutated()
        }
        if let updated = detail {
            persistDetailSnapshot(
                updated,
                season: updated.mediaType == "series" ? selectedSeasonNumber : nil,
                seasonEpisodes: updated.mediaType == "series" ? episodes : nil
            )
        }
    }

    func markLocalMutationAndReload() async {
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail?.ids.tmdb)
        if let sessionContext {
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce &+ 1
            sessionContext.notifyContentMutated()
        }
        await runSerializedDetailLoad(preserveSeason: true, bypassCache: true)
    }

    func toggleWatchlist() async {
        guard let item = detail, let client = refreshedClient() else { return }
        let nextVal = !item.inWatchlist
        detail?.inWatchlist = nextVal
        do {
            try await client.setWatchlist(
                listed: nextVal,
                mediaType: item.mediaType,
                ids: item.ids,
                title: item.title,
                year: item.year
            )
            persistOptimisticDetailMutation()
        } catch {
            detail?.inWatchlist = item.inWatchlist
            showMutationError(error)
        }
    }

    func toggleMonitor() async {
        guard let item = detail, let client = refreshedClient() else { return }
        let nextMonitored = !item.isMonitoredFlag
        let nextMode = nextMonitored ? (item.mediaType == "series" ? "unwatched" : "all") : "off"
        detail?.monitored = nextMonitored
        detail?.monitorMode = nextMode
        do {
            let res = try await client.toggleMonitor(
                monitored: nextMonitored,
                monitorMode: nextMode,
                mediaType: item.mediaType,
                ids: item.ids,
                title: item.title,
                year: item.year
            )
            detail?.monitored = res.monitored ?? nextMonitored
            detail?.monitorMode = res.monitorMode ?? nextMode
            persistOptimisticDetailMutation()
        } catch {
            detail?.monitored = item.monitored
            detail?.monitorMode = item.monitorMode
            showMutationError(error)
        }
    }

    func handleHeroWatchedTap() async {
        guard let item = detail else { return }
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            if let ep = episodes.first(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }) {
                await toggleEpisodeWatched(ep)
                return
            }
            guard let client = refreshedClient() else { return }
            do {
                try await client.setWatched(
                    watched: true,
                    mediaType: "episode",
                    ids: item.ids,
                    title: item.title,
                    year: item.year,
                    season: next.season,
                    episode: next.episode
                )
                await markLocalMutationAndReload()
            } catch {
                showMutationError(error)
            }
            return
        }
        if item.mediaType == "series" {
            pendingSeriesWatchedItem = item
            return
        }
        await toggleWatched(item)
    }

    func confirmSeriesWatched(_ item: TvItemDetail) async {
        pendingSeriesWatchedItem = nil
        await toggleWatched(item)
    }

    private func toggleWatched(_ item: TvItemDetail) async {
        guard let client = refreshedClient() else { return }
        let nextWatched = !item.watched
        detail?.watched = nextWatched
        do {
            try await client.setWatched(
                watched: nextWatched,
                mediaType: item.mediaType,
                ids: item.ids,
                title: item.title,
                year: item.year
            )
            await markLocalMutationAndReload()
        } catch {
            detail?.watched = item.watched
            showMutationError(error)
        }
    }

    func toggleEpisodeWatched(_ episode: TvEpisodeCard) async {
        guard let detail, let client = refreshedClient() else { return }
        let targetWatched = !episode.watched
        if let idx = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[idx].watched = targetWatched
            if targetWatched {
                episodes[idx].progress = nil
            }
        }
        do {
            try await client.setWatched(
                watched: targetWatched,
                mediaType: "episode",
                ids: detail.ids,
                title: detail.title,
                year: detail.year,
                season: episode.seasonNumber,
                episode: episode.episodeNumber
            )
            await markLocalMutationAndReload()
        } catch {
            if let idx = episodes.firstIndex(where: { $0.id == episode.id }) {
                episodes[idx] = episode
            }
            showMutationError(error)
        }
    }
}
