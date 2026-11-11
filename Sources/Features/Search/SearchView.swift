import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var query: String = ""
    @State private var results: [TvMediaCard] = []
    @State private var isSearching: Bool = false
    @State private var selectedCard: TvMediaCard?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 34)
    ]

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Søk")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 64)
                    .padding(.top, 36)

                TextField("Søk etter film eller serie…", text: $query)
                    .padding(.horizontal, 64)

                if isSearching {
                    ProgressView()
                        .padding(.horizontal, 64)
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                    Text("Ingen treff for «\(query)».")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 64)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(results) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    MediaArtworkImage(
                                        url: client?.resolveArtworkURL(card.posterUrl ?? card.backdropUrl),
                                        placeholderSymbol: "magnifyingglass"
                                    )
                                    .frame(width: 240, height: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    Text(card.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text(card.formattedSubtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.bottom, 64)
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
                isSearching = false
                return
            }
            searchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled, let client = sessionStore.makeClient() else { return }
                isSearching = true
                results = (try? await client.search(query: trimmed)) ?? []
                isSearching = false
            }
        }
    }
}
