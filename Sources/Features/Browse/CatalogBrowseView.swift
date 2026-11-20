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

@MainActor
internal final class CatalogBrowseMemoryCache {
    static let shared = CatalogBrowseMemoryCache()
    private let maxEntries = 16
    private var entries: [String: CatalogBrowseSnapshot] = [:]
    private var order: [String] = []

    var entryCount: Int { entries.count }

    func snapshot(for key: String) -> CatalogBrowseSnapshot? {
        guard let hit = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    func store(_ snapshot: CatalogBrowseSnapshot, for key: String) {
        entries[key] = snapshot
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    func clear() {
        entries.removeAll()
        order.removeAll()
    }
}

struct CatalogBrowseView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

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
    @State private var mutationBannerTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0

    @State private var selectedCard: TvMediaCard?
    @FocusState private var focusedCardId: String?

    private let columns = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.posterW), spacing: LunaTokens.Layout.cardGap, alignment: .topLeading),
        count: 5
    )

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
        "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(mediaType)#\(selectedGenreSlug ?? "all")#\(selectedSort)#\(localOnly)#\(unwatchedOnly)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()

        let columns = Array(
            repeating: GridItem(.fixed(LunaTokens.Layout.posterW), spacing: LunaTokens.Layout.cardGap, alignment: .topLeading),
            count: 5
        )
        _ = columns
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                Text(headerTitle)
                    .font(LunaTheme.Font.pageTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                // Single calm compact filter strip within 90 pt margins
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortOptions, id: \.id) { opt in
                            LunaPillButton(
                                opt.label,
                                isSelected: selectedSort == opt.id,
                                prominence: .subtleChip,
                                size: .compact
                            ) {
                                guard selectedSort != opt.id else { return }
                                selectedSort = opt.id
                            }
                        }

                        if !isRootTab {
                            LunaPillButton(
                                "Kun lokalt",
                                systemImage: localOnly ? "checkmark" : nil,
                                isSelected: localOnly,
                                prominence: .subtleChip,
                                size: .compact
                            ) {
                                localOnly.toggle()
                            }
                        }

                        LunaPillButton(
                            "Skjul sette",
                            systemImage: unwatchedOnly ? "checkmark" : nil,
                            isSelected: unwatchedOnly,
                            prominence: .subtleChip,
                            size: .compact
                        ) {
                            unwatchedOnly.toggle()
                        }

                        if !availableGenres.isEmpty {
                            Text("·")
                                .font(LunaTheme.Font.caption)
                                .foregroundStyle(LunaTheme.muted)
                                .padding(.horizontal, 6)

                            LunaPillButton(
                                "Alle sjangre",
                                isSelected: selectedGenreSlug == nil,
                                prominence: .subtleChip,
                                size: .compact
                            ) {
                                selectedGenreSlug = nil
                                selectedGenreLabel = nil
                            }

                            ForEach(availableGenres) { chip in
                                let active = selectedGenreSlug == chip.slug
                                LunaPillButton(
                                    chip.label,
                                    isSelected: active,
                                    prominence: .subtleChip,
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
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()

                // Content Grid
                if isLoading && items.isEmpty {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter utvalg…")
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 60)
                } else if let errorMessage, items.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.danger)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            scheduleReloadFirstPage(forceNetwork: true)
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingenting passer akkurat disse filtrene.")
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.linen)
                        if localOnly || unwatchedOnly || selectedGenreSlug != nil {
                            LunaPillButton("Nullstill filtre", systemImage: "xmark.circle", prominence: .subtleChip) {
                                localOnly = false
                                unwatchedOnly = false
                                selectedGenreSlug = nil
                                selectedGenreLabel = nil
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 34) {
                        ForEach(items) { card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: LunaTokens.Layout.posterW,
                                showStorageBadge: !isRootTab && (localOnly || selectedSort == "local_recent"),
                                onSelect: {
                                    selectedCard = card
                                },
                                onPlayShortcut: {
                                    MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                                }
                            )
                            .focused($focusedCardId, equals: card.id)
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
                                if card.id == items.last?.id && hasMore && !isLoadingMore {
                                    Task { await loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.bottom, 32)

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
            .padding(.top, isRootTab ? LunaTopBarView.contentTopPadding : 32)
            .padding(.bottom, 84)
        }
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .defaultFocus($focusedCardId, items.first?.id, priority: .userInitiated)
        .lunaRootScrollTopBarTracking(tab: rootNavigationTab, isEnabled: isRootTab)
        .overlay(alignment: .topLeading) {
            if let mutationErrorBanner {
                TransientErrorBanner(message: mutationErrorBanner)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, (isRootTab ? LunaTopBarView.contentTopPadding : 24) + 8)
                    .allowsHitTesting(false)
            }
        }
        .focusSection()
        .lunaNavigationContainerBackdrop(
            isEnabled: !isRootTab,
            mode: .ambient(isPaused: sessionStore.activePlaybackTarget != nil)
        )
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onAppear {
            if !isRootTab {
                subpageVisibility.enterSubpage(subpageToken)
            }
        }
        .task(id: reloadTriggerKey) {
            reloadTask?.cancel()
            reloadTask = nil
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
        .onChange(of: isActiveTab) { _, active in
            guard active else { return }
            let cached = CatalogBrowseMemoryCache.shared.snapshot(for: reloadTriggerKey)
            let isFresh = TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: !(cached?.items.isEmpty ?? items.isEmpty),
                lastValidatedAt: cached?.fetchedAt ?? .distantPast,
                cachedRefreshNonce: cached?.refreshNonce ?? lastSeenRefreshNonce,
                currentRefreshNonce: sessionStore.homeRefreshNonce
            )
            guard !isFresh else { return }
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            scheduleReloadFirstPage(forceNetwork: true)
        }
        .onDisappear {
            mutationBannerTask?.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: isRootTab,
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
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
                   currentRefreshNonce: currentNonce
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
                limit: 30
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
        } catch is CancellationError {
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
        isLoadingMore = true
        let nextPage = currentPage + 1
        defer { isLoadingMore = false }

        guard let res = try? await client.fetchCatalog(
            kind: mediaType,
            genre: selectedGenreSlug,
            sort: selectedSort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            page: nextPage,
            limit: 30
        ), reloadTriggerKey == triggerKey else {
            return
        }

        currentPage = nextPage
        hasMore = res.hasMore
        let existingIDs = Set(items.map(\.id))
        let fresh = res.items.filter { !existingIDs.contains($0.id) }
        items.append(contentsOf: fresh)
        persistSnapshot(for: triggerKey)
    }

    private func showMutationError(_ error: Error) {
        mutationBannerTask?.cancel()
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
        mutationBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            mutationErrorBanner = nil
        }
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
            if try await MediaCardMutator.toggleWatched(for: card, watched: nextWatched, sessionStore: sessionStore) {
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
