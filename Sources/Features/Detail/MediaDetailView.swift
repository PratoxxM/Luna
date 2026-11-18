import SwiftUI
import AetherBridge

struct MediaDetailView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.dismiss) private var dismiss

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
    @State private var pendingDeleteTarget: TvDeleteRequestTarget?
    @State private var lastSeenRefreshNonce: Int = -1

    @StateObject private var preResolve = DetailPreResolveController()
    @State private var sourcePickerContext: SourcePickerContext?
    @State private var bannerClearTask: Task<Void, Never>?
    @State private var postPlaybackReloadFallbackTask: Task<Void, Never>?
    @State private var detailLoadTask: Task<Void, Never>?
    @State private var detailLoadGeneration: UInt64 = 0
    @State private var loadedScopeKey: String?
    @State private var awaitingPostPlaybackRefresh: Bool = false
    @State private var subpageToken = UUID()
    @State private var modalToken = UUID()

    private var scopeKey: String {
        "\(mediaType)#\(itemId)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    @Namespace private var detailFocusNamespace

    private let detailGutter: CGFloat = 90

    var body: some View {
        let client = sessionStore.makeClient()

        ZStack(alignment: .topLeading) {
            LunaTheme.canvas.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    if let detail {
                        DetailHeroHeaderView(
                            item: detail,
                            client: client,
                            primaryPlayTitle: primaryPlayLabel(detail),
                            watchedButtonTitle: watchedButtonTitle(detail),
                            isPreResolvedReady: preResolve.isPreResolvedReady,
                            horizontalGutter: detailGutter,
                            focusNamespace: detailFocusNamespace,
                            hasLocalEpisodes: episodes.contains {
                                $0.availability?.isPhysicalLocal == true ||
                                $0.availability?.isLocalVfs == true
                            },
                            onPlay: {
                                launchPrimaryPlayback(detail)
                            },
                            onToggleWatchlist: {
                                Task { await toggleWatchlist(detail) }
                            },
                            onToggleWatched: {
                                Task { await handleHeroWatchedTap(detail) }
                            },
                            onToggleMonitor: {
                                Task { await toggleMonitor(detail) }
                            },
                            onPickSource: {
                                let target = primaryTargetInfo(detail)
                                sourcePickerContext = SourcePickerContext(
                                    itemId: target.itemId,
                                    title: target.title,
                                    seriesTitle: target.seriesTitle,
                                    season: target.season,
                                    episode: target.episode,
                                    startPositionSeconds: target.startPos,
                                    existingPrepareToken: preResolve.matchingToken(
                                        for: target.itemId,
                                        startPosition: target.startPos
                                    ),
                                    backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
                                    logoUrl: detail.logoUrl
                                )
                            },
                            onDeleteTitle: {
                                pendingDeleteTarget = TvDeleteRequestTarget(
                                    kind: detail.mediaType,
                                    itemId: detail.itemId,
                                    tmdbId: detail.ids.tmdb,
                                    tvdbId: detail.ids.tvdb,
                                    title: detail.title,
                                    subtitle: detail.year.map(String.init),
                                    scope: detail.mediaType == "series" ? .series : .title
                                )
                            }
                        )

                        if detail.mediaType == "series", let seasons = detail.seasons, !seasons.isEmpty {
                            seasonsAndEpisodesSection(detail: detail, seasons: seasons, client: client)
                        }
                    } else if isLoading {
                        HStack(spacing: 16) {
                            ProgressView()
                            Text("Henter detaljer for \(initialTitle)…")
                                .font(.title3)
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.top, 180)
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(errorMessage)
                                .foregroundStyle(LunaTheme.amber)
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                Task { await runSerializedDetailLoad(preserveSeason: false) }
                            }
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.top, 180)
                    }
                }
                .padding(.bottom, detail?.mediaType == "series" ? 84 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.zero, for: .scrollContent)
            .ignoresSafeArea(edges: [.top, .horizontal])

            if let mutationErrorBanner {
                TransientErrorBanner(message: mutationErrorBanner)
                    .padding(.horizontal, detailGutter)
                    .padding(.top, 72)
            }
        }
        .lunaNavigationContainerBackdrop(mode: .probeOnly)
        .focusScope(detailFocusNamespace)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $pendingDeleteTarget) { target in
            DetailDeleteSheetView(
                target: target,
                onPrepareBeforePreflight: {
                    preResolve.discardPreparedSession(client: sessionStore.makeClient())
                },
                onDeleted: { _ in
                    pendingDeleteTarget = nil
                    if target.isWholeTitle {
                        dismiss()
                    } else {
                        Task { await markLocalMutationAndReload() }
                    }
                },
                onCancel: {
                    pendingDeleteTarget = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .sheet(item: $sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked, reusedToken in
                    let target = ctx
                    if reusedToken != nil {
                        _ = preResolve.consumeForPlayback(
                            itemId: target.itemId,
                            startPosition: target.startPositionSeconds,
                            client: sessionStore.makeClient()
                        )
                    } else {
                        preResolve.discardPreparedSession(client: sessionStore.makeClient())
                    }
                    sourcePickerContext = nil
                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                        itemId: target.itemId,
                        title: target.title,
                        seriesTitle: target.seriesTitle,
                        season: target.season,
                        episode: target.episode,
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
            .environmentObject(sessionStore.comfort)
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
        .onAppear {
            subpageVisibility.enterSubpage(subpageToken)
        }
        .onChange(of: sourcePickerContext != nil || pendingSeriesWatchedItem != nil || pendingDeleteTarget != nil) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
                subpageVisibility.enterSubpage(subpageToken)
            }
        }
        .task(id: scopeKey) {
            let currentScope = scopeKey
            let action = DetailReloadPolicy.actionForTaskAppearance(
                hasLoadedDetail: detail != nil,
                loadedScopeKey: loadedScopeKey,
                currentScopeKey: currentScope,
                lastSeenRefreshNonce: lastSeenRefreshNonce,
                currentRefreshNonce: sessionStore.homeRefreshNonce,
                awaitingPostPlaybackRefresh: awaitingPostPlaybackRefresh
            )
            switch action {
            case .skip:
                return
            case .loadInitial:
                awaitingPostPlaybackRefresh = false
                postPlaybackReloadFallbackTask?.cancel()
                postPlaybackReloadFallbackTask = nil
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce
                await runSerializedDetailLoad(preserveSeason: false, expectedScope: currentScope)
            case .reloadPreservingSeason:
                awaitingPostPlaybackRefresh = false
                postPlaybackReloadFallbackTask?.cancel()
                postPlaybackReloadFallbackTask = nil
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce
                await runSerializedDetailLoad(preserveSeason: true, expectedScope: currentScope)
            }
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard newNonce != lastSeenRefreshNonce else { return }
            awaitingPostPlaybackRefresh = false
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            lastSeenRefreshNonce = newNonce
            launchSerializedDetailLoad(preserveSeason: true)
        }
        .onChange(of: sessionStore.activePlaybackTarget) { oldTarget, newTarget in
            if newTarget != nil {
                awaitingPostPlaybackRefresh = false
                postPlaybackReloadFallbackTask?.cancel()
                postPlaybackReloadFallbackTask = nil
                detailLoadTask?.cancel()
                detailLoadTask = nil
            } else if oldTarget != nil {
                // Wait for PlayerViewModel.teardownAndStop()'s stopped heartbeat and notifyContentMutated()
                // so loadDetail(preserveSeason: true) pre-resolves with the fresh resume position & nextUp.
                awaitingPostPlaybackRefresh = true
                postPlaybackReloadFallbackTask?.cancel()
                postPlaybackReloadFallbackTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    guard !Task.isCancelled, sessionStore.activePlaybackTarget == nil else { return }
                    awaitingPostPlaybackRefresh = false
                    await runSerializedDetailLoad(preserveSeason: true)
                }
            }
        }
        .onDisappear {
            bannerClearTask?.cancel()
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            detailLoadTask?.cancel()
            detailLoadTask = nil
            let isLaunchingPlayback = sessionStore.activePlaybackTarget != nil
            let isShowingModal = sourcePickerContext != nil || pendingSeriesWatchedItem != nil || pendingDeleteTarget != nil
            preResolve.handleDisappear(
                isLaunchingPlayback: isLaunchingPlayback,
                isShowingSourcePicker: isShowingModal,
                client: sessionStore.makeClient()
            )
            PlayerAudioSessionCoordinator.shared.handleDetailDisappear(
                isLaunchingPlayback: isLaunchingPlayback,
                isShowingSourcePicker: isShowingModal,
                keepDisplayModeInMenu: sessionStore.comfort.keepDisplayModeInMenuAfterPlayback
            )
            if !isShowingModal {
                subpageVisibility.leaveModal(modalToken)
            }
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                hasPushedChildDestination: false,
                hasActivePlayback: isLaunchingPlayback,
                isShowingModalSheet: isShowingModal
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    // MARK: - Seasons & 16:9 Episodes

    private func seasonsAndEpisodesSection(
        detail: TvItemDetail,
        seasons: [TvSeasonSummary],
        client: LunaCoreClient?
    ) -> some View {
        DetailSeasonsSectionView(
            detail: detail,
            seasons: seasons,
            selectedSeasonNumber: $selectedSeasonNumber,
            episodes: episodes,
            isLoadingEpisodes: isLoadingEpisodes,
            client: client,
            detailGutter: detailGutter,
            onSelectSeason: { seasonNumber in
                Task { await loadSeasonEpisodes(detail: detail, seasonNumber: seasonNumber) }
            },
            onPlayEpisode: { ep in
                guard ep.isUpcoming != true else { return }
                let usePrep = preResolve.consumeForPlayback(
                    itemId: ep.itemId,
                    startPosition: ep.progress?.positionSeconds,
                    client: sessionStore.makeClient()
                )
                let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                    ep.title,
                    seriesTitle: detail.title,
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber,
                    episodeCode: ep.seasonEpisodeCode
                ) ?? ""
                sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                    itemId: ep.itemId,
                    title: cleanEpisodeTitle,
                    seriesTitle: detail.title,
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber,
                    startPositionSeconds: ep.progress?.positionSeconds,
                    prepareToken: usePrep,
                    backdropUrl: ep.stillUrl ?? detail.backdropUrl,
                    logoUrl: detail.logoUrl
                )
            },
            onPickEpisodeSource: { ep in
                guard ep.isUpcoming != true else { return }
                let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                    ep.title,
                    seriesTitle: detail.title,
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber,
                    episodeCode: ep.seasonEpisodeCode
                ) ?? ""
                sourcePickerContext = SourcePickerContext(
                    itemId: ep.itemId,
                    title: cleanEpisodeTitle,
                    seriesTitle: detail.title,
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber,
                    startPositionSeconds: ep.progress?.positionSeconds,
                    existingPrepareToken: preResolve.matchingToken(
                        for: ep.itemId,
                        startPosition: ep.progress?.positionSeconds
                    ),
                    backdropUrl: ep.stillUrl ?? detail.backdropUrl,
                    logoUrl: detail.logoUrl
                )
            },
            onToggleEpisodeWatched: { ep in
                Task { await toggleEpisodeWatched(detail: detail, episode: ep) }
            },
            onDeleteSeason: { seasonNum in
                pendingDeleteTarget = TvDeleteRequestTarget(
                    kind: "series",
                    itemId: detail.itemId,
                    tmdbId: detail.ids.tmdb,
                    tvdbId: detail.ids.tvdb,
                    title: detail.title,
                    subtitle: "Sesong \(seasonNum)",
                    scope: .season,
                    season: seasonNum
                )
            },
            onDeleteEpisode: { ep in
                pendingDeleteTarget = TvDeleteRequestTarget(
                    kind: "series",
                    itemId: ep.itemId,
                    tmdbId: detail.ids.tmdb,
                    tvdbId: detail.ids.tvdb,
                    title: detail.title,
                    subtitle: "\(ep.seasonEpisodeCode) · \(ep.nonGenericTitle ?? ep.title)",
                    scope: .episode,
                    season: ep.seasonNumber,
                    episode: ep.episodeNumber
                )
            }
        )
    }

    // MARK: - Playback Target & Silent 450ms Pre-Resolve

    private func primaryPlayLabel(_ item: TvItemDetail) -> String {
        let inProgress = (item.progress?.positionSeconds ?? 0) > 30 && (item.progress?.percent ?? 0) < 90
        if item.mediaType == "series" {
            if let next = item.nextUp {
                if inProgress,
                   item.progress?.season == next.season,
                   item.progress?.episode == next.episode {
                    return String(format: "Fortsett S%02dE%02d", next.season, next.episode)
                }
                return String(format: "Spill S%02dE%02d", next.season, next.episode)
            }
            return item.watched ? "Spill på nytt S01E01" : "Spill S01E01"
        }
        if inProgress {
            return "Fortsett"
        }
        return "Spill av"
    }

    private func primaryTargetInfo(_ item: TvItemDetail) -> (
        itemId: String,
        title: String,
        seriesTitle: String?,
        season: Int?,
        episode: Int?,
        startPos: Double?
    ) {
        let itemProgPos: Double? = (item.progress?.percent ?? 0) < 90 ? item.progress?.positionSeconds : 0
        if item.mediaType == "series" {
            let rewatchFromStart = item.nextUp == nil && item.watched
            let s = rewatchFromStart ? 1 : (item.nextUp?.season ?? selectedSeasonNumber)
            let playable = episodes.filter { $0.isUpcoming != true }
            let e = rewatchFromStart ? 1 : (item.nextUp?.episode ?? playable.first?.episodeNumber ?? 1)
            let epId: String
            if let tmdb = item.ids.tmdb {
                epId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
            } else {
                epId = item.itemId
            }
            let matchingEp = episodes.first { $0.seasonNumber == s && $0.episodeNumber == e }
            let startPos: Double?
            if rewatchFromStart {
                startPos = 0
            } else if let epProg = matchingEp?.progress {
                startPos = epProg.percent < 90 ? epProg.positionSeconds : 0
            } else if let itemProg = item.progress,
                      itemProg.season == s,
                      itemProg.episode == e,
                      itemProg.percent < 90 {
                startPos = itemProg.positionSeconds
            } else {
                startPos = 0
            }
            let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                matchingEp?.title,
                seriesTitle: item.title,
                season: s,
                episode: e,
                episodeCode: matchingEp?.seasonEpisodeCode
            )
            return (epId, cleanEpisodeTitle ?? "", item.title, s, e, startPos)
        }
        return (item.itemId, item.title, nil, nil, nil, itemProgPos)
    }

    private func launchPrimaryPlayback(_ item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        let matchingToken = preResolve.consumeForPlayback(
            itemId: target.itemId,
            startPosition: target.startPos,
            client: sessionStore.makeClient()
        )
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
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

    private func launchSerializedDetailLoad(preserveSeason: Bool, expectedScope: String? = nil) {
        detailLoadTask?.cancel()
        detailLoadGeneration &+= 1
        let generation = detailLoadGeneration
        let targetScope = expectedScope ?? scopeKey
        detailLoadTask = Task { @MainActor in
            await loadDetail(preserveSeason: preserveSeason, generation: generation, expectedScope: targetScope)
        }
    }

    private func runSerializedDetailLoad(preserveSeason: Bool, expectedScope: String? = nil) async {
        launchSerializedDetailLoad(preserveSeason: preserveSeason, expectedScope: expectedScope)
        await detailLoadTask?.value
    }

    private func loadDetail(preserveSeason: Bool = false, generation: UInt64, expectedScope: String) async {
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
            guard !Task.isCancelled, generation == detailLoadGeneration, scopeKey == expectedScope else { return }
            loadedScopeKey = expectedScope
            detail = loaded

            if loaded.mediaType == "movie",
               !Task.isCancelled,
               generation == detailLoadGeneration,
               sessionStore.activePlaybackTarget == nil {
                schedulePreResolve(for: loaded)
            }

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
                guard !Task.isCancelled,
                      generation == detailLoadGeneration,
                      scopeKey == expectedScope,
                      sessionStore.activePlaybackTarget == nil else {
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
            sessionStore.unpairDevice()
        } catch {
            guard generation == detailLoadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == detailLoadGeneration {
            isLoading = false
        }
    }

    private func loadSeasonEpisodes(detail: TvItemDetail, seasonNumber: Int) async {
        guard let client = sessionStore.makeClient(),
              let tmdbId = detail.ids.tmdb else { return }
        isLoadingEpisodes = true
        if let seasonRes = try? await client.fetchSeasonEpisodes(tmdbId: tmdbId, seasonNumber: seasonNumber),
           !Task.isCancelled {
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
        await runSerializedDetailLoad(preserveSeason: true)
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

    private func toggleMonitor(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
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
