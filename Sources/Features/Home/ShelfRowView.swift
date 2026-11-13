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
    let onSeeAllRow: (TvShelfRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            if row.rowStyle == "continue_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
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

                        if row.hasMore == true {
                            SeeAllShelfCardButton(width: 240, height: 263) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
                .scrollClipDisabled()
            } else if row.rowStyle == "upcoming_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .upcomingEpisode,
                                width: 468
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

                        if row.hasMore == true {
                            SeeAllShelfCardButton(width: 240, height: 263) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 30) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 248,
                                showStorageBadge: false,
                                onSelect: {
                                    onSelectCard(card)
                                },
                                onPlayShortcut: {
                                    onPlayContinueCard(card)
                                }
                            )
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                StandardPosterContextMenuItems(
                                    card: card,
                                    onPlay: {
                                        onPlayContinueCard(card)
                                    },
                                    onOpenDetails: {
                                        onSelectCard(card)
                                    },
                                    onToggleWatched: {
                                        onMarkWatched(card)
                                    },
                                    onToggleWatchlist: {
                                        onToggleWatchlist(card)
                                    },
                                    onToggleFavorite: {
                                        onToggleFavorite(card)
                                    }
                                )
                            }
                        }

                        if row.hasMore == true {
                            SeeAllShelfCardButton(width: 248, height: 372) {
                                onSeeAllRow(row)
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

private struct SeeAllShelfCardButton: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.amber)

                Text("Se alle")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isFocused ? LunaTheme.canvas : .white)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isFocused ? LunaTheme.amber : LunaTheme.surfaceRaised.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.white.opacity(0.92) : LunaTheme.moonlight.opacity(0.14),
                        lineWidth: isFocused ? 2.5 : 1
                    )
            )
            .shadow(
                color: isFocused ? LunaTheme.amber.opacity(0.4) : .black.opacity(0.25),
                radius: isFocused ? 20 : 8,
                x: 0,
                y: isFocused ? 8 : 4
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
