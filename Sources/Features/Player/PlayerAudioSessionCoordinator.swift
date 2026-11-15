import Foundation
import AVFoundation
import AetherBridge
import os

private actor AudioSessionActivationWorker {
    private let logger = Logger(subsystem: "local.lunacore.luna", category: "AudioSession")

    func configureAndActivate() {
        let session = AVAudioSession.sharedInstance()

        do {
            if session.category != .playback || session.mode != .moviePlayback {
                do {
                    try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio)
                } catch {
                    try session.setCategory(.playback, mode: .moviePlayback)
                }
            }
        } catch {
            logger.warning("Failed to set AVAudioSession category: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if !session.supportsMultichannelContent {
                try session.setSupportsMultichannelContent(true)
            }
        } catch {
            logger.debug("Multichannel preference skipped: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try session.setActive(true)
        } catch {
            logger.warning("Failed to activate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reactivateOnly() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.warning("Failed to reactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Owns `AVAudioSession` activation and rapid HDMI/eARC re-entry settling for Luna's bare
/// `AVPlayerLayer` host (`AetherPlayerSurface`), fulfilling `AetherEngine`'s audio-session contract.
@MainActor
final class PlayerAudioSessionCoordinator {
    static let shared = PlayerAudioSessionCoordinator()

    nonisolated static let defaultRapidReentrySettleMs: Int = 1100

    private let worker = AudioSessionActivationWorker()
    private var lastDisplayCriteriaResetUptimeNs: UInt64?
    private var routeChangeObserver: NSObjectProtocol?
    private var isActivelyPresentingPlayback: Bool = false

    private init() {}

    nonisolated static func rapidReentrySettleDelayMs(
        elapsedSinceResetMs: Int?,
        minimumSettleWindowMs: Int = defaultRapidReentrySettleMs
    ) -> Int {
        guard let elapsed = elapsedSinceResetMs, elapsed >= 0, minimumSettleWindowMs > 0 else {
            return 0
        }
        guard elapsed < minimumSettleWindowMs else { return 0 }
        return min(minimumSettleWindowMs - elapsed, minimumSettleWindowMs)
    }

    nonisolated static func shouldReactivateOnRouteChange(reasonRawValue: UInt?) -> Bool {
        guard let raw = reasonRawValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else {
            return false
        }
        switch reason {
        case .newDeviceAvailable, .routeConfigurationChange, .override, .categoryChange:
            return true
        default:
            return false
        }
    }

    func noteDisplayCriteriaReset(nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lastDisplayCriteriaResetUptimeNs = nowUptimeNs
    }

    func prepareForPlayback(isInPlaceReplacement: Bool) async {
        isActivelyPresentingPlayback = true
        installRouteObserverIfNeeded()

        if !isInPlaceReplacement, let resetNs = lastDisplayCriteriaResetUptimeNs {
            let nowNs = DispatchTime.now().uptimeNanoseconds
            let elapsedMs = nowNs >= resetNs ? Int((nowNs - resetNs) / 1_000_000) : 0
            let waitMs = Self.rapidReentrySettleDelayMs(elapsedSinceResetMs: elapsedMs)
            lastDisplayCriteriaResetUptimeNs = nil
            if waitMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
                if Task.isCancelled { return }
            }
        } else if !isInPlaceReplacement {
            lastDisplayCriteriaResetUptimeNs = nil
        }

        await worker.configureAndActivate()
    }

    func ensureActiveAfterDisplaySwitch() {
        guard isActivelyPresentingPlayback else { return }
        Task {
            await worker.reactivateOnly()
        }
    }

    func handleRouteChange(reasonRawValue: UInt?) {
        guard isActivelyPresentingPlayback,
              Self.shouldReactivateOnRouteChange(reasonRawValue: reasonRawValue) else {
            return
        }
        Task {
            await worker.configureAndActivate()
        }
    }

    func togglePlayPause(engine: AetherEngine, phase: PlaybackPhase) {
        if phase == .paused {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        engine.togglePlayPause()
    }

    func notePlaybackStopped() {
        isActivelyPresentingPlayback = false
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func installRouteObserverIfNeeded() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                PlayerAudioSessionCoordinator.shared.handleRouteChange(reasonRawValue: rawReason)
            }
        }
    }
}
