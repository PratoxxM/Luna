import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let initialQuery: String

    @State private var query: String
    @State private var results: [TvMediaCard] = []
    @State private var localCount: Int = 0
    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorBanner: String?
    @State private var recentSearches: [String] = []
    @State private var selectedCard: TvMediaCard?
    @State private var searchTask: Task<Void, Never>?
    @State private var bannerClearTask: Task<Void, Never>?

    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    init(initialQuery: String = "") {
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    TextField("Søk etter film, serie, person eller originaltittel…", text: $query)

                    if !query.isEmpty {
                        LunaPillButton("Tøm", systemImage: "xmark.circle") {
                            query = ""
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 18)

                if let mutationErrorBanner {
                    TransientErrorBanner(message: mutationErrorBanner)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                if trimmedQuery.count < 2 {
                    if !recentSearches.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 16) {
                                Text("Tidligere søk")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(LunaTheme.moonlight)
                                LunaPillButton("Tøm logg", systemImage: "trash") {
                                    clearRecentSearches()
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentSearches, id: \.self) { term in
                                        LunaPillButton(term, systemImage: "clock.arrow.circlepath") {
                                            query = term
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .scrollClipDisabled()
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                    } else {
                        Text("Skriv minst to tegn for å søke i bibliotek og katalog.")
                            .font(.callout)
                            .foregroundStyle(LunaTheme.muted)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.top, 8)
                    }
                } else {
                    if !results.isEmpty {
                        HStack(spacing: 12) {
                            if localCount > 0 {
                                Text("\(localCount) i lokalt bibliotek")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(LunaTheme.emerald)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(LunaTheme.emerald.opacity(0.14), in: Capsule())
                            }
                            Text("\(results.count) treff totalt")
                                .font(.caption)
                                .foregroundStyle(LunaTheme.muted)
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    if isSearching && results.isEmpty {
                        HStack(spacing: 14) {
                            ProgressView()
                            Text("Søker…")
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                    } else if let errorMessage, results.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(errorMessage)
                                .foregroundStyle(LunaTheme.amber)
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                triggerSearch(trimmedQuery, debounceNanoseconds: 0)
                            }
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.top, 12)
                    } else if !isSearching && results.isEmpty {
                        Text("Ingen treff for «\(trimmedQuery)».")
                            .font(.title3)
                            .foregroundStyle(LunaTheme.muted)
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                            .padding(.top, 20)
                    } else {
                        LazyVGrid(columns: columns, spacing: 42) {
                            ForEach(results) { card in
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
                                            Task { await toggleWatched(card) }
                                        },
                                        onToggleWatchlist: {
                                            Task { await toggleWatchlist(card) }
                                        },
                                        onToggleFavorite: {
                                            Task { await toggleFavorite(card) }
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
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .task(id: initialQuery) {
            loadRecentSearches()
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 {
                triggerSearch(trimmed, debounceNanoseconds: 0)
            }
        }
        .onChange(of: query) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                searchTask?.cancel()
                results = []
                localCount = 0
                errorMessage = nil
                isSearching = false
                return
            }
            triggerSearch(trimmed, debounceNanoseconds: 180_000_000)
        }
        .onDisappear {
            searchTask?.cancel()
            bannerClearTask?.cancel()
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
                errorMessage = error.localizedDescription
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
        mutationErrorBanner = "Kunne ikke lagre endring: \(error.localizedDescription)"
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

    private func toggleFavorite(_ card: TvMediaCard) async {
        let previous = card.isFavorite
        let nextFavorite = !(card.isFavorite ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].isFavorite = nextFavorite
        }
        do {
            if try await MediaCardMutator.setFavorite(for: card, favorite: nextFavorite, sessionStore: sessionStore) {
                sessionStore.notifyContentMutated()
            }
        } catch {
            if let idx = results.firstIndex(where: { $0.id == card.id }) {
                results[idx].isFavorite = previous
            }
            showMutationError(error)
        }
    }
}
