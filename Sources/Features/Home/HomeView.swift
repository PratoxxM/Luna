import SwiftUI

internal enum HomeRefreshPolicy {
    nonisolated static func shouldRevalidateOnForeground(
        isSceneActive: Bool,
        isActiveTab: Bool,
        hasActivePlayback: Bool,
        secondsSinceLastValidation: TimeInterval,
        minimumIntervalSeconds: TimeInterval = 10
    ) -> Bool {
        guard isSceneActive, isActiveTab, !hasActivePlayback else {
            return false
        }
        return secondsSinceLastValidation >= minimumIntervalSeconds
    }
}

struct HomeView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    let isActiveTab: Bool

    @State private var homePayload: TvHomeResponse?
    @State private var cachedEtag: String?
    @State private var isInitialColdFetch: Bool = false
    @State private var errorMessage: String?
    @State private var mutationErrorMessage: String?
    @State private var lastSeenRefreshNonce: Int = -1
    @State private var lastValidatedAt: Date = .distantPast
    @State private var validatedScopeKey: String?

    @State private var selectedCard: TvMediaCard?
    @State private var selectedSeeAllRow: TvShelfRow?
    @State private var sourcePickerContext: SourcePickerContext?
    @State private var modalToken = UUID()
    @State private var mutationBannerTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0

    @Namespace private var homeFocusNamespace

    private nonisolated static let duplicateWatchlistRowIds: Set<String> = [
        "medialogg-watchlist",
        "custom:medialogg-watchlist",
        "system-watchlist",
        "custom:system-watchlist",
        "watchlist",
    ]

    private nonisolated static let duplicateGenericLocalRowIds: Set<String> = [
        "medialogg-local",
        "custom:medialogg-local",
        "system-local",
        "custom:system-local",
        "local-library",
    ]

    private nonisolated static let duplicateGenericLocalTitles: Set<String> = [
        "lokalt",
        "lokalt på nas",
        "lokalt hos oss",
        "lokal samling",
        "mitt bibliotek",
        "bibliotek",
        "hele samlingen",
    ]

    nonisolated static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        rows.filter { row in
            guard !row.items.isEmpty else { return false }
            let lowerId = row.rowId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerSource = (row.sourceKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Én ting på ett sted: Huskeliste og full lokal samling bor i Bibliotek
            if lowerSource == "watchlist" || duplicateWatchlistRowIds.contains(lowerId) {
                return false
            }
            if duplicateGenericLocalRowIds.contains(lowerId) {
                return false
            }
            if lowerSource == "local_library" && duplicateGenericLocalTitles.contains(lowerTitle) {
                return false
            }
            return true
        }
    }

    nonisolated static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        var rows = filterVisibleRows(payload?.rows ?? [])
        let continueIdx = rows.firstIndex { row in
            row.rowId == "medialogg-continue" || row.sourceKind == "system_continue"
        }

        if let idx = continueIdx {
            var contRow = rows.remove(at: idx)
            let prioritizedItems = prioritizeContinueCards(
                contRow.items,
                preparedFromPhone: payload?.tonight?.preparedFromPhone
            )
            contRow = TvShelfRow(
                rowId: contRow.rowId,
                title: contRow.title,
                rowStyle: contRow.rowStyle,
                sourceKind: contRow.sourceKind,
                listMode: contRow.listMode,
                hasMore: contRow.hasMore,
                nextPath: contRow.nextPath,
                items: prioritizedItems,
                genres: contRow.genres
            )
            rows.insert(contRow, at: 0)
        } else if let prepared = payload?.tonight?.preparedFromPhone {
            let synthetic = TvShelfRow(
                rowId: "medialogg-continue",
                title: "Fortsett å se",
                rowStyle: "continue_backdrop",
                sourceKind: "system_continue",
                listMode: "smart",
                hasMore: false,
                nextPath: nil,
                items: [prepared],
                genres: nil
            )
            rows.insert(synthetic, at: 0)
        }

        return rows
    }

    nonisolated static func prioritizeContinueCards(
        _ items: [TvMediaCard],
        preparedFromPhone: TvMediaCard?
    ) -> [TvMediaCard] {
        var merged = items
        if let prepared = preparedFromPhone {
            merged.removeAll { $0.itemId == prepared.itemId }
            merged.insert(prepared, at: 0)
        }
        let phone = merged.filter { $0.origin == "phone" }
        let tonight = merged.filter { $0.origin == "tonight" }
        let rest = merged.filter { $0.origin != "phone" && $0.origin != "tonight" }
        return phone + tonight + rest
    }

    init(
        initialServerHost: String? = nil,
        initialRoomName: String = "Stua",
        initialHardwareProfile: String = "hdr10-512",
        isActiveTab: Bool = true
    ) {
        self.isActiveTab = isActiveTab
        let snap = DiskSWRStore.memorySnapshot(
            serverHost: initialServerHost,
            roomName: initialRoomName,
            hardwareProfile: initialHardwareProfile
        )
        _homePayload = State(initialValue: snap?.payload)
        _cachedEtag = State(initialValue: snap?.etag)
    }

    private var visibleRows: [TvShelfRow] {
        Self.prepareVisibleRows(from: homePayload)
    }

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 38) {
                if let mutationErrorMessage {
                    TransientErrorBanner(message: mutationErrorMessage)
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
                            .foregroundStyle(LunaTheme.danger)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            scheduleRevalidateHome(forceUnconditional: true)
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
                            MediaCardMutator.launchPlayback(for: card, sessionStore: sessionStore)
                        },
                        onPickSourceForCard: { card in
                            openSourcePicker(for: card)
                        },
                        onToggleWatchlist: { card in
                            Task { await toggleWatchlist(for: card) }
                        },
                        onMarkWatched: { card in
                            Task { await markWatched(for: card) }
                        },
                        onRemoveFromOngoing: { card in
                            Task { await removeFromOngoing(for: card) }
                        },
                        onRemoveFromList: { card, row in
                            Task { await removeFromList(card, row: row) }
                        },
                        onSeeAllRow: { row in
                            selectedSeeAllRow = row
                        }
                    )
                }
            }
            .padding(.bottom, 84)
        }
        .contentMargins(.zero, for: .scrollContent)
        .ignoresSafeArea(edges: .horizontal)
        .lunaRootScrollTopBarTracking(tab: .home)
        .safeAreaPadding(.top, LunaTopBarView.contentTopPadding)
        .focusSection()
        .focusScope(homeFocusNamespace)
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedSeeAllRow) { row in
            let isOngoing = CustomRowContextPolicy.isOngoingList(
                explicitFlag: false,
                rowId: row.rowId,
                sourceKind: row.sourceKind
            )
            if row.nextPath?.contains("/rows/") == true {
                CustomRowBrowseView(title: row.title, pathOrRowId: row.nextPath ?? row.rowId, isOngoingList: isOngoing)
            } else if row.rowId == "popular-movies"
                || row.sourceKind == "system_popular_movies"
                || row.nextPath?.contains("/catalog/movies") == true {
                CatalogBrowseView(mediaType: "movie", initialGenre: nil, isRootTab: false)
            } else if row.rowId == "popular-series"
                || row.sourceKind == "system_popular_series"
                || row.nextPath?.contains("/catalog/series") == true {
                CatalogBrowseView(mediaType: "series", initialGenre: nil, isRootTab: false)
            } else {
                CustomRowBrowseView(title: row.title, pathOrRowId: row.nextPath ?? row.rowId, isOngoingList: isOngoing)
            }
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
                        season: target.season,
                        episode: target.episode,
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
            .environmentObject(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .task(id: "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)") {
            let currentScope = "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
            await syncDiskSnapshotIfRoomChanged()
            if validatedScopeKey == currentScope,
               TabContentFreshnessPolicy.isCacheFresh(
                   hasCachedContent: homePayload != nil,
                   lastValidatedAt: lastValidatedAt,
                   cachedRefreshNonce: lastSeenRefreshNonce,
                   currentRefreshNonce: sessionStore.homeRefreshNonce
               ) {
                return
            }
            reloadTask?.cancel()
            reloadTask = nil
            reloadGeneration &+= 1
            let taskGen = reloadGeneration
            lastSeenRefreshNonce = sessionStore.homeRefreshNonce
            await revalidateHome(forceUnconditional: false, scopeKey: currentScope, generation: taskGen)
        }
        .onChange(of: sourcePickerContext != nil) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
            }
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
            lastSeenRefreshNonce = newNonce
            scheduleRevalidateHome(forceUnconditional: false)
        }
        .onChange(of: isActiveTab) { _, active in
            guard active else { return }
            let isFresh = TabContentFreshnessPolicy.isCacheFresh(
                hasCachedContent: homePayload != nil,
                lastValidatedAt: lastValidatedAt,
                cachedRefreshNonce: lastSeenRefreshNonce,
                currentRefreshNonce: sessionStore.homeRefreshNonce
            )
            if !isFresh {
                lastSeenRefreshNonce = sessionStore.homeRefreshNonce
                scheduleRevalidateHome(forceUnconditional: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            let elapsed = Date().timeIntervalSince(lastValidatedAt)
            guard HomeRefreshPolicy.shouldRevalidateOnForeground(
                isSceneActive: phase == .active,
                isActiveTab: isActiveTab,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil,
                secondsSinceLastValidation: elapsed
            ) else {
                return
            }
            scheduleRevalidateHome(forceUnconditional: false)
        }
        .onDisappear {
            mutationBannerTask?.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            if sourcePickerContext == nil {
                subpageVisibility.leaveModal(modalToken)
            }
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

    private func scheduleRevalidateHome(forceUnconditional: Bool, scopeKey: String? = nil) {
        reloadTask?.cancel()
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor in
            await revalidateHome(forceUnconditional: forceUnconditional, scopeKey: scopeKey, generation: gen)
            if reloadGeneration == gen {
                reloadTask = nil
            }
        }
    }

    private func revalidateHome(forceUnconditional: Bool, scopeKey: String? = nil, generation: UInt64? = nil) async {
        guard let client = sessionStore.makeClient() else { return }
        let resolvedScope = scopeKey ?? "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
        if homePayload == nil {
            isInitialColdFetch = true
        }
        errorMessage = nil

        do {
            let result = try await client.fetchHomeConditional(
                ifNoneMatch: forceUnconditional ? nil : cachedEtag
            )
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            switch result {
            case .notModified:
                lastValidatedAt = Date()
                validatedScopeKey = resolvedScope
            case .updated(let payload, let newEtag, let rawData):
                cachedEtag = newEtag
                lastValidatedAt = Date()
                validatedScopeKey = resolvedScope
                if !(homePayload?.isSemanticallyEqual(to: payload) ?? false) {
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
        } catch is CancellationError {
            return
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if homePayload == nil {
                errorMessage = error.localizedDescription
            }
        }
        if generation == nil || generation == reloadGeneration {
            isInitialColdFetch = false
        }
    }

    private func openSourcePicker(for card: TvMediaCard) {
        let resolved = MediaCardMutator.resolvePlayTarget(for: card)
        sourcePickerContext = SourcePickerContext(
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
        let nextListed = !(card.inWatchlist ?? false)
        do {
            if try await MediaCardMutator.setWatchlist(for: card, listed: nextListed, sessionStore: sessionStore) {
                await markLocalMutationAndRevalidate()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func removeFromOngoing(for card: TvMediaCard) async {
        do {
            if try await MediaCardMutator.removeFromOngoing(for: card, sessionStore: sessionStore) {
                await markLocalMutationAndRevalidate()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func removeFromList(_ card: TvMediaCard, row: TvShelfRow) async {
        do {
            if try await MediaCardMutator.removeFromList(for: card, rowId: row.rowId, sessionStore: sessionStore) {
                await markLocalMutationAndRevalidate()
            }
        } catch {
            showMutationError(error)
        }
    }

    private func markWatched(for card: TvMediaCard) async {
        let nextWatched = !(card.progress?.watched ?? false)
        do {
            if try await MediaCardMutator.toggleWatched(
                for: card,
                watched: nextWatched,
                preferSeriesEpisodeTarget: true,
                sessionStore: sessionStore
            ) {
                await markLocalMutationAndRevalidate()
            }
        } catch {
            showMutationError(error)
        }
    }
}
