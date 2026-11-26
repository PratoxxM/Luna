import SwiftUI

struct HomeView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    var previewFocusPosterRow: Bool = false
    var allowInitialColdFocus: Bool = false

    @State private var viewModel: HomeViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)

    @State private var selectedCard: TvMediaCard?
    @State private var selectedSeeAllRow: TvShelfRow?
    @State private var sourcePickerContext: SourcePickerContext?
    @State private var modalToken = UUID()

    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardKey: String?
    @State private var entryFocusNonce: Int = 0
    @FocusState private var isRetryButtonFocused: Bool
    @Namespace private var homeFocusNamespace

    nonisolated static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        HomeViewModel.filterVisibleRows(rows)
    }

    nonisolated static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        HomeViewModel.prepareVisibleRows(from: payload)
    }

    init(
        viewModel: HomeViewModel? = nil,
        initialServerHost: String? = nil,
        initialRoomName: String = "Stua",
        initialHardwareProfile: String = "hdr10-512",
        isActiveTab: Bool = true,
        previewFocusPosterRow: Bool = false,
        allowInitialColdFocus: Bool = false
    ) {
        self.isActiveTab = isActiveTab
        self.previewFocusPosterRow = previewFocusPosterRow
        self.allowInitialColdFocus = allowInitialColdFocus
        _viewModel = State(
            initialValue: viewModel ?? HomeViewModel(
                initialServerHost: initialServerHost,
                initialRoomName: initialRoomName,
                initialHardwareProfile: initialHardwareProfile
            )
        )
    }

    private func resolveDefaultRow(in rows: [TvShelfRow]) -> TvShelfRow? {
        if previewFocusPosterRow,
           let posterRow = rows.first(where: { $0.rowStyle == "poster" && !$0.items.isEmpty }) {
            return posterRow
        }
        return rows.first(where: { !$0.items.isEmpty })
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let client = sessionStore.makeClient()
        let rows = viewModel.visibleRows
        let defaultRow = resolveDefaultRow(in: rows)
        let focusRowId = defaultRow?.rowId
        let focusTargetKey = defaultRow.flatMap { row in
            row.items.first.map { "\(row.rowId)#\($0.itemId)" }
        }
        let isPreviewMode = PreviewLaunchConfiguration.parse(arguments: ProcessInfo.processInfo.arguments) != nil

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.sectionGap) {
                if rows.isEmpty && viewModel.isInitialColdFetch {
                    LunaLoadingRow(message: "Henter innhold…")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                if let errorMessage = viewModel.errorMessage, rows.isEmpty {
                    LunaInlineError(message: errorMessage) {
                        viewModel.scheduleRevalidateHome(forceUnconditional: true, session: sessionStore)
                    }
                    .focused($isRetryButtonFocused)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                ForEach(rows) { row in
                    ShelfRowView(
                        row: row,
                        isDefaultFocusRow: row.rowId == focusRowId,
                        mountedTracker: mountedTracker,
                        entryCardKey: entryCardKey,
                        entryFocusNonce: entryFocusNonce,
                        focusNamespace: homeFocusNamespace,
                        client: client,
                        onSelectCard: { card in
                            selectedCard = card
                        },
                        onPlayContinueCard: { card in
                            MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                        },
                        onPickSourceForCard: { card in
                            openSourcePicker(for: card)
                        },
                        onToggleWatchlist: { card in
                            Task { await viewModel.toggleWatchlist(for: card, session: sessionStore) }
                        },
                        onMarkWatched: { card in
                            Task { await viewModel.markWatched(for: card, session: sessionStore) }
                        },
                        onRemoveFromOngoing: { card in
                            Task { await viewModel.removeFromOngoing(for: card, session: sessionStore) }
                        },
                        onRemoveFromList: { card, row in
                            Task { await viewModel.removeFromList(card, row: row, session: sessionStore) }
                        },
                        onSeeAllRow: { row in
                            selectedSeeAllRow = row
                        }
                    )
                    .id(row.rowId)
                }
            }
            .scrollTargetLayout()
            .padding(.top, LunaTopBarView.contentTopPadding)
            .padding(.bottom, 96)
        }
        .scrollPosition($scrollPosition)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .lunaRootScrollTopBarTracking(tab: .home)
        .onAppear {
            if (allowInitialColdFocus || previewFocusPosterRow), let focusTargetKey {
                entryCardKey = focusTargetKey
                entryFocusNonce &+= 1
            }
        }
        .task(id: previewFocusPosterRow ? focusRowId : nil) {
            guard previewFocusPosterRow, let focusRowId else { return }
            for delayNs: UInt64 in [220_000_000, 480_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                scrollPosition.scrollTo(id: focusRowId, anchor: .center)
                if let focusTargetKey {
                    entryCardKey = focusTargetKey
                    entryFocusNonce &+= 1
                }
            }
        }
        .onChange(of: focusTargetKey) { _, nextKey in
            if previewFocusPosterRow, let nextKey, let focusRowId {
                scrollPosition.scrollTo(id: focusRowId, anchor: .center)
                entryCardKey = nextKey
                entryFocusNonce &+= 1
            }
        }
        .onChange(of: scrollToTopNonce) { _, _ in
            guard isActiveTab else { return }
            withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .onChange(of: contentEntryFocusNonce) { _, _ in
            guard isActiveTab else { return }
            focusLeftmostHomeTarget(rows: rows)
        }
        .lunaBottomToast(message: $viewModel.mutationErrorMessage, tone: .danger)
        .focusSection()
        .focusScope(homeFocusNamespace)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedSeeAllRow) { row in
            let isOngoing = CustomRowContextPolicy.isOngoingList(
                explicitFlag: false,
                rowId: row.rowId,
                sourceKind: row.sourceKind
            )
            if row.nextPath?.contains("/rows/") == true {
                CustomRowBrowseView(title: row.title, pathOrRowId: row.nextPath ?? row.rowId, isOngoingList: isOngoing)
            } else if row.rowId == "popular-movies"
                || row.sourceKind == "system_popular_movies"
                || row.nextPath?.contains("/catalog/movies") == true {
                CatalogBrowseView(mediaType: "movie", initialGenre: nil, isRootTab: false)
            } else if row.rowId == "popular-series"
                || row.sourceKind == "system_popular_series"
                || row.nextPath?.contains("/catalog/series") == true {
                CatalogBrowseView(mediaType: "series", initialGenre: nil, isRootTab: false)
            } else {
                CustomRowBrowseView(title: row.title, pathOrRowId: row.nextPath ?? row.rowId, isOngoingList: isOngoing)
            }
        }
        .sheet(item: $sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked, reusedPrepareToken, createdPreparedSession in
                    let target = ctx
                    sourcePickerContext = nil
                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                        itemId: target.itemId,
                        title: target.title,
                        seriesTitle: target.seriesTitle,
                        season: target.season,
                        episode: target.episode,
                        startPositionSeconds: target.startPositionSeconds,
                        candidateId: reusedPrepareToken == nil ? picked.candidateId : nil,
                        prepareToken: reusedPrepareToken,
                        preparedSession: createdPreparedSession,
                        backdropUrl: target.backdropUrl,
                        logoUrl: target.logoUrl
                    )
                },
                onCancel: {
                    sourcePickerContext = nil
                }
            )
            .environment(sessionStore)
            .preferredColorScheme(.dark)
        }
        .task(id: "\(viewModel.scopeKey(for: sessionStore))#active:\(isActiveTab)") {
            await viewModel.handleActivation(session: sessionStore, isActiveTab: isActiveTab)
        }
        .task(id: "\(viewModel.validatedScopeKey ?? "")#warm:\(!rows.isEmpty && !viewModel.isInitialColdFetch)") {
            await viewModel.warmCatalogMetadataAfterHomePaintIfEligible(
                session: sessionStore,
                isPreviewMode: isPreviewMode
            )
        }
        .onChange(of: sourcePickerContext != nil) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            viewModel.handleHomeRefreshNonceChange(newNonce, isActiveTab: isActiveTab, session: sessionStore)
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleForegroundTransition(
                isSceneActive: phase == .active,
                isActiveTab: isActiveTab,
                session: sessionStore
            )
        }
        .onDisappear {
            viewModel.cancelAllTasks()
            if sourcePickerContext == nil {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    private func focusLeftmostHomeTarget(rows: [TvShelfRow]) {
        if let firstRow = rows.first(where: { !$0.items.isEmpty }) {
            let orderedKeys = firstRow.items.map { "\(firstRow.rowId)#\($0.itemId)" }
            scrollPosition.scrollTo(edge: .top)
            if let resolvedKey = mountedTracker.resolveEntryID(orderedIDs: orderedKeys) {
                entryCardKey = resolvedKey
                entryFocusNonce &+= 1
            }
        } else if viewModel.errorMessage != nil && rows.isEmpty {
            isRetryButtonFocused = true
        }
    }

    private func openSourcePicker(for card: TvMediaCard) {
        let resolved = MediaCardMutator.resolvePlayTarget(for: card)
        sourcePickerContext = SourcePickerContext(
            itemId: resolved.itemId,
            title: resolved.title,
            seriesTitle: resolved.seriesTitle,
            season: resolved.season,
            episode: resolved.episode,
            startPositionSeconds: resolved.startPos,
            backdropUrl: card.preferredLandscapePath,
            logoUrl: card.logoUrl
        )
    }
}
