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
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce
    @Environment(\.lunaContentEntryFocusNonce) private var contentEntryFocusNonce

    let isActiveTab: Bool
    var previewFocusPosterRow: Bool = false
    var allowInitialColdFocus: Bool = false

    @State private var homePayload: TvHomeResponse?
    @State private var visibleRows: [TvShelfRow]
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
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration: UInt64 = 0

    @State private var mountedTracker = MountedEntryCardTracker()
    @State private var entryCardKey: String?
    @State private var entryFocusNonce: Int = 0
    @FocusState private var isRetryButtonFocused: Bool
    @Namespace private var homeFocusNamespace

    nonisolated static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        CatalogShelfIndexer.filterVisibleRows(rows)
    }

    nonisolated static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        CatalogShelfIndexer.prepareVisibleRows(from: payload)
    }

    init(
        initialServerHost: String? = nil,
        initialRoomName: String = "Stua",
        initialHardwareProfile: String = "hdr10-512",
        isActiveTab: Bool = true,
        previewFocusPosterRow: Bool = false,
        allowInitialColdFocus: Bool = false
    ) {
        self.isActiveTab = isActiveTab
        self.previewFocusPosterRow = previewFocusPosterRow
        self.allowInitialColdFocus = allowInitialColdFocus
        let snap = DiskSWRStore.memorySnapshot(
            serverHost: initialServerHost,
            roomName: initialRoomName,
            hardwareProfile: initialHardwareProfile
        )
        _homePayload = State(initialValue: snap?.payload)
        _visibleRows = State(initialValue: snap?.visibleRows ?? [])
        _cachedEtag = State(initialValue: snap?.etag)
    }

    private func resolveDefaultRow(in rows: [TvShelfRow]) -> TvShelfRow? {
        if previewFocusPosterRow,
           let posterRow = rows.first(where: { $0.rowStyle == "poster" && !$0.items.isEmpty }) {
            return posterRow
        }
        return rows.first(where: { !$0.items.isEmpty })
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let rows = visibleRows
        let defaultRow = resolveDefaultRow(in: rows)
        let focusRowId = defaultRow?.rowId
        let focusTargetKey = defaultRow.flatMap { row in
            row.items.first.map { "\(row.rowId)#\($0.itemId)" }
        }

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.sectionGap) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    if rows.isEmpty && isInitialColdFetch {
                        LunaLoadingRow(message: "Henter innhold…")
                            .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    if let errorMessage, rows.isEmpty {
                        LunaInlineError(message: errorMessage) {
                            scheduleRevalidateHome(forceUnconditional: true)
                        }
                        .focused($isRetryButtonFocused)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    ForEach(rows) { row in
                        ShelfRowView(
                            row: row,
                            isDefaultFocusRow: row.rowId == focusRowId,
                            mountedTracker: mountedTracker,
                            entryCardKey: entryCardKey,
                            entryFocusNonce: entryFocusNonce,
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
                        .id(row.rowId)
                    }
                }
                .padding(.top, LunaTopBarView.contentTopPadding)
                .padding(.bottom, 96)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .lunaRootScrollTopBarTracking(tab: .home)
            .onAppear {
                if (allowInitialColdFocus || previewFocusPosterRow), let focusTargetKey {
                    entryCardKey = focusTargetKey
                    entryFocusNonce &+= 1
                }
            }
            .task(id: previewFocusPosterRow ? focusRowId : nil) {
                guard previewFocusPosterRow, let focusRowId else { return }
                for delayNs: UInt64 in [220_000_000, 480_000_000] {
                    try? await Task.sleep(nanoseconds: delayNs)
                    guard !Task.isCancelled else { return }
                    scrollProxy.scrollTo(focusRowId, anchor: .center)
                    if let focusTargetKey {
                        entryCardKey = focusTargetKey
                        entryFocusNonce &+= 1
                    }
                }
            }
            .onChange(of: focusTargetKey) { _, nextKey in
                if previewFocusPosterRow, let nextKey, let focusRowId {
                    scrollProxy.scrollTo(focusRowId, anchor: .center)
                    entryCardKey = nextKey
                    entryFocusNonce &+= 1
                }
            }
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isActiveTab else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                }
            }
            .onChange(of: contentEntryFocusNonce) { _, _ in
                guard isActiveTab else { return }
                focusLeftmostHomeTarget(rows: rows, scrollProxy: scrollProxy)
            }
        }
        .lunaBottomToast(message: $mutationErrorMessage, tone: .danger)
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
                onSelectCandidate: { picked, reusedPrepareToken, createdPreparedSession in
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
                        preparedSession: createdPreparedSession,
                        backdropUrl: target.backdropUrl,
                        logoUrl: target.logoUrl
                    )
                },
                onCancel: {
                    sourcePickerContext = nil
                }
            )
            .environment(sessionStore)
            .preferredColorScheme(.dark)
        }
        .task(id: "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.hardwareProfile)#active:\(isActiveTab)") {
            guard isActiveTab else { return }
            let currentScope = "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.hardwareProfile)"
            await syncDiskSnapshotIfRoomChanged()
            if validatedScopeKey == currentScope,
               TabContentFreshnessPolicy.isCacheFresh(
                   hasCachedContent: homePayload != nil,
                   lastValidatedAt: lastValidatedAt,
                   cachedRefreshNonce: lastSeenRefreshNonce,
                   currentRefreshNonce: sessionStore.homeRefreshNonce,
                   freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
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
        .task(id: "\(validatedScopeKey ?? "")#warm:\(!visibleRows.isEmpty && !isInitialColdFetch)") {
            await warmCatalogMetadataAfterHomePaintIfEligible()
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
            reloadTask?.cancel()
            reloadTask = nil
            if sourcePickerContext == nil {
                subpageVisibility.leaveModal(modalToken)
            }
        }
    }

    private func focusLeftmostHomeTarget(rows: [TvShelfRow], scrollProxy: ScrollViewProxy) {
        if let firstRow = rows.first(where: { !$0.items.isEmpty }) {
            let orderedKeys = firstRow.items.map { "\(firstRow.rowId)#\($0.itemId)" }
            scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
            if let resolvedKey = mountedTracker.resolveEntryID(orderedIDs: orderedKeys) {
                entryCardKey = resolvedKey
                entryFocusNonce &+= 1
            }
        } else if errorMessage != nil && rows.isEmpty {
            isRetryButtonFocused = true
        }
    }

    private func syncDiskSnapshotIfRoomChanged() async {
        let targetHost = sessionStore.serverBaseURL?.host
        let targetRoom = sessionStore.roomName
        let targetProfile = sessionStore.hardwareProfile
        guard let current = homePayload else {
            if let snap = await DiskSWRStore.loadHomeAsync(
                serverHost: targetHost,
                roomName: targetRoom,
                hardwareProfile: targetProfile
            ), !Task.isCancelled {
                homePayload = snap.payload
                visibleRows = snap.visibleRows
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
                visibleRows = snap.visibleRows
                cachedEtag = snap.etag
            } else {
                cachedEtag = nil
            }
        }
    }

    private func warmCatalogMetadataAfterHomePaintIfEligible() async {
        let profile = DeviceMemoryProfile.current
        guard profile.enableBackgroundCatalogMetadataWarmup,
              !visibleRows.isEmpty,
              !isInitialColdFetch,
              sessionStore.activePlaybackTarget == nil,
              PreviewLaunchConfiguration.parse(arguments: ProcessInfo.processInfo.arguments) == nil else {
            return
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled,
              sessionStore.activePlaybackTarget == nil,
              let client = sessionStore.makeClient() else {
            return
        }
        let baseURL = sessionStore.serverBaseURL
        let room = sessionStore.roomName
        let hwProfile = sessionStore.hardwareProfile
        let pageSize = profile.catalogPageSize

        for kind in ["movie", "series"] {
            guard !Task.isCancelled, sessionStore.activePlaybackTarget == nil else { return }
            let cacheKey = CatalogBrowseView.makeCacheKey(
                serverBaseURL: baseURL,
                mediaType: kind,
                roomName: room,
                hardwareProfile: hwProfile
            )
            let currentNonce = sessionStore.homeRefreshNonce
            if let existing = CatalogBrowseMemoryCache.shared.snapshot(for: cacheKey),
               TabContentFreshnessPolicy.isCacheFresh(
                   hasCachedContent: !existing.items.isEmpty,
                   lastValidatedAt: existing.fetchedAt,
                   cachedRefreshNonce: existing.refreshNonce,
                   currentRefreshNonce: currentNonce,
                   freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
               ) {
                continue
            }
            let fetched: TvCatalogResponse? = await Task.detached(priority: .utility) {
                try? await client.fetchCatalog(kind: kind, sort: "popular", page: 1, limit: pageSize)
            }.value
            guard !Task.isCancelled,
                  sessionStore.activePlaybackTarget == nil,
                  let res = fetched,
                  !res.items.isEmpty else {
                continue
            }
            CatalogBrowseMemoryCache.shared.store(
                CatalogBrowseSnapshot(
                    items: res.items,
                    availableGenres: res.availableGenres ?? [],
                    selectedGenreLabel: res.genre?.label,
                    hasMore: res.hasMore,
                    currentPage: 1,
                    fetchedAt: Date(),
                    refreshNonce: sessionStore.homeRefreshNonce
                ),
                for: cacheKey
            )
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
        let resolvedScope = scopeKey ?? "\(sessionStore.serverBaseURL?.absoluteString ?? "")#\(sessionStore.roomName)#\(sessionStore.hardwareProfile)"
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
                let computedRows = await Task.detached(priority: .userInitiated) {
                    CatalogShelfIndexer.prepareVisibleRows(from: payload)
                }.value
                guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
                cachedEtag = newEtag
                lastValidatedAt = Date()
                validatedScopeKey = resolvedScope
                if !(homePayload?.isSemanticallyEqual(to: payload) ?? false) {
                    homePayload = payload
                    visibleRows = computedRows
                }
                DiskSWRStore.saveHomeInBackground(
                    rawPayloadData: rawData,
                    etag: newEtag,
                    serverHost: sessionStore.serverBaseURL?.host,
                    roomName: sessionStore.roomName,
                    hardwareProfile: sessionStore.hardwareProfile,
                    decodedPayload: payload,
                    precomputedRows: computedRows
                )
            }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch where AppSessionStore.isFailoverEligibleError(error) {
            if await sessionStore.probeAndFailoverServerURLIfNeeded() {
                return
            }
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if homePayload == nil {
                errorMessage = LunaCopy.friendlyErrorMessage(error)
            }
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == reloadGeneration) else { return }
            if homePayload == nil {
                errorMessage = LunaCopy.friendlyErrorMessage(error)
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
        mutationErrorMessage = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func markLocalMutationAndRevalidate() async {
        reloadTask?.cancel()
        reloadTask = nil
        reloadGeneration &+= 1
        let gen = reloadGeneration
        lastSeenRefreshNonce = sessionStore.homeRefreshNonce &+ 1
        sessionStore.notifyContentMutated()
        await revalidateHome(forceUnconditional: true, generation: gen)
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
