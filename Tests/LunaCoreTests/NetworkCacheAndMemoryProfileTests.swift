import Foundation
import Synchronization
import XCTest
@testable import LunaCore

private final class LockedBox<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ initial: Value) { self.mutex = Mutex(initial) }
    func get() -> Value { mutex.withLock { $0 } }
    func set(_ newValue: Value) { mutex.withLock { $0 = newValue } }
    func modify(_ body: (inout Value) -> Void) { mutex.withLock { body(&$0) } }
}

final class NetworkCacheAndMemoryProfileTests: XCTestCase {
    func testDeviceMemoryProfileStandardVsHigh2026Thresholds() {
        let gib: UInt64 = 1_073_741_824

        let gen2ThreeGB = DeviceMemoryProfile(physicalMemoryBytes: 3 * gib, activeProcessorCount: 6)
        let gen3FourGB = DeviceMemoryProfile(physicalMemoryBytes: 4 * gib, activeProcessorCount: 5)
        let a19EightGB = DeviceMemoryProfile(physicalMemoryBytes: 8 * gib, activeProcessorCount: 6)

        XCTAssertEqual(gen2ThreeGB.tier, .standard)
        XCTAssertEqual(gen3FourGB.tier, .standard)
        XCTAssertEqual(a19EightGB.tier, .high2026)

        XCTAssertEqual(gen3FourGB.artworkMemoryBytes, 112 * 1024 * 1024)
        XCTAssertEqual(gen3FourGB.artworkMemoryCountLimit, 420)
        XCTAssertEqual(gen3FourGB.artworkDiskMaxBytes, 160 * 1024 * 1024)
        XCTAssertEqual(gen3FourGB.maxConcurrentDecodes, 4)
        XCTAssertEqual(gen3FourGB.apiConnectionsPerHost, 8)
        XCTAssertEqual(gen3FourGB.artworkConnectionsPerHost, 8)
        XCTAssertEqual(gen3FourGB.externalArtworkConnectionsPerHost, 8)
        XCTAssertEqual(gen3FourGB.catalogPageSize, 30)
        XCTAssertEqual(gen3FourGB.libraryPageSize, 36)
        XCTAssertEqual(gen3FourGB.catalogCacheMaxEntries, 16)
        XCTAssertEqual(gen3FourGB.libraryCacheMaxEntries, 12)
        XCTAssertEqual(gen3FourGB.itemDetailCacheMaxEntries, 8)
        XCTAssertEqual(gen3FourGB.scrollPrefetchCardWindow, 6)
        XCTAssertFalse(gen3FourGB.enableBackgroundCatalogMetadataWarmup)
        XCTAssertEqual(gen3FourGB.prewarmByteBudget(availableMemoryBytes: 800 * 1024 * 1024), 8 * 1024 * 1024)
        XCTAssertEqual(gen3FourGB.prewarmByteBudget(availableMemoryBytes: 400 * 1024 * 1024), 0)

        XCTAssertEqual(a19EightGB.artworkMemoryBytes, 384 * 1024 * 1024)
        XCTAssertEqual(a19EightGB.artworkMemoryCountLimit, 1_400)
        XCTAssertEqual(a19EightGB.artworkDiskMaxBytes, 512 * 1024 * 1024)
        XCTAssertEqual(a19EightGB.maxConcurrentDecodes, 8)
        XCTAssertEqual(a19EightGB.apiConnectionsPerHost, 12)
        XCTAssertEqual(a19EightGB.artworkConnectionsPerHost, 16)
        XCTAssertEqual(a19EightGB.externalArtworkConnectionsPerHost, 16)
        XCTAssertEqual(a19EightGB.catalogPageSize, 48)
        XCTAssertEqual(a19EightGB.libraryPageSize, 60)
        XCTAssertEqual(a19EightGB.catalogCacheMaxEntries, 64)
        XCTAssertEqual(a19EightGB.libraryCacheMaxEntries, 36)
        XCTAssertEqual(a19EightGB.itemDetailCacheMaxEntries, 32)
        XCTAssertEqual(a19EightGB.scrollPrefetchCardWindow, 18)
        XCTAssertTrue(a19EightGB.enableBackgroundCatalogMetadataWarmup)
        XCTAssertEqual(a19EightGB.prewarmByteBudget(availableMemoryBytes: 2_000 * 1024 * 1024, isFastLocalTier: true), 16 * 1024 * 1024)
        XCTAssertEqual(a19EightGB.prewarmByteBudget(availableMemoryBytes: 2_000 * 1024 * 1024, isFastLocalTier: false), 8 * 1024 * 1024)
        XCTAssertEqual(a19EightGB.prewarmByteBudget(availableMemoryBytes: 900 * 1024 * 1024, isFastLocalTier: true), 8 * 1024 * 1024)
        XCTAssertEqual(a19EightGB.prewarmByteBudget(availableMemoryBytes: 500 * 1024 * 1024, isFastLocalTier: true), 0)
        XCTAssertEqual(SideloadSafeStorage.currentAppVersionString(), "3.0.0")
    }

    func testHeartbeatNextEpisodePrewarmPayloadDecoding() throws {
        let raw = #"""
        {
          "ok": true,
          "sessionId": "tvs_active",
          "state": "playing",
          "nextEpisodePrewarm": {
            "itemId": "episode:tmdb:95396:s1:e2",
            "sessionId": "tvs_next85",
            "streamToken": "0123456789abcdef0123456789abcdef",
            "streamUrl": "/api/tv/v2/stream/tvs_next85/0123456789abcdef0123456789abcdef/Severance.S01E02.mkv",
            "canClientPrewarmBytes": true,
            "nextEpisode": {
              "itemId": "episode:tmdb:95396:s1:e2",
              "season": 1,
              "episode": 2,
              "title": "Half Loop"
            }
          }
        }
        """#
        let decoded = try JSONDecoder().decode(TvHeartbeatResponse.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.nextEpisodePrewarm?.sessionId, "tvs_next85")
        XCTAssertEqual(decoded.nextEpisodePrewarm?.canClientPrewarmBytes, true)
        XCTAssertEqual(decoded.nextEpisodePrewarm?.nextEpisode?.episode, 2)
        XCTAssertEqual(decoded.nextEpisodePrewarm?.nextEpisode?.title, "Half Loop")
    }

    func testInflightTaskCoalescerDeduplicatesConcurrentCallers() async throws {
        let coalescer = InflightTaskCoalescer<String, Int>()
        let invocationCounter = LockedBox(0)

        async let first = coalescer.coalesce(key: "GET|/home") {
            invocationCounter.modify { $0 += 1 }
            try await Task.sleep(nanoseconds: 60_000_000)
            return 42
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        async let second = coalescer.coalesce(key: "GET|/home") {
            invocationCounter.modify { $0 += 1 }
            return 99
        }
        async let third = coalescer.coalesce(key: "GET|/home") {
            invocationCounter.modify { $0 += 1 }
            return 100
        }

        let (r1, r2, r3) = try await (first, second, third)
        XCTAssertEqual(r1.value, 42)
        XCTAssertEqual(r2.value, 42)
        XCTAssertEqual(r3.value, 42)
        XCTAssertFalse(r1.wasCoalesced)
        XCTAssertTrue(r2.wasCoalesced)
        XCTAssertTrue(r3.wasCoalesced)
        XCTAssertEqual(invocationCounter.get(), 1)
        XCTAssertEqual(coalescer.inflightCount, 0)
    }

    func testInflightTaskCoalescerIsolatesSingleWaiterCancellationWhileOtherWaitersListen() async throws {
        let coalescer = InflightTaskCoalescer<String, String>()
        let underlyingCancelled = LockedBox(false)
        let startedGate = LockedBox(false)

        let survivingTask = Task {
            try await coalescer.coalesce(key: "shared-key") {
                startedGate.set(true)
                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                    if Task.isCancelled {
                        underlyingCancelled.set(true)
                    }
                    return "fullført-verdi"
                } catch {
                    underlyingCancelled.set(true)
                    throw error
                }
            }
        }

        while !startedGate.get() {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        let cancelledWaiter1 = Task {
            try await coalescer.coalesce(key: "shared-key") { "feil" }
        }
        let cancelledWaiter2 = Task {
            try await coalescer.coalesce(key: "shared-key") { "feil" }
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        // Cancel two of the three waiters while `survivingTask` is still awaiting!
        cancelledWaiter1.cancel()
        cancelledWaiter2.cancel()

        let res1 = await cancelledWaiter1.result
        let res2 = await cancelledWaiter2.result
        if case .success = res1 { XCTFail("Expected cancelledWaiter1 to fail with CancellationError") }
        if case .success = res2 { XCTFail("Expected cancelledWaiter2 to fail with CancellationError") }

        let survivor = try await survivingTask.value
        XCTAssertEqual(survivor.value, "fullført-verdi")
        XCTAssertFalse(underlyingCancelled.get(), "Underlying task MUST NOT be cancelled while a surviving waiter still listens")
        XCTAssertEqual(coalescer.inflightCount, 0)
    }

    func testInflightTaskCoalescerCancelsUnderlyingTaskWhenLastWaiterCancels() async throws {
        let coalescer = InflightTaskCoalescer<String, Int>()
        let underlyingObservedCancel = LockedBox(false)
        let startedGate = LockedBox(false)

        let waiterA = Task {
            try await coalescer.coalesce(key: "ephemeral") {
                startedGate.set(true)
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return 7
                } catch {
                    underlyingObservedCancel.set(true)
                    throw error
                }
            }
        }

        while !startedGate.get() {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        let waiterB = Task {
            try await coalescer.coalesce(key: "ephemeral") { 8 }
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        waiterA.cancel()
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertFalse(underlyingObservedCancel.get(), "Must stay alive while waiterB still listens")

        waiterB.cancel()
        _ = await waiterA.result
        _ = await waiterB.result
        for _ in 0..<50 where !underlyingObservedCancel.get() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(underlyingObservedCancel.get(), "Underlying task must cancel once final waiter cancels")
        XCTAssertEqual(coalescer.inflightCount, 0)
    }

    func testBoundedLRUMemoryCacheEvictionAndPredicateInvalidation() async {
        await MainActor.run {
            let cache = BoundedLRUMemoryCache<Int>(maxEntries: 3)
            cache.store(1, for: "movie:tmdb:100")
            cache.store(2, for: "movie:tmdb:200")
            cache.store(3, for: "series:tmdb:300")
            XCTAssertEqual(cache.snapshot(for: "movie:tmdb:100"), 1)
            cache.store(4, for: "movie:tmdb:400")

            XCTAssertNil(cache.snapshot(for: "movie:tmdb:200"))
            XCTAssertEqual(cache.snapshot(for: "movie:tmdb:100"), 1)
            XCTAssertEqual(cache.snapshot(for: "series:tmdb:300"), 3)
            XCTAssertEqual(cache.snapshot(for: "movie:tmdb:400"), 4)

            cache.removeWhere { key, _ in key.contains("tmdb:300") }
            XCTAssertNil(cache.snapshot(for: "series:tmdb:300"))
            XCTAssertEqual(cache.entryCount, 2)
        }
    }

    func testItemDetailMemoryCacheTargetedInvalidationByItemIdAndTmdbId() async throws {
        let movie550 = try JSONDecoder().decode(
            TvItemDetail.self,
            from: Data(#"{"itemId":"movie:tmdb:550","mediaType":"movie","ids":{"tmdb":550},"title":"Fight Club","inWatchlist":false,"watched":false}"#.utf8)
        )
        let series95396 = try JSONDecoder().decode(
            TvItemDetail.self,
            from: Data(#"{"itemId":"series:tmdb:95396","mediaType":"series","ids":{"tmdb":95396},"title":"Severance","inWatchlist":true,"watched":false}"#.utf8)
        )
        let movie157336 = try JSONDecoder().decode(
            TvItemDetail.self,
            from: Data(#"{"itemId":"movie:tmdb:157336","mediaType":"movie","ids":{"tmdb":157336},"title":"Interstellar","inWatchlist":false,"watched":false}"#.utf8)
        )

        let base = try XCTUnwrap(URL(string: "http://luna-cache-test.local:8090"))
        await MainActor.run {
            ItemDetailMemoryCache.shared.clear()
            let key550 = ItemDetailMemoryCache.makeKey(baseURL: base, mediaType: "movie", itemId: "movie:tmdb:550", roomName: "Stua", hardwareProfile: "hdr10-512")
            let key95396 = ItemDetailMemoryCache.makeKey(baseURL: base, mediaType: "series", itemId: "series:tmdb:95396", roomName: "Stua", hardwareProfile: "hdr10-512")
            let key157336 = ItemDetailMemoryCache.makeKey(baseURL: base, mediaType: "movie", itemId: "movie:tmdb:157336", roomName: "Stua", hardwareProfile: "hdr10-512")

            ItemDetailMemoryCache.shared.store(ItemDetailSnapshot(detail: movie550, refreshNonce: 1), for: key550)
            ItemDetailMemoryCache.shared.store(ItemDetailSnapshot(detail: series95396, refreshNonce: 1), for: key95396)
            ItemDetailMemoryCache.shared.store(ItemDetailSnapshot(detail: movie157336, refreshNonce: 1), for: key157336)
            XCTAssertEqual(ItemDetailMemoryCache.shared.entryCount, 3)

            // Closing player after watching episode:tmdb:95396:s1:e2 must extract tmdb 95396 and evict series:tmdb:95396!
            ItemDetailMemoryCache.invalidate(itemId: "episode:tmdb:95396:s1:e2", tmdbId: nil)
            XCTAssertNil(ItemDetailMemoryCache.shared.snapshot(for: key95396))
            XCTAssertNotNil(ItemDetailMemoryCache.shared.snapshot(for: key550))
            XCTAssertNotNil(ItemDetailMemoryCache.shared.snapshot(for: key157336))

            // Mutating movie:tmdb:550 evicts only 550
            ItemDetailMemoryCache.invalidate(itemId: "movie:tmdb:550", tmdbId: 550)
            XCTAssertNil(ItemDetailMemoryCache.shared.snapshot(for: key550))
            XCTAssertNotNil(ItemDetailMemoryCache.shared.snapshot(for: key157336))

            ItemDetailMemoryCache.shared.clear()
        }
    }

    func testLunaCoreErrorRecognizesCancellationErrorAndURLErrorCancelled() {
        XCTAssertTrue(LunaCoreError.isCancellation(CancellationError()))
        XCTAssertTrue(LunaCoreError.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(LunaCoreError.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(LunaCoreError.isCancellation(LunaCoreError.unauthorized))
    }

    func testEtappe3A19PlaybackBudgetsAndConcurrencyCaps() {
        let standard = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 6)
        let high2026 = DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824, activeProcessorCount: 6)

        XCTAssertEqual(standard.sessionCacheByteBudget, 1_073_741_824)
        XCTAssertEqual(standard.sessionCacheFreeReserveBytes, 1_536 * 1_048_576)
        XCTAssertFalse(standard.defaultLowResUpscaleEnabled)

        XCTAssertEqual(high2026.sessionCacheByteBudget, 3 * 1_073_741_824)
        XCTAssertEqual(high2026.sessionCacheFreeReserveBytes, 4 * 1_073_741_824)
        XCTAssertTrue(high2026.defaultLowResUpscaleEnabled)

        // Retained session cache after stop
        XCTAssertFalse(standard.retainsSessionCacheAfterStop(availableMemoryBytes: 2_000 * 1_048_576))
        XCTAssertFalse(high2026.retainsSessionCacheAfterStop(availableMemoryBytes: 900 * 1_048_576))
        XCTAssertTrue(high2026.retainsSessionCacheAfterStop(availableMemoryBytes: 1_000 * 1_048_576))

        // Forward buffer segments
        XCTAssertEqual(high2026.forwardBufferSegments(availableMemoryBytes: 1_600 * 1_048_576), 45)
        XCTAssertEqual(high2026.forwardBufferSegments(availableMemoryBytes: 1_000 * 1_048_576), 24)
        XCTAssertEqual(high2026.forwardBufferSegments(availableMemoryBytes: 500 * 1_048_576), 12)
        XCTAssertEqual(standard.forwardBufferSegments(availableMemoryBytes: 600 * 1_048_576), 12)
        XCTAssertEqual(standard.forwardBufferSegments(availableMemoryBytes: 400 * 1_048_576), 8)

        // Concurrent source requests + strict single-stream (<= 1) server cap preservation
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 2), 8)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: false, isSameOrigin: true, serverConfigured: 2), 4)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: false, isSameOrigin: false, serverConfigured: 2), 2)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 1), 1)
        XCTAssertEqual(high2026.maxConcurrentSourceRequests(isFastLocalTier: false, isSameOrigin: true, serverConfigured: 1), 1)

        XCTAssertEqual(standard.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 2), 6)
        XCTAssertEqual(standard.maxConcurrentSourceRequests(isFastLocalTier: false, isSameOrigin: true, serverConfigured: 2), 3)
        XCTAssertEqual(standard.maxConcurrentSourceRequests(isFastLocalTier: false, isSameOrigin: true, serverConfigured: 4), 4)
        XCTAssertEqual(standard.maxConcurrentSourceRequests(isFastLocalTier: true, isSameOrigin: true, serverConfigured: 1), 1)
    }

    func testCandidateHardwareRoutingAndBcp47LanguageNormalization() {
        func makeCandidate(
            resolution: String? = "2160p",
            range: String? = nil,
            dvProfile: Int? = nil,
            dvLayer: String? = nil,
            codec: String? = nil
        ) -> TvCandidateInfo {
            TvCandidateInfo(
                candidateId: "c1",
                displayHeadline: "Test",
                releaseTitle: "Test",
                source: "ssd",
                tier: "ssd",
                resolution: resolution,
                videoRangeType: range,
                dvProfile: dvProfile,
                dvEnhancementLayer: dvLayer,
                audioCodec: "truehd",
                sizeBytes: 50 * 1_073_741_824,
                tvScore: 100,
                isActive: true,
                explanationChips: nil,
                releaseGroup: nil,
                isNorwegian: false,
                videoCodec: codec
            )
        }

        let dvFel = makeCandidate(range: "DolbyVision", dvProfile: 7, dvLayer: "FEL", codec: "hevc")
        XCTAssertTrue(dvFel.canCarryDualLayerDolbyVision)
        XCTAssertTrue(dvFel.allowsDualLayerDolbyVisionWhenForced)
        XCTAssertFalse(dvFel.requiresSoftwareVideoDecode(supportsHardwareAV1: true))

        let av1Hdr = makeCandidate(range: "HDR10+", dvProfile: nil, codec: "av1")
        XCTAssertFalse(av1Hdr.canCarryDualLayerDolbyVision)
        XCTAssertFalse(av1Hdr.allowsDualLayerDolbyVisionWhenForced)
        XCTAssertFalse(av1Hdr.requiresSoftwareVideoDecode(supportsHardwareAV1: true))
        XCTAssertTrue(av1Hdr.requiresSoftwareVideoDecode(supportsHardwareAV1: false))

        let dvP8 = makeCandidate(range: "DolbyVision", dvProfile: 8, codec: "hevc")
        XCTAssertFalse(dvP8.canCarryDualLayerDolbyVision)
        XCTAssertFalse(dvP8.allowsDualLayerDolbyVisionWhenForced)

        let hdr10Remux = makeCandidate(range: "HDR10", dvProfile: nil, codec: "hevc")
        XCTAssertFalse(hdr10Remux.canCarryDualLayerDolbyVision)
        XCTAssertTrue(hdr10Remux.allowsDualLayerDolbyVisionWhenForced)
        XCTAssertFalse(hdr10Remux.isLikelyLowResolutionSDRForUpscale)

        let hdSdr = makeCandidate(resolution: "1080p", range: "SDR", codec: "h264")
        XCTAssertTrue(hdSdr.isLikelyLowResolutionSDRForUpscale)
        XCTAssertFalse(hdSdr.canCarryDualLayerDolbyVision)

        let vp9Web = makeCandidate(resolution: "2160p", range: "HDR10", codec: "vp9")
        XCTAssertTrue(vp9Web.requiresSoftwareVideoDecode(supportsHardwareAV1: true))

        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("nb-NO"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("nn_NO"), "nob")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("en-US"), "eng")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("sv-SE"), "swe")
        XCTAssertEqual(SmartTrackRuleEngine.normalizeLanguage("da-DK"), "dan")
    }

    func testThreadSafeLRUMemoryCacheConcurrentStressSafety() async {
        let cache = ThreadSafeLRUMemoryCache<Int>(totalCostLimit: 256, countLimit: 24)
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<16 {
                group.addTask {
                    for iter in 0..<250 {
                        let key = "item-\((worker * 7 + iter) % 40)"
                        let subject = "subj-\((worker + iter) % 10)"
                        cache.insert(
                            worker * 1000 + iter,
                            forKey: key,
                            subjectKey: subject,
                            cost: ((iter % 5) + 1) * 8,
                            qualityRank: (iter % 4) * 320 + 320
                        )
                        _ = cache.image(forKey: key)
                        _ = cache.bestImage(forSubjectKey: subject)
                        if iter % 40 == 0 {
                            cache.totalCostLimit = (iter % 80 == 0) ? 192 : 256
                        }
                        if iter % 125 == 124 && worker == 0 {
                            cache.removeAll()
                        }
                        XCTAssertLessThanOrEqual(cache.count, 24)
                        XCTAssertLessThanOrEqual(cache.totalCost, 256)
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 24)
        XCTAssertLessThanOrEqual(cache.totalCost, cache.totalCostLimit)
        cache.totalCostLimit = 128
        XCTAssertLessThanOrEqual(cache.totalCost, 128)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    @MainActor
    func testHomeViewModelWarmCatalogMetadataConditionalRawPayloadNotModifiedAndStandardSkip() async throws {
        try await DiskSWRTestGate.shared.withLock { @MainActor in
            try await self.runWarmCatalogMetadataChecks()
        }
    }

    @MainActor
    private func runWarmCatalogMetadataChecks() async throws {
        await DiskSWRStore.clearAllAsync()
        CatalogBrowseMemoryCache.shared.clear()
        defer {
            CatalogBrowseMemoryCache.shared.clear()
        }

        final class WarmupMockClient: HomeClientProviding, CatalogClientProviding, @unchecked Sendable {
            struct State: Sendable {
                var homeResponse: TvHomeResponse
                var catalogResponses: [String: [ConditionalHTTPResult<TvCatalogResponse>]] = [:]
                var requestedCatalogETags: [(kind: String, etag: String?)] = []
            }
            let lock: Mutex<State>
            init(homeResponse: TvHomeResponse) {
                self.lock = Mutex(State(homeResponse: homeResponse))
            }
            func fetchHomeConditional(ifNoneMatch: String?) async throws -> HomeConditionalResult {
                .updated(payload: lock.withLock { $0.homeResponse }, etag: "\"home-1\"", rawPayloadData: Data())
            }
            func fetchCatalog(kind: String, genre: String?, sort: String, localOnly: Bool, unwatchedOnly: Bool, page: Int, limit: Int) async throws -> TvCatalogResponse {
                XCTFail("warmCatalogMetadataAfterHomePaintIfEligible must use fetchCatalogConditional")
                throw CancellationError()
            }
            func fetchCatalogConditional(
                kind: String,
                genre: String?,
                sort: String,
                localOnly: Bool,
                unwatchedOnly: Bool,
                page: Int,
                limit: Int,
                ifNoneMatch: String?
            ) async throws -> ConditionalHTTPResult<TvCatalogResponse> {
                lock.withLock { s in
                    s.requestedCatalogETags.append((kind, ifNoneMatch))
                    if var list = s.catalogResponses[kind], !list.isEmpty {
                        let first = list.removeFirst()
                        s.catalogResponses[kind] = list
                        return first
                    }
                    return .notModified
                }
            }
            func setWatchlist(listed: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?) async throws {}
            func setWatched(watched: Bool, mediaType: String, ids: TvMediaIds, title: String, year: Int?, season: Int?, episode: Int?) async throws {}
            func removeFromOngoing(mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws {}
            func removeFromList(rowId: String, mediaType: String, itemId: String?, ids: TvMediaIds, title: String?) async throws -> Bool { true }
        }

        @MainActor
        final class WarmupSession: TabSessionContext {
            var serverBaseURL: URL?
            var roomName = "Stua"
            var hardwareProfile = "hdr10-512"
            var homeRefreshNonce = 1
            var hasActivePlayback = false
            let client: WarmupMockClient
            init(host: String, client: WarmupMockClient) {
                self.serverBaseURL = URL(string: "http://\(host):8090")
                self.client = client
            }
            func makeHomeClient() -> (any HomeClientProviding)? { client }
            func makeCatalogClient() -> (any CatalogClientProviding)? { client }
            func makeLibraryClient() -> (any LibraryClientProviding)? { nil }
            func makeSearchClient() -> (any SearchClientProviding)? { nil }
            func notifyContentMutated() { homeRefreshNonce &+= 1 }
            func unpairDevice() {}
        }

        let host = "warmup-\(UUID().uuidString.lowercased()).local"
        let homeCard = TvMediaCard(itemId: "movie:tmdb:10", mediaType: "movie", ids: TvMediaIds(tmdb: 10), title: "Home Movie")
        let homeResp = TvHomeResponse(
            ok: true,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            rows: [TvShelfRow(rowId: "popular-movies", title: "Filmer", rowStyle: "poster", items: [homeCard])]
        )
        let movieCard = TvMediaCard(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club")
        let seriesCard = TvMediaCard(itemId: "series:tmdb:95396", mediaType: "series", ids: TvMediaIds(tmdb: 95396), title: "Severance")
        let movieResp = TvCatalogResponse(ok: true, mediaType: "movie", title: "Filmer", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 48, hasMore: false, items: [movieCard])
        let seriesResp = TvCatalogResponse(ok: true, mediaType: "series", title: "Serier", sort: "popular", localOnly: false, unwatchedOnly: false, page: 1, limit: 48, hasMore: false, items: [seriesCard])

        // Deliberately non-JSONEncoder formatting to prove verbatim rawPayloadData persistence on disk
        let customMovieRaw = Data("  { \"rawMarker\": \"verbatim-movie\", \"ok\": true }  ".utf8)
        let customSeriesRaw = Data("  { \"rawMarker\": \"verbatim-series\", \"ok\": true }  ".utf8)

        let client = WarmupMockClient(homeResponse: homeResp)
        client.lock.withLock { s in
            s.catalogResponses["movie"] = [
                .updated(payload: movieResp, etag: "\"w-mov-1\"", rawPayloadData: customMovieRaw),
                .notModified,
            ]
            s.catalogResponses["series"] = [
                .updated(payload: seriesResp, etag: "\"w-ser-1\"", rawPayloadData: customSeriesRaw),
                .notModified,
            ]
        }
        let session = WarmupSession(host: host, client: client)
        let vm = HomeViewModel(initialServerHost: host, initialRoomName: "Stua", initialHardwareProfile: "hdr10-512")
        await vm.handleActivation(session: session, isActiveTab: true)

        let gib: UInt64 = 1_073_741_824
        let standardProfile = DeviceMemoryProfile(physicalMemoryBytes: 4 * gib, activeProcessorCount: 6)
        let high2026Profile = DeviceMemoryProfile(physicalMemoryBytes: 8 * gib, activeProcessorCount: 6)

        // 1. Standard (4 GiB) profile must skip warmup completely
        await vm.warmCatalogMetadataAfterHomePaintIfEligible(
            session: session,
            isPreviewMode: false,
            delayNanoseconds: 0,
            memoryProfile: standardProfile
        )
        XCTAssertTrue(client.lock.withLock { $0.requestedCatalogETags.isEmpty })

        // 2. High2026 (8 GiB) profile warms both movie & series, stores ETag and rawPayloadData verbatim
        await vm.warmCatalogMetadataAfterHomePaintIfEligible(
            session: session,
            isPreviewMode: false,
            delayNanoseconds: 0,
            memoryProfile: high2026Profile
        )
        await DiskSWRStore.drainPendingWrites()

        let movieKey = CatalogBrowseViewModel.makeCacheKey(
            serverBaseURL: session.serverBaseURL,
            mediaType: "movie",
            roomName: "Stua",
            hardwareProfile: "hdr10-512"
        )
        let seriesKey = CatalogBrowseViewModel.makeCacheKey(
            serverBaseURL: session.serverBaseURL,
            mediaType: "series",
            roomName: "Stua",
            hardwareProfile: "hdr10-512"
        )
        XCTAssertEqual(CatalogBrowseMemoryCache.shared.snapshot(for: movieKey)?.etag, "\"w-mov-1\"")
        XCTAssertEqual(CatalogBrowseMemoryCache.shared.snapshot(for: seriesKey)?.etag, "\"w-ser-1\"")

        let cachesBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let swrDir = cachesBase.appendingPathComponent("LunaV2", isDirectory: true).appendingPathComponent("swr", isDirectory: true)
        let sanitizedHost = String(host.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
        let diskMovieFile = swrDir.appendingPathComponent("catalog-movies-\(sanitizedHost)-stua-hdr10-512.json")
        let diskMovieBytes = try Data(contentsOf: diskMovieFile)
        XCTAssertEqual(diskMovieBytes, customMovieRaw, "Warmup must persist rawPayloadData verbatim without MainActor JSONEncoder re-encoding")

        // 3. After nonce bump, subsequent warmup sends stored ETags and handles .notModified without losing items
        session.homeRefreshNonce = 2
        await vm.warmCatalogMetadataAfterHomePaintIfEligible(
            session: session,
            isPreviewMode: false,
            delayNanoseconds: 0,
            memoryProfile: high2026Profile
        )
        let requests = client.lock.withLock { $0.requestedCatalogETags }
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].etag, nil)
        XCTAssertEqual(requests[1].etag, nil)
        XCTAssertEqual(requests[2].etag, "\"w-mov-1\"")
        XCTAssertEqual(requests[3].etag, "\"w-ser-1\"")

        let refreshedMovie = CatalogBrowseMemoryCache.shared.snapshot(for: movieKey)
        XCTAssertEqual(refreshedMovie?.items.map(\.title), ["Fight Club"])
        XCTAssertEqual(refreshedMovie?.refreshNonce, 2)
        XCTAssertEqual(refreshedMovie?.etag, "\"w-mov-1\"")
        await DiskSWRStore.clearAllAsync()
    }

    func testUpgradeArtworkURLHero4KAndEdgeCases() throws {
        let cardURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/card/tmdb/a.jpg"))
        let stillURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/still/tmdb/a.jpg"))
        let backdropURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/backdrop/tmdb/a.jpg"))
        let mediaV2Backdrop = try XCTUnwrap(URL(string: "https://media.example.invalid/api/media/v2/img/backdrop/tmdb/a.jpg"))
        let legacyV1Card = try XCTUnwrap(URL(string: "http://192.0.2.10:8090/api/tv/v1/img/card/tmdb/a.jpg"))

        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(cardURL, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg"
        )
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(stillURL, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg"
        )
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(backdropURL, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg"
        )
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(mediaV2Backdrop, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/media/v2/img/backdrop4k/tmdb/a.jpg"
        )
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(legacyV1Card, target: .hero4K).absoluteString,
            "http://192.0.2.10:8090/api/tv/v1/img/backdrop4k/tmdb/a.jpg"
        )

        // Already-4K URL must never be downgraded across any target
        let backdrop4kURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(backdrop4kURL, target: .hero4K), backdrop4kURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(backdrop4kURL, target: .landscape2x), backdrop4kURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(backdrop4kURL, target: .poster2x), backdrop4kURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(backdrop4kURL, target: .preserve), backdrop4kURL)

        // Non-landscape variants remain untouched on .hero4K
        let posterURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/poster/tmdb/a.jpg"))
        let posterWebURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/posterWeb/tmdb/a.jpg"))
        let logoURL = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/logo/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(posterURL, target: .hero4K), posterURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(posterWebURL, target: .hero4K), posterWebURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(logoURL, target: .hero4K), logoURL)

        // Query parameters are preserved via path-anchored matching
        let queryBackdrop = try XCTUnwrap(URL(string: "https://media.example.invalid/api/tv/v2/img/backdrop/tmdb/a.jpg?v=2"))
        XCTAssertEqual(
            LunaCoreClient.upgradeArtworkURL(queryBackdrop, target: .hero4K).absoluteString,
            "https://media.example.invalid/api/tv/v2/img/backdrop4k/tmdb/a.jpg?v=2"
        )

        // External URLs & proxy URLs with /api/tv/v2/img/ inside query remain unchanged
        let extURL = try XCTUnwrap(URL(string: "https://cdn.example.net/card/a.jpg"))
        let proxyURL = try XCTUnwrap(URL(string: "https://proxy.example.net/fetch?url=/api/tv/v2/img/card/tmdb/a.jpg"))
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(extURL, target: .hero4K), extURL)
        XCTAssertEqual(LunaCoreClient.upgradeArtworkURL(proxyURL, target: .hero4K), proxyURL)
    }

    func testResolveArtworkURLAndBuildAbsoluteURLCaseInsensitiveSchemes() throws {
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "https://media.example.invalid:8920")),
            deviceID: "dev-scheme",
            deviceToken: "tok-scheme",
            roomName: "Stua",
            hardwareProfile: "dv-fel-714",
            allowSelfSignedLanTLS: false
        )

        let upperHTTPS = try XCTUnwrap(client.resolveArtworkURL("HTTPS://image.tmdb.org/t/p/w342/poster.jpg", target: .poster2x))
        XCTAssertEqual(upperHTTPS.scheme?.lowercased(), "https")
        XCTAssertEqual(upperHTTPS.host, "image.tmdb.org")
        XCTAssertEqual(upperHTTPS.path, "/t/p/w780/poster.jpg")
        XCTAssertFalse(upperHTTPS.absoluteString.contains("media.example.invalid"))

        let upperHTTP = try XCTUnwrap(client.resolveArtworkURL("HTTP://cdn.example.net/artwork?w=320", target: .landscape2x))
        XCTAssertEqual(upperHTTP.scheme?.lowercased(), "http")
        XCTAssertEqual(upperHTTP.host, "cdn.example.net")
        XCTAssertTrue(upperHTTP.query?.contains("w=1280") == true)

        let mixedScheme = try XCTUnwrap(
            client.resolveArtworkURL("HtTpS://media.example.invalid:8920/api/tv/v2/img/card/tmdb/hero.jpg", target: .hero4K)
        )
        XCTAssertEqual(mixedScheme.host, "media.example.invalid")
        XCTAssertEqual(mixedScheme.port, 8920)
        XCTAssertEqual(mixedScheme.path, "/api/tv/v2/img/backdrop4k/tmdb/hero.jpg")

        let directBuild = try XCTUnwrap(client.buildAbsoluteURL("HTTPS://cdn.example.net/stream.mkv"))
        XCTAssertEqual(directBuild.scheme?.lowercased(), "https")
        XCTAssertEqual(directBuild.host, "cdn.example.net")

        let nestedRelative = try XCTUnwrap(client.buildAbsoluteURL("api/tv/v2/http://nested"))
        XCTAssertEqual(nestedRelative.absoluteString, "https://media.example.invalid:8920/api/tv/v2/http://nested")
    }
}
