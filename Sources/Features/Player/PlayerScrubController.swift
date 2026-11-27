import Foundation
import ImageIO
import Observation
import UIKit
import AetherBridge

/// Owns Siri Remote touch scrubbing, ring-hold progressive seeking, coalesced `±10 s` seek,
/// chapter jumping, and isolated `PlayerScrubState` preview frame fetching.
@MainActor
@Observable
final class PlayerScrubController {
    var previewPlayheadOverrideSeconds: Double?
    var coalescedSeekDelta: Double = 0
    var coalescedSeekPreviewTarget: Double?
    var isScrubbing: Bool = false
    let scrubState = PlayerScrubState()

    @ObservationIgnored private weak var host: PlayerViewModel?
    @ObservationIgnored let engine: AetherEngine
    @ObservationIgnored let transport: any PlayerTransportControlling
    @ObservationIgnored let audioActivator: any NativeAudioActivating

    @ObservationIgnored var wasPlayingBeforeScrub: Bool = false
    @ObservationIgnored var pendingScrubPreviewTarget: Double?
    @ObservationIgnored var scrubPreviewLoopTask: Task<Void, Never>?
    @ObservationIgnored weak var compositorPreviewView: AetherScrubPreviewView?
    @ObservationIgnored var coalescedSeekTask: Task<Void, Never>?
    @ObservationIgnored var chapterSeekTask: Task<Void, Never>?
    @ObservationIgnored var scrubCommitTask: Task<Void, Never>?
    @ObservationIgnored var scrubCommitToken: UInt64 = 0
    @ObservationIgnored var ringHoldLoopTask: Task<Void, Never>?
    @ObservationIgnored private var serverTrickplayCacheSessionId: String?
    @ObservationIgnored private var serverTrickplayFrames: [Int: CGImage] = [:]
    @ObservationIgnored private var serverTrickplayLRUOrder: [Int] = []
    @ObservationIgnored private var isServerTrickplayDisabledForSession: Bool = false

    init(
        engine: AetherEngine,
        transport: any PlayerTransportControlling,
        audioActivator: any NativeAudioActivating
    ) {
        self.engine = engine
        self.transport = transport
        self.audioActivator = audioActivator
    }

    func bindHost(_ host: PlayerViewModel) {
        self.host = host
    }

    func cancelRingHoldTask() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
    }

    func cancelPendingScrubCommit() {
        scrubCommitToken &+= 1
        scrubCommitTask?.cancel()
        scrubCommitTask = nil
    }

    private func canFinishScrubCommit(expectedToken: UInt64, expectedSessionId: String?) -> Bool {
        guard let host else { return false }
        return !Task.isCancelled &&
            scrubCommitToken == expectedToken &&
            !host.sessionController.isTeardownCompleted &&
            host.sessionController.fatalError == nil &&
            !host.sessionController.isResolving &&
            !host.sessionController.isSwitchingSource &&
            !host.restoreController.isRestoringFromBackground &&
            !isScrubbing &&
            host.restoreController.isForegroundActive &&
            !transport.needsForegroundVideoRestore &&
            host.sessionController.activeSession?.sessionId == expectedSessionId
    }

    func beginTouchScrub() {
        guard let host, !host.sessionController.isResolving,
              host.sessionController.effectiveDurationSeconds > 5 else {
            return
        }
        host.restoreController.cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        if !isScrubbing {
            let origin = max(0, transport.currentTime)
            wasPlayingBeforeScrub = (host.qosReporter.playbackPhase == .playing)
            if wasPlayingBeforeScrub {
                transport.pause()
            }
            scrubState.originSeconds = origin
            scrubState.targetSeconds = origin
            scrubState.previewImage = nil
            isScrubbing = true
            UIApplication.shared.isIdleTimerDisabled = true
            enqueueScrubPreview(at: origin)
        }
    }

    func configurePreviewScrub(
        originSeconds: Double = 1122,
        targetSeconds: Double = 2145,
        previewImage: CGImage?
    ) {
        scrubState.originSeconds = originSeconds
        scrubState.targetSeconds = targetSeconds
        scrubState.previewImage = previewImage
        isScrubbing = true
    }

    func updateTouchScrub(deltaSeconds: Double) {
        guard isScrubbing else { return }
        let dur = max(1, host?.sessionController.effectiveDurationSeconds ?? 1)
        let clamped = min(max(0, scrubState.targetSeconds + deltaSeconds), max(0, dur - 0.5))
        scrubState.targetSeconds = clamped
        enqueueScrubPreview(at: clamped)
    }

    func stepTouchScrub(by deltaSeconds: Double) {
        updateTouchScrub(deltaSeconds: deltaSeconds)
    }

    func beginRingHoldScrub(direction: Int) {
        guard let host, !host.sessionController.isResolving,
              host.sessionController.effectiveDurationSeconds > 5,
              direction != 0 else {
            return
        }
        let signedDir = direction > 0 ? 1.0 : -1.0
        beginTouchScrub()
        ringHoldLoopTask?.cancel()
        let startedAt = ProcessInfo.processInfo.systemUptime
        ringHoldLoopTask = Task { @MainActor [weak self] in
            var lastTick = startedAt
            while let self, !Task.isCancelled, self.isScrubbing {
                let now = ProcessInfo.processInfo.systemUptime
                let dt = min(0.12, max(0.01, now - lastTick))
                lastTick = now
                let speed = RemoteScrubMath.ringHoldSpeedSecondsPerSecond(holdDurationSeconds: now - startedAt)
                self.updateTouchScrub(deltaSeconds: signedDir * speed * dt)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func endRingHoldScrub(cancelled: Bool = false) {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        guard isScrubbing else { return }
        if cancelled {
            cancelTouchScrub()
            return
        }
        if wasPlayingBeforeScrub {
            let target = scrubState.targetSeconds
            resetScrubStateOnSessionChange()
            performScrubSeekCommit(target: target, exact: false, shouldPlayAfterSeek: true)
        }
    }

    func commitTouchScrub() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        guard isScrubbing else { return }
        let target = scrubState.targetSeconds
        resetScrubStateOnSessionChange()
        performScrubSeekCommit(target: target, exact: true, shouldPlayAfterSeek: true)
    }

    func commitTouchScrubPaused() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        guard isScrubbing else { return }
        let origin = scrubState.originSeconds
        let target = scrubState.targetSeconds
        resetScrubStateOnSessionChange()
        guard abs(target - origin) >= 0.25 else { return }
        performScrubSeekCommit(target: target, exact: true, shouldPlayAfterSeek: false)
    }

    func cancelTouchScrub() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        guard isScrubbing else { return }
        cancelPendingScrubCommit()
        let origin = scrubState.originSeconds
        let shouldResume = wasPlayingBeforeScrub
        scrubState.targetSeconds = origin
        resetScrubStateOnSessionChange()
        if abs(transport.currentTime - origin) > 0.25 {
            performScrubSeekCommit(target: origin, exact: true, shouldPlayAfterSeek: shouldResume)
        } else if shouldResume {
            transport.play()
        }
    }

    private func performScrubSeekCommit(target: Double, exact: Bool, shouldPlayAfterSeek: Bool) {
        guard let host else { return }
        host.restoreController.cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        scrubCommitToken &+= 1
        let commitToken = scrubCommitToken
        let expectedSessionId = host.sessionController.activeSession?.sessionId

        scrubCommitTask = Task { @MainActor [weak self] in
            guard let self, let host = self.host else { return }
            await self.transport.seek(to: target, exact: exact)
            guard self.canFinishScrubCommit(expectedToken: commitToken, expectedSessionId: expectedSessionId) else {
                if self.scrubCommitToken == commitToken {
                    self.scrubCommitTask = nil
                }
                return
            }
            if shouldPlayAfterSeek && host.restoreController.needsNativeAudioActivationAfterPausedRestore {
                await host.restoreController.activateNativeAudioForPendingResumeIfNeeded()
                guard self.canFinishScrubCommit(expectedToken: commitToken, expectedSessionId: expectedSessionId) else {
                    if self.scrubCommitToken == commitToken {
                        self.scrubCommitTask = nil
                    }
                    return
                }
                host.restoreController.needsNativeAudioActivationAfterPausedRestore = false
            }
            if self.scrubCommitToken == commitToken {
                self.scrubCommitTask = nil
            }
            if shouldPlayAfterSeek {
                if self.transport.state == .paused || self.transport.state == .loading {
                    self.transport.play()
                }
                if host.restoreController.isForegroundActive && !self.transport.needsForegroundVideoRestore {
                    host.restoreController.lastForegroundPlaybackWasPlaying = PlayerRestoreController.isActiveTransportIntent(
                        playbackPhase: self.transport.playbackPhase,
                        engineState: self.transport.state
                    )
                }
            }
        }
    }

    func attachCompositorPreviewView(_ view: AetherScrubPreviewView?) {
        compositorPreviewView = view
        guard view != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isScrubbing else { return }
            self.enqueueScrubPreview(at: self.scrubState.targetSeconds)
        }
    }

    func clearServerTrickplayCache() {
        serverTrickplayCacheSessionId = nil
        serverTrickplayFrames.removeAll(keepingCapacity: false)
        serverTrickplayLRUOrder.removeAll(keepingCapacity: false)
        isServerTrickplayDisabledForSession = false
    }

    func resetScrubStateOnSessionChange() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        scrubPreviewLoopTask?.cancel()
        scrubPreviewLoopTask = nil
        pendingScrubPreviewTarget = nil
        compositorPreviewView?.clear()
        if isScrubbing { isScrubbing = false }
        if scrubState.previewImage != nil { scrubState.previewImage = nil }
        wasPlayingBeforeScrub = false
    }

    private func enqueueScrubPreview(at targetSeconds: Double) {
        pendingScrubPreviewTarget = targetSeconds
        guard scrubPreviewLoopTask == nil else { return }

        scrubPreviewLoopTask = Task { @MainActor [weak self] in
            defer { self?.scrubPreviewLoopTask = nil }

            while let self, !Task.isCancelled, self.isScrubbing, let requested = self.pendingScrubPreviewTarget {
                self.pendingScrubPreviewTarget = nil

                var didObtainEnginePreview = false
                if self.engine.scrubPreviewDrawsInView {
                    if let compView = self.compositorPreviewView {
                        let placement = await self.engine.showScrubPreview(atSeconds: requested, in: compView)
                        guard !Task.isCancelled, self.isScrubbing else { return }
                        if placement != nil {
                            didObtainEnginePreview = true
                            if self.scrubState.previewImage != nil {
                                self.scrubState.previewImage = nil
                            }
                        }
                    }
                } else if self.engine.supportsCacheBackedStills {
                    let still = await self.engine.scrubThumbnail(atSeconds: requested, maxWidth: 480)
                    guard !Task.isCancelled, self.isScrubbing else { return }
                    if let still {
                        didObtainEnginePreview = true
                        if self.scrubState.previewImage !== still {
                            self.scrubState.previewImage = still
                        }
                    }
                }

                if !didObtainEnginePreview {
                    await self.fetchServerTrickplayFallback(for: requested)
                    guard !Task.isCancelled, self.isScrubbing else { return }
                }

                if self.pendingScrubPreviewTarget == nil {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                }
            }
        }
    }

    private func fetchServerTrickplayFallback(for requested: Double) async {
        guard let session = host?.sessionController.activeSession,
              let client = host?.sessionController.activeClient,
              PlaybackTrickplayPolicy.shouldAttemptServerTrickplay(session: session) else {
            if scrubState.previewImage != nil {
                scrubState.previewImage = nil
            }
            return
        }

        if serverTrickplayCacheSessionId != session.sessionId {
            clearServerTrickplayCache()
            serverTrickplayCacheSessionId = session.sessionId
        }
        guard !isServerTrickplayDisabledForSession else {
            if scrubState.previewImage != nil {
                scrubState.previewImage = nil
            }
            return
        }

        let dur = host?.sessionController.effectiveDurationSeconds ?? 0
        guard let bucket = PlaybackTrickplayPolicy.quantizedBucketSeconds(
            for: requested,
            durationSeconds: dur
        ) else {
            if scrubState.previewImage != nil {
                scrubState.previewImage = nil
            }
            return
        }

        if let cached = cachedTrickplayFrame(for: bucket) {
            if scrubState.previewImage !== cached {
                scrubState.previewImage = cached
            }
            return
        }

        try? await Task.sleep(nanoseconds: PlaybackTrickplayPolicy.httpDebounceNanoseconds)
        guard !Task.isCancelled, isScrubbing else { return }
        if pendingScrubPreviewTarget != nil {
            return
        }

        do {
            let result = try await client.fetchScrubFrame(
                sessionId: session.sessionId,
                atSeconds: Double(bucket)
            )
            guard !Task.isCancelled,
                  isScrubbing,
                  host?.sessionController.activeSession?.sessionId == session.sessionId else {
                return
            }
            switch result {
            case .image(let data, _):
                let decoded = await Task.detached(priority: .userInitiated) {
                    Self.decodeTrickplayCGImage(from: data, maxPixelSize: 480)
                }.value
                guard !Task.isCancelled,
                      isScrubbing,
                      host?.sessionController.activeSession?.sessionId == session.sessionId else {
                    return
                }
                if let decoded {
                    storeTrickplayFrame(decoded, for: bucket)
                    let latestTarget = pendingScrubPreviewTarget ?? scrubState.targetSeconds
                    let latestBucket = PlaybackTrickplayPolicy.quantizedBucketSeconds(
                        for: latestTarget,
                        durationSeconds: host?.sessionController.effectiveDurationSeconds ?? 0
                    )
                    if latestBucket == bucket || pendingScrubPreviewTarget == nil {
                        if scrubState.previewImage !== decoded {
                            scrubState.previewImage = decoded
                        }
                    }
                } else if scrubState.previewImage != nil {
                    scrubState.previewImage = nil
                }
            case .unavailable(let statusCode, let errorCode):
                if PlaybackTrickplayPolicy.shouldDisableTrickplayForSession(
                    statusCode: statusCode,
                    errorCode: errorCode
                ) {
                    isServerTrickplayDisabledForSession = true
                }
                if scrubState.previewImage != nil {
                    scrubState.previewImage = nil
                }
            }
        } catch where LunaCoreError.isCancellation(error) || Task.isCancelled {
            return
        } catch LunaCoreError.unauthorized {
            isServerTrickplayDisabledForSession = true
            if scrubState.previewImage != nil {
                scrubState.previewImage = nil
            }
        } catch {
            if scrubState.previewImage != nil {
                scrubState.previewImage = nil
            }
        }
    }

    private func cachedTrickplayFrame(for bucket: Int) -> CGImage? {
        guard let frame = serverTrickplayFrames[bucket] else { return nil }
        serverTrickplayLRUOrder.removeAll { $0 == bucket }
        serverTrickplayLRUOrder.append(bucket)
        return frame
    }

    private func storeTrickplayFrame(_ frame: CGImage, for bucket: Int) {
        serverTrickplayFrames[bucket] = frame
        serverTrickplayLRUOrder.removeAll { $0 == bucket }
        serverTrickplayLRUOrder.append(bucket)
        while serverTrickplayLRUOrder.count > PlaybackTrickplayPolicy.maxSessionCacheFrames {
            let evicted = serverTrickplayLRUOrder.removeFirst()
            serverTrickplayFrames.removeValue(forKey: evicted)
        }
    }

    nonisolated static func decodeTrickplayCGImage(from data: Data, maxPixelSize: Int = 480) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func coalesceRelativeSeek(delta: Double) {
        guard let host, !host.sessionController.isResolving else { return }
        let dur = host.sessionController.effectiveDurationSeconds
        let base = coalescedSeekPreviewTarget ?? max(0, transport.currentTime)
        let accumulatedDelta = coalescedSeekDelta + delta
        let rawTarget = max(0, base + delta)
        let clampedTarget = dur > 1 ? min(dur - 0.5, rawTarget) : rawTarget

        coalescedSeekDelta = accumulatedDelta
        coalescedSeekPreviewTarget = clampedTarget

        chapterSeekTask?.cancel()
        chapterSeekTask = nil
        coalescedSeekTask?.cancel()
        coalescedSeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: PlayerViewModel.relativeSeekDebounceNs)
            guard !Task.isCancelled, let self else { return }
            let finalTarget = self.coalescedSeekPreviewTarget ?? max(0, self.transport.currentTime)
            await self.transport.seek(to: finalTarget, exact: false)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.coalescedSeekDelta = 0
            self.coalescedSeekPreviewTarget = nil
        }
    }

    func seekToChapter(_ chapter: PlaybackChapter) {
        seekToPosition(chapter.startSeconds, exact: true)
    }

    func seekToPosition(_ rawTargetSeconds: Double, exact: Bool = true) {
        guard let host, !host.sessionController.isResolving else { return }
        coalescedSeekTask?.cancel()
        coalescedSeekTask = nil
        coalescedSeekDelta = 0
        coalescedSeekPreviewTarget = nil
        chapterSeekTask?.cancel()
        let targetSeconds = max(0, rawTargetSeconds)
        chapterSeekTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.transport.seek(to: targetSeconds, exact: exact)
            if !Task.isCancelled {
                self.chapterSeekTask = nil
            }
        }
    }

    func cancelTasks() {
        cancelPendingScrubCommit()
        cancelRingHoldTask()
        coalescedSeekTask?.cancel(); coalescedSeekTask = nil
        chapterSeekTask?.cancel(); chapterSeekTask = nil
    }
}
