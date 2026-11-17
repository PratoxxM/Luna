import SwiftUI

private enum LibrarySectionTab: String, CaseIterable, Identifiable, Sendable {
    case watchlist = "watchlist"
    case favorites = "favorites"
    case local = "local"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watchlist: return "Huskeliste"
        case .favorites: return "Favoritter & Lister"
        case .local: return "Lokalt på NAS"
        }
    }
}

internal struct LibraryBrowseSnapshot {
    var payload: TvLibraryResponse
    var localItems: [TvMediaCard]
    var localOffset: Int
    var localHasMore: Bool
    var fetchedAt: Date
    var refreshNonce: Int
}

@MainActor
internal final class LibraryBrowseMemoryCache {
    static let shared = LibraryBrowseMemoryCache()
    private let maxEntries = 12
    private var entries: [String: LibraryBrowseSnapshot] = [:]
    private var order: [String] = []

    var entryCount: Int { entries.count }

    func snapshot(for key: String) -> LibraryBrowseSnapshot? {
        guard let hit = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    func store(_ snapshot: LibraryBrowseSnapshot, for key: String) {
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

struct LibraryHubView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let isActiveTab: Bool

    @State private var activeSection: LibrarySectionTab = .watchlist
    @State private var mediaTypeFilter: String = "all"
    @State private var localTierFilter: String = "all"
    @State private var localSort: String = "recent"

    @State private var libraryPayload: TvLibraryResponse?
    @State private var localItems: [TvMediaCard] = []
    @State private var localOffset: Int = 0
    @State private var localHasMore: Bool = false
    @State private var isLoading: Bool = true
    @State private var isLoadingMoreLocal: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var mutationBannerTask: Task<Void, Never>?

    @State private var selectedCard: TvMediaCard?
    @State private var selectedCustomList: TvCustomListSummary?

    init(isActiveTab: Bool = true) {
        self.isActiveTab = isActiveTab
    }

    private let pageSize = 36
    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    private var queryKey: String {
        "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(activeSection.rawValue)#\(mediaTypeFilter)#\(localTierFilter)#\(localSort)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let counts = libraryPayload?.counts

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if let mutationErrorBanner {
                    TransientErrorBanner(message: mutationErrorBanner)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 14)
                }

                Text("Mitt bibliotek")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, 14)

                // Primary 3-section switcher (uniform warm espresso pills)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        LunaPillButton(
                            LibrarySectionTab.watchlist.label,
                            badgeText: counts.map { String($0.watchlist) },
                            isSelected: activeSection == .watchlist
                        ) {
                            activeSection = .watchlist
                        }

                        LunaPillButton(
                            LibrarySectionTab.favorites.label,
                            badgeText: counts.map { String($0.favorites) },
                            isSelected: activeSection == .favorites
                        ) {
                            activeSection = .favorites
                        }

                        LunaPillButton(
                            LibrarySectionTab.local.label,
                            badgeText: counts.map { String($0.localTotal) },
                            isSelected: activeSection == .local
                        ) {
                            activeSection = .local
                        }

                        Rectangle()
                            .fill(LunaTheme.warmBorder)
                            .frame(width: 1, height: 26)
                            .padding(.horizontal, 6)

                        mediaTypePills
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()

                // Secondary filter bar for "Lokalt på NAS"
                if activeSection == .local {
                    localTierAndSortBar(counts: counts)
                }

                // Custom MediaLogg shelves strip inside "Favoritter & Lister"
                if activeSection == .favorites,
                   let customLists = libraryPayload?.customLists,
                   !customLists.isEmpty {
                    customShelvesSection(customLists)
                }

                // Active Grid Content
                if isLoading && libraryPayload == nil {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter bibliotek fra NVMe-indeks…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 56)
                } else if let errorMessage, libraryPayload == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadLibrary(forceNetwork: true) }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else {
                    sectionGrid(client: client)
                }
            }
            .padding(.bottom, 72)
        }
        .lunaRootScrollTopBarTracking(tab: .library)
        .safeAreaPadding(.top, LunaTopBarView.contentTopPadding)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedCustomList) { list in
            CustomRowBrowseView(title: list.name, pathOrRowId: list.browsePath)
        }
        .task(id: queryKey) {
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadLibrary(forceNetwork: false)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            Task { await loadLibrary(forceNetwork: true) }
        }
        .onChange(of: isActiveTab) { _, active in
            guard active else { return }
            let cached = LibraryBrowseMemoryCache.shared.snapshot(for: queryKey)
            let isFresh = TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: cached != nil,
                lastValidatedAt: cached?.fetchedAt ?? .distantPast,
                cachedRefreshNonce: cached?.refreshNonce ?? lastSeenRefreshNonce,
                currentRefreshNonce: sessionStore.homeRefreshNonce
            )
            guard !isFresh else { return }
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            Task { await loadLibrary(forceNetwork: true) }
        }
        .onDisappear {
            mutationBannerTask?.cancel()
        }
    }

    @ViewBuilder
    private var mediaTypePills: some View {
        LunaPillButton("Alle typer", isSelected: mediaTypeFilter == "all", prominence: .subtleChip) {
            mediaTypeFilter = "all"
        }
        LunaPillButton("Filmer", isSelected: mediaTypeFilter == "movie", prominence: .subtleChip) {
            mediaTypeFilter = "movie"
        }
        LunaPillButton("Serier", isSelected: mediaTypeFilter == "series", prominence: .subtleChip) {
            mediaTypeFilter = "series"
        }
    }

    private func localTierAndSortBar(counts: TvLibraryCounts?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                LunaPillButton(
                    "Alle lokale",
                    badgeText: counts.map { String($0.localTotal) },
                    isSelected: localTierFilter == "all",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "all"
                }

                LunaPillButton(
                    "Hurtiglagring (NVMe)",
                    badgeText: counts.map { String($0.nvme) },
                    isSelected: localTierFilter == "nvme",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "nvme"
                }

                LunaPillButton(
                    "Arkiv",
                    badgeText: counts.map { String($0.archive) },
                    isSelected: localTierFilter == "archive",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "archive"
                }

                Rectangle()
                    .fill(LunaTheme.warmBorder)
                    .frame(width: 1, height: 26)
                    .padding(.horizontal, 6)

                LunaPillButton("Nylig lagt til", isSelected: localSort == "recent", prominence: .subtleChip) {
                    localSort = "recent"
                }
                LunaPillButton("Høyest rangert", isSelected: localSort == "rating", prominence: .subtleChip) {
                    localSort = "rating"
                }
                LunaPillButton("A–Å", isSelected: localSort == "title", prominence: .subtleChip) {
                    localSort = "title"
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
    }

    private func customShelvesSection(_ lists: [TvCustomListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Egne samlinger fra MediaLogg")
                .font(.title3.weight(.bold))
                .foregroundStyle(LunaTheme.linen)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(lists) { list in
                        LunaPillButton(
                            list.name,
                            badgeText: list.itemCount > 0 ? String(list.itemCount) : nil
                        ) {
                            selectedCustomList = list
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func sectionGrid(client: LunaCoreClient?) -> some View {
        let activeItems: [TvMediaCard] = {
            switch activeSection {
            case .watchlist:
                return libraryPayload?.watchlist ?? []
            case .favorites:
                return libraryPayload?.favorites ?? []
            case .local:
                return localItems
            }
        }()

        if activeItems.isEmpty {
            LibraryEmptyStateView(
                headline: emptyStateHeadline,
                subtitle: emptyStateSubtitle
            )
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 48)
        } else {
            LazyVGrid(columns: columns, spacing: 42) {
                ForEach(activeItems) { card in
                    PosterCardView(
                        card: card,
                        client: client,
                        width: 244,
                        showStorageBadge: activeSection == .local,
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
                        if activeSection == .local,
                           card.id == localItems.last?.id,
                           localHasMore,
                           !isLoadingMoreLocal {
                            Task { await loadMoreLocalItems() }
                        }
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)

            if activeSection == .local && isLoadingMoreLocal {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        }
    }

    private var emptyStateHeadline: String {
        switch activeSection {
        case .watchlist:
            return "Ingen titler i «Huskeliste» akkurat nå."
        case .favorites:
            return "Ingen lagrede favoritter ennå."
        case .local:
            return "Ingen lokale filer matchet filteret."
        }
    }

    private var emptyStateSubtitle: String {
        switch activeSection {
        case .watchlist:
            return "Trykk på «Huskeliste» inne på en film eller serie for å samle det dere vil se her."
        case .favorites:
            return "Trykk på «Favoritt» inne på favorittfilmer og -serier for rask tilgang."
        case .local:
            return "Lokal filoversikt leses rett fra NVMe-indeksen uten å vekke arkivdiskene."
        }
    }

    private func persistLibrarySnapshot(for key: String, payload: TvLibraryResponse, fetchedAt: Date? = nil) {
        let existing = LibraryBrowseMemoryCache.shared.snapshot(for: key)
        LibraryBrowseMemoryCache.shared.store(
            LibraryBrowseSnapshot(
                payload: payload,
                localItems: localItems,
                localOffset: localOffset,
                localHasMore: localHasMore,
                fetchedAt: fetchedAt ?? existing?.fetchedAt ?? Date(),
                refreshNonce: sessionStore.homeRefreshNonce
            ),
            for: key
        )
    }

    private func loadLibrary(forceNetwork: Bool = false) async {
        guard let client = sessionStore.makeClient() else { return }
        let targetKey = queryKey
        let currentNonce = sessionStore.homeRefreshNonce

        if let cached = LibraryBrowseMemoryCache.shared.snapshot(for: targetKey) {
            libraryPayload = cached.payload
            localItems = cached.localItems
            localOffset = cached.localOffset
            localHasMore = cached.localHasMore
            isLoading = false

            if !forceNetwork,
               TabContentFreshnessPolicy.isCacheFresh(
                   hasCachedContent: true,
                   lastValidatedAt: cached.fetchedAt,
                   cachedRefreshNonce: cached.refreshNonce,
                   currentRefreshNonce: currentNonce
               ) {
                errorMessage = nil
                return
            }
        } else {
            isLoading = true
        }
        errorMessage = nil

        do {
            let res = try await client.fetchLibrary(
                section: activeSection.rawValue,
                tier: localTierFilter,
                mediaType: mediaTypeFilter,
                sort: localSort,
                offset: 0,
                limit: pageSize
            )
            guard !Task.isCancelled, queryKey == targetKey else { return }
            libraryPayload = res
            localItems = res.localItems
            localOffset = res.localItems.count
            localHasMore = res.localHasMore ?? false
            persistLibrarySnapshot(for: targetKey, payload: res, fetchedAt: Date())
        } catch LunaCoreError.unauthorized {
            LibraryBrowseMemoryCache.shared.clear()
            sessionStore.unpairDevice()
        } catch {
            if libraryPayload == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadMoreLocalItems() async {
        guard !isLoadingMoreLocal, localHasMore, let client = sessionStore.makeClient() else { return }
        let targetKey = queryKey
        isLoadingMoreLocal = true
        defer { isLoadingMoreLocal = false }

        guard let res = try? await client.fetchLibrary(
            section: "local",
            tier: localTierFilter,
            mediaType: mediaTypeFilter,
            sort: localSort,
            offset: localOffset,
            limit: pageSize
        ), queryKey == targetKey else {
            return
        }

        let existing = Set(localItems.map(\.id))
        let fresh = res.localItems.filter { !existing.contains($0.id) }
        localItems.append(contentsOf: fresh)
        localOffset += res.localItems.count
        localHasMore = res.localHasMore ?? false
        if let payload = libraryPayload {
            persistLibrarySnapshot(for: targetKey, payload: payload)
        }
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

    private func markLocalMutationAndReload() async {
        LibraryBrowseMemoryCache.shared.clear()
        lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
        sessionStore.notifyContentMutated()
        await loadLibrary(forceNetwork: true)
    }

    private func toggleWatchlist(_ card: TvMediaCard) async {
        let nextListed = !(card.inWatchlist ?? false)
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextListed, sessionStore: sessionStore) {
                await markLocalMutationAndReload()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func toggleFavorite(_ card: TvMediaCard) async {
        let nextFavorite = !(card.isFavorite ?? false)
        do {
            if try await MediaCardMutator.setFavorite(for: card, favorite: nextFavorite, sessionStore: sessionStore) {
                await markLocalMutationAndReload()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func toggleWatched(_ card: TvMediaCard) async {
        let nextWatched = !(card.progress?.watched ?? false)
        do {
            if try await MediaCardMutator.toggleWatched(for: card, watched: nextWatched, sessionStore: sessionStore) {
                await markLocalMutationAndReload()
            }
        } catch {
            showMutationError(error)
        }
    }
}

private struct LibraryEmptyStateView: View {
    let headline: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LunaTheme.linen)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(LunaTheme.muted)
        }
        .padding(28)
        .frame(maxWidth: 880, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                .fill(LunaTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                .strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1)
        )
    }
}
