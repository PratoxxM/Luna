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
    @Environment(\.lunaScrollToTopNonce) private var scrollToTopNonce

    let isActiveTab: Bool
    var previewFocusPosterRow: Bool = false
    var allowInitialColdFocus: Bool = false

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

    @FocusState private var focusedCardKey: String?
    @Namespace private var homeFocusNamespace

    nonisolated static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        CatalogShelfIndexer.filterVisibleRows(rows)
    }

    nonisolated static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        CatalogShelfIndexer.prepareVisibleRows(from: payload)
    }

    nonisolated static func prioritizeContinueCards(
        _ items: [TvMediaCard],
        preparedFromPhone: TvMediaCard?
    ) -> [TvMediaCard] {
        CatalogShelfIndexer.prioritizeContinueCards(items, preparedFromPhone: preparedFromPhone)
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
        _cachedEtag = State(initialValue: snap?.etag)
    }

    private var visibleRows: [TvShelfRow] {
        Self.prepareVisibleRows(from: homePayload)
    }

    private var targetDefaultRow: TvShelfRow? {
        if previewFocusPosterRow,
           let posterRow = visibleRows.first(where: { $0.rowStyle == "poster" && !$0.items.isEmpty }) {
            return posterRow
        }
        return visibleRows.first(where: { !$0.items.isEmpty })
    }

    private var defaultFocusCardKey: String? {
        guard let row = targetDefaultRow, let card = row.items.first else { return nil }
        return "\(row.rowId)#\(card.itemId)"
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let focusTargetKey = defaultFocusCardKey
        let focusRowId = targetDefaultRow?.rowId

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 44) {
                    Color.clear
                        .frame(height: 0)
                        .id("luna-scroll-top")

                    if visibleRows.isEmpty && isInitialColdFetch {
                        HStack(spacing: 16) {
                            ProgressView()
                            Text("Henter innhold…")
                                .font(LunaTheme.Font.cardTitle)
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 64)
                    }

                    if let errorMessage, visibleRows.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(errorMessage)
                                .font(LunaTheme.Font.body)
                                .foregroundStyle(LunaTheme.danger)
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                scheduleRevalidateHome(forceUnconditional: true)
                            }
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                    }

                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { _, row in
                        ShelfRowView(
                            row: row,
                            isDefaultFocusRow: row.rowId == focusRowId,
                            focusedCardKey: $focusedCardKey,
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
                    focusedCardKey = focusTargetKey
                }
                if previewFocusPosterRow, let focusRowId {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        scrollProxy.scrollTo(focusRowId, anchor: .center)
                        if let target = defaultFocusCardKey {
                            focusedCardKey = target
                        }
                    }
                }
            }
            .onChange(of: focusTargetKey) { _, nextKey in
                if previewFocusPosterRow, let nextKey, let focusRowId {
                    scrollProxy.scrollTo(focusRowId, anchor: .center)
                    focusedCardKey = nextKey
                }
            }
            .onChange(of: scrollToTopNonce) { _, _ in
                guard isActiveTab else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("luna-scroll-top", anchor: .top)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let mutationErrorMessage {
                TransientErrorBanner(message: mutationErrorMessage)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, LunaTopBarView.contentTopPadding + 8)
                    .allowsHitTesting(false)
            }
        }
        .defaultFocus(
            $focusedCardKey,
            (allowInitialColdFocus || previewFocusPosterRow) ? focusTargetKey : nil,
            priority: (allowInitialColdFocus || previewFocusPosterRow) ? .userInitiated : .automatic
        )
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
                   currentRefreshNonce: sessionStore.homeRefreshNonce,
                   freshnessInterval: DeviceHardwareCapabilities.isHighMemoryDevice ? 600 : TabContentFreshnessPolicy.defaultFreshnessInterval
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
                currentRefreshNonce: sessionStore.homeRefreshNonce,
                freshnessInterval: DeviceHardwareCapabilities.isHighMemoryDevice ? 600 : TabContentFreshnessPolicy.defaultFreshnessInterval
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
                    homePayload = payload
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
        mutationBannerTask?.cancel()
        mutationErrorMessage = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
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
