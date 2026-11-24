import Foundation
import Observation

@MainActor
protocol MediaDetailSessionContext: AnyObject {
    var roomName: String { get }
    var hardwareProfile: String { get }
    var homeRefreshNonce: Int { get }
    var activePlaybackTarget: PlaybackLaunchRequest? { get set }
    var keepDisplayModeInMenuAfterPlayback: Bool { get }
    func makeClient() -> LunaCoreClient?
    func notifyContentMutated()
    func unpairDevice()
}

extension AppSessionStore: MediaDetailSessionContext {
    var keepDisplayModeInMenuAfterPlayback: Bool {
        comfort.keepDisplayModeInMenuAfterPlayback
    }
}

@MainActor
@Observable
final class MediaDetailViewModel {
    let mediaType: String
    let itemId: String
    let initialTitle: String

    private(set) var client: LunaCoreClient?
    var detail: TvItemDetail?
    var selectedSeasonNumber: Int = 1
    var episodes: [TvEpisodeCard] = []
    var isLoading: Bool = true
    var isLoadingEpisodes: Bool = false
    var errorMessage: String?
    var mutationErrorBanner: String?
    var pendingSeriesWatchedItem: TvItemDetail?
    var pendingDeleteTarget: TvDeleteRequestTarget?
    var sourcePickerContext: SourcePickerContext?
    var showMoreSheet: Bool = false
    var showFullOverviewSheet: Bool = false

    let preResolve: DetailPreResolveController

    @ObservationIgnored weak var sessionContext: (any MediaDetailSessionContext)?
    @ObservationIgnored var lastSeenRefreshNonce: Int = -1
    @ObservationIgnored var postPlaybackReloadFallbackTask: Task<Void, Never>?
    @ObservationIgnored var episodePreResolveTask: Task<Void, Never>?
    @ObservationIgnored var detailLoadTask: Task<Void, Never>?
    @ObservationIgnored var detailLoadGeneration: UInt64 = 0
    @ObservationIgnored var seasonLoadGeneration: UInt64 = 0
    @ObservationIgnored var loadedScopeKey: String?

    nonisolated static let episodeFocusPreResolveDebounceNs: UInt64 = 340_000_000

    init(
        mediaType: String,
        itemId: String,
        initialTitle: String,
        preResolve: DetailPreResolveController = DetailPreResolveController()
    ) {
        self.mediaType = mediaType
        self.itemId = itemId
        self.initialTitle = initialTitle
        self.preResolve = preResolve
    }

    var isShowingModal: Bool {
        sourcePickerContext != nil
            || pendingSeriesWatchedItem != nil
            || pendingDeleteTarget != nil
            || showMoreSheet
            || showFullOverviewSheet
    }

    var hasLocalEpisodes: Bool {
        episodes.contains {
            $0.availability?.isPhysicalLocal == true || $0.availability?.isLocalVfs == true
        }
    }

    var currentScopeKey: String {
        let room = sessionContext?.roomName ?? ""
        let profile = sessionContext?.hardwareProfile ?? ""
        return "\(mediaType)#\(itemId)#\(room)#\(profile)"
    }

    // MARK: - Lifecycle & Orchestration

    func bind(sessionContext: any MediaDetailSessionContext) {
        self.sessionContext = sessionContext
        self.client = sessionContext.makeClient()
    }

    func setClient(_ next: LunaCoreClient?) {
        self.client = next
    }

    func handleTaskAppearance(
        scopeKey: String,
        sessionContext: any MediaDetailSessionContext
    ) async {
        bind(sessionContext: sessionContext)
        let action = DetailReloadPolicy.actionForTaskAppearance(
            hasLoadedDetail: detail != nil,
            loadedScopeKey: loadedScopeKey,
            currentScopeKey: scopeKey,
            lastSeenRefreshNonce: lastSeenRefreshNonce,
            currentRefreshNonce: sessionContext.homeRefreshNonce
        )
        switch action {
        case .skip:
            return
        case .loadInitial:
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce
            await runSerializedDetailLoad(preserveSeason: false, expectedScope: scopeKey)
        case .reloadPreservingSeason:
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce
            await runSerializedDetailLoad(preserveSeason: true, expectedScope: scopeKey)
        }
    }

    func handleHomeRefreshNonceChange(_ newNonce: Int) {
        guard newNonce != lastSeenRefreshNonce else { return }
        postPlaybackReloadFallbackTask?.cancel()
        postPlaybackReloadFallbackTask = nil
        lastSeenRefreshNonce = newNonce
        launchSerializedDetailLoad(preserveSeason: true)
    }

    func handlePlaybackTargetChange(
        oldTarget: PlaybackLaunchRequest?,
        newTarget: PlaybackLaunchRequest?
    ) {
        if newTarget != nil {
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            episodePreResolveTask?.cancel()
            episodePreResolveTask = nil
            detailLoadTask?.cancel()
            detailLoadTask = nil
        } else if oldTarget != nil {
            // Wait for PlayerViewModel.teardownAndStop()'s stopped heartbeat and notifyContentMutated()
            // so loadDetail(preserveSeason: true) pre-resolves with the fresh resume position & nextUp.
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.sessionContext?.activePlaybackTarget == nil else {
                    return
                }
                await self.runSerializedDetailLoad(preserveSeason: true)
            }
        }
    }

    func handleDisappear(sessionContext: (any MediaDetailSessionContext)? = nil) {
        if let sessionContext {
            self.sessionContext = sessionContext
        }
        postPlaybackReloadFallbackTask?.cancel()
        postPlaybackReloadFallbackTask = nil
        episodePreResolveTask?.cancel()
        episodePreResolveTask = nil
        detailLoadTask?.cancel()
        detailLoadTask = nil
        seasonLoadGeneration &+= 1

        let isLaunchingPlayback = self.sessionContext?.activePlaybackTarget != nil
        let showingModal = isShowingModal
        let currentClient = refreshedClient()
        preResolve.handleDisappear(
            isLaunchingPlayback: isLaunchingPlayback,
            isShowingSourcePicker: showingModal,
            client: currentClient
        )
        PlayerAudioSessionCoordinator.shared.handleDetailDisappear(
            isLaunchingPlayback: isLaunchingPlayback,
            isShowingSourcePicker: showingModal,
            keepDisplayModeInMenu: self.sessionContext?.keepDisplayModeInMenuAfterPlayback ?? false
        )
    }

    func reloadFromError() async {
        await runSerializedDetailLoad(preserveSeason: false)
    }

    func selectSeason(_ seasonNumber: Int) async {
        episodePreResolveTask?.cancel()
        episodePreResolveTask = nil
        let previousSeason = selectedSeasonNumber
        selectedSeasonNumber = seasonNumber
        guard let detail else { return }
        let loadedOk = await loadSeasonEpisodes(detail: detail, seasonNumber: seasonNumber, previousSeason: previousSeason)
        if loadedOk, sessionContext?.activePlaybackTarget == nil {
            schedulePreResolve(for: detail, immediate: false)
        }
    }

    func handleEpisodeFocusChanged(_ ep: TvEpisodeCard) {
        episodePreResolveTask?.cancel()
        episodePreResolveTask = nil
        guard ep.isUpcoming != true else { return }
        episodePreResolveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.episodeFocusPreResolveDebounceNs)
            guard !Task.isCancelled,
                  let self,
                  self.sessionContext?.activePlaybackTarget == nil,
                  !self.isShowingModal,
                  let detail = self.detail else {
                return
            }
            let cleanTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                ep.title,
                seriesTitle: detail.title,
                season: ep.seasonNumber,
                episode: ep.episodeNumber,
                episodeCode: ep.seasonEpisodeCode
            ) ?? ""
            let startPos: Double? = {
                guard let prog = ep.progress else { return 0 }
                return prog.percent < 90 ? prog.positionSeconds : 0
            }()
            self.preResolve.schedule(
                targetItemId: ep.itemId,
                title: cleanTitle,
                seriesTitle: detail.title,
                startPos: startPos,
                immediate: true,
                client: self.refreshedClient()
            )
            self.episodePreResolveTask = nil
        }
    }

    nonisolated static func resolveRestoredEpisodeFocusID(
        lastFocusedEpisodeID: String?,
        episodes: [TvEpisodeCard],
        nextUp: TvNextUpPointer?
    ) -> String? {
        let resolvedNextID: String? = {
            if let next = nextUp,
               let match = episodes.first(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }) {
                return match.id
            }
            return episodes.first(where: { !$0.watched && $0.isUpcoming != true })?.id
        }()

        if let lastID = lastFocusedEpisodeID,
           let current = episodes.first(where: { $0.id == lastID }) {
            if current.watched, let nextID = resolvedNextID {
                return nextID
            }
            return current.id
        }
        return resolvedNextID
    }

    // MARK: - Playback, Source Picker & Delete Intents

    func launchPrimaryPlayback() {
        guard let detail else { return }
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail.ids.tmdb)
        let target = primaryTargetInfo(detail)
        let handoff = preResolve.consumeHandoffForPlayback(
            itemId: target.itemId,
            startPosition: target.startPos,
            client: refreshedClient()
        )
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
            startPositionSeconds: target.startPos,
            prepareToken: handoff.prepareToken,
            preparedSession: handoff.preparedSession,
            inflightPrepareTask: handoff.inflightPrepareTask,
            inflightPrepareToken: handoff.inflightPrepareToken,
            backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func playEpisode(_ ep: TvEpisodeCard) {
        guard let detail, ep.isUpcoming != true else { return }
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail.ids.tmdb)
        let handoff = preResolve.consumeHandoffForPlayback(
            itemId: ep.itemId,
            startPosition: ep.progress?.positionSeconds,
            client: refreshedClient()
        )
        let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            ep.title,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            episodeCode: ep.seasonEpisodeCode
        ) ?? ""
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: ep.itemId,
            title: cleanEpisodeTitle,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            startPositionSeconds: ep.progress?.positionSeconds,
            prepareToken: handoff.prepareToken,
            preparedSession: handoff.preparedSession,
            inflightPrepareTask: handoff.inflightPrepareTask,
            inflightPrepareToken: handoff.inflightPrepareToken,
            backdropUrl: ep.stillUrl ?? detail.backdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func openPrimarySourcePicker() {
        guard let detail else { return }
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
    }

    func openEpisodeSourcePicker(_ ep: TvEpisodeCard) {
        guard let detail, ep.isUpcoming != true else { return }
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
    }

    func launchSelectedSource(
        _ picked: TvCandidateInfo,
        reusedToken: String?,
        createdPreparedSession: TvPlaybackSession? = nil,
        context target: SourcePickerContext
    ) {
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail?.ids.tmdb)
        let currentClient = refreshedClient()
        var handedOverSession: TvPlaybackSession? = nil
        var handedOverInflight: Task<TvPrepareResponse?, Never>? = nil
        var handedOverInflightToken: String? = nil
        if reusedToken != nil {
            if let createdPreparedSession {
                preResolve.discardPreparedSession(client: currentClient)
                handedOverSession = createdPreparedSession
            } else {
                let handoff = preResolve.consumeHandoffForPlayback(
                    itemId: target.itemId,
                    startPosition: target.startPositionSeconds,
                    client: currentClient
                )
                handedOverSession = handoff.preparedSession
                handedOverInflight = handoff.inflightPrepareTask
                handedOverInflightToken = handoff.inflightPrepareToken
            }
        } else {
            preResolve.discardPreparedSession(client: currentClient)
        }
        sourcePickerContext = nil
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
            startPositionSeconds: target.startPositionSeconds,
            candidateId: reusedToken == nil ? picked.candidateId : nil,
            prepareToken: reusedToken,
            preparedSession: handedOverSession,
            inflightPrepareTask: handedOverInflight,
            inflightPrepareToken: handedOverInflightToken,
            backdropUrl: target.backdropUrl ?? detail?.backdropUrl,
            logoUrl: target.logoUrl ?? detail?.logoUrl
        )
    }

    func prepareForDeletePreflight() {
        preResolve.discardPreparedSession(client: refreshedClient())
    }

    func requestDeleteTitle() {
        guard let detail else { return }
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

    func requestDeleteSeason(_ seasonNum: Int) {
        guard let detail else { return }
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
    }

    func requestDeleteEpisode(_ ep: TvEpisodeCard) {
        guard let detail else { return }
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

    func handleDeleted(target: TvDeleteRequestTarget) async -> Bool {
        pendingDeleteTarget = nil
        ItemDetailMemoryCache.invalidate(itemId: target.itemId, tmdbId: target.tmdbId ?? detail?.ids.tmdb)
        if target.isWholeTitle {
            detailLoadTask?.cancel()
            detailLoadTask = nil
            if let sessionContext {
                lastSeenRefreshNonce = sessionContext.homeRefreshNonce &+ 1
                sessionContext.notifyContentMutated()
            }
            return true
        }
        await markLocalMutationAndReload()
        return false
    }

    // MARK: - Formatting Helpers

    func heroPrimaryPlayTitle(_ item: TvItemDetail) -> String {
        let base = primaryPlayLabel(item)
        if base.hasPrefix("Fortsett") {
            let targetProg: TvWatchProgress? = {
                if item.mediaType == "series", let next = item.nextUp,
                   let ep = episodes.first(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }),
                   let epProg = ep.progress, epProg.durationSeconds > epProg.positionSeconds {
                    return epProg
                }
                return item.progress
            }()
            guard let prog = targetProg,
                  prog.positionSeconds > 30,
                  prog.durationSeconds > prog.positionSeconds else {
                return base
            }
            let totalMins = max(1, Int(((prog.durationSeconds - prog.positionSeconds) / 60.0).rounded()))
            let remText = totalMins >= 60 && totalMins % 60 > 0
                ? "\(totalMins / 60) t \(totalMins % 60) min igjen"
                : (totalMins >= 60 ? "\(totalMins / 60) t igjen" : "\(totalMins) min igjen")
            return "\(base) · \(remText)"
        }

        if item.mediaType == "series" {
            let targetSeason = item.nextUp?.season ?? selectedSeasonNumber
            let targetEpisode = item.nextUp?.episode ?? 1
            if let ep = episodes.first(where: { $0.seasonNumber == targetSeason && $0.episodeNumber == targetEpisode }),
               let epRuntime = ep.formattedRuntime, !epRuntime.isEmpty {
                return "\(base) · \(epRuntime)"
            }
        }
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            return "\(base) · \(runtime)"
        }
        return base
    }

    func primaryPlayLabel(_ item: TvItemDetail) -> String {
        let inProgress = (item.progress?.positionSeconds ?? 0) > 30 && (item.progress?.percent ?? 0) < 90
        if item.mediaType == "series" {
            if let next = item.nextUp {
                if inProgress,
                   item.progress?.season == next.season,
                   item.progress?.episode == next.episode {
                    return "Fortsett S\(next.season) E\(next.episode)"
                }
                return "Spill S\(next.season) E\(next.episode)"
            }
            return item.watched ? "Spill på nytt S1 E1" : "Spill S1 E1"
        }
        if inProgress {
            return "Fortsett"
        }
        return "Spill av"
    }

    func primaryTargetInfo(_ item: TvItemDetail) -> (
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
}
