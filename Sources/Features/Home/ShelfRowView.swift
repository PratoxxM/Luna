import SwiftUI

struct MediaArtworkImage: View {
    let url: URL?
    let placeholderSymbol: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.15, blue: 0.20),
                    Color(red: 0.08, green: 0.09, blue: 0.13),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: placeholderSymbol)
                .font(.title)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct ShelfRowView: View {
    let row: TvShelfRow
    let client: BFFClient?
    let onSelectCard: (TvMediaCard) -> Void
    let onPlayContinueCard: (TvMediaCard) -> Void
    let onSelectGenre: (TvGenreChip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 64)

            if row.rowStyle == "genre_chips", let genres = row.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 22) {
                        ForEach(genres) { chip in
                            Button {
                                onSelectGenre(chip)
                            } label: {
                                Text(chip.label)
                                    .font(.headline)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 12)
                }
            } else if row.rowStyle == "continue_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 32) {
                        ForEach(row.items) { card in
                            Button {
                                onPlayContinueCard(card)
                            } label: {
                                continueCardView(card)
                            }
                            .buttonStyle(.card)
                            .contextMenu {
                                Button("Åpne detaljer") {
                                    onSelectCard(card)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 18)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(row.items) { card in
                            Button {
                                onSelectCard(card)
                            } label: {
                                posterCardView(card)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private func continueCardView(_ card: TvMediaCard) -> some View {
        let imgURL = client?.resolveArtworkURL(card.backdropUrl ?? card.posterUrl)
        let pct = min(100.0, max(0.0, card.progress?.percent ?? 0))

        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                MediaArtworkImage(url: imgURL, placeholderSymbol: "play.tv")
                    .frame(width: 440, height: 248)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.caption.bold())
                        Text(card.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(card.formattedSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))

                    if pct > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.24))
                                Capsule()
                                    .fill(Color(red: 0.96, green: 0.77, blue: 0.42))
                                    .frame(width: geo.size.width * CGFloat(pct / 100.0))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(18)
            }
            .frame(width: 440, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func posterCardView(_ card: TvMediaCard) -> some View {
        let imgURL = client?.resolveArtworkURL(card.posterUrl ?? card.backdropUrl)

        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                MediaArtworkImage(url: imgURL, placeholderSymbol: "film")
                    .frame(width: 240, height: 360)
                    .clipped()

                if let badge = card.badges?.first {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .frame(width: 240, height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(card.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)

            Text(card.formattedSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)
        }
    }
}
