import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var query: String = ""
    @State private var results: [TvMediaCard] = []
    @State private var localCount: Int = 0
    @State private var isSearching: Bool = false
    @State private var selectedCard: TvMediaCard?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Søk")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Lynraskt søk på tvers av lokalt NAS-bibliotek og TMDB.")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 26)

                TextField("Søk etter film, serie eller originaltittel…", text: $query)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

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
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching && results.isEmpty {
                    Text("Ingen treff for «\(query)».")
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
                                showStorageBadge: true
                            ) {
                                selectedCard = card
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.bottom, 72)
                }
            }
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                results = []
                localCount = 0
                isSearching = false
                return
            }
            searchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let client = sessionStore.makeClient() else { return }
                isSearching = true
                if let res = try? await client.searchFull(query: trimmed, limit: 30), !Task.isCancelled {
                    results = res.items
                    localCount = res.localCount ?? 0
                }
                isSearching = false
            }
        }
    }
}
