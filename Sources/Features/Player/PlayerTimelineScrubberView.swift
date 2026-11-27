import SwiftUI
import CoreGraphics
import AetherBridge

/// Isolated leaf timeline scrubber observing `engine.clock.$currentTime` and `$bufferedPosition`
/// (`0.5 s` / `2.0 s` buckets) and `PlayerScrubState` so scrub updates never re-render the bottom bar.
struct TimelineScrubberLeafView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: PlayerViewModel
    let scrubState: PlayerScrubState
    let engine: AetherEngine
    let duration: Double
    let isPaused: Bool
    var showPausedSwipeHint: Bool = false
    var inlineMovieChapterMode: Bool = false

    @State private var currentTime: Double = 0
    @State private var lastTimeBucket: Int = -1
    @State private var bufferedTime: Double = 0
    @State private var lastBufferBucket: Int = -1

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
            if let previewOverride = viewModel.previewPlayheadOverrideSeconds {
                return previewOverride
            }
            return currentTime
        }()
        let isExpanded = isScrubbing || isPaused || viewModel.coalescedSeekPreviewTarget != nil
        let barHeight: CGFloat = isExpanded ? 8 : 5
        let effectiveBuffered = viewModel.previewPlayheadOverrideSeconds.map { $0 + 480 } ?? bufferedTime
        let progressRatio = min(1.0, max(0.0, displayTime / effectiveDuration))
        let bufferRatio = min(1.0, max(0.0, effectiveBuffered / effectiveDuration))
        let originRatio = min(1.0, max(0.0, scrubState.originSeconds / effectiveDuration))

        VStack(alignment: .leading, spacing: 11) {
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let playheadX = totalWidth * CGFloat(progressRatio)
                let originX = totalWidth * CGFloat(originRatio)

                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LunaTheme.pureBlack.opacity(0.52))

                        Capsule()
                            .fill(LunaTokens.Edge.progressTrack)

                        Capsule()
                            .fill(LunaTokens.Edge.grabber)
                            .frame(width: totalWidth * CGFloat(bufferRatio))

                        if isExpanded,
                           viewModel.chapters.count > 1,
                           let activeChapter = viewModel.trackController.activeChapter(at: displayTime) {
                            let chStart = max(0, min(effectiveDuration, activeChapter.startSeconds))
                            let chEnd = max(chStart, min(effectiveDuration, activeChapter.endSeconds))
                            if chEnd - chStart > 0.5 && (chStart > 0.5 || chEnd < effectiveDuration - 0.5) {
                                let startX = totalWidth * CGFloat(chStart / effectiveDuration)
                                let spanW = max(2, totalWidth * CGFloat((chEnd - chStart) / effectiveDuration))
                                Rectangle()
                                    .fill(LunaTheme.amber.opacity(isScrubbing ? 0.24 : 0.14))
                                    .frame(width: spanW, height: barHeight)
                                    .offset(x: startX)
                            }
                        }

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
                                let isPlayedSegment = ch.startSeconds <= displayTime
                                Rectangle()
                                    .fill(
                                        isPlayedSegment
                                            ? LunaTheme.pureBlack.opacity(0.84)
                                            : LunaTheme.linen.opacity(0.58)
                                    )
                                    .frame(width: 2.5, height: barHeight)
                                    .offset(x: xPos)
                            }
                        }
                    }
                    .frame(height: barHeight)
                    .clipShape(Capsule())

                    if isScrubbing {
                        Capsule()
                            .fill(LunaTheme.pauseWarmLine)
                            .frame(width: 2.0, height: 14)
                            .offset(x: max(0, min(totalWidth - 2.0, originX - 1.0)))
                    }

                    if isExpanded {
                        let knobDiameter: CGFloat = isScrubbing ? 16 : 13
                        Circle()
                            .fill(isScrubbing ? LunaTheme.amber : LunaTheme.linen)
                            .frame(width: knobDiameter, height: knobDiameter)
                            .offset(x: max(0, min(totalWidth - knobDiameter, playheadX - knobDiameter * 0.5)))
                    }
                }
                .frame(height: barHeight)
                .overlay(alignment: .bottomLeading) {
                    if isScrubbing {
                        let chapterTitle = viewModel.trackController.activeChapter(at: displayTime)?.title
                        let bubble = ScrubPreviewBubbleView(
                            targetSeconds: displayTime,
                            originSeconds: scrubState.originSeconds,
                            chapterTitle: chapterTitle,
                            previewImage: scrubState.previewImage,
                            drawsInCompositorView: engine.scrubPreviewDrawsInView && scrubState.previewImage == nil,
                            onMountCompositorView: { compView in
                                viewModel.scrubController.attachCompositorPreviewView(compView)
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
            .animation(LunaFocusStyle.calmEaseOut(duration: 0.16, reduceMotion: reduceMotion), value: isExpanded)

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text(Self.formatSeconds(displayTime))
                        .font(LunaTheme.Font.subtitle.monospacedDigit())
                        .foregroundStyle(isScrubbing ? LunaTheme.amber : LunaTheme.moonlight)
                        .lineLimit(1)
                        .layoutPriority(1)

                    if inlineMovieChapterMode, !viewModel.chapters.isEmpty, !isScrubbing {
                        TimelineActiveChapterLabel(
                            viewModel: viewModel,
                            engine: viewModel.engine,
                            chapters: viewModel.chapters
                        )
                    }
                }

                Spacer()

                if isScrubbing {
                    Text("Klikk for å spille herfra")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.78))
                        .lineLimit(1)
                        .layoutPriority(1)
                } else if showPausedSwipeHint {
                    Text("Sveip for å spole")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.muted.opacity(0.72))
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Spacer()

                Text("−\(Self.formatSeconds(max(0, effectiveDuration - displayTime)))")
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.84))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .onAppear {
            let initialTime = max(0, engine.currentTime)
            currentTime = initialTime
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(initialTime)
            let initialBuf = max(0, engine.bufferedPosition)
            bufferedTime = initialBuf
            lastBufferBucket = PlayerTimelinePolicy.bufferBucket(initialBuf)
        }
        .onReceive(engine.clock.$currentTime) { t in
            let bucket = PlayerTimelinePolicy.timeBucket(t)
            if bucket != lastTimeBucket {
                lastTimeBucket = bucket
                currentTime = t
            }
        }
        .onReceive(engine.clock.$bufferedPosition) { b in
            let bucket = PlayerTimelinePolicy.bufferBucket(b)
            if bucket != lastBufferBucket {
                lastBufferBucket = bucket
                bufferedTime = b
            }
        }
    }

    static func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0,
              let total = Int(exactly: seconds.rounded(.down)) else { return "--:--" }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

private struct TimelineActiveChapterLabel: View {
    let viewModel: PlayerViewModel
    let engine: AetherEngine
    let chapters: [PlaybackChapter]

    @State private var activeTitle: String?
    @State private var lastTimeBucket: Int = -1

    private var effectiveTimeOverride: Double? {
        viewModel.coalescedSeekPreviewTarget ?? viewModel.previewPlayheadOverrideSeconds
    }

    var body: some View {
        Group {
            if let activeTitle {
                Text("· \(activeTitle)")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .onAppear {
            let initial = effectiveTimeOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(initial)
            refresh(for: initial)
        }
        .onChange(of: chapters) { _, _ in
            let current = effectiveTimeOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(current)
            refresh(for: current)
        }
        .onChange(of: effectiveTimeOverride) { _, nextOverride in
            let target = nextOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(target)
            refresh(for: target)
        }
        .onReceive(engine.clock.$currentTime) { t in
            guard effectiveTimeOverride == nil, !chapters.isEmpty else { return }
            let bucket = PlayerTimelinePolicy.timeBucket(t)
            guard bucket != lastTimeBucket else { return }
            lastTimeBucket = bucket
            refresh(for: t)
        }
    }

    private func refresh(for timeSeconds: Double) {
        let nextTitle = chapters.first(where: { timeSeconds >= $0.startSeconds && timeSeconds < $0.endSeconds })?.title
        if activeTitle != nextTitle {
            activeTitle = nextTitle
        }
    }
}
