import Foundation
import AVFoundation
import AetherBridge
import os

private actor NativeAudioSessionActivator {
    private let logger = Logger(subsystem: "local.lunacore.luna", category: "AudioSession")

    /// Activates the shared `AVAudioSession` off-main for bare `AVPlayerLayer` native routes.
    /// `AetherEngine` owns category/policy/multichannel configuration on first load and activates
    /// `.software` / `.audio` paths itself (`activateRendererAudioSession`). When `deactivatesAudioSessionOnStop`
    /// is enabled, final stop deactivates the session, so native `AVPlayerLayer` playback ensures
    /// the session is active once `engine.load(...)` completes without mutating category or mode.
    func ensureActiveOffMain() {
        guard !Task.isCancelled else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.warning("Failed to activate native AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Aligns `AVAudioSession` native-layer activation and deferred HDMI display-criteria resets
/// with `AetherEngine` 7.69.0's tvOS lifecycle contracts.
@MainActor
final class PlayerAudioSessionCoordinator {
    static let shared = PlayerAudioSessionCoordinator()

    nonisolated static let defaultDisplayCriteriaResetDelayNs: UInt64 = 20_000_000_000

    private let activator = NativeAudioSessionActivator()
    private var activeEngineOwnerToken: UInt64 = 0
    private var deferredResetTask: Task<Void, Never>?
    private var deferredResetToken: UInt64 = 0
    private var pendingResetCheck: (@MainActor () -> Bool)?
    private var pendingResetAction: (@MainActor () -> Void)?

    init() {}

    @discardableResult
    func claimEngineOwnership() -> UInt64 {
        activeEngineOwnerToken &+= 1
        if activeEngineOwnerToken == 0 {
            activeEngineOwnerToken = 1
        }
        return activeEngineOwnerToken
    }

    func isCurrentEngineOwner(_ token: UInt64) -> Bool {
        token == 0 || activeEngineOwnerToken == token
    }

    /// Only native `AVPlayerLayer` routes (`.loopback`, `.remoteBypass`) bypass `AVPlayerViewController`
    /// and `AetherEngine`'s renderer activation. `.software` and `.audio` are activated by the engine.
    nonisolated static func shouldActivateNativeAudioSession(for videoRoute: VideoRoute) -> Bool {
        switch videoRoute {
        case .loopback, .remoteBypass:
            return true
        case .software, .audio, .none:
            return false
        }
    }

    /// Only reset display criteria once the singleton engine is genuinely idle so a deferred reset
    /// never interrupts a follow-up playback load or active session.
    nonisolated static func shouldExecuteDeferredDisplayCriteriaReset(engineState: PlaybackState) -> Bool {
        engineState == .idle
    }

    nonisolated static func shouldFlushDeferredResetOnDetailDisappear(
        isLaunchingPlayback: Bool,
        isShowingSourcePicker: Bool
    ) -> Bool {
        !isLaunchingPlayback && !isShowingSourcePicker
    }

    func activateNativePlaybackIfNeeded(videoRoute: VideoRoute) async {
        guard !Task.isCancelled, Self.shouldActivateNativeAudioSession(for: videoRoute) else {
            return
        }
        await activator.ensureActiveOffMain()
    }

    func cancelDeferredDisplayCriteriaReset() {
        deferredResetToken &+= 1
        deferredResetTask?.cancel()
        deferredResetTask = nil
        pendingResetCheck = nil
        pendingResetAction = nil
    }

    func scheduleDeferredDisplayCriteriaReset(
        engine: AetherEngine,
        delayNanoseconds: UInt64 = defaultDisplayCriteriaResetDelayNs
    ) {
        scheduleDeferredDisplayCriteriaReset(
            delayNanoseconds: delayNanoseconds,
            shouldExecute: { [weak engine] in
                guard let engine else { return false }
                return Self.shouldExecuteDeferredDisplayCriteriaReset(engineState: engine.state)
            },
            performReset: { [weak engine] in
                engine?.stop(resetDisplayCriteria: true)
            }
        )
    }

    func scheduleDeferredDisplayCriteriaReset(
        delayNanoseconds: UInt64 = defaultDisplayCriteriaResetDelayNs,
        shouldExecute: @escaping @MainActor () -> Bool,
        performReset: @escaping @MainActor () -> Void
    ) {
        cancelDeferredDisplayCriteriaReset()
        deferredResetToken &+= 1
        let token = deferredResetToken
        pendingResetCheck = shouldExecute
        pendingResetAction = performReset

        deferredResetTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self, self.deferredResetToken == token else {
                return
            }
            self.executePendingResetIfEligible()
        }
    }

    func handleDetailDisappear(
        isLaunchingPlayback: Bool,
        isShowingSourcePicker: Bool
    ) {
        guard Self.shouldFlushDeferredResetOnDetailDisappear(
            isLaunchingPlayback: isLaunchingPlayback,
            isShowingSourcePicker: isShowingSourcePicker
        ) else {
            return
        }
        flushDeferredDisplayCriteriaResetIfIdle()
    }

    func flushDeferredDisplayCriteriaResetIfIdle() {
        guard deferredResetTask != nil else { return }
        if pendingResetCheck?() == true {
            executePendingResetIfEligible()
        }
    }

    func flushDeferredDisplayCriteriaResetIfIdle(engine: AetherEngine) {
        guard deferredResetTask != nil else { return }
        if Self.shouldExecuteDeferredDisplayCriteriaReset(engineState: engine.state) {
            executePendingResetIfEligible()
        }
    }

    func flushPendingDeferredResetIfEligibleForTesting() {
        guard deferredResetTask != nil else { return }
        executePendingResetIfEligible()
    }

    private func executePendingResetIfEligible() {
        let shouldExecute = pendingResetCheck
        let action = pendingResetAction
        deferredResetToken &+= 1
        deferredResetTask?.cancel()
        deferredResetTask = nil
        pendingResetCheck = nil
        pendingResetAction = nil
        if shouldExecute?() == true {
            action?()
        }
    }
}
