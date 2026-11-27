import SwiftUI

struct SearchView: View {
    private enum SearchControlFocus: Hashable {
        case kindFilter(TvSearchKindFilter)
        case recent(String)
        case retry
        case emptyReset
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let initialQuery: String
    let isRootTab: Bool
    let isActiveTab: Bool
    let previewFocusFirstResult: Bool
    let previewFocusSearchField: Bool

    @State private var viewModel: SearchViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var subpageToken = UUID()
    @State private var selectedCard: TvMediaCard?
    @State private var queryFocusNonce: Int = 0

    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @State private var didApplyPreviewResultFocus: Bool = false

    @FocusState private var isQueryFieldFocused: Bool
    @FocusState private var controlFocus: SearchControlFocus?
    @Namespace private var searchKindFocusNamespace

    private let columns = LunaTheme.posterGridColumns

    init(
        viewModel: SearchViewModel? = nil,
        initialQuery: String = "",
        isRootTab: Bool = false,
        isActiveTab: Bool = true,
        previewFocusFirstResult: Bool = false,
        previewFocusSearchField: Bool = false
    ) {
        self.initialQuery = initialQuery
        self.isRootTab = isRootTab
        self.isActiveTab = isActiveTab
        self.previewFocusFirstResult = previewFocusFirstResult
        self.previewFocusSearchField = previewFocusSearchField
        _viewModel = State(
            initialValue: viewModel ?? SearchViewModel(
                initialQuery: initialQuery,
                isRootTab: isRootTab
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let client = sessionStore.makeClient()
        let trimmedQuery = viewModel.trimmedQuery
        let results = viewModel.results

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                if !isRootTab {
                    Text("Søk")
                        .font(LunaTheme.Font.pageTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                HStack(spacing: 14) {
                    LunaTextField(
                        "Film, serie eller person",
                        text: $viewModel.query,
                        leadingSystemImage: "magnifyingglass",
                        returnKeyType: .search,
                        onEditingEnded: {
                            isQueryFieldFocused = true
                        }
                    )
                    .focused($isQueryFieldFocused)
                    .lunaRequestDirectFocus(nonce: queryFocusNonce, isFocused: $isQueryFieldFocused)

                    if !viewModel.query.isEmpty {
                        LunaIconButton(systemImage: "xmark", accessibilityLabel: "Tøm søk") {
                            clearSearchKeepingFieldFocus()
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .focusSection()
                .onMoveCommand { direction in
                    if direction == .down {
                        controlFocus = .kindFilter(viewModel.selectedKind)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(TvSearchKindFilter.allCases) { kind in
                        let isSelected = viewModel.selectedKind == kind
                        LunaPillButton(
                            kind.label,
                            isSelected: isSelected,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            guard viewModel.selectedKind != kind else { return }
                            viewModel.selectedKind = kind
                        }
                        .focused($controlFocus, equals: .kindFilter(kind))
                        .prefersDefaultFocus(isSelected, in: searchKindFocusNamespace)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 4)
                .focusScope(searchKindFocusNamespace)
                .focusSection()
                .onMoveCommand { direction in
                    if direction == .down {
                        focusFirstResultOrHistory(trimmedQuery: trimmedQuery)
                    } else if direction == .up {
                        isQueryFieldFocused = true
                        queryFocusNonce &+= 1
                    }
                }

                if trimmedQuery.count < 2 {
                    if !viewModel.recentSearches.isEmpty {
                        VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
                            LunaSectionHeader(title: "Tidligere søk") {
                                LunaPillButton("Tøm", prominence: .subtleChip, size: .compact) {
                                    viewModel.clearRecentSearches(session: sessionStore)
                                }
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(viewModel.recentSearches, id: \.self) { term in
                                        LunaPillButton(term, prominence: .glassPill, size: .compact) {
                                            viewModel.query = term
                                        }
                                        .focused($controlFocus, equals: .recent(term))
                                    }
                                }
                                .padding(.horizontal, LunaTheme.horizontalGutter)
                                .padding(.vertical, 6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentMargins(.zero, for: .scrollContent)
                            .scrollClipDisabled()
                            .ignoresSafeArea(.container, edges: .horizontal)
                            .focusSection()
                        }
                    }
                } else {
                    if !results.isEmpty {
                        Text(viewModel.resultsSummaryText)
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.muted)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    if viewModel.isSearching && results.isEmpty {
                        LunaLoadingRow(message: "Søker…")
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                    } else if let errorMessage = viewModel.errorMessage, results.isEmpty {
                        LunaInlineError(message: errorMessage) {
                            viewModel.triggerRetry()
                        }
                        .focused($controlFocus, equals: .retry)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 12)
                    } else if !viewModel.isSearching && results.isEmpty {
                        LunaEmptyState(
                            headline: "Fant ikke «\(trimmedQuery)»",
                            actionTitle: "Tøm søk",
                            actionSymbol: "xmark.circle",
                            actionProminence: .glassPill
                        ) {
                            clearSearchKeepingFieldFocus()
                        }
                        .focused($controlFocus, equals: .emptyReset)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 48)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: LunaTokens.Layout.gridRowGap) {
                            ForEach(results) { card in
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
                                        }
                                    )
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.bottom, 72)
                        .focusSection()
                    }
                }
            }
            .padding(.top, isRootTab ? LunaTokens.Layout.contentTop : LunaTokens.Layout.subpageTop)
            .padding(.bottom, 72)
        }
        .scrollPosition($scrollPosition)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .lunaRootScrollTopBarTracking(tab: .search, isEnabled: isRootTab)
        .onChange(of: scrollToTopNonce) { _, _ in
            guard isRootTab, isActiveTab else { return }
            withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .onChange(of: contentEntryFocusNonce) { _, _ in
            guard isRootTab, isActiveTab else { return }
            scrollPosition.scrollTo(edge: .top)
            queryFocusNonce &+= 1
        }
        .lunaBottomToast(message: $viewModel.mutationErrorBanner, tone: .danger)
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
            viewModel.loadRecentSearches(session: sessionStore)
            if !isRootTab {
                subpageVisibility.enterSubpage(subpageToken)
            }
            if previewFocusSearchField {
                isQueryFieldFocused = true
                queryFocusNonce &+= 1
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    isQueryFieldFocused = true
                    queryFocusNonce &+= 1
                }
            }
        }
        .task(id: "\(trimmedQuery)#\(viewModel.selectedKind.rawValue)#\(viewModel.searchRetryNonce)#\(sessionStore.homeRefreshNonce)#active:\(isActiveTab)") {
            await viewModel.handleSearchTrigger(session: sessionStore, isActiveTab: isActiveTab)
            if previewFocusFirstResult, !didApplyPreviewResultFocus, let firstID = viewModel.results.first?.id {
                didApplyPreviewResultFocus = true
                entryCardID = firstID
                cardFocusNonce &+= 1
                try? await Task.sleep(nanoseconds: 120_000_000)
                if !Task.isCancelled {
                    cardFocusNonce &+= 1
                }
            }
        }
        .onDisappear {
            viewModel.cancelAllTasks()
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: isRootTab,
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    private func focusFirstResultOrHistory(trimmedQuery: String) {
        if trimmedQuery.count < 2 {
            if let firstRecent = viewModel.recentSearches.first {
                controlFocus = .recent(firstRecent)
            }
        } else if !viewModel.results.isEmpty {
            if !mountedTracker.hasAnyMounted, let firstID = viewModel.results.first?.id {
                scrollPosition.scrollTo(id: firstID, anchor: .top)
            }
            if let resolvedID = mountedTracker.resolveEntryID(orderedIDs: viewModel.results.map(\.id)) {
                entryCardID = resolvedID
                cardFocusNonce &+= 1
            }
        } else if viewModel.errorMessage != nil {
            controlFocus = .retry
        } else if !viewModel.isSearching {
            controlFocus = .emptyReset
        }
    }

    private func clearSearchKeepingFieldFocus() {
        isQueryFieldFocused = true
        queryFocusNonce &+= 1
        viewModel.clearQuery()
        Task { @MainActor in
            await Task.yield()
            if !isQueryFieldFocused {
                isQueryFieldFocused = true
            }
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if !isQueryFieldFocused && controlFocus == nil {
                    isQueryFieldFocused = true
                } else {
                    return
                }
            }
        }
    }
}
