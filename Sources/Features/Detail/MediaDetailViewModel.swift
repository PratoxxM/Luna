import Combine
import Foundation

@MainActor
protocol MediaDetailSessionContext: AnyObject {
    var roomName: String { get }
    var effectiveHardwareProfile: String { get }
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

    func makeClient() -> LunaCoreClient? {
        makeClient(overrideBaseURL: nil)
    }
}

@MainActor
final class MediaDetailViewModel: ObservableObject {
    let mediaType: String
    let itemId: String
    let initialTitle: String

    @Published private(set) var client: LunaCoreClient?
    @Published var detail: TvItemDetail?
    @Published var selectedSeasonNumber: Int = 1
    @Published var episodes: [TvEpisodeCard] = []
    @Published var isLoading: Bool = true
    @Published var isLoadingEpisodes: Bool = false
    @Published var errorMessage: String?
    @Published var mutationErrorBanner: String?
    @Published var pendingSeriesWatchedItem: TvItemDetail?
    @Published var pendingDeleteTarget: TvDeleteRequestTarget?
    @Published var sourcePickerContext: SourcePickerContext?
    @Published private(set) var isPreResolvedReady: Bool = false

    let preResolve: DetailPreResolveController

    weak var sessionContext: (any MediaDetailSessionContext)?
    var lastSeenRefreshNonce: Int = -1
    var bannerClearTask: Task<Void, Never>?
    var postPlaybackReloadFallbackTask: Task<Void, Never>?
    var detailLoadTask: Task<Void, Never>?
    var detailLoadGeneration: UInt64 = 0
    var seasonLoadGeneration: UInt64 = 0
    var loadedScopeKey: String?
    var awaitingPostPlaybackRefresh: Bool = false
    private var preResolveCancellable: AnyCancellable?

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
        self.preResolveCancellable = preResolve.$isPreResolvedReady
            .sink { [weak self] ready in
                self?.isPreResolvedReady = ready
            }
    }

    var isShowingModal: Bool {
        sourcePickerContext != nil || pendingSeriesWatchedItem != nil || pendingDeleteTarget != nil
    }

    var hasLocalEpisodes: Bool {
        episodes.contains {
            $0.availability?.isPhysicalLocal == true || $0.availability?.isLocalVfs == true
        }
    }

    var currentScopeKey: String {
        let room = sessionContext?.roomName ?? ""
        let profile = sessionContext?.effectiveHardwareProfile ?? ""
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
            currentRefreshNonce: sessionContext.homeRefreshNonce,
            awaitingPostPlaybackRefresh: awaitingPostPlaybackRefresh
        )
        switch action {
        case .skip:
            return
        case .loadInitial:
            awaitingPostPlaybackRefresh = false
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce
            await runSerializedDetailLoad(preserveSeason: false, expectedScope: scopeKey)
        case .reloadPreservingSeason:
            awaitingPostPlaybackRefresh = false
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            lastSeenRefreshNonce = sessionContext.homeRefreshNonce
            await runSerializedDetailLoad(preserveSeason: true, expectedScope: scopeKey)
        }
    }

    func handleHomeRefreshNonceChange(_ newNonce: Int) {
        guard newNonce != lastSeenRefreshNonce else { return }
        awaitingPostPlaybackRefresh = false
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
            postPlaybackReloadFallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.sessionContext?.activePlaybackTarget == nil else {
                    return
                }
                self.awaitingPostPlaybackRefresh = false
                await self.runSerializedDetailLoad(preserveSeason: true)
            }
        }
    }

    func handleDisappear(sessionContext: (any MediaDetailSessionContext)? = nil) {
        if let sessionContext {
            self.sessionContext = sessionContext
        }
        bannerClearTask?.cancel()
        postPlaybackReloadFallbackTask?.cancel()
        postPlaybackReloadFallbackTask = nil
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
        selectedSeasonNumber = seasonNumber
        guard let detail else { return }
        await loadSeasonEpisodes(detail: detail, seasonNumber: seasonNumber)
    }

    // MARK: - Playback, Source Picker & Delete Intents

    func launchPrimaryPlayback() {
        guard let detail else { return }
        let target = primaryTargetInfo(detail)
        let matchingToken = preResolve.consumeForPlayback(
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
            prepareToken: matchingToken,
            backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func playEpisode(_ ep: TvEpisodeCard) {
        guard let detail, ep.isUpcoming != true else { return }
        let usePrep = preResolve.consumeForPlayback(
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
            prepareToken: usePrep,
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
        context target: SourcePickerContext
    ) {
        let currentClient = refreshedClient()
        if reusedToken != nil {
            _ = preResolve.consumeForPlayback(
                itemId: target.itemId,
                startPosition: target.startPositionSeconds,
                client: currentClient
            )
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
        if target.isWholeTitle {
            return true
        }
        await markLocalMutationAndReload()
        return false
    }

    // MARK: - Formatting Helpers

    func primaryPlayLabel(_ item: TvItemDetail) -> String {
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

    func watchedButtonTitle(_ item: TvItemDetail) -> String {
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            return String(format: "Sett S%02dE%02d", next.season, next.episode)
        }
        return "Sett"
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
