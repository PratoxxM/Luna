import SwiftUI

private enum LibrarySectionTab: String, CaseIterable, Identifiable, Sendable {
    case watchlist = "watchlist"
    case lists = "lists"
    case local = "local"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watchlist: return "Huskeliste"
        case .lists: return "Egne lister"
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
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

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
    @State private var pendingDeleteTarget: TvDeleteRequestTarget?
    @State private var modalToken = UUID()
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0

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
                }

                Text("Mitt bibliotek")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

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
                            LibrarySectionTab.lists.label,
                            badgeText: counts.map { String($0.customLists) },
                            isSelected: activeSection == .lists
                        ) {
                            activeSection = .lists
                        }

                        LunaPillButton(
                            LibrarySectionTab.local.label,
                            badgeText: counts.map { String($0.localTotal) },
                            isSelected: activeSection == .local
                        ) {
                            activeSection = .local
                        }

                        if activeSection != .lists {
                            Rectangle()
                                .fill(LunaTheme.warmBorder)
                                .frame(width: 1, height: 26)
                                .padding(.horizontal, 6)

                            mediaTypePills
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()

                // Secondary filter bar for "Lokalt på NAS"
                if activeSection == .local {
                    localTierAndSortBar(counts: counts)
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
                            .foregroundStyle(LunaTheme.danger)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            scheduleReloadLibrary(forceNetwork: true)
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if activeSection == .lists {
                    customListsGridSection(libraryPayload?.customLists ?? [])
                } else {
                    sectionGrid(client: client)
                }
            }
            .padding(.bottom, 72)
        }
        .contentMargins(.zero, for: .scrollContent)
        .ignoresSafeArea(edges: .horizontal)
        .lunaRootScrollTopBarTracking(tab: .library)
        .safeAreaPadding(.top, LunaTopBarView.contentTopPadding)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedCustomList) { list in
            CustomRowBrowseView(
                title: list.name,
                pathOrRowId: list.browsePath,
                isOngoingList: list.sourceType == "active_series"
                    || list.id.contains("pagaende")
                    || list.id.contains("active")
                    || list.id.contains("continue")
            )
        }
        .sheet(item: $pendingDeleteTarget) { target in
            DetailDeleteSheetView(
                target: target,
                onDeleted: { _ in
                    localItems.removeAll { $0.itemId == target.itemId }
                    pendingDeleteTarget = nil
                    Task { await markLocalMutationAndReload() }
                },
                onCancel: {
                    pendingDeleteTarget = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .onChange(of: pendingDeleteTarget != nil) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .task(id: queryKey) {
            reloadTask?.cancel()
            reloadTask = nil
            reloadGeneration &+= 1
            let gen = reloadGeneration
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadLibrary(forceNetwork: false, generation: gen)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            scheduleReloadLibrary(forceNetwork: true)
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
            scheduleReloadLibrary(forceNetwork: true)
        }
        .onDisappear {
            mutationBannerTask?.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            if pendingDeleteTarget == nil {
                subpageVisibility.leaveModal(modalToken)
            }
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
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func customListsGridSection(_ lists: [TvCustomListSummary]) -> some View {
        if lists.isEmpty {
            LibraryEmptyStateView(
                headline: emptyStateHeadline,
                subtitle: emptyStateSubtitle
            )
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 48)
        } else {
            let listColumns = [
                GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 26)
            ]
            LazyVGrid(columns: listColumns, spacing: 24) {
                ForEach(lists) { list in
                    LibraryCustomListTileButton(list: list) {
                        selectedCustomList = list
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func sectionGrid(client: LunaCoreClient?) -> some View {
        let activeItems: [TvMediaCard] = {
            switch activeSection {
            case .watchlist:
                return libraryPayload?.watchlist ?? []
            case .lists:
                return []
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
                            onRequestDelete: activeSection == .local ? {
                                pendingDeleteTarget = TvDeleteRequestTarget(
                                    kind: card.mediaType,
                                    itemId: card.itemId,
                                    tmdbId: card.ids.tmdb,
                                    tvdbId: card.ids.tvdb,
                                    title: card.title,
                                    subtitle: card.year.map(String.init),
                                    scope: card.mediaType == "series" ? .series : .title
                                )
                            } : nil
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
        case .lists:
            return "Ingen egne lister ennå."
        case .local:
            return "Ingen lokale filer matchet filteret."
        }
    }

    private var emptyStateSubtitle: String {
        switch activeSection {
        case .watchlist:
            return "Trykk på «Huskeliste» inne på en film eller serie for å samle det dere vil se her."
        case .lists:
            return "Opprett egne lister eller temahylla i LunaCore Web så dukker de opp her."
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

    private func scheduleReloadLibrary(forceNetwork: Bool) {
        reloadTask?.cancel()
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor in
            await loadLibrary(forceNetwork: forceNetwork, generation: gen)
            if reloadGeneration == gen {
                reloadTask = nil
            }
        }
    }

    private func loadLibrary(forceNetwork: Bool = false, generation: UInt64? = nil) async {
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
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration), queryKey == targetKey else { return }
            libraryPayload = res
            localItems = res.localItems
            localOffset = res.localItems.count
            localHasMore = res.localHasMore ?? false
            persistLibrarySnapshot(for: targetKey, payload: res, fetchedAt: Date())
        } catch is CancellationError {
            return
        } catch LunaCoreError.unauthorized {
            LibraryBrowseMemoryCache.shared.clear()
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if libraryPayload == nil {
                errorMessage = error.localizedDescription
            }
        }
        if generation == nil || generation == reloadGeneration {
            isLoading = false
        }
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

private struct LibraryCustomListTileButton: View {
    let list: TvCustomListSummary
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private var kindLabel: String {
        switch list.mediaType?.lowercased() {
        case "movie": return "Filmer"
        case "series": return "Serier"
        default: return "Filmer & Serier"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(LunaTheme.amber)
                    .frame(width: 44, height: 44)
                    .background(LunaTheme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(1)

                    Text(list.itemCount > 0 ? "\(kindLabel) · \(LunaCopy.pinnedCount(list.itemCount))" : kindLabel)
                        .font(.caption)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.muted)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.focusGoldBorder : LunaTheme.warmBorderSubtle,
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.84), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
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
