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
/// Leaf timeline & chapter/clock observers remain isolated so 10 Hz engine ticks never re-render the strip.
struct PlayerBottomBarView: View {
    @ObservedObject var viewModel: PlayerViewModel
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
    @State private var focusRetryTask: Task<Void, Never>?
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
        let isMovie = (titleDisplay.seriesLine == nil)

        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let seriesLine = titleDisplay.seriesLine {
                            HStack(spacing: 8) {
                                Text(seriesLine)
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.moonlight)
                                    .lineLimit(1)

                                if !viewModel.chapters.isEmpty && !viewModel.isScrubbing {
                                    ActiveChapterLabelLeafView(
                                        engine: viewModel.engine,
                                        chapters: viewModel.chapters,
                                        prefix: "· ",
                                        previewTimeOverride: viewModel.previewPlayheadOverrideSeconds
                                    )
                                }
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
                    .allowsHitTesting(false)

                    EndsAtLeafView(
                        engine: viewModel.engine,
                        duration: duration,
                        qualitySummary: viewModel.liveQualitySummaryBadge,
                        previewTimeOverride: viewModel.previewPlayheadOverrideSeconds
                    )
                    .allowsHitTesting(false)
                }

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
                        .init(color: LunaTheme.canvas.opacity(0.35), location: 0.28),
                        .init(color: LunaTheme.canvas.opacity(0.78), location: 0.65),
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
                applyRequestedActionFocus()
            }
        }
        .onChange(of: focusRequestNonce) { _, _ in
            guard activeQuickPanel == nil else { return }
            applyRequestedActionFocus()
        }
        .onChange(of: clearFocusNonce) { _, _ in
            focusRetryTask?.cancel()
            focusRetryTask = nil
            focusedAction = nil
        }
        .onChange(of: focusedAction) { _, newValue in
            onFocusPresenceChanged(newValue != nil)
            if newValue != nil {
                onUserNavigatedOSD()
            }
        }
        .onDisappear {
            focusRetryTask?.cancel()
            focusRetryTask = nil
            onFocusPresenceChanged(false)
        }
    }

    @ViewBuilder
    private var quickActionsRow: some View {
        let tabs = PlayerQuickPanelTab.visibleTabs(hasChapters: !viewModel.chapters.isEmpty)
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
        .allowsHitTesting(activeQuickPanel == nil)
        .disabled(activeQuickPanel != nil)
        .onMoveCommand { direction in
            if direction == .up {
                focusRetryTask?.cancel()
                focusRetryTask = nil
                focusedAction = nil
                onReturnFocusToCanvas()
            }
        }
    }

    private func applyRequestedActionFocus() {
        focusRetryTask?.cancel()
        let target = requestedAction
        focusedAction = target
        focusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, activeQuickPanel == nil else { return }
                if focusedAction == nil {
                    focusedAction = target
                } else {
                    return
                }
            }
        }
    }
}

// MARK: - Isolated & Bucketed Clock Leaf Views

private struct EndsAtLeafView: View {
    let engine: AetherEngine
    let duration: Double
    var qualitySummary: String? = nil
    var previewTimeOverride: Double? = nil

    @State private var currentTime: Double = 0
    @State private var lastTimeBucket: Int = -1

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.dateFormat = "HH.mm"
        return f
    }()

    var body: some View {
        let effectiveCurrent = previewTimeOverride ?? currentTime
        let endsAtText: String? = {
            guard duration > 30 else { return nil }
            let remaining = max(0, duration - effectiveCurrent)
            let finishClock = Self.formatter.string(from: Date().addingTimeInterval(remaining))
            return "Ferdig kl. \(finishClock)"
        }()
        let combined = [qualitySummary, endsAtText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        Group {
            if !combined.isEmpty {
                Text(combined)
                    .font(LunaTheme.Font.caption.monospacedDigit())
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
    let prefix: String
    var previewTimeOverride: Double? = nil

    @State private var currentTime: Double = 0

    var body: some View {
        let effectiveCurrent = previewTimeOverride ?? currentTime
        Group {
            if let active = chapters.first(where: { effectiveCurrent >= $0.startSeconds && effectiveCurrent < $0.endSeconds }) {
                Text("\(prefix)\(active.title)")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                            let isPlayedSegment = ch.startSeconds <= displayTime
                            Rectangle()
                                .fill(
                                    isPlayedSegment
                                        ? LunaTheme.pureBlack.opacity(0.75)
                                        : LunaTheme.warmBorderBase.opacity(0.42)
                                )
                                .frame(width: 2.0, height: barHeight)
                                .offset(x: xPos)
                        }
                    }

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
                            engine: viewModel.engine,
                            chapters: viewModel.chapters,
                            prefix: "· ",
                            previewTimeOverride: viewModel.previewPlayheadOverrideSeconds
                        )
                    }
                }

                Spacer()

                if isScrubbing {
                    Text("Klikk for å spille herfra")
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
