import SwiftUI

struct TransientErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(LunaTheme.amber)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(LunaTheme.cinemaGlass, in: Capsule())
            .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.45), lineWidth: 1))
    }
}

@MainActor
enum MediaCardMutator {
    static func resolvePlayTarget(
        for card: TvMediaCard
    ) -> (itemId: String, title: String, seriesTitle: String?, startPos: Double?) {
        if let direct = card.directPlayTarget {
            let displayTitle = card.episodeTitle ?? direct.title ?? card.title
            let seriesName = card.mediaType == "series" ? card.title : direct.seriesTitle
            return (
                direct.itemId,
                displayTitle,
                seriesName,
                direct.startPositionSeconds ?? card.progress?.positionSeconds
            )
        }
        if card.mediaType == "series", let next = card.nextUp, let tmdb = card.ids.tmdb {
            return (
                "episode:tmdb:\(tmdb):s\(next.season):e\(next.episode)",
                card.episodeTitle ?? card.title,
                card.title,
                card.progress?.positionSeconds
            )
        }
        if card.mediaType == "series",
           let s = card.progress?.season,
           let e = card.progress?.episode,
           let tmdb = card.ids.tmdb {
            return (
                "episode:tmdb:\(tmdb):s\(s):e\(e)",
                card.title,
                card.title,
                card.progress?.positionSeconds
            )
        }
        return (card.itemId, card.title, nil, card.progress?.positionSeconds)
    }

    static func launchPlayback(for card: TvMediaCard, sessionStore: AppSessionStore) {
        let resolved = resolvePlayTarget(for: card)
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: resolved.itemId,
            title: resolved.title,
            seriesTitle: resolved.seriesTitle,
            startPositionSeconds: resolved.startPos,
            backdropUrl: card.preferredLandscapePath,
            logoUrl: card.logoUrl
        )
    }

    static func setWatchlist(
        for card: TvMediaCard,
        listed: Bool,
        sessionStore: AppSessionStore
    ) async throws -> Bool {
        guard let client = sessionStore.makeClient() else { return false }
        do {
            try await client.setWatchlist(
                listed: listed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            return true
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
            return false
        }
    }

    static func setFavorite(
        for card: TvMediaCard,
        favorite: Bool,
        sessionStore: AppSessionStore
    ) async throws -> Bool {
        guard let client = sessionStore.makeClient() else { return false }
        do {
            try await client.setFavorite(
                favorite: favorite,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            return true
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
            return false
        }
    }

    static func toggleWatched(
        for card: TvMediaCard,
        watched: Bool,
        preferSeriesEpisodeTarget: Bool = false,
        sessionStore: AppSessionStore
    ) async throws -> Bool {
        guard let client = sessionStore.makeClient() else { return false }
        do {
            if preferSeriesEpisodeTarget && card.mediaType == "series" && (watched || card.directPlayTarget?.season != nil) {
                let s = card.directPlayTarget?.season ?? card.nextUp?.season ?? card.progress?.season
                let e = card.directPlayTarget?.episode ?? card.nextUp?.episode ?? card.progress?.episode
                if let s, let e {
                    try await client.setWatched(
                        watched: watched,
                        mediaType: "episode",
                        ids: card.ids,
                        title: card.title,
                        year: card.year,
                        season: s,
                        episode: e
                    )
                    return true
                }
            }
            try await client.setWatched(
                watched: watched,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            return true
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
            return false
        }
    }
}

struct StandardPosterContextMenuItems: View {
    let card: TvMediaCard
    var onPlay: (() -> Void)? = nil
    let onOpenDetails: () -> Void
    var onToggleWatched: (() -> Void)? = nil
    let onToggleWatchlist: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        if let onPlay {
            Button(action: onPlay) {
                Label("Spill av", systemImage: "play.fill")
            }
        }

        Button(action: onOpenDetails) {
            Label("Åpne detaljer", systemImage: "info.circle")
        }

        if let onToggleWatched {
            Button(action: onToggleWatched) {
                Label(
                    card.progress?.watched == true ? "Marker som usett" : "Marker som sett",
                    systemImage: card.progress?.watched == true ? "eye.slash" : "checkmark.circle"
                )
            }
        }

        Button(action: onToggleWatchlist) {
            Label(
                card.inWatchlist == true ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                systemImage: card.inWatchlist == true ? "bookmark.slash" : "bookmark"
            )
        }

        Button(action: onToggleFavorite) {
            Label(
                card.isFavorite == true ? "Fjern favoritt" : "Marker som favoritt",
                systemImage: card.isFavorite == true ? "star.slash" : "star.fill"
            )
        }
    }
}
