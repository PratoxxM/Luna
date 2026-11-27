import SwiftUI

struct LibraryHubView: View {
    private enum LibraryFallbackFocus: Hashable {
        case retry
        case empty
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    var onSelectTab: ((MainNavigationTab) -> Void)? = nil

    @State private var viewModel: LibraryViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)

    @State private var selectedCard: TvMediaCard?
    @State private var selectedCustomList: TvLibraryCustomList?
    @State private var pendingDeleteTarget: TvDeleteRequestTarget?
    @State private var modalToken = UUID()
    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @State private var tierSortFocusNonce: Int = 0
    @State private var showSortSheet: Bool = false
    @State private var sortModalToken = UUID()

    @FocusState private var focusedCustomListID: String?
    @FocusState private var fallbackFocus: LibraryFallbackFocus?

    private let columns = LunaTheme.posterGridColumns

    init(
        viewModel: LibraryViewModel? = nil,
        isActiveTab: Bool = true,
        onSelectTab: ((MainNavigationTab) -> Void)? = nil
    ) {
        self.isActiveTab = isActiveTab
        self.onSelectTab = onSelectTab
        _viewModel = State(initialValue: viewModel ?? LibraryViewModel())
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let client = sessionStore.makeClient()
        let counts = viewModel.libraryPayload?.counts

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                LibraryFilterStripView(
                    counts: counts,
                    activeSection: $viewModel.activeSection,
                    didApplyInitialSectionFallback: $viewModel.didApplyInitialSectionFallback,
                    entryFocusNonce: contentEntryFocusNonce,
                    isEntryActive: isActiveTab,
                    onScrollToTop: {
                        scrollPosition.scrollTo(edge: .top)
                    },
                    onMoveDown: {
                        if viewModel.supportsTierAndSortFilters {
                            tierSortFocusNonce &+= 1
                        } else {
                            focusFirstLibraryContentItem()
                        }
                    }
                )

                if viewModel.supportsTierAndSortFilters {
                    LibraryTierAndSortStripView(
                        viewModel: viewModel,
                        focusRequestNonce: tierSortFocusNonce,
                        isEntryActive: isActiveTab,
                        onOpenSortSheet: {
                            showSortSheet = true
                        },
                        onMoveDown: {
                            focusFirstLibraryContentItem()
                        }
                    )
                }

                Group {
                    if viewModel.isLoading && viewModel.libraryPayload == nil {
                        LunaLoadingRow(message: "Henter samlingen…")
                    } else if let errorMessage = viewModel.errorMessage, viewModel.libraryPayload == nil {
                        LunaInlineError(message: errorMessage) {
                            viewModel.scheduleReloadLibrary(forceNetwork: true, session: sessionStore)
                        }
                        .focused($fallbackFocus, equals: .retry)
                    } else if viewModel.activeSection == .lists {
                        customListsSection()
                            .focusSection()
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
        .scrollPosition($scrollPosition)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .lunaRootScrollTopBarTracking(tab: .library)
        .onChange(of: scrollToTopNonce) { _, _ in
            guard isActiveTab else { return }
            withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .lunaBottomToast(message: $viewModel.mutationErrorBanner, tone: .danger)
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
        .sheet(isPresented: $showSortSheet) {
            LibrarySortPickerSheetView(
                selectedSort: viewModel.selectedSort,
                onSelectSort: { nextSort in
                    showSortSheet = false
                    if viewModel.selectedSort != nextSort {
                        viewModel.selectedSort = nextSort
                    }
                },
                onClose: {
                    showSortSheet = false
                }
            )
            .preferredColorScheme(.dark)
        }
        .onChange(of: showSortSheet) { _, isPresented in
            if isPresented {
                subpageVisibility.enterModal(sortModalToken)
            } else {
                subpageVisibility.leaveModal(sortModalToken)
            }
        }
        .sheet(item: $pendingDeleteTarget) { target in
            DetailDeleteSheetView(
                target: target,
                onDeleted: { _ in
                    viewModel.removeOptimisticLocalItem(itemId: target.itemId)
                    pendingDeleteTarget = nil
                    Task { await viewModel.markLocalMutationAndReload(session: sessionStore) }
                },
                onCancel: {
                    pendingDeleteTarget = nil
                }
            )
            .environment(sessionStore)
            .preferredColorScheme(.dark)
        }
        .onChange(of: pendingDeleteTarget != nil) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .task(id: "\(viewModel.queryKey(for: sessionStore))#active:\(isActiveTab)") {
            await viewModel.handleActivation(session: sessionStore, isActiveTab: isActiveTab)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            viewModel.handleHomeRefreshNonceChange(newNonce, isActiveTab: isActiveTab, session: sessionStore)
        }
        .onDisappear {
            viewModel.cancelAllTasks()
            if pendingDeleteTarget == nil && !showSortSheet {
                subpageVisibility.leaveModal(modalToken)
                subpageVisibility.leaveModal(sortModalToken)
            }
        }
    }

    private func focusFirstLibraryContentItem() {
        if viewModel.activeSection == .lists {
            if let firstList = viewModel.customLists.first {
                scrollPosition.scrollTo(id: firstList.id, anchor: .top)
                focusedCustomListID = firstList.id
            } else if viewModel.errorMessage != nil && viewModel.libraryPayload == nil {
                fallbackFocus = .retry
            }
            return
        }
        let activeItems = viewModel.activeMediaCards
        if !activeItems.isEmpty {
            if !mountedTracker.hasAnyMounted, let firstID = activeItems.first?.id {
                scrollPosition.scrollTo(id: firstID, anchor: .top)
            }
            if let resolvedID = mountedTracker.resolveEntryID(orderedIDs: activeItems.map(\.id)) {
                entryCardID = resolvedID
                cardFocusNonce &+= 1
            }
        } else if viewModel.errorMessage != nil && viewModel.libraryPayload == nil {
            fallbackFocus = .retry
        } else if onSelectTab != nil, viewModel.activeSection.emptyActionTitle != nil {
            fallbackFocus = .empty
        }
    }

    @ViewBuilder
    private func customListsSection() -> some View {
        let lists = viewModel.customLists
        if lists.isEmpty {
            emptyStateCard
        } else {
            LunaListGroup {
                ForEach(Array(lists.enumerated()), id: \.element.id) { idx, list in
                    LunaListRow(
                        title: list.name,
                        subtitle: customListSubtitle(for: list),
                        trailingText: LunaCopy.plural(list.itemCount, "tittel", "titler"),
                        showsChevron: true,
                        externalIsFocused: focusedCustomListID == list.id
                    ) {
                        selectedCustomList = list
                    }
                    .id(list.id)
                    .focused($focusedCustomListID, equals: list.id)

                    if idx < lists.count - 1 {
                        LunaListDivider()
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 32)
        }
    }

    private func customListSubtitle(for list: TvLibraryCustomList) -> String? {
        switch list.mediaType?.lowercased() {
        case "movie": return "Filmer"
        case "series", "tv": return "Serier"
        default: return nil
        }
    }

    @ViewBuilder
    private func sectionGrid(client: LunaCoreClient?) -> some View {
        let activeItems = viewModel.activeMediaCards

        if activeItems.isEmpty {
            emptyStateCard
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: LunaTokens.Layout.gridRowGap) {
                let prefetchThreshold = max(0, viewModel.localItems.count - 6)
                ForEach(Array(activeItems.enumerated()), id: \.element.id) { idx, card in
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
                                Task { await viewModel.toggleWatched(card, session: sessionStore) }
                            },
                            onToggleWatchlist: {
                                Task { await viewModel.toggleWatchlist(card, session: sessionStore) }
                            },
                            onRequestDelete: viewModel.activeSection != .watchlist ? {
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
                        ArtworkPipeline.shared.prefetchUpcomingCards(
                            in: activeItems,
                            afterIndex: idx,
                            client: client
                        )
                        if (viewModel.activeSection == .movies || viewModel.activeSection == .series),
                           idx >= prefetchThreshold,
                           viewModel.localHasMore,
                           !viewModel.isLoadingMoreLocal {
                            viewModel.scheduleLoadMoreLocalItems(session: sessionStore)
                        }
                    }
                }
            }
            .scrollTargetLayout()

            if (viewModel.activeSection == .movies || viewModel.activeSection == .series) && viewModel.isLoadingMoreLocal {
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
        let buttonTitle = onSelectTab != nil ? viewModel.activeSection.emptyActionTitle : nil
        let view = LunaEmptyState(
            headline: viewModel.activeSection.emptyHeadline,
            actionTitle: buttonTitle,
            actionSymbol: viewModel.activeSection.emptyActionSymbol,
            onAction: buttonTitle == nil ? nil : {
                onSelectTab?(viewModel.activeSection.emptyTargetTab)
            }
        )
        if buttonTitle != nil {
            view.focused($fallbackFocus, equals: .empty)
        } else {
            view
        }
    }
}

/// Focus-isolated horizontal filter pill strip so moving Siri Remote focus across library sections
/// updates only this strip's `@FocusState` (`0` re-evaluations of `LibraryHubView` / `LazyVGrid`).
private struct LibraryFilterStripView: View {
    let counts: TvLibraryCounts?
    @Binding var activeSection: LibraryFilterSection
    @Binding var didApplyInitialSectionFallback: Bool
    let entryFocusNonce: Int
    let isEntryActive: Bool
    let onScrollToTop: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void

    @FocusState private var focusedFilterPill: LibraryFilterSection?
    @Namespace private var filterFocusNamespace

    var body: some View {
        HStack(spacing: 14) {
            ForEach(LibraryFilterSection.allCases) { section in
                LunaPillButton(
                    section.pillTitle(counts: counts),
                    badgeText: section.pillBadgeText(counts: counts),
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
        .lunaEntryFocusTarget(
            nonce: entryFocusNonce,
            isActive: isEntryActive,
            focus: $focusedFilterPill,
            target: { activeSection },
            onTrigger: onScrollToTop
        )
        .onMoveCommand { direction in
            if direction == .down {
                onMoveDown()
            }
        }
    }
}

private struct LibraryTierAndSortStripView: View {
    @Bindable var viewModel: LibraryViewModel
    let focusRequestNonce: Int
    let isEntryActive: Bool
    let onOpenSortSheet: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void

    @FocusState private var focusedControl: String?
    @Namespace private var tierSortFocusNamespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(LibraryTierFilter.allCases) { tier in
                let isSelected = viewModel.selectedTier == tier
                let badge = viewModel.count(for: tier).map(String.init)
                LunaPillButton(
                    tier.label,
                    badgeText: badge,
                    isSelected: isSelected,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    guard viewModel.selectedTier != tier else { return }
                    viewModel.selectedTier = tier
                }
                .focused($focusedControl, equals: "tier-\(tier.rawValue)")
                .prefersDefaultFocus(isSelected, in: tierSortFocusNamespace)
            }

            Rectangle()
                .fill(LunaTheme.warmBorderStrong)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)

            LunaPillButton(
                viewModel.selectedSort.label,
                systemImage: "arrow.up.arrow.down",
                isSelected: viewModel.selectedSort != .recent,
                prominence: .glassPill,
                size: .compact
            ) {
                onOpenSortSheet()
            }
            .focused($focusedControl, equals: "sort-trigger")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .padding(.vertical, 4)
        .focusScope(tierSortFocusNamespace)
        .focusSection()
        .lunaEntryFocusTarget(
            nonce: focusRequestNonce,
            isActive: isEntryActive,
            focus: $focusedControl,
            target: { "tier-\(viewModel.selectedTier.rawValue)" },
            onTrigger: {}
        )
        .onMoveCommand { direction in
            if direction == .down {
                onMoveDown()
            }
        }
    }
}

private struct LibrarySortPickerSheetView: View {
    let selectedSort: LibrarySortOption
    let onSelectSort: (LibrarySortOption) -> Void
    let onClose: () -> Void

    @FocusState private var focusedSort: LibrarySortOption?
    @Namespace private var sortSheetNamespace

    var body: some View {
        LunaSheetContainer(
            title: "Sortering",
            subtitle: "Bibliotek",
            width: .narrow,
            maxHeight: 620,
            onClose: onClose
        ) {
            LunaListGroup(showsSurface: false) {
                let options = LibrarySortOption.allCases
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    let isSelected = option == selectedSort
                    LunaListRow(
                        title: option.label,
                        isSelected: isSelected,
                        externalIsFocused: focusedSort == option
                    ) {
                        onSelectSort(option)
                    }
                    .focused($focusedSort, equals: option)
                    .prefersDefaultFocus(isSelected, in: sortSheetNamespace)

                    if index < options.count - 1 {
                        LunaListDivider()
                    }
                }
            }
            .padding(.vertical, 4)
            .defaultFocus($focusedSort, selectedSort, priority: .userInitiated)
            .focusScope(sortSheetNamespace)
            .onAppear {
                focusedSort = selectedSort
            }
        }
    }
}
