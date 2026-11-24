import SwiftUI

struct SearchView: View {
    private enum SearchControlFocus: Hashable {
        case recent(String)
        case retry
        case emptyReset
    }

    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let initialQuery: String
    let isRootTab: Bool
    let isActiveTab: Bool
    let previewFocusFirstResult: Bool

    @State private var subpageToken = UUID()

    @State private var query: String
    @State private var results: [TvMediaCard] = []
    @State private var localCount: Int = 0
    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var recentSearches: [String] = []
    @State private var selectedCard: TvMediaCard?
    @State private var lastCompletedQuery: String = ""
    @State private var didConsumeInitialQuery: Bool = false
    @State private var searchRetryNonce: Int = 0
    @State private var lastHandledRetryNonce: Int = 0
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var queryFocusNonce: Int = 0

    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @State private var didApplyPreviewResultFocus: Bool = false

    @FocusState private var isQueryFieldFocused: Bool
    @FocusState private var controlFocus: SearchControlFocus?

    private let columns = LunaTheme.posterGridColumns

    nonisolated static func resolveSearchFieldBorderColor(isFocused: Bool) -> Color {
        isFocused ? LunaTokens.Accent.border : .clear
    }

    init(
        initialQuery: String = "",
        isRootTab: Bool = false,
        isActiveTab: Bool = true,
        previewFocusFirstResult: Bool = false
    ) {
        self.initialQuery = initialQuery
        self.isRootTab = isRootTab
        self.isActiveTab = isActiveTab
        self.previewFocusFirstResult = previewFocusFirstResult
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    if !isRootTab {
                        Text("Søk")
                            .font(LunaTheme.Font.pageTitle)
                            .foregroundStyle(LunaTheme.linen)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    HStack(spacing: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(LunaTheme.Font.pillIcon)
                                .foregroundStyle(LunaTheme.muted)

                            TextField("Film, serie eller person", text: $query)
                                .font(LunaTheme.Font.body)
                                .foregroundStyle(LunaTheme.linen)
                                .focused($isQueryFieldFocused)
                                .lunaRequestDirectFocus(nonce: queryFocusNonce, isFocused: $isQueryFieldFocused)
                                .onMoveCommand { direction in
                                    if direction == .down {
                                        focusFirstResultOrHistory(trimmedQuery: trimmedQuery, scrollProxy: scrollProxy)
                                    }
                                }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                                .fill(isQueryFieldFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                                .strokeBorder(
                                    Self.resolveSearchFieldBorderColor(isFocused: isQueryFieldFocused),
                                    lineWidth: LunaTokens.Layout.hairlineWidth
                                )
                        )
                        .lunaFocusSurface(.listRow, isFocused: isQueryFieldFocused, cornerRadius: LunaTokens.Radius.card)

                        if !query.isEmpty {
                            LunaIconButton(systemImage: "xmark", accessibilityLabel: "Tøm søk") {
                                clearSearchKeepingFieldFocus()
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .focusSection()

                    if trimmedQuery.count < 2 {
                        if !recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
                                LunaSectionHeader(title: "Tidligere søk") {
                                    LunaPillButton("Tøm", prominence: .subtleChip, size: .compact) {
                                        clearRecentSearches()
                                    }
                                }
                                .padding(.horizontal, LunaTheme.horizontalGutter)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(recentSearches, id: \.self) { term in
                                            LunaPillButton(term, prominence: .glassPill, size: .compact) {
                                                query = term
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
                            Text(
                                localCount > 0
                                    ? "\(LunaCopy.searchHits(results.count)) · \(localCount) lokalt"
                                    : LunaCopy.searchHits(results.count)
                            )
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.muted)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                        }

                        if isSearching && results.isEmpty {
                            LunaLoadingRow(message: "Søker…")
                                .padding(.horizontal, LunaTheme.horizontalGutter)
                        } else if let errorMessage, results.isEmpty {
                            LunaInlineError(message: errorMessage) {
                                searchRetryNonce &+= 1
                            }
                            .focused($controlFocus, equals: .retry)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.top, 12)
                        } else if !isSearching && results.isEmpty {
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
                                                Task { await toggleWatched(card) }
                                            },
                                            onToggleWatchlist: {
                                                Task { await toggleWatchlist(card) }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.bottom, 72)
                            .focusSection()
                        }
                    }
                }
                .padding(.top, isRootTab ? LunaTokens.Layout.contentTop : LunaTokens.Layout.subpageTop)
                .padding(.bottom, 72)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .lunaRootScrollTopBarTracking(tab: .search, isEnabled: isRootTab)
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isRootTab, isActiveTab else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                }
            }
            .onChange(of: contentEntryFocusNonce) { _, _ in
                guard isRootTab, isActiveTab else { return }
                scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                queryFocusNonce &+= 1
            }
        }
        .lunaBottomToast(message: $mutationErrorBanner, tone: .danger)
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
            loadRecentSearches()
            if !isRootTab {
                subpageVisibility.enterSubpage(subpageToken)
            }
        }
        .task(id: "\(trimmedQuery)#\(searchRetryNonce)#\(sessionStore.homeRefreshNonce)#active:\(isActiveTab)") {
            guard trimmedQuery.count >= 2 else {
                results = []
                localCount = 0
                lastCompletedQuery = ""
                errorMessage = nil
                isSearching = false
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce
                return
            }

            let initialTrimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let isRetry = searchRetryNonce != lastHandledRetryNonce
            if isRetry {
                lastHandledRetryNonce = searchRetryNonce
            }
            let nonceChanged = lastSeenRefreshNonce != -1 && lastSeenRefreshNonce != sessionStore.homeRefreshNonce
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            if nonceChanged && !isActiveTab && isRootTab {
                // Invalidate cached query marker so returning to Search tab refreshes immediately
                lastCompletedQuery = ""
                return
            }
            let skipDebounce = (!didConsumeInitialQuery && !initialTrimmed.isEmpty && trimmedQuery == initialTrimmed) || isRetry || nonceChanged
            didConsumeInitialQuery = true

            if !skipDebounce {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
            guard !Task.isCancelled else { return }
            if !isRetry && !nonceChanged && trimmedQuery == lastCompletedQuery && !results.isEmpty && errorMessage == nil {
                return
            }
            await executeSearch(trimmed: trimmedQuery)
            if previewFocusFirstResult, !didApplyPreviewResultFocus, let firstID = results.first?.id {
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
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: isRootTab,
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    private func focusFirstResultOrHistory(trimmedQuery: String, scrollProxy: ScrollViewProxy) {
        if trimmedQuery.count < 2 {
            if let firstRecent = recentSearches.first {
                controlFocus = .recent(firstRecent)
            }
        } else if !results.isEmpty {
            if !mountedTracker.hasAnyMounted, let firstID = results.first?.id {
                scrollProxy.scrollTo(firstID, anchor: .top)
            }
            if let resolvedID = mountedTracker.resolveEntryID(orderedIDs: results.map(\.id)) {
                entryCardID = resolvedID
                cardFocusNonce &+= 1
            }
        } else if errorMessage != nil {
            controlFocus = .retry
        } else if !isSearching {
            controlFocus = .emptyReset
        }
    }

    private func executeSearch(trimmed: String) async {
        guard let client = sessionStore.makeClient() else { return }
        isSearching = true
        errorMessage = nil

        do {
            let res = try await client.searchFull(query: trimmed, limit: 30)
            guard !Task.isCancelled else { return }
            results = res.items
            localCount = res.localCount ?? 0
            lastCompletedQuery = trimmed
            if !res.items.isEmpty {
                recordRecentSearch(trimmed)
            }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            guard !Task.isCancelled else { return }
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }

        if !Task.isCancelled {
            isSearching = false
        }
    }

    private func clearSearchKeepingFieldFocus() {
        isQueryFieldFocused = true
        queryFocusNonce &+= 1
        query = ""
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

    private func loadRecentSearches() {
        recentSearches = sessionStore.loadRecentSearches()
    }

    private func recordRecentSearch(_ term: String) {
        recentSearches = sessionStore.recordRecentSearch(term)
    }

    private func clearRecentSearches() {
        recentSearches = []
        sessionStore.clearRecentSearches()
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func toggleWatchlist(_ card: TvMediaCard) async {
        let previous = card.inWatchlist
        let nextListed = !(card.inWatchlist ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].inWatchlist = nextListed
        }
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextListed, sessionStore: sessionStore) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = results.firstIndex(where: { $0.id == card.id }) {
                results[idx].inWatchlist = previous
            }
            showMutationError(error)
        }
    }

    private func toggleWatched(_ card: TvMediaCard) async {
        let previousProgress = card.progress
        let nextWatched = !(card.progress?.watched ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].progress = TvWatchProgress(
                positionSeconds: nextWatched ? 0 : (previousProgress?.positionSeconds ?? 0),
                durationSeconds: previousProgress?.durationSeconds ?? 0,
                percent: nextWatched ? 100 : 0,
                season: previousProgress?.season,
                episode: previousProgress?.episode,
                watched: nextWatched
            )
        }
        do {
            if try await MediaCardMutator.toggleWatched(
                for: card,
                watched: nextWatched,
                preferSeriesEpisodeTarget: true,
                sessionStore: sessionStore
            ) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = results.firstIndex(where: { $0.id == card.id }) {
                results[idx].progress = previousProgress
            }
            showMutationError(error)
        }
    }
}
