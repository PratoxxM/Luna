import SwiftUI

internal enum CustomRowContextPolicy {
    nonisolated static func isOngoingList(
        explicitFlag: Bool,
        rowId: String,
        sourceKind: String?
    ) -> Bool {
        if explicitFlag { return true }
        if sourceKind == "active_series" || sourceKind == "system_continue" || sourceKind == "system_upcoming" {
            return true
        }
        let lower = rowId.lowercased()
        return lower == "medialogg-continue"
            || lower == "continue-watching"
            || lower == "upcoming-episodes"
            || lower == "medialogg-upcoming"
            || lower.contains("pagaende")
            || lower.contains("active")
            || lower.contains("continue")
    }

    nonisolated static func removeActionTitle(
        explicitFlag: Bool,
        rowId: String,
        sourceKind: String?
    ) -> String? {
        if isOngoingList(explicitFlag: explicitFlag, rowId: rowId, sourceKind: sourceKind) {
            return "Fjern fra pågående"
        }
        if rowId.hasPrefix("genre:") || sourceKind == "genre" || sourceKind == "local_library" {
            return nil
        }
        return "Fjern fra listen"
    }
}

/// Full-grid explorer for custom MediaLogg shelves or "Se alle" row links.
struct CustomRowBrowseView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
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
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var mutationBannerTask: Task<Void, Never>?

    private let pageSize = 36
    private let columns = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.gridPosterW), spacing: LunaTokens.Layout.gridCardGap, alignment: .topLeading),
        count: 6
    )

    var body: some View {
        let client = sessionStore.makeClient()

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
                        Task { await loadInitial() }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    LunaEmptyState(headline: "Ingen titler i denne listen")
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: LunaTokens.Layout.gridRowGap) {
                        ForEach(items) { card in
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
                                    removeActionTitle: CustomRowContextPolicy.removeActionTitle(
                                        explicitFlag: isOngoingList,
                                        rowId: effectiveRowId,
                                        sourceKind: rowSourceKind
                                    ),
                                    onRemoveFromContainer: CustomRowContextPolicy.removeActionTitle(
                                        explicitFlag: isOngoingList,
                                        rowId: effectiveRowId,
                                        sourceKind: rowSourceKind
                                    ) == nil ? nil : {
                                        Task { await removeCardFromCurrentList(card) }
                                    }
                                )
                            }
                            .onAppear {
                                if card.id == items.last?.id && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)

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
        .contentMargins(.zero, for: .scrollContent)
        .scrollClipDisabled()
        .ignoresSafeArea()
        .lunaBottomToast(message: mutationErrorBanner, tone: .danger)
        .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: sessionStore.activePlaybackTarget != nil))
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onAppear {
            subpageVisibility.enterSubpage(subpageToken)
        }
        .task {
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await loadInitial()
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            Task { await loadInitial() }
        }
        .onDisappear {
            mutationBannerTask?.cancel()
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                hasPushedChildDestination: selectedCard != nil,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }

    private func loadInitial() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil
        offset = 0
        do {
            let res = try await client.fetchRow(pathOrRowId: pathOrRowId, offset: 0, limit: pageSize)
            items = res.items
            if let sk = res.sourceKind {
                rowSourceKind = sk
            }
            hasMore = res.hasMore
            offset = res.items.count
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, let client = sessionStore.makeClient() else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let res = try await client.fetchRow(pathOrRowId: pathOrRowId, offset: offset, limit: pageSize)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: res.items.filter { !existing.contains($0.id) })
            hasMore = res.hasMore
            offset += res.items.count
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            showMutationError(error)
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

    private func toggleCustomWatchlist(_ card: TvMediaCard) async {
        let nextVal = !(card.inWatchlist ?? false)
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].inWatchlist = nextVal
        }
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextVal, sessionStore: sessionStore) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
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
        let stripped = pathOrRowId
            .replacingOccurrences(of: "/api/tv/v1/rows/", with: "")
            .split(separator: "?").first.map(String.init) ?? pathOrRowId
        return stripped.removingPercentEncoding ?? stripped
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
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
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
            if try await MediaCardMutator.toggleWatched(for: card, watched: nextVal, sessionStore: sessionStore) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
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
