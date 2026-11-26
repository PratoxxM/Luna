import Foundation
import XCTest
@testable import Luna

private actor SourcePickerHeartbeatSignal {
    private var count = 0
    private var waiters: [(target: Int, cont: CheckedContinuation<Void, Never>)] = []

    func record() {
        count += 1
        var remaining: [(target: Int, cont: CheckedContinuation<Void, Never>)] = []
        for entry in waiters {
            if count >= entry.target {
                entry.cont.resume()
            } else {
                remaining.append(entry)
            }
        }
        waiters = remaining
    }

    func wait(untilAtLeast target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }
}

private final class MockSourcePickerSessionClient: SourcePickerSessionClient, @unchecked Sendable {
    let prepareGate = TestStepGate()
    let heartbeatSignal = SourcePickerHeartbeatSignal()
    let log = TestLockedBox<[String]>([])
    let stoppedSessions = TestLockedBox<[String]>([])
    let cancelledInflightTokens = TestLockedBox<[String]>([])
    let fetchAlternativesCount = TestLockedBox<Int>(0)
    let prepareCount = TestLockedBox<Int>(0)
    let sessionIdToReturn: String
    let prepareTokenToReturn: String
    let gatePrepare: Bool
    let failAlternativesOnce: Bool
    let throwOnFetchAlternatives: (any Error)?

    init(
        sessionIdToReturn: String = "sess-orphan-1",
        prepareTokenToReturn: String = "prep-tok-1",
        gatePrepare: Bool = true,
        failAlternativesOnce: Bool = false,
        throwOnFetchAlternatives: (any Error)? = nil
    ) {
        self.sessionIdToReturn = sessionIdToReturn
        self.prepareTokenToReturn = prepareTokenToReturn
        self.gatePrepare = gatePrepare
        self.failAlternativesOnce = failAlternativesOnce
        self.throwOnFetchAlternatives = throwOnFetchAlternatives
    }

    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        prepareToken: String?
    ) async throws -> TvPrepareResponse {
        let idx = prepareCount.withLock { count -> Int in
            count += 1
            return count
        }
        if gatePrepare {
            await prepareGate.wait(label: "prepare", log: log)
        }
        let sid = idx == 1 ? sessionIdToReturn : "\(sessionIdToReturn)-\(idx)"
        let tok = idx == 1 ? prepareTokenToReturn : "\(prepareTokenToReturn)-\(idx)"
        let json = """
        {
          "ok": true,
          "status": "ready",
          "prepareToken": "\(tok)",
          "playbackSession": {
            "sessionId": "\(sid)",
            "streamToken": "stream-placeholder-token",
            "roomName": "Stua",
            "hardwareProfile": "hdr10-512",
            "item": {
              "itemId": "\(itemId)",
              "mediaType": "movie",
              "ids": { "tmdb": 550 },
              "title": "\(title)"
            },
            "selectedCandidate": {
              "candidateId": "cand-1",
              "displayHeadline": "4K",
              "releaseTitle": "Movie.2024.2160p",
              "source": "nvme"
            },
            "stream": { "url": "/api/tv/v2/streams/\(sid)/master" },
            "aetherConfig": {
              "preferDualLayerDolbyVision": false,
              "dolbyVisionHandling": "baseLayerOnly",
              "matchContentEnabled": true,
              "audioBridgeMode": "lossless"
            }
          }
        }
        """
        return try JSONDecoder().decode(TvPrepareResponse.self, from: Data(json.utf8))
    }

    func cancelInflightPlayback(
        sessionId: String?,
        resolveId: String?,
        itemId: String?,
        prepareToken: String?
    ) async throws {
        if let prepareToken {
            cancelledInflightTokens.withLock { $0.append(prepareToken) }
        }
    }

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        let callIndex = fetchAlternativesCount.withLock { count -> Int in
            count += 1
            return count
        }
        if let throwOnFetchAlternatives {
            throw throwOnFetchAlternatives
        }
        if failAlternativesOnce && callIndex == 1 {
            throw LunaCoreError.serverMessage(404, "Expired session")
        }
        let json = """
        {
          "ok": true,
          "sessionId": "\(sessionId)",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "activeCandidateId": "cand-1",
          "alternatives": [
            {
              "candidateId": "cand-1",
              "displayHeadline": "4K",
              "releaseTitle": "Movie.2024.2160p",
              "source": "nvme",
              "isActive": true
            }
          ]
        }
        """
        return try JSONDecoder().decode(TvAlternativesResponse.self, from: Data(json.utf8))
    }

    func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?
    ) async throws -> TvHeartbeatResponse {
        if state == "stopped" {
            stoppedSessions.withLock { $0.append(sessionId) }
            await heartbeatSignal.record()
        }
        let json = """
        {
          "ok": true,
          "sessionId": "\(sessionId)",
          "state": "\(state)",
          "vfsLockActive": false
        }
        """
        return try JSONDecoder().decode(TvHeartbeatResponse.self, from: Data(json.utf8))
    }
}

final class SourcePickerCancellationTests: XCTestCase {
    func testSourcePickerTokenPolicyClearsExpiredExistingPrepareTokenOnRetry() {
        XCTAssertEqual(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: " prep-tok-1 ",
                existingTokenFailed: false
            ),
            "prep-tok-1"
        )
        XCTAssertNil(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: "prep-tok-1",
                existingTokenFailed: true
            )
        )
        XCTAssertNil(
            SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: "   ",
                existingTokenFailed: false
            )
        )
    }

    @MainActor
    func testSourcePickerCancellationDuringInFlightPrepareStopsOrphanSessionWithoutLeaking() async {
        let context = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club"
        )

        // 1. Sheet dismisses (.onDisappear + task cancel) while preparePlayback is in-flight:
        //    newly returned sessionId MUST be stopped immediately via sendHeartbeat(state: "stopped")
        //    and MUST NOT record createdOrphanSessionId or call fetchAlternatives.
        let cancelledClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-orphan-cancel-1",
            prepareTokenToReturn: "prep-cancel-1"
        )
        let vm = SourcePickerViewModel()
        let loadTask = Task { @MainActor in
            await vm.loadCandidates(context: context, client: cancelledClient, onUnauthorized: {})
        }

        await cancelledClient.prepareGate.waitUntilStarted()
        vm.handleDisappear(context: context, client: cancelledClient)
        loadTask.cancel()
        await cancelledClient.prepareGate.finish()
        await loadTask.value
        await cancelledClient.heartbeatSignal.wait(untilAtLeast: 1)

        XCTAssertEqual(cancelledClient.stoppedSessions.withLock { $0 }, ["sess-orphan-cancel-1"])
        XCTAssertEqual(cancelledClient.fetchAlternativesCount.withLock { $0 }, 0)
        XCTAssertNil(vm.createdOrphanSessionId)
        XCTAssertNil(vm.resolvedPrepareToken)
        XCTAssertTrue(vm.candidates.isEmpty)

        // 2. Non-cancelled load populates candidates & stops created session once on disappear.
        let activeClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-active-2",
            prepareTokenToReturn: "prep-active-2"
        )
        let activeVm = SourcePickerViewModel()
        let activeTask = Task { @MainActor in
            await activeVm.loadCandidates(context: context, client: activeClient, onUnauthorized: {})
        }
        await activeClient.prepareGate.waitUntilStarted()
        await activeClient.prepareGate.finish()
        await activeTask.value

        XCTAssertEqual(activeClient.fetchAlternativesCount.withLock { $0 }, 1)
        XCTAssertTrue(activeClient.stoppedSessions.withLock { $0 }.isEmpty)
        XCTAssertEqual(activeVm.createdOrphanSessionId, "sess-active-2")
        XCTAssertEqual(activeVm.resolvedPrepareToken, "prep-active-2")
        XCTAssertEqual(activeVm.candidates.count, 1)

        activeVm.handleDisappear(context: context, client: activeClient)
        await activeClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(activeClient.stoppedSessions.withLock { $0 }, ["sess-active-2"])
        XCTAssertNil(activeVm.createdOrphanSessionId)

        // 3. Existing token fails -> retry launches preparePlayback -> sheet dismissed before Task.cancel():
        //    isDismissed guard still stops the newly created session without leaking.
        let retryContext = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            existingPrepareToken: "stale-preresolve-tok"
        )
        let retryClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-retry-orphan-3",
            prepareTokenToReturn: "prep-retry-3",
            gatePrepare: true,
            failAlternativesOnce: true
        )
        let retryVm = SourcePickerViewModel()
        await retryVm.loadCandidates(context: retryContext, client: retryClient, onUnauthorized: {})
        XCTAssertTrue(retryVm.existingTokenFailed)
        XCTAssertEqual(retryClient.fetchAlternativesCount.withLock { $0 }, 1)

        let retryTask = Task { @MainActor in
            await retryVm.loadCandidates(context: retryContext, client: retryClient, onUnauthorized: {})
        }
        await retryClient.prepareGate.waitUntilStarted()
        retryVm.handleDisappear(context: retryContext, client: retryClient)
        await retryClient.prepareGate.finish()
        await retryTask.value
        await retryClient.heartbeatSignal.wait(untilAtLeast: 1)

        XCTAssertEqual(retryClient.stoppedSessions.withLock { $0 }, ["sess-retry-orphan-3"])
        XCTAssertEqual(retryClient.fetchAlternativesCount.withLock { $0 }, 1)
        XCTAssertNil(retryVm.createdOrphanSessionId)

        // 4. Non-cancellation fetchAlternatives failure stops created orphan session immediately before retry.
        let failAltClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-alt-fail",
            prepareTokenToReturn: "prep-alt-fail",
            gatePrepare: false,
            failAlternativesOnce: true
        )
        let failAltVm = SourcePickerViewModel()
        await failAltVm.loadCandidates(context: context, client: failAltClient, onUnauthorized: {})
        await failAltClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(failAltClient.stoppedSessions.withLock { $0 }, ["sess-alt-fail"])
        XCTAssertNil(failAltVm.createdOrphanSessionId)
        XCTAssertNotNil(failAltVm.errorMessage)

        await failAltVm.loadCandidates(context: context, client: failAltClient, onUnauthorized: {})
        XCTAssertNil(failAltVm.errorMessage)
        XCTAssertEqual(failAltVm.createdOrphanSessionId, "sess-alt-fail-2")
        failAltVm.handleDisappear(context: context, client: failAltClient)
        await failAltClient.heartbeatSignal.wait(untilAtLeast: 2)
        XCTAssertEqual(failAltClient.stoppedSessions.withLock { $0 }, ["sess-alt-fail", "sess-alt-fail-2"])

        // 5. Whitespace-only existingPrepareToken ("   ") is treated as nil on disappear
        //    so a newly created orphan session is still stopped cleanly on dismiss.
        let whitespaceContext = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            existingPrepareToken: "   "
        )
        let whitespaceClient = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-whitespace-orphan",
            prepareTokenToReturn: "prep-whitespace-1"
        )
        let whitespaceVm = SourcePickerViewModel()
        let whitespaceTask = Task { @MainActor in
            await whitespaceVm.loadCandidates(context: whitespaceContext, client: whitespaceClient, onUnauthorized: {})
        }
        await whitespaceClient.prepareGate.waitUntilStarted()
        await whitespaceClient.prepareGate.finish()
        await whitespaceTask.value
        whitespaceVm.handleDisappear(context: whitespaceContext, client: whitespaceClient)
        await whitespaceClient.heartbeatSignal.wait(untilAtLeast: 1)
        XCTAssertEqual(whitespaceClient.stoppedSessions.withLock { $0 }, ["sess-whitespace-orphan"])
        XCTAssertNil(whitespaceVm.createdOrphanSessionId)
    }

    @MainActor
    func testSourcePickerLoadCandidatesIgnoresNSURLErrorCancelledAndStopsOrphanSession() async {
        let context = SourcePickerContext(
            itemId: "movie:tmdb:550",
            title: "Fight Club"
        )
        let client = MockSourcePickerSessionClient(
            sessionIdToReturn: "sess-nsurl-cancel",
            prepareTokenToReturn: "prep-nsurl-cancel",
            gatePrepare: false,
            throwOnFetchAlternatives: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )
        let vm = SourcePickerViewModel()
        var unauthorizedCount = 0

        await vm.loadCandidates(
            context: context,
            client: client,
            onUnauthorized: { unauthorizedCount += 1 }
        )
        await client.heartbeatSignal.wait(untilAtLeast: 1)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(unauthorizedCount, 0)
        XCTAssertEqual(client.stoppedSessions.withLock { $0 }, ["sess-nsurl-cancel"])
        XCTAssertNil(vm.createdOrphanSessionId)
    }
}
