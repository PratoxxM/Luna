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
    var onDeleteSeason: (Int) -> Void = { _ in }
    let onDeleteEpisode: (TvEpisodeCard) -> Void

    @State private var showSeasonPickerSheet: Bool = false
    @Namespace private var seasonsFocusNamespace
    @Namespace private var episodesFocusNamespace

    private var selectedSeasonSummary: TvSeasonSummary? {
        seasons.first { $0.seasonNumber == selectedSeasonNumber } ?? seasons.first
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
        VStack(alignment: .leading, spacing: 14) {
            if seasons.count <= 6 {
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
                        "\(activeName) ▾",
                        systemImage: "square.grid.2x2",
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
                            .font(LunaTheme.Font.subtitle)
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
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Henter episoder…")
                        .font(LunaTheme.Font.body)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, detailGutter)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: LunaTokens.Layout.cardGap) {
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
                        .padding(.vertical, 10)
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

    private func scrollToTargetEpisode(proxy: ScrollViewProxy) {
        guard let targetID = nextEpisodeTargetID, targetID != episodes.first?.id else { return }
        proxy.scrollTo(targetID, anchor: .leading)
    }
}

private struct DetailSeasonPickerSheetView: View {
    let seriesTitle: String
    let seasons: [TvSeasonSummary]
    let selectedSeasonNumber: Int
    let onPickSeason: (Int) -> Void
    let onClose: () -> Void

    @FocusState private var focusedSeasonNumber: Int?
    @Namespace private var seasonGridNamespace

    private let gridColumns = Array(
        repeating: GridItem(.fixed(330), spacing: 20, alignment: .leading),
        count: 4
    )

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(seriesTitle)
                            .font(LunaTheme.Font.subtitle)
                            .foregroundStyle(LunaTheme.muted)
                        Text("Velg sesong")
                            .font(LunaTheme.Font.pageTitle)
                            .foregroundStyle(LunaTheme.linen)
                    }

                    Spacer()

                    Text(LunaCopy.seasonsCount(seasons.count))
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.muted)
                }

                Rectangle()
                    .fill(LunaTheme.warmBorderSubtle)
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                            ForEach(seasons) { season in
                                let isSelected = (season.seasonNumber == selectedSeasonNumber)
                                SeasonGridTileButton(
                                    season: season,
                                    isSelected: isSelected,
                                    isFocused: focusedSeasonNumber == season.seasonNumber
                                ) {
                                    onPickSeason(season.seasonNumber)
                                }
                                .id(season.seasonNumber)
                                .focused($focusedSeasonNumber, equals: season.seasonNumber)
                                .prefersDefaultFocus(isSelected, in: seasonGridNamespace)
                            }
                        }
                        .padding(8)
                    }
                    .scrollClipDisabled()
                    .onAppear {
                        focusedSeasonNumber = selectedSeasonNumber
                        proxy.scrollTo(selectedSeasonNumber, anchor: .center)
                    }
                }
                .focusScope(seasonGridNamespace)
            }
            .padding(48)
            .frame(maxWidth: 1480, maxHeight: 860)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .lunaTopLightEdge(
                cornerRadius: LunaTokens.Radius.panel,
                topColor: LunaTokens.Edge.top3,
                sideColor: LunaTokens.Edge.top1
            )
        }
        .onExitCommand {
            onClose()
        }
    }
}

private struct SeasonGridTileButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let season: TvSeasonSummary
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(season.localizedName)
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(1)

                    if season.episodeCount > 0 {
                        Text(LunaCopy.episodesCount(season.episodeCount))
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Text("✓")
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.amber)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    .overlay {
                        if isSelected && !isFocused {
                            RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                                .fill(LunaTokens.Accent.soft)
                        }
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
                            : (isSelected ? LunaTokens.Accent.border : LunaTheme.warmBorderSubtle),
                        lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                    )
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength * 0.7) : .clear,
                radius: isFocused ? 20 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous))
        .focusEffectDisabled(true)
    }
}
