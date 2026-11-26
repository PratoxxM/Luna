import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import LunaCore

@MainActor
private final class OverflowMockDiscovery: ServerDiscoveryProviding {
    var servers: [DiscoveredLunaCoreServer] = []
    var isSearching: Bool = false
    func start() { isSearching = true }
    func stop() { isSearching = false }
}

private final class OverflowMockPairingClient: PairingClientProviding, @unchecked Sendable {
    let pollIntervalSeconds: Int?
    let requested = Mutex<Bool>(false)

    init(pollIntervalSeconds: Int?) {
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    func requestPairingCode(
        model: String,
        osVersion: String,
        appVersion: String,
        capabilities: TvDeviceCapabilities
    ) async throws -> TvPairingRequestResponse {
        requested.withLock { $0 = true }
        return TvPairingRequestResponse(
            ok: true,
            pairingCode: "482910",
            displayCode: "482 910",
            expiresAt: "2026-11-26T04:00:00Z",
            pollIntervalSeconds: pollIntervalSeconds
        )
    }

    func pollPairingCode(_ code: String) async throws -> (httpStatus: Int, response: TvPairingPollResponse) {
        (200, TvPairingPollResponse(ok: true, status: "pending", deviceToken: nil, device: nil, error: nil))
    }
}

@MainActor
private final class OverflowMockPairingSession: PairingSessionContext {
    let deviceMetadata = PairingDeviceMetadata(model: "AppleTV14,1", osVersion: "tvOS 26.0", appVersion: "3.0.0")
    let client: OverflowMockPairingClient

    init(client: OverflowMockPairingClient) {
        self.client = client
    }

    func makePairingClient(baseURL: URL) -> (any PairingClientProviding)? { client }
    func completePairing(baseURL: URL, token: String, pairedDevice: TvPairedDeviceInfo, localHostnameURL: URL?) {}
}

@Suite("Etappe 6 Numeric & Overflow Hardening")
struct Etappe6NumericOverflowTests {
    @Test("TvProbeChapter decodes Int.max and Int.min index without title overflow")
    func tvProbeChapterIndexOverflowSafety() throws {
        let maxData = Data(#"{"index":9223372036854775807}"#.utf8)
        let maxChapter = try JSONDecoder().decode(TvProbeChapter.self, from: maxData)
        #expect(maxChapter.index == Int.max)
        #expect(maxChapter.title == "Kapittel 9223372036854775808")

        let minData = Data(#"{"index":-9223372036854775808}"#.utf8)
        let minChapter = try JSONDecoder().decode(TvProbeChapter.self, from: minData)
        #expect(minChapter.index == Int.min)
        #expect(minChapter.title == "Kapittel -9223372036854775807")

        let normalData = Data(#"{"index":0}"#.utf8)
        let normalChapter = try JSONDecoder().decode(TvProbeChapter.self, from: normalData)
        #expect(normalChapter.title == "Kapittel 1")
    }

    @Test("PlayerTimelinePolicy buckets clamp extreme finite, greatestFiniteMagnitude, infinity & NaN")
    func timelinePolicyBucketsOverflowSafety() {
        #expect(PlayerTimelinePolicy.timeBucket(1e30) == Int.max)
        #expect(PlayerTimelinePolicy.bufferBucket(1e30) == Int.max)
        #expect(PlayerTimelinePolicy.finishTimeBucket(1e30) == Int.max)

        #expect(PlayerTimelinePolicy.timeBucket(.greatestFiniteMagnitude) == Int.max)
        #expect(PlayerTimelinePolicy.bufferBucket(.greatestFiniteMagnitude) == Int.max)
        #expect(PlayerTimelinePolicy.finishTimeBucket(.greatestFiniteMagnitude) == Int.max)

        #expect(PlayerTimelinePolicy.timeBucket(.nan) == -1)
        #expect(PlayerTimelinePolicy.bufferBucket(.infinity) == -1)
        #expect(PlayerTimelinePolicy.finishTimeBucket(-1.0) == -1)

        #expect(PlayerTimelinePolicy.timeBucket(100.4) == 200)
        #expect(PlayerTimelinePolicy.bufferBucket(9.9) == 4)
        #expect(PlayerTimelinePolicy.finishTimeBucket(59.9) == 5)
    }

    @Test("LunaCoreSessionPool.probeSession handles 1e30, NaN, infinity & negative timeouts without trapping")
    func sessionPoolProbeTimeoutBounds() throws {
        let host = "overflow-pool-\(UUID().uuidString.lowercased()).invalid"
        let baseURL = try #require(URL(string: "https://\(host):8920"))

        let s1 = LunaCoreSessionPool.shared.probeSession(for: baseURL, allowSelfSignedLanTLS: false, timeoutSeconds: 1e30)
        let s2 = LunaCoreSessionPool.shared.probeSession(for: baseURL, allowSelfSignedLanTLS: false, timeoutSeconds: .nan)
        let s3 = LunaCoreSessionPool.shared.probeSession(for: baseURL, allowSelfSignedLanTLS: false, timeoutSeconds: .infinity)
        let s4 = LunaCoreSessionPool.shared.probeSession(for: baseURL, allowSelfSignedLanTLS: false, timeoutSeconds: -5.0)

        #expect(s1.configuration.timeoutIntervalForRequest == 3600.0)
        #expect(s2.configuration.timeoutIntervalForRequest == 4.0)
        #expect(s3.configuration.timeoutIntervalForRequest == 4.0)
        #expect(s4.configuration.timeoutIntervalForRequest == 0.1)
    }

    @Test("MediaDetailViewModel.heroPrimaryPlayTitle guards extreme & non-finite watch progress")
    @MainActor
    func detailViewModelHeroTitleOverflowSafety() {
        let vm = MediaDetailViewModel(mediaType: "movie", itemId: "movie:tmdb:1", initialTitle: "Test")
        let extremeMovie = TvItemDetail(
            itemId: "movie:tmdb:1",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 1),
            title: "Test",
            inWatchlist: false,
            watched: false,
            progress: TvWatchProgress(positionSeconds: 40, durationSeconds: 1e30, percent: 50)
        )
        #expect(vm.heroPrimaryPlayTitle(extremeMovie) == "Fortsett")

        let infMovie = TvItemDetail(
            itemId: "movie:tmdb:2",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 2),
            title: "Test",
            inWatchlist: false,
            watched: false,
            progress: TvWatchProgress(positionSeconds: 40, durationSeconds: .infinity, percent: 50)
        )
        #expect(vm.heroPrimaryPlayTitle(infMovie) == "Fortsett")

        let normalMovie = TvItemDetail(
            itemId: "movie:tmdb:3",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 3),
            title: "Test",
            inWatchlist: false,
            watched: false,
            progress: TvWatchProgress(positionSeconds: 600, durationSeconds: 5400, percent: 11)
        )
        #expect(vm.heroPrimaryPlayTitle(normalMovie) == "Fortsett · 1 t 20 min igjen")
    }

    @Test("PairingViewModel clamps Int.max & Int.min pollIntervalSeconds without UInt64 overflow")
    @MainActor
    func pairingViewModelIntervalOverflowSafety() async throws {
        #expect(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.max, multiplier: 1) == 300_000_000_000)
        #expect(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.max, multiplier: 2) == 600_000_000_000)
        #expect(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: Int.min, multiplier: 1) == 2_000_000_000)
        #expect(PairingViewModel.pollSleepNanoseconds(pollIntervalSeconds: nil, multiplier: 1) == 3_000_000_000)

        let discovery = OverflowMockDiscovery()
        let client = OverflowMockPairingClient(pollIntervalSeconds: Int.max)
        let session = OverflowMockPairingSession(client: client)
        let vm = PairingViewModel(discovery: discovery)
        let url = try #require(URL(string: "https://example.invalid:8920"))

        let task = vm.startPairing(against: url, session: session, pollIntervalOverrideNanoseconds: nil)
        for _ in 0..<50 {
            if vm.pairingInfo != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(vm.pairingInfo?.pollIntervalSeconds == Int.max)
        vm.stopDiscovery()
        await task.value
    }

    @Test("PlaybackTrackIntent.scoreAudio & PlaybackSyncTimingPolicy handle Int.max and Int.min safely")
    func playbackTrackIntentExtremeChannelCounts() {
        let intentMax = PlaybackTrackIntent(
            audioIntent: .matching(languageCode: "eng", isCommentary: false, prefersObjectAudio: false, preferredChannels: 6),
            subtitleIntent: .automatic
        )
        let tracksMax = [
            PlaybackAudioTrackDescriptor(id: 1, language: "eng", channels: Int.max),
            PlaybackAudioTrackDescriptor(id: 2, language: "eng", channels: 6),
        ]
        let resMax = intentMax.resolve(audioTracks: tracksMax, currentActiveAudioID: nil, subtitleTracks: [], smartNordicRuleEnabled: false)
        #expect(resMax.selectedAudioTrackID == 2)

        let tracksMin = [
            PlaybackAudioTrackDescriptor(id: 1, language: "eng", channels: Int.min),
            PlaybackAudioTrackDescriptor(id: 2, language: "eng", channels: 6),
        ]
        let resMin = intentMax.resolve(audioTracks: tracksMin, currentActiveAudioID: nil, subtitleTracks: [], smartNordicRuleEnabled: false)
        #expect(resMin.selectedAudioTrackID == 2)

        let intentExtremePref = PlaybackTrackIntent(
            audioIntent: .matching(languageCode: "eng", isCommentary: false, prefersObjectAudio: false, preferredChannels: Int.max),
            subtitleIntent: .automatic
        )
        let tracksBothExtreme = [
            PlaybackAudioTrackDescriptor(id: 10, language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 11, language: "eng", channels: Int.max),
        ]
        let resExtremePref = intentExtremePref.resolve(audioTracks: tracksBothExtreme, currentActiveAudioID: nil, subtitleTracks: [], smartNordicRuleEnabled: false)
        #expect(resExtremePref.selectedAudioTrackID == 11)

        #expect(PlaybackSyncTimingPolicy.formatSignedDelayMs(Int.min) == "−9223372036854775808 ms")
    }

    @Test("ScrollTopSample.capture handles 1e30, infinity, negative & NaN offsets safely")
    func scrollTopSampleExtremeOffsets() {
        let extreme = ScrollTopSample.capture(scrolledOffsetY: 1e30)
        #expect(extreme.zone == .scrolledDown)
        #expect(extreme.downwardBucket == Int.max)

        let infinite = ScrollTopSample.capture(scrolledOffsetY: .infinity)
        #expect(infinite.zone == .scrolledDown)
        #expect(infinite.downwardBucket == Int.max)

        let nanSample = ScrollTopSample.capture(scrolledOffsetY: .nan)
        #expect(nanSample.zone == .midBand)
        #expect(nanSample.downwardBucket == 0)

        let normal = ScrollTopSample.capture(scrolledOffsetY: 96)
        #expect(normal.zone == .scrolledDown)
        #expect(normal.downwardBucket == 2)
    }

    @Test("LunaCoreClient.buildRowRequestPath guards Int.max offset division page + 1 overflow")
    func buildRowRequestPathIntMaxOffset() {
        let maxPath = LunaCoreClient.buildRowRequestPath(pathOrRowId: "/api/tv/v2/catalog/movies", offset: Int.max, limit: 1)
        #expect(maxPath.contains("page=\(Int.max)"))
        #expect(maxPath.contains("limit=1"))

        let normalPath = LunaCoreClient.buildRowRequestPath(pathOrRowId: "/api/tv/v2/catalog/movies", offset: 48, limit: 24)
        #expect(normalPath.contains("page=3"))
        #expect(normalPath.contains("limit=24"))
    }

    @Test("LunaCopy.plural and localized count helpers handle Int.min without SIGILL")
    func lunaCopyPluralIntMinSafety() {
        #expect(LunaCopy.plural(Int.min, "treff", "treff") == "\(Int.min) treff")
        #expect(LunaCopy.plural(-1, "treff", "treff") == "-1 treff")
        #expect(LunaCopy.plural(1, "episode", "episoder") == "1 episode")
        #expect(LunaCopy.plural(0, "sesong", "sesonger") == "0 sesonger")

        #expect(LunaCopy.searchHits(Int.min).contains("\(Int.min)"))
        #expect(LunaCopy.episodesCount(Int.min).contains("\(Int.min)"))
        #expect(LunaCopy.seasonsCount(Int.min).contains("\(Int.min)"))
        #expect(LunaCopy.mediaFilesCount(Int.min).contains("\(Int.min)"))
    }

    @Test("PlaybackChapter.mergeRaw maintains strict weak ordering when .nan appears in large chapter arrays")
    func playbackChapterMergeRawNaNSortingSafety() {
        var engineChapters: [RawEngineChapter] = []
        var probeChapters: [TvProbeChapter] = []
        for idx in 0..<45 {
            let start: Double = (idx % 5 == 0) ? .nan : Double((45 - idx) * 30)
            engineChapters.append(RawEngineChapter(
                id: 100 - idx,
                name: "Kapittel \(idx)",
                startSeconds: start,
                durationSeconds: 20
            ))
            probeChapters.append(TvProbeChapter(
                index: idx,
                idString: "p-\(idx)",
                title: idx == 2 ? "Intro" : "Kapittel \(idx)",
                startSeconds: (idx % 7 == 0) ? .nan : Double((45 - idx) * 30),
                endSeconds: Double((45 - idx) * 30) + 25,
                kind: idx == 2 ? "intro" : nil
            ))
        }

        let mergedWithEngine = PlaybackChapter.mergeRaw(
            probeChapters: probeChapters,
            engineChapters: engineChapters,
            mediaDuration: 2000
        )
        #expect(mergedWithEngine.count >= 45)
        #expect(mergedWithEngine.allSatisfy { $0.startSeconds.isFinite && $0.startSeconds >= 0 })

        let mergedProbesOnly = PlaybackChapter.mergeRaw(
            probeChapters: probeChapters,
            engineChapters: [],
            mediaDuration: 2000
        )
        #expect(mergedProbesOnly.count == 45)
        #expect(mergedProbesOnly.allSatisfy { $0.startSeconds.isFinite && $0.startSeconds >= 0 })
    }
}
