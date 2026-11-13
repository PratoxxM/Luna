import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var homePayload: TvHomeResponse?
    @State private var cachedEtag: String?
    @State private var isInitialColdFetch: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorMessage: String?
    @State private var lastSeenRefreshNonce: Int = -1

    @State private var selectedCard: TvMediaCard?
    @State private var selectedSeeAllRow: TvShelfRow?
    @State private var sourcePickerContext: SourcePickerContext?
    @State private var mutationBannerTask: Task<Void, Never>?

    @Namespace private var homeFocusNamespace

    private static let canonicalHomeRowIDs: Set<String> = [
        "medialogg-continue",
        "upcoming-episodes",
        "popular-movies",
        "popular-series"
    ]

    init(
        initialServerHost: String? = nil,
        initialRoomName: String = "Stua",
        initialHardwareProfile: String = "hdr10-512"
    ) {
        let snap = DiskSWRStore.memorySnapshot(
            serverHost: initialServerHost,
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
                if let mutationErrorMessage {
                    Text(mutationErrorMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LunaTheme.amber)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(LunaTheme.cinemaGlass, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.45), lineWidth: 1))
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                }

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
                        },
                        onSeeAllRow: { row in
                            selectedSeeAllRow = row
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
        .navigationDestination(item: $selectedSeeAllRow) { row in
            CustomRowBrowseView(title: row.title, pathOrRowId: row.nextPath ?? row.rowId)
        }
        .sheet(item: $sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked, reusedPrepareToken in
                    let target = ctx
                    sourcePickerContext = nil
                    sessionStore.activePlaybackTarget = PlaybackLaunchRequest(
                        itemId: target.itemId,
                        title: target.title,
                        seriesTitle: target.seriesTitle,
                        startPositionSeconds: target.startPositionSeconds,
                        candidateId: reusedPrepareToken == nil ? picked.candidateId : nil,
                        prepareToken: reusedPrepareToken,
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
        .task(id: "\(sessionStore.serverBaseURL?.host ?? "")#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)") {
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await syncDiskSnapshotIfRoomChanged()
            await revalidateHome(forceUnconditional: false)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            Task { await revalidateHome(forceUnconditional: true) }
        }
        .onDisappear {
            mutationBannerTask?.cancel()
        }
    }

    private func syncDiskSnapshotIfRoomChanged() async {
        let targetHost = sessionStore.serverBaseURL?.host
        let targetRoom = sessionStore.roomName
        let targetProfile = sessionStore.effectiveHardwareProfile
        guard let current = homePayload else {
            if let snap = await DiskSWRStore.loadHomeAsync(
                serverHost: targetHost,
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
                serverHost: targetHost,
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
                    serverHost: sessionStore.serverBaseURL?.host,
                    roomName: sessionStore.roomName,
                    hardwareProfile: sessionStore.effectiveHardwareProfile,
                    decodedPayload: payload
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

    private func showMutationError(_ error: Error) {
        mutationBannerTask?.cancel()
        mutationErrorMessage = "Kunne ikke lagre endring: \(error.localizedDescription)"
        mutationBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            mutationErrorMessage = nil
        }
    }

    private func markLocalMutationAndRevalidate() async {
        lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
        sessionStore.notifyContentMutated()
        await revalidateHome(forceUnconditional: true)
    }

    private func toggleWatchlist(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextListed = !(card.inWatchlist ?? false)
        do {
            try await client.setWatchlist(
                listed: nextListed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            await markLocalMutationAndRevalidate()
        } catch {
            showMutationError(error)
        }
    }

    private func toggleFavorite(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextFav = !(card.isFavorite ?? false)
        do {
            try await client.setFavorite(
                favorite: nextFav,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            await markLocalMutationAndRevalidate()
        } catch {
            showMutationError(error)
        }
    }

    private func markWatched(for card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        do {
            if card.mediaType == "series" {
                let s = card.directPlayTarget?.season ?? card.nextUp?.season ?? card.progress?.season
                let e = card.directPlayTarget?.episode ?? card.nextUp?.episode ?? card.progress?.episode
                if let s, let e {
                    try await client.setWatched(
                        watched: true,
                        mediaType: "episode",
                        ids: card.ids,
                        title: card.title,
                        year: card.year,
                        season: s,
                        episode: e
                    )
                } else {
                    try await client.setWatched(
                        watched: !(card.progress?.watched ?? false),
                        mediaType: "series",
                        ids: card.ids,
                        title: card.title,
                        year: card.year
                    )
                }
            } else {
                let nextWatched = !(card.progress?.watched ?? false)
                try await client.setWatched(
                    watched: nextWatched,
                    mediaType: "movie",
                    ids: card.ids,
                    title: card.title,
                    year: card.year
                )
            }
            await markLocalMutationAndRevalidate()
        } catch {
            showMutationError(error)
        }
    }
}
