import SwiftUI
import AetherBridge

/// Leaf subtitle overlay subscribing exclusively to `engine.clock.$sourceTime`
/// so 10 Hz clock ticks never re-render the rest of the player hierarchy.
struct SubtitleOverlayView: View {
    let engine: AetherEngine

    @State private var sourceTime: Double = 0
    @State private var cues: [SubtitleCue] = []
    @State private var tracks: [TrackInfo] = []
    @State private var activeTrackID: Int?

    var body: some View {
        GeometryReader { geo in
            if !isNativeSubtitleActive {
                let effectiveTime = sourceTime - engine.softwareSubtitleDelaySeconds
                let visible = cues.filter { $0.startTime <= effectiveTime && effectiveTime < $0.endTime }

                ZStack(alignment: .bottom) {
                    Color.clear

                    ForEach(visible) { cue in
                        renderCue(cue, containerSize: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .onReceive(engine.clock.$sourceTime) { sourceTime = $0 }
        .onReceive(engine.$subtitleCues) { cues = $0 }
        .onReceive(engine.$subtitleTracks) { tracks = $0 }
        .onReceive(engine.$activeSubtitleTrackIndex) { activeTrackID = $0 }
    }

    private var isNativeSubtitleActive: Bool {
        guard let activeTrackID,
              let track = tracks.first(where: { $0.id == activeTrackID }) else {
            return false
        }
        return track.isNativelyRenderedSubtitle
    }

    @ViewBuilder
    private func renderCue(_ cue: SubtitleCue, containerSize: CGSize) -> some View {
        switch cue.body {
        case .text(let plain):
            Text(plain)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.95), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 120)
                .padding(.bottom, 74)

        case .richText(let runs):
            Text(buildAttributedString(from: runs))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.95), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 120)
                .padding(.bottom, 74)

        case .image(let bitmap):
            let rect = bitmap.position
            let w = max(1, containerSize.width * rect.width)
            let h = max(1, containerSize.height * rect.height)
            let cx = containerSize.width * rect.midX
            let cy = containerSize.height * rect.midY

            Image(decorative: bitmap.cgImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
                .position(x: cx, y: cy)
        }
    }

    private func buildAttributedString(from runs: [SubtitleTextRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            if let c = run.color {
                part.foregroundColor = Color(
                    red: Double(c.r) / 255.0,
                    green: Double(c.g) / 255.0,
                    blue: Double(c.b) / 255.0
                )
            } else {
                part.foregroundColor = .white
            }
            if run.isUnderlined {
                part.underlineStyle = .single
            }
            if run.isStruckThrough {
                part.strikethroughStyle = .single
            }
            result.append(part)
        }
        return result
    }
}
