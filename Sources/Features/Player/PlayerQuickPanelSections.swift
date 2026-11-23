import SwiftUI
import AetherBridge

private extension View {
    /// Intercepts Siri Remote Left/Right on full-width rows to switch directly between adjacent
    /// quick-panel tabs (`Tekst ↔ Lyd ↔ Utgave ↔ Bilde ↔ Kapitler`), while never intercepting
    /// horizontal navigation inside inline pill strips (`Kveldslys`, `Tekstsynk`, `Høyttaleroppsett`, `Lydsynk`).
    @ViewBuilder
    func quickPanelRowTabSwitch(
        enabled: Bool,
        focusedItemID: String?,
        onSwitchTab: @escaping (QuickPanelHorizontalDirection) -> Void
    ) -> some View {
        if enabled {
            self.onMoveCommand { direction in
                guard !PlayerQuickPanelTab.isHorizontalPillFocusID(focusedItemID) else { return }
                switch direction {
                case .left:
                    onSwitchTab(.left)
                case .right:
                    onSwitchTab(.right)
                default:
                    break
                }
            }
        } else {
            self
        }
    }
}

extension PlayerQuickPanelView {
    // MARK: - Tekst

    @ViewBuilder
    var subtitlesList: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        }
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )

        LunaListDivider()
            .padding(.vertical, 4)

        if let lockReason = viewModel.kveldslysLockReason {
            HStack(spacing: 12) {
                Text("Kveldslys · \(comfort.hdrSubtitlePreset.shortTitle)")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
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
                Text("Kveldslys · \(comfort.hdrSubtitlePreset.shortTitle)")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ForEach(HDRSubtitlePreset.allCases) { preset in
                        LunaPillButton(
                            preset.compactPillLabel,
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
            headerTitle: PlaybackSyncTimingPolicy.headerTitle(
                baseTitle: "Tekstsynk",
                delayMs: viewModel.subtitleDelayMs
            ),
            subtitleNotice: nil,
            minusLabel: "−50 ms",
            plusLabel: "+50 ms",
            isNonZero: viewModel.subtitleDelayMs != 0,
            focusPrefix: "sub-sync",
            onMinus: { viewModel.adjustSubtitleDelay(byMs: -PlaybackSyncTimingPolicy.subtitleStepMs) },
            onReset: { viewModel.resetSubtitleDelay() },
            onPlus: { viewModel.adjustSubtitleDelay(byMs: PlaybackSyncTimingPolicy.subtitleStepMs) }
        )
    }

    // MARK: - Lyd

    @ViewBuilder
    var audioList: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            if !viewModel.drawerAudioOptions.isEmpty {
                LunaListDivider()
                    .padding(.vertical, 4)
            }

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
                .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
            }
        }
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )

        LunaListDivider()
            .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.speakerLayoutHeaderSummary)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(1)

            HStack(spacing: 8) {
                ForEach(SpeakerLayoutOverrideMode.quickPanelCases) { mode in
                    LunaPillButton(
                        mode.quickPillTitle,
                        isSelected: comfort.speakerLayoutOverride == mode,
                        prominence: .glassPill,
                        size: .compact
                    ) {
                        viewModel.setSpeakerLayoutLive(mode)
                    }
                    .focused($focusedItemID, equals: "aud-layout-\(mode.rawValue)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .focusSection()

        syncDelayStepperRow(
            headerTitle: PlaybackSyncTimingPolicy.headerTitle(
                baseTitle: "Lydsynk",
                delayMs: viewModel.audioDelayMs
            ),
            subtitleNotice: viewModel.wirelessAudioDelayNotice,
            minusLabel: "−25 ms",
            plusLabel: "+25 ms",
            isNonZero: viewModel.audioDelayMs != 0,
            focusPrefix: "aud-sync",
            onMinus: { viewModel.adjustAudioDelay(byMs: -PlaybackSyncTimingPolicy.audioStepMs) },
            onReset: { viewModel.resetAudioDelay() },
            onPlus: { viewModel.adjustAudioDelay(byMs: PlaybackSyncTimingPolicy.audioStepMs) }
        )
    }

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
                        roomName: viewModel.activeSession?.roomName ?? "",
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
        }
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )

        Text(viewModel.videoFormatSummaryLine)
            .font(LunaTheme.Font.caption)
            .foregroundStyle(LunaTheme.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.top, 2)
    }

    // MARK: - Kapitler

    @ViewBuilder
    var chaptersList: some View {
        let activeChapterID = viewModel.activeChapter(at: effectiveChapterSnapshotSeconds)?.id
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

    // MARK: - Unified Millisecond Sync Row

    func syncDelayStepperRow(
        headerTitle: String,
        subtitleNotice: String?,
        minusLabel: String,
        plusLabel: String,
        isNonZero: Bool,
        focusPrefix: String,
        onMinus: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        let minusID = "\(focusPrefix)-minus"
        let zeroID = "\(focusPrefix)-zero"
        let plusID = "\(focusPrefix)-plus"

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(LunaTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(isNonZero ? LunaTheme.moonlight : LunaTheme.muted)
                    .lineLimit(1)

                if let subtitleNotice, !subtitleNotice.isEmpty {
                    Text(subtitleNotice)
                        .font(LunaTheme.Font.badge)
                        .foregroundStyle(LunaTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                LunaPillButton(minusLabel, prominence: .glassPill, size: .compact, action: onMinus)
                    .id(minusID)
                    .focused($focusedItemID, equals: minusID)

                if isNonZero {
                    LunaPillButton("Nullstill", isSelected: true, prominence: .glassPill, size: .compact) {
                        // Hand focus to the permanent `+` sibling inside the same `.focusSection()`
                        // BEFORE `isNonZero` flips to `false` so tvOS Focus Engine never jumps vertically.
                        focusedItemID = plusID
                        onReset()
                        Task { @MainActor in
                            await Task.yield()
                            if focusedItemID != plusID && focusedItemID != minusID {
                                focusedItemID = plusID
                            }
                            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                                try? await Task.sleep(nanoseconds: delayNs)
                                guard !Task.isCancelled else { return }
                                if focusedItemID != plusID && focusedItemID != minusID {
                                    focusedItemID = plusID
                                } else {
                                    return
                                }
                            }
                        }
                    }
                    .id(zeroID)
                    .focused($focusedItemID, equals: zeroID)
                }

                LunaPillButton(plusLabel, prominence: .glassPill, size: .compact, action: onPlus)
                    .id(plusID)
                    .focused($focusedItemID, equals: plusID)
            }
            .fixedSize(horizontal: true, vertical: false)
            .focusSection()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func chapterSubtitle(_ chapter: PlaybackChapter, isActive: Bool) -> String? {
        if isActive { return "Spilles nå" }
        return chapter.kind.badgeLabel
    }
}
