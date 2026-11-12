import SwiftUI
import CoreGraphics
import AetherBridge

/// Minimalist Nordic cinema OSD revealed on light touch/click and auto-hidden after 4.5s.
/// Clock-driven elements are isolated in leaf views so 10 Hz ticks never invalidate
/// surrounding buttons or video layers.
struct PlayerBottomBarView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let fallbackTitle: String
    let onOpenTopDrawer: () -> Void
    let onUserInteraction: () -> Void

    private var isPaused: Bool {
        viewModel.playbackPhase == .paused
    }

    var body: some View {
        let duration = viewModel.effectiveDurationSeconds

        VStack(spacing: 0) {
            // Top-right «Ferdig kl. HH:MM» pill
            HStack(alignment: .center) {
                if viewModel.isSwitchingSource {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Bytter kilde sømløst…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LunaTheme.amber)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.45), lineWidth: 1))
                }

                Spacer()

                if duration > 30 {
                    EndsAtClockPillLeafView(
                        engine: viewModel.engine,
                        duration: duration,
                        isPaused: isPaused
                    )
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 42)

            Spacer()

            // Bottom Liquid-Glass Transport & Chapter Timeline
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let seriesLine = seriesContextLine {
                            Text(seriesLine)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.amber)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(viewModel.activeSession?.item.title ?? fallbackTitle)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if !viewModel.chapters.isEmpty {
                                ActiveChapterLabelLeafView(
                                    engine: viewModel.engine,
                                    chapters: viewModel.chapters
                                )
                            }
                        }
                    }

                    Spacer()

                    // Live AV Format & Tier Badges
                    HStack(spacing: 10) {
                        ForEach(viewModel.activeFormatBadges, id: \.self) { badge in
                            formatBadgePill(badge)
                        }
                    }
                }

                TimelineScrubberLeafView(
                    engine: viewModel.engine,
                    duration: duration,
                    chapters: viewModel.chapters,
                    previewTargetOverride: viewModel.coalescedSeekPreviewTarget,
                    isPaused: isPaused,
                    onOpenTopDrawer: onOpenTopDrawer,
                    onUserInteraction: onUserInteraction
                )
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 36)
            .padding(.bottom, 46)
            .background(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.68),
                        Color.black.opacity(0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var seriesContextLine: String? {
        guard let item = viewModel.activeSession?.item else { return nil }
        if let series = item.seriesTitle, !series.isEmpty {
            if let s = item.season, let e = item.episode, s > 0, e > 0 {
                return String(format: "%@ · S%02dE%02d", series, s, e)
            }
            return series
        }
        return nil
    }

    private func formatBadgePill(_ text: String) -> some View {
        let isHighlight = text.contains("DV") || text.contains("HDR") || text.contains("Atmos") || text.contains("DTS:X")
        let isNvme = text.contains("NVMe")

        return Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(isNvme ? LunaTheme.emerald : (isHighlight ? LunaTheme.amber : LunaTheme.moonlight))
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isNvme
                            ? LunaTheme.emerald.opacity(0.45)
                            : (isHighlight ? LunaTheme.amber.opacity(0.45) : LunaTheme.moonlight.opacity(0.18)),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Isolated Leaf Views (10 Hz Clock Contained)

private struct EndsAtClockPillLeafView: View {
    let engine: AetherEngine
    let duration: Double
    let isPaused: Bool

    @State private var currentTime: Double = 0

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        let remaining = max(0, duration - currentTime)
        let finishDate = Date().addingTimeInterval(remaining)
        let clockStr = Self.formatter.string(from: finishDate)

        HStack(spacing: 8) {
            Image(systemName: isPaused ? "pause.circle.fill" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPaused ? LunaTheme.amber : LunaTheme.moonlight.opacity(0.8))
            Text("Ferdig kl. \(clockStr)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.moonlight.opacity(0.16), lineWidth: 1)
        )
        .onReceive(engine.clock.$currentTime) { currentTime = $0 }
    }
}

private struct ActiveChapterLabelLeafView: View {
    let engine: AetherEngine
    let chapters: [PlaybackChapter]

    @State private var currentTime: Double = 0

    var body: some View {
        if let active = chapters.first(where: { currentTime >= $0.startSeconds && currentTime < $0.endSeconds }) {
            Text("· \(active.title)")
                .font(.callout.weight(.medium))
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(1)
                .onReceive(engine.clock.$currentTime) { currentTime = $0 }
        } else {
            Color.clear
                .frame(width: 1, height: 1)
                .onReceive(engine.clock.$currentTime) { currentTime = $0 }
        }
    }
}

struct TimelineScrubberLeafView: View {
    let engine: AetherEngine
    let duration: Double
    let chapters: [PlaybackChapter]
    let previewTargetOverride: Double?
    let isPaused: Bool
    let onOpenTopDrawer: () -> Void
    let onUserInteraction: () -> Void

    @State private var currentTime: Double = 0
    @State private var bufferedTime: Double = 0
    @State private var scrubCursorTime: Double?
    @State private var scrubThumbnailImage: CGImage?
    @State private var thumbnailTask: Task<Void, Never>?

    var body: some View {
        let effectiveDuration = max(duration, currentTime, 1)
        let displayTime = scrubCursorTime ?? previewTargetOverride ?? currentTime
        let progressRatio = min(1.0, max(0.0, displayTime / effectiveDuration))
        let bufferRatio = min(1.0, max(0.0, bufferedTime / effectiveDuration))

        VStack(alignment: .leading, spacing: 12) {
            // Optional pause scrub preview thumbnail & chapter card
            if isPaused, let cursor = scrubCursorTime {
                pauseScrubPreviewCard(at: cursor, duration: effectiveDuration)
            }

            // Timeline bar with chapter tick marks
            GeometryReader { geo in
                let totalWidth = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))

                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: totalWidth * CGFloat(bufferRatio))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [LunaTheme.amber, LunaTheme.amberDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: totalWidth * CGFloat(progressRatio))

                    // Chapter tick markers
                    ForEach(chapters) { ch in
                        if ch.startSeconds > 2 && ch.startSeconds < effectiveDuration - 2 {
                            let xPos = totalWidth * CGFloat(ch.startSeconds / effectiveDuration)
                            Rectangle()
                                .fill(Color.black.opacity(0.78))
                                .frame(width: 2.5, height: isPaused ? 12 : 8)
                                .offset(x: xPos)
                        }
                    }

                    // Playhead dot when paused or scrubbing
                    if isPaused || previewTargetOverride != nil {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: LunaTheme.amber.opacity(0.75), radius: 8)
                            .offset(x: max(0, min(totalWidth - 18, totalWidth * CGFloat(progressRatio) - 9)))
                    }
                }
            }
            .frame(height: isPaused ? 12 : 8)

            // Timestamps & contextual controls
            HStack(alignment: .center) {
                Text(Self.formatSeconds(displayTime))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(LunaTheme.moonlight)

                Spacer()

                if !isPaused {
                    Text("Klikk ◀ -10s / +30s ▶ · Sveip ned for Lyd, Tekst, Kilder & Kapitler")
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted.opacity(0.82))
                }

                Spacer()

                Text("-\(Self.formatSeconds(max(0, effectiveDuration - displayTime)))")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(LunaTheme.muted)
            }

            // Pause-mode interactive chapter & scrub strip
            if isPaused {
                HStack(spacing: 16) {
                    LunaPillButton(
                        "",
                        systemImage: "play.fill",
                        prominence: .primaryAmber
                    ) {
                        onUserInteraction()
                        if let target = scrubCursorTime {
                            scrubCursorTime = nil
                            scrubThumbnailImage = nil
                            Task {
                                await engine.seek(to: target, exact: true)
                                engine.play()
                            }
                        } else {
                            engine.play()
                        }
                    }

                    LunaPillButton("-10s", systemImage: "gobackward.10", prominence: .subtleChip) {
                        stepScrub(by: -10, duration: effectiveDuration)
                    }

                    LunaPillButton("+30s", systemImage: "goforward.30", prominence: .subtleChip) {
                        stepScrub(by: 30, duration: effectiveDuration)
                    }

                    if !chapters.isEmpty {
                        LunaPillButton("Forrige kapittel", systemImage: "backward.end.fill", prominence: .subtleChip) {
                            jumpChapter(direction: -1, duration: effectiveDuration)
                        }

                        LunaPillButton("Neste kapittel", systemImage: "forward.end.fill", prominence: .subtleChip) {
                            jumpChapter(direction: 1, duration: effectiveDuration)
                        }
                    }

                    Spacer()

                    LunaPillButton("Lyd, Tekst & Kilder", systemImage: "slider.horizontal.3", prominence: .glassPill) {
                        onUserInteraction()
                        onOpenTopDrawer()
                    }
                }
                .padding(.top, 4)
            }
        }
        .onChange(of: isPaused) { _, paused in
            if !paused {
                thumbnailTask?.cancel()
                scrubCursorTime = nil
                scrubThumbnailImage = nil
            }
        }
        .onReceive(engine.clock.$currentTime) { currentTime = $0 }
        .onReceive(engine.clock.$bufferedPosition) { bufferedTime = $0 }
    }

    private func pauseScrubPreviewCard(at target: Double, duration: Double) -> some View {
        let matchedChapter = chapters.first { target >= $0.startSeconds && target < $0.endSeconds }
        return HStack(spacing: 16) {
            if let cg = scrubThumbnailImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 210, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(LunaTheme.amber.opacity(0.5), lineWidth: 1.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(Self.formatSeconds(target))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(LunaTheme.amber)
                if let ch = matchedChapter {
                    Text(ch.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Text("Trykk ▶ for å spille herfra")
                    .font(.caption)
                    .foregroundStyle(LunaTheme.muted)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LunaTheme.amber.opacity(0.35), lineWidth: 1)
        )
    }

    private func stepScrub(by delta: Double, duration: Double) {
        onUserInteraction()
        let base = scrubCursorTime ?? currentTime
        let next = min(max(0, base + delta), max(0, duration - 0.5))
        scrubCursorTime = next
        requestScrubPreviewThumbnail(at: next)
    }

    private func jumpChapter(direction: Int, duration: Double) {
        onUserInteraction()
        let anchor = scrubCursorTime ?? currentTime
        let targetChapter: PlaybackChapter?
        if direction > 0 {
            targetChapter = chapters.first { $0.startSeconds > anchor + 1.5 }
        } else {
            targetChapter = chapters.last { $0.startSeconds < anchor - 3.0 } ?? chapters.first
        }
        guard let ch = targetChapter else { return }
        scrubCursorTime = min(max(0, ch.startSeconds), duration)
        requestScrubPreviewThumbnail(at: ch.startSeconds)
    }

    private func requestScrubPreviewThumbnail(at seconds: Double) {
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            if let cg = await engine.scrubThumbnail(atSeconds: seconds, maxWidth: 384) {
                guard !Task.isCancelled else { return }
                scrubThumbnailImage = cg
            }
        }
    }

    static func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
