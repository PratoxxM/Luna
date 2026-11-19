import SwiftUI

struct DetailSeasonsSectionView: View {
    let detail: TvItemDetail
    let seasons: [TvSeasonSummary]
    @Binding var selectedSeasonNumber: Int
    let episodes: [TvEpisodeCard]
    let isLoadingEpisodes: Bool
    let client: LunaCoreClient?
    let detailGutter: CGFloat

    let onSelectSeason: (Int) -> Void
    let onPlayEpisode: (TvEpisodeCard) -> Void
    let onPickEpisodeSource: (TvEpisodeCard) -> Void
    let onToggleEpisodeWatched: (TvEpisodeCard) -> Void
    let onDeleteSeason: (Int) -> Void
    let onDeleteEpisode: (TvEpisodeCard) -> Void

    @Namespace private var episodesFocusNamespace

    private var hasRemovableEpisodesInSeason: Bool {
        episodes.contains { (ep: TvEpisodeCard) in
            ep.availability?.isPhysicalLocal == true || ep.availability?.isLocalVfs == true
        }
    }

    private var nextEpisodeTargetID: String? {
        if let next = detail.nextUp,
           let nextMatch = episodes.first(where: {
               $0.seasonNumber == next.season && $0.episodeNumber == next.episode
           }) {
            return nextMatch.id
        }
        return episodes.first(where: { !$0.watched && $0.isUpcoming != true })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(seasons) { season in
                        let selected = selectedSeasonNumber == season.seasonNumber
                        LunaPillButton(
                            season.name,
                            badgeText: season.episodeCount > 0 ? String(season.episodeCount) : nil,
                            isSelected: selected,
                            prominence: .subtleChip
                        ) {
                            guard selectedSeasonNumber != season.seasonNumber else { return }
                            selectedSeasonNumber = season.seasonNumber
                            onSelectSeason(season.seasonNumber)
                        }
                    }

                    if hasRemovableEpisodesInSeason {
                        LunaPillButton(
                            "Slett sesong \(selectedSeasonNumber)",
                            systemImage: "trash",
                            prominence: .subtleChip,
                            accent: .coral
                        ) {
                            onDeleteSeason(selectedSeasonNumber)
                        }
                    }
                }
                .padding(.horizontal, detailGutter)
                .padding(.vertical, 10)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()

            if isLoadingEpisodes && episodes.isEmpty {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Henter episoder…")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, detailGutter)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: LunaTokens.Layout.cardGap) {
                            ForEach(episodes) { ep in
                                EpisodeCardView(
                                    episode: ep,
                                    seriesTitle: detail.title,
                                    isNextForYou: ep.id == nextEpisodeTargetID,
                                    client: client,
                                    onPlay: { onPlayEpisode(ep) },
                                    onPickSource: { onPickEpisodeSource(ep) },
                                    onToggleWatched: { onToggleEpisodeWatched(ep) },
                                    onRequestDelete: { onDeleteEpisode(ep) }
                                )
                                .id(ep.id)
                                .prefersDefaultFocus(ep.id == nextEpisodeTargetID, in: episodesFocusNamespace)
                            }
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.vertical, 18)
                    }
                    .contentMargins(.zero, for: .scrollContent)
                    .scrollClipDisabled()
                    .focusScope(episodesFocusNamespace)
                    .focusSection()
                    .onAppear {
                        scrollToTargetEpisode(proxy: proxy)
                    }
                    .onChange(of: episodes.map(\.id)) { _, _ in
                        scrollToTargetEpisode(proxy: proxy)
                    }
                }
            }
        }
    }

    private func scrollToTargetEpisode(proxy: ScrollViewProxy) {
        guard let targetID = nextEpisodeTargetID, targetID != episodes.first?.id else { return }
        proxy.scrollTo(targetID, anchor: .leading)
    }
}
