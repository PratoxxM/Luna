import SwiftUI
import AetherBridge

extension View {
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
        let track = viewModel.trackController
        VStack(alignment: .leading, spacing: 4) {
            LunaListRow(
                title: "Av",
                isSelected: track.activeSubtitleTrackIndex == nil,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == "sub-off"
            ) {
                track.clearSubtitleManually()
                onClose(false)
            }
            .id("sub-off")
            .focused($focusedItemID, equals: "sub-off")
            .prefersDefaultFocus(preferredActiveItemID == "sub-off", in: panelFocusNamespace)

            ForEach(track.drawerSubtitleOptions) { sub in
                let rowID = "sub-\(sub.id)"
                let selected = track.activeSubtitleTrackIndex == sub.id
                LunaListRow(
                    title: sub.humanLanguageTitle,
                    subtitle: sub.humanSubtitleDescription,
                    isSelected: selected,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == rowID
                ) {
                    track.selectSubtitleManually(sub.id)
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

        if let lockReason = track.kveldslysLockReason {
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
                delayMs: track.subtitleDelayMs
            ),
            subtitleNotice: nil,
            minusLabel: "−50 ms",
            plusLabel: "+50 ms",
            isNonZero: track.subtitleDelayMs != 0,
            focusPrefix: "sub-sync",
            onMinus: { track.adjustSubtitleDelay(byMs: -PlaybackSyncTimingPolicy.subtitleStepMs) },
            onReset: { track.resetSubtitleDelay() },
            onPlus: { track.adjustSubtitleDelay(byMs: PlaybackSyncTimingPolicy.subtitleStepMs) }
        )

        LunaListDivider()
            .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 4) {
            LunaListRow(
                title: track.isSearchingSubtitles ? LunaCopy.searchingSubtitlesTitle : LunaCopy.fetchSubtitlesTitle,
                subtitle: track.subtitleActionStatusMessage,
                leadingSystemImage: "magnifyingglass",
                trailingText: track.isSearchingSubtitles ? "…" : nil,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == "sub-fetch"
            ) {
                track.searchAndAttachSubtitles()
            }
            .id("sub-fetch")
            .focused($focusedItemID, equals: "sub-fetch")

            LunaListRow(
                title: track.isAutoAligningSubtitles ? LunaCopy.autoAligningSubtitlesTitle : LunaCopy.autoAlignSubtitlesTitle,
                subtitle: track.activeSubtitleTrackIndex == nil
                    ? LunaCopy.autoAlignSelectTrackFirst
                    : LunaCopy.autoAlignSubtitleIdle,
                leadingSystemImage: "waveform.path.ecg",
                trailingText: track.isAutoAligningSubtitles ? "…" : nil,
                dimUnfocusedTitle: true,
                externalIsFocused: focusedItemID == "sub-auto-align"
            ) {
                track.autoAlignActiveSubtitle()
            }
            .id("sub-auto-align")
            .focused($focusedItemID, equals: "sub-auto-align")
        }
        .quickPanelRowTabSwitch(
            enabled: canSwitchTabs,
            focusedItemID: focusedItemID,
            onSwitchTab: onSwitchTab
        )
    }

    // MARK: - Lyd

    @ViewBuilder
    var audioList: some View {
        let track = viewModel.trackController
        VStack(alignment: .leading, spacing: 4) {
            ForEach(track.drawerAudioOptions) { audio in
                let rowID = "aud-\(audio.id)"
                let selected = track.activeAudioTrackIndex == audio.id
                LunaListRow(
                    title: audio.humanLanguageTitle,
                    subtitle: audio.humanFormatSubtitle,
                    isSelected: selected,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == rowID
                ) {
                    track.selectAudioTrack(audio.id)
                    onClose(false)
                }
                .id(rowID)
                .focused($focusedItemID, equals: rowID)
                .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
            }

            if track.hasNorwegianAudioTrack || track.preferNorwegianAudio {
                LunaListRow(
                    title: LunaCopy.norwegianAudioTitle,
                    subtitle: track.preferNorwegianAudio
                        ? LunaCopy.norwegianAudioActiveSubtitle
                        : LunaCopy.norwegianAudioInactiveSubtitle,
                    trailingText: track.preferNorwegianAudio ? "På" : "Av",
                    trailingTextProminent: track.preferNorwegianAudio,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == "aud-norwegian-toggle"
                ) {
                    track.togglePreferNorwegianAudio()
                }
                .id("aud-norwegian-toggle")
                .focused($focusedItemID, equals: "aud-norwegian-toggle")
            }

            if !track.drawerAudioOptions.isEmpty || track.hasNorwegianAudioTrack || track.preferNorwegianAudio {
                LunaListDivider()
                    .padding(.vertical, 4)
            }

            ForEach(AudioEnhancementMode.allCases) { mode in
                let rowID = "aud-mode-\(mode.rawValue)"
                LunaListRow(
                    title: mode.displayTitle,
                    subtitle: mode.subtitle,
                    isSelected: track.audioEnhancement == mode,
                    dimUnfocusedTitle: true,
                    externalIsFocused: focusedItemID == rowID
                ) {
                    track.setAudioEnhancement(mode)
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
            Text(track.speakerLayoutHeaderSummary)
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
                        track.setSpeakerLayoutLive(mode)
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
                delayMs: track.audioDelayMs
            ),
            subtitleNotice: track.wirelessAudioDelayNotice,
            minusLabel: "−25 ms",
            plusLabel: "+25 ms",
            isNonZero: track.audioDelayMs != 0,
            focusPrefix: "aud-sync",
            onMinus: { track.adjustAudioDelay(byMs: -PlaybackSyncTimingPolicy.audioStepMs) },
            onReset: { track.resetAudioDelay() },
            onPlus: { track.adjustAudioDelay(byMs: PlaybackSyncTimingPolicy.audioStepMs) }
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
}
