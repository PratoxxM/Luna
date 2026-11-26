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

/// Evening-cinema transport OSD with bottom quick-action strip (`Tekst · Lyd · Utgave · Bilde · Kapitler`).
/// Leaf timeline & chapter/clock observers remain isolated so 10 Hz engine ticks and 60 Hz scrub updates
/// never re-render `PlayerBottomBarView` or `PlayerContainerView`.
struct PlayerBottomBarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: PlayerViewModel
    let fallbackRequest: PlaybackLaunchRequest
    var activeQuickPanel: PlayerQuickPanelTab? = nil
    var isQuickActionsModeActive: Bool = false
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
        let hideHeaderForOverlay = isScrubbing || activeQuickPanel != nil

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
                        qualitySummary: viewModel.qosReporter.liveQualitySummaryBadge
                    )
                    .allowsHitTesting(false)
                }
                .opacity(hideHeaderForOverlay ? 0 : 1)
                .animation(LunaFocusStyle.calmEaseOut(duration: 0.14, reduceMotion: reduceMotion), value: hideHeaderForOverlay)

                TimelineScrubberLeafView(
                    viewModel: viewModel,
                    scrubState: viewModel.scrubState,
                    engine: viewModel.engine,
                    duration: duration,
                    isPaused: isPaused,
                    showPausedSwipeHint: isPaused && !isQuickActionsModeActive && activeQuickPanel == nil,
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
            if isQuickActionsModeActive && focusRequestNonce > 0 && activeQuickPanel == nil {
                activeFocusNonce = focusRequestNonce
            } else {
                activeFocusNonce = 0
                focusedAction = nil
            }
        }
        .onChange(of: focusRequestNonce) { _, newNonce in
            guard isQuickActionsModeActive && activeQuickPanel == nil else { return }
            activeFocusNonce = newNonce
        }
        .onChange(of: isQuickActionsModeActive) { _, active in
            if !active {
                activeFocusNonce = 0
                focusedAction = nil
            }
        }
        .onChange(of: clearFocusNonce) { _, _ in
            activeFocusNonce = 0
            focusedAction = nil
        }
        .lunaEntryFocusTarget(
            nonce: activeFocusNonce,
            isActive: isQuickActionsModeActive && activeQuickPanel == nil,
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
        let interactive = (isQuickActionsModeActive && activeQuickPanel == nil && !viewModel.isScrubbing)
        HStack(spacing: 12) {
            ForEach(tabs) { tab in
                let isOpenPopover = (activeQuickPanel == tab)
                let showsActiveDot: Bool = {
                    guard !isOpenPopover else { return false }
                    switch tab {
                    case .subtitles:
                        return viewModel.activeSubtitleTrackIndex != nil
                    case .audio:
                        return viewModel.audioEnhancement != .reference || viewModel.audioDelayMs != 0
                    case .source, .picture, .chapters:
                        return false
                    }
                }()
                LunaPillButton(
                    tab.title,
                    systemImage: tab.systemImage,
                    showsTrailingDot: showsActiveDot,
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
