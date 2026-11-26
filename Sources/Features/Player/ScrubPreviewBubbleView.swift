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
        guard delta.isFinite,
              let absTotal = Int(exactly: abs(delta).rounded()) else {
            return "\(sign)--:--"
        }
        let h = absTotal / 3600
        let m = (absTotal % 3600) / 60
        let s = absTotal % 60
        if h > 0 {
            return "\(sign)\(h):" + String(format: "%02d:%02d", m, s)
        }
        return "\(sign)" + String(format: "%d:%02d", m, s)
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
