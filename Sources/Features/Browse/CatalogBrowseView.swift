import SwiftUI

struct CatalogBrowseView: View {
    private enum CatalogFallbackFocus: Hashable {
        case retry
        case emptyReset
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let mediaType: String
    let initialGenre: TvGenreChip?
    let isActiveTab: Bool
    let isRootTab: Bool

    @State private var viewModel: CatalogBrowseViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var subpageToken = UUID()
    @State private var selectedCard: TvMediaCard?
    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @FocusState private var fallbackFocus: CatalogFallbackFocus?
    @Namespace private var catalogGridNamespace

    private let columns = LunaTheme.posterGridColumns

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
        CatalogBrowseViewModel.makeCacheKey(
            serverBaseURL: serverBaseURL,
            mediaType: mediaType,
            genreSlug: genreSlug,
            sort: sort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
    }

    init(
        viewModel: CatalogBrowseViewModel? = nil,
        mediaType: String,
        initialGenre: TvGenreChip?,
        isActiveTab: Bool = true,
        isRootTab: Bool = false
    ) {
        self.mediaType = mediaType
        self.initialGenre = initialGenre
        self.isActiveTab = isActiveTab
        self.isRootTab = isRootTab
        _viewModel = State(
            initialValue: viewModel ?? CatalogBrowseViewModel(
                mediaType: mediaType,
                initialGenre: initialGenre,
                isRootTab: isRootTab
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let client = sessionStore.makeClient()
        let items = viewModel.items

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                if !isRootTab {
                    Text(viewModel.headerTitle)
                        .font(LunaTheme.Font.pageTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                CatalogFilterBarView(
                    categoryTitle: viewModel.headerTitle,
                    availableGenres: viewModel.availableGenres,
                    selectedSort: $viewModel.selectedSort,
                    localOnly: $viewModel.localOnly,
                    unwatchedOnly: $viewModel.unwatchedOnly,
                    selectedGenreSlug: $viewModel.selectedGenreSlug,
                    selectedGenreLabel: $viewModel.selectedGenreLabel,
                    entryFocusNonce: contentEntryFocusNonce,
                    isEntryActive: isRootTab && isActiveTab,
                    onScrollToTop: {
                        scrollPosition.scrollTo(edge: .top)
                    },
                    onMoveDown: {
                        if !items.isEmpty {
                            if !mountedTracker.hasAnyMounted, let firstID = items.first?.id {
                                scrollPosition.scrollTo(id: firstID, anchor: .top)
                            }
                            if let resolvedID = mountedTracker.resolveEntryID(orderedIDs: items.map(\.id)) {
                                entryCardID = resolvedID
                                cardFocusNonce &+= 1
                            }
                        } else if viewModel.errorMessage != nil {
                            fallbackFocus = .retry
                        } else if viewModel.hasActiveFilters {
                            fallbackFocus = .emptyReset
                        }
                    }
                )

                if viewModel.isLoading && items.isEmpty {
                    LunaLoadingRow(message: "Henter utvalg…")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if let errorMessage = viewModel.errorMessage, items.isEmpty {
                    LunaInlineError(message: errorMessage) {
                        viewModel.scheduleReloadFirstPage(forceNetwork: true, session: sessionStore)
                    }
                    .focused($fallbackFocus, equals: .retry)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    let hasFilters = viewModel.hasActiveFilters
                    let emptyView = LunaEmptyState(
                        headline: "Ingen treff med disse filtrene",
                        actionTitle: hasFilters ? "Nullstill filtre" : nil,
                        actionSymbol: hasFilters ? "xmark" : nil,
                        actionProminence: .subtleChip,
                        onAction: hasFilters ? {
                            viewModel.resetFilters()
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
                                        Task { await viewModel.toggleWatched(card, session: sessionStore) }
                                    },
                                    onToggleWatchlist: {
                                        Task { await viewModel.toggleWatchlist(card, session: sessionStore) }
                                    }
                                )
                            }
                            .onAppear {
                                ArtworkPipeline.shared.prefetchUpcomingCards(
                                    in: items,
                                    afterIndex: idx,
                                    client: client
                                )
                                if idx >= prefetchThreshold && viewModel.hasMore && !viewModel.isLoadingMore {
                                    viewModel.scheduleLoadNextPage(session: sessionStore)
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.bottom, 32)
                    .focusSection()

                    if viewModel.isLoadingMore {
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
        .scrollPosition($scrollPosition)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .focusScope(catalogGridNamespace)
        .lunaRootScrollTopBarTracking(tab: viewModel.rootNavigationTab, isEnabled: isRootTab)
        .onChange(of: scrollToTopNonce) { _, _ in
            guard isRootTab, isActiveTab else { return }
            withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
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
        .task(id: "\(viewModel.reloadTriggerKey(for: sessionStore))#active:\(isActiveTab || !isRootTab)") {
            await viewModel.handleActivation(session: sessionStore, isActive: isActiveTab || !isRootTab)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            viewModel.handleHomeRefreshNonceChange(newNonce, isActiveTab: isActiveTab, session: sessionStore)
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
}
