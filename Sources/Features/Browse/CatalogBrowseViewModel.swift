import Foundation
import Observation

public struct CatalogSortOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let subtitle: String

    public init(id: String, label: String, subtitle: String) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
    }

    public static let allOptions: [CatalogSortOption] = [
        CatalogSortOption(
            id: "popular",
            label: "Mest populære",
            subtitle: "Titler med høyest interesse nå"
        ),
        CatalogSortOption(
            id: "top_rated",
            label: "Høyest rangert",
            subtitle: "Sortert etter høyeste vurdering"
        ),
        CatalogSortOption(
            id: "newest",
            label: "Nyeste",
            subtitle: "Nyeste utgivelser først"
        ),
        CatalogSortOption(
            id: "local_recent",
            label: "Nylig lagt til lokalt",
            subtitle: "Sist lagret på LunaCore"
        ),
    ]

    public static func label(for sortID: String) -> String {
        allOptions.first(where: { $0.id == sortID })?.label ?? "Mest populære"
    }
}

public struct CatalogBrowseSnapshot: Sendable {
    public var items: [TvMediaCard]
    public var availableGenres: [TvGenreChip]
    public var selectedGenreLabel: String?
    public var hasMore: Bool
    public var currentPage: Int
    public var fetchedAt: Date
    public var refreshNonce: Int
    public var etag: String?

    public init(
        items: [TvMediaCard],
        availableGenres: [TvGenreChip],
        selectedGenreLabel: String?,
        hasMore: Bool,
        currentPage: Int,
        fetchedAt: Date,
        refreshNonce: Int,
        etag: String? = nil
    ) {
        self.items = items
        self.availableGenres = availableGenres
        self.selectedGenreLabel = selectedGenreLabel
        self.hasMore = hasMore
        self.currentPage = currentPage
        self.fetchedAt = fetchedAt
        self.refreshNonce = refreshNonce
        self.etag = etag
    }
}

public enum CatalogBrowseMemoryCache {
    @MainActor
    public static let shared = BoundedLRUMemoryCache<CatalogBrowseSnapshot>(
        maxEntries: DeviceMemoryProfile.current.catalogCacheMaxEntries
    )
}

@MainActor
@Observable
public final class CatalogBrowseViewModel {
    public let mediaType: String
    public let isRootTab: Bool

    public var selectedGenreSlug: String?
    public var selectedGenreLabel: String?
    public var selectedSort: String = "popular"
    public var localOnly: Bool = false
    public var unwatchedOnly: Bool = false

    public private(set) var availableGenres: [TvGenreChip] = []
    public private(set) var items: [TvMediaCard] = []
    public private(set) var currentPage: Int = 1
    public private(set) var hasMore: Bool = false
    public private(set) var cachedEtag: String?
    public private(set) var isLoading: Bool = true
    public private(set) var isLoadingMore: Bool = false
    public private(set) var errorMessage: String?
    public var mutationErrorBanner: String?
    public var lastSeenRefreshNonce: Int = -1
    public private(set) var isUnloadedForMemoryWarning: Bool = false

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var loadedTriggerKey: String?
    @ObservationIgnored private let pageSize: Int

    public init(
        mediaType: String,
        initialGenre: TvGenreChip? = nil,
        isRootTab: Bool = false,
        pageSize: Int = DeviceMemoryProfile.current.catalogPageSize
    ) {
        self.mediaType = mediaType
        self.isRootTab = isRootTab
        self.selectedGenreSlug = initialGenre?.slug
        self.selectedGenreLabel = initialGenre?.label
        self.pageSize = max(1, pageSize)
    }

    public static func makeCacheKey(
        serverBaseURL: URL?,
        mediaType: String,
        genreSlug: String? = nil,
        sort: String = "popular",
        localOnly: Bool = false,
        unwatchedOnly: Bool = false,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        "\(serverBaseURL?.absoluteString ?? "")#\(mediaType)#\(genreSlug ?? "all")#\(sort)#\(localOnly)#\(unwatchedOnly)#\(roomName)#\(hardwareProfile)"
    }

    public var rootNavigationTab: MainNavigationTab {
        (mediaType == "series" || mediaType == "tv") ? .series : .movies
    }

    public var headerTitle: String {
        let kindLabel = (mediaType == "series" || mediaType == "tv") ? "Serier" : "Filmer"
        if let label = selectedGenreLabel, !label.isEmpty {
            return "\(label) · \(kindLabel)"
        }
        return kindLabel
    }

    public var hasActiveFilters: Bool {
        localOnly || unwatchedOnly || selectedGenreSlug != nil
    }

    public var isDefaultUnfilteredQuery: Bool {
        selectedGenreSlug == nil && selectedSort == "popular" && !localOnly && !unwatchedOnly
    }

    public func reloadTriggerKey(for session: any TabSessionContext) -> String {
        Self.makeCacheKey(
            serverBaseURL: session.serverBaseURL,
            mediaType: mediaType,
            genreSlug: selectedGenreSlug,
            sort: selectedSort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            roomName: session.roomName,
            hardwareProfile: session.hardwareProfile
        )
    }

    public func resetFilters() {
        localOnly = false
        unwatchedOnly = false
        selectedGenreSlug = nil
        selectedGenreLabel = nil
    }

    public func handleActivation(session: any TabSessionContext, isActive: Bool) async {
        guard isActive else { return }
        reloadTask?.cancel()
        reloadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        reloadGeneration &+= 1
        let gen = reloadGeneration
        lastSeenRefreshNonce = session.homeRefreshNonce
        await loadFirstPage(forceNetwork: false, session: session, generation: gen)
    }

    public func handleHomeRefreshNonceChange(
        _ newNonce: Int,
        isActiveTab: Bool,
        session: any TabSessionContext
    ) {
        guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
        lastSeenRefreshNonce = newNonce
        scheduleReloadFirstPage(forceNetwork: true, session: session)
    }

    public func scheduleReloadFirstPage(forceNetwork: Bool, session: any TabSessionContext) {
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadFirstPage(forceNetwork: forceNetwork, session: session, generation: gen)
            if self.reloadGeneration == gen {
                self.reloadTask = nil
            }
        }
    }

    public func scheduleLoadNextPage(session: any TabSessionContext) {
        guard !isLoadingMore, hasMore else { return }
        loadMoreTask?.cancel()
        loadMoreTask = Task { @MainActor [weak self] in
            await self?.loadNextPage(session: session)
        }
    }

    public func loadFirstPage(
        forceNetwork: Bool = false,
        session: any TabSessionContext,
        generation: UInt64? = nil
    ) async {
        guard let client = session.makeCatalogClient() else { return }
        let triggerKey = reloadTriggerKey(for: session)
        let currentNonce = session.homeRefreshNonce
        let wasUnloaded = isUnloadedForMemoryWarning

        if loadedTriggerKey != triggerKey {
            loadedTriggerKey = triggerKey
            cachedEtag = nil
            items = []
            hasMore = false
            currentPage = 1
        }

        if let cached = CatalogBrowseMemoryCache.shared.snapshot(for: triggerKey) {
            items = cached.items
            if availableGenres.isEmpty && !cached.availableGenres.isEmpty {
                availableGenres = cached.availableGenres
            }
            if selectedGenreSlug != nil, selectedGenreLabel == nil {
                selectedGenreLabel = cached.selectedGenreLabel
            }
            hasMore = cached.hasMore
            currentPage = max(1, cached.currentPage)
            cachedEtag = cached.etag
            isLoading = cached.items.isEmpty
            isUnloadedForMemoryWarning = false

            if !forceNetwork,
               !wasUnloaded,
               TabContentFreshnessPolicy.isCacheFresh(
                   hasCachedContent: !cached.items.isEmpty,
                   lastValidatedAt: cached.fetchedAt,
                   cachedRefreshNonce: cached.refreshNonce,
                   currentRefreshNonce: currentNonce,
                   freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
               ) {
                errorMessage = nil
                isLoading = false
                return
            }
        } else if isDefaultUnfilteredQuery {
            let host = session.serverBaseURL?.host
            let room = session.roomName
            let profile = session.hardwareProfile
            let memDisk = DiskSWRStore.catalogMemorySnapshot(
                kind: mediaType,
                serverHost: host,
                roomName: room,
                hardwareProfile: profile
            )
            let diskSnap: CachedCatalogSnapshot?
            if let memDisk {
                diskSnap = memDisk
            } else {
                diskSnap = await DiskSWRStore.loadCatalogAsync(
                    kind: mediaType,
                    serverHost: host,
                    roomName: room,
                    hardwareProfile: profile
                )
            }
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration), reloadTriggerKey(for: session) == triggerKey else {
                if generation == nil || generation == reloadGeneration {
                    isLoading = false
                }
                return
            }
            if let diskSnap, !diskSnap.payload.items.isEmpty {
                items = diskSnap.payload.items
                if let genres = diskSnap.payload.availableGenres, !genres.isEmpty {
                    availableGenres = genres
                }
                hasMore = diskSnap.payload.hasMore
                currentPage = 1
                cachedEtag = diskSnap.etag
                isLoading = false
                isUnloadedForMemoryWarning = false
            } else {
                cachedEtag = nil
                isLoading = true
            }
        } else {
            cachedEtag = nil
            isLoading = true
        }
        errorMessage = nil

        do {
            let result = try await client.fetchCatalogConditional(
                kind: mediaType,
                genre: selectedGenreSlug,
                sort: selectedSort,
                localOnly: localOnly,
                unwatchedOnly: unwatchedOnly,
                page: 1,
                limit: pageSize,
                ifNoneMatch: (forceNetwork || items.isEmpty) ? nil : cachedEtag
            )
            guard !Task.isCancelled,
                  (generation == nil || generation == reloadGeneration),
                  reloadTriggerKey(for: session) == triggerKey else {
                if generation == nil || generation == reloadGeneration {
                    isLoading = false
                }
                return
            }
            switch result {
            case .notModified:
                isUnloadedForMemoryWarning = false
                persistSnapshot(for: triggerKey, fetchedAt: Date(), refreshNonce: session.homeRefreshNonce)
            case .updated(let res, let newEtag, let rawData):
                currentPage = 1
                items = res.items
                hasMore = res.hasMore
                cachedEtag = newEtag
                isUnloadedForMemoryWarning = false
                if let genres = res.availableGenres, !genres.isEmpty {
                    availableGenres = genres
                }
                if let serverGenre = res.genre {
                    selectedGenreLabel = serverGenre.label
                }
                persistSnapshot(
                    for: triggerKey,
                    fetchedAt: Date(),
                    refreshNonce: session.homeRefreshNonce,
                    preserveExistingEtag: false
                )
                if isDefaultUnfilteredQuery {
                    DiskSWRStore.saveCatalogInBackground(
                        rawPayloadData: rawData,
                        etag: newEtag,
                        kind: mediaType,
                        serverHost: session.serverBaseURL?.host,
                        roomName: session.roomName,
                        hardwareProfile: session.hardwareProfile,
                        decodedPayload: res
                    )
                }
            }
        } catch where LunaCoreError.isCancellation(error) {
            if generation == nil || generation == reloadGeneration {
                isLoading = false
            }
            return
        } catch LunaCoreError.unauthorized {
            CatalogBrowseMemoryCache.shared.clear()
            session.unpairDevice()
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if items.isEmpty {
                errorMessage = LunaCopy.friendlyErrorMessage(error)
            }
        }
        if generation == nil || generation == reloadGeneration {
            isLoading = false
        }
    }

    public func loadNextPage(session: any TabSessionContext) async {
        guard !isLoadingMore, hasMore, let client = session.makeCatalogClient() else { return }
        let triggerKey = reloadTriggerKey(for: session)
        let gen = reloadGeneration
        isLoadingMore = true
        let nextPage = currentPage + 1
        defer {
            if gen == reloadGeneration {
                isLoadingMore = false
            }
        }

        do {
            let result = try await client.fetchCatalogConditional(
                kind: mediaType,
                genre: selectedGenreSlug,
                sort: selectedSort,
                localOnly: localOnly,
                unwatchedOnly: unwatchedOnly,
                page: nextPage,
                limit: pageSize,
                ifNoneMatch: nil
            )
            guard !Task.isCancelled, gen == reloadGeneration, reloadTriggerKey(for: session) == triggerKey else {
                return
            }
            guard case .updated(let res, _, _) = result else {
                return
            }
            currentPage = nextPage
            hasMore = res.hasMore
            let existingIDs = Set(items.map(\.id))
            let fresh = res.items.filter { !existingIDs.contains($0.id) }
            items.append(contentsOf: fresh)
            persistSnapshot(for: triggerKey)
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            CatalogBrowseMemoryCache.shared.clear()
            session.unpairDevice()
        } catch {
            guard !Task.isCancelled, gen == reloadGeneration else { return }
            showMutationError(error)
        }
    }

    public func toggleWatchlist(_ card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeCatalogClient() else { return }
        let nextListed = !(card.inWatchlist ?? false)
        let triggerKey = reloadTriggerKey(for: session)
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].inWatchlist = nextListed
            persistSnapshot(for: triggerKey)
        }
        do {
            try await client.setWatchlist(
                listed: nextListed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            let bumped = session.homeRefreshNonce &+ 1
            lastSeenRefreshNonce = bumped
            session.notifyContentMutated()
            persistSnapshot(for: triggerKey, refreshNonce: session.homeRefreshNonce)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].inWatchlist = card.inWatchlist
                persistSnapshot(for: triggerKey)
            }
            showMutationError(error)
        }
    }

    public func toggleWatched(_ card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeCatalogClient() else { return }
        let nextWatched = !(card.progress?.watched ?? false)
        let originalProgress = card.progress
        let triggerKey = reloadTriggerKey(for: session)
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            var updated = items[idx].progress ?? TvWatchProgress()
            updated.watched = nextWatched
            items[idx].progress = updated
            persistSnapshot(for: triggerKey)
        }
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
            if unwatchedOnly && nextWatched {
                items.removeAll { $0.id == card.id }
            }
            let bumped = session.homeRefreshNonce &+ 1
            lastSeenRefreshNonce = bumped
            session.notifyContentMutated()
            persistSnapshot(for: triggerKey, refreshNonce: session.homeRefreshNonce)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].progress = originalProgress
                persistSnapshot(for: triggerKey)
            }
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
        isLoadingMore = false
    }

    public func unloadForMemoryWarning() {
        cancelAllTasks()
        items = []
        availableGenres = []
        currentPage = 1
        hasMore = false
        cachedEtag = nil
        loadedTriggerKey = nil
        isLoading = false
        isLoadingMore = false
        isUnloadedForMemoryWarning = true
    }

    private func persistSnapshot(
        for triggerKey: String,
        fetchedAt: Date? = nil,
        refreshNonce: Int? = nil,
        preserveExistingEtag: Bool = true
    ) {
        let existing = CatalogBrowseMemoryCache.shared.snapshot(for: triggerKey)
        CatalogBrowseMemoryCache.shared.store(
            CatalogBrowseSnapshot(
                items: items,
                availableGenres: availableGenres,
                selectedGenreLabel: selectedGenreLabel,
                hasMore: hasMore,
                currentPage: currentPage,
                fetchedAt: fetchedAt ?? existing?.fetchedAt ?? Date(),
                refreshNonce: refreshNonce ?? existing?.refreshNonce ?? 0,
                etag: preserveExistingEtag ? (cachedEtag ?? existing?.etag) : cachedEtag
            ),
            for: triggerKey
        )
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }
}
