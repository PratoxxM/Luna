import SwiftUI

struct LibraryHubView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce

    let isActiveTab: Bool
    var onSelectTab: ((MainNavigationTab) -> Void)? = nil

    @State private var activeSection: LibrarySidebarSection = .localAll
    @State private var localTierFilter: String = "all"
    @State private var localSort: String = "recent"
    @State private var watchlistTypeFilter: String = "all"

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
    @FocusState private var focusedSidebarSection: LibrarySidebarSection?
    @Namespace private var sidebarFocusNamespace

    init(isActiveTab: Bool = true, onSelectTab: ((MainNavigationTab) -> Void)? = nil) {
        self.isActiveTab = isActiveTab
        self.onSelectTab = onSelectTab
    }

    private let pageSize = 36
    private let columns = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.posterW), spacing: LunaTokens.Layout.cardGap, alignment: .topLeading),
        count: 4
    )

    private var activeMediaTypeFilter: String {
        activeSection == .watchlist ? watchlistTypeFilter : activeSection.apiMediaType
    }

    private var queryKey: String {
        "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(activeSection.rawValue)#\(activeMediaTypeFilter)#\(localTierFilter)#\(localSort)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let counts = libraryPayload?.counts

        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(LibrarySidebarSection.allCases) { section in
                    LibrarySidebarRowButton(
                        section: section,
                        countText: countLabel(for: section, counts: counts),
                        isSelected: activeSection == section
                    ) {
                        activeSection = section
                    }
                    .focused($focusedSidebarSection, equals: section)
                    .prefersDefaultFocus(activeSection == section, in: sidebarFocusNamespace)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 280, alignment: .topLeading)
            .padding(.top, 12)
            .defaultFocus($focusedSidebarSection, activeSection as LibrarySidebarSection?, priority: .userInitiated)
            .focusScope(sidebarFocusNamespace)
            .focusSection()

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear
                            .frame(height: 0)
                            .id("luna-scroll-top")

                        if isLoading && libraryPayload == nil {
                        HStack(spacing: 16) {
                            ProgressView()
                            Text("Henter samlingen…")
                                .font(LunaTheme.Font.subtitle)
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        .padding(.vertical, 56)
                    } else if let errorMessage, libraryPayload == nil {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(errorMessage)
                                .font(LunaTheme.Font.body)
                                .foregroundStyle(LunaTheme.danger)
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                scheduleReloadLibrary(forceNetwork: true)
                            }
                        }
                    } else if activeSection == .lists {
                        customListsGridSection(libraryPayload?.customLists ?? [])
                    } else {
                        sectionGrid(client: client)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 84)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .lunaRootScrollTopBarTracking(tab: .library)
            .focusSection()
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isActiveTab else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, LunaTopBarView.contentTopPadding)
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .ignoresSafeArea()
        .defaultFocus($focusedSidebarSection, activeSection as LibrarySidebarSection?, priority: .userInitiated)
        .onAppear {
            if focusedSidebarSection == nil {
                focusedSidebarSection = activeSection
            }
        }
        .overlay(alignment: .topTrailing) {
            if let mutationErrorBanner {
                TransientErrorBanner(message: mutationErrorBanner)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, LunaTopBarView.contentTopPadding + 8)
                    .allowsHitTesting(false)
            }
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedCustomList) { list in
            CustomRowBrowseView(
                title: list.name,
                pathOrRowId: list.browsePath,
                isOngoingList: CustomRowContextPolicy.isOngoingList(
                    explicitFlag: false,
                    rowId: list.id,
                    sourceKind: list.sourceType
                )
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
                currentRefreshNonce: sessionStore.homeRefreshNonce,
                freshnessInterval: DeviceHardwareCapabilities.isHighMemoryDevice ? 600 : TabContentFreshnessPolicy.defaultFreshnessInterval
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

    private func countLabel(for section: LibrarySidebarSection, counts: TvLibraryCounts?) -> String? {
        guard let counts else { return nil }
        switch section {
        case .localAll: return counts.localTotal > 0 ? String(counts.localTotal) : nil
        case .localMovies:
            if let movies = counts.localMovies, movies > 0 { return String(movies) }
            return nil
        case .localSeries:
            if let series = counts.localSeries, series > 0 { return String(series) }
            return nil
        case .watchlist: return counts.watchlist > 0 ? String(counts.watchlist) : nil
        case .lists: return counts.customLists > 0 ? String(counts.customLists) : nil
        }
    }

    @ViewBuilder
    private func customListsGridSection(_ lists: [TvCustomListSummary]) -> some View {
        if lists.isEmpty {
            emptyStateCard
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
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func sectionGrid(client: LunaCoreClient?) -> some View {
        let activeItems: [TvMediaCard] = activeSection == .watchlist
            ? (libraryPayload?.watchlist ?? [])
            : localItems

        if activeItems.isEmpty {
            emptyStateCard
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 34) {
                ForEach(activeItems) { card in
                    PosterCardView(
                        card: card,
                        client: client,
                        width: LunaTokens.Layout.posterW,
                        showStorageBadge: activeSection != .watchlist,
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
                            onRequestDelete: activeSection != .watchlist ? {
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
                        if activeSection != .watchlist,
                           card.id == localItems.last?.id,
                           localHasMore,
                           !isLoadingMoreLocal {
                            Task { await loadMoreLocalItems() }
                        }
                    }
                }
            }

            if activeSection != .watchlist && isLoadingMoreLocal {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        }
    }

    @ViewBuilder
    private var emptyStateCard: some View {
        let hasActiveLocalFilter = activeSection != .watchlist && activeSection != .lists && localTierFilter != "all"
        let buttonTitle: String? = hasActiveLocalFilter
            ? "Vis alle lokale"
            : (onSelectTab != nil ? activeSection.emptyActionTitle : nil)

        LibraryEmptyStateView(
            headline: activeSection.emptyHeadline,
            subtitle: activeSection.emptySubtitle,
            actionTitle: buttonTitle,
            actionSymbol: activeSection == .localSeries ? "tv" : "film",
            onAction: buttonTitle == nil ? nil : {
                if hasActiveLocalFilter {
                    localTierFilter = "all"
                } else {
                    onSelectTab?(activeSection.emptyTargetTab)
                }
            }
        )
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
                   currentRefreshNonce: currentNonce,
                   freshnessInterval: DeviceHardwareCapabilities.isHighMemoryDevice ? 600 : TabContentFreshnessPolicy.defaultFreshnessInterval
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
                section: activeSection.apiSection,
                tier: localTierFilter,
                mediaType: activeMediaTypeFilter,
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
                errorMessage = LunaCopy.friendlyErrorMessage(error)
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
            mediaType: activeMediaTypeFilter,
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
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
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
