import SwiftUI

/// Full-grid explorer for custom MediaLogg shelves or "Se alle" row links.
struct CustomRowBrowseView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let title: String
    let pathOrRowId: String

    @State private var items: [TvMediaCard] = []
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
    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                if let mutationErrorBanner {
                    TransientErrorBanner(message: mutationErrorBanner)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 14)
                }

                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, 28)

                if isLoading && items.isEmpty {
                    ProgressView()
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 48)
                } else if let errorMessage, items.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadInitial() }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    Text("Denne listen har ingen titler ennå.")
                        .foregroundStyle(LunaTheme.muted)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else {
                    LazyVGrid(columns: columns, spacing: 42) {
                        ForEach(items) { card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 244,
                                showStorageBadge: true,
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
                                    onToggleFavorite: {
                                        Task { await toggleCustomFavorite(card) }
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
            .padding(.bottom, 72)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
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
            hasMore = res.hasMore
            offset = res.items.count
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = error.localizedDescription
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
        mutationErrorBanner = "Kunne ikke lagre endring: \(error.localizedDescription)"
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

    private func toggleCustomFavorite(_ card: TvMediaCard) async {
        let nextVal = !(card.isFavorite ?? false)
        if let idx = items.firstIndex(where: { $0.id == card.id }) {
            items[idx].isFavorite = nextVal
        }
        do {
            if try await MediaCardMutator.setFavorite(for: card, favorite: nextVal, sessionStore: sessionStore) {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == card.id }) {
                items[idx].isFavorite = card.isFavorite
            }
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
