import SwiftUI

struct DetailSeasonsSectionView: View {
    let detail: TvItemDetail
    let seasons: [TvSeasonSummary]
    @Binding var selectedSeasonNumber: Int
    let episodes: [TvEpisodeCard]
    let isLoadingEpisodes: Bool
    let client: LunaCoreClient?
    let detailGutter: CGFloat
    var restoreFocusEpisodeID: String? = nil
    var restoreFocusNonce: Int = 0

    let onSelectSeason: (Int) -> Void
    var onEpisodeFocused: ((TvEpisodeCard) -> Void)? = nil
    let onPlayEpisode: (TvEpisodeCard) -> Void
    let onPickEpisodeSource: (TvEpisodeCard) -> Void
    let onToggleEpisodeWatched: (TvEpisodeCard) -> Void
    let onDeleteEpisode: (TvEpisodeCard) -> Void

    @State private var showSeasonPickerSheet: Bool = false
    @State private var episodeScrollPosition = ScrollPosition(idType: String.self)
    @Namespace private var seasonsFocusNamespace
    @Namespace private var episodesFocusNamespace

    private var selectedSeasonSummary: TvSeasonSummary? {
        Self.selectedSeasonSummary(seasons: seasons, selectedSeasonNumber: selectedSeasonNumber)
    }

    private var nextEpisodeTargetID: String? {
        Self.nextEpisodeTargetID(detail: detail, episodes: episodes)
    }

    nonisolated static func usesSeasonPickerSheet(seasonCount: Int) -> Bool {
        seasonCount > 6
    }

    nonisolated static func selectedSeasonSummary(
        seasons: [TvSeasonSummary],
        selectedSeasonNumber: Int
    ) -> TvSeasonSummary? {
        seasons.first { $0.seasonNumber == selectedSeasonNumber } ?? seasons.first
    }

    nonisolated static func nextEpisodeTargetID(
        detail: TvItemDetail,
        episodes: [TvEpisodeCard]
    ) -> String? {
        if let next = detail.nextUp,
           let nextMatch = episodes.first(where: {
               $0.seasonNumber == next.season && $0.episodeNumber == next.episode
           }) {
            return nextMatch.id
        }
        return episodes.first(where: { !$0.watched && $0.isUpcoming != true })?.id
    }

    nonisolated static func scrollTargetEpisodeID(
        overrideID: String?,
        detail: TvItemDetail,
        episodes: [TvEpisodeCard]
    ) -> String? {
        guard let targetID = overrideID ?? nextEpisodeTargetID(detail: detail, episodes: episodes),
              episodes.contains(where: { $0.id == targetID }),
              targetID != episodes.first?.id else {
            return nil
        }
        return targetID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
            if !Self.usesSeasonPickerSheet(seasonCount: seasons.count) {
                HStack(spacing: 10) {
                    ForEach(seasons) { season in
                        let selected = selectedSeasonNumber == season.seasonNumber
                        LunaPillButton(
                            season.localizedName,
                            isSelected: selected,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            guard selectedSeasonNumber != season.seasonNumber else { return }
                            selectedSeasonNumber = season.seasonNumber
                            onSelectSeason(season.seasonNumber)
                        }
                        .id(season.seasonNumber)
                        .prefersDefaultFocus(selected, in: seasonsFocusNamespace)
                    }

                    Spacer(minLength: 12)

                    if !episodes.isEmpty {
                        Text(LunaCopy.episodesCount(episodes.count))
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }
                }
                .padding(.horizontal, detailGutter)
                .padding(.vertical, 6)
                .focusScope(seasonsFocusNamespace)
                .focusSection()
            } else {
                HStack(spacing: 16) {
                    let activeName = selectedSeasonSummary?.localizedName ?? "Sesong \(selectedSeasonNumber)"
                    LunaPillButton(
                        activeName,
                        systemImage: "chevron.down",
                        isSelected: true,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        showSeasonPickerSheet = true
                    }
                    .prefersDefaultFocus(true, in: seasonsFocusNamespace)

                    let displayedEpisodeCount = selectedSeasonSummary?.episodeCount ?? episodes.count
                    if displayedEpisodeCount > 0 {
                        Text(LunaCopy.episodesCount(displayedEpisodeCount))
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, detailGutter)
                .padding(.vertical, 6)
                .focusScope(seasonsFocusNamespace)
                .focusSection()
            }

            if isLoadingEpisodes && episodes.isEmpty {
                LunaLoadingRow(message: "Henter episoder…")
                    .padding(.horizontal, detailGutter)
            } else {
                let nextTargetID = nextEpisodeTargetID
                let preferredEpisodeID = restoreFocusEpisodeID ?? nextTargetID
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
                        ForEach(episodes) { ep in
                            EpisodeCardView(
                                episode: ep,
                                seriesTitle: detail.title,
                                isNextForYou: ep.id == nextTargetID,
                                client: client,
                                focusRequestNonce: ep.id == restoreFocusEpisodeID ? restoreFocusNonce : 0,
                                onFocusChanged: { focused in
                                    if focused {
                                        onEpisodeFocused?(ep)
                                    }
                                },
                                onPlay: { onPlayEpisode(ep) },
                                onPickSource: { onPickEpisodeSource(ep) },
                                onToggleWatched: { onToggleEpisodeWatched(ep) },
                                onRequestDelete: { onDeleteEpisode(ep) }
                            )
                            .id(ep.id)
                            .prefersDefaultFocus(ep.id == preferredEpisodeID, in: episodesFocusNamespace)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, detailGutter)
                    .padding(.vertical, 10)
                }
                .scrollPosition($episodeScrollPosition)
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusScope(episodesFocusNamespace)
                .focusSection()
                .onAppear {
                    scrollToTargetEpisode(overrideID: restoreFocusEpisodeID)
                }
                .onChange(of: episodes) { _, _ in
                    scrollToTargetEpisode(overrideID: restoreFocusEpisodeID)
                }
                .onChange(of: restoreFocusNonce) { _, _ in
                    scrollToTargetEpisode(overrideID: restoreFocusEpisodeID)
                }
            }
        }
        .sheet(isPresented: $showSeasonPickerSheet) {
            DetailSeasonPickerSheetView(
                seriesTitle: detail.title,
                seasons: seasons,
                selectedSeasonNumber: selectedSeasonNumber,
                onPickSeason: { num in
                    showSeasonPickerSheet = false
                    guard selectedSeasonNumber != num else { return }
                    selectedSeasonNumber = num
                    onSelectSeason(num)
                },
                onClose: {
                    showSeasonPickerSheet = false
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    private func scrollToTargetEpisode(overrideID: String? = nil) {
        guard let targetID = Self.scrollTargetEpisodeID(
            overrideID: overrideID,
            detail: detail,
            episodes: episodes
        ) else { return }
        episodeScrollPosition.scrollTo(id: targetID, anchor: .leading)
    }
}

private struct DetailSeasonPickerSheetView: View {
    let seriesTitle: String
    let seasons: [TvSeasonSummary]
    let selectedSeasonNumber: Int
    let onPickSeason: (Int) -> Void
    let onClose: () -> Void

    @State private var seasonScrollPosition = ScrollPosition(idType: Int.self)
    @FocusState private var focusedSeasonNumber: Int?
    @Namespace private var seasonGridNamespace

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 18, alignment: .leading),
        count: 4
    )

    var body: some View {
        LunaSheetContainer(
            title: "Velg sesong",
            subtitle: seriesTitle,
            trailingMeta: LunaCopy.seasonsCount(seasons.count),
            width: .wide,
            maxHeight: 860,
            onClose: onClose
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                    ForEach(seasons) { season in
                        let isSelected = (season.seasonNumber == selectedSeasonNumber)
                        LunaListRow(
                            title: season.localizedName,
                            subtitle: season.episodeCount > 0 ? LunaCopy.episodesCount(season.episodeCount) : nil,
                            isSelected: isSelected,
                            externalIsFocused: focusedSeasonNumber == season.seasonNumber
                        ) {
                            onPickSeason(season.seasonNumber)
                        }
                        .id(season.seasonNumber)
                        .focused($focusedSeasonNumber, equals: season.seasonNumber)
                        .prefersDefaultFocus(isSelected, in: seasonGridNamespace)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollPosition($seasonScrollPosition)
            .scrollClipDisabled()
            .onAppear {
                focusedSeasonNumber = selectedSeasonNumber
                seasonScrollPosition.scrollTo(id: selectedSeasonNumber, anchor: .center)
            }
            .defaultFocus($focusedSeasonNumber, selectedSeasonNumber, priority: .userInitiated)
            .focusScope(seasonGridNamespace)
        }
    }
}
