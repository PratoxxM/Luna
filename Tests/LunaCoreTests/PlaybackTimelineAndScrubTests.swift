import Foundation
import XCTest
@testable import LunaCore

final class PlaybackTimelineAndScrubTests: XCTestCase {
    private static func makeSession(source: String, tier: String?) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: "sess-1",
            streamToken: "tok-stream-1234",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            item: TvPlaybackItemContext(itemId: "movie:tmdb:550", mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: "Fight Club"),
            selectedCandidate: TvCandidateInfo(
                candidateId: "cand-1", displayHeadline: "4K", releaseTitle: "Rel", source: source, tier: tier,
                resolution: nil, videoRangeType: nil, dvProfile: nil, dvEnhancementLayer: nil,
                audioCodec: nil, sizeBytes: nil, tvScore: nil, isActive: false,
                explanationChips: nil, releaseGroup: nil, isNorwegian: false
            ),
            stream: TvStreamEndpoint(url: "/api/tv/v2/stream/sess-1/tok/video.mkv"),
            aetherConfig: TvAetherConfig(preferDualLayerDolbyVision: true, dolbyVisionHandling: "automatic", matchContentEnabled: true, audioBridgeMode: "lossless")
        )
    }

    // MARK: - PlayerTimelinePolicy Buckets, Overflow Bounds, Finish Time & Menu Exit Ladder

    func testTimelinePolicyBucketsOverflowFinishTimeAndMenuExitLadder() throws {
        XCTAssertEqual(PlayerTimelinePolicy.playheadBucketSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(PlayerTimelinePolicy.bufferBucketSeconds, 2.0, accuracy: 0.001)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucketSeconds, 10.0, accuracy: 0.001)

        for bad in [-0.001, -42.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(PlayerTimelinePolicy.timeBucket(bad), -1)
            XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(bad), -1)
            XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(bad), -1)
        }
        for extreme in [1e30, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(PlayerTimelinePolicy.timeBucket(extreme), Int.max)
            XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(extreme), Int.max)
            XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(extreme), Int.max)
        }

        XCTAssertEqual(PlayerTimelinePolicy.timeBucket(0.499), 0)
        XCTAssertEqual(PlayerTimelinePolicy.timeBucket(0.50), 1)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(10.50), 21)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(19.9), 9)
        XCTAssertEqual(TimelineClockBucketer.finishTimeBucket(3649.0), 364)

        // Norwegian 24-hour colon formatting & midnight rollover
        let tz = try XCTUnwrap(TimeZone(secondsFromGMT: 3600))
        var usCal = Calendar(identifier: .gregorian)
        usCal.locale = Locale(identifier: "en_US")
        usCal.timeZone = tz
        let now = try XCTUnwrap(DateComponents(calendar: usCal, timeZone: tz, year: 2026, month: 11, day: 23, hour: 20, minute: 5, second: 0).date)

        XCTAssertNil(PlayerTimelinePolicy.formatFinishTimeText(currentSeconds: 0, durationSeconds: 30, now: now, calendar: usCal))
        XCTAssertNil(PlayerTimelinePolicy.formatFinishTimeText(currentSeconds: 0, durationSeconds: .nan, now: now, calendar: usCal))
        XCTAssertEqual(PlayerTimelinePolicy.formatFinishTimeText(currentSeconds: 1800, durationSeconds: 7200, now: now, calendar: usCal), "Slutter kl. 21:35")
        XCTAssertEqual(PlayerTimelinePolicy.formatFinishTimeText(currentSeconds: 0, durationSeconds: 4 * 3600, now: now, calendar: usCal), "Slutter kl. 00:05")
        XCTAssertEqual(PlayerTimelinePolicy.formatFinishTimeText(currentSeconds: -15, durationSeconds: 3600, now: now, calendar: usCal), "Slutter kl. 21:05")

        // All 6 steps of Menu exit resolution ladder
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: true, isScrubbing: true, hasSeriesPrompt: true, isHUDResting: false, isQuickActionsModeActive: true, showBottomBar: true, isPlaying: true), .closeQuickPanel)
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: true, hasSeriesPrompt: true, isHUDResting: false, isQuickActionsModeActive: false, showBottomBar: true, isPlaying: false), .cancelScrubbing)
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: true, isHUDResting: false, isQuickActionsModeActive: true, showBottomBar: true, isPlaying: true), .dismissSeriesPrompt)
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: true, isHUDResting: true, isQuickActionsModeActive: false, showBottomBar: false, isPlaying: false), .closePlayer)
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: false, isHUDResting: false, isQuickActionsModeActive: true, showBottomBar: true, isPlaying: true), .releaseQuickActionsFocus(hideBottomBar: true))
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: false, isHUDResting: false, isQuickActionsModeActive: true, showBottomBar: true, isPlaying: false), .releaseQuickActionsFocus(hideBottomBar: false))
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: false, isHUDResting: false, isQuickActionsModeActive: false, showBottomBar: true, isPlaying: true), .hideBottomBar)
        XCTAssertEqual(PlayerTimelinePolicy.resolveExitAction(hasActiveQuickPanel: false, isScrubbing: false, hasSeriesPrompt: false, isHUDResting: false, isQuickActionsModeActive: false, showBottomBar: true, isPlaying: false), .closePlayer)
    }

    // MARK: - RemoteScrubMath Activation, 3-Zone Curve, Reversal & Ring Hold

    func testRemoteScrubMathActivationCurvesSmoothingAndRingHold() {
        XCTAssertFalse(RemoteScrubMath.shouldActivateTouchScrub(dx: 220, dy: 0, isPlaying: true, isSelectPressed: false, secondsSinceDiscreteClick: nil))
        XCTAssertFalse(RemoteScrubMath.shouldActivateTouchScrub(dx: 19.5, dy: 0, isPlaying: false, isSelectPressed: false, secondsSinceDiscreteClick: nil))
        XCTAssertTrue(RemoteScrubMath.shouldActivateTouchScrub(dx: -20.0, dy: 10.0, isPlaying: false, isSelectPressed: false, secondsSinceDiscreteClick: nil))
        XCTAssertFalse(RemoteScrubMath.shouldActivateTouchScrub(dx: 30.0, dy: 25.0, isPlaying: false, isSelectPressed: false, secondsSinceDiscreteClick: nil))
        XCTAssertFalse(RemoteScrubMath.shouldActivateTouchScrub(dx: 80, dy: 0, isPlaying: false, isSelectPressed: true, secondsSinceDiscreteClick: nil))
        XCTAssertFalse(RemoteScrubMath.shouldActivateTouchScrub(dx: 80, dy: 0, isPlaying: false, isSelectPressed: false, secondsSinceDiscreteClick: 0.12))
        XCTAssertTrue(RemoteScrubMath.shouldActivateTouchScrub(dx: 80, dy: 0, isPlaying: false, isSelectPressed: false, secondsSinceDiscreteClick: 0.19))

        XCTAssertEqual(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 2700, speedNorm: 0.4), 40.5, accuracy: 0.01)
        XCTAssertEqual(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 0.4), 90.0, accuracy: 0.01)
        XCTAssertEqual(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 2700, speedNorm: 2.4), 432.0, accuracy: 0.01)
        XCTAssertEqual(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 2.4), 1620.0, accuracy: 0.01)
        XCTAssertEqual(RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 4.0), 3300.0, accuracy: 0.01)

        let reverseStep = RemoteScrubMath.incrementalStepSeconds(stepDxPoints: -1.5, durationSeconds: 2700, speedNorm: 0.3)
        XCTAssertEqual(reverseStep, (-1.5 / 260.0) * 40.5, accuracy: 0.001)

        let s1 = RemoteScrubMath.smoothedSpeedNorm(previous: 0.0, velocityXPointsPerSecond: 1040.0)
        let s2 = RemoteScrubMath.smoothedSpeedNorm(previous: s1, velocityXPointsPerSecond: 1040.0)
        XCTAssertEqual(s1, 1.4, accuracy: 0.001)
        XCTAssertEqual(s2, 2.31, accuracy: 0.001)

        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 1.09), 30.0)
        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 1.5), 120.0)
        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 3.0), 300.0)
    }

    // MARK: - PlaybackTrickplayPolicy & BackgroundScrubPreviewPolicy

    func testPlaybackTrickplayAndBackgroundScrubPreviewPolicies() {
        XCTAssertEqual(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 14.9, durationSeconds: 3600), 10)
        XCTAssertEqual(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 3599.9, durationSeconds: 3600), 3595)
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: -1, durationSeconds: 3600))
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: .nan, durationSeconds: 3600))
        XCTAssertNil(PlaybackTrickplayPolicy.quantizedBucketSeconds(for: 1e30, durationSeconds: 0))

        XCTAssertFalse(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(session: Self.makeSession(source: "archive", tier: "archive")))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(session: Self.makeSession(source: "infinidysk", tier: "vfs")))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(session: Self.makeSession(source: "easynews", tier: "remote")))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(session: Self.makeSession(source: "nvme", tier: "nvme")))

        XCTAssertTrue(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 404, errorCode: "archive_spindown_protected"))
        XCTAssertTrue(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 410, errorCode: "session_ended"))
        XCTAssertFalse(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 404, errorCode: "scrub_frame_unavailable"))
        XCTAssertFalse(PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(statusCode: 503, errorCode: "trickplay_busy"))

        let highFloor = UInt64(1_500 * 1024 * 1024)
        let plentyRAM = UInt64(2_200 * 1024 * 1024)
        XCTAssertTrue(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026, availableMemoryBytes: plentyRAM, playbackMemoryShedFloorBytes: highFloor,
                source: "nvme", tier: "nvme", supportsByteRanges: true, preferDualLayerDolbyVision: false,
                dvProfile: 8, dvEnhancementLayer: nil, requiresSoftwareVideoDecode: false, serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .standard, availableMemoryBytes: plentyRAM, playbackMemoryShedFloorBytes: 900 * 1024 * 1024,
                source: "nvme", tier: "nvme", supportsByteRanges: true, preferDualLayerDolbyVision: false,
                dvProfile: nil, dvEnhancementLayer: nil, requiresSoftwareVideoDecode: false, serverConfigured: true
            )
        )
        for badTier in ["archive", "vfs", "infinidysk", "easynews", "usenet", "remote", ""] {
            XCTAssertFalse(
                BackgroundScrubPreviewPolicy.shouldGenerate(
                    memoryTier: .high2026, availableMemoryBytes: plentyRAM, playbackMemoryShedFloorBytes: highFloor,
                    source: badTier, tier: badTier, supportsByteRanges: true, preferDualLayerDolbyVision: false,
                    dvProfile: nil, dvEnhancementLayer: nil, requiresSoftwareVideoDecode: false, serverConfigured: true
                )
            )
        }
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026, availableMemoryBytes: plentyRAM, playbackMemoryShedFloorBytes: highFloor,
                source: "nvme", tier: "nvme", supportsByteRanges: true, preferDualLayerDolbyVision: true,
                dvProfile: 7, dvEnhancementLayer: "FEL", requiresSoftwareVideoDecode: false, serverConfigured: true
            )
        )
    }
}
