import Foundation
import Observation
import Synchronization

@MainActor
protocol MediaDetailSessionContext: AnyObject {
    var roomName: String { get }
    var hardwareProfile: String { get }
    var homeRefreshNonce: Int { get }
    var activePlaybackTarget: PlaybackLaunchRequest? { get set }
    var keepDisplayModeInMenuAfterPlayback: Bool { get }
    var lastPlaybackStopReceipt: PlaybackStopReceipt? { get }
    var detailStreamPrewarmer: any DetailStreamPrewarming { get }
    func makeClient() -> LunaCoreClient?
    func notifyContentMutated()
    func unpairDevice()
    func awaitPlaybackStopReceipt(for itemId: String, timeout: Duration) async -> PlaybackStopReceipt?
    func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration,
        recordedAfter: Date?,
        excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt?
    func handleDetailDisappear(isLaunchingPlayback: Bool, isShowingSourcePicker: Bool)
}

extension MediaDetailSessionContext {
    var lastPlaybackStopReceipt: PlaybackStopReceipt? { nil }
    var detailStreamPrewarmer: any DetailStreamPrewarming { NoopDetailStreamPrewarmer() }
    func awaitPlaybackStopReceipt(for itemId: String, timeout: Duration) async -> PlaybackStopReceipt? {
        nil
    }
    func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration,
        recordedAfter: Date?,
        excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt? {
        await awaitPlaybackStopReceipt(for: itemId, timeout: timeout)
    }
    func handleDetailDisappear(isLaunchingPlayback: Bool, isShowingSourcePicker: Bool) {}
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
    @ObservationIgnored var stopReceiptTimeout: Duration = .seconds(3)
    @ObservationIgnored var lastPlaybackLaunchAt: Date?
    @ObservationIgnored var preLaunchStopReceipt: PlaybackStopReceipt?

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
        self.preResolve.configure(prewarmer: sessionContext.detailStreamPrewarmer)
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
            lastPlaybackLaunchAt = Date()
            preLaunchStopReceipt = sessionContext?.lastPlaybackStopReceipt
            postPlaybackReloadFallbackTask?.cancel()
            postPlaybackReloadFallbackTask = nil
            episodePreResolveTask?.cancel()
            episodePreResolveTask = nil
            detailLoadTask?.cancel()
            detailLoadTask = nil
        } else if let oldTarget {
            // Await the player's `PlaybackStopReceipt` directly (`0 ms` when already emitted)
            // across both the launched itemId (e.g. episode) and the detail itemId (e.g. series),
            // then invalidate detail cache and refresh `nextUp` + resume position immediately.
            postPlaybackReloadFallbackTask?.cancel()
            let lookupIDs = oldTarget.itemId == itemId ? [itemId] : [oldTarget.itemId, itemId]
            let timeout = stopReceiptTimeout
            postPlaybackReloadFallbackTask = Task { @MainActor [weak self] in
                guard let self else { return }
                if self.sessionContext != nil {
                    _ = await self.awaitAnyStopReceipt(
                        lookupIDs: lookupIDs,
                        timeout: timeout
                    )
                }
                guard !Task.isCancelled,
                      self.sessionContext?.activePlaybackTarget == nil else {
                    return
                }
                if let sessionContext = self.sessionContext {
                    self.lastSeenRefreshNonce = sessionContext.homeRefreshNonce
                }
                ItemDetailMemoryCache.invalidate(itemId: self.itemId, tmdbId: self.detail?.ids.tmdb)
                await self.runSerializedDetailLoad(preserveSeason: true, bypassCache: true)
            }
        }
    }

    private func awaitAnyStopReceipt(
        lookupIDs: [String],
        timeout: Duration
    ) async -> PlaybackStopReceipt? {
        guard let sessionContext else { return nil }
        let minRecordedAt = lastPlaybackLaunchAt?.addingTimeInterval(-0.05)
        let staleReceipt = preLaunchStopReceipt
        if let immediate = sessionContext.lastPlaybackStopReceipt,
           lookupIDs.contains(immediate.itemId),
           immediate != staleReceipt,
           immediate.recordedAt >= (minRecordedAt ?? .distantPast),
           Date().timeIntervalSince(immediate.recordedAt) <= 5.0 {
            return immediate
        }
        if lookupIDs.count <= 1, let singleID = lookupIDs.first {
            return await sessionContext.awaitPlaybackStopReceipt(
                for: singleID,
                timeout: timeout,
                recordedAfter: minRecordedAt,
                excluding: staleReceipt
            )
        }
        let taskBox = Mutex<[Task<Void, Never>]>([])
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PlaybackStopReceipt?, Never>) in
                final class RaceBox {
                    var resumed = false
                    var remaining: Int
                    init(remaining: Int) { self.remaining = remaining }
                }
                let race = RaceBox(remaining: lookupIDs.count)
                let spawned = lookupIDs.map { id in
                    Task { @MainActor [weak self] in
                        let receipt = await self?.sessionContext?.awaitPlaybackStopReceipt(
                            for: id,
                            timeout: timeout,
                            recordedAfter: minRecordedAt,
                            excluding: staleReceipt
                        )
                        guard !race.resumed else { return }
                        if let receipt {
                            race.resumed = true
                            let toCancel = taskBox.withLock { $0 }
                            toCancel.forEach { $0.cancel() }
                            continuation.resume(returning: receipt)
                        } else {
                            race.remaining -= 1
                            if race.remaining <= 0 {
                                race.resumed = true
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
                taskBox.withLock { $0 = spawned }
                if Task.isCancelled && !race.resumed {
                    race.resumed = true
                    spawned.forEach { $0.cancel() }
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            let toCancel = taskBox.withLock { $0 }
            toCancel.forEach { $0.cancel() }
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
        self.sessionContext?.handleDetailDisappear(
            isLaunchingPlayback: isLaunchingPlayback,
            isShowingSourcePicker: showingModal
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
}
