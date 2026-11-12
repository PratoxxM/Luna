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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            if row.rowStyle == "continue_backdrop" {
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
                .scrollClipDisabled()
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
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 30) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 248,
                                showStorageBadge: false
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
                                    onMarkWatched(card)
                                } label: {
                                    Label(
                                        card.progress?.watched == true ? "Marker som usett" : "Marker som sett",
                                        systemImage: card.progress?.watched == true ? "eye.slash" : "checkmark.circle"
                                    )
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
                .scrollClipDisabled()
            }
        }
    }
}
