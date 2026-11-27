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
    var heldPictureFrameWaitSeconds: Double { get }
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
    func attachStillView(_ view: AetherStillView?)
    @discardableResult func holdOutgoingPicture() async -> Bool
    func releaseOutgoingPicture()
    func prepareForItemReplacement()
    func loadStream(url: URL, startPosition: Double?, options: LoadOptions) async throws
    func reloadAtCurrentPosition(applying change: (inout LoadOptions) -> Void) async throws
    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool)
}

extension PlayerTransportControlling {
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] { [] }
    var activeAudioTrackIndex: Int? { nil }
    var subtitleTrackDescriptors: [SmartTrackDescriptor] { [] }
    var activeSubtitleTrackIndex: Int? { nil }
    var heldPictureFrameWaitSeconds: Double { 0 }
    func setAudioShaping(_: AudioShaping) {}
    func setSoftwareSubtitleDelay(_: Double) {}
    func selectAudioTrack(index _: Int) {}
    func selectSubtitleTrack(index _: Int) {}
    func clearSubtitle() {}
    func attachStillView(_: AetherStillView?) {}
    @discardableResult func holdOutgoingPicture() async -> Bool { false }
    func releaseOutgoingPicture() {}
    func prepareForItemReplacement() {}
    func loadStream(url _: URL, startPosition _: Double?, options _: LoadOptions) async throws {}
    func reloadAtCurrentPosition(applying _: (inout LoadOptions) -> Void) async throws {}
}

@MainActor
final class AetherEngineTransport: PlayerTransportControlling {
    private let engine: AetherEngine
    private weak var stillView: AetherStillView?
    private var holdGeneration: UInt64 = 0
    private var inFlightHoldCount: Int = 0
    private var isHoldingStill: Bool = false
    private var hasUnclaimedEngineHold: Bool = false

    init(engine: AetherEngine) {
        self.engine = engine
    }

    var state: PlaybackState { engine.state }
    var playbackPhase: PlaybackPhase { engine.playbackPhase }
    var videoRoute: VideoRoute { engine.videoRoute }
    var currentTime: Double { engine.currentTime }
    var needsForegroundVideoRestore: Bool { engine.needsForegroundVideoRestore }
    var heldPictureFrameWaitSeconds: Double { engine.heldPictureFrameWaitSeconds }
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

    func attachStillView(_ view: AetherStillView?) {
        if stillView !== view {
            stillView?.alpha = 0
            holdGeneration &+= 1
            let hadEngineHold = isHoldingStill || hasUnclaimedEngineHold
            isHoldingStill = false
            if hadEngineHold {
                if inFlightHoldCount == 0 {
                    hasUnclaimedEngineHold = false
                    engine.releaseOutgoingPicture()
                } else {
                    hasUnclaimedEngineHold = true
                }
            }
        }
        stillView = view
        if !isHoldingStill {
            view?.alpha = 0
        }
    }

    @discardableResult
    func holdOutgoingPicture() async -> Bool {
        guard let targetView = stillView else {
            if hasUnclaimedEngineHold && !isHoldingStill && inFlightHoldCount == 0 {
                hasUnclaimedEngineHold = false
                engine.releaseOutgoingPicture()
            }
            return false
        }
        holdGeneration &+= 1
        let token = holdGeneration
        inFlightHoldCount += 1
        let held: Bool
        do {
            defer { inFlightHoldCount -= 1 }
            held = await engine.holdOutgoingPicture(on: targetView)
        }
        if held, stillView === targetView, token == holdGeneration {
            isHoldingStill = true
            hasUnclaimedEngineHold = false
            targetView.alpha = 1
            return true
        }
        if held {
            hasUnclaimedEngineHold = true
        }
        if stillView !== targetView || (!isHoldingStill && inFlightHoldCount == 0) {
            targetView.alpha = 0
        }
        if (held || hasUnclaimedEngineHold) && !isHoldingStill && inFlightHoldCount == 0 {
            hasUnclaimedEngineHold = false
            engine.releaseOutgoingPicture()
        }
        return false
    }

    func releaseOutgoingPicture() {
        holdGeneration &+= 1
        isHoldingStill = false
        hasUnclaimedEngineHold = false
        stillView?.alpha = 0
        engine.releaseOutgoingPicture()
    }

    func prepareForItemReplacement() {
        engine.prepareForItemReplacement()
    }

    func loadStream(url: URL, startPosition: Double?, options: LoadOptions) async throws {
        _ = try await engine.load(url: url, startPosition: startPosition, options: options)
    }

    func reloadAtCurrentPosition(applying change: (inout LoadOptions) -> Void) async throws {
        _ = try await engine.reloadAtCurrentPosition(applying: change)
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
