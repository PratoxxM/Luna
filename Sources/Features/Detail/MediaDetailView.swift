import SwiftUI
import AetherBridge

struct MediaDetailView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var ambient: AmbientBackdropController

    let mediaType: String
    let itemId: String
    let initialTitle: String

    @State private var detail: TvItemDetail?
    @State private var selectedSeasonNumber: Int = 1
    @State private var episodes: [TvEpisodeCard] = []
    @State private var isLoading: Bool = true
    @State private var isLoadingEpisodes: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var pendingSeriesWatchedItem: TvItemDetail?
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var selectedActorQuery: String?

    @StateObject private var preResolve = DetailPreResolveController()
    @State private var sourcePickerContext: SourcePickerContext?
    @State private var bannerClearTask: Task<Void, Never>?

    @Namespace private var detailFocusNamespace

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                if let mutationErrorBanner {
                    TransientErrorBanner(message: mutationErrorBanner)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 18)
                }

                if let detail {
                    DetailHeroHeaderView(
                        item: detail,
                        client: client,
                        primaryPlayTitle: primaryPlayLabel(detail),
                        watchedButtonTitle: watchedButtonTitle(detail),
                        isPreResolvedReady: preResolve.isPreResolvedReady,
                        focusNamespace: detailFocusNamespace,
                        onPlay: {
                            launchPrimaryPlayback(detail)
                        },
                        onToggleWatchlist: {
                            Task { await toggleWatchlist(detail) }
                        },
                        onToggleWatched: {
                            Task { await handleHeroWatchedTap(detail) }
                        },
                        onPickSource: {
                            let target = primaryTargetInfo(detail)
                            sourcePickerContext = SourcePickerContext(
                                itemId: target.itemId,
                                title: target.title,
                                seriesTitle: target.seriesTitle,
                                startPositionSeconds: target.startPos,
                                existingPrepareToken: preResolve.matchingToken(for: target.itemId),
                                backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
                                logoUrl: detail.logoUrl
                            )
                        },
                        onToggleFavorite: {
                            Task { await toggleFavorite(detail) }
                        }
                    )

                    if detail.mediaType == "series", let seasons = detail.seasons, !seasons.isEmpty {
                        seasonsAndEpisodesSection(detail: detail, seasons: seasons, client: client)
                    }

                    DetailCastStripView(
                        members: detail.castMembers,
                        castNames: detail.cast,
                        client: client
                    ) { actorName in
                        selectedActorQuery = actorName
                    }
                } else if isLoading {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter detaljer for \(initialTitle)…")
                            .font(.title3)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(80)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadDetail() }
                        }
                    }
                    .padding(LunaTheme.horizontalGutter)
                }
            }
            .padding(.bottom, 84)
        }
        .focusScope(detailFocusNamespace)
        .navigationDestination(item: $selectedActorQuery) { actorName in
            SearchView(initialQuery: actorName)
        }
        .sheet(item: $sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked, reusedToken in
                    let target = ctx
                    _ = preResolve.consumeForPlayback(itemId: target.itemId, client: sessionStore.makeClient())
                    sourcePickerContext = nil
                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                        itemId: target.itemId,
                        title: target.title,
                        seriesTitle: target.seriesTitle,
                        startPositionSeconds: target.startPositionSeconds,
                        candidateId: reusedToken == nil ? picked.candidateId : nil,
                        prepareToken: reusedToken,
                        backdropUrl: target.backdropUrl ?? detail?.backdropUrl,
                        logoUrl: target.logoUrl ?? detail?.logoUrl
                    )
                },
                onCancel: {
                    sourcePickerContext = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            pendingSeriesWatchedItem?.watched == true
                ? "Marker hele serien som usett?"
                : "Marker hele serien som sett?",
            isPresented: Binding(
                get: { pendingSeriesWatchedItem != nil },
                set: { if !$0 { pendingSeriesWatchedItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = pendingSeriesWatchedItem {
                Button(item.watched ? "Marker hele serien som usett" : "Marker hele serien som sett") {
                    pendingSeriesWatchedItem = nil
                    Task { await toggleWatched(item) }
                }
                Button("Avbryt", role: .cancel) {
                    pendingSeriesWatchedItem = nil
                }
            }
        }
        .task(id: "\(mediaType)#\(itemId)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)") {
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadDetail()
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            Task { await loadDetail(preserveSeason: true) }
        }
        .onChange(of: sessionStore.activePlaybackTarget) { oldTarget, newTarget in
            if oldTarget != nil, newTarget == nil, let detail {
                schedulePreResolve(for: detail)
            }
        }
        .onDisappear {
            bannerClearTask?.cancel()
            preResolve.handleDisappear(
                isLaunchingPlayback: sessionStore.activePlaybackTarget != nil,
                isShowingSourcePicker: sourcePickerContext != nil,
                client: sessionStore.makeClient()
            )
        }
    }

    // MARK: - Seasons & 16:9 Episodes

    private func seasonsAndEpisodesSection(
        detail: TvItemDetail,
        seasons: [TvSeasonSummary],
        client: MediaOSClient?
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(seasons) { season in
                        let selected = selectedSeasonNumber == season.seasonNumber
                        LunaPillButton(
                            season.name,
                            badgeText: season.episodeCount > 0 ? String(season.episodeCount) : nil,
                            isSelected: selected,
                            prominence: .subtleChip
                        ) {
                            guard selectedSeasonNumber != season.seasonNumber else { return }
                            selectedSeasonNumber = season.seasonNumber
                            Task { await loadSeasonEpisodes(detail: detail, seasonNumber: season.seasonNumber) }
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()

            if isLoadingEpisodes {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Henter episoder…")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 28) {
                            ForEach(episodes) { ep in
                                EpisodeCardView(
                                    episode: ep,
                                    client: client,
                                    onPlay: {
                                        guard ep.isUpcoming != true else { return }
                                        let usePrep = preResolve.consumeForPlayback(
                                            itemId: ep.itemId,
                                            client: sessionStore.makeClient()
                                        )
                                        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                                            itemId: ep.itemId,
                                            title: ep.title,
                                            seriesTitle: detail.title,
                                            startPositionSeconds: ep.progress?.positionSeconds,
                                            prepareToken: usePrep,
                                            backdropUrl: ep.stillUrl ?? detail.backdropUrl,
                                            logoUrl: detail.logoUrl
                                        )
                                    },
                                    onPickSource: {
                                        guard ep.isUpcoming != true else { return }
                                        sourcePickerContext = SourcePickerContext(
                                            itemId: ep.itemId,
                                            title: ep.title,
                                            seriesTitle: detail.title,
                                            startPositionSeconds: ep.progress?.positionSeconds,
                                            existingPrepareToken: preResolve.matchingToken(for: ep.itemId)
                                        )
                                    },
                                    onToggleWatched: {
                                        Task { await toggleEpisodeWatched(detail: detail, episode: ep) }
                                    }
                                )
                                .id(ep.id)
                            }
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 18)
                    }
                    .scrollClipDisabled()
                    .onAppear {
                        scrollToTargetEpisode(in: detail, proxy: proxy)
                    }
                    .onChange(of: episodes.map(\.id)) { _, _ in
                        scrollToTargetEpisode(in: detail, proxy: proxy)
                    }
                }
            }
        }
    }

    private func scrollToTargetEpisode(in detail: TvItemDetail, proxy: ScrollViewProxy) {
        let target: TvEpisodeCard? = {
            if let next = detail.nextUp,
               let nextMatch = episodes.first(where: {
                   $0.seasonNumber == next.season && $0.episodeNumber == next.episode
               }) {
                return nextMatch
            }
            return episodes.first(where: { !$0.watched && $0.isUpcoming != true })
        }()
        guard let target, target.id != episodes.first?.id else { return }
        proxy.scrollTo(target.id, anchor: .leading)
    }

    // MARK: - Playback Target & Silent 450ms Pre-Resolve

    private func primaryPlayLabel(_ item: TvItemDetail) -> String {
        if item.mediaType == "series" {
            if let next = item.nextUp {
                if let pos = item.progress?.positionSeconds, pos > 30,
                   item.progress?.season == next.season,
                   item.progress?.episode == next.episode {
                    return String(format: "Fortsett S%02dE%02d", next.season, next.episode)
                }
                return String(format: "Spill S%02dE%02d", next.season, next.episode)
            }
            return "Spill S01E01"
        }
        if let pos = item.progress?.positionSeconds, pos > 30 {
            return "Fortsett"
        }
        return "Spill av"
    }

    private func primaryTargetInfo(_ item: TvItemDetail) -> (itemId: String, title: String, seriesTitle: String?, startPos: Double?) {
        if item.mediaType == "series" {
            let s = item.nextUp?.season ?? selectedSeasonNumber
            let playable = episodes.filter { $0.isUpcoming != true }
            let e = item.nextUp?.episode ?? playable.first?.episodeNumber ?? 1
            let epId: String
            if let tmdb = item.ids.tmdb {
                epId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
            } else {
                epId = item.itemId
            }
            let matchingEp = episodes.first { $0.seasonNumber == s && $0.episodeNumber == e }
            let startPos = matchingEp?.progress?.positionSeconds ?? item.progress?.positionSeconds
            return (epId, matchingEp?.title ?? item.title, item.title, startPos)
        }
        return (item.itemId, item.title, nil, item.progress?.positionSeconds)
    }

    private func launchPrimaryPlayback(_ item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        let matchingToken = preResolve.consumeForPlayback(
            itemId: target.itemId,
            client: sessionStore.makeClient()
        )
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            startPositionSeconds: target.startPos,
            prepareToken: matchingToken,
            backdropUrl: item.backdropUrl ?? item.cardBackdropUrl,
            logoUrl: item.logoUrl
        )
    }

    private func schedulePreResolve(for item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        preResolve.schedule(
            targetItemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            startPos: target.startPos,
            client: sessionStore.makeClient()
        )
    }

    // MARK: - Data Loading & Mutations

    private func watchedButtonTitle(_ item: TvItemDetail) -> String {
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            return String(format: "Sett S%02dE%02d", next.season, next.episode)
        }
        return "Sett"
    }

    private func loadDetail(preserveSeason: Bool = false) async {
        guard let client = sessionStore.makeClient() else { return }
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
            detail = loaded
            ambient.setImmediate(
                dominantColor: loaded.dominantColor,
                blurHash: loaded.blurHash
            )

            if loaded.mediaType == "series" {
                let targetSeason: Int
                if preserveSeason && selectedSeasonNumber > 0 {
                    targetSeason = selectedSeasonNumber
                } else {
                    targetSeason = loaded.selectedSeason
                        ?? loaded.nextUp?.season
                        ?? loaded.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                        ?? 1
                    selectedSeasonNumber = targetSeason
                }
                if let inlineEpisodes = loaded.episodes,
                   !inlineEpisodes.isEmpty,
                   loaded.selectedSeason == targetSeason {
                    episodes = inlineEpisodes
                } else {
                    await loadSeasonEpisodes(detail: loaded, seasonNumber: targetSeason)
                }
            }

            schedulePreResolve(for: loaded)
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSeasonEpisodes(detail: TvItemDetail, seasonNumber: Int) async {
        guard let client = sessionStore.makeClient(),
              let tmdbId = detail.ids.tmdb else { return }
        isLoadingEpisodes = true
        if let seasonRes = try? await client.fetchSeasonEpisodes(tmdbId: tmdbId, seasonNumber: seasonNumber) {
            episodes = seasonRes.episodes
        }
        isLoadingEpisodes = false
    }

    private func showMutationError(_ error: Error) {
        bannerClearTask?.cancel()
        mutationErrorBanner = "Kunne ikke lagre endring: \(error.localizedDescription)"
        bannerClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            mutationErrorBanner = nil
        }
    }

    private func markLocalMutationAndReload() async {
        lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
        sessionStore.notifyContentMutated()
        await loadDetail(preserveSeason: true)
    }

    private func toggleWatchlist(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
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

    private func toggleFavorite(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextVal = !item.favoriteFlag
        detail?.isFavorite = nextVal
        do {
            try await client.setFavorite(
                favorite: nextVal,
                mediaType: item.mediaType,
                ids: item.ids,
                title: item.title,
                year: item.year
            )
            await markLocalMutationAndReload()
        } catch {
            detail?.isFavorite = item.isFavorite
            showMutationError(error)
        }
    }

    private func handleHeroWatchedTap(_ item: TvItemDetail) async {
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            if let idx = episodes.firstIndex(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }) {
                await toggleEpisodeWatched(detail: item, episode: episodes[idx])
                return
            }
            guard let client = sessionStore.makeClient() else { return }
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

    private func toggleWatched(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
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

    private func toggleEpisodeWatched(detail: TvItemDetail, episode: TvEpisodeCard) async {
        guard let client = sessionStore.makeClient() else { return }
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
