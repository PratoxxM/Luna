import SwiftUI
import AetherBridge

/// Button-anchored Lampelys popover positioned directly above the triggering bottom-bar pill.
/// Supports direct Left/Right tab switching from full-width rows, starts deterministically on the
/// active (`✓`) item inside each list, and uses a lightweight `16 pt` shadow for 4K DV P7 FEL headroom.
struct PlayerQuickPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: PlayerViewModel
    let comfort: ComfortPreferences
    let tab: PlayerQuickPanelTab
    var triggerFrame: CGRect? = nil
    var canSwitchTabs: Bool = true
    var onSwitchTab: (QuickPanelHorizontalDirection) -> Void = { _ in }
    let onClose: (_ returnFocusToPill: Bool) -> Void

    @FocusState var focusedItemID: String?
    @State private var chapterSnapshotTime: Double?
    @State private var contentHeight: CGFloat = 280
    @Namespace var panelFocusNamespace

    private static let topScrollFadeHeight: CGFloat = 12
    private static let bottomScrollFadeHeight: CGFloat = 14
    nonisolated static let maxScrollAreaHeight: CGFloat = 376

    private var maxScrollContentHeight: CGFloat {
        Self.maxScrollAreaHeight
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
            return CGFloat(tab.fallbackTriggerMinX)
        }()
        return min(max(gutter, rawMinX), max(gutter, containerWidth - gutter - width))
    }

    private var panelWidth: CGFloat {
        Self.panelWidth(for: tab)
    }

    var currentPlayheadSnapshotSeconds: Double {
        viewModel.previewPlayheadOverrideSeconds ?? max(0, viewModel.engine.currentTime)
    }

    func preferredActiveItemID(at snapshotSeconds: Double) -> String {
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
            if let first = viewModel.trackController.drawerAudioOptions.first {
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
            if let activeCh = viewModel.trackController.activeChapter(at: snapshotSeconds) ?? viewModel.chapters.first {
                return "ch-\(activeCh.id)"
            }
            return "ch-empty"
        }
    }

    var effectiveChapterSnapshotSeconds: Double {
        chapterSnapshotTime ?? currentPlayheadSnapshotSeconds
    }

    var preferredActiveItemID: String {
        preferredActiveItemID(at: effectiveChapterSnapshotSeconds)
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
                panelScrollView(proxy: proxy, maxHeight: maxHeight)
                    .optionalTopBottomScrollMask(
                        enabled: isScrollable,
                        topHeight: Self.topScrollFadeHeight,
                        bottomHeight: Self.bottomScrollFadeHeight
                    )
            }
            .focusScope(panelFocusNamespace)
            .focusSection()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(width: panelWidth, alignment: .leading)
        .lunaCinemaGlassSurface(
            shadowColor: LunaTheme.pureBlack.opacity(0.58),
            shadowRadius: 16,
            shadowY: 8
        )
        .padding(.leading, leadingX)
        .padding(.bottom, 248)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: tab)
        .task(id: "\(tab.rawValue)#\(viewModel.activeSession?.sessionId ?? "")") {
            guard tab == .source,
                  viewModel.alternativesSessionId != viewModel.activeSession?.sessionId else {
                return
            }
            await viewModel.loadAlternatives()
        }
    }

    private func panelScrollView(proxy: ScrollViewProxy, maxHeight: CGFloat) -> some View {
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
        .task(id: "\(tab.rawValue)#\(tab == .source ? viewModel.alternatives.count : 0)#\(viewModel.activeSession?.sessionId ?? "")") {
            let snapshotSeconds = currentPlayheadSnapshotSeconds
            chapterSnapshotTime = snapshotSeconds
            let targetID = preferredActiveItemID(at: snapshotSeconds)
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

    private var panelHeader: some View {
        Text(tab.panelHeaderTitle)
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
}

private extension View {
    @ViewBuilder
    func optionalTopBottomScrollMask(
        enabled: Bool,
        topHeight: CGFloat,
        bottomHeight: CGFloat
    ) -> some View {
        if enabled {
            self.mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, LunaTheme.pureBlack],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topHeight)

                    LunaTheme.pureBlack

                    LinearGradient(
                        colors: [LunaTheme.pureBlack, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottomHeight)
                }
            }
        } else {
            self
        }
    }
}
