import SwiftUI
import CoreGraphics
import AetherBridge

/// Minimalist evening-cinema transport overlay.
/// Contains zero focusable buttons so `SiriRemoteTouchSurface` retains uninterrupted
/// touch-scrubbing and clickpad control across playing, paused, and scrubbing states.
struct PlayerBottomBarView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let fallbackTitle: String

    private var isPaused: Bool {
        viewModel.playbackPhase == .paused
    }

    var body: some View {
        let duration = viewModel.effectiveDurationSeconds

        VStack(spacing: 0) {
            if viewModel.isSwitchingSource {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Bytter kilde…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.amber)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(LunaTheme.cinemaGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.45), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 42)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let seriesLine = seriesContextLine {
                            Text(seriesLine)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.amber)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            if isPaused && !viewModel.isScrubbing {
                                Image(systemName: "pause.fill")
                                    .font(.callout.weight(.bold))
                                    .foregroundStyle(LunaTheme.amber)
                            }

                            Text(viewModel.activeSession?.item.title ?? fallbackTitle)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if !viewModel.chapters.isEmpty && !viewModel.isScrubbing {
                                ActiveChapterLabelLeafView(
                                    engine: viewModel.engine,
                                    chapters: viewModel.chapters
                                )
                            }
                        }
                    }

                    Spacer()

                    EndsAtAndFormatLeafView(
                        engine: viewModel.engine,
                        duration: duration,
                        formatSummary: compactFormatSummary
                    )
                }

                TimelineScrubberLeafView(
                    viewModel: viewModel,
                    scrubState: viewModel.scrubState,
                    engine: viewModel.engine,
                    duration: duration,
                    isPaused: isPaused
                )
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 56)
            .padding(.bottom, 44)
            .background(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.62),
                        Color.black.opacity(0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .allowsHitTesting(false)
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

    private var compactFormatSummary: String {
        let video = viewModel.videoFormatBadge
        let audio = viewModel.audioFormatBadge
        if audio.isEmpty {
            return video
        }
        return "\(video) · \(audio)"
    }
}

// MARK: - Isolated Clock Leaf Views (10 Hz Contained)

private struct EndsAtAndFormatLeafView: View {
    let engine: AetherEngine
    let duration: Double
    let formatSummary: String

    @State private var currentTime: Double = 0
    @State private var lastTimeBucket: Int = -1

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        let text: String = {
            guard duration > 30 else { return formatSummary }
            let remaining = max(0, duration - currentTime)
            let finishClock = Self.formatter.string(from: Date().addingTimeInterval(remaining))
            return "Ferdig \(finishClock) · \(formatSummary)"
        }()

        Text(text)
            .font(.callout.weight(.medium).monospacedDigit())
            .foregroundStyle(LunaTheme.muted)
            .lineLimit(1)
            .onReceive(engine.clock.$currentTime) { t in
                let bucket = Int(max(0, t) / 5.0)
                if bucket != lastTimeBucket {
                    lastTimeBucket = bucket
                    currentTime = t
                }
            }
    }
}

private struct ActiveChapterLabelLeafView: View {
    let engine: AetherEngine
    let chapters: [PlaybackChapter]

    @State private var currentTime: Double = 0

    var body: some View {
        Group {
            if let active = chapters.first(where: { currentTime >= $0.startSeconds && currentTime < $0.endSeconds }) {
                Text("· \(active.title)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .onReceive(engine.clock.$currentTime) { t in
            guard !chapters.isEmpty else { return }
            if abs(t - currentTime) >= 0.5 || t < 1.0 {
                currentTime = t
            }
        }
    }
}

struct TimelineScrubberLeafView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var scrubState: PlayerScrubState
    let engine: AetherEngine
    let duration: Double
    let isPaused: Bool

    @State private var currentTime: Double = 0
    @State private var bufferedTime: Double = 0

    var body: some View {
        let effectiveDuration = max(duration, currentTime, 1)
        let isScrubbing = viewModel.isScrubbing
        let displayTime: Double = {
            if isScrubbing {
                return scrubState.targetSeconds
            }
            if let seekOverride = viewModel.coalescedSeekPreviewTarget {
                return seekOverride
            }
            return currentTime
        }()
        let isExpanded = isScrubbing || isPaused || viewModel.coalescedSeekPreviewTarget != nil
        let barHeight: CGFloat = isExpanded ? 10 : 6
        let progressRatio = min(1.0, max(0.0, displayTime / effectiveDuration))
        let bufferRatio = min(1.0, max(0.0, bufferedTime / effectiveDuration))

        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let playheadX = totalWidth * CGFloat(progressRatio)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))

                    Capsule()
                        .fill(Color.white.opacity(0.30))
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

                    // Subtle chapter tick marks
                    ForEach(viewModel.chapters) { ch in
                        if ch.startSeconds > 2 && ch.startSeconds < effectiveDuration - 2 {
                            let xPos = totalWidth * CGFloat(ch.startSeconds / effectiveDuration)
                            Rectangle()
                                .fill(Color.black.opacity(0.76))
                                .frame(width: 2.5, height: barHeight)
                                .offset(x: xPos)
                        }
                    }

                    if isExpanded {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: LunaTheme.amber.opacity(0.82), radius: isScrubbing ? 12 : 7)
                            .offset(x: max(0, min(totalWidth - 18, playheadX - 9)))
                    }
                }
                .frame(height: barHeight)
                .overlay(alignment: .bottomLeading) {
                    if isScrubbing {
                        let chapterTitle = viewModel.activeChapter(at: displayTime)?.title
                        let bubble = ScrubPreviewBubbleView(
                            targetSeconds: displayTime,
                            originSeconds: scrubState.originSeconds,
                            chapterTitle: chapterTitle,
                            previewImage: scrubState.previewImage,
                            drawsInCompositorView: engine.scrubPreviewDrawsInView,
                            onMountCompositorView: { compView in
                                viewModel.attachCompositorPreviewView(compView)
                            }
                        )
                        let bubbleWidth = bubble.preferredWidth
                        let clampedOriginX = min(
                            max(0, playheadX - bubbleWidth / 2.0),
                            max(0, totalWidth - bubbleWidth)
                        )
                        bubble
                            .offset(x: clampedOriginX, y: -22)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: barHeight)
            .animation(.easeOut(duration: 0.16), value: isExpanded)

            HStack(alignment: .center) {
                Text(Self.formatSeconds(displayTime))
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(isScrubbing ? LunaTheme.amber : LunaTheme.moonlight)

                Spacer()

                if isScrubbing {
                    Text("Klikk for å spille herfra · Menu avbryter")
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                }

                Spacer()

                Text("-\(Self.formatSeconds(max(0, effectiveDuration - displayTime)))")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(LunaTheme.muted)
            }
        }
        .onReceive(engine.clock.$currentTime) { currentTime = $0 }
        .onReceive(engine.clock.$bufferedPosition) { bufferedTime = $0 }
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
