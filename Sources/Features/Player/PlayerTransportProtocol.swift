import Foundation
import CoreGraphics
import Observation
import AetherBridge

/// Isolated high-frequency scrubbing state so touch-surface updates during
/// 60–120 Hz Siri Remote panning only invalidate `TimelineScrubberLeafView`.
@MainActor
@Observable
final class PlayerScrubState {
    var targetSeconds: Double = 0
    var originSeconds: Double = 0
    var previewImage: CGImage?
}

/// Protocol abstraction for `AetherEngine` transport operations so lifecycle,
/// paused-restore resume, scrub commit, and dismissal flows can be tested without
/// mutating production `PlayerViewModel` state with test closures.
@MainActor
protocol PlayerTransportControlling: AnyObject {
    var state: PlaybackState { get }
    var playbackPhase: PlaybackPhase { get }
    var videoRoute: VideoRoute { get }
    var currentTime: Double { get }
    var needsForegroundVideoRestore: Bool { get }
    func play()
    func pause()
    func togglePlayPause()
    func seek(to seconds: Double, exact: Bool) async
    func setAudioDelay(_ seconds: Double)
    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool)
}

@MainActor
final class AetherEngineTransport: PlayerTransportControlling {
    private let engine: AetherEngine

    init(engine: AetherEngine) {
        self.engine = engine
    }

    var state: PlaybackState { engine.state }
    var playbackPhase: PlaybackPhase { engine.playbackPhase }
    var videoRoute: VideoRoute { engine.videoRoute }
    var currentTime: Double { engine.currentTime }
    var needsForegroundVideoRestore: Bool { engine.needsForegroundVideoRestore }

    func play() {
        engine.play()
    }

    func pause() {
        engine.pause()
    }

    func togglePlayPause() {
        engine.togglePlayPause()
    }

    func seek(to seconds: Double, exact: Bool) async {
        await engine.seek(to: seconds, exact: exact)
    }

    func setAudioDelay(_ seconds: Double) {
        engine.setAudioDelay(seconds)
    }

    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool) {
        engine.stop(resetDisplayCriteria: resetDisplayCriteria, finalTeardown: finalTeardown)
    }
}

/// Protocol abstraction for activating `AVAudioSession` off the main actor
/// when resuming or starting native `AVPlayerLayer` routes.
protocol NativeAudioActivating: Sendable {
    func activateNativePlaybackIfNeeded(videoRoute: VideoRoute) async
}

struct DefaultNativeAudioActivator: NativeAudioActivating {
    func activateNativePlaybackIfNeeded(videoRoute: VideoRoute) async {
        await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(videoRoute: videoRoute)
    }
}
