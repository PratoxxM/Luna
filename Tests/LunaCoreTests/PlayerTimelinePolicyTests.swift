import Foundation
import XCTest
@testable import LunaCore

final class PlayerTimelinePolicyTests: XCTestCase {
    func testPlayheadBufferAndTenSecondFinishTimeBucketsIncludingInvalidInputs() {
        XCTAssertEqual(PlayerTimelinePolicy.playheadBucketSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(PlayerTimelinePolicy.bufferBucketSeconds, 2.0, accuracy: 0.001)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucketSeconds, 10.0, accuracy: 0.001)

        // Invalid / non-finite / negative values return -1 across all three bucketers
        for bad in [-0.001, -42.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(PlayerTimelinePolicy.timeBucket(bad), -1)
            XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(bad), -1)
            XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(bad), -1)
        }

        // 0.5 s playhead buckets + TimelineClockBucketer alias compatibility
        XCTAssertEqual(PlayerTimelinePolicy.timeBucket(0.0), 0)
        XCTAssertEqual(PlayerTimelinePolicy.timeBucket(0.499), 0)
        XCTAssertEqual(PlayerTimelinePolicy.timeBucket(0.50), 1)
        XCTAssertEqual(TimelineClockBucketer.timeBucket(10.50), 21)

        // 2.0 s buffer buckets
        XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(0.0), 0)
        XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(1.999), 0)
        XCTAssertEqual(PlayerTimelinePolicy.bufferBucket(2.00), 1)
        XCTAssertEqual(TimelineClockBucketer.bufferBucket(19.9), 9)

        // 10.0 s finish-time buckets (0.1 Hz steady-state)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(0.0), 0)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(9.999), 0)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(10.0), 1)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(59.99), 5)
        XCTAssertEqual(PlayerTimelinePolicy.finishTimeBucket(60.0), 6)
        XCTAssertEqual(TimelineClockBucketer.finishTimeBucket(3649.0), 364)
    }

    func testNorwegian24HourColonFinishTimeFormattingAndScrubUpdates() throws {
        let tz = try XCTUnwrap(TimeZone(secondsFromGMT: 3600))
        var usTwelveHourCalendar = Calendar(identifier: .gregorian)
        usTwelveHourCalendar.locale = Locale(identifier: "en_US")
        usTwelveHourCalendar.timeZone = tz

        // 2026-11-23 20:05:00 +01:00
        let baseComponents = DateComponents(
            calendar: usTwelveHourCalendar,
            timeZone: tz,
            year: 2026,
            month: 11,
            day: 23,
            hour: 20,
            minute: 5,
            second: 0
        )
        let now = try XCTUnwrap(baseComponents.date)

        // Short clips (<= 30 s) or invalid durations return nil
        XCTAssertNil(
            PlayerTimelinePolicy.formatFinishTimeText(
                currentSeconds: 0,
                durationSeconds: 30,
                now: now,
                calendar: usTwelveHourCalendar
            )
        )
        XCTAssertNil(
            PlayerTimelinePolicy.formatFinishTimeText(
                currentSeconds: 0,
                durationSeconds: .nan,
                now: now,
                calendar: usTwelveHourCalendar
            )
        )
        XCTAssertNil(
            PlayerTimelinePolicy.formatFinishTimeText(
                currentSeconds: 0,
                durationSeconds: .infinity,
                now: now,
                calendar: usTwelveHourCalendar
            )
        )

        // 2-hour movie (7200 s) at 1800 s (90 min left) -> 21:35 with colon even on en_US calendar
        let atThirtyMin = PlayerTimelinePolicy.formatFinishTimeText(
            currentSeconds: 1800,
            durationSeconds: 7200,
            now: now,
            calendar: usTwelveHourCalendar
        )
        XCTAssertEqual(atThirtyMin, "Slutter kl. 21:35")

        // Scrubbing +30 min forward to 3600 s (60 min left) updates finish time to 21:05
        let afterScrubForward = PlayerTimelinePolicy.formatFinishTimeText(
            currentSeconds: 3600,
            durationSeconds: 7200,
            now: now,
            calendar: usTwelveHourCalendar
        )
        XCTAssertEqual(afterScrubForward, "Slutter kl. 21:05")

        // Midnight rollover pads single-digit hours & minutes ("Slutter kl. 00:05")
        let midnightRollover = PlayerTimelinePolicy.formatFinishTimeText(
            currentSeconds: 0,
            durationSeconds: 4 * 3600,
            now: now,
            calendar: usTwelveHourCalendar
        )
        XCTAssertEqual(midnightRollover, "Slutter kl. 00:05")

        // Negative or NaN playhead clamps safely to 0 without crashing
        let negativePlayhead = PlayerTimelinePolicy.formatFinishTimeText(
            currentSeconds: -15,
            durationSeconds: 3600,
            now: now,
            calendar: usTwelveHourCalendar
        )
        XCTAssertEqual(negativePlayhead, "Slutter kl. 21:05")
    }

    func testAllSixStepsOfMenuExitResolutionLadder() {
        // Step 1: Open quick panel always wins
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: true,
                isScrubbing: true,
                hasSeriesPrompt: true,
                isHUDResting: false,
                isQuickActionsModeActive: true,
                showBottomBar: true,
                isPlaying: true
            ),
            .closeQuickPanel
        )

        // Step 2: Active touch or ring-hold scrubbing cancels scrub without closing player
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: true,
                hasSeriesPrompt: true,
                isHUDResting: false,
                isQuickActionsModeActive: false,
                showBottomBar: true,
                isPlaying: false
            ),
            .cancelScrubbing
        )

        // Step 3a: Visible series continuity prompt dismisses prompt first
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: true,
                isHUDResting: false,
                isQuickActionsModeActive: true,
                showBottomBar: true,
                isPlaying: true
            ),
            .dismissSeriesPrompt
        )

        // Step 3b: Hidden series prompt during 12s OLED pause rest does NOT trap Menu
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: true,
                isHUDResting: true,
                isQuickActionsModeActive: false,
                showBottomBar: false,
                isPlaying: false
            ),
            .closePlayer
        )

        // Step 4a: Focused quick-action pills while playing -> release focus AND hide OSD
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: false,
                isHUDResting: false,
                isQuickActionsModeActive: true,
                showBottomBar: true,
                isPlaying: true
            ),
            .releaseQuickActionsFocus(hideBottomBar: true)
        )

        // Step 4b: Focused quick-action pills while paused -> release focus to scrub-ready canvas, keep OSD visible
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: false,
                isHUDResting: false,
                isQuickActionsModeActive: true,
                showBottomBar: true,
                isPlaying: false
            ),
            .releaseQuickActionsFocus(hideBottomBar: false)
        )

        // Step 5a: Visible bottom OSD while playing (canvas focused) -> hide OSD without exiting
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: false,
                isHUDResting: false,
                isQuickActionsModeActive: false,
                showBottomBar: true,
                isPlaying: true
            ),
            .hideBottomBar
        )

        // Step 5b / Step 6: Resting canvas focus while paused (even with paused OSD shown) -> close player
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: false,
                isHUDResting: false,
                isQuickActionsModeActive: false,
                showBottomBar: true,
                isPlaying: false
            ),
            .closePlayer
        )

        // Step 6: Hidden OSD during active playback -> close player
        XCTAssertEqual(
            PlayerTimelinePolicy.resolveExitAction(
                hasActiveQuickPanel: false,
                isScrubbing: false,
                hasSeriesPrompt: false,
                isHUDResting: false,
                isQuickActionsModeActive: false,
                showBottomBar: false,
                isPlaying: true
            ),
            .closePlayer
        )
    }
}
