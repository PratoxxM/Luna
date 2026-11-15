import SwiftUI

private struct CatalogBrowseSnapshot {
    var items: [TvMediaCard]
    var availableGenres: [TvGenreChip]
    var selectedGenreLabel: String?
    var hasMore: Bool
    var currentPage: Int
}

@MainActor
private final class CatalogBrowseMemoryCache {
    static let shared = CatalogBrowseMemoryCache()
    private let maxEntries = 16
    private var entries: [String: CatalogBrowseSnapshot] = [:]
    private var order: [String] = []

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

    let mediaType: String
    let initialGenre: TvGenreChip?
    let isActiveTab: Bool

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

    @State private var selectedCard: TvMediaCard?

    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    private let sortOptions: [(id: String, label: String, icon: String)] = [
        ("popular", "Mest populære", "flame.fill"),
        ("top_rated", "Høyest rangert", "star.fill"),
        ("newest", "Nyeste", "sparkles"),
        ("local_recent", "Lokalt hos oss", "internaldrive.fill")
    ]

    init(mediaType: String, initialGenre: TvGenreChip?, isActiveTab: Bool = true) {
        self.mediaType = mediaType
        self.initialGenre = initialGenre
        self.isActiveTab = isActiveTab
        _selectedGenreSlug = State(initialValue: initialGenre?.slug)
        _selectedGenreLabel = State(initialValue: initialGenre?.label)
    }

    private var headerTitle: String {
        let kindLabel = (mediaType == "series" || mediaType == "tv") ? "Serier" : "Filmer"
        if let label = selectedGenreLabel, !label.isEmpty {
            return "\(label) · \(kindLabel)"
        }
        return kindLabel
    }

    private var reloadTriggerKey: String {
        "\(mediaType)#\(selectedGenreSlug ?? "all")#\(selectedSort)#\(localOnly)#\(unwatchedOnly)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let mutationErrorBanner {
                    TransientErrorBanner(message: mutationErrorBanner)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 14)
                }

                Text(headerTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, 14)

                // Sort & quick filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(sortOptions, id: \.id) { opt in
                            LunaPillButton(
                                opt.label,
                                systemImage: opt.icon,
                                isSelected: selectedSort == opt.id
                            ) {
                                guard selectedSort != opt.id else { return }
                                selectedSort = opt.id
                            }
                        }

                        Rectangle()
                            .fill(LunaTheme.moonlight.opacity(0.16))
                            .frame(width: 1, height: 28)
                            .padding(.horizontal, 6)

                        LunaPillButton(
                            "Kun lokalt",
                            systemImage: localOnly ? "checkmark.circle.fill" : "internaldrive",
                            isSelected: localOnly
                        ) {
                            localOnly.toggle()
                        }

                        LunaPillButton(
                            "Skjul sette",
                            systemImage: unwatchedOnly ? "eye.slash.fill" : "eye.slash",
                            isSelected: unwatchedOnly
                        ) {
                            unwatchedOnly.toggle()
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()

                // Genre strip
                if !availableGenres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            LunaPillButton(
                                "Alle sjangre",
                                systemImage: "square.grid.2x2",
                                isSelected: selectedGenreSlug == nil,
                                prominence: .subtleChip
                            ) {
                                selectedGenreSlug = nil
                                selectedGenreLabel = nil
                            }

                            ForEach(availableGenres) { chip in
                                let active = selectedGenreSlug == chip.slug
                                LunaPillButton(
                                    chip.label,
                                    systemImage: LunaTheme.symbolForGenre(slug: chip.slug, serverIcon: chip.icon),
                                    isSelected: active,
                                    prominence: .subtleChip
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
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 10)
                    }
                    .scrollClipDisabled()
                }

                // Content Grid
                if isLoading && items.isEmpty {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter utvalg…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 60)
                } else if let errorMessage, items.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadFirstPage() }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingen treff med valgte filtre.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)
                        if localOnly || unwatchedOnly {
                            LunaPillButton("Nullstill hurtigfiltre", systemImage: "xmark.circle") {
                                localOnly = false
                                unwatchedOnly = false
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 42) {
                        ForEach(items) { card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 244,
                                showStorageBadge: localOnly || selectedSort == "local_recent",
                                onSelect: {
                                    selectedCard = card
                                },
                                onPlayShortcut: {
                                    MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                                }
                            )
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
                                    },
                                    onToggleFavorite: {
                                        Task { await toggleFavorite(card) }
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
            .padding(.bottom, 64)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .task(id: reloadTriggerKey) {
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadFirstPage()
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            Task { await loadFirstPage() }
        }
        .onChange(of: isActiveTab) { _, active in
            guard active, lastSeenRefreshNonce != sessionStore.homeRefreshNonce else { return }
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            Task { await loadFirstPage() }
        }
        .onDisappear {
            mutationBannerTask?.cancel()
        }
    }

    private func persistSnapshot(for triggerKey: String) {
        CatalogBrowseMemoryCache.shared.store(
            CatalogBrowseSnapshot(
                items: items,
                availableGenres: availableGenres,
                selectedGenreLabel: selectedGenreLabel,
                hasMore: hasMore,
                currentPage: currentPage
            ),
            for: triggerKey
        )
    }

    private func loadFirstPage() async {
        guard let client = sessionStore.makeClient() else { return }
        let triggerKey = reloadTriggerKey
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
            guard !Task.isCancelled, reloadTriggerKey == triggerKey else { return }
            currentPage = 1
            items = res.items
            hasMore = res.hasMore
            if let genres = res.availableGenres, !genres.isEmpty {
                availableGenres = genres
            }
            if let serverGenre = res.genre {
                selectedGenreLabel = serverGenre.label
            }
            persistSnapshot(for: triggerKey)
        } catch LunaCoreError.unauthorized {
            CatalogBrowseMemoryCache.shared.clear()
            sessionStore.unpairDevice()
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
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
        mutationErrorBanner = "Kunne ikke lagre endring: \(error.localizedDescription)"
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
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].inWatchlist = card.inWatchlist
                persistSnapshot(for: triggerKey)
            }
            showMutationError(error)
        }
    }

    private func toggleFavorite(_ card: TvMediaCard) async {
        let nextFavorite = !(card.isFavorite ?? false)
        let triggerKey = reloadTriggerKey
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].isFavorite = nextFavorite
            persistSnapshot(for: triggerKey)
        }
        do {
            if try await MediaCardMutator.setFavorite(for: card, favorite: nextFavorite, sessionStore: sessionStore) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].isFavorite = card.isFavorite
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
                persistSnapshot(for: triggerKey)
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
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
