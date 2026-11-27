import Foundation
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public let initialQuery: String
    public let isRootTab: Bool

    public var query: String
    public var selectedKind: TvSearchKindFilter = .all
    public private(set) var results: [TvMediaCard] = []
    public private(set) var localCount: Int = 0
    public private(set) var isSearching: Bool = false
    public private(set) var errorMessage: String?
    public var mutationErrorBanner: String?
    public private(set) var recentSearches: [String] = []
    public private(set) var lastCompletedQuery: String = ""
    public private(set) var lastCompletedKind: TvSearchKindFilter = .all
    public private(set) var didConsumeInitialQuery: Bool = false
    public private(set) var searchRetryNonce: Int = 0
    public private(set) var lastHandledRetryNonce: Int = 0
    public var lastSeenRefreshNonce: Int = -1
    public private(set) var isUnloadedForMemoryWarning: Bool = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration: UInt64 = 0

    public init(initialQuery: String = "", isRootTab: Bool = false) {
        self.initialQuery = initialQuery
        self.isRootTab = isRootTab
        self.query = initialQuery
    }

    public var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resultsSummaryText: String {
        localCount > 0
            ? "\(LunaCopy.searchHits(results.count)) · \(localCount) lokalt"
            : LunaCopy.searchHits(results.count)
    }

    public func loadRecentSearches(session: any SearchSessionContext) {
        recentSearches = session.loadRecentSearches()
    }

    public func clearRecentSearches(session: any SearchSessionContext) {
        recentSearches = []
        session.clearRecentSearches()
    }

    public func triggerRetry() {
        searchRetryNonce &+= 1
    }

    public func clearQuery() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        query = ""
        results = []
        localCount = 0
        lastCompletedQuery = ""
        lastCompletedKind = .all
        errorMessage = nil
        isSearching = false
    }

    public func handleSearchTrigger(
        session: any SearchSessionContext,
        isActiveTab: Bool,
        debounceNanoseconds: UInt64 = 180_000_000
    ) async {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        let gen = searchGeneration

        let nonceChanged = lastSeenRefreshNonce != -1 && lastSeenRefreshNonce != session.homeRefreshNonce
        lastSeenRefreshNonce = session.homeRefreshNonce
        guard isActiveTab || !isRootTab else {
            if nonceChanged {
                lastCompletedQuery = ""
            }
            isSearching = false
            return
        }

        let trimmed = trimmedQuery
        guard trimmed.count >= 2 else {
            results = []
            localCount = 0
            lastCompletedQuery = ""
            errorMessage = nil
            isSearching = false
            return
        }

        let initialTrimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRetry = searchRetryNonce != lastHandledRetryNonce
        if isRetry {
            lastHandledRetryNonce = searchRetryNonce
        }
        let skipDebounce = (!didConsumeInitialQuery && !initialTrimmed.isEmpty && trimmed == initialTrimmed)
            || isRetry
            || nonceChanged
            || isUnloadedForMemoryWarning
        didConsumeInitialQuery = true

        if !skipDebounce && debounceNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
        }
        guard !Task.isCancelled, gen == searchGeneration else {
            if gen == searchGeneration {
                isSearching = false
            }
            return
        }

        if !isRetry && !nonceChanged && !isUnloadedForMemoryWarning && trimmed == lastCompletedQuery && selectedKind == lastCompletedKind && !results.isEmpty && errorMessage == nil {
            isSearching = false
            return
        }
        await executeSearch(trimmed: trimmed, session: session, generation: gen)
    }

    public func scheduleSearch(
        session: any SearchSessionContext,
        isActiveTab: Bool,
        debounceNanoseconds: UInt64 = 180_000_000
    ) {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        guard isActiveTab || !isRootTab else {
            isSearching = false
            return
        }
        let gen = searchGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let trimmed = self.trimmedQuery
            guard trimmed.count >= 2 else {
                self.results = []
                self.localCount = 0
                self.lastCompletedQuery = ""
                self.errorMessage = nil
                self.isSearching = false
                self.lastSeenRefreshNonce = session.homeRefreshNonce
                return
            }
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled, gen == self.searchGeneration, isActiveTab || !self.isRootTab else {
                if gen == self.searchGeneration {
                    self.isSearching = false
                }
                return
            }
            await self.executeSearch(trimmed: trimmed, session: session, generation: gen)
            if self.searchGeneration == gen {
                self.searchTask = nil
            }
        }
        searchTask = task
    }

    public func executeSearch(
        trimmed: String,
        session: any SearchSessionContext,
        generation: UInt64? = nil
    ) async {
        guard let client = session.makeSearchClient() else {
            if generation == nil || generation == searchGeneration {
                isSearching = false
            }
            return
        }
        isSearching = true
        errorMessage = nil
        let requestedKind = selectedKind

        do {
            let res = try await client.searchFull(query: trimmed, limit: 30, kind: requestedKind.rawValue)
            guard !Task.isCancelled, (generation == nil || generation == searchGeneration) else {
                if generation == nil || generation == searchGeneration {
                    isSearching = false
                }
                return
            }
            results = res.items
            localCount = res.localCount ?? 0
            lastCompletedQuery = trimmed
            lastCompletedKind = requestedKind
            isUnloadedForMemoryWarning = false
            if !res.items.isEmpty {
                recentSearches = session.recordRecentSearch(trimmed)
            }
        } catch where LunaCoreError.isCancellation(error) {
            if generation == nil || generation == searchGeneration {
                isSearching = false
            }
            return
        } catch LunaCoreError.unauthorized {
            guard !Task.isCancelled, (generation == nil || generation == searchGeneration) else { return }
            session.unpairDevice()
        } catch {
            guard !Task.isCancelled, (generation == nil || generation == searchGeneration) else { return }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }

        if generation == nil || generation == searchGeneration {
            isSearching = false
        }
    }

    public func toggleWatchlist(_ card: TvMediaCard, session: any SearchSessionContext) async {
        guard let client = session.makeSearchClient() else { return }
        let previous = card.inWatchlist
        let nextListed = !(card.inWatchlist ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].inWatchlist = nextListed
        }
        do {
            try await client.setWatchlist(
                listed: nextListed,
                mediaType: card.mediaType,
                ids: card.ids,
                title: card.title,
                year: card.year
            )
            ItemDetailMemoryCache.invalidate(itemId: card.itemId, tmdbId: card.ids.tmdb)
            lastSeenRefreshNonce = session.homeRefreshNonce &+ 1
            session.notifyContentMutated()
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            if let idx = results.firstIndex(where: { $0.id == card.id }) {
                results[idx].inWatchlist = previous
            }
            showMutationError(error)
        }
    }

    public func toggleWatched(_ card: TvMediaCard, session: any SearchSessionContext) async {
        guard let client = session.makeSearchClient() else { return }
        let previousProgress = card.progress
        let nextWatched = !(card.progress?.watched ?? false)
        if let idx = results.firstIndex(where: { $0.id == card.id }) {
            results[idx].progress = TvWatchProgress(
                positionSeconds: nextWatched ? 0 : (previousProgress?.positionSeconds ?? 0),
                durationSeconds: previousProgress?.durationSeconds ?? 0,
                percent: nextWatched ? 100 : 0,
                season: previousProgress?.season,
                episode: previousProgress?.episode,
                watched: nextWatched
            )
        }
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
            lastSeenRefreshNonce = session.homeRefreshNonce &+ 1
            session.notifyContentMutated()
        } catch LunaCoreError.unauthorized {
            session.unpairDevice()
        } catch {
            if let idx = results.firstIndex(where: { $0.id == card.id }) {
                results[idx].progress = previousProgress
            }
            showMutationError(error)
        }
    }

    public func cancelAllTasks() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        isSearching = false
    }

    public func unloadForMemoryWarning() {
        cancelAllTasks()
        results = []
        localCount = 0
        lastCompletedQuery = ""
        lastCompletedKind = .all
        isSearching = false
        isUnloadedForMemoryWarning = true
    }

    private func showMutationError(_ error: Error) {
        mutationErrorBanner = "Kunne ikke lagre endringen: \(LunaCopy.friendlyErrorMessage(error))"
    }
}
