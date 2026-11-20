import Foundation
import XCTest
@testable import LunaCore

final class RemoteScrubMathTests: XCTestCase {
    func testPausedOnlyActivationBreakawayAndClickSuppression() {
        // Active playback never enters touch-surface scrubbing regardless of drag distance
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 220,
                dy: 0,
                isPlaying: true,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )

        // While paused, below 20 pt breakaway does not activate
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 19.5,
                dy: 0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )

        // At or above 20 pt with valid horizontal 1.35:1 axis ratio activates
        XCTAssertTrue(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: -20.0,
                dy: 10.0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )

        // Steep diagonal fails 1.35 axis lock
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 30.0,
                dy: 25.0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: nil
            )
        )

        // Holding Select or within 180 ms of discrete click suppresses pan activation
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 80,
                dy: 0,
                isPlaying: false,
                isSelectPressed: true,
                secondsSinceDiscreteClick: nil
            )
        )
        XCTAssertFalse(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 80,
                dy: 0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: 0.12
            )
        )
        XCTAssertTrue(
            RemoteScrubMath.shouldActivateTouchScrub(
                dx: 80,
                dy: 0,
                isPlaying: false,
                isSelectPressed: false,
                secondsSinceDiscreteClick: 0.19
            )
        )
    }

    func testThreeZoneDurationAdaptiveCurveAndZeroReversalDeadzone() {
        // Zone 1 precision (45-min episode -> 40.5 s per swipe, 3h movie -> 90 s per swipe)
        XCTAssertEqual(
            RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 2700, speedNorm: 0.4),
            40.5,
            accuracy: 0.01
        )
        XCTAssertEqual(
            RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 0.4),
            90.0,
            accuracy: 0.01
        )

        // Zone 2 normal swipe (45-min -> ~432 s, 3h movie -> ~1620 s)
        XCTAssertEqual(
            RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 2700, speedNorm: 2.4),
            432.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 2.4),
            1620.0,
            accuracy: 0.01
        )

        // Zone 3 fast flick on 3h movie eliminates the 75 s wall (~3300 s = 55 min per full flick)
        XCTAssertEqual(
            RemoteScrubMath.secondsPerFullSwipe(durationSeconds: 10800, speedNorm: 4.0),
            3300.0,
            accuracy: 0.01
        )

        // Zero reversal deadzone: a tiny 1.5 pt reversal immediately yields negative delta
        let reverseMicroStep = RemoteScrubMath.incrementalStepSeconds(
            stepDxPoints: -1.5,
            durationSeconds: 2700,
            speedNorm: 0.3
        )
        XCTAssertLessThan(reverseMicroStep, 0)
        XCTAssertEqual(reverseMicroStep, (-1.5 / 260.0) * 40.5, accuracy: 0.001)
    }

    func testEmaVelocitySmoothingAndProgressiveRingHoldSpeeds() {
        let s1 = RemoteScrubMath.smoothedSpeedNorm(previous: 0.0, velocityXPointsPerSecond: 1040.0)
        // raw = 4.0 -> 0.35 * 4.0 = 1.4
        XCTAssertEqual(s1, 1.4, accuracy: 0.001)

        let s2 = RemoteScrubMath.smoothedSpeedNorm(previous: s1, velocityXPointsPerSecond: 1040.0)
        // 1.4 * 0.65 + 4.0 * 0.35 = 2.31
        XCTAssertEqual(s2, 2.31, accuracy: 0.001)

        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 0.0), 30.0)
        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 1.09), 30.0)
        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 1.5), 120.0)
        XCTAssertEqual(RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: 3.0), 300.0)
    }
}
