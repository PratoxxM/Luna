import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var homePayload: TvHomeResponse?
    @State private var cachedEtag: String?
    @State private var isInitialColdFetch: Bool = false
    @State private var errorMessage: String?

    @State private var selectedCard: TvMediaCard?
    @State private var sourcePickerContext: SourcePickerContext?

    @Namespace private var homeFocusNamespace

    private static let canonicalHomeRowIDs: Set<String> = [
        "medialogg-continue",
        "upcoming-episodes",
        "popular-movies",
        "popular-series"
    ]

    init(initialRoomName: String = "Stua", initialHardwareProfile: String = "hdr10-512") {
        let snap = DiskSWRStore.loadHomeSynchronously(
            roomName: initialRoomName,
            hardwareProfile: initialHardwareProfile
        )
        _homePayload = State(initialValue: snap?.payload)
        _cachedEtag = State(initialValue: snap?.etag)
    }

    private var visibleRows: [TvShelfRow] {
        (homePayload?.rows ?? []).filter { row in
            Self.canonicalHomeRowIDs.contains(row.rowId) && !row.items.isEmpty
        }
    }

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 38) {
                if visibleRows.isEmpty && isInitialColdFetch {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter innhold…")
                            .font(.title3)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 64)
                }

                if let errorMessage, visibleRows.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await revalidateHome(forceUnconditional: true) }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                }

                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { rowIndex, row in
                    ShelfRowView(
                        row: row,
                        isFirstRow: rowIndex == 0,
                        focusNamespace: homeFocusNamespace,
                        client: client,
                        onSelectCard: { card in
                            selectedCard = card
                        },
                        onPlayContinueCard: { card in
                            launchDirectPlayback(for: card)
                        },
                        onPickSourceForCard: { card in
                            openSourcePicker(for: card)
                        },
                        onToggleWatchlist: { card in
                            Task { await toggleWatchlist(for: card) }
                        },
                        onToggleFavorite: { card in
                            Task { await toggleFavorite(for: card) }
                        },
                        onMarkWatched: { card in
                            Task { await markWatched(for: card) }
                        }
                    )
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 84)
        }
        .focusScope(homeFocusNamespace)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
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
                        backdropUrl: target.backdropUrl,
                        logoUrl: target.logoUrl
                    )
                },
                onCancel: {
                    sourcePickerContext = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .task(id: "\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)#\(sessionStore.homeRefreshNonce)") {
            await syncDiskSnapshotIfRoomChanged()
            await revalidateHome(forceUnconditional: false)
        }
    }

    private func syncDiskSnapshotIfRoomChanged() async {
        let targetRoom = sessionStore.roomName
        let targetProfile = sessionStore.effectiveHardwareProfile
        guard let current = homePayload else {
            if let snap = await DiskSWRStore.loadHomeAsync(
                roomName: targetRoom,
                hardwareProfile: targetProfile
            ), !Task.isCancelled {
                homePayload = snap.payload
                cachedEtag = snap.etag
            }
            return
        }
        if current.roomName != targetRoom || current.hardwareProfile != targetProfile {
            if let snap = await DiskSWRStore.loadHomeAsync(
                roomName: targetRoom,
                hardwareProfile: targetProfile
            ), !Task.isCancelled {
                homePayload = snap.payload
                cachedEtag = snap.etag
            } else {
                cachedEtag = nil
            }
        }
    }

    private func revalidateHome(forceUnconditional: Bool) async {
        guard let client = sessionStore.makeClient() else { return }
        if homePayload == nil {
            isInitialColdFetch = true
        }
        errorMessage = nil

        do {
            let result = try await client.fetchHomeConditional(
                ifNoneMatch: forceUnconditional ? nil : cachedEtag
            )
            switch result {
            case .notModified:
                break
            case .updated(let payload, let newEtag, let rawData):
                cachedEtag = newEtag
                if homePayload != payload {
                    withAnimation(.easeOut(duration: 0.22)) {
                        homePayload = payload
                    }
                }
                DiskSWRStore.saveHomeInBackground(
                    rawPayloadData: rawData,
                    etag: newEtag,
                    roomName: sessionStore.roomName,
                    hardwareProfile: sessionStore.effectiveHardwareProfile
                )
            }
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            if homePayload == nil {
                errorMessage = error.localizedDescription
            }
        }
        isInitialColdFetch = false
    }

    private func resolvePlayTarget(for card: TvMediaCard) -> (itemId: String, title: String, seriesTitle: String?, startPos: Double?) {
        if let direct = card.directPlayTarget {
            let displayTitle = card.episodeTitle ?? direct.title ?? card.title
            let seriesName = card.mediaType == "series" ? card.title : direct.seriesTitle
            return (direct.itemId, displayTitle, seriesName, direct.startPositionSeconds ?? card.progress?.positionSeconds)
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

    private func launchDirectPlayback(for card: TvMediaCard) {
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

    private func openSourcePicker(for card: TvMediaCard) {
        let resolved = resolvePlayTarget(for: card)
        sourcePickerContext = SourcePickerContext(
            itemId: resolved.itemId,
            title: resolved.title,
            seriesTitle: resolved.seriesTitle,
            startPositionSeconds: resolved.startPos,
            backdropUrl: card.preferredLandscapePath,
            logoUrl: card.logoUrl
        )
    }

    private func toggleWatchlist(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextListed = !(card.inWatchlist ?? false)
        try? await client.setWatchlist(
            listed: nextListed,
            mediaType: card.mediaType,
            ids: card.ids,
            title: card.title,
            year: card.year
        )
        sessionStore.notifyContentMutated()
        await revalidateHome(forceUnconditional: true)
    }

    private func toggleFavorite(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextFav = !(card.isFavorite ?? false)
        try? await client.setFavorite(
            favorite: nextFav,
            mediaType: card.mediaType,
            ids: card.ids,
            title: card.title,
            year: card.year
        )
        sessionStore.notifyContentMutated()
        await revalidateHome(forceUnconditional: true)
    }

    private func markWatched(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        if card.mediaType == "series" {
            let s = card.directPlayTarget?.season ?? card.nextUp?.season ?? card.progress?.season
            let e = card.directPlayTarget?.episode ?? card.nextUp?.episode ?? card.progress?.episode
            if let s, let e {
                try? await client.setWatched(
                    watched: true,
                    mediaType: "episode",
                    ids: card.ids,
                    title: card.title,
                    year: card.year,
                    season: s,
                    episode: e
                )
            } else {
                try? await client.setWatched(
                    watched: !(card.progress?.watched ?? false),
                    mediaType: "series",
                    ids: card.ids,
                    title: card.title,
                    year: card.year
                )
            }
        } else {
            let nextWatched = !(card.progress?.watched ?? false)
            try? await client.setWatched(
                watched: nextWatched,
                mediaType: "movie",
                ids: card.ids,
                title: card.title,
                year: card.year
            )
        }
        sessionStore.notifyContentMutated()
        await revalidateHome(forceUnconditional: true)
    }
}
