import SwiftUI

struct ShelfRowView: View {
    let row: TvShelfRow
    let isFirstRow: Bool
    let focusNamespace: Namespace.ID
    let client: MediaOSClient?

    let onSelectCard: (TvMediaCard) -> Void
    let onPlayContinueCard: (TvMediaCard) -> Void
    let onPickSourceForCard: (TvMediaCard) -> Void
    let onToggleWatchlist: (TvMediaCard) -> Void
    let onToggleFavorite: (TvMediaCard) -> Void
    let onMarkWatched: (TvMediaCard) -> Void
    let onSelectGenre: (TvGenreChip) -> Void
    let onOpenFullRow: (TvShelfRow) -> Void

    private var showsStorageBadge: Bool {
        row.rowId.contains("local") || row.rowId.contains("watchlist")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(row.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                if row.rowStyle == "upcoming_backdrop" {
                    Text("Neste episoder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.amber)
                }

                Spacer()

                if row.hasMore == true, row.rowStyle != "genre_chips" {
                    LunaPillButton("Se alle", systemImage: "arrow.right", prominence: .subtleChip) {
                        onOpenFullRow(row)
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)

            if row.rowStyle == "genre_chips", let genres = row.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(Array(genres.enumerated()), id: \.element.id) { idx, chip in
                            GenreTileView(chip: chip) {
                                onSelectGenre(chip)
                            }
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 14)
                }
            } else if row.rowStyle == "continue_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 32) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .continueWatching,
                                width: 468
                            ) {
                                onPlayContinueCard(card)
                            }
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                Button {
                                    onPlayContinueCard(card)
                                } label: {
                                    Label("Spill av nå", systemImage: "play.fill")
                                }

                                Button {
                                    onSelectCard(card)
                                } label: {
                                    Label("Åpne detaljer", systemImage: "info.circle")
                                }

                                Button {
                                    onPickSourceForCard(card)
                                } label: {
                                    Label("Bytt kilde…", systemImage: "arrow.triangle.2.circlepath")
                                }

                                Button {
                                    onMarkWatched(card)
                                } label: {
                                    Label("Marker som sett", systemImage: "checkmark.circle")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
            } else if row.rowStyle == "upcoming_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .upcomingEpisode,
                                width: 440
                            ) {
                                onSelectCard(card)
                            }
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                Button {
                                    onSelectCard(card)
                                } label: {
                                    Label("Åpne serie og sesonger", systemImage: "tv")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 248,
                                showStorageBadge: showsStorageBadge
                            ) {
                                onSelectCard(card)
                            }
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                Button {
                                    onPlayContinueCard(card)
                                } label: {
                                    Label("Spill av", systemImage: "play.fill")
                                }

                                Button {
                                    onSelectCard(card)
                                } label: {
                                    Label("Åpne detaljer", systemImage: "info.circle")
                                }

                                Button {
                                    onToggleWatchlist(card)
                                } label: {
                                    Label(
                                        card.inWatchlist == true ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                                        systemImage: card.inWatchlist == true ? "bookmark.slash" : "bookmark"
                                    )
                                }

                                Button {
                                    onToggleFavorite(card)
                                } label: {
                                    Label(
                                        card.isFavorite == true ? "Fjern favoritt" : "Marker som favoritt",
                                        systemImage: card.isFavorite == true ? "star.slash" : "star.fill"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
            }
        }
    }
}
