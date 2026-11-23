import SwiftUI
import CoreGraphics
import AetherBridge

enum PlayerBottomBarAction: Hashable {
    case panel(PlayerQuickPanelTab)
    case nextEpisode
}

struct QuickActionAnchorFramesKey: PreferenceKey {
    static let defaultValue: [PlayerQuickPanelTab: CGRect] = [:]

    static func reduce(
        value: inout [PlayerQuickPanelTab: CGRect],
        nextValue: () -> [PlayerQuickPanelTab: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Evening-cinema transport OSD with bottom quick-action strip (`Tekst · Lyd · Kilde · Bilde · Kapitler`).
/// Leaf timeline & chapter/clock observers remain isolated so 10 Hz engine ticks and 60 Hz scrub updates
/// never re-render `PlayerBottomBarView` or `PlayerContainerView`.
struct PlayerBottomBarView: View {
    let viewModel: PlayerViewModel
    let fallbackRequest: PlaybackLaunchRequest
    var activeQuickPanel: PlayerQuickPanelTab? = nil
    var suppressFloatingNextPill: Bool = false
    var focusRequestNonce: Int = 0
    var clearFocusNonce: Int = 0
    var requestedAction: PlayerBottomBarAction = .panel(.subtitles)
    var onOpenQuickPanel: (PlayerQuickPanelTab) -> Void = { _ in }
    var onPlayNextEpisode: (TvNextEpisodeSummary) -> Void = { _ in }
    var onFocusPresenceChanged: (Bool) -> Void = { _ in }
    var onUserNavigatedOSD: () -> Void = {}
    var onReturnFocusToCanvas: () -> Void = {}

    @FocusState private var focusedAction: PlayerBottomBarAction?
    @State private var activeFocusNonce: Int = 0
    @Namespace private var bottomBarFocusNamespace

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
        let titles = titleDisplay
        let isMovie = (titles.seriesLine == nil)
        let isScrubbing = viewModel.isScrubbing

        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let seriesLine = titles.seriesLine {
                            HStack(spacing: 8) {
                                Text(seriesLine)
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.moonlight)
                                    .lineLimit(1)

                                if !viewModel.chapters.isEmpty && !isScrubbing {
                                    ActiveChapterLabelLeafView(
                                        viewModel: viewModel,
                                        engine: viewModel.engine,
                                        chapters: viewModel.chapters,
                                        prefix: "· "
                                    )
                                }
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            if isPaused && !isScrubbing {
                                Image(systemName: "pause.fill")
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.pauseWarmLine)
                            }

                            Text(titles.titleLine)
                                .font(LunaTheme.Font.sectionTitle)
                                .foregroundStyle(LunaTheme.linen)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)

                    EndsAtLeafView(
                        viewModel: viewModel,
                        scrubState: viewModel.scrubState,
                        engine: viewModel.engine,
                        duration: duration,
                        qualitySummary: viewModel.liveQualitySummaryBadge
                    )
                    .allowsHitTesting(false)
                }
                .opacity(isScrubbing ? 0 : 1)
                .animation(.easeOut(duration: 0.14), value: isScrubbing)

                TimelineScrubberLeafView(
                    viewModel: viewModel,
                    scrubState: viewModel.scrubState,
                    engine: viewModel.engine,
                    duration: duration,
                    isPaused: isPaused,
                    inlineMovieChapterMode: isMovie
                )
                .allowsHitTesting(false)

                quickActionsRow
                    .padding(.top, 4)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 96)
            .padding(.bottom, 60)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: LunaTheme.canvas.opacity(0.52), location: 0.24),
                        .init(color: LunaTheme.canvas.opacity(0.84), location: 0.60),
                        .init(color: LunaTheme.pureBlack.opacity(0.94), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(minHeight: 360)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if focusRequestNonce > 0 && activeQuickPanel == nil {
                activeFocusNonce = focusRequestNonce
            }
        }
        .onChange(of: focusRequestNonce) { _, newNonce in
            guard activeQuickPanel == nil else { return }
            activeFocusNonce = newNonce
        }
        .onChange(of: clearFocusNonce) { _, _ in
            activeFocusNonce = 0
            focusedAction = nil
        }
        .lunaEntryFocusTarget(
            nonce: activeFocusNonce,
            isActive: activeQuickPanel == nil,
            focus: $focusedAction,
            target: { requestedAction }
        )
        .onChange(of: focusedAction) { _, newValue in
            onFocusPresenceChanged(newValue != nil)
            if newValue != nil {
                onUserNavigatedOSD()
            }
        }
        .onDisappear {
            activeFocusNonce = 0
            onFocusPresenceChanged(false)
        }
    }

    @ViewBuilder
    private var quickActionsRow: some View {
        let tabs = PlayerQuickPanelTab.visibleTabs(hasChapters: !viewModel.chapters.isEmpty)
        let interactive = (activeQuickPanel == nil && !viewModel.isScrubbing)
        HStack(spacing: 12) {
            ForEach(tabs) { tab in
                let isOpenPopover = (activeQuickPanel == tab)
                let showsSubtitlesDot = !isOpenPopover && tab == .subtitles && viewModel.activeSubtitleTrackIndex != nil
                LunaPillButton(
                    tab.title,
                    systemImage: tab.systemImage,
                    showsTrailingDot: showsSubtitlesDot,
                    isSelected: isOpenPopover,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    onOpenQuickPanel(tab)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: QuickActionAnchorFramesKey.self,
                            value: [tab: geo.frame(in: .named("playerOSD"))]
                        )
                    }
                )
                .focused($focusedAction, equals: .panel(tab))
                .prefersDefaultFocus(requestedAction == .panel(tab), in: bottomBarFocusNamespace)
            }

            Spacer(minLength: 16)

            if !suppressFloatingNextPill, let next = viewModel.activeSession?.nextEpisode {
                LunaPillButton(
                    "Neste episode",
                    systemImage: "forward.end.fill",
                    badgeText: "S\(next.season) · E\(next.episode)",
                    prominence: .glassPill,
                    size: .compact
                ) {
                    onPlayNextEpisode(next)
                }
                .focused($focusedAction, equals: .nextEpisode)
            }
        }
        .focusScope(bottomBarFocusNamespace)
        .focusSection()
        .allowsHitTesting(interactive)
        .disabled(!interactive)
        .onMoveCommand { direction in
            if direction == .up {
                activeFocusNonce = 0
                focusedAction = nil
                onReturnFocusToCanvas()
            }
        }
    }
}

// MARK: - Isolated & Bucketed Clock Leaf Views

private struct EndsAtLeafView: View {
    let viewModel: PlayerViewModel
    let scrubState: PlayerScrubState
    let engine: AetherEngine
    let duration: Double
    var qualitySummary: String? = nil

    @State private var endsAtText: String?
    @State private var lastFinishBucket: Int = -1

    private var nonScrubOverrideSeconds: Double? {
        viewModel.coalescedSeekPreviewTarget ?? viewModel.previewPlayheadOverrideSeconds
    }

    var body: some View {
        let activeScrubBucket: Int? = viewModel.isScrubbing
            ? PlayerTimelinePolicy.finishTimeBucket(scrubState.targetSeconds)
            : nil
        let combined = [qualitySummary, endsAtText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        Group {
            if !combined.isEmpty {
                Text(combined)
                    .font(LunaTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .onAppear {
            let initial = viewModel.isScrubbing
                ? scrubState.targetSeconds
                : (nonScrubOverrideSeconds ?? max(0, engine.currentTime))
            lastFinishBucket = PlayerTimelinePolicy.finishTimeBucket(initial)
            refreshEndsAt(for: initial)
        }
        .onChange(of: duration) { _, _ in
            let current = viewModel.isScrubbing
                ? scrubState.targetSeconds
                : (nonScrubOverrideSeconds ?? max(0, engine.currentTime))
            lastFinishBucket = PlayerTimelinePolicy.finishTimeBucket(current)
            refreshEndsAt(for: current)
        }
        .onChange(of: activeScrubBucket) { _, nextBucket in
            if let nextBucket, viewModel.isScrubbing {
                lastFinishBucket = nextBucket
                refreshEndsAt(for: scrubState.targetSeconds)
            } else if !viewModel.isScrubbing {
                let settled = nonScrubOverrideSeconds ?? scrubState.targetSeconds
                lastFinishBucket = PlayerTimelinePolicy.finishTimeBucket(settled)
                refreshEndsAt(for: settled)
            }
        }
        .onChange(of: nonScrubOverrideSeconds) { _, nextOverride in
            guard !viewModel.isScrubbing else { return }
            let target = nextOverride ?? max(0, engine.currentTime)
            lastFinishBucket = PlayerTimelinePolicy.finishTimeBucket(target)
            refreshEndsAt(for: target)
        }
        .onReceive(engine.clock.$currentTime) { t in
            guard !viewModel.isScrubbing, nonScrubOverrideSeconds == nil else { return }
            let bucket = PlayerTimelinePolicy.finishTimeBucket(t)
            guard bucket != lastFinishBucket else { return }
            lastFinishBucket = bucket
            refreshEndsAt(for: t)
        }
    }

    private func refreshEndsAt(for currentSeconds: Double) {
        let nextText = PlayerTimelinePolicy.formatFinishTimeText(
            currentSeconds: currentSeconds,
            durationSeconds: duration
        )
        if endsAtText != nextText {
            endsAtText = nextText
        }
    }
}

private struct ActiveChapterLabelLeafView: View {
    let viewModel: PlayerViewModel
    let engine: AetherEngine
    let chapters: [PlaybackChapter]
    let prefix: String

    @State private var activeTitle: String?
    @State private var lastTimeBucket: Int = -1

    private var effectiveTimeOverride: Double? {
        viewModel.coalescedSeekPreviewTarget ?? viewModel.previewPlayheadOverrideSeconds
    }

    var body: some View {
        Group {
            if let activeTitle {
                Text("\(prefix)\(activeTitle)")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .onAppear {
            let initial = effectiveTimeOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(initial)
            refreshActiveTitle(for: initial)
        }
        .onChange(of: chapters) { _, _ in
            let current = effectiveTimeOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(current)
            refreshActiveTitle(for: current)
        }
        .onChange(of: effectiveTimeOverride) { _, nextOverride in
            let target = nextOverride ?? max(0, engine.currentTime)
            lastTimeBucket = PlayerTimelinePolicy.timeBucket(target)
            refreshActiveTitle(for: target)
        }
        .onReceive(engine.clock.$currentTime) { t in
            guard effectiveTimeOverride == nil, !chapters.isEmpty else { return }
            let bucket = PlayerTimelinePolicy.timeBucket(t)
            guard bucket != lastTimeBucket else { return }
            lastTimeBucket = bucket
            refreshActiveTitle(for: t)
        }
    }

    private func refreshActiveTitle(for timeSeconds: Double) {
        let nextTitle = chapters.first(where: { timeSeconds >= $0.startSeconds && timeSeconds < $0.endSeconds })?.title
        if activeTitle != nextTitle {
            activeTitle = nextTitle
        }
    }
}

struct TimelineScrubberLeafView: View {
    let viewModel: PlayerViewModel
    let scrubState: PlayerScrubState
    let engine: AetherEngine
    let duration: Double
    let isPaused: Bool
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
                           let activeChapter = viewModel.activeChapter(at: displayTime) {
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

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text(Self.formatSeconds(displayTime))
                        .font(LunaTheme.Font.subtitle.monospacedDigit())
                        .foregroundStyle(isScrubbing ? LunaTheme.amber : LunaTheme.moonlight)

                    if inlineMovieChapterMode, !viewModel.chapters.isEmpty, !isScrubbing {
                        ActiveChapterLabelLeafView(
                            viewModel: viewModel,
                            engine: viewModel.engine,
                            chapters: viewModel.chapters,
                            prefix: "· "
                        )
                    }
                }

                Spacer()

                if isScrubbing {
                    Text("Klikk for å spille herfra")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.78))
                }

                Spacer()

                Text("−\(Self.formatSeconds(max(0, effectiveDuration - displayTime)))")
                    .font(LunaTheme.Font.subtitle.monospacedDigit())
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.84))
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
