import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class MockSearchClient: SearchClientProviding, @unchecked Sendable {
    let lock = Mutex<State>(State())

    struct State: Sendable {
        var queries: [String] = []
        var startedQueries: [String] = []
        var searchDelayNanoseconds: UInt64 = 0
        var failWatchlist = false
    }

    func searchFull(query: String, limit: Int) async throws -> TvSearchResponse {
        let delay = lock.withLock { s -> UInt64 in
            s.startedQueries.append(query)
            return s.searchDelayNanoseconds
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        lock.withLock { $0.queries.append(query) }
        return TvSearchResponse(
            ok: true,
            query: query,
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
        var requestCount = 0
        var pollCount = 0
    }

    func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String,
        capabilities: TvDeviceCapabilities
    ) async throws -> TvPairingRequestResponse {
        let delay = lock.withLock { s -> UInt64 in
            s.requestCount += 1
            return s.requestDelayNanoseconds
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return TvPairingRequestResponse(
            ok: true,
            pairingCode: "482910",
            displayCode: "482 910",
            expiresAt: "2026-11-26T01:00:00Z",
            pollIntervalSeconds: 2
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

final class SearchPairingAndRoomProfileTests: XCTestCase {
    @MainActor
    func testSearchViewModelDebounceCancellationRollbackAndMemoryUnload() async throws {
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
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(client.lock.withLock { $0.queries }, ["Dune"])
        XCTAssertEqual(vm.results.first?.title, "Dune: Dune")
        XCTAssertEqual(session.recent, ["Dune"])

        client.lock.withLock { $0.failWatchlist = true }
        let card = try XCTUnwrap(vm.results.first)
        await vm.toggleWatchlist(card, session: session)
        XCTAssertEqual(vm.results.first?.inWatchlist, false)
        XCTAssertNotNil(vm.mutationErrorBanner)

        vm.unloadForMemoryWarning()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertTrue(vm.isUnloadedForMemoryWarning)
        XCTAssertEqual(vm.query, "Dune")
    }

    @MainActor
    func testPairingViewModelAutoPairValidationExpiryAndCancellation() async throws {
        let discovery = MockServerDiscovery()
        let client = MockPairingClient()
        let session = MockPairingSession(client: client)
        let vm = PairingViewModel(discovery: discovery)

        vm.manualURLInput = "not a url ://"
        vm.submitManualURL(session: session)
        XCTAssertEqual(vm.errorMessage, "Oppgi en gyldig http:// eller https:// adresse.")

        let pairedDevice = TvPairedDeviceInfo(
            deviceId: "dev-1",
            deviceName: "Stua TV",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            speakerLayout: "5.1.2"
        )
        client.lock.withLock { s in
            s.pollSteps = [
                (429, TvPairingPollResponse(ok: false, status: "rate_limited", deviceToken: nil, device: nil, error: nil)),
                (200, TvPairingPollResponse(ok: true, status: "approved", deviceToken: "tok-paired", device: pairedDevice, error: nil)),
            ]
        }

        let srvURL = URL(string: "http://lunacore.local:8090")!
        let discovered = DiscoveredLunaCoreServer(id: "srv1", name: "LunaCore", baseURL: srvURL, apiPath: "/api/tv/v2", localHostnameURL: srvURL)
        let task = vm.startPairing(against: discovered.baseURL, localHostnameURL: discovered.localHostnameURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000)
        await task.value

        XCTAssertEqual(session.completedToken, "tok-paired")
        XCTAssertEqual(session.completedDevice?.speakerLayout, "5.1.2")

        // Expired 410 stops polling cleanly
        client.lock.withLock { s in
            s.pollSteps = [(410, TvPairingPollResponse(ok: false, status: "expired", deviceToken: nil, device: nil, error: nil))]
        }
        let expTask = vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000)
        await expTask.value
        XCTAssertTrue(vm.isCodeExpired)

        // Reset & stop cancels in-flight poll
        client.lock.withLock { $0.pollSteps = [] }
        let cancelTask = vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: 500_000_000)
        vm.stopDiscovery()
        await cancelTask.value
        XCTAssertEqual(discovery.stopCount, 1)
    }

    func testRoomSpeakerLayoutResolutionAndDecoding() throws {
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: "5.1.2", equipmentLabel: "7.1.4", hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"),
            "5.1.2"
        )
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: nil, equipmentLabel: "Samsung Frame · 5.1.2", hardwareProfile: "custom", roomName: "Stua"),
            "5.1.2"
        )
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: nil, equipmentLabel: nil, hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"),
            "7.1.4"
        )
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: nil, equipmentLabel: nil, hardwareProfile: "custom", roomName: "Stua"),
            "5.1.2"
        )
        XCTAssertEqual(SpeakerLayoutOverrideMode.auto.displayTitle(forAutoLayout: "2.0"), "Auto (Stereo 2.0)")

        let bootJSON = #"""
        {
          "ok": true,
          "device": {
            "deviceId": "tv-stua",
            "deviceName": "Apple TV Stua",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512",
            "speakerLayout": "5.1.2"
          },
          "defaultRooms": [
            { "roomId": "kjellerstua", "roomName": "Kjellerstua", "hardwareProfile": "dv-fel-714", "speakerLayout": "7.1.4" },
            { "roomId": "stua", "roomName": "Stua", "hardwareProfile": "hdr10-512", "speakerLayout": "5.1.2" }
          ]
        }
        """#
        let decoded = try JSONDecoder().decode(TvBootstrapResponse.self, from: Data(bootJSON.utf8))
        XCTAssertEqual(decoded.device.speakerLayout, "5.1.2")
        XCTAssertEqual(decoded.defaultRooms?.count, 2)
        XCTAssertEqual(decoded.defaultRooms?[0].speakerLayout, "7.1.4")
        XCTAssertEqual(decoded.defaultRooms?[1].speakerLayout, "5.1.2")
    }

    @MainActor
    func testSearchInactiveRootTabDoesNotFireAndCancelResetsIsSearching() async throws {
        let client = MockSearchClient()
        let session = MockSearchSession(client: client)
        let vm = SearchViewModel(initialQuery: "Dune", isRootTab: true)

        // Inactive root tab trigger must NOT fire search
        await vm.handleSearchTrigger(session: session, isActiveTab: false, debounceNanoseconds: 0)
        XCTAssertEqual(client.lock.withLock { $0.queries }, [])
        XCTAssertFalse(vm.isSearching)

        // Active root tab fires search cleanly
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(client.lock.withLock { $0.queries }, ["Dune"])
        XCTAssertEqual(vm.lastCompletedQuery, "Dune")

        // Mutation while inactive clears lastCompletedQuery without firing, then re-entering triggers fresh search
        session.homeRefreshNonce &+= 1
        await vm.handleSearchTrigger(session: session, isActiveTab: false, debounceNanoseconds: 0)
        XCTAssertEqual(client.lock.withLock { $0.queries }, ["Dune"])
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(client.lock.withLock { $0.queries }, ["Dune", "Dune"])

        // Cancelling mid-flight via cancelAllTasks resets isSearching = false
        client.lock.withLock { $0.searchDelayNanoseconds = 5_000_000_000 }
        vm.query = "Blade Runner"
        vm.scheduleSearch(session: session, isActiveTab: true, debounceNanoseconds: 0)
        for _ in 0..<50 {
            if client.lock.withLock({ $0.startedQueries.contains("Blade Runner") }) { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(vm.isSearching)
        vm.cancelAllTasks()
        XCTAssertFalse(vm.isSearching)

        // Direct executeSearch cancellation resets isSearching = false
        let directTask = Task { @MainActor in
            await vm.executeSearch(trimmed: "Arrival", session: session)
        }
        for _ in 0..<50 {
            if client.lock.withLock({ $0.startedQueries.contains("Arrival") }) { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(vm.isSearching)
        directTask.cancel()
        await directTask.value
        XCTAssertFalse(vm.isSearching)
    }

    @MainActor
    func testPairingStopDiscoveryMidRequestResetsIsRequestingCodeAndAllowsManualRetry() async throws {
        let discovery = MockServerDiscovery()
        let client = MockPairingClient()
        let session = MockPairingSession(client: client)
        let vm = PairingViewModel(discovery: discovery)
        let srvURL = URL(string: "http://lunacore.local:8090")!

        client.lock.withLock { $0.requestDelayNanoseconds = 5_000_000_000 }
        let task = vm.startPairing(against: srvURL, session: session, pollIntervalOverrideNanoseconds: 1_000_000)
        await Task.yield()
        XCTAssertTrue(vm.isRequestingCode)

        vm.stopDiscovery()
        XCTAssertFalse(vm.isRequestingCode)
        await task.value
        XCTAssertFalse(vm.isRequestingCode)

        // Manual URL submission must not be locked out after stopDiscovery
        client.lock.withLock { $0.requestDelayNanoseconds = 0 }
        vm.manualURLInput = "http://lunacore.local:8090"
        vm.submitManualURL(session: session)
        XCTAssertTrue(vm.isRequestingCode)
        vm.stopDiscovery()
        XCTAssertFalse(vm.isRequestingCode)
    }

    @MainActor
    func testSearchScheduleInactiveTabCancelsInFlightAndResetsIsSearching() async throws {
        let client = MockSearchClient()
        let session = MockSearchSession(client: client)
        let vm = SearchViewModel(isRootTab: true)

        // 1. Seed a completed query so cache-hit path is available later
        vm.query = "Dune"
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertEqual(vm.lastCompletedQuery, "Dune")
        XCTAssertFalse(vm.isSearching)

        // 2. Start an in-flight search, then call scheduleSearch(isActiveTab: false)
        client.lock.withLock { $0.searchDelayNanoseconds = 5_000_000_000 }
        vm.query = "Arrival"
        vm.scheduleSearch(session: session, isActiveTab: true, debounceNanoseconds: 0)
        for _ in 0..<50 {
            if client.lock.withLock({ $0.startedQueries.contains("Arrival") }) { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(vm.isSearching)

        vm.scheduleSearch(session: session, isActiveTab: false, debounceNanoseconds: 0)
        XCTAssertFalse(vm.isSearching)
        await Task.yield()
        XCTAssertFalse(vm.isSearching)

        // 3. Cache-hit early return on handleSearchTrigger resets isSearching after cancelling an in-flight search
        vm.query = "Solaris"
        vm.scheduleSearch(session: session, isActiveTab: true, debounceNanoseconds: 0)
        for _ in 0..<50 {
            if client.lock.withLock({ $0.startedQueries.contains("Solaris") }) { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(vm.isSearching)
        vm.query = "Dune"
        await vm.handleSearchTrigger(session: session, isActiveTab: true, debounceNanoseconds: 0)
        XCTAssertFalse(vm.isSearching)
    }
}
