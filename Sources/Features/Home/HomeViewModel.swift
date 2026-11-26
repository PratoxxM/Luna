import Foundation
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var homePayload: TvHomeResponse?
    public private(set) var visibleRows: [TvShelfRow]
    public private(set) var cachedEtag: String?
    public private(set) var isInitialColdFetch: Bool = false
    public private(set) var errorMessage: String?
    public var mutationErrorMessage: String?
    public var lastSeenRefreshNonce: Int = -1
    public private(set) var lastValidatedAt: Date = .distantPast
    public private(set) var validatedScopeKey: String?
    public private(set) var isUnloadedForMemoryWarning: Bool = false

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var warmupTask: Task<Void, Never>?
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var loadedScopeKey: String?

    private nonisolated static func makeDiskScopeKey(
        serverHost: String?,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        "\(serverHost ?? "")|\(roomName)|\(hardwareProfile)"
    }

    public nonisolated static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        CatalogShelfIndexer.filterVisibleRows(rows)
    }

    public nonisolated static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        CatalogShelfIndexer.prepareVisibleRows(from: payload)
    }

    public init(
        initialServerHost: String? = nil,
        initialRoomName: String = "Stua",
        initialHardwareProfile: String = "hdr10-512"
    ) {
        let snap = DiskSWRStore.memorySnapshot(
            serverHost: initialServerHost,
            roomName: initialRoomName,
            hardwareProfile: initialHardwareProfile
        )
        self.homePayload = snap?.payload
        self.visibleRows = snap?.visibleRows ?? []
        self.cachedEtag = snap?.etag
        if snap != nil {
            self.loadedScopeKey = Self.makeDiskScopeKey(
                serverHost: initialServerHost,
                roomName: initialRoomName,
                hardwareProfile: initialHardwareProfile
            )
        }
    }

    public func scopeKey(for session: any TabSessionContext) -> String {
        "\(session.serverBaseURL?.absoluteString ?? "")#\(session.roomName)#\(session.hardwareProfile)"
    }

    public func handleActivation(session: any TabSessionContext, isActiveTab: Bool) async {
        guard isActiveTab else { return }
        let currentScope = scopeKey(for: session)
        await syncDiskSnapshotIfNeeded(session: session)
        if !isUnloadedForMemoryWarning,
           validatedScopeKey == currentScope,
           TabContentFreshnessPolicy.isCacheFresh(
               hasCachedContent: homePayload != nil,
               lastValidatedAt: lastValidatedAt,
               cachedRefreshNonce: lastSeenRefreshNonce,
               currentRefreshNonce: session.homeRefreshNonce,
               freshnessInterval: TabContentFreshnessPolicy.effectiveFreshnessInterval
           ) {
            return
        }
        reloadTask?.cancel()
        reloadTask = nil
        reloadGeneration &+= 1
        let gen = reloadGeneration
        lastSeenRefreshNonce = session.homeRefreshNonce
        await revalidateHome(forceUnconditional: false, session: session, scopeKey: currentScope, generation: gen)
    }

    public func handleHomeRefreshNonceChange(
        _ newNonce: Int,
        isActiveTab: Bool,
        session: any TabSessionContext
    ) {
        guard isActiveTab, newNonce != lastSeenRefreshNonce else { return }
        lastSeenRefreshNonce = newNonce
        scheduleRevalidateHome(forceUnconditional: false, session: session)
    }

    public func handleForegroundTransition(
        isSceneActive: Bool,
        isActiveTab: Bool,
        session: any TabSessionContext,
        now: Date = Date()
    ) {
        let elapsed = now.timeIntervalSince(lastValidatedAt)
        guard HomeRefreshPolicy.shouldRevalidateOnForeground(
            isSceneActive: isSceneActive,
            isActiveTab: isActiveTab,
            hasActivePlayback: session.hasActivePlayback,
            secondsSinceLastValidation: elapsed
        ) else {
            return
        }
        scheduleRevalidateHome(forceUnconditional: false, session: session)
    }

    public func scheduleRevalidateHome(
        forceUnconditional: Bool,
        session: any TabSessionContext,
        scopeKey: String? = nil
    ) {
        reloadTask?.cancel()
        reloadGeneration &+= 1
        let gen = reloadGeneration
        reloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.revalidateHome(
                forceUnconditional: forceUnconditional,
                session: session,
                scopeKey: scopeKey,
                generation: gen
            )
            if self.reloadGeneration == gen {
                self.reloadTask = nil
            }
        }
    }

    private func currentDiskScopeKey(for session: any TabSessionContext) -> String {
        Self.makeDiskScopeKey(
            serverHost: session.serverBaseURL?.host,
            roomName: session.roomName,
            hardwareProfile: session.hardwareProfile
        )
    }

    public func revalidateHome(
        forceUnconditional: Bool,
        session: any TabSessionContext,
        scopeKey: String? = nil,
        generation: UInt64? = nil
    ) async {
        guard let client = session.makeHomeClient() else { return }
        let targetHost = session.serverBaseURL?.host
        let targetRoom = session.roomName
        let targetProfile = session.hardwareProfile
        let resolvedScope = scopeKey ?? self.scopeKey(for: session)
        let targetDiskScope = Self.makeDiskScopeKey(
            serverHost: targetHost,
            roomName: targetRoom,
            hardwareProfile: targetProfile
        )
        if loadedScopeKey != targetDiskScope
            || homePayload?.roomName != targetRoom
            || homePayload?.hardwareProfile != targetProfile {
            await syncDiskSnapshotIfNeeded(session: session)
            guard !Task.isCancelled,
                  (generation == nil || generation == reloadGeneration),
                  currentDiskScopeKey(for: session) == targetDiskScope else {
                return
            }
        } else if let validatedScopeKey, validatedScopeKey != resolvedScope {
            homePayload = nil
            visibleRows = []
            cachedEtag = nil
            loadedScopeKey = nil
            self.validatedScopeKey = nil
        }

        if homePayload == nil {
            isInitialColdFetch = true
        }
        defer {
            if generation == nil || generation == reloadGeneration {
                isInitialColdFetch = false
            }
        }
        errorMessage = nil

        do {
            let effectiveIfNoneMatch = (forceUnconditional || homePayload == nil) ? nil : cachedEtag
            let result = try await client.fetchHomeConditional(
                ifNoneMatch: effectiveIfNoneMatch
            )
            guard !Task.isCancelled,
                  (generation == nil || generation == reloadGeneration),
                  currentDiskScopeKey(for: session) == targetDiskScope else {
                return
            }
            switch result {
            case .notModified:
                if homePayload != nil {
                    lastValidatedAt = Date()
                    validatedScopeKey = resolvedScope
                    loadedScopeKey = targetDiskScope
                }
                isUnloadedForMemoryWarning = false
            case .updated(let payload, let newEtag, let rawData):
                let computedRows = await Task.detached(priority: .userInitiated) {
                    CatalogShelfIndexer.prepareVisibleRows(from: payload)
                }.value
                guard !Task.isCancelled,
                      (generation == nil || generation == reloadGeneration),
                      currentDiskScopeKey(for: session) == targetDiskScope else {
                    return
                }
                cachedEtag = newEtag
                lastValidatedAt = Date()
                validatedScopeKey = resolvedScope
                loadedScopeKey = targetDiskScope
                isUnloadedForMemoryWarning = false
                if !(homePayload?.isSemanticallyEqual(to: payload) ?? false) {
                    homePayload = payload
                    visibleRows = computedRows
                }
                DiskSWRStore.saveHomeInBackground(
                    rawPayloadData: rawData,
                    etag: newEtag,
                    serverHost: targetHost,
                    roomName: targetRoom,
                    hardwareProfile: targetProfile,
                    decodedPayload: payload,
                    precomputedRows: computedRows
                )
            }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch where ServerFailoverPolicy.isFailoverEligibleError(error) {
            if await session.probeAndFailoverServerURLIfNeeded() {
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
    }

    public func syncDiskSnapshotIfNeeded(session: any TabSessionContext) async {
        let targetHost = session.serverBaseURL?.host
        let targetRoom = session.roomName
        let targetProfile = session.hardwareProfile
        let targetScope = Self.makeDiskScopeKey(
            serverHost: targetHost,
            roomName: targetRoom,
            hardwareProfile: targetProfile
        )
        if let current = homePayload,
           loadedScopeKey == targetScope,
           current.roomName == targetRoom,
           current.hardwareProfile == targetProfile {
            return
        }
        if let snap = await DiskSWRStore.loadHomeAsync(
            serverHost: targetHost,
            roomName: targetRoom,
            hardwareProfile: targetProfile
        ), !Task.isCancelled {
            homePayload = snap.payload
            visibleRows = snap.visibleRows
            cachedEtag = snap.etag
            loadedScopeKey = targetScope
            validatedScopeKey = nil
            isUnloadedForMemoryWarning = false
        } else if !Task.isCancelled {
            homePayload = nil
            visibleRows = []
            cachedEtag = nil
            loadedScopeKey = nil
            validatedScopeKey = nil
        }
    }

    public func warmCatalogMetadataAfterHomePaintIfEligible(
        session: any TabSessionContext,
        isPreviewMode: Bool = false,
        delayNanoseconds: UInt64 = 1_500_000_000
    ) async {
        let profile = DeviceMemoryProfile.current
        guard profile.enableBackgroundCatalogMetadataWarmup,
              !visibleRows.isEmpty,
              !isInitialColdFetch,
              !session.hasActivePlayback,
              !isPreviewMode else {
            return
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !Task.isCancelled,
              !session.hasActivePlayback,
              let client = session.makeHomeClient() else {
            return
        }
        let baseURL = session.serverBaseURL
        let room = session.roomName
        let hwProfile = session.hardwareProfile
        let pageSize = profile.catalogPageSize

        for kind in ["movie", "series"] {
            guard !Task.isCancelled, !session.hasActivePlayback else { return }
            let cacheKey = CatalogBrowseViewModel.makeCacheKey(
                serverBaseURL: baseURL,
                mediaType: kind,
                roomName: room,
                hardwareProfile: hwProfile
            )
            let currentNonce = session.homeRefreshNonce
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
                try? await client.fetchCatalog(
                    kind: kind,
                    genre: nil,
                    sort: "popular",
                    localOnly: false,
                    unwatchedOnly: false,
                    page: 1,
                    limit: pageSize
                )
            }.value
            guard !Task.isCancelled,
                  !session.hasActivePlayback,
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
                    refreshNonce: session.homeRefreshNonce
                ),
                for: cacheKey
            )
            if let raw = try? JSONEncoder().encode(res) {
                DiskSWRStore.saveCatalogInBackground(
                    rawPayloadData: raw,
                    etag: nil,
                    kind: kind,
                    serverHost: baseURL?.host,
                    roomName: room,
                    hardwareProfile: hwProfile,
                    decodedPayload: res
                )
            }
        }
    }

    public func toggleWatchlist(for card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeHomeClient() else { return }
        let nextListed = !(card.inWatchlist ?? false)
        do {
            try await client.setWatchlist(
                listed: nextListed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            await markLocalMutationAndRevalidate(session: session)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func removeFromOngoing(for card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeHomeClient() else { return }
        do {
            try await client.removeFromOngoing(
                mediaType: card.mediaType,
                itemId: card.itemId,
                ids: card.ids,
                title: card.title
            )
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            await markLocalMutationAndRevalidate(session: session)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func removeFromList(_ card: TvMediaCard, row: TvShelfRow, session: any TabSessionContext) async {
        guard let client = session.makeHomeClient() else { return }
        do {
            let removed = try await client.removeFromList(
                rowId: row.rowId,
                mediaType: card.mediaType,
                itemId: card.itemId,
                ids: card.ids,
                title: card.title
            )
            if removed {
                ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
                await markLocalMutationAndRevalidate(session: session)
            }
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func markWatched(for card: TvMediaCard, session: any TabSessionContext) async {
        guard let client = session.makeHomeClient() else { return }
        let nextWatched = !(card.progress?.watched ?? false)
        do {
            let s = card.directPlayTarget?.season ?? card.nextUp?.season ?? card.progress?.season
            let e = card.directPlayTarget?.episode ?? card.nextUp?.episode ?? card.progress?.episode
            if card.mediaType == "series" && (nextWatched || card.directPlayTarget?.season != nil),
               let s, let e {
                try await client.setWatched(
                    watched: nextWatched,
                    mediaType: "episode",
                    ids: card.ids,
                    title: card.title,
                    year: card.year,
                    season: s,
                    episode: e
                )
            } else {
                try await client.setWatched(
                    watched: nextWatched,
                    mediaType: card.mediaType,
                    ids: card.ids,
                    title: card.title,
                    year: card.year,
                    season: nil,
                    episode: nil
                )
            }
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            await markLocalMutationAndRevalidate(session: session)
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            showMutationError(error)
        }
    }

    public func cancelAllTasks() {
        reloadTask?.cancel()
        reloadTask = nil
        warmupTask?.cancel()
        warmupTask = nil
        reloadGeneration &+= 1
        isInitialColdFetch = false
    }

    public func unloadForMemoryWarning() {
        cancelAllTasks()
        homePayload = nil
        visibleRows = []
        cachedEtag = nil
        loadedScopeKey = nil
        validatedScopeKey = nil
        isInitialColdFetch = false
        isUnloadedForMemoryWarning = true
    }

    private func showMutationError(_ error: Error) {
        mutationErrorMessage = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }

    private func markLocalMutationAndRevalidate(session: any TabSessionContext) async {
        reloadTask?.cancel()
        reloadTask = nil
        reloadGeneration &+= 1
        let gen = reloadGeneration
        lastSeenRefreshNonce = session.homeRefreshNonce &+ 1
        session.notifyContentMutated()
        await revalidateHome(forceUnconditional: true, session: session, generation: gen)
    }
}
