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
        XCTAssertEqual(SideloadSafeStorage.currentAppVersionString(), "2.12.0")
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
            "streamUrl": "/api/tv/v1/stream/tvs_next85/0123456789abcdef0123456789abcdef/Severance.S01E02.mkv",
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
}
