import SwiftUI

struct ShelfRowView: View {
    let row: TvShelfRow
    let isDefaultFocusRow: Bool
    var focusedCardKey: FocusState<String?>.Binding
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
        CustomRowContextPolicy.isOngoingList(
            explicitFlag: false,
            rowId: row.rowId,
            sourceKind: row.sourceKind
        )
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
        VStack(alignment: .leading, spacing: 18) {
            Text(row.title)
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.linen)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            if row.rowStyle == "continue_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .continueWatching,
                                width: LunaTokens.Layout.backdropW,
                                onPrimaryAction: {
                                    onPlayContinueCard(card)
                                }
                            )
                            .focused(focusedCardKey, equals: "\(row.rowId)#\(card.itemId)")
                            .prefersDefaultFocus(isDefaultFocusRow && idx == 0, in: focusNamespace)
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
                                    onPickSourceForCard(card)
                                } label: {
                                    Label("Velg kilde…", systemImage: "arrow.triangle.2.circlepath")
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
                            SeeAllShelfCardButton(width: LunaTokens.Layout.posterW, height: LunaTokens.Layout.backdropH) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 28)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()
            } else if row.rowStyle == "upcoming_backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .upcomingEpisode,
                                width: LunaTokens.Layout.backdropW,
                                onPrimaryAction: {
                                    onSelectCard(card)
                                }
                            )
                            .focused(focusedCardKey, equals: "\(row.rowId)#\(card.itemId)")
                            .prefersDefaultFocus(isDefaultFocusRow && idx == 0, in: focusNamespace)
                            .contextMenu {
                                Button {
                                    onSelectCard(card)
                                } label: {
                                    Label("Åpne detaljer", systemImage: "tv")
                                }

                                Button {
                                    onRemoveFromOngoing(card)
                                } label: {
                                    Label("Fjern fra pågående", systemImage: "minus.circle")
                                }
                            }
                        }

                        if row.hasMore == true {
                            SeeAllShelfCardButton(width: LunaTokens.Layout.posterW, height: LunaTokens.Layout.backdropH) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 28)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()
            } else if row.rowStyle == "backdrop" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            BackdropCardView(
                                card: card,
                                client: client,
                                variant: .standard,
                                width: LunaTokens.Layout.backdropW,
                                showStorageBadge: row.sourceKind == "local_library",
                                onPrimaryAction: {
                                    onSelectCard(card)
                                },
                                onPlayShortcut: {
                                    onPlayContinueCard(card)
                                }
                            )
                            .focused(focusedCardKey, equals: "\(row.rowId)#\(card.itemId)")
                            .prefersDefaultFocus(isDefaultFocusRow && idx == 0, in: focusNamespace)
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
                            SeeAllShelfCardButton(width: LunaTokens.Layout.posterW, height: LunaTokens.Layout.backdropH) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 28)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: LunaTokens.Layout.posterW,
                                showStorageBadge: row.sourceKind == "local_library",
                                onSelect: {
                                    onSelectCard(card)
                                },
                                onPlayShortcut: {
                                    onPlayContinueCard(card)
                                }
                            )
                            .focused(focusedCardKey, equals: "\(row.rowId)#\(card.itemId)")
                            .prefersDefaultFocus(isDefaultFocusRow && idx == 0, in: focusNamespace)
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
                            SeeAllShelfCardButton(width: LunaTokens.Layout.posterW, height: LunaTokens.Layout.posterH) {
                                onSeeAllRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 28)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()
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
                    .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)

                Text("Se alle")
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(LunaTheme.linen)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surface)
            )
            .lunaFocusSurface(.secondaryPill, isFocused: isFocused, cornerRadius: LunaTheme.cardRadius)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
