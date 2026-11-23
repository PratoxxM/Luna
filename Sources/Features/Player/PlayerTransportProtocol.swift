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

/// Protocol abstraction for `AetherEngine` transport, track, and reload operations so lifecycle,
/// paused-restore resume, scrub commit, source switching, and dismissal flows can be tested cleanly.
@MainActor
protocol PlayerTransportControlling: AnyObject {
    var state: PlaybackState { get }
    var playbackPhase: PlaybackPhase { get }
    var videoRoute: VideoRoute { get }
    var currentTime: Double { get }
    var needsForegroundVideoRestore: Bool { get }
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] { get }
    var activeAudioTrackIndex: Int? { get }
    var subtitleTrackDescriptors: [SmartTrackDescriptor] { get }
    var activeSubtitleTrackIndex: Int? { get }
    func play()
    func pause()
    func togglePlayPause()
    func seek(to seconds: Double, exact: Bool) async
    func setAudioDelay(_ seconds: Double)
    func setAudioShaping(_ shaping: AudioShaping)
    func setSoftwareSubtitleDelay(_ seconds: Double)
    func selectAudioTrack(index: Int)
    func selectSubtitleTrack(index: Int)
    func clearSubtitle()
    func prepareForItemReplacement()
    func loadStream(url: URL, startPosition: Double?, options: LoadOptions) async throws
    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool)
}

extension PlayerTransportControlling {
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] { [] }
    var activeAudioTrackIndex: Int? { nil }
    var subtitleTrackDescriptors: [SmartTrackDescriptor] { [] }
    var activeSubtitleTrackIndex: Int? { nil }
    func setAudioShaping(_: AudioShaping) {}
    func setSoftwareSubtitleDelay(_: Double) {}
    func selectAudioTrack(index _: Int) {}
    func selectSubtitleTrack(index _: Int) {}
    func clearSubtitle() {}
    func prepareForItemReplacement() {}
    func loadStream(url _: URL, startPosition _: Double?, options _: LoadOptions) async throws {}
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
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] {
        engine.audioTracks.map(PlaybackAudioTrackDescriptor.init(track:))
    }
    var activeAudioTrackIndex: Int? { engine.activeAudioTrackIndex }
    var subtitleTrackDescriptors: [SmartTrackDescriptor] {
        engine.subtitleTracks.map(SmartTrackDescriptor.init(track:))
    }
    var activeSubtitleTrackIndex: Int? { engine.activeSubtitleTrackIndex }

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

    func setAudioShaping(_ shaping: AudioShaping) {
        engine.setAudioShaping(shaping)
    }

    func setSoftwareSubtitleDelay(_ seconds: Double) {
        engine.setSoftwareSubtitleDelay(seconds)
    }

    func selectAudioTrack(index: Int) {
        engine.selectAudioTrack(index: index)
    }

    func selectSubtitleTrack(index: Int) {
        engine.selectSubtitleTrack(index: index)
    }

    func clearSubtitle() {
        engine.clearSubtitle()
    }

    func prepareForItemReplacement() {
        engine.prepareForItemReplacement()
    }

    func loadStream(url: URL, startPosition: Double?, options: LoadOptions) async throws {
        _ = try await engine.load(url: url, startPosition: startPosition, options: options)
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
