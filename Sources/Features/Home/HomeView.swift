import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var homePayload: TvHomeResponse?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedCard: TvMediaCard?
    @State private var selectedGenre: TvGenreChip?

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 42) {
                if let hero = homePayload?.hero {
                    heroHeader(hero, client: client)
                } else if isLoading {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Laster Hjem for \(sessionStore.roomName)…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(80)
                }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                        Button("Prøv igjen") {
                            Task { await loadHome() }
                        }
                    }
                    .padding(.horizontal, 64)
                }

                if let rows = homePayload?.rows {
                    ForEach(rows) { row in
                        if !row.items.isEmpty || !(row.genres ?? []).isEmpty {
                            ShelfRowView(
                                row: row,
                                client: client,
                                onSelectCard: { card in
                                    selectedCard = card
                                },
                                onPlayContinueCard: { card in
                                    launchCardPlayback(card)
                                },
                                onSelectGenre: { chip in
                                    selectedGenre = chip
                                }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .sheet(item: $selectedGenre) { chip in
            GenreBrowseSheet(chip: chip) { picked in
                selectedGenre = nil
                selectedCard = picked
            }
            .environmentObject(sessionStore)
        }
        .task(id: "\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)") {
            await loadHome()
        }
    }

    private func heroHeader(_ hero: TvHeroBanner, client: BFFClient?) -> some View {
        let bgURL = client?.resolveArtworkURL(hero.backdropUrl ?? hero.posterUrl)

        return ZStack(alignment: .bottomLeading) {
            MediaArtworkImage(url: bgURL, placeholderSymbol: "sparkles.tv")
                .frame(maxWidth: .infinity)
                .frame(height: 620)
                .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text(sessionStore.roomName.uppercased())
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.96, green: 0.77, blue: 0.42).opacity(0.24), in: Capsule())

                    ForEach(hero.badges ?? [], id: \.self) { badge in
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }

                Text(hero.title)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .lineLimit(2)

                if let overview = hero.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(3)
                        .frame(maxWidth: 960, alignment: .leading)
                }

                HStack(spacing: 22) {
                    Button {
                        launchHeroPlayback(hero)
                    } label: {
                        Label(hero.primaryCta ?? "Spill av", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 14)
                    }

                    Button {
                        selectedCard = TvMediaCard(
                            itemId: hero.itemId,
                            mediaType: hero.mediaType,
                            ids: hero.ids,
                            title: hero.title,
                            year: hero.year,
                            overview: hero.overview,
                            posterUrl: hero.posterUrl,
                            backdropUrl: hero.backdropUrl,
                            logoUrl: hero.logoUrl,
                            imdbRating: hero.imdbRating,
                            badges: hero.badges,
                            inWatchlist: hero.inWatchlist,
                            nextUp: hero.nextUp,
                            availability: hero.availability,
                            progress: hero.progress
                        )
                    } label: {
                        Label("Detaljer", systemImage: "info.circle")
                            .font(.headline)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 44)
        }
    }

    private func launchHeroPlayback(_ hero: TvHeroBanner) {
        let targetItemId: String
        if hero.mediaType == "series", let next = hero.nextUp, let tmdb = hero.ids.tmdb {
            targetItemId = "episode:tmdb:\(tmdb):s\(next.season):e\(next.episode)"
        } else {
            targetItemId = hero.itemId
        }
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: targetItemId,
            title: hero.title,
            seriesTitle: hero.mediaType == "series" ? hero.title : nil,
            startPositionSeconds: hero.progress?.positionSeconds
        )
    }

    private func launchCardPlayback(_ card: TvMediaCard) {
        let targetItemId: String
        if card.mediaType == "series", let next = card.nextUp, let tmdb = card.ids.tmdb {
            targetItemId = "episode:tmdb:\(tmdb):s\(next.season):e\(next.episode)"
        } else if card.mediaType == "series",
                  let s = card.progress?.season,
                  let e = card.progress?.episode,
                  let tmdb = card.ids.tmdb {
            targetItemId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
        } else {
            targetItemId = card.itemId
        }
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: targetItemId,
            title: card.title,
            seriesTitle: card.mediaType == "series" ? card.title : nil,
            startPositionSeconds: card.progress?.positionSeconds
        )
    }

    private func loadHome() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil
        do {
            homePayload = try await client.fetchHome()
        } catch BFFError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct GenreBrowseSheet: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    let chip: TvGenreChip
    let onPick: (TvMediaCard) -> Void

    @State private var page: TvRowPageResponse?
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 32)
    ]

    var body: some View {
        let client = sessionStore.makeClient()
        VStack(alignment: .leading, spacing: 24) {
            Text(page?.title ?? chip.label)
                .font(.title2.bold())
                .padding(.horizontal, 48)
                .padding(.top, 36)

            if isLoading {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 36) {
                        ForEach(page?.items ?? []) { card in
                            Button {
                                onPick(card)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    MediaArtworkImage(
                                        url: client?.resolveArtworkURL(card.posterUrl ?? card.backdropUrl),
                                        placeholderSymbol: "film"
                                    )
                                    .frame(width: 230, height: 345)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    Text(card.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.bottom, 48)
                }
            }
        }
        .task {
            guard let client else { return }
            page = try? await client.fetchRow(pathOrRowId: chip.browsePath, offset: 0, limit: 36)
            isLoading = false
        }
    }
}
