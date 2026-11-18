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
    ) -> (itemId: String, title: String, seriesTitle: String?, season: Int?, episode: Int?, startPos: Double?) {
        if let direct = card.directPlayTarget {
            let parsedFromId = EpisodeTitleFormatter.parseEpisodeFromItemId(direct.itemId)
            let s = direct.season ?? card.nextUp?.season ?? card.progress?.season ?? parsedFromId?.season
            let e = direct.episode ?? card.nextUp?.episode ?? card.progress?.episode ?? parsedFromId?.episode
            let isEpisode = EpisodeTitleFormatter.isEpisodeTarget(
                itemId: direct.itemId,
                mediaType: direct.mediaType ?? (card.mediaType == "series" ? "episode" : card.mediaType),
                seriesTitle: direct.seriesTitle ?? (card.mediaType == "series" ? card.title : nil),
                season: s,
                episode: e
            )
            let seriesName = card.mediaType == "series" ? card.title : direct.seriesTitle
            let displayTitle: String
            if isEpisode {
                let clean = card.nonGenericEpisodeTitle
                    ?? EpisodeTitleFormatter.nonGenericEpisodeTitle(
                        direct.title,
                        seriesTitle: seriesName,
                        season: s,
                        episode: e,
                        episodeCode: card.episodeCode
                    )
                displayTitle = clean ?? ""
            } else {
                displayTitle = direct.title ?? card.title
            }
            return (
                direct.itemId,
                displayTitle,
                seriesName,
                s,
                e,
                direct.startPositionSeconds ?? card.progress?.positionSeconds
            )
        }
        if card.mediaType == "series", let next = card.nextUp, let tmdb = card.ids.tmdb {
            let clean = card.nonGenericEpisodeTitle
            return (
                "episode:tmdb:\(tmdb):s\(next.season):e\(next.episode)",
                clean ?? "",
                card.title,
                next.season,
                next.episode,
                card.progress?.positionSeconds
            )
        }
        if card.mediaType == "series",
           let s = card.progress?.season,
           let e = card.progress?.episode,
           let tmdb = card.ids.tmdb {
            let clean = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                card.episodeTitle,
                seriesTitle: card.title,
                season: s,
                episode: e,
                episodeCode: card.episodeCode
            )
            return (
                "episode:tmdb:\(tmdb):s\(s):e\(e)",
                clean ?? "",
                card.title,
                s,
                e,
                card.progress?.positionSeconds
            )
        }
        if card.mediaType == "series" {
            let parsedCode = EpisodeTitleFormatter.parseEpisodeCode(card.episodeCode)
            return (
                card.itemId,
                card.nonGenericEpisodeTitle ?? "",
                card.title,
                parsedCode?.season,
                parsedCode?.episode,
                card.progress?.positionSeconds
            )
        }
        return (card.itemId, card.title, nil, nil, nil, card.progress?.positionSeconds)
    }

    static func launchPlayback(for card: TvMediaCard, sessionStore: AppSessionStore) {
        let resolved = resolvePlayTarget(for: card)
        sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: resolved.itemId,
            title: resolved.title,
            seriesTitle: resolved.seriesTitle,
            season: resolved.season,
            episode: resolved.episode,
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
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
            return false
        }
    }

    static func removeFromOngoing(
        for card: TvMediaCard,
        sessionStore: AppSessionStore
    ) async throws -> Bool {
        guard let client = sessionStore.makeClient() else { return false }
        do {
            try await client.removeFromOngoing(
                mediaType: card.mediaType,
                itemId: card.itemId,
                ids: card.ids,
                title: card.title
            )
            return true
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
            return false
        }
    }

    static func removeFromList(
        for card: TvMediaCard,
        rowId: String,
        sessionStore: AppSessionStore
    ) async throws -> Bool {
        guard let client = sessionStore.makeClient() else { return false }
        do {
            try await client.removeFromList(
                rowId: rowId,
                mediaType: card.mediaType,
                itemId: card.itemId,
                ids: card.ids,
                title: card.title
            )
            return true
        } catch LunaCoreError.unauthorized {
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
        } catch LunaCoreError.unauthorized {
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
    var removeActionTitle: String? = nil
    var onRemoveFromContainer: (() -> Void)? = nil
    var onRequestDelete: (() -> Void)? = nil

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

        if let removeActionTitle, let onRemoveFromContainer {
            Button(action: onRemoveFromContainer) {
                Label(removeActionTitle, systemImage: "minus.circle")
            }
        }

        if let onRequestDelete {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Slett fra NAS…", systemImage: "trash")
            }
        }
    }
}
