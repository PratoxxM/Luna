import SwiftUI
import AetherBridge

/// Leaf subtitle overlay subscribing exclusively to `engine.clock.$sourceTime`
/// so 10 Hz clock ticks never re-render the surrounding player UI.
///
/// Implements HDR/Dolby Vision OLED luminance comfort:
///  - Text & ASS cues keep a 95% opaque black outline/shadow while scaling only
///    foreground glyph RGB to a warm-white luminance target (`75 % Varmhvit`, etc.).
///  - PGS bitmap cues map proportionally within `bitmap.canvasSize` and apply GPU
///    `.colorMultiply(...)`, keeping black `(0,0,0,α)` borders 100% jet-black while
///    dimming bright white letter fills in dark HDR/DV scenes.
struct SubtitleOverlayView: View {
    let engine: AetherEngine
    @ObservedObject var comfort: ComfortPreferences
    var isBottomBarVisible: Bool = false

    @State private var sourceTime: Double = 0
    @State private var cues: [SubtitleCue] = []
    @State private var tracks: [TrackInfo] = []
    @State private var activeTrackID: Int?
    @State private var videoFormat: VideoFormat = .sdr

    var body: some View {
        GeometryReader { geo in
            if !isNativeSubtitleActive {
                let effectiveTime = sourceTime - engine.softwareSubtitleDelaySeconds
                let visible = cues.filter { $0.startTime <= effectiveTime && effectiveTime < $0.endTime }
                let isHDR = (videoFormat != .sdr)
                let topCues = visible.filter { isTextCue($0) && resolveVerticalSlot(for: $0.placement) == .top }
                let centerCues = visible.filter { isTextCue($0) && resolveVerticalSlot(for: $0.placement) == .center }
                let bottomCues = visible.filter { isTextCue($0) && resolveVerticalSlot(for: $0.placement) == .bottom }
                let bitmapCues = visible.filter { !isTextCue($0) }

                ZStack {
                    Color.clear

                    ForEach(bitmapCues) { cue in
                        renderBitmapCue(cue, containerSize: geo.size, isHDR: isHDR)
                    }

                    if !topCues.isEmpty {
                        stackedTextSlot(topCues, verticalSlot: .top, isHDR: isHDR)
                    }
                    if !centerCues.isEmpty {
                        stackedTextSlot(centerCues, verticalSlot: .center, isHDR: isHDR)
                    }
                    if !bottomCues.isEmpty {
                        stackedTextSlot(bottomCues, verticalSlot: .bottom, isHDR: isHDR)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .onReceive(engine.clock.$sourceTime) { sourceTime = $0 }
        .onReceive(engine.$subtitleCues) { cues = $0 }
        .onReceive(engine.$subtitleTracks) { tracks = $0 }
        .onReceive(engine.$activeSubtitleTrackIndex) { activeTrackID = $0 }
        .onReceive(engine.$videoFormat) { videoFormat = $0 }
    }

    private var isNativeSubtitleActive: Bool {
        guard let activeTrackID,
              let track = tracks.first(where: { $0.id == activeTrackID }) else {
            return false
        }
        return track.isNativelyRenderedSubtitle
    }

    private func isTextCue(_ cue: SubtitleCue) -> Bool {
        switch cue.body {
        case .text, .richText:
            return true
        case .image:
            return false
        }
    }

    private func stackedTextSlot(
        _ slotCues: [SubtitleCue],
        verticalSlot: VerticalSlot,
        isHDR: Bool
    ) -> some View {
        let alignment: Alignment = {
            switch verticalSlot {
            case .top: return .top
            case .center: return .center
            case .bottom: return .bottom
            }
        }()
        let bottomInset: CGFloat = isBottomBarVisible ? 204 : 74

        return VStack(spacing: 8) {
            ForEach(slotCues) { cue in
                renderTextCue(cue, isHDR: isHDR)
            }
        }
        .padding(.horizontal, 120)
        .padding(.top, verticalSlot == .top ? 72 : 0)
        .padding(.bottom, verticalSlot == .bottom ? bottomInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(.easeOut(duration: 0.16), value: isBottomBarVisible)
    }

    @ViewBuilder
    private func renderTextCue(_ cue: SubtitleCue, isHDR: Bool) -> some View {
        let pointSize = comfort.subtitleFontSize.pointSize
        let boxAlpha = comfort.subtitleBoxOpacity.alpha

        switch cue.body {
        case .text(let plain):
            styledTextBox(
                content: Text(plain)
                    .font(.system(size: pointSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(comfort.hdrSubtitlePreset.foregroundColor(isHDR: isHDR)),
                boxAlpha: boxAlpha
            )

        case .richText(let runs):
            styledTextBox(
                content: Text(buildAttributedString(from: runs, pointSize: pointSize, isHDR: isHDR)),
                boxAlpha: boxAlpha
            )

        case .image:
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderBitmapCue(_ cue: SubtitleCue, containerSize: CGSize, isHDR: Bool) -> some View {
        if case .image(let bitmap) = cue.body {
            let baseRect = Self.computeBitmapFrame(
                position: bitmap.position,
                canvasSize: bitmap.canvasSize,
                containerSize: containerSize
            )
            let safeBottomY = containerSize.height - 204
            let adjustedMidY: CGFloat = {
                guard isBottomBarVisible, baseRect.maxY > safeBottomY else {
                    return baseRect.midY
                }
                let shift = baseRect.maxY - safeBottomY
                return max(baseRect.height / 2.0 + 24, baseRect.midY - shift)
            }()

            Image(decorative: bitmap.cgImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .colorMultiply(comfort.hdrSubtitlePreset.bitmapMultiplyColor(isHDR: isHDR))
                .frame(width: max(1, baseRect.width), height: max(1, baseRect.height))
                .position(x: baseRect.midX, y: adjustedMidY)
        }
    }

    private enum VerticalSlot: Equatable {
        case top
        case center
        case bottom
    }

    private func resolveVerticalSlot(for placement: SubtitleTextPlacement?) -> VerticalSlot {
        if let align = placement?.alignment {
            if (7...9).contains(align) { return .top }
            if (4...6).contains(align) { return .center }
        }
        if let pos = placement?.position, pos.y >= 0, pos.y <= 0.30 {
            return .top
        }
        return .bottom
    }

    private func styledTextBox<Content: View>(
        content: Content,
        boxAlpha: Double
    ) -> some View {
        content
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.96), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.92), radius: 6, x: 0, y: 2)
            .padding(.horizontal, boxAlpha > 0 ? 26 : 12)
            .padding(.vertical, boxAlpha > 0 ? 10 : 4)
            .background {
                if boxAlpha > 0 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(boxAlpha))
                }
            }
    }

    private func buildAttributedString(
        from runs: [SubtitleTextRun],
        pointSize: CGFloat,
        isHDR: Bool
    ) -> AttributedString {
        var result = AttributedString()
        let mult = isHDR ? comfort.hdrSubtitlePreset.hdrRGB : (r: 1.0, g: 1.0, b: 1.0)

        for run in runs {
            var part = AttributedString(run.text)
            let baseFont = Font.system(
                size: pointSize,
                weight: run.isBold ? .bold : .semibold,
                design: .rounded
            )
            part.font = run.isItalic ? baseFont.italic() : baseFont

            if let c = run.color {
                part.foregroundColor = Color(
                    red: (Double(c.r) / 255.0) * mult.r,
                    green: (Double(c.g) / 255.0) * mult.g,
                    blue: (Double(c.b) / 255.0) * mult.b
                )
            } else {
                part.foregroundColor = comfort.hdrSubtitlePreset.foregroundColor(isHDR: isHDR)
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

    /// Matches `SubtitleFrameCompositor.imageRect` so cropped Blu-ray / Remux PGS canvases
    /// align width-wise and center vertically on 16:9 displays.
    static func computeBitmapFrame(
        position: CGRect,
        canvasSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        let fw = max(1, containerSize.width)
        let fh = max(1, containerSize.height)
        guard canvasSize != .zero, canvasSize.width > 0 else {
            return CGRect(
                x: position.minX * fw,
                y: position.minY * fh,
                width: position.width * fw,
                height: position.height * fh
            )
        }
        let px = position.minX * canvasSize.width
        let py = position.minY * canvasSize.height
        let scale = fw / canvasSize.width
        let frameCenterY = fh / 2.0
        let canvasCenterY = canvasSize.height / 2.0
        return CGRect(
            x: px * scale,
            y: frameCenterY + (py - canvasCenterY) * scale,
            width: position.width * canvasSize.width * scale,
            height: position.height * canvasSize.height * scale
        )
    }
}
