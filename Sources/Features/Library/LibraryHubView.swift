import SwiftUI

struct LibraryHubView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    var onSelectTab: ((MainNavigationTab) -> Void)? = nil

    @State private var activeSection: LibraryFilterSection = .movies
    @State private var didApplyInitialSectionFallback: Bool = false

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
    @State private var pendingDeleteTarget: TvDeleteRequestTarget?
    @State private var modalToken = UUID()
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0
    @State private var entryFocusRetryTask: Task<Void, Never>?

    @FocusState private var focusedFilterPill: LibraryFilterSection?
    @FocusState private var focusedCardId: String?
    @Namespace private var filterFocusNamespace

    init(isActiveTab: Bool = true, onSelectTab: ((MainNavigationTab) -> Void)? = nil) {
        self.isActiveTab = isActiveTab
        self.onSelectTab = onSelectTab
    }

    private let pageSize = 36
    private let columns = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.gridPosterW), spacing: LunaTokens.Layout.gridCardGap, alignment: .topLeading),
        count: 6
    )

    private var queryKey: String {
        "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(activeSection.rawValue)#\(activeSection.apiMediaType)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let counts = libraryPayload?.counts

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    HStack(spacing: 14) {
                        ForEach(LibraryFilterSection.allCases) { section in
                            LunaPillButton(
                                section.label,
                                badgeText: section.countValue(from: counts).map(String.init),
                                isSelected: activeSection == section,
                                prominence: .glassPill,
                                size: .compact
                            ) {
                                didApplyInitialSectionFallback = true
                                guard activeSection != section else { return }
                                activeSection = section
                            }
                            .focused($focusedFilterPill, equals: section)
                            .prefersDefaultFocus(activeSection == section, in: filterFocusNamespace)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 6)
                    .focusScope(filterFocusNamespace)
                    .focusSection()
                    .onMoveCommand { direction in
                        if direction == .down {
                            focusFirstLibraryContentItem()
                        }
                    }

                    Group {
                        if isLoading && libraryPayload == nil {
                            LunaLoadingRow(message: "Henter samlingen…")
                        } else if let errorMessage, libraryPayload == nil {
                            LunaInlineError(message: errorMessage) {
                                scheduleReloadLibrary(forceNetwork: true)
                            }
                            .focused($focusedCardId, equals: "__library_retry__")
                        } else {
                            sectionGrid(client: client)
                                .focusSection()
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                }
                .padding(.top, LunaTopBarView.contentTopPadding)
                .padding(.bottom, 84)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .lunaRootScrollTopBarTracking(tab: .library)
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isActiveTab else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                }
            }
            .onChange(of: contentEntryFocusNonce) { _, _ in
                guard isActiveTab else { return }
                focusLibraryEntryPill(scrollProxy: scrollProxy)
            }
        }
        .lunaBottomToast(message: mutationErrorBanner, tone: .danger)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
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
            entryFocusRetryTask?.cancel()
            entryFocusRetryTask = nil
            mutationBannerTask?.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            if pendingDeleteTarget == nil {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    private func focusLibraryEntryPill(scrollProxy: ScrollViewProxy) {
        entryFocusRetryTask?.cancel()
        let targetPill = activeSection
        scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
        focusedFilterPill = targetPill
        entryFocusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, isActiveTab else { return }
                if focusedFilterPill == nil {
                    focusedFilterPill = targetPill
                } else {
                    return
                }
            }
        }
    }

    private func focusFirstLibraryContentItem() {
        let activeItems: [TvMediaCard] = activeSection == .watchlist
            ? (libraryPayload?.watchlist ?? [])
            : localItems
        if let firstID = activeItems.first?.id {
            focusedCardId = firstID
        } else if errorMessage != nil && libraryPayload == nil {
            focusedCardId = "__library_retry__"
        } else if onSelectTab != nil {
            focusedCardId = "__library_empty__"
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
            LazyVGrid(columns: columns, alignment: .leading, spacing: LunaTokens.Layout.gridRowGap) {
                ForEach(activeItems) { card in
                    PosterCardView(
                        card: card,
                        client: client,
                        width: LunaTokens.Layout.gridPosterW,
                        showStorageBadge: true,
                        showRestingTitle: true,
                        onSelect: {
                            selectedCard = card
                        },
                        onPlayShortcut: {
                            MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                        }
                    )
                    .id(card.id)
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
        let buttonTitle = onSelectTab != nil ? activeSection.emptyActionTitle : nil
        let view = LunaEmptyState(
            headline: activeSection.emptyHeadline,
            actionTitle: buttonTitle,
            actionSymbol: activeSection == .series ? "tv" : "film",
            onAction: buttonTitle == nil ? nil : {
                onSelectTab?(activeSection.emptyTargetTab)
            }
        )
        if buttonTitle != nil {
            view.focused($focusedCardId, equals: "__library_empty__")
        } else {
            view
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

    private func applyInitialSectionResolutionIfNeeded(counts: TvLibraryCounts) {
        let resolution = LibraryFilterSection.resolveInitialSection(
            counts: counts,
            didApplyInitialFallback: didApplyInitialSectionFallback,
            current: activeSection
        )
        didApplyInitialSectionFallback = resolution.didApplyInitialFallback
        if resolution.section != activeSection {
            activeSection = resolution.section
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
            applyInitialSectionResolutionIfNeeded(counts: cached.payload.counts)

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
                tier: "all",
                mediaType: activeSection.apiMediaType,
                sort: "recent",
                offset: 0,
                limit: pageSize
            )
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration), queryKey == targetKey else { return }
            libraryPayload = res
            localItems = res.localItems
            localOffset = res.localItems.count
            localHasMore = res.localHasMore ?? false
            persistLibrarySnapshot(for: targetKey, payload: res, fetchedAt: Date())
            applyInitialSectionResolutionIfNeeded(counts: res.counts)
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
            tier: "all",
            mediaType: activeSection.apiMediaType,
            sort: "recent",
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
