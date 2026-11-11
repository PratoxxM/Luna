import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var items: [TvMediaCard] = []
    @State private var isLoading: Bool = true
    @State private var selectedCard: TvMediaCard?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 34)
    ]

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Huskeliste")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 64)
                    .padding(.top, 36)

                if isLoading {
                    ProgressView()
                        .padding(64)
                } else if items.isEmpty {
                    Text("Huskelisten er tom. Legg til filmer og serier fra MediaOS eller detaljer-siden.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 64)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(items) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    MediaArtworkImage(
                                        url: client?.resolveArtworkURL(card.posterUrl ?? card.backdropUrl),
                                        placeholderSymbol: "bookmark"
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
        .task {
            guard let client else { return }
            isLoading = true
            items = (try? await client.fetchWatchlist()) ?? []
            isLoading = false
        }
    }
}
