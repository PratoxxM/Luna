import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class MockSearchClient: SearchClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var queries: [String] = []
        var kinds: [String] = []
        var startedQueries: [String] = []
        var searchDelayNanoseconds: UInt64 = 0
        var failWatchlist = false
    }

    func searchFull(query: String, limit: Int, kind: String) async throws -> TvSearchResponse {
        let delay = lock.withLock { s -> UInt64 in
            s.startedQueries.append(query)
            return s.searchDelayNanoseconds
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        lock.withLock {
            $0.queries.append(query)
            $0.kinds.append(kind)
        }
        return TvSearchResponse(
            ok: true,
            query: query,
            kind: kind,
            localCount: 1,
            items: [
                TvMediaCard(itemId: "movie:tmdb:693134", mediaType: "movie", ids: TvMediaIds(tmdb: 693134), title: "Dune: \(query)", inWatchlist: false)
            ]
        )
    }

    func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {
        if lock.withLock({ $0.failWatchlist }) {
            throw LunaCoreError.serverMessage(500, "Feil")
        }
    }

    func setWatched(watched: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?, season: Int?, episode: Int?) async throws {}
    func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws {}
    func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool { true }
}

@MainActor
private final class MockSearchSession: SearchSessionContext {
    var serverBaseURL: URL? = URL(string: "http://mock-search.local:8090")
    var roomName: String = "Stua"
    var hardwareProfile: String = "hdr10-512"
    var homeRefreshNonce: Int = 1
    var hasActivePlayback: Bool = false
    var recent: [String] = []
    let client: MockSearchClient

    init(client: MockSearchClient) {
        self.client = client
    }

    func makeHomeClient() -> (any HomeClientProviding)? { nil }
    func makeCatalogClient() -> (any CatalogClientProviding)? { nil }
    func makeLibraryClient() -> (any LibraryClientProviding)? { nil }
    func makeSearchClient() -> (any SearchClientProviding)? { client }
    func notifyContentMutated() { homeRefreshNonce &+= 1 }
    func unpairDevice() {}
    func loadRecentSearches() -> [String] { recent }
    @discardableResult
    func recordRecentSearch(_ term: String) -> [String] {
        recent.removeAll { $0 == term }
        recent.insert(term, at: 0)
        return recent
    }
    func clearRecentSearches() { recent.removeAll() }
}

@MainActor
private final class MockServerDiscovery: ServerDiscoveryProviding {
    var servers: [DiscoveredLunaCoreServer] = []
    var isSearching: Bool = false
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1; isSearching = true }
    func stop() { stopCount += 1; isSearching = false }
}

private final class MockPairingClient: PairingClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var pollSteps: [(Int, TvPairingPollResponse)] = []
        var requestDelayNanoseconds: UInt64 = 0
        var pollIntervalSeconds: Int? = 2
        var requestCount = 0
        var pollCount = 0
    }

    func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String,
        capabilities: TvDeviceCapabilities
    ) async throws -> TvPairingRequestResponse {
        let (delay, interval) = lock.withLock { s -> (UInt64, Int?) in
            s.requestCount += 1
            return (s.requestDelayNanoseconds, s.pollIntervalSeconds)
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return TvPairingRequestResponse(
            ok: true,
            pairingCode: "482910",
            displayCode: "482 910",
            expiresAt: "2026-11-26T01:00:00Z",
            pollIntervalSeconds: interval
        )
    }

    func pollPairingCode(_ code: String) async throws -> (httpStatus: Int, response: TvPairingPollResponse) {
        lock.withLock { s in
            s.pollCount += 1
            if s.pollSteps.isEmpty {
                return (200, TvPairingPollResponse(ok: true, status: "pending", deviceToken: nil, device: nil, error: nil))
            }
            return s.pollSteps.removeFirst()
        }
    }
}

@MainActor
private final class MockPairingSession: PairingSessionContext {
    let deviceMetadata = PairingDeviceMetadata(model: "AppleTV14,1", osVersion: "tvOS 26.0", appVersion: "3.0.0")
    let client: MockPairingClient
    var completedBaseURL: URL?
    var completedToken: String?
    var completedDevice: TvPairedDeviceInfo?

    init(client: MockPairingClient) {
        self.client = client
    }

    func makePairingClient(baseURL: URL) -> (any PairingClientProviding)? { client }
    func completePairing(baseURL: URL, token: String, pairedDevice: TvPairedDeviceInfo, localHostnameURL: URL?) {
        completedBaseURL = baseURL
        completedToken = token
        completedDevice = pairedDevice
    }
}

final class SearchAndPairingViewModelsTests: XCTestCase {
    // MARK: - SearchViewModel Debounce, Kind Filtering, Rollback & Cancellation

    @MainActor
    func testSearchViewModelDebounceKindFilteringRollbackAndInactiveCancellation() async throws {
        let client = MockSearchClient()
        let session = MockSearchSession(client: client)
        let vm = SearchViewModel(isRootTab: true)

        vm.query = "a"
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertTrue(vm.results.isEmpty)

        // Rapid query schedule cancels first search before firing
        vm.query = "Du"
        vm.scheduleSearch(session: session, isActiveTab: true, debounceNanoseconds: 100_000_000)
        vm.query = "Dune"
        vm.scheduleSearch(session: session, isActiveTab: true, debounceNanoseconds: 10_000_000)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.lock.withLock { $0.queries }, ["Dune"])
        XCTAssertEqual(client.lock.withLock { $0.kinds }, ["all"])
        XCTAssertEqual(vm.results.first?.title, "Dune: Dune")
        XCTAssertEqual(session.recent, ["Dune"])

        // Kind filter triggers wire query with kind=series
        vm.selectedKind = .series
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(vm.lastCompletedKind, .series)
        XCTAssertEqual(client.lock.withLock { $0.kinds.last }, "series")

        client.lock.withLock { $0.failWatchlist = true }
        let card = try XCTUnwrap(vm.results.first)
        await vm.toggleWatchlist(card, session: session)
        XCTAssertEqual(vm.results.first?.inWatchlist, false)
        XCTAssertNotNil(vm.mutationErrorBanner)

        vm.unloadForMemoryWarning()
        XCTAssertTrue(vm.results.isEmpty && vm.isUnloadedForMemoryWarning)

        // Inactive root tab suppression, cancelAllTasks, direct cancel & scheduleSearch(isActiveTab: false)
        let tabClient = MockSearchClient()
        let tabSession = MockSearchSession(client: tabClient)
        let tabVM = SearchViewModel(initialQuery: "Dune", isRootTab: true)
        await tabVM.handleSearchTrigger(session: tabSession, isActiveTab: false, debounceNanoseconds: 0)
        XCTAssertTrue(tabClient.lock.withLock { $0.queries.isEmpty })

        await tabVM.handleSearchTrigger(session: tabSession, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(tabVM.lastCompletedQuery, "Dune")

        tabClient.lock.withLock { $0.searchDelayNanoseconds = 5_000_000_000 }
        tabVM.query = "Arrival"
        tabVM.scheduleSearch(session: tabSession, isActiveTab: true, debounceNanoseconds: 0)
        for _ in 0..<50 where !tabClient.lock.withLock({ $0.startedQueries.contains("Arrival") }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(tabVM.isSearching)
        tabVM.scheduleSearch(session: tabSession, isActiveTab: false, debounceNanoseconds: 0)
        XCTAssertFalse(tabVM.isSearching)

        // Cache-hit early return resets isSearching after cancelling in-flight search
        tabVM.query = "Solaris"
        tabVM.scheduleSearch(session: tabSession, isActiveTab: true, debounceNanoseconds: 0)
        for _ in 0..<50 where !tabClient.lock.withLock({ $0.startedQueries.contains("Solaris") }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(tabVM.isSearching)
        tabVM.query = "Dune"
        await tabVM.handleSearchTrigger(session: tabSession, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertFalse(tabVM.isSearching)
    }

    // MARK: - PairingViewModel Flow, Overflow Bounds & Room Speaker Layout

    @MainActor
    func testPairingViewModelFlowIntervalOverflowBoundsAndSpeakerLayout() async throws {
        XCTAssertEqual(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.max, multiplier: 1), 300_000_000_000)
        XCTAssertEqual(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.max, multiplier: 2), 600_000_000_000)
        XCTAssertEqual(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.min, multiplier: 1), 2_000_000_000)
        XCTAssertEqual(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: nil, multiplier: 1), 3_000_000_000)

        let discovery = MockServerDiscovery()
        let client = MockPairingClient()
        let session = MockPairingSession(client: client)
        let vm = PairingViewModel(discovery: discovery)

        vm.manualURLInput = "not a url ://"
        vm.submitManualURL(session: session)
        XCTAssertEqual(vm.errorMessage, "Oppgi en gyldig http:// eller https:// adresse.")

        let pairedDevice = TvPairedDeviceInfo(deviceId: "dev-1", deviceName: "Stua TV", roomName: "Stua", hardwareProfile: "hdr10-512", speakerLayout: "5.1.2")
        client.lock.withLock { s in
            s.pollSteps = [
                (429, TvPairingPollResponse(ok: false, status: "rate_limited", deviceToken: nil, device: nil, error: nil)),
                (200, TvPairingPollResponse(ok: true, status: "approved", deviceToken: "tok-paired", device: pairedDevice, error: nil)),
            ]
        }

        let srvURL = URL(string: "http://lunacore.local:8090")!
        let task = vm.startPairing(against: srvURL, localHostnameURL: srvURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000)
        await task.value
        XCTAssertEqual(session.completedToken, "tok-paired")
        XCTAssertEqual(session.completedDevice?.speakerLayout, "5.1.2")

        // Expired 410 stops polling cleanly
        client.lock.withLock { s in
            s.pollSteps = [(410, TvPairingPollResponse(ok: false, status: "expired", deviceToken: nil, device: nil, error: nil))]
        }
        await vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000).value
        XCTAssertTrue(vm.isCodeExpired)

        // stopDiscovery mid-request resets isRequestingCode and allows manual retry
        client.lock.withLock { $0.requestDelayNanoseconds = 5_000_000_000 }
        let midTask = vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000)
        await Task.yield()
        XCTAssertTrue(vm.isRequestingCode)
        vm.stopDiscovery()
        XCTAssertFalse(vm.isRequestingCode)
        await midTask.value

        client.lock.withLock { s in
            s.requestDelayNanoseconds = 0
            s.pollIntervalSeconds = Int.max
            s.pollSteps = []
        }
        let maxTask = vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: nil)
        for _ in 0..<50 where vm.pairingInfo?.pollIntervalSeconds != Int.max {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(vm.pairingInfo?.pollIntervalSeconds, Int.max)
        vm.stopDiscovery()
        await maxTask.value

        // Room speaker layout resolution
        XCTAssertEqual(SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: "5.1.2", equipmentLabel: "7.1.4", hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"), "5.1.2")
        XCTAssertEqual(SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: nil, equipmentLabel: "Samsung Frame · 5.1.2", hardwareProfile: "custom", roomName: "Stua"), "5.1.2")
        XCTAssertEqual(SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: nil, equipmentLabel: nil, hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"), "7.1.4")
        XCTAssertEqual(SpeakerLayoutOverrideMode.auto.displayTitle(forAutoLayout: "2.0"), "Auto (Stereo 2.0)")
    }
}
