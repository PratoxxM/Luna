import SwiftUI
import CoreGraphics
import AetherBridge

internal enum TimelineClockBucketer {
    /// 0.5 s buckets (2 Hz max while playing, 0 Hz when paused) so 10 Hz engine clock ticks
    /// never trigger unnecessary SwiftUI layout passes on the player timeline.
    nonisolated static func timeBucket(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return Int((seconds * 2.0).rounded(.down))
    }

    /// 2.0 s buckets (0.5 Hz max) for the subtle background forward-buffer bar.
    nonisolated static func bufferBucket(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return Int((seconds / 2.0).rounded(.down))
    }
}

/// Minimalist evening-cinema transport overlay.
/// Contains zero focusable buttons so `SiriRemoteTouchSurface` retains uninterrupted
/// touch-scrubbing and clickpad control across playing, paused, and scrubbing states.
struct PlayerBottomBarView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let fallbackRequest: PlaybackLaunchRequest

    private var isPaused: Bool {
        viewModel.playbackPhase == .paused
    }

    private var titleDisplay: (seriesLine: String?, titleLine: String) {
        EpisodeTitleFormatter.bottomBarLabels(
            sessionItem: viewModel.activeSession?.item,
            request: viewModel.currentRequest ?? fallbackRequest
        )
    }

    var body: some View {
        let duration = viewModel.effectiveDurationSeconds

        VStack(spacing: 0) {
            if viewModel.isSwitchingSource {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Bytter kilde…")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.moonlight)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(LunaTheme.cinemaGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 42)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if let seriesLine = titleDisplay.seriesLine {
                                Text(seriesLine)
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.moonlight)
                                    .lineLimit(1)
                            }

                            if !viewModel.chapters.isEmpty && !viewModel.isScrubbing {
                                ActiveChapterLabelLeafView(
                                    engine: viewModel.engine,
                                    chapters: viewModel.chapters,
                                    hasLeadingSeriesLine: titleDisplay.seriesLine != nil
                                )
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            if isPaused && !viewModel.isScrubbing {
                                Image(systemName: "pause.fill")
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.pauseWarmLine)
                            }

                            Text(titleDisplay.titleLine)
                                .font(LunaTheme.Font.sectionTitle)
                                .foregroundStyle(LunaTheme.linen)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    EndsAtLeafView(
                        engine: viewModel.engine,
                        duration: duration
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
            .background {
                LinearGradient(
                    colors: [
                        Color.clear,
                        LunaTheme.pureBlack.opacity(0.58),
                        LunaTheme.pureBlack.opacity(0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: [.bottom, .horizontal])
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Isolated & Bucketed Clock Leaf Views

private struct EndsAtLeafView: View {
    let engine: AetherEngine
    let duration: Double

    @State private var currentTime: Double = 0
    @State private var lastTimeBucket: Int = -1

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "HH.mm"
        return f
    }()

    var body: some View {
        Group {
            if duration > 30 {
                let remaining = max(0, duration - currentTime)
                let finishClock = Self.formatter.string(from: Date().addingTimeInterval(remaining))
                Text("Ferdig kl. \(finishClock)")
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            }
        }
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
    let hasLeadingSeriesLine: Bool

    @State private var currentTime: Double = 0

    var body: some View {
        Group {
            if let active = chapters.first(where: { currentTime >= $0.startSeconds && currentTime < $0.endSeconds }) {
                Text(hasLeadingSeriesLine ? "· \(active.title)" : active.title)
                    .font(LunaTheme.Font.subtitle)
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
    @State private var lastTimeBucket: Int = -1
    @State private var bufferedTime: Double = 0
    @State private var lastBufferBucket: Int = -1
    @State private var showFirstTimeScrubHint: Bool = false

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
        let barHeight: CGFloat = isExpanded ? 7 : 5
        let progressRatio = min(1.0, max(0.0, displayTime / effectiveDuration))
        let bufferRatio = min(1.0, max(0.0, bufferedTime / effectiveDuration))

        VStack(alignment: .leading, spacing: 11) {
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let playheadX = totalWidth * CGFloat(progressRatio)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LunaTheme.warmBorderBase.opacity(0.16))

                    Capsule()
                        .fill(LunaTheme.warmBorderBase.opacity(0.28))
                        .frame(width: totalWidth * CGFloat(bufferRatio))

                    Capsule()
                        .fill(
                            isScrubbing
                                ? AnyShapeStyle(LunaTheme.primaryAmberGradient)
                                : AnyShapeStyle(LunaTheme.pauseWarmLine)
                        )
                        .frame(width: totalWidth * CGFloat(progressRatio))

                    ForEach(viewModel.chapters) { ch in
                        if ch.startSeconds > 2 && ch.startSeconds < effectiveDuration - 2 {
                            let xPos = totalWidth * CGFloat(ch.startSeconds / effectiveDuration)
                            Rectangle()
                                .fill(LunaTheme.pureBlack.opacity(0.76))
                                .frame(width: 2.0, height: barHeight)
                                .offset(x: xPos)
                        }
                    }

                    if isExpanded {
                        let knobDiameter: CGFloat = isScrubbing ? 15 : 13
                        Circle()
                            .fill(isScrubbing ? LunaTheme.amber : LunaTheme.linen)
                            .frame(width: knobDiameter, height: knobDiameter)
                            .offset(x: max(0, min(totalWidth - knobDiameter, playheadX - knobDiameter * 0.5)))
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
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(isScrubbing ? LunaTheme.amber : LunaTheme.moonlight)

                Spacer()

                if isScrubbing {
                    Text("Klikk for å spille herfra")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.muted)
                } else if showFirstTimeScrubHint {
                    Text("Sveip på styreflaten for å spole · Sveip ned for valg")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.muted)
                }

                Spacer()

                Text("−\(Self.formatSeconds(max(0, effectiveDuration - displayTime)))")
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(LunaTheme.muted)
            }
        }
        .onAppear {
            let initialTime = max(0, engine.currentTime)
            currentTime = initialTime
            lastTimeBucket = TimelineClockBucketer.timeBucket(initialTime)
            let initialBuf = max(0, engine.bufferedPosition)
            bufferedTime = initialBuf
            lastBufferBucket = TimelineClockBucketer.bufferBucket(initialBuf)
            let seenCount = UserDefaults.standard.integer(forKey: SideloadSafeStorage.playerScrubHintCountKey)
            if seenCount < 3 {
                showFirstTimeScrubHint = true
                UserDefaults.standard.set(seenCount + 1, forKey: SideloadSafeStorage.playerScrubHintCountKey)
            }
        }
        .onReceive(engine.clock.$currentTime) { t in
            let bucket = TimelineClockBucketer.timeBucket(t)
            if bucket != lastTimeBucket {
                lastTimeBucket = bucket
                currentTime = t
            }
        }
        .onReceive(engine.clock.$bufferedPosition) { b in
            let bucket = TimelineClockBucketer.bufferBucket(b)
            if bucket != lastBufferBucket {
                lastBufferBucket = bucket
                bufferedTime = b
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
