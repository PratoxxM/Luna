import SwiftUI

struct ShelfRowView: View {
    let row: TvShelfRow
    let isDefaultFocusRow: Bool
    let mountedTracker: MountedEntryCardTracker
    let entryCardKey: String?
    let entryFocusNonce: Int
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
        let isContinue = row.rowStyle == "continue_backdrop"
        let isBackdrop = isContinue || row.rowStyle == "backdrop"
        let seeAllHeight = isBackdrop ? LunaTokens.Layout.backdropH : LunaTokens.Layout.posterH
        let seeAllRadius = isBackdrop ? LunaTheme.cardRadius : LunaTheme.posterRadius
        let removeTitle = rowRemoveActionTitle

        VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
            Text(row.title)
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.linen)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { idx, card in
                        let cardKey = "\(row.rowId)#\(card.itemId)"
                        let directNonce = cardKey == entryCardKey ? entryFocusNonce : 0

                        Group {
                            if isContinue {
                                BackdropCardView(
                                    card: card,
                                    client: client,
                                    variant: .continueWatching,
                                    width: LunaTokens.Layout.backdropW,
                                    focusRequestNonce: directNonce,
                                    onPrimaryAction: { onPlayContinueCard(card) }
                                )
                                .contextMenu {
                                    continueContextMenu(for: card)
                                }
                            } else if isBackdrop {
                                BackdropCardView(
                                    card: card,
                                    client: client,
                                    variant: .standard,
                                    width: LunaTokens.Layout.backdropW,
                                    showStorageBadge: true,
                                    focusRequestNonce: directNonce,
                                    onPrimaryAction: { onSelectCard(card) },
                                    onPlayShortcut: { onPlayContinueCard(card) }
                                )
                                .contextMenu {
                                    standardContextMenu(for: card, removeTitle: removeTitle)
                                }
                            } else {
                                PosterCardView(
                                    card: card,
                                    client: client,
                                    width: LunaTokens.Layout.posterW,
                                    showStorageBadge: true,
                                    showRestingTitle: false,
                                    focusRequestNonce: directNonce,
                                    onSelect: { onSelectCard(card) },
                                    onPlayShortcut: { onPlayContinueCard(card) }
                                )
                                .contextMenu {
                                    standardContextMenu(for: card, removeTitle: removeTitle)
                                }
                            }
                        }
                        .lunaTrackMountedCard(id: cardKey, in: mountedTracker)
                        .prefersDefaultFocus(isDefaultFocusRow && idx == 0, in: focusNamespace)
                        .onAppear {
                            ArtworkPipeline.shared.prefetchUpcomingCards(
                                in: row.items,
                                afterIndex: idx,
                                isBackdrop: isBackdrop,
                                maxLookahead: 10,
                                client: client
                            )
                        }
                    }

                    if row.hasMore == true {
                        SeeAllShelfCardButton(
                            width: LunaTokens.Layout.posterW,
                            height: seeAllHeight,
                            cornerRadius: seeAllRadius
                        ) {
                            onSeeAllRow(row)
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 10)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .focusSection()
        }
    }

    @ViewBuilder
    private func continueContextMenu(for card: TvMediaCard) -> some View {
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

    @ViewBuilder
    private func standardContextMenu(for card: TvMediaCard, removeTitle: String?) -> some View {
        StandardPosterContextMenuItems(
            card: card,
            onPlay: { onPlayContinueCard(card) },
            onOpenDetails: { onSelectCard(card) },
            onToggleWatched: { onMarkWatched(card) },
            onToggleWatchlist: { onToggleWatchlist(card) },
            removeActionTitle: removeTitle,
            onRemoveFromContainer: removeTitle == nil ? nil : {
                triggerRemoveAction(for: card)
            }
        )
    }
}

private struct SeeAllShelfCardButton: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surface)
            )
            .lunaFocusSurface(.card, isFocused: isFocused, cornerRadius: cornerRadius)
        }
        .lunaChromelessButton(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .focused($isFocused)
    }
}
