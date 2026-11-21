import SwiftUI
import AetherBridge

public enum PlayerQuickPanelTab: String, CaseIterable, Identifiable, Sendable {
    case subtitles
    case audio
    case source
    case picture
    case chapters

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subtitles: return "Tekst"
        case .audio: return "Lyd"
        case .source: return "Kilde"
        case .picture: return "Bilde"
        case .chapters: return "Kapitler"
        }
    }

    public var systemImage: String {
        switch self {
        case .subtitles: return "captions.bubble"
        case .audio: return "waveform"
        case .source: return "film.stack"
        case .picture: return "sparkles.tv"
        case .chapters: return "list.bullet"
        }
    }

    public static func visibleTabs(hasChapters: Bool) -> [PlayerQuickPanelTab] {
        allCases.filter { hasChapters || $0 != .chapters }
    }

    public var fallbackTriggerMinX: CGFloat {
        switch self {
        case .subtitles: return 90
        case .audio: return 242
        case .source: return 384
        case .picture: return 530
        case .chapters: return 676
        }
    }
}

/// Button-anchored Lampelys popover positioned directly above the triggering bottom-bar pill.
/// Focus starts deterministically on the active (`✓`) item inside each list and closes back cleanly.
struct PlayerQuickPanelView: View {
    let viewModel: PlayerViewModel
    let comfort: ComfortPreferences
    let tab: PlayerQuickPanelTab
    var triggerFrame: CGRect? = nil
    let onClose: (_ returnFocusToPill: Bool) -> Void

    @FocusState private var focusedItemID: String?
    @State private var chapterSnapshotTime: Double = 0
    @State private var contentHeight: CGFloat = 280
    @Namespace private var panelFocusNamespace

    private static let topScrollFadeHeight: CGFloat = 12
    private static let bottomScrollFadeHeight: CGFloat = 14

    private var maxScrollContentHeight: CGFloat {
        tab == .subtitles ? 500 : 610
    }

    nonisolated static func panelWidth(for tab: PlayerQuickPanelTab) -> CGFloat {
        switch tab {
        case .source:
            return LunaTokens.Layout.quickPanelWideW
        case .subtitles, .audio, .picture, .chapters:
            return LunaTokens.Layout.quickPanelW
        }
    }

    nonisolated static func resolvedPanelLeadingX(
        triggerFrame: CGRect?,
        tab: PlayerQuickPanelTab,
        containerWidth: CGFloat = 1920,
        gutter: CGFloat = LunaTheme.horizontalGutter
    ) -> CGFloat {
        let width = panelWidth(for: tab)
        let rawMinX: CGFloat = {
            if let frame = triggerFrame, frame.width > 1 {
                return frame.minX
            }
            return tab.fallbackTriggerMinX
        }()
        return min(max(gutter, rawMinX), max(gutter, containerWidth - gutter - width))
    }

    private var panelWidth: CGFloat {
        Self.panelWidth(for: tab)
    }

    private var preferredActiveItemID: String {
        switch tab {
        case .subtitles:
            if let subIdx = viewModel.activeSubtitleTrackIndex {
                return "sub-\(subIdx)"
            }
            return "sub-off"
        case .audio:
            if let audIdx = viewModel.activeAudioTrackIndex {
                return "aud-\(audIdx)"
            }
            if let first = viewModel.drawerAudioOptions.first {
                return "aud-\(first.id)"
            }
            return "aud-mode-\(viewModel.audioEnhancement.rawValue)"
        case .source:
            let activeId = viewModel.activeSession?.selectedCandidate.candidateId
            if let match = viewModel.alternatives.first(where: { cand in
                activeId != nil ? (cand.candidateId == activeId) : (cand.isActive == true)
            }) {
                return "src-\(match.candidateId)"
            }
            if let first = viewModel.alternatives.first {
                return "src-\(first.candidateId)"
            }
            return "src-empty"
        case .picture:
            return "pic-metalfx-\(comfort.lowResUpscaleMode.rawValue)"
        case .chapters:
            if let activeCh = viewModel.activeChapter(at: chapterSnapshotTime) ?? viewModel.chapters.first {
                return "ch-\(activeCh.id)"
            }
            return "ch-empty"
        }
    }

    var body: some View {
        let leadingX = Self.resolvedPanelLeadingX(triggerFrame: triggerFrame, tab: tab)
        let maxHeight = maxScrollContentHeight
        let isScrollable = contentHeight > maxHeight + 2

        VStack(alignment: .leading, spacing: 12) {
            panelHeader

            Rectangle()
                .fill(LunaTokens.Edge.divider)
                .frame(height: LunaTokens.Layout.hairlineWidth)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        panelListContent
                    }
                    .padding(.top, Self.topScrollFadeHeight)
                    .padding(.bottom, Self.bottomScrollFadeHeight)
                    .padding(.horizontal, 6)
                    .onGeometryChange(for: CGFloat.self) { geo in
                        geo.size.height
                    } action: { newHeight in
                        if newHeight > 10, abs(contentHeight - newHeight) > 1 {
                            contentHeight = newHeight
                        }
                    }
                }
                .frame(height: min(max(contentHeight, 120), maxHeight))
                .mask {
                    if isScrollable {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: Self.topScrollFadeHeight)

                            Color.black

                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: Self.bottomScrollFadeHeight)
                        }
                    } else {
                        Color.black
                    }
                }
                .onAppear {
                    chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                }
                .onChange(of: tab) { _, _ in
                    chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                }
                .task(id: "\(tab.rawValue)#\(tab == .source ? viewModel.alternatives.count : 0)#\(viewModel.activeSession?.sessionId ?? "")") {
                    let targetID = preferredActiveItemID
                    proxy.scrollTo(targetID)
                    focusedItemID = targetID
                    for delayNs: UInt64 in [16_000_000, 48_000_000] {
                        try? await Task.sleep(nanoseconds: delayNs)
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(targetID)
                        if focusedItemID != targetID {
                            focusedItemID = targetID
                        } else {
                            return
                        }
                    }
                }
            }
            .focusScope(panelFocusNamespace)
            .focusSection()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(width: panelWidth, alignment: .leading)
        .lunaCinemaGlassSurface(
            shadowColor: LunaTheme.pureBlack.opacity(0.68),
            shadowRadius: 34,
            shadowY: 16
        )
        .padding(.leading, leadingX)
        .padding(.bottom, 248)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .task(id: tab) {
            guard tab == .source,
                  viewModel.alternativesSessionId != viewModel.activeSession?.sessionId || viewModel.alternatives.isEmpty else {
                return
            }
            await viewModel.loadAlternatives()
        }
    }

    private var panelHeader: some View {
        Text(tab.title)
            .font(LunaTheme.Font.cardTitle)
            .foregroundStyle(LunaTheme.moonlight)
            .lineLimit(1)
    }

    @ViewBuilder
    private var panelListContent: some View {
        switch tab {
        case .subtitles:
            subtitlesList
        case .audio:
            audioList
        case .source:
            sourceList
        case .picture:
            pictureList
        case .chapters:
            chaptersList
        }
    }

    // MARK: - Tekst

    @ViewBuilder
    private var subtitlesList: some View {
        LunaListRow(
            title: "Av",
            isSelected: viewModel.activeSubtitleTrackIndex == nil,
            dimUnfocusedTitle: true,
            externalIsFocused: focusedItemID == "sub-off"
        ) {
            viewModel.clearSubtitleManually()
            onClose(false)
        }
        .id("sub-off")
        .focused($focusedItemID, equals: "sub-off")
        .prefersDefaultFocus(preferredActiveItemID == "sub-off", in: panelFocusNamespace)

        ForEach(viewModel.drawerSubtitleOptions) { sub in
            let rowID = "sub-\(sub.id)"
            let selected = viewModel.activeSubtitleTrackIndex == sub.id
            LunaListRow(
                title: sub.humanLanguageTitle,
                subtitle: sub.humanSubtitleDescription,
                isSelected: selected,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == rowID
            ) {
                viewModel.selectSubtitleManually(sub.id)
                onClose(false)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        LunaListDivider()
            .padding(.vertical, 4)

        if let lockReason = viewModel.kveldslysLockReason {
            HStack(spacing: 12) {
                Text("Kveldslys")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                Spacer(minLength: 8)
                Text(lockReason)
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kveldslys")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)

                HStack(spacing: 8) {
                    ForEach(HDRSubtitlePreset.allCases) { preset in
                        LunaPillButton(
                            compactNightLightLabel(preset),
                            isSelected: comfort.hdrSubtitlePreset == preset,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            comfort.hdrSubtitlePreset = preset
                        }
                        .focused($focusedItemID, equals: "sub-kveldslys-\(preset.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .focusSection()
        }

        syncDelayStepperRow(
            title: "Tekstsynk",
            minusLabel: "−0,1 s",
            centerLabel: formatSubtitleDelay(viewModel.subtitleDelaySeconds),
            plusLabel: "+0,1 s",
            focusPrefix: "sub-sync",
            onMinus: { viewModel.adjustSubtitleDelay(by: -0.1) },
            onReset: { viewModel.resetSubtitleDelay() },
            onPlus: { viewModel.adjustSubtitleDelay(by: 0.1) }
        )
    }

    // MARK: - Lyd

    @ViewBuilder
    private var audioList: some View {
        ForEach(viewModel.drawerAudioOptions) { track in
            let rowID = "aud-\(track.id)"
            let selected = viewModel.activeAudioTrackIndex == track.id
            LunaListRow(
                title: track.humanLanguageTitle,
                subtitle: track.humanFormatSubtitle,
                isSelected: selected,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == rowID
            ) {
                viewModel.selectAudioTrack(track.id)
                onClose(false)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        LunaListDivider()
            .padding(.vertical, 4)

        ForEach(AudioEnhancementMode.allCases) { mode in
            let rowID = "aud-mode-\(mode.rawValue)"
            LunaListRow(
                title: mode.displayTitle,
                subtitle: mode.subtitle,
                isSelected: viewModel.audioEnhancement == mode,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == rowID
            ) {
                viewModel.setAudioEnhancement(mode)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
        }

        syncDelayStepperRow(
            title: "Lydsynk",
            minusLabel: "−25 ms",
            centerLabel: ComfortPreferences.displayAudioDelayMs(viewModel.audioDelayMs),
            plusLabel: "+25 ms",
            focusPrefix: "aud-sync",
            onMinus: { viewModel.adjustAudioDelay(byMs: -25) },
            onReset: { viewModel.resetAudioDelay() },
            onPlus: { viewModel.adjustAudioDelay(byMs: 25) }
        )
    }

    // MARK: - Kilde

    @ViewBuilder
    private var sourceList: some View {
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId

        if viewModel.isLoadingAlternatives && viewModel.alternatives.isEmpty {
            LunaLoadingRow(message: "Henter tilgjengelige kilder…")
                .padding(.horizontal, 12)
        } else if viewModel.alternatives.isEmpty {
            Text("Ingen alternative kilder funnet for denne tittelen.")
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.muted)
                .padding(20)
        } else {
            ForEach(Array(viewModel.alternatives.enumerated()), id: \.element.id) { idx, cand in
                let isCurrent = activeCandidateId != nil
                    ? (cand.candidateId == activeCandidateId)
                    : (cand.isActive == true)
                let rowID = "src-\(cand.candidateId)"
                SourceCandidateRowView(
                    candidate: cand,
                    roomName: "",
                    isRecommended: idx == 0,
                    isSelected: isCurrent,
                    activeStatusLabel: "Spilles nå",
                    isFocused: focusedItemID == rowID,
                    dimUnfocusedTitle: true
                ) {
                    if !isCurrent {
                        viewModel.triggerSourceSwitch(to: cand.candidateId)
                    }
                    onClose(false)
                }
                .id(rowID)
                .focused($focusedItemID, equals: rowID)
                .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
            }
        }
    }

    // MARK: - Bilde

    @ViewBuilder
    private var pictureList: some View {
        ForEach(LowResUpscaleMode.allCases) { mode in
            let rowID = "pic-metalfx-\(mode.rawValue)"
            LunaListRow(
                title: "MetalFX: \(mode.displayTitle)",
                subtitle: mode.shortDescription,
                isSelected: comfort.lowResUpscaleMode == mode,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == rowID
            ) {
                viewModel.setMetalFXModeLive(mode)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        LunaListDivider()
            .padding(.vertical, 4)

        LunaListRow(
            title: "Teknisk oversikt",
            trailingText: comfort.showNerdHUD ? "På" : "Av",
            trailingTextProminent: comfort.showNerdHUD,
            dimUnfocusedTitle: true,
            externalIsFocused: focusedItemID == "pic-hud"
        ) {
            comfort.showNerdHUD.toggle()
        }
        .id("pic-hud")
        .focused($focusedItemID, equals: "pic-hud")

        Text(viewModel.videoFormatSummaryLine)
            .font(LunaTheme.Font.caption)
            .foregroundStyle(LunaTheme.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }

    // MARK: - Kapitler

    @ViewBuilder
    private var chaptersList: some View {
        let activeChapterID = viewModel.activeChapter(at: chapterSnapshotTime)?.id
        ForEach(viewModel.chapters) { ch in
            let rowID = "ch-\(ch.id)"
            let isCurrent = ch.id == activeChapterID
            LunaListRow(
                title: ch.title,
                subtitle: chapterSubtitle(ch, isActive: isCurrent),
                trailingText: TimelineScrubberLeafView.formatSeconds(ch.startSeconds),
                isSelected: isCurrent,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == rowID
            ) {
                viewModel.seekToChapter(ch)
                onClose(false)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }
    }

    // MARK: - Helpers

    private func syncDelayStepperRow(
        title: String,
        minusLabel: String,
        centerLabel: String,
        plusLabel: String,
        focusPrefix: String,
        onMinus: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)

            Spacer(minLength: 8)

            LunaPillButton(minusLabel, prominence: .glassPill, size: .compact, action: onMinus)
                .focused($focusedItemID, equals: "\(focusPrefix)-minus")

            LunaPillButton(centerLabel, isSelected: true, prominence: .glassPill, size: .compact, action: onReset)
                .focused($focusedItemID, equals: "\(focusPrefix)-zero")

            LunaPillButton(plusLabel, prominence: .glassPill, size: .compact, action: onPlus)
                .focused($focusedItemID, equals: "\(focusPrefix)-plus")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .focusSection()
    }

    private func compactNightLightLabel(_ preset: HDRSubtitlePreset) -> String {
        switch preset {
        case .white100: return "100 %"
        case .warm75: return "75 %"
        case .warm60: return "60 %"
        case .soft50: return "50 %"
        }
    }

    private func formatSubtitleDelay(_ seconds: Double) -> String {
        if abs(seconds) < 0.05 { return "0 s" }
        let formatted = String(format: "%.1f", abs(seconds)).replacingOccurrences(of: ".", with: ",")
        return seconds >= 0 ? "+\(formatted) s" : "−\(formatted) s"
    }

    private func chapterSubtitle(_ chapter: PlaybackChapter, isActive: Bool) -> String? {
        if isActive { return "Spilles nå" }
        return chapter.kind.badgeLabel
    }
}
