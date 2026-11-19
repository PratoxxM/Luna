import SwiftUI

struct ShelfRowView: View {
    let row: TvShelfRow
    let isFirstRow: Bool
    let focusNamespace: Namespace.ID
    let client: LunaCoreClient?

    let onSelectCard: (TvMediaCard) -> Void
    let onPlayContinueCard: (TvMediaCard) -> Void
    let onPickSourceForCard: (TvMediaCard) -> Void
    let onToggleWatchlist: (TvMediaCard) -> Void
    let onMarkWatched: (TvMediaCard) -> Void
    let onRemoveFromOngoing: (TvMediaCard) -> Void
    let onRemoveFromList: (TvMediaCard, TvShelfRow) -> Void
    let onSeeAllRow: (TvShelfRow) -> Void

    private var isOngoingRow: Bool {
        row.rowId == "medialogg-continue"
            || row.rowId == "continue-watching"
            || row.rowId == "upcoming-episodes"
            || row.rowId == "medialogg-upcoming"
            || row.sourceKind == "system_continue"
            || row.sourceKind == "system_upcoming"
            || row.sourceKind == "active_series"
    }

    private var rowRemoveActionTitle: String? {
        if isOngoingRow { return "Fjern fra pågående" }
        if row.sourceKind == "local_library" { return nil }
        return "Fjern fra listen"
    }

    private func triggerRemoveAction(for card: TvMediaCard) {
        if isOngoingRow {
            onRemoveFromOngoing(card)
        } else if row.sourceKind != "local_library" {
            onRemoveFromList(card, row)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(LunaTheme.linen)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            if row.rowStyle == "continue_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .continueWatching,
                                width: 468,
                                onPrimaryAction: {
                                    onPlayContinueCard(card)
                                }
                            )
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

                                Button {
                                    onRemoveFromOngoing(card)
                                } label: {
                                    Label("Fjern fra pågående", systemImage: "minus.circle")
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
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
            } else if row.rowStyle == "upcoming_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .upcomingEpisode,
                                width: 468,
                                onPrimaryAction: {
                                    onSelectCard(card)
                                }
                            )
                            .prefersDefaultFocus(isFirstRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                Button {
                                    onSelectCard(card)
                                } label: {
                                    Label("Åpne serie og sesonger", systemImage: "tv")
                                }

                                Button {
                                    onRemoveFromOngoing(card)
                                } label: {
                                    Label("Fjern fra pågående", systemImage: "minus.circle")
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
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
            } else if row.rowStyle == "backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .standard,
                                width: 468,
                                showStorageBadge: row.sourceKind == "local_library",
                                onPrimaryAction: {
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
                                    removeActionTitle: rowRemoveActionTitle,
                                    onRemoveFromContainer: rowRemoveActionTitle == nil ? nil : {
                                        triggerRemoveAction(for: card)
                                    }
                                )
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
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 30) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 248,
                                showStorageBadge: row.sourceKind == "local_library",
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
                                    removeActionTitle: rowRemoveActionTitle,
                                    onRemoveFromContainer: rowRemoveActionTitle == nil ? nil : {
                                        triggerRemoveAction(for: card)
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
                .contentMargins(.zero, for: .scrollContent)
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
                Image(systemName: "arrow.right")
                    .font(LunaTheme.Font.sectionTitle)
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.moonlight)

                Text("Se alle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.linen)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(
                        isFocused
                            ? AnyShapeStyle(LunaTheme.focusGoldGradient)
                            : AnyShapeStyle(LunaTheme.surface)
                    )
            )
            .lunaFocusSurface(.secondaryPill, isFocused: isFocused, cornerRadius: LunaTheme.cardRadius)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
