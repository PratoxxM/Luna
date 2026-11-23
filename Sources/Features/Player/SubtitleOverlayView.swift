import SwiftUI
import AetherBridge

/// Pure subtitle placement rules preventing collisions with bottom OSD (`320 pt`),
/// series continuity overlays (`.skipPrompt` `152 pt`, `.nextEpisodeCard` `268 pt`, or
/// relocated to top when bottom OSD + series card are visible simultaneously), open quick-panel
/// popovers, and `NerdHUDView` (`x = 90..830 pt`, `y = 42..330 pt`).
internal enum SubtitleOverlayLayout {
    static let nerdHUDProtectedRect = CGRect(x: 90, y: 42, width: 740, height: 288)

    struct VerticalPlacement: Equatable, Sendable {
        let relocateToTop: Bool
        let topInset: CGFloat
        let bottomInset: CGFloat
        let leadingInset: CGFloat
        let trailingInset: CGFloat

        init(
            relocateToTop: Bool,
            topInset: CGFloat,
            bottomInset: CGFloat,
            leadingInset: CGFloat = 120,
            trailingInset: CGFloat = 120
        ) {
            self.relocateToTop = relocateToTop
            self.topInset = topInset
            self.bottomInset = bottomInset
            self.leadingInset = leadingInset
            self.trailingInset = trailingInset
        }
    }

    nonisolated static func verticalPlacement(
        isBottomBarVisible: Bool,
        isQuickPanelOpen: Bool,
        isNerdHUDVisible: Bool,
        activeSeriesOverlay: ActiveSeriesOverlayKind = .none
    ) -> VerticalPlacement {
        if isQuickPanelOpen {
            if isNerdHUDVisible {
                return VerticalPlacement(
                    relocateToTop: true,
                    topInset: 72,
                    bottomInset: 0,
                    leadingInset: 856,
                    trailingInset: 90
                )
            }
            return VerticalPlacement(
                relocateToTop: true,
                topInset: 84,
                bottomInset: 0,
                leadingInset: 120,
                trailingInset: 120
            )
        }

        if isBottomBarVisible && activeSeriesOverlay != .none {
            return VerticalPlacement(
                relocateToTop: true,
                topInset: isNerdHUDVisible ? 340 : 84,
                bottomInset: 0,
                leadingInset: 120,
                trailingInset: 120
            )
        }

        let resolvedBottomInset: CGFloat = {
            if isBottomBarVisible {
                return 320
            }
            switch activeSeriesOverlay {
            case .none:
                return 74
            case .skipPrompt:
                return 152
            case .nextEpisodeCard:
                return 268
            }
        }()

        return VerticalPlacement(
            relocateToTop: false,
            topInset: isNerdHUDVisible ? 340 : 72,
            bottomInset: resolvedBottomInset,
            leadingInset: 120,
            trailingInset: 120
        )
    }
}

/// Leaf subtitle overlay subscribing exclusively to `engine.clock.$sourceTime`
/// so 10 Hz clock ticks never re-render the surrounding player UI.
struct SubtitleOverlayView: View {
    let engine: AetherEngine
    let comfort: ComfortPreferences
    var subtitleDelaySeconds: Double = 0
    var isBottomBarVisible: Bool = false
    var isQuickPanelOpen: Bool = false
    var isNerdHUDVisible: Bool = false
    var activeSeriesOverlay: ActiveSeriesOverlayKind = .none

    @State private var clockBox = SubtitleClockBox()
    @State private var visibleCues: [SubtitleCue] = []
    @State private var tracks: [TrackInfo] = []
    @State private var activeTrackID: Int?
    @State private var videoFormat: VideoFormat = .sdr

    var body: some View {
        let placement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: isBottomBarVisible,
            isQuickPanelOpen: isQuickPanelOpen,
            isNerdHUDVisible: isNerdHUDVisible,
            activeSeriesOverlay: activeSeriesOverlay
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
        .padding(.leading, verticalSlot == .top ? placement.leadingInset : 120)
        .padding(.trailing, verticalSlot == .top ? placement.trailingInset : 120)
        .padding(.top, verticalSlot == .top ? placement.topInset : 0)
        .padding(.bottom, verticalSlot == .bottom ? placement.bottomInset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(.easeOut(duration: 0.18), value: placement)
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
            let adjusted = Self.adjustedBitmapRect(
                baseRect: baseRect,
                containerSize: containerSize,
                placement: placement,
                isNerdHUDVisible: isNerdHUDVisible
            )

            Image(decorative: bitmap.cgImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .colorMultiply(comfort.hdrSubtitlePreset.bitmapMultiplyColor(isHDR: isHDR))
                .frame(width: max(1, adjusted.width), height: max(1, adjusted.height))
                .position(x: adjusted.midX, y: adjusted.midY)
                .animation(.easeOut(duration: 0.18), value: placement)
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

    /// Halved GPU subtitle shadow pass for `AppleTV14,1` 4K DV P7 FEL `.softwareHost` headroom:
    /// - When `boxAlpha > 0`, the dark rounded background box provides full contrast with **zero**
    ///   per-glyph offscreen blur passes.
    /// - When `boxAlpha == 0`, uses a single crisp `radius: 4` drop shadow instead of stacked passes.
    @ViewBuilder
    private func styledTextBox<Content: View>(
        content: Content,
        boxAlpha: Double
    ) -> some View {
        if boxAlpha > 0 {
            content
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LunaTheme.pureBlack.opacity(boxAlpha))
                }
        } else {
            content
                .multilineTextAlignment(.center)
                .shadow(color: LunaTheme.pureBlack.opacity(0.95), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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

    /// Lifts or relocates PGS/DVB bitmap subtitles cleanly above bottom OSD / series continuity
    /// cards (`placement.bottomInset`) and outside `NerdHUDView` (`x = 90..830, y = 42..330`).
    static func adjustedBitmapRect(
        baseRect: CGRect,
        containerSize: CGSize,
        placement: SubtitleOverlayLayout.VerticalPlacement,
        isNerdHUDVisible: Bool
    ) -> CGRect {
        let fw = max(1, containerSize.width)
        let fh = max(1, containerSize.height)
        var width = max(1, baseRect.width)
        var height = max(1, baseRect.height)
        var midX = baseRect.midX
        var midY = baseRect.midY

        let isRelocatedBottomCue = placement.relocateToTop && baseRect.midY > fh * 0.48
        let isTopZoneCue = isRelocatedBottomCue || baseRect.minY < placement.topInset

        if isTopZoneCue {
            if placement.leadingInset > 120 {
                let corridorMinX = placement.leadingInset
                let corridorMaxX = max(corridorMinX + 60, fw - placement.trailingInset)
                let corridorWidth = corridorMaxX - corridorMinX
                if width > corridorWidth {
                    let scale = corridorWidth / width
                    width *= scale
                    height *= scale
                }
                if isRelocatedBottomCue {
                    midX = (corridorMinX + corridorMaxX) * 0.5
                } else {
                    midX = min(max(corridorMinX + width * 0.5, midX), corridorMaxX - width * 0.5)
                }
            }
            if isRelocatedBottomCue {
                midY = max(height * 0.5 + 24, placement.topInset + height * 0.5)
            } else if isNerdHUDVisible && midY - height * 0.5 < placement.topInset && midX - width * 0.5 < 856 {
                midY = max(height * 0.5 + 24, placement.topInset + height * 0.5)
            }
        } else if placement.bottomInset > 74 {
            let safeBottomY = fh - placement.bottomInset
            if baseRect.maxY > safeBottomY {
                let shift = baseRect.maxY - safeBottomY
                midY = max(height * 0.5 + 24, baseRect.midY - shift)
            }
        }

        return CGRect(
            x: midX - width * 0.5,
            y: midY - height * 0.5,
            width: width,
            height: height
        )
    }
}

@MainActor
private final class SubtitleClockBox {
    var lastSourceTime: Double = 0
    var cues: [SubtitleCue] = []
}
