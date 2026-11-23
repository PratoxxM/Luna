import SwiftUI
import UIKit
import CoreGraphics
import AetherBridge

/// Floating 16:9 preview card positioned directly above the scrub playhead dot on the timeline.
///
/// Supports both zero-extra-connection `AetherEngine.scrubThumbnail` (`CGImage`) stills and
/// `AetherScrubPreviewView` compositor previews for Dolby Vision Profile 5 / AV1 Profile 10.0,
/// collapsing cleanly to a compact timecode pill whenever a distant segment is not cached yet.
struct ScrubPreviewBubbleView: View {
    let targetSeconds: Double
    let originSeconds: Double
    let chapterTitle: String?
    let previewImage: CGImage?
    let drawsInCompositorView: Bool
    let onMountCompositorView: (AetherScrubPreviewView?) -> Void

    static let frameWidth: CGFloat = 284
    static let compactWidth: CGFloat = 252

    var hasVisualFrame: Bool {
        drawsInCompositorView || previewImage != nil
    }

    var preferredWidth: CGFloat {
        hasVisualFrame ? Self.frameWidth : Self.compactWidth
    }

    var body: some View {
        VStack(spacing: 8) {
            if drawsInCompositorView {
                CompositorScrubPreviewRepresentable(onMount: onMountCompositorView)
                    .frame(width: 260, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let cg = previewImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 260, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                Text(TimelineScrubberLeafView.formatSeconds(targetSeconds))
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)

                let delta = targetSeconds - originSeconds
                if abs(delta) >= 1.0 {
                    Text(Self.formatSignedDelta(delta))
                        .font(LunaTheme.Font.badge.monospacedDigit())
                        .foregroundStyle(LunaTheme.amber)
                        .lineLimit(1)
                }
            }

            if let chapterTitle, !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(LunaTheme.Font.badge)
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: preferredWidth - 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: preferredWidth)
        .lunaCinemaGlassSurface(
            cornerRadius: LunaTokens.Radius.poster,
            shadowColor: LunaTheme.pureBlack.opacity(0.55),
            shadowRadius: 12,
            shadowY: 6
        )
        .allowsHitTesting(false)
    }

    private static func formatSignedDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : "−"
        let absTotal = Int(abs(delta).rounded())
        let h = absTotal / 3600
        let m = (absTotal % 3600) / 60
        let s = absTotal % 60
        if h > 0 {
            return String(format: "%@%d:%02d:%02d", sign, h, m, s)
        }
        return String(format: "%@%d:%02d", sign, m, s)
    }
}

@MainActor
private struct CompositorScrubPreviewRepresentable: UIViewRepresentable {
    let onMount: (AetherScrubPreviewView?) -> Void

    func makeUIView(context: Context) -> AetherScrubPreviewView {
        let view = AetherScrubPreviewView()
        view.videoGravity = .resizeAspectFill
        onMount(view)
        return view
    }

    func updateUIView(_ uiView: AetherScrubPreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: AetherScrubPreviewView, coordinator: ()) {
        uiView.clear()
    }
}

// MARK: - Velocity-Aware Siri Remote Touch Scrubbing & Preview Worker

extension PlayerViewModel {
    func cancelPendingScrubCommit() {
        scrubCommitToken &+= 1
        scrubCommitTask?.cancel()
        scrubCommitTask = nil
    }

    private func canFinishScrubCommit(expectedToken: UInt64, expectedSessionId: String?) -> Bool {
        !Task.isCancelled &&
        scrubCommitToken == expectedToken &&
        !isTeardownCompleted &&
        fatalError == nil &&
        !isResolving &&
        !isSwitchingSource &&
        !isRestoringFromBackground &&
        !isScrubbing &&
        isForegroundActive &&
        !transport.needsForegroundVideoRestore &&
        activeSession?.sessionId == expectedSessionId
    }

    func beginTouchScrub() {
        guard !isResolving, effectiveDurationSeconds > 5 else { return }
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        if !isScrubbing {
            let origin = max(0, transport.currentTime)
            wasPlayingBeforeScrub = (playbackPhase == .playing)
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

    func updateTouchScrub(deltaSeconds: Double) {
        guard isScrubbing else { return }
        let dur = max(1, effectiveDurationSeconds)
        let clamped = min(max(0, scrubState.targetSeconds + deltaSeconds), max(0, dur - 0.5))
        scrubState.targetSeconds = clamped
        enqueueScrubPreview(at: clamped)
    }

    func stepTouchScrub(by deltaSeconds: Double) {
        updateTouchScrub(deltaSeconds: deltaSeconds)
    }

    func beginRingHoldScrub(direction: Int) {
        guard !isResolving, effectiveDurationSeconds > 5, direction != 0 else { return }
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
        // When started while paused, stay in paused scrub mode so the user can fine-tune or click Play.
    }

    func commitTouchScrub() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        guard isScrubbing else { return }
        let target = scrubState.targetSeconds
        resetScrubStateOnSessionChange()
        performScrubSeekCommit(target: target, exact: true, shouldPlayAfterSeek: true)
    }

    /// Commits any active scrubbed position while staying paused (e.g. pressing Down into quick actions).
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
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        scrubCommitToken &+= 1
        let commitToken = scrubCommitToken
        let expectedSessionId = activeSession?.sessionId

        scrubCommitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.transport.seek(to: target, exact: exact)
            guard self.canFinishScrubCommit(expectedToken: commitToken, expectedSessionId: expectedSessionId) else {
                if self.scrubCommitToken == commitToken {
                    self.scrubCommitTask = nil
                }
                return
            }
            if shouldPlayAfterSeek && self.needsNativeAudioActivationAfterPausedRestore {
                await self.activateNativeAudioForPendingResumeIfNeeded()
                guard self.canFinishScrubCommit(expectedToken: commitToken, expectedSessionId: expectedSessionId) else {
                    if self.scrubCommitToken == commitToken {
                        self.scrubCommitTask = nil
                    }
                    return
                }
                self.needsNativeAudioActivationAfterPausedRestore = false
            }
            if self.scrubCommitToken == commitToken {
                self.scrubCommitTask = nil
            }
            if shouldPlayAfterSeek {
                if self.transport.state == .paused || self.transport.state == .loading {
                    self.transport.play()
                }
                if self.isForegroundActive && !self.transport.needsForegroundVideoRestore {
                    self.lastForegroundPlaybackWasPlaying = Self.isActiveTransportIntent(
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

    func resetScrubStateOnSessionChange() {
        ringHoldLoopTask?.cancel()
        ringHoldLoopTask = nil
        scrubPreviewLoopTask?.cancel()
        scrubPreviewLoopTask = nil
        pendingScrubPreviewTarget = nil
        compositorPreviewView?.clear()
        if isScrubbing {
            isScrubbing = false
        }
        if scrubState.previewImage != nil {
            scrubState.previewImage = nil
        }
        wasPlayingBeforeScrub = false
    }

    private func enqueueScrubPreview(at targetSeconds: Double) {
        pendingScrubPreviewTarget = targetSeconds
        guard scrubPreviewLoopTask == nil else { return }

        scrubPreviewLoopTask = Task { @MainActor [weak self] in
            defer { self?.scrubPreviewLoopTask = nil }

            while let self, !Task.isCancelled, self.isScrubbing, let requested = self.pendingScrubPreviewTarget {
                self.pendingScrubPreviewTarget = nil

                if self.engine.scrubPreviewDrawsInView {
                    if let compView = self.compositorPreviewView {
                        _ = await self.engine.showScrubPreview(atSeconds: requested, in: compView)
                    }
                } else if self.engine.supportsCacheBackedStills {
                    let still = await self.engine.scrubThumbnail(atSeconds: requested, maxWidth: 480)
                    guard !Task.isCancelled, self.isScrubbing else { return }
                    if self.scrubState.previewImage !== still {
                        self.scrubState.previewImage = still
                    }
                } else if self.scrubState.previewImage != nil {
                    self.scrubState.previewImage = nil
                }

                try? await Task.sleep(nanoseconds: 45_000_000)
            }
        }
    }
}
