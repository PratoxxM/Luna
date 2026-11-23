import SwiftUI
import AetherBridge

/// Pure subtitle placement rules preventing collisions with both bottom OSD
/// (`320 pt` clearance) and open quick-panel popovers (upper cinema safe zone `y = 84..168 pt`).
internal enum SubtitleOverlayLayout {
    struct VerticalPlacement: Equatable, Sendable {
        let relocateToTop: Bool
        let topInset: CGFloat
        let bottomInset: CGFloat
    }

    nonisolated static func verticalPlacement(
        isBottomBarVisible: Bool,
        isQuickPanelOpen: Bool,
        isNerdHUDVisible: Bool
    ) -> VerticalPlacement {
        if isQuickPanelOpen {
            return VerticalPlacement(
                relocateToTop: true,
                topInset: isNerdHUDVisible ? 168 : 84,
                bottomInset: 0
            )
        }
        return VerticalPlacement(
            relocateToTop: false,
            topInset: 72,
            bottomInset: isBottomBarVisible ? 320 : 74
        )
    }
}

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
    let comfort: ComfortPreferences
    var subtitleDelaySeconds: Double = 0
    var isBottomBarVisible: Bool = false
    var isQuickPanelOpen: Bool = false
    var isNerdHUDVisible: Bool = false

    @State private var clockBox = SubtitleClockBox()
    @State private var visibleCues: [SubtitleCue] = []
    @State private var tracks: [TrackInfo] = []
    @State private var activeTrackID: Int?
    @State private var videoFormat: VideoFormat = .sdr

    var body: some View {
        let placement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: isBottomBarVisible,
            isQuickPanelOpen: isQuickPanelOpen,
            isNerdHUDVisible: isNerdHUDVisible
        )

        GeometryReader { geo in
            if !isNativeSubtitleActive {
                let isHDR = (videoFormat != .sdr)
                let topCues = visibleCues.filter {
                    isTextCue($0) && (resolveVerticalSlot(for: $0.placement) == .top || (placement.relocateToTop && resolveVerticalSlot(for: $0.placement) == .bottom))
                }
                let centerCues = visibleCues.filter { isTextCue($0) && resolveVerticalSlot(for: $0.placement) == .center }
                let bottomCues = visibleCues.filter {
                    isTextCue($0) && !placement.relocateToTop && resolveVerticalSlot(for: $0.placement) == .bottom
                }
                let bitmapCues = visibleCues.filter { !isTextCue($0) }

                ZStack {
                    Color.clear

                    ForEach(bitmapCues) { cue in
                        renderBitmapCue(cue, containerSize: geo.size, isHDR: isHDR, placement: placement)
                    }

                    if !topCues.isEmpty {
                        stackedTextSlot(topCues, verticalSlot: .top, isHDR: isHDR, placement: placement)
                    }
                    if !centerCues.isEmpty {
                        stackedTextSlot(centerCues, verticalSlot: .center, isHDR: isHDR, placement: placement)
                    }
                    if !bottomCues.isEmpty {
                        stackedTextSlot(bottomCues, verticalSlot: .bottom, isHDR: isHDR, placement: placement)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .onReceive(engine.clock.$sourceTime) { time in
            clockBox.lastSourceTime = time
            recomputeVisibleCues(at: time)
        }
        .onReceive(engine.$subtitleCues) { nextCues in
            clockBox.cues = nextCues
            recomputeVisibleCues(at: clockBox.lastSourceTime, cueSource: nextCues)
        }
        .onReceive(engine.$subtitleTracks) { nextTracks in
            if tracks != nextTracks {
                tracks = nextTracks
            }
        }
        .onReceive(engine.$activeSubtitleTrackIndex) { nextID in
            if activeTrackID != nextID {
                activeTrackID = nextID
            }
        }
        .onReceive(engine.$videoFormat) { nextFormat in
            if videoFormat != nextFormat {
                videoFormat = nextFormat
            }
        }
        .onChange(of: subtitleDelaySeconds) { _, _ in
            recomputeVisibleCues(at: clockBox.lastSourceTime)
        }
    }

    private func recomputeVisibleCues(at sourceTime: Double, cueSource: [SubtitleCue]? = nil) {
        let activeCues = cueSource ?? clockBox.cues
        let delay = subtitleDelaySeconds != 0 ? subtitleDelaySeconds : engine.softwareSubtitleDelaySeconds
        let effectiveTime = sourceTime - delay
        let next = activeCues.filter { $0.startTime <= effectiveTime && effectiveTime < $0.endTime }
        let changed = next.count != visibleCues.count || zip(next, visibleCues).contains(where: { $0.id != $1.id })
        if changed {
            visibleCues = next
        }
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
        isHDR: Bool,
        placement: SubtitleOverlayLayout.VerticalPlacement
    ) -> some View {
        let alignment: Alignment = {
            switch verticalSlot {
            case .top: return .top
            case .center: return .center
            case .bottom: return .bottom
            }
        }()

        return VStack(spacing: 8) {
            ForEach(slotCues) { cue in
                renderTextCue(cue, isHDR: isHDR)
            }
        }
        .padding(.horizontal, 120)
        .padding(.top, verticalSlot == .top ? placement.topInset : 0)
        .padding(.bottom, verticalSlot == .bottom ? placement.bottomInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(.easeOut(duration: 0.16), value: placement)
    }

    @ViewBuilder
    private func renderTextCue(_ cue: SubtitleCue, isHDR: Bool) -> some View {
        let pointSize = comfort.subtitleFontSize.pointSize
        let boxAlpha = comfort.subtitleBoxOpacity.alpha

        switch cue.body {
        case .text(let plain):
            styledTextBox(
                content: Text(plain)
                    .font(LunaTheme.Font.subtitleCue(size: pointSize))
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
    private func renderBitmapCue(
        _ cue: SubtitleCue,
        containerSize: CGSize,
        isHDR: Bool,
        placement: SubtitleOverlayLayout.VerticalPlacement
    ) -> some View {
        if case .image(let bitmap) = cue.body {
            let baseRect = Self.computeBitmapFrame(
                position: bitmap.position,
                canvasSize: bitmap.canvasSize,
                containerSize: containerSize
            )
            let adjustedMidY: CGFloat = {
                if placement.relocateToTop, baseRect.midY > containerSize.height * 0.48 {
                    return max(baseRect.height / 2.0 + 24, placement.topInset + baseRect.height / 2.0)
                }
                let safeBottomY = containerSize.height - placement.bottomInset
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
            .shadow(color: LunaTheme.pureBlack.opacity(0.96), radius: 2, x: 0, y: 1)
            .shadow(color: LunaTheme.pureBlack.opacity(0.92), radius: 6, x: 0, y: 2)
            .padding(.horizontal, boxAlpha > 0 ? 26 : 12)
            .padding(.vertical, boxAlpha > 0 ? 10 : 4)
            .background {
                if boxAlpha > 0 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LunaTheme.pureBlack.opacity(boxAlpha))
                }
            }
    }

    private func buildAttributedString(
        from runs: [SubtitleTextRun],
        pointSize: CGFloat,
        isHDR: Bool
    ) -> AttributedString {
        var result = AttributedString()
        let mult = comfort.hdrSubtitlePreset.rgbComponents

        for run in runs {
            var part = AttributedString(run.text)
            let baseFont = LunaTheme.Font.subtitleCue(
                size: pointSize,
                weight: run.isBold ? .bold : .semibold
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

@MainActor
private final class SubtitleClockBox {
    var lastSourceTime: Double = 0
    var cues: [SubtitleCue] = []
}
