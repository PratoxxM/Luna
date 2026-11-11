import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let mediaType: String
    let itemId: String
    let initialTitle: String

    @State private var detail: TvItemDetail?
    @State private var selectedSeasonNumber: Int = 1
    @State private var episodes: [TvEpisodeCard] = []
    @State private var isLoading: Bool = true
    @State private var isLoadingEpisodes: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 38) {
                if let detail {
                    headerSection(detail, client: client)

                    if detail.mediaType == "series", let seasons = detail.seasons, !seasons.isEmpty {
                        seasonsSection(detail: detail, seasons: seasons, client: client)
                    }
                } else if isLoading {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Laster \(initialTitle)…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(80)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        Button("Prøv igjen") {
                            Task { await loadDetail() }
                        }
                    }
                    .padding(64)
                }
            }
            .padding(.bottom, 80)
        }
        .task {
            await loadDetail()
        }
    }

    private func headerSection(_ item: TvItemDetail, client: BFFClient?) -> some View {
        let bgURL = client?.resolveArtworkURL(item.backdropUrl ?? item.posterUrl)

        return ZStack(alignment: .bottomLeading) {
            MediaArtworkImage(url: bgURL, placeholderSymbol: "film.stack")
                .frame(maxWidth: .infinity)
                .frame(height: 580)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    if let year = item.year {
                        Text(String(year))
                    }
                    if let vote = item.voteAverage, vote > 0 {
                        Text(String(format: "★ %.1f", vote))
                    }
                    if let genres = item.genres, !genres.isEmpty {
                        Text(genres.prefix(3).joined(separator: " · "))
                    }
                    if let tier = item.availability?.tier {
                        Text(tier.uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.16), in: Capsule())
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.system(size: 50, weight: .bold, design: .rounded))

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(4)
                        .frame(maxWidth: 1020, alignment: .leading)
                }

                HStack(spacing: 20) {
                    Button {
                        startPrimaryPlayback(item)
                    } label: {
                        Label(primaryPlayLabel(item), systemImage: "play.fill")
                            .font(.headline)
                    }

                    Button {
                        Task { await toggleWatchlist(item) }
                    } label: {
                        Label(
                            item.inWatchlist ? "I huskeliste" : "Huskeliste",
                            systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark"
                        )
                    }

                    if item.mediaType == "movie" {
                        Button {
                            Task { await toggleWatched(item) }
                        } label: {
                            Label(
                                item.watched ? "Sett" : "Marker sett",
                                systemImage: item.watched ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 40)
        }
    }

    private func seasonsSection(detail: TvItemDetail, seasons: [TvSeasonSummary], client: BFFClient?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(seasons) { season in
                        Button {
                            selectedSeasonNumber = season.seasonNumber
                            Task { await loadSeasonEpisodes(detail: detail, seasonNumber: season.seasonNumber) }
                        } label: {
                            Text(season.name)
                                .font(.callout.weight(selectedSeasonNumber == season.seasonNumber ? .bold : .regular))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 64)
            }

            if isLoadingEpisodes {
                ProgressView()
                    .padding(.horizontal, 64)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 28) {
                        ForEach(episodes) { ep in
                            Button {
                                sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                                    itemId: ep.itemId,
                                    title: ep.title,
                                    seriesTitle: detail.title,
                                    startPositionSeconds: ep.progress?.positionSeconds
                                )
                            } label: {
                                episodeCard(ep, client: client)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private func episodeCard(_ ep: TvEpisodeCard, client: BFFClient?) -> some View {
        let stillURL = client?.resolveArtworkURL(ep.stillUrl)

        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                MediaArtworkImage(url: stillURL, placeholderSymbol: "tv")
                    .frame(width: 380, height: 214)
                    .clipped()

                if ep.watched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(10)
                }
            }
            .frame(width: 380, height: 214)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("\(ep.codeLabel) · \(ep.title)")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: 380, alignment: .leading)

            if let overview = ep.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 380, alignment: .leading)
            }
        }
    }

    private func primaryPlayLabel(_ item: TvItemDetail) -> String {
        if item.mediaType == "series", let next = item.nextUp {
            return String(format: "Spill S%02dE%02d", next.season, next.episode)
        }
        if let pos = item.progress?.positionSeconds, pos > 30 {
            return "Fortsett avspilling"
        }
        return "Spill av"
    }

    private func startPrimaryPlayback(_ item: TvItemDetail) {
        if item.mediaType == "series" {
            let s = item.nextUp?.season ?? selectedSeasonNumber
            let e = item.nextUp?.episode ?? episodes.first?.episodeNumber ?? 1
            let epId: String
            if let tmdb = item.ids.tmdb {
                epId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
            } else {
                epId = item.itemId
            }
            sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                itemId: epId,
                title: item.title,
                seriesTitle: item.title,
                startPositionSeconds: item.progress?.positionSeconds
            )
        } else {
            sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                itemId: item.itemId,
                title: item.title,
                seriesTitle: nil,
                startPositionSeconds: item.progress?.positionSeconds
            )
        }
    }

    private func loadDetail() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await client.fetchItemDetail(mediaType: mediaType, itemId: itemId)
            detail = loaded
            if loaded.mediaType == "series" {
                let defaultSeason = loaded.nextUp?.season
                    ?? loaded.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                    ?? loaded.seasons?.first?.seasonNumber
                    ?? 1
                selectedSeasonNumber = defaultSeason
                await loadSeasonEpisodes(detail: loaded, seasonNumber: defaultSeason)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSeasonEpisodes(detail: TvItemDetail, seasonNumber: Int) async {
        guard let client = sessionStore.makeClient(),
              let tmdbId = detail.ids.tmdb else { return }
        isLoadingEpisodes = true
        if let seasonRes = try? await client.fetchSeasonEpisodes(tmdbId: tmdbId, seasonNumber: seasonNumber) {
            episodes = seasonRes.episodes
        }
        isLoadingEpisodes = false
    }

    private func toggleWatchlist(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
        try? await client.setWatchlist(
            listed: !item.inWatchlist,
            mediaType: item.mediaType,
            ids: item.ids,
            title: item.title,
            year: item.year
        )
        await loadDetail()
    }

    private func toggleWatched(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
        try? await client.setWatched(
            watched: !item.watched,
            mediaType: item.mediaType,
            ids: item.ids,
            title: item.title,
            year: item.year
        )
        await loadDetail()
    }
}
