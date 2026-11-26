import SwiftUI
import AetherBridge

extension PlayerQuickPanelView {
    // MARK: - Velg utgave

    @ViewBuilder
    var sourceList: some View {
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId

        VStack(alignment: .leading, spacing: 4) {
            if viewModel.isLoadingAlternatives && viewModel.alternatives.isEmpty {
                LunaLoadingRow(message: "Henter tilgjengelige utgaver…")
                    .padding(.horizontal, 12)
            } else if viewModel.alternatives.isEmpty {
                Text("Ingen alternative utgaver funnet for denne tittelen.")
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
                        isRecommended: idx == 0,
                        isSelected: isCurrent,
                        activeStatusLabel: "Spilles nå",
                        isFocused: focusedItemID == rowID,
                        dimUnfocusedTitle: true,
                        compactForQuickPanel: true
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
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )
    }

    // MARK: - Bilde

    @ViewBuilder
    var pictureList: some View {
        let qos = viewModel.qosReporter
        VStack(alignment: .leading, spacing: 4) {
            ForEach(LowResUpscaleMode.allCases) { mode in
                let rowID = "pic-metalfx-\(mode.rawValue)"
                LunaListRow(
                    title: "MetalFX: \(mode.displayTitle)",
                    subtitle: mode.shortDescription,
                    isSelected: comfort.lowResUpscaleMode == mode,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == rowID
                ) {
                    viewModel.trackController.setMetalFXModeLive(mode)
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

            if qos.canSwitchToHDR10BaseLayer {
                LunaListRow(
                    title: LunaCopy.switchToHDR10BaseLayerTitle,
                    subtitle: qos.suggestsHDR10BaseLayer
                        ? LunaCopy.hdr10FallbackRecommendedSubtitle
                        : LunaCopy.hdr10FallbackHintSubtitle,
                    trailingText: qos.suggestsHDR10BaseLayer ? "Anbefalt" : nil,
                    trailingTextProminent: qos.suggestsHDR10BaseLayer,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == "pic-hdr10-baselayer"
                ) {
                    viewModel.switchToHDR10BaseLayer()
                }
                .id("pic-hdr10-baselayer")
                .focused($focusedItemID, equals: "pic-hdr10-baselayer")
            }
        }
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )

        Text(qos.videoFormatSummaryLine)
            .font(LunaTheme.Font.caption)
            .foregroundStyle(LunaTheme.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }

    // MARK: - Kapitler

    @ViewBuilder
    var chaptersList: some View {
        let activeChapterID = viewModel.trackController.activeChapter(at: effectiveChapterSnapshotSeconds)?.id
        VStack(alignment: .leading, spacing: 4) {
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
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )
    }

    private func chapterSubtitle(_ chapter: PlaybackChapter, isActive: Bool) -> String? {
        if isActive { return "Spilles nå" }
        return chapter.kind.badgeLabel
    }
}
