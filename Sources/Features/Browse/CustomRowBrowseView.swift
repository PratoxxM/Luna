import SwiftUI

/// Full-grid explorer for custom MediaLogg shelves or "Se alle" row links.
struct CustomRowBrowseView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    let title: String
    let pathOrRowId: String
    var isOngoingList: Bool = false

    @State private var subpageToken = UUID()

    @State private var items: [TvMediaCard] = []
    @State private var rowSourceKind: String?
    @State private var hasMore: Bool = false
    @State private var offset: Int = 0
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var selectedCard: TvMediaCard?
    @State private var retryNonce: Int = 0
    @State private var suppressNextRefreshReload: Bool = false
    @State private var reloadGeneration: UInt64 = 0
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardID: String?
    @State private var cardFocusNonce: Int = 0
    @FocusState private var isRetryButtonFocused: Bool
    @Namespace private var customRowGridNamespace

    private let pageSize = 36
    private let columns = LunaTheme.posterGridColumns

    nonisolated static func resolveInitialFocusTarget(
        currentEntryCardID: String?,
        oldFirstID: String?,
        newFirstID: String?
    ) -> String? {
        guard let newFirstID else { return nil }
        if oldFirstID == nil || currentEntryCardID == nil {
            return newFirstID
        }
        return nil
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let removeTitle = CustomRowContextPolicy.removeActionTitle(
            explicitFlag: isOngoingList,
            rowId: effectiveRowId,
            sourceKind: rowSourceKind
        )

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                Text(title)
                    .font(LunaTheme.Font.pageTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                if isLoading && items.isEmpty {
                    LunaLoadingRow(message: "Henter innhold…")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if let errorMessage, items.isEmpty {
                    LunaInlineError(message: errorMessage) {
                        retryNonce &+= 1
                    }
                    .focused($isRetryButtonFocused)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    LunaEmptyState(headline: "Ingen titler i denne listen")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
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
                            .prefersDefaultFocus(idx == 0, in: customRowGridNamespace)
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
                                        Task { await toggleCustomWatched(card) }
                                    },
                                    onToggleWatchlist: {
                                        Task { await toggleCustomWatchlist(card) }
                                    },
                                    removeActionTitle: removeTitle,
                                    onRemoveFromContainer: removeTitle == nil ? nil : {
                                        Task { await removeCardFromCurrentList(card) }
                                    }
                                )
                            }
                            .onAppear {
                                if idx >= prefetchThreshold && hasMore && !isLoadingMore {
                                    loadMoreTask?.cancel()
                                    loadMoreTask = Task { @MainActor in
                                        await loadMore()
                                    }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .focusSection()

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                }
            }
            .padding(.top, LunaTokens.Layout.subpageTop)
            .padding(.bottom, 72)
        }
        .scrollPosition($scrollPosition)
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .ignoresSafeArea()
        .focusScope(customRowGridNamespace)
        .lunaBottomToast(message: $mutationErrorBanner, tone: .danger)
        .focusSection()
        .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: sessionStore.activePlaybackTarget != nil))
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onAppear {
            subpageVisibility.enterSubpage(subpageToken)
            if entryCardID == nil,
               let target = Self.resolveInitialFocusTarget(
                   currentEntryCardID: entryCardID,
                   oldFirstID: nil,
                   newFirstID: items.first?.id
               ) {
                entryCardID = target
                cardFocusNonce &+= 1
            } else if errorMessage != nil && items.isEmpty {
                isRetryButtonFocused = true
            }
        }
        .onChange(of: items.first?.id) { oldFirst, newFirst in
            if let target = Self.resolveInitialFocusTarget(
                currentEntryCardID: entryCardID,
                oldFirstID: oldFirst,
                newFirstID: newFirst
            ) {
                entryCardID = target
                cardFocusNonce &+= 1
            }
        }
        .onChange(of: errorMessage != nil && items.isEmpty) { _, hasError in
            if hasError {
                isRetryButtonFocused = true
            }
        }
        .task(id: "\(pathOrRowId)#\(sessionStore.homeRefreshNonce)#\(retryNonce)") {
            if suppressNextRefreshReload {
                suppressNextRefreshReload = false
                return
            }
            loadMoreTask?.cancel()
            loadMoreTask = nil
            reloadGeneration &+= 1
            let gen = reloadGeneration
            await loadInitial(generation: gen)
        }
        .onDisappear {
            loadMoreTask?.cancel()
            loadMoreTask = nil
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    private func loadInitial(generation: UInt64) async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil
        offset = 0
        do {
            let res = try await client.fetchRow(pathOrRowId: pathOrRowId, offset: 0, limit: pageSize)
            guard !Task.isCancelled, generation == reloadGeneration else { return }
            items = res.items
            if let sk = res.sourceKind {
                rowSourceKind = sk
            }
            hasMore = res.hasMore
            offset = res.items.count
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled, generation == reloadGeneration else { return }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        if generation == reloadGeneration {
            isLoading = false
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, let client = sessionStore.makeClient() else { return }
        let gen = reloadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let res = try await client.fetchRow(pathOrRowId: pathOrRowId, offset: offset, limit: pageSize)
            guard !Task.isCancelled, gen == reloadGeneration else { return }
            let existing = Set(items.map(\.id))
            items.append(contentsOf: res.items.filter { !existing.contains($0.id) })
            hasMore = res.hasMore
            offset += res.items.count
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled, gen == reloadGeneration else { return }
            showMutationError(error)
        }
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func toggleCustomWatchlist(_ card: TvMediaCard) async {
        let nextVal = !(card.inWatchlist ?? false)
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].inWatchlist = nextVal
        }
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextVal, sessionStore: sessionStore) {
                suppressNextRefreshReload = true
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].inWatchlist = card.inWatchlist
            }
            showMutationError(error)
        }
    }

    private var effectiveRowId: String {
        CustomRowContextPolicy.extractRowId(from: pathOrRowId)
    }

    private var effectiveIsOngoing: Bool {
        CustomRowContextPolicy.isOngoingList(
            explicitFlag: isOngoingList,
            rowId: effectiveRowId,
            sourceKind: rowSourceKind
        )
    }

    private func removeCardFromCurrentList(_ card: TvMediaCard) async {
        do {
            let ok: Bool
            if effectiveIsOngoing {
                ok = try await MediaCardMutator.removeFromOngoing(for: card, sessionStore: sessionStore)
            } else {
                ok = try await MediaCardMutator.removeFromList(for: card, rowId: effectiveRowId, sessionStore: sessionStore)
            }
            if ok {
                items.removeAll { $0.id == card.id }
                suppressNextRefreshReload = true
                sessionStore.notifyContentMutated()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func toggleCustomWatched(_ card: TvMediaCard) async {
        let nextVal = !(card.progress?.watched ?? false)
        let original = card.progress
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            var updated = items[idx].progress ?? TvWatchProgress()
            updated.watched = nextVal
            items[idx].progress = updated
        }
        do {
            if try await MediaCardMutator.toggleWatched(
                for: card,
                watched: nextVal,
                preferSeriesEpisodeTarget: true,
                sessionStore: sessionStore
            ) {
                suppressNextRefreshReload = true
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].progress = original
            }
            showMutationError(error)
        }
    }
}
