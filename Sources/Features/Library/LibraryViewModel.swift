import Foundation
import Observation

@MainActor
@Observable
public final class LibraryViewModel {
    public var activeSection: LibraryFilterSection = .movies
    public var selectedTier: LibraryTierFilter = .all
    public var selectedSort: LibrarySortOption = .recent
    public var didApplyInitialSectionFallback: Bool = false

    public private(set) var libraryPayload: TvLibraryResponse?
    public private(set) var localItems: [TvMediaCard] = []
    public private(set) var localOffset: Int = 0
    public private(set) var localHasMore: Bool = false
    public private(set) var cachedEtag: String?
    public private(set) var isLoading: Bool = true
    public private(set) var isLoadingMoreLocal: Bool = false
    public private(set) var errorMessage: String?
    public var mutationErrorBanner: String?
    public var lastSeenRefreshNonce: Int = -1
    public private(set) var isUnloadedForMemoryWarning: Bool = false

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var loadedQueryKey: String?
    @ObservationIgnored private let pageSize: Int

    public init(pageSize: Int = DeviceMemoryProfile.current.libraryPageSize) {
        self.pageSize = max(1, pageSize)
    }

    public var customLists: [TvLibraryCustomList] {
        libraryPayload?.resolvedCustomLists ?? []
    }

    public var counts: TvLibraryCounts? {
        libraryPayload?.counts
    }

    public func count(for tier: LibraryTierFilter) -> Int? {
        tier.countValue(from: libraryPayload?.counts)
    }

    public var supportsTierAndSortFilters: Bool {
        activeSection == .movies || activeSection == .series
    }

    private var effectiveTierRawValue: String {
        supportsTierAndSortFilters ? selectedTier.rawValue : "all"
    }

    private var effectiveSortRawValue: String {
        supportsTierAndSortFilters ? selectedSort.rawValue : "recent"
    }

    private var shouldUseDiskSWRStore: Bool {
        effectiveTierRawValue == "all" && effectiveSortRawValue == "recent"
    }

    public var activeMediaCards: [TvMediaCard] {
        switch activeSection {
        case .watchlist:
            return libraryPayload?.watchlist ?? []
        case .movies, .series:
            return localItems
        case .lists:
            return []
        }
    }

    public func queryKey(for session: any TabSessionContext) -> String {
        "\(session.serverBaseURL?.absoluteString ?? "")#\(activeSection.rawValue)#\(activeSection.apiMediaType)#\(effectiveTierRawValue)#\(effectiveSortRawValue)#\(session.roomName)#\(session.hardwareProfile)"
    }

    public func handleActivation(session: any TabSessionContext, isActiveTab: Bool) async {
        guard isActiveTab else { return }
        reloadTask?.cancel()
        reloadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMoreLocal = false
        reloadGeneration &+= 1
        let gen = reloadGeneration
        lastSeenRefreshNonce = session.homeRefreshNonce
        await loadLibrary(forceNetwork: false, session: session, generation: gen)
    }

    public func handleHomeRefreshNonceChange(
        _ newNonce: Int,
        isActiveTab: Bool,
        session: any TabSessionContext
    ) {
        guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
        lastSeenRefreshNonce = newNonce
        scheduleReloadLibrary(forceNetwork: true, session: session)
    }

    public func scheduleReloadLibrary(forceNetwork: Bool, session: any TabSessionContext) {
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMoreLocal = false
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadLibrary(forceNetwork: forceNetwork, session: session, generation: gen)
            if self.reloadGeneration == gen {
                self.reloadTask = nil
            }
        }
    }

    public func scheduleLoadMoreLocalItems(session: any TabSessionContext) {
        guard activeSection == .movies || activeSection == .series,
              !isLoadingMoreLocal,
              localHasMore else {
            return
        }
        loadMoreTask?.cancel()
        loadMoreTask = Task { @MainActor [weak self] in
            await self?.loadMoreLocalItems(session: session)
        }
    }

    public func loadLibrary(
        forceNetwork: Bool = false,
        session: any TabSessionContext,
        generation: UInt64? = nil
    ) async {
        guard let client = session.makeLibraryClient() else { return }
        var targetKey = queryKey(for: session)
        let currentNonce = session.homeRefreshNonce
        let wasUnloaded = isUnloadedForMemoryWarning

        if loadedQueryKey != targetKey {
            loadedQueryKey = targetKey
            libraryPayload = nil
            localItems = []
            localOffset = 0
            localHasMore = false
            cachedEtag = nil
        }

        if let cached = LibraryBrowseMemoryCache.shared.snapshot(for: targetKey) {
            libraryPayload = cached.payload
            localItems = cached.localItems
            localOffset = cached.localOffset
            localHasMore = cached.localHasMore
            cachedEtag = cached.etag
            isLoading = false
            isUnloadedForMemoryWarning = false
            let switchedSection = applyInitialSectionResolutionIfNeeded(counts: cached.payload.counts)
            if switchedSection {
                targetKey = queryKey(for: session)
                loadedQueryKey = targetKey
                libraryPayload = nil
                localItems = []
                localOffset = 0
                localHasMore = false
                cachedEtag = nil
                isLoading = true
            } else if !forceNetwork,
                      !wasUnloaded,
                      TabContentFreshnessPolicy.isCacheFresh(
                          hasCachedContent: true,
                          lastValidatedAt: cached.fetchedAt,
                          cachedRefreshNonce: cached.refreshNonce,
                          currentRefreshNonce: currentNonce,
                          freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
                      ) {
                errorMessage = nil
                return
            }
        } else if shouldUseDiskSWRStore {
            let host = session.serverBaseURL?.host
            let room = session.roomName
            let profile = session.hardwareProfile
            let sectionApi = activeSection.apiSection
            let mediaApi = activeSection.apiMediaType
            let memDisk = DiskSWRStore.libraryMemorySnapshot(
                section: sectionApi,
                mediaType: mediaApi,
                serverHost: host,
                roomName: room,
                hardwareProfile: profile
            )
            let diskSnap: CachedLibrarySnapshot?
            if let memDisk {
                diskSnap = memDisk
            } else {
                diskSnap = await DiskSWRStore.loadLibraryAsync(
                    section: sectionApi,
                    mediaType: mediaApi,
                    serverHost: host,
                    roomName: room,
                    hardwareProfile: profile
                )
            }
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration), queryKey(for: session) == targetKey else {
                if generation == nil || generation == reloadGeneration {
                    isLoading = false
                }
                return
            }
            if let diskSnap {
                libraryPayload = diskSnap.payload
                localItems = diskSnap.payload.localItems
                localOffset = diskSnap.payload.localItems.count
                localHasMore = diskSnap.payload.localHasMore ?? false
                cachedEtag = diskSnap.etag
                isLoading = false
                isUnloadedForMemoryWarning = false
                if applyInitialSectionResolutionIfNeeded(counts: diskSnap.payload.counts) {
                    targetKey = queryKey(for: session)
                    loadedQueryKey = targetKey
                    libraryPayload = nil
                    localItems = []
                    localOffset = 0
                    localHasMore = false
                    cachedEtag = nil
                    isLoading = true
                }
            } else {
                libraryPayload = nil
                localItems = []
                localOffset = 0
                localHasMore = false
                cachedEtag = nil
                isLoading = true
            }
        } else {
            libraryPayload = nil
            localItems = []
            localOffset = 0
            localHasMore = false
            cachedEtag = nil
            isLoading = true
        }
        errorMessage = nil

        do {
            let effectiveIfNoneMatch = (forceNetwork || libraryPayload == nil) ? nil : cachedEtag
            let result = try await client.fetchLibrary(
                section: activeSection.apiSection,
                tier: effectiveTierRawValue,
                mediaType: activeSection.apiMediaType,
                sort: effectiveSortRawValue,
                offset: 0,
                limit: pageSize,
                ifNoneMatch: effectiveIfNoneMatch
            )
            guard !Task.isCancelled,
                  (generation == nil || generation == reloadGeneration),
                  queryKey(for: session) == targetKey else {
                if generation == nil || generation == reloadGeneration {
                    isLoading = false
                }
                return
            }
            switch result {
            case .notModified:
                isUnloadedForMemoryWarning = false
                if let payload = libraryPayload {
                    persistLibrarySnapshot(
                        for: targetKey,
                        payload: payload,
                        fetchedAt: Date(),
                        refreshNonce: session.homeRefreshNonce
                    )
                }
            case .updated(let res, let newEtag, let rawData):
                libraryPayload = res
                localItems = res.localItems
                localOffset = res.localItems.count
                localHasMore = res.localHasMore ?? false
                cachedEtag = newEtag
                isUnloadedForMemoryWarning = false
                persistLibrarySnapshot(
                    for: targetKey,
                    payload: res,
                    fetchedAt: Date(),
                    refreshNonce: session.homeRefreshNonce,
                    preserveExistingEtag: false
                )
                if shouldUseDiskSWRStore {
                    DiskSWRStore.saveLibraryInBackground(
                        rawPayloadData: rawData,
                        etag: newEtag,
                        section: activeSection.apiSection,
                        mediaType: activeSection.apiMediaType,
                        serverHost: session.serverBaseURL?.host,
                        roomName: session.roomName,
                        hardwareProfile: session.hardwareProfile,
                        decodedPayload: res
                    )
                }
                if applyInitialSectionResolutionIfNeeded(counts: res.counts) {
                    loadedQueryKey = nil
                    cachedEtag = nil
                    libraryPayload = nil
                    localItems = []
                    localOffset = 0
                    localHasMore = false
                    isLoading = true
                    return
                }
            }
        } catch where LunaCoreError.isCancellation(error) {
            if generation == nil || generation == reloadGeneration {
                isLoading = false
            }
            return
        } catch LunaCoreError.unauthorized {
            LibraryBrowseMemoryCache.shared.clear()
            session.unpairDevice()
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if libraryPayload == nil {
                errorMessage = LunaCopy.friendlyErrorMessage(error)
            }
        }
        if generation == nil || generation == reloadGeneration {
            isLoading = false
        }
    }

    public func loadMoreLocalItems(session: any TabSessionContext) async {
        guard (activeSection == .movies || activeSection == .series),
              !isLoadingMoreLocal,
              localHasMore,
              let client = session.makeLibraryClient() else {
            return
        }
        let targetKey = queryKey(for: session)
        let gen = reloadGeneration
        isLoadingMoreLocal = true
        defer {
            if gen == reloadGeneration {
                isLoadingMoreLocal = false
            }
        }

        do {
            let result = try await client.fetchLibrary(
                section: "local",
                tier: effectiveTierRawValue,
                mediaType: activeSection.apiMediaType,
                sort: effectiveSortRawValue,
                offset: localOffset,
                limit: pageSize,
                ifNoneMatch: nil
            )
            guard !Task.isCancelled, gen == reloadGeneration, queryKey(for: session) == targetKey else {
                return
            }
            guard case .updated(let res, _, _) = result else {
                return
            }
            let existing = Set(localItems.map(\.id))
            let fresh = res.localItems.filter { !existing.contains($0.id) }
            localItems.append(contentsOf: fresh)
            localOffset += res.localItems.count
            localHasMore = res.localHasMore ?? false
            if let payload = libraryPayload {
                persistLibrarySnapshot(for: targetKey, payload: payload, refreshNonce: session.homeRefreshNonce)
            }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            LibraryBrowseMemoryCache.shared.clear()
            session.unpairDevice()
        } catch {
            guard !Task.isCancelled, gen == reloadGeneration else { return }
            showMutationError(error)
        }
    }

    public func removeOptimisticLocalItem(itemId: String) {
        localItems.removeAll { $0.itemId == itemId }
    }

    public func markLocalMutationAndReload(session: any TabSessionContext) async {
        reloadTask?.cancel()
        reloadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMoreLocal = false
        reloadGeneration &+= 1
        let gen = reloadGeneration
        LibraryBrowseMemoryCache.shared.clear()
        cachedEtag = nil
        lastSeenRefreshNonce = session.homeRefreshNonce &+ 1
        session.notifyContentMutated()
        await loadLibrary(forceNetwork: true, session: session, generation: gen)
    }

    public func toggleWatchlist(_ card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeLibraryClient() else { return }
        let nextListed = !(card.inWatchlist ?? false)
        do {
            try await client.setWatchlist(
                listed: nextListed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            await markLocalMutationAndReload(session: session)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func toggleWatched(_ card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeLibraryClient() else { return }
        let nextWatched = !(card.progress?.watched ?? false)
        do {
            let s = card.directPlayTarget?.season ?? card.nextUp?.season ?? card.progress?.season
            let e = card.directPlayTarget?.episode ?? card.nextUp?.episode ?? card.progress?.episode
            if card.mediaType == "series" && (nextWatched || card.directPlayTarget?.season != nil),
               let s, let e {
                try await client.setWatched(
                    watched: nextWatched,
                    mediaType: "episode",
                    ids: card.ids,
                    title: card.title,
                    year: card.year,
                    season: s,
                    episode: e
                )
            } else {
                try await client.setWatched(
                    watched: nextWatched,
                    mediaType: card.mediaType,
                    ids: card.ids,
                    title: card.title,
                    year: card.year,
                    season: nil,
                    episode: nil
                )
            }
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            await markLocalMutationAndReload(session: session)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func cancelAllTasks() {
        reloadTask?.cancel()
        reloadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        reloadGeneration &+= 1
        isLoading = false
        isLoadingMoreLocal = false
    }

    public func unloadForMemoryWarning() {
        cancelAllTasks()
        libraryPayload = nil
        localItems = []
        localOffset = 0
        localHasMore = false
        cachedEtag = nil
        loadedQueryKey = nil
        isLoading = false
        isLoadingMoreLocal = false
        isUnloadedForMemoryWarning = true
    }

    @discardableResult
    private func applyInitialSectionResolutionIfNeeded(counts: TvLibraryCounts) -> Bool {
        let resolution = LibraryFilterSection.resolveInitialSection(
            counts: counts,
            didApplyInitialFallback: didApplyInitialSectionFallback,
            current: activeSection
        )
        didApplyInitialSectionFallback = resolution.didApplyInitialFallback
        if resolution.section != activeSection {
            activeSection = resolution.section
            return true
        }
        return false
    }

    private func persistLibrarySnapshot(
        for key: String,
        payload: TvLibraryResponse,
        fetchedAt: Date? = nil,
        refreshNonce: Int,
        preserveExistingEtag: Bool = true
    ) {
        let existing = LibraryBrowseMemoryCache.shared.snapshot(for: key)
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(
                payload: payload,
                localItems: localItems,
                localOffset: localOffset,
                localHasMore: localHasMore,
                fetchedAt: fetchedAt ?? existing?.fetchedAt ?? Date(),
                refreshNonce: refreshNonce,
                etag: preserveExistingEtag ? (cachedEtag ?? existing?.etag) : cachedEtag
            ),
            for: key
        )
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }
}
