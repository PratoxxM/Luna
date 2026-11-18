import SwiftUI
import UIKit
import AVFoundation
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

    static let frameWidth: CGFloat = 236
    static let compactWidth: CGFloat = 212

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
                    .frame(width: 208, height: 117)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let cg = previewImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 208, height: 117)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 6) {
                Text(TimelineScrubberLeafView.formatSeconds(targetSeconds))
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                let delta = targetSeconds - originSeconds
                if abs(delta) >= 1.0 {
                    Text(Self.formatSignedDelta(delta))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(LunaTheme.amber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            if let chapterTitle, !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: preferredWidth - 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: preferredWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LunaTheme.cinemaGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LunaTheme.amber.opacity(0.45), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    private static func formatSignedDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : "-"
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

    func updateTouchScrub(deltaPoints: CGFloat, velocityPointsPerSec: CGFloat) {
        guard isScrubbing else { return }
        let dur = max(1, effectiveDurationSeconds)
        let durationScale = min(1.45, max(0.65, dur / 5400.0))
        let speed = Double(abs(velocityPointsPerSec))

        let secondsPerPoint: Double
        if speed <= 260 {
            secondsPerPoint = 0.24
        } else if speed <= 950 {
            let t = (speed - 260.0) / 690.0
            secondsPerPoint = (0.24 + t * 1.06) * durationScale
        } else {
            let t = min(1.0, (speed - 950.0) / 1400.0)
            secondsPerPoint = min(3.4, (1.30 + t * 1.55) * durationScale)
        }

        let rawNext = scrubState.targetSeconds + Double(deltaPoints) * secondsPerPoint
        let clamped = min(max(0, rawNext), max(0, dur - 0.5))
        scrubState.targetSeconds = clamped
        enqueueScrubPreview(at: clamped)
    }

    func stepTouchScrub(by deltaSeconds: Double) {
        guard isScrubbing else { return }
        let dur = max(1, effectiveDurationSeconds)
        let clamped = min(max(0, scrubState.targetSeconds + deltaSeconds), max(0, dur - 0.5))
        scrubState.targetSeconds = clamped
        enqueueScrubPreview(at: clamped)
    }

    func commitTouchScrub() {
        guard isScrubbing else { return }
        let target = scrubState.targetSeconds
        resetScrubStateOnSessionChange()
        cancelPendingPausedRestoreResume()
        cancelPendingScrubCommit()
        scrubCommitToken &+= 1
        let commitToken = scrubCommitToken
        let expectedSessionId = activeSession?.sessionId

        scrubCommitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.transport.seek(to: target, exact: true)
            guard self.canFinishScrubCommit(expectedToken: commitToken, expectedSessionId: expectedSessionId) else {
                if self.scrubCommitToken == commitToken {
                    self.scrubCommitTask = nil
                }
                return
            }
            if self.needsNativeAudioActivationAfterPausedRestore {
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

    func cancelTouchScrub() {
        guard isScrubbing else { return }
        cancelPendingScrubCommit()
        let shouldResume = wasPlayingBeforeScrub
        resetScrubStateOnSessionChange()
        if shouldResume {
            transport.play()
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
                    let still = await self.engine.scrubThumbnail(atSeconds: requested, maxWidth: 320)
                    guard !Task.isCancelled, self.isScrubbing else { return }
                    self.scrubState.previewImage = still
                } else if self.scrubState.previewImage != nil {
                    self.scrubState.previewImage = nil
                }

                try? await Task.sleep(nanoseconds: 45_000_000)
            }
        }
    }
}
