import Foundation

/// Deterministic Siri Remote `Menu` (`onExitCommand`) step ladder for the tvOS player shell.
public enum PlayerExitAction: Equatable, Sendable {
    case closeQuickPanel
    case cancelScrubbing
    case dismissSeriesPrompt
    case releaseQuickActionsFocus(hideBottomBar: Bool)
    case hideBottomBar
    case closePlayer
}

/// Pure, Linux-testable clock bucketing, Norwegian 24-hour finish-time formatting,
/// and `Menu` / `onExitCommand` resolution shared between `LunaCore` and `Luna`.
public enum PlayerTimelinePolicy: Sendable {
    public static let playheadBucketSeconds: Double = 0.5
    public static let bufferBucketSeconds: Double = 2.0
    public static let finishTimeBucketSeconds: Double = 10.0

    private static func clampedBucket(_ scaled: Double) -> Int {
        guard scaled.isFinite else { return Int.max }
        let floored = scaled.rounded(.down)
        guard floored >= 0 else { return -1 }
        return Int(exactly: floored) ?? Int.max
    }

    /// `0.5 s` buckets (`2 Hz` max while playing, `0 Hz` when paused) so `10 Hz` engine clock
    /// ticks never trigger unnecessary SwiftUI layout passes on the timeline or chapter label.
    public static func timeBucket(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return clampedBucket(seconds * 2.0)
    }

    /// `2.0 s` buckets (`0.5 Hz` max) for the subtle background forward-buffer bar.
    public static func bufferBucket(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return clampedBucket(seconds / 2.0)
    }

    /// `10.0 s` buckets (`0.1 Hz` max) for the wall-clock finish-time label (`Slutter kl. HH:mm`).
    public static func finishTimeBucket(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return clampedBucket(seconds / 10.0)
    }

    /// Formats the wall-clock completion label as `Slutter kl. HH:mm` (explicit 24-hour colon
    /// format independent of host locale) whenever `durationSeconds > 30`.
    public static func formatFinishTimeText(
        currentSeconds: Double,
        durationSeconds: Double,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard durationSeconds.isFinite, durationSeconds > 30 else { return nil }
        let clampedCurrent = currentSeconds.isFinite ? max(0, currentSeconds) : 0
        let remaining = max(0, durationSeconds - clampedCurrent)
        let finishDate = now.addingTimeInterval(remaining)
        let components = calendar.dateComponents([.hour, .minute], from: finishDate)
        guard let hour = components.hour, let minute = components.minute,
              (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        let hh = hour < 10 ? "0\(hour)" : "\(hour)"
        let mm = minute < 10 ? "0\(minute)" : "\(minute)"
        return "Slutter kl. \(hh):\(mm)"
    }

    /// Evaluates the 6-step `Menu` / `onExitCommand` state machine in strict priority order:
    /// 1. Open quick-panel popover -> close popover and return focus to its bottom pill.
    /// 2. Active touch or ring-hold scrubbing -> cancel scrub back to `originSeconds`.
    /// 3. Visible series continuity prompt -> dismiss prompt and return focus to canvas.
    /// 4. Focused bottom quick-actions strip -> release focus to canvas (hiding bar if playing, keeping bar in pause).
    /// 5. Visible bottom OSD while playing -> hide bottom OSD without exiting playback.
    /// 6. Otherwise (hidden OSD in play, resting canvas focus in pause, curtain, or fatal error) -> close player.
    public static func resolveExitAction(
        hasActiveQuickPanel: Bool,
        isScrubbing: Bool,
        hasSeriesPrompt: Bool,
        isHUDResting: Bool,
        isQuickActionsModeActive: Bool,
        showBottomBar: Bool,
        isPlaying: Bool
    ) -> PlayerExitAction {
        if hasActiveQuickPanel {
            return .closeQuickPanel
        }
        if isScrubbing {
            return .cancelScrubbing
        }
        if hasSeriesPrompt && !isHUDResting {
            return .dismissSeriesPrompt
        }
        if isQuickActionsModeActive {
            return .releaseQuickActionsFocus(hideBottomBar: isPlaying)
        }
        if showBottomBar && isPlaying {
            return .hideBottomBar
        }
        return .closePlayer
    }
}

public typealias TimelineClockBucketer = PlayerTimelinePolicy
