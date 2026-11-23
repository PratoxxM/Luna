import SwiftUI

internal struct CatalogBrowseSnapshot {
    var items: [TvMediaCard]
    var availableGenres: [TvGenreChip]
    var selectedGenreLabel: String?
    var hasMore: Bool
    var currentPage: Int
    var fetchedAt: Date
    var refreshNonce: Int
}

internal enum CatalogBrowseMemoryCache {
    @MainActor
    static let shared = BoundedLRUMemoryCache<CatalogBrowseSnapshot>(
        maxEntries: DeviceMemoryProfile.current.catalogCacheMaxEntries
    )
}

struct CatalogBrowseView: View {
    private enum CatalogFallbackFocus: Hashable {
        case retry
        case emptyReset
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let mediaType: String
    let initialGenre: TvGenreChip?
    let isActiveTab: Bool
    let isRootTab: Bool

    @State private var subpageToken = UUID()

    @State private var selectedGenreSlug: String?
    @State private var selectedGenreLabel: String?
    @State private var selectedSort: String = "popular"
    @State private var localOnly: Bool = false
    @State private var unwatchedOnly: Bool = false

    @State private var availableGenres: [TvGenreChip] = []
    @State private var items: [TvMediaCard] = []
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var reloadTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0

    @State private var selectedCard: TvMediaCard?
    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @FocusState private var fallbackFocus: CatalogFallbackFocus?
    @Namespace private var catalogGridNamespace

    private let columns = LunaTheme.posterGridColumns
    private let pageSize = DeviceMemoryProfile.current.catalogPageSize

    internal static func makeCacheKey(
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

    private var sortOptions: [(id: String, label: String)] {
        let base: [(id: String, label: String)] = [
            ("popular", "Mest populære"),
            ("top_rated", "Høyest rangert"),
            ("newest", "Nyeste"),
        ]
        if isRootTab {
            return base
        }
        return base + [("local_recent", "Lokalt")]
    }

    init(
        mediaType: String,
        initialGenre: TvGenreChip?,
        isActiveTab: Bool = true,
        isRootTab: Bool = false
    ) {
        self.mediaType = mediaType
        self.initialGenre = initialGenre
        self.isActiveTab = isActiveTab
        self.isRootTab = isRootTab
        _selectedGenreSlug = State(initialValue: initialGenre?.slug)
        _selectedGenreLabel = State(initialValue: initialGenre?.label)
    }

    private var rootNavigationTab: MainNavigationTab {
        (mediaType == "series" || mediaType == "tv") ? .series : .movies
    }

    private var headerTitle: String {
        let kindLabel = (mediaType == "series" || mediaType == "tv") ? "Serier" : "Filmer"
        if let label = selectedGenreLabel, !label.isEmpty {
            return "\(label) · \(kindLabel)"
        }
        return kindLabel
    }

    private var reloadTriggerKey: String {
        Self.makeCacheKey(
            serverBaseURL: sessionStore.serverBaseURL,
            mediaType: mediaType,
            genreSlug: selectedGenreSlug,
            sort: selectedSort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            roomName: sessionStore.roomName,
            hardwareProfile: sessionStore.hardwareProfile
        )
    }

    var body: some View {
        let client = sessionStore.makeClient()

        return ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    if !isRootTab {
                        Text(headerTitle)
                            .font(LunaTheme.Font.pageTitle)
                            .foregroundStyle(LunaTheme.linen)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    CatalogFilterStripView(
                        sortOptions: sortOptions,
                        isRootTab: isRootTab,
                        availableGenres: availableGenres,
                        selectedSort: $selectedSort,
                        localOnly: $localOnly,
                        unwatchedOnly: $unwatchedOnly,
                        selectedGenreSlug: $selectedGenreSlug,
                        selectedGenreLabel: $selectedGenreLabel,
                        entryFocusNonce: contentEntryFocusNonce,
                        isEntryActive: isRootTab && isActiveTab,
                        onScrollToTop: {
                            scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                        },
                        onMoveDown: {
                            if !items.isEmpty {
                                if !mountedTracker.hasAnyMounted, let firstID = items.first?.id {
                                    scrollProxy.scrollTo(firstID, anchor: .top)
                                }
                                if let resolvedID = mountedTracker.resolveEntryID(orderedIDs: items.map(\.id)) {
                                    entryCardID = resolvedID
                                    cardFocusNonce &+= 1
                                }
                            } else if errorMessage != nil {
                                fallbackFocus = .retry
                            } else if localOnly || unwatchedOnly || selectedGenreSlug != nil {
                                fallbackFocus = .emptyReset
                            }
                        }
                    )

                // Content Grid
                if isLoading && items.isEmpty {
                    LunaLoadingRow(message: "Henter utvalg…")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if let errorMessage, items.isEmpty {
                    LunaInlineError(message: errorMessage) {
                        scheduleReloadFirstPage(forceNetwork: true)
                    }
                    .focused($fallbackFocus, equals: .retry)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    let hasFilters = localOnly || unwatchedOnly || selectedGenreSlug != nil
                    let emptyView = LunaEmptyState(
                        headline: "Ingen treff med disse filtrene",
                        actionTitle: hasFilters ? "Nullstill filtre" : nil,
                        actionSymbol: hasFilters ? "xmark" : nil,
                        actionProminence: .subtleChip,
                        onAction: hasFilters ? {
                            localOnly = false
                            unwatchedOnly = false
                            selectedGenreSlug = nil
                            selectedGenreLabel = nil
                        } : nil
                    )
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                    if hasFilters {
                        emptyView.focused($fallbackFocus, equals: .emptyReset)
                    } else {
                        emptyView
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: LunaTokens.Layout.gridRowGap) {
                        let prefetchThreshold = max(0, items.count - 6)
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: LunaTokens.Layout.gridPosterW,
                                showStorageBadge: true,
                                showRestingTitle: true,
                                focusRequestNonce: card.id == entryCardID ? cardFocusNonce : 0,
                                onSelect: {
                                    selectedCard = card
                                },
                                onPlayShortcut: {
                                    MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                                }
                            )
                            .id(card.id)
                            .lunaTrackMountedCard(id: card.id, in: mountedTracker)
                            .prefersDefaultFocus(!isRootTab && idx == 0, in: catalogGridNamespace)
                            .contextMenu {
                                StandardPosterContextMenuItems(
                                    card: card,
                                    onPlay: {
                                        MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                                    },
                                    onOpenDetails: {
                                        selectedCard = card
                                    },
                                    onToggleWatched: {
                                        Task { await toggleWatched(card) }
                                    },
                                    onToggleWatchlist: {
                                        Task { await toggleWatchlist(card) }
                                    }
                                )
                            }
                            .onAppear {
                                ArtworkPipeline.shared.prefetchUpcomingCards(
                                    in: items,
                                    afterIndex: idx,
                                    client: client
                                )
                                if idx >= prefetchThreshold && hasMore && !isLoadingMore {
                                    loadMoreTask?.cancel()
                                    loadMoreTask = Task { @MainActor in
                                        await loadNextPage()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.bottom, 32)
                    .focusSection()

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.bottom, 48)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isRootTab ? LunaTopBarView.contentTopPadding : LunaTokens.Layout.subpageTop)
            .padding(.bottom, 84)
        }
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .focusScope(catalogGridNamespace)
        .lunaRootScrollTopBarTracking(tab: rootNavigationTab, isEnabled: isRootTab)
        .onChange(of: scrollToTopNonce) { _, _ in
            guard isRootTab, isActiveTab else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
            }
        }
        .lunaBottomToast(message: $mutationErrorBanner, tone: .danger)
        .focusSection()
        .lunaNavigationContainerBackdrop(
            isEnabled: !isRootTab,
            mode: .ambient(isPaused: !isRootTab && sessionStore.activePlaybackTarget != nil)
        )
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onAppear {
            if !isRootTab {
                subpageVisibility.enterSubpage(subpageToken)
                if let firstID = items.first?.id {
                    entryCardID = firstID
                    cardFocusNonce &+= 1
                }
            }
        }
        .onChange(of: items.first?.id) { oldFirst, newFirst in
            if !isRootTab, oldFirst == nil, let newFirst {
                entryCardID = newFirst
                cardFocusNonce &+= 1
            }
        }
        .task(id: "\(reloadTriggerKey)#active:\(isActiveTab || !isRootTab)") {
            guard isActiveTab || !isRootTab else { return }
            reloadTask?.cancel()
            reloadTask = nil
            loadMoreTask?.cancel()
            loadMoreTask = nil
            reloadGeneration &+= 1
            let gen = reloadGeneration
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadFirstPage(forceNetwork: false, generation: gen)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            scheduleReloadFirstPage(forceNetwork: true)
        }
        .onDisappear {
            reloadTask?.cancel()
            reloadTask = nil
            loadMoreTask?.cancel()
            loadMoreTask = nil
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: isRootTab,
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
        }
    }

    private func persistSnapshot(for triggerKey: String, fetchedAt: Date? = nil, refreshNonce: Int? = nil) {
        let existing = CatalogBrowseMemoryCache.shared.snapshot(for: triggerKey)
        CatalogBrowseMemoryCache.shared.store(
            CatalogBrowseSnapshot(
                items: items,
                availableGenres: availableGenres,
                selectedGenreLabel: selectedGenreLabel,
                hasMore: hasMore,
                currentPage: currentPage,
                fetchedAt: fetchedAt ?? existing?.fetchedAt ?? Date(),
                refreshNonce: refreshNonce ?? existing?.refreshNonce ?? sessionStore.homeRefreshNonce
            ),
            for: triggerKey
        )
    }

    private func scheduleReloadFirstPage(forceNetwork: Bool) {
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor in
            await loadFirstPage(forceNetwork: forceNetwork, generation: gen)
            if reloadGeneration == gen {
                reloadTask = nil
            }
        }
    }

    private func loadFirstPage(forceNetwork: Bool = false, generation: UInt64? = nil) async {
        guard let client = sessionStore.makeClient() else { return }
        let triggerKey = reloadTriggerKey
        let currentNonce = sessionStore.homeRefreshNonce

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
            isLoading = cached.items.isEmpty

            if !forceNetwork,
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
        } else {
            isLoading = true
        }
        errorMessage = nil

        do {
            let res = try await client.fetchCatalog(
                kind: mediaType,
                genre: selectedGenreSlug,
                sort: selectedSort,
                localOnly: localOnly,
                unwatchedOnly: unwatchedOnly,
                page: 1,
                limit: pageSize
            )
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration), reloadTriggerKey == triggerKey else { return }
            currentPage = 1
            items = res.items
            hasMore = res.hasMore
            if let genres = res.availableGenres, !genres.isEmpty {
                availableGenres = genres
            }
            if let serverGenre = res.genre {
                selectedGenreLabel = serverGenre.label
            }
            persistSnapshot(for: triggerKey, fetchedAt: Date(), refreshNonce: sessionStore.homeRefreshNonce)
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            CatalogBrowseMemoryCache.shared.clear()
            sessionStore.unpairDevice()
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

    private func loadNextPage() async {
        guard !isLoadingMore, hasMore, let client = sessionStore.makeClient() else { return }
        let triggerKey = reloadTriggerKey
        let gen = reloadGeneration
        isLoadingMore = true
        let nextPage = currentPage + 1
        defer { isLoadingMore = false }

        do {
            let res = try await client.fetchCatalog(
                kind: mediaType,
                genre: selectedGenreSlug,
                sort: selectedSort,
                localOnly: localOnly,
                unwatchedOnly: unwatchedOnly,
                page: nextPage,
                limit: pageSize
            )
            guard !Task.isCancelled, gen == reloadGeneration, reloadTriggerKey == triggerKey else {
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
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled, gen == reloadGeneration else { return }
            showMutationError(error)
        }
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func toggleWatchlist(_ card: TvMediaCard) async {
        let nextListed = !(card.inWatchlist ?? false)
        let triggerKey = reloadTriggerKey
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].inWatchlist = nextListed
            persistSnapshot(for: triggerKey)
        }
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextListed, sessionStore: sessionStore) {
                let bumped = sessionStore.homeRefreshNonce &+ 1
                lastSeenRefreshNonce = bumped
                sessionStore.notifyContentMutated()
                persistSnapshot(for: triggerKey, refreshNonce: sessionStore.homeRefreshNonce)
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].inWatchlist = card.inWatchlist
                persistSnapshot(for: triggerKey)
            }
            showMutationError(error)
        }
    }

    private func toggleWatched(_ card: TvMediaCard) async {
        let nextWatched = !(card.progress?.watched ?? false)
        let originalProgress = card.progress
        let triggerKey = reloadTriggerKey
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            var updated = items[idx].progress ?? TvWatchProgress()
            updated.watched = nextWatched
            items[idx].progress = updated
            persistSnapshot(for: triggerKey)
        }
        do {
            if try await MediaCardMutator.toggleWatched(
                for: card,
                watched: nextWatched,
                preferSeriesEpisodeTarget: true,
                sessionStore: sessionStore
            ) {
                if unwatchedOnly && nextWatched {
                    items.removeAll { $0.id == card.id }
                }
                let bumped = sessionStore.homeRefreshNonce &+ 1
                lastSeenRefreshNonce = bumped
                sessionStore.notifyContentMutated()
                persistSnapshot(for: triggerKey, refreshNonce: sessionStore.homeRefreshNonce)
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].progress = originalProgress
                persistSnapshot(for: triggerKey)
            }
            showMutationError(error)
        }
    }
}

/// Focus-isolated horizontal filter pill strip so moving Siri Remote focus across sort/filter/genre
/// pills updates only this strip's `@FocusState` (`0` re-evaluations of `CatalogBrowseView` / `LazyVGrid`).
private struct CatalogFilterStripView: View {
    let sortOptions: [(id: String, label: String)]
    let isRootTab: Bool
    let availableGenres: [TvGenreChip]
    @Binding var selectedSort: String
    @Binding var localOnly: Bool
    @Binding var unwatchedOnly: Bool
    @Binding var selectedGenreSlug: String?
    @Binding var selectedGenreLabel: String?
    let entryFocusNonce: Int
    let isEntryActive: Bool
    let onScrollToTop: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void

    @FocusState private var focusedFilterId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sortOptions, id: \.id) { opt in
                    LunaPillButton(
                        opt.label,
                        isSelected: selectedSort == opt.id,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        guard selectedSort != opt.id else { return }
                        selectedSort = opt.id
                    }
                    .focused($focusedFilterId, equals: "sort-\(opt.id)")
                }

                Rectangle()
                    .fill(LunaTheme.warmBorderStrong)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)

                if !isRootTab {
                    LunaPillButton(
                        "Kun lokalt",
                        systemImage: localOnly ? "checkmark" : nil,
                        isSelected: localOnly,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        localOnly.toggle()
                    }
                    .focused($focusedFilterId, equals: "local-only")
                }

                LunaPillButton(
                    "Skjul sette",
                    systemImage: unwatchedOnly ? "checkmark" : nil,
                    isSelected: unwatchedOnly,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    unwatchedOnly.toggle()
                }
                .focused($focusedFilterId, equals: "unwatched")

                if !availableGenres.isEmpty {
                    Rectangle()
                        .fill(LunaTheme.warmBorderStrong)
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)

                    LunaPillButton(
                        "Alle sjangre",
                        isSelected: selectedGenreSlug == nil,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        selectedGenreSlug = nil
                        selectedGenreLabel = nil
                    }
                    .focused($focusedFilterId, equals: "genre-all")

                    ForEach(availableGenres) { chip in
                        let active = selectedGenreSlug == chip.slug
                        LunaPillButton(
                            chip.label,
                            isSelected: active,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            if active {
                                selectedGenreSlug = nil
                                selectedGenreLabel = nil
                            } else {
                                selectedGenreSlug = chip.slug
                                selectedGenreLabel = chip.label
                            }
                        }
                        .focused($focusedFilterId, equals: "genre-\(chip.slug)")
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .horizontal)
        .focusSection()
        .lunaEntryFocusTarget(
            nonce: entryFocusNonce,
            isActive: isEntryActive,
            focus: $focusedFilterId,
            target: { "sort-\(selectedSort)" },
            onTrigger: onScrollToTop
        )
        .onMoveCommand { direction in
            if direction == .down {
                onMoveDown()
            }
        }
    }
}
