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

    func schedulePreResolve(for item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        preResolve.schedule(
            targetItemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            startPos: target.startPos,
            client: refreshedClient()
        )
    }

    func launchSerializedDetailLoad(preserveSeason: Bool, expectedScope: String? = nil) {
        detailLoadTask?.cancel()
        detailLoadGeneration &+= 1
        let generation = detailLoadGeneration
        let targetScope = expectedScope ?? currentScopeKey
        detailLoadTask = Task { @MainActor [weak self] in
            await self?.loadDetail(
                preserveSeason: preserveSeason,
                generation: generation,
                expectedScope: targetScope
            )
        }
    }

    func runSerializedDetailLoad(preserveSeason: Bool, expectedScope: String? = nil) async {
        launchSerializedDetailLoad(preserveSeason: preserveSeason, expectedScope: expectedScope)
        await detailLoadTask?.value
    }

    private func loadDetail(preserveSeason: Bool = false, generation: UInt64, expectedScope: String) async {
        guard let client = refreshedClient() else {
            isLoading = false
            return
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

            if loaded.mediaType == "movie",
               !Task.isCancelled,
               generation == detailLoadGeneration,
               sessionContext?.activePlaybackTarget == nil {
                schedulePreResolve(for: loaded)
            }

            if loaded.mediaType == "series" {
                let targetSeason: Int
                if preserveSeason && selectedSeasonNumber > 0 {
                    targetSeason = selectedSeasonNumber
                } else if let nextSeason = loaded.nextUp?.season,
                          nextSeason >= 0,
                          loaded.seasons?.contains(where: { $0.seasonNumber == nextSeason }) ?? true {
                    targetSeason = nextSeason
                } else {
                    targetSeason = loaded.selectedSeason
                        ?? loaded.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                        ?? 1
                }
                if !preserveSeason {
                    selectedSeasonNumber = targetSeason
                }
                if let inlineEpisodes = loaded.episodes,
                   !inlineEpisodes.isEmpty,
                   (loaded.selectedSeason == targetSeason || inlineEpisodes.first?.seasonNumber == targetSeason) {
                    seasonLoadGeneration &+= 1
                    isLoadingEpisodes = false
                    episodes = inlineEpisodes
                } else {
                    await loadSeasonEpisodes(detail: loaded, seasonNumber: targetSeason)
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
                schedulePreResolve(for: loaded)
            }
        } catch is CancellationError {
            return
        } catch LunaCoreError.unauthorized {
            guard generation == detailLoadGeneration else { return }
            sessionContext?.unpairDevice()
        } catch {
            guard generation == detailLoadGeneration else { return }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        if generation == detailLoadGeneration {
            isLoading = false
        }
    }

    func loadSeasonEpisodes(detail: TvItemDetail, seasonNumber: Int) async {
        guard let client = refreshedClient(),
              let tmdbId = detail.ids.tmdb else { return }
        seasonLoadGeneration &+= 1
        let generation = seasonLoadGeneration
        isLoadingEpisodes = true
        if let seasonRes = try? await client.fetchSeasonEpisodes(tmdbId: tmdbId, seasonNumber: seasonNumber),
           !Task.isCancelled,
           generation == seasonLoadGeneration,
           selectedSeasonNumber == seasonNumber {
            episodes = seasonRes.episodes
        }
        if generation == seasonLoadGeneration {
            isLoadingEpisodes = false
        }
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    func markLocalMutationAndReload() async {
        if let sessionContext {
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce &+ 1
            sessionContext.notifyContentMutated()
        }
        await runSerializedDetailLoad(preserveSeason: true)
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
            await markLocalMutationAndReload()
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
            await markLocalMutationAndReload()
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
