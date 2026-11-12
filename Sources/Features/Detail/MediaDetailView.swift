import SwiftUI
import AetherBridge

struct MediaDetailView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @EnvironmentObject private var ambient: AmbientBackdropController

    let mediaType: String
    let itemId: String
    let initialTitle: String

    @State private var detail: TvItemDetail?
    @State private var selectedSeasonNumber: Int = 1
    @State private var episodes: [TvEpisodeCard] = []
    @State private var isLoading: Bool = true
    @State private var isLoadingEpisodes: Bool = false
    @State private var errorMessage: String?

    // Silent 450ms Pre-Resolve state
    @State private var preparedToken: String?
    @State private var preparedSessionId: String?
    @State private var preparedForItemId: String?
    @State private var prewarmedStreamToken: String?
    @State private var isPreResolvedReady: Bool = false
    @State private var preResolveTask: Task<Void, Never>?

    @State private var sourcePickerContext: SourcePickerContext?

    @Namespace private var detailFocusNamespace

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                if let detail {
                    heroHeaderSection(detail, client: client)

                    if detail.mediaType == "series", let seasons = detail.seasons, !seasons.isEmpty {
                        seasonsAndEpisodesSection(detail: detail, seasons: seasons, client: client)
                    }

                    if let cast = detail.cast, !cast.isEmpty {
                        castSection(cast)
                    }
                } else if isLoading {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter detaljer for \(initialTitle)…")
                            .font(.title3)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(80)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadDetail() }
                        }
                    }
                    .padding(LunaTheme.horizontalGutter)
                }
            }
            .padding(.bottom, 84)
        }
        .focusScope(detailFocusNamespace)
        .sheet(item: $sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked in
                    let target = ctx
                    sourcePickerContext = nil
                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                        itemId: target.itemId,
                        title: target.title,
                        seriesTitle: target.seriesTitle,
                        startPositionSeconds: target.startPositionSeconds,
                        candidateId: picked.candidateId,
                        backdropUrl: detail?.backdropUrl,
                        logoUrl: detail?.logoUrl
                    )
                },
                onCancel: {
                    sourcePickerContext = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .task(id: "\(mediaType)#\(itemId)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)") {
            await loadDetail()
        }
        .onDisappear {
            preResolveTask?.cancel()
            preResolveTask = nil
            if sessionStore.activePlaybackTarget == nil {
                if let tok = prewarmedStreamToken, tok.count >= 8 {
                    EngineLog.unregisterSecret(tok)
                    prewarmedStreamToken = nil
                }
                if let sid = preparedSessionId, let client = sessionStore.makeClient() {
                    preparedSessionId = nil
                    preparedToken = nil
                    isPreResolvedReady = false
                    Task.detached(priority: .utility) {
                        _ = try? await client.sendHeartbeat(
                            sessionId: sid,
                            state: "stopped",
                            positionSeconds: 0,
                            durationSeconds: 0
                        )
                    }
                }
            }
        }
    }

    // MARK: - Header & Streamlined CTA Bar

    private func heroHeaderSection(_ item: TvItemDetail, client: MediaOSClient?) -> some View {
        let bgURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl ?? item.posterUrl)
        let logoURL = client?.resolveArtworkURL(item.logoUrl)

        return ZStack(alignment: .bottomLeading) {
            CachedArtworkView(
                url: bgURL,
                client: client,
                maxPixelSize: 1920,
                blurHash: item.blurHash,
                dominantColor: item.dominantColor,
                placeholderSymbol: "film.stack",
                contentMode: .fill
            )
            .frame(maxWidth: .infinity)
            .frame(height: 610)
            .clipped()

            LinearGradient(
                colors: [
                    LunaTheme.canvas.opacity(0.05),
                    LunaTheme.canvas.opacity(0.62),
                    LunaTheme.canvas.opacity(0.97),
                    LunaTheme.canvas
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    LunaTheme.canvas.opacity(0.82),
                    LunaTheme.canvas.opacity(0.32),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 20) {
                // ClearLogo or clean typography title
                if let logoURL {
                    CachedArtworkView(
                        url: logoURL,
                        client: client,
                        maxPixelSize: 800,
                        placeholderSymbol: "sparkles.tv",
                        contentMode: .fit
                    )
                    .frame(maxWidth: 520, maxHeight: 118, alignment: .bottomLeading)
                } else {
                    Text(item.title)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: 980, alignment: .leading)
                }

                // Clean single-line metadata + optional local/upcoming pill
                HStack(spacing: 14) {
                    Text(detailMetadataLine(item))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.88))

                    if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text("Kommer: \(upcomingBadge)")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LunaTheme.canvas)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(LunaTheme.amber, in: Capsule())
                    } else if let avail = item.availability, avail.isLocalNvme || avail.isLocalArchive {
                        Text(avail.householdBadgeLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(avail.isLocalNvme ? LunaTheme.emerald : LunaTheme.moonlight)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }
                }

                // Overview
                if let overview = item.preferredOverview {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.88))
                        .lineLimit(3)
                        .frame(maxWidth: 1020, alignment: .leading)
                }

                // Streamlined Action Bar: Focus lands directly on Primary Play!
                HStack(spacing: 16) {
                    PrimaryPlayButton(
                        title: primaryPlayLabel(item),
                        isWarmReady: isPreResolvedReady
                    ) {
                        launchPrimaryPlayback(item)
                    }
                    .prefersDefaultFocus(true, in: detailFocusNamespace)

                    LunaPillButton(
                        item.inWatchlist ? "I huskeliste" : "Huskeliste",
                        systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark",
                        isSelected: item.inWatchlist
                    ) {
                        Task { await toggleWatchlist(item) }
                    }

                    LunaPillButton(
                        watchedButtonTitle(item),
                        systemImage: item.watched ? "checkmark.circle.fill" : "checkmark.circle",
                        isSelected: item.watched
                    ) {
                        Task { await handleHeroWatchedTap(item) }
                    }

                    LunaPillButton("Bytt kilde", systemImage: "arrow.triangle.2.circlepath") {
                        let target = primaryTargetInfo(item)
                        sourcePickerContext = SourcePickerContext(
                            itemId: target.itemId,
                            title: target.title,
                            seriesTitle: target.seriesTitle,
                            startPositionSeconds: target.startPos,
                            existingPrepareToken: preparedForItemId == target.itemId ? preparedToken : nil,
                            backdropUrl: item.backdropUrl ?? item.cardBackdropUrl,
                            logoUrl: item.logoUrl
                        )
                    }

                    LunaPillButton(
                        "",
                        systemImage: item.favoriteFlag ? "star.fill" : "star",
                        isSelected: item.favoriteFlag,
                        prominence: .subtleChip
                    ) {
                        Task { await toggleFavorite(item) }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, 34)
        }
    }

    // MARK: - Seasons & 16:9 Episodes

    private func seasonsAndEpisodesSection(
        detail: TvItemDetail,
        seasons: [TvSeasonSummary],
        client: MediaOSClient?
    ) -> some View {
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
                            Task { await loadSeasonEpisodes(detail: detail, seasonNumber: season.seasonNumber) }
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()

            if isLoadingEpisodes {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Henter episoder…")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 28) {
                        ForEach(episodes) { ep in
                            EpisodeCardView(
                                episode: ep,
                                client: client,
                                onPlay: {
                                    guard ep.isUpcoming != true else { return }
                                    let usePrep = (preparedForItemId == ep.itemId) ? preparedToken : nil
                                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                                        itemId: ep.itemId,
                                        title: ep.title,
                                        seriesTitle: detail.title,
                                        startPositionSeconds: ep.progress?.positionSeconds,
                                        prepareToken: usePrep,
                                        backdropUrl: ep.stillUrl ?? detail.backdropUrl,
                                        logoUrl: detail.logoUrl
                                    )
                                },
                                onPickSource: {
                                    guard ep.isUpcoming != true else { return }
                                    sourcePickerContext = SourcePickerContext(
                                        itemId: ep.itemId,
                                        title: ep.title,
                                        seriesTitle: detail.title,
                                        startPositionSeconds: ep.progress?.positionSeconds,
                                        existingPrepareToken: preparedForItemId == ep.itemId ? preparedToken : nil
                                    )
                                },
                                onToggleWatched: {
                                    Task { await toggleEpisodeWatched(detail: detail, episode: ep) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 18)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func castSection(_ castNames: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medvirkende")
                .font(.headline.weight(.bold))
                .foregroundStyle(LunaTheme.moonlight)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(castNames.prefix(12), id: \.self) { actor in
                        Text(actor)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(LunaTheme.moonlight.opacity(0.85))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(LunaTheme.surfaceRaised.opacity(0.8), in: Capsule())
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
            }
        }
    }

    // MARK: - Playback Target & Silent 450ms Pre-Resolve

    private func detailMetadataLine(_ item: TvItemDetail) -> String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let vote = item.voteAverage, vote > 0 {
            parts.append(String(format: "★ %.1f", vote))
        }
        if let genres = item.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func primaryPlayLabel(_ item: TvItemDetail) -> String {
        if item.mediaType == "series" {
            if let next = item.nextUp {
                if let pos = item.progress?.positionSeconds, pos > 30,
                   item.progress?.season == next.season,
                   item.progress?.episode == next.episode {
                    return String(format: "Fortsett S%02dE%02d", next.season, next.episode)
                }
                return String(format: "Spill S%02dE%02d", next.season, next.episode)
            }
            return "Spill S01E01"
        }
        if let pos = item.progress?.positionSeconds, pos > 30 {
            return "Fortsett"
        }
        return "Spill av"
    }

    private func primaryTargetInfo(_ item: TvItemDetail) -> (itemId: String, title: String, seriesTitle: String?, startPos: Double?) {
        if item.mediaType == "series" {
            let s = item.nextUp?.season ?? selectedSeasonNumber
            let playable = episodes.filter { $0.isUpcoming != true }
            let e = item.nextUp?.episode ?? playable.first?.episodeNumber ?? 1
            let epId: String
            if let tmdb = item.ids.tmdb {
                epId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
            } else {
                epId = item.itemId
            }
            let matchingEp = episodes.first { $0.seasonNumber == s && $0.episodeNumber == e }
            let startPos = matchingEp?.progress?.positionSeconds ?? item.progress?.positionSeconds
            return (epId, matchingEp?.title ?? item.title, item.title, startPos)
        }
        return (item.itemId, item.title, nil, item.progress?.positionSeconds)
    }

    private func launchPrimaryPlayback(_ item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        let matchingToken = (preparedForItemId == target.itemId) ? preparedToken : nil
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            startPositionSeconds: target.startPos,
            prepareToken: matchingToken,
            backdropUrl: item.backdropUrl ?? item.cardBackdropUrl,
            logoUrl: item.logoUrl
        )
    }

    /// 450ms debounced `POST /api/tv/v1/playback/prepare` + strict NVMe/VFS-only
    /// `AetherEngine.prewarm(byteBudget: 8 MiB)` (never spins up mechanical archive drives!).
    private func scheduleSilentPreResolve(for item: TvItemDetail) {
        let target = primaryTargetInfo(item)
        if preparedForItemId == target.itemId, let existingToken = preparedToken, !existingToken.isEmpty {
            return
        }
        preResolveTask?.cancel()
        if preparedForItemId != target.itemId {
            if let oldTok = prewarmedStreamToken, oldTok.count >= 8 {
                EngineLog.unregisterSecret(oldTok)
                prewarmedStreamToken = nil
            }
            preparedToken = nil
            preparedSessionId = nil
            isPreResolvedReady = false
        }

        preResolveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let client = sessionStore.makeClient() else { return }

            guard let prep = try? await client.preparePlayback(
                itemId: target.itemId,
                title: target.title,
                seriesTitle: target.seriesTitle,
                startPositionSeconds: target.startPos
            ), !Task.isCancelled else {
                return
            }

            if let token = prep.prepareToken, !token.isEmpty {
                self.preparedToken = token
                self.preparedSessionId = prep.playbackSession?.sessionId
                self.preparedForItemId = target.itemId
                self.isPreResolvedReady = true
            }

            if let streamTok = prep.playbackSession?.streamToken, streamTok.count >= 8 {
                if let oldTok = self.prewarmedStreamToken, oldTok.count >= 8, oldTok != streamTok {
                    EngineLog.unregisterSecret(oldTok)
                }
                _ = EngineLog.registerSecret(streamTok)
                self.prewarmedStreamToken = streamTok
            }

            // Strictly respect `canClientPrewarmBytes == true` so mechanical archive drives
            // are NEVER spun up merely by opening a detail page!
            if prep.canClientPrewarmBytes == true,
               let relStreamPath = prep.playbackSession?.stream.url,
               let streamURL = client.buildAbsoluteURL(relStreamPath) {
                let headers = client.streamHTTPHeaders()
                Task.detached(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    if !AetherEngine.isPrewarmed(url: streamURL) {
                        _ = await AetherEngine.prewarm(
                            url: streamURL,
                            httpHeaders: headers,
                            byteBudget: 8 * 1024 * 1024
                        )
                    }
                }
            }
        }
    }

    // MARK: - Data Loading & Mutations

    private func watchedButtonTitle(_ item: TvItemDetail) -> String {
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            return String(format: "Sett S%02dE%02d", next.season, next.episode)
        }
        return "Sett"
    }

    private func loadDetail(preserveSeason: Bool = false) async {
        guard let client = sessionStore.makeClient() else { return }
        if detail == nil {
            isLoading = true
        }
        errorMessage = nil

        let requestedSeason: Int? = (preserveSeason && mediaType == "series") ? selectedSeasonNumber : nil

        do {
            let loaded = try await client.fetchItemDetail(
                mediaType: mediaType,
                itemId: itemId,
                seasonNumber: requestedSeason
            )
            detail = loaded
            ambient.setImmediate(
                dominantColor: loaded.dominantColor,
                backdropURL: client.resolveArtworkURL(loaded.backdropUrl ?? loaded.cardBackdropUrl ?? loaded.posterUrl),
                blurHash: loaded.blurHash
            )

            if loaded.mediaType == "series" {
                let targetSeason: Int
                if preserveSeason && selectedSeasonNumber > 0 {
                    targetSeason = selectedSeasonNumber
                } else {
                    targetSeason = loaded.selectedSeason
                        ?? loaded.nextUp?.season
                        ?? loaded.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                        ?? 1
                    selectedSeasonNumber = targetSeason
                }
                if let inlineEpisodes = loaded.episodes,
                   !inlineEpisodes.isEmpty,
                   loaded.selectedSeason == targetSeason {
                    episodes = inlineEpisodes
                } else {
                    await loadSeasonEpisodes(detail: loaded, seasonNumber: targetSeason)
                }
            }

            scheduleSilentPreResolve(for: loaded)
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
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
        let nextVal = !item.inWatchlist
        detail?.inWatchlist = nextVal
        try? await client.setWatchlist(
            listed: nextVal,
            mediaType: item.mediaType,
            ids: item.ids,
            title: item.title,
            year: item.year
        )
        sessionStore.notifyContentMutated()
        await loadDetail(preserveSeason: true)
    }

    private func toggleFavorite(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextVal = !item.favoriteFlag
        detail?.isFavorite = nextVal
        try? await client.setFavorite(
            favorite: nextVal,
            mediaType: item.mediaType,
            ids: item.ids,
            title: item.title,
            year: item.year
        )
        sessionStore.notifyContentMutated()
        await loadDetail(preserveSeason: true)
    }

    private func handleHeroWatchedTap(_ item: TvItemDetail) async {
        if item.mediaType == "series", !item.watched, let next = item.nextUp {
            if let idx = episodes.firstIndex(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }) {
                await toggleEpisodeWatched(detail: item, episode: episodes[idx])
                return
            }
            guard let client = sessionStore.makeClient() else { return }
            do {
                try await client.setWatched(
                    watched: true,
                    mediaType: "episode",
                    ids: item.ids,
                    title: item.title,
                    year: item.year,
                    season: next.season,
                    episode: next.episode
                )
                sessionStore.notifyContentMutated()
                await loadDetail(preserveSeason: true)
            } catch {}
            return
        }
        await toggleWatched(item)
    }

    private func toggleWatched(_ item: TvItemDetail) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextWatched = !item.watched
        detail?.watched = nextWatched
        do {
            try await client.setWatched(
                watched: nextWatched,
                mediaType: item.mediaType,
                ids: item.ids,
                title: item.title,
                year: item.year
            )
            sessionStore.notifyContentMutated()
            await loadDetail(preserveSeason: true)
        } catch {
            detail?.watched = item.watched
        }
    }

    private func toggleEpisodeWatched(detail: TvItemDetail, episode: TvEpisodeCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let targetWatched = !episode.watched
        if let idx = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[idx].watched = targetWatched
            if targetWatched {
                episodes[idx].progress = nil
            }
        }
        do {
            try await client.setWatched(
                watched: targetWatched,
                mediaType: "episode",
                ids: detail.ids,
                title: detail.title,
                year: detail.year,
                season: episode.seasonNumber,
                episode: episode.episodeNumber
            )
            sessionStore.notifyContentMutated()
            await loadDetail(preserveSeason: true)
        } catch {
            if let idx = episodes.firstIndex(where: { $0.id == episode.id }) {
                episodes[idx].watched = episode.watched
            }
        }
    }
}

// MARK: - Dedicated Primary Play CTA Button

private struct PrimaryPlayButton: View {
    let title: String
    let isWarmReady: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryPlayLabel(title: title, isWarmReady: isWarmReady)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }
}

private struct PrimaryPlayLabel: View {
    @Environment(\.isFocused) private var focused

    let title: String
    let isWarmReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.headline.weight(.black))
            Text(title)
                .font(.headline.weight(.bold))
            if isWarmReady {
                Circle()
                    .fill(LunaTheme.canvas.opacity(0.65))
                    .frame(width: 7, height: 7)
            }
        }
        .foregroundStyle(LunaTheme.canvas)
        .padding(.horizontal, 32)
        .padding(.vertical, 15)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: focused
                            ? [Color.white, LunaTheme.amber]
                            : [LunaTheme.amber, LunaTheme.amberDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(focused ? 0.95 : 0.35), lineWidth: focused ? 2.5 : 1.0)
        )
        .shadow(
            color: LunaTheme.amber.opacity(focused ? 0.55 : 0.22),
            radius: focused ? 22 : 10,
            x: 0,
            y: focused ? 8 : 4
        )
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: focused)
    }
}
