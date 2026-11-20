import SwiftUI

struct SearchView: View {
    private enum SearchFocusTarget: Hashable {
        case queryField
        case clearQuery
        case recent(String)
        case clearHistory
        case card(String)
        case retry
        case emptyReset
    }

    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let initialQuery: String
    let isRootTab: Bool
    let isActiveTab: Bool

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
    @State private var searchTask: Task<Void, Never>?
    @State private var bannerClearTask: Task<Void, Never>?
    @State private var entryFocusRetryTask: Task<Void, Never>?

    @FocusState private var searchFocus: SearchFocusTarget?

    private let columns = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.gridPosterW), spacing: LunaTokens.Layout.gridCardGap, alignment: .topLeading),
        count: 6
    )

    init(initialQuery: String = "", isRootTab: Bool = false, isActiveTab: Bool = true) {
        self.initialQuery = initialQuery
        self.isRootTab = isRootTab
        self.isActiveTab = isActiveTab
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    Text("Søk")
                        .font(LunaTheme.Font.pageTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .padding(.horizontal, LunaTheme.horizontalGutter)

                    HStack(spacing: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(LunaTheme.Font.pillIcon)
                                .foregroundStyle(searchFocus == .queryField ? LunaTheme.amber : LunaTheme.muted)

                            TextField("Søk etter film, serie, person eller originaltittel…", text: $query)
                                .font(LunaTheme.Font.body)
                                .foregroundStyle(LunaTheme.linen)
                                .focused($searchFocus, equals: .queryField)
                                .onMoveCommand { direction in
                                    if direction == .down {
                                        focusFirstResultOrHistory(trimmedQuery: trimmedQuery)
                                    }
                                }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                                .fill(searchFocus == .queryField ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                        )
                        .lunaFocusSurface(.listRow, isFocused: searchFocus == .queryField, cornerRadius: LunaTokens.Radius.card)

                        if !query.isEmpty {
                            LunaPillButton("Tøm", systemImage: "xmark.circle", prominence: .glassPill, size: .compact) {
                                query = ""
                            }
                            .focused($searchFocus, equals: .clearQuery)
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .focusSection()

                    if trimmedQuery.count < 2 {
                        if !recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 16) {
                                    Text("Tidligere søk")
                                        .font(LunaTheme.Font.cardTitle)
                                        .foregroundStyle(LunaTheme.moonlight)

                                    Spacer(minLength: 16)

                                    LunaPillButton("Tøm logg", systemImage: "trash", prominence: .subtleChip, accent: .coral, size: .compact) {
                                        clearRecentSearches()
                                    }
                                    .focused($searchFocus, equals: .clearHistory)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(recentSearches, id: \.self) { term in
                                            LunaPillButton(term, systemImage: "clock.arrow.circlepath", prominence: .glassPill, size: .compact) {
                                                query = term
                                            }
                                            .focused($searchFocus, equals: .recent(term))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .contentMargins(.zero, for: .scrollContent)
                                .scrollClipDisabled()
                                .focusSection()
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                        } else {
                            Text("Skriv minst to tegn for å søke i bibliotek og katalog.")
                                .font(LunaTheme.Font.body)
                                .foregroundStyle(LunaTheme.muted)
                                .padding(.horizontal, LunaTheme.horizontalGutter)
                                .padding(.top, 8)
                        }
                    } else {
                        if !results.isEmpty {
                            HStack(spacing: 12) {
                                if localCount > 0 {
                                    Text("\(localCount) i Lokalt")
                                        .font(LunaTheme.Font.badge)
                                        .foregroundStyle(LunaTheme.moonlight)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(LunaTheme.surfaceRaised, in: Capsule())
                                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                                }
                                Text("\(LunaCopy.searchHits(results.count)) totalt")
                                    .font(LunaTheme.Font.caption)
                                    .foregroundStyle(LunaTheme.muted)
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                        }

                        if isSearching && results.isEmpty {
                            HStack(spacing: 14) {
                                ProgressView()
                                Text("Søker…")
                                    .font(LunaTheme.Font.body)
                                    .foregroundStyle(LunaTheme.moonlight)
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                        } else if let errorMessage, results.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(errorMessage)
                                    .font(LunaTheme.Font.body)
                                    .foregroundStyle(LunaTheme.danger)
                                LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                    triggerSearch(trimmedQuery, debounceNanoseconds: 0)
                                }
                                .focused($searchFocus, equals: .retry)
                            }
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.top, 12)
                        } else if !isSearching && results.isEmpty {
                            VStack(spacing: 18) {
                                LunaCrescentMarkView(size: 64, color: LunaTheme.moonlight.opacity(0.65))
                                Text("Fant ikke «\(trimmedQuery)»")
                                    .font(isRootTab ? LunaTheme.Font.pageTitle : LunaTheme.Font.heroSerif)
                                    .foregroundStyle(LunaTheme.linen)
                                Text("Prøv originaltittelen eller en annen stavemåte.")
                                    .font(LunaTheme.Font.body)
                                    .foregroundStyle(LunaTheme.moonlight)
                                LunaPillButton("Tøm søk", systemImage: "xmark.circle", prominence: .glassPill) {
                                    query = ""
                                }
                                .focused($searchFocus, equals: .emptyReset)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.top, 48)
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                                ForEach(results) { card in
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
                                    .focused($searchFocus, equals: .card(card.id))
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
                        }
                    }
                }
                .padding(.top, isRootTab ? LunaTopBarView.contentTopPadding : 60)
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
                focusSearchQueryField(scrollProxy: scrollProxy)
            }
        }
        .overlay(alignment: .topLeading) {
            if let mutationErrorBanner {
                TransientErrorBanner(message: mutationErrorBanner)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, (isRootTab ? LunaTopBarView.contentTopPadding : 60) + 8)
                    .allowsHitTesting(false)
            }
        }
        .focusSection()
        .lunaNavigationContainerBackdrop(
            isEnabled: !isRootTab,
            mode: .ambient(isPaused: sessionStore.activePlaybackTarget != nil)
        )
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onAppear {
            if !isRootTab {
                subpageVisibility.enterSubpage(subpageToken)
            }
        }
        .task(id: initialQuery) {
            loadRecentSearches()
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2, trimmed != lastCompletedQuery || results.isEmpty {
                triggerSearch(trimmed, debounceNanoseconds: 0)
            }
        }
        .onChange(of: query) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                searchTask?.cancel()
                results = []
                localCount = 0
                lastCompletedQuery = ""
                errorMessage = nil
                isSearching = false
                return
            }
            triggerSearch(trimmed, debounceNanoseconds: 180_000_000)
        }
        .onDisappear {
            entryFocusRetryTask?.cancel()
            entryFocusRetryTask = nil
            searchTask?.cancel()
            bannerClearTask?.cancel()
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                isRootTab: isRootTab,
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    private func focusSearchQueryField(scrollProxy: ScrollViewProxy) {
        entryFocusRetryTask?.cancel()
        scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
        searchFocus = .queryField
        entryFocusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, isRootTab, isActiveTab else { return }
                if searchFocus == nil {
                    searchFocus = .queryField
                } else {
                    return
                }
            }
        }
    }

    private func focusFirstResultOrHistory(trimmedQuery: String) {
        if trimmedQuery.count < 2 {
            if let firstRecent = recentSearches.first {
                searchFocus = .recent(firstRecent)
            }
        } else if let firstCard = results.first {
            searchFocus = .card(firstCard.id)
        } else if errorMessage != nil {
            searchFocus = .retry
        } else if !isSearching {
            searchFocus = .emptyReset
        }
    }

    private func triggerSearch(_ trimmed: String, debounceNanoseconds: UInt64) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled, let client = sessionStore.makeClient() else { return }
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
            } catch is CancellationError {
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
    }

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: SideloadSafeStorage.recentSearchesKey) ?? []
    }

    private func recordRecentSearch(_ term: String) {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return }
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(normalized) != .orderedSame }
        updated.insert(normalized, at: 0)
        if updated.count > 8 {
            updated = Array(updated.prefix(8))
        }
        recentSearches = updated
        UserDefaults.standard.set(updated, forKey: SideloadSafeStorage.recentSearchesKey)
    }

    private func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: SideloadSafeStorage.recentSearchesKey)
    }

    private func showMutationError(_ error: Error) {
        bannerClearTask?.cancel()
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
        bannerClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            mutationErrorBanner = nil
        }
    }

    private func toggleWatchlist(_ card: TvMediaCard) async {
        let previous = card.inWatchlist
        let nextListed = !(card.inWatchlist ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].inWatchlist = nextListed
        }
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextListed, sessionStore: sessionStore) {
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
            if try await MediaCardMutator.toggleWatched(for: card, watched: nextWatched, sessionStore: sessionStore) {
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
