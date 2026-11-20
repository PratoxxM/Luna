import SwiftUI
import AetherBridge

extension PlayerTopDrawerView {
    // MARK: - Tab 1: Info

    var infoTabContent: some View {
        let session = viewModel.activeSession
        let item = session?.item
        let headlineTitle = item?.seriesTitle ?? viewModel.currentRequest?.seriesTitle ?? item?.title ?? viewModel.currentRequest?.title ?? "Avspilling"

        return VStack(alignment: .leading, spacing: 12) {
            Text(headlineTitle)
                .font(LunaTheme.Font.heroSerif)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(2)

            Text(infoMetadataLine(session: session))
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)

            if let sourceLine = infoSourceSummaryLine(session: session) {
                Text(sourceLine)
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }

            PlayerDrawerOptionCardButton(
                title: "MetalFX: \(comfort.lowResUpscaleMode.displayTitle)",
                subtitle: viewModel.metalFXStatusSubtitle,
                isSelected: viewModel.isMetalFXActive,
                width: 440
            ) {
                viewModel.cycleMetalFXModeLive()
            }
            .padding(.top, 8)
            .focusSection()
        }
        .frame(maxWidth: 1020, alignment: .leading)
        .padding(.horizontal, LunaTheme.horizontalGutter)
    }

    // MARK: - Tab 2: Lyd og tekst

    var audioAndSubtitlesTabContent: some View {
        let audioOptions = viewModel.drawerAudioOptions
        let subtitleOptions = viewModel.drawerSubtitleOptions

        return VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 26) {
                    ForEach(audioOptions) { track in
                        PlayerDrawerOptionCardButton(
                            title: "Lyd: \(track.humanLanguageTitle)",
                            subtitle: track.humanFormatSubtitle,
                            isSelected: viewModel.activeAudioTrackIndex == track.id,
                            width: 340
                        ) {
                            viewModel.selectAudioTrack(track.id)
                        }
                    }

                    ForEach(subtitleOptions) { sub in
                        PlayerDrawerOptionCardButton(
                            title: "Tekst: \(sub.humanLanguageTitle)",
                            subtitle: sub.humanSubtitleDescription,
                            isSelected: viewModel.activeSubtitleTrackIndex == sub.id,
                            width: 340
                        ) {
                            viewModel.selectSubtitleManually(sub.id)
                        }
                    }

                    PlayerDrawerOptionCardButton(
                        title: "Tekst: Av",
                        subtitle: "Ingen undertekster",
                        isSelected: viewModel.activeSubtitleTrackIndex == nil,
                        width: 280
                    ) {
                        viewModel.clearSubtitleManually()
                    }

                    let kveldslysLock = viewModel.kveldslysLockReason
                    PlayerDrawerOptionCardButton(
                        title: "Kveldslys",
                        subtitle: kveldslysLock ?? comfort.hdrSubtitlePreset.displayTitle,
                        isSelected: kveldslysLock == nil && comfort.hdrSubtitlePreset != .white100,
                        isDimmedLocked: kveldslysLock != nil,
                        width: 300
                    ) {
                        guard viewModel.kveldslysLockReason == nil else { return }
                        cycleNightLightPreset()
                    }

                    PlayerDrawerOptionCardButton(
                        title: showAudioAdvancedControls ? "Skjul synk og klang" : "Synk og klang…",
                        subtitle: compactSyncSummary,
                        isSelected: showAudioAdvancedControls,
                        width: 300
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            showAudioAdvancedControls.toggle()
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 16)
            }
            .contentMargins(.zero, for: .scrollContent)
            .scrollClipDisabled()
            .focusSection()

            if showAudioAdvancedControls {
                audioSyncInlineBar
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .transition(.opacity)
            }
        }
    }

    private var audioSyncInlineBar: some View {
        HStack(spacing: 28) {
            HStack(spacing: 8) {
                ForEach(AudioEnhancementMode.allCases) { mode in
                    LunaPillButton(
                        mode.displayTitle,
                        isSelected: viewModel.audioEnhancement == mode,
                        prominence: .subtleChip,
                        size: .compact
                    ) {
                        viewModel.setAudioEnhancement(mode)
                    }
                }
            }

            HStack(spacing: 6) {
                sectionHeader("Tekst")
                LunaPillButton("−0,1 s", prominence: .subtleChip, size: .compact) {
                    viewModel.adjustSubtitleDelay(by: -0.1)
                }
                LunaPillButton("0 s", isSelected: abs(viewModel.subtitleDelaySeconds) < 0.01, prominence: .subtleChip, size: .compact) {
                    viewModel.resetSubtitleDelay()
                }
                LunaPillButton("+0,1 s", prominence: .subtleChip, size: .compact) {
                    viewModel.adjustSubtitleDelay(by: 0.1)
                }
            }

            HStack(spacing: 6) {
                sectionHeader("Lyd")
                LunaPillButton("−25 ms", prominence: .subtleChip, size: .compact) {
                    viewModel.adjustAudioDelay(byMs: -25)
                }
                LunaPillButton("0 ms", isSelected: viewModel.audioDelayMs == 0, prominence: .subtleChip, size: .compact) {
                    viewModel.resetAudioDelay()
                }
                LunaPillButton("+25 ms", prominence: .subtleChip, size: .compact) {
                    viewModel.adjustAudioDelay(byMs: 25)
                }
            }
        }
        .padding(.bottom, 6)
        .focusSection()
    }

    // MARK: - Tab 3: Kilde

    var sourceTabContent: some View {
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId
        let room = viewModel.activeSession?.roomName ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoadingAlternatives {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Henter tilgjengelige kilder…")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 28)
            } else if viewModel.alternatives.isEmpty {
                Text("Ingen alternative kilder funnet for denne tittelen.")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 26) {
                        ForEach(Array(viewModel.alternatives.enumerated()), id: \.element.id) { idx, cand in
                            let isCurrent = activeCandidateId != nil
                                ? (cand.candidateId == activeCandidateId)
                                : (cand.isActive == true)
                            PlayerDrawerOptionCardButton(
                                title: cand.humanDrawerTitle(
                                    roomName: room,
                                    isRecommended: idx == 0,
                                    isActive: false
                                ),
                                subtitle: cand.humanDrawerSubtitle(isActive: isCurrent),
                                isSelected: isCurrent,
                                width: 440
                            ) {
                                guard !isCurrent else {
                                    onClose()
                                    return
                                }
                                viewModel.triggerSourceSwitch(to: cand.candidateId)
                                onClose()
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 16)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }

    // MARK: - Tab 4: Kapitler

    var chaptersTabContent: some View {
        let activeChapterID = viewModel.activeChapter(at: chapterSnapshotTime)?.id

        return VStack(alignment: .leading, spacing: 12) {
            if viewModel.chapters.isEmpty {
                Text("Ingen kapitler i denne utgivelsen.")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 24)
            } else {
                sectionHeader(LunaCopy.chaptersHeader(viewModel.chapters.count))
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(viewModel.chapters) { ch in
                                PlayerDrawerOptionCardButton(
                                    title: ch.title,
                                    subtitle: chapterCardSubtitle(ch, isActive: ch.id == activeChapterID),
                                    isSelected: ch.id == activeChapterID,
                                    width: 300
                                ) {
                                    viewModel.seekToChapter(ch)
                                    onClose()
                                }
                                .id(ch.id)
                            }
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 16)
                    }
                    .contentMargins(.zero, for: .scrollContent)
                    .scrollClipDisabled()
                    .focusSection()
                    .onAppear {
                        chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                        if let targetID = viewModel.activeChapter(at: chapterSnapshotTime)?.id {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func cycleNightLightPreset() {
        let all = HDRSubtitlePreset.allCases
        guard let idx = all.firstIndex(of: comfort.hdrSubtitlePreset) else {
            comfort.hdrSubtitlePreset = .warm75
            return
        }
        comfort.hdrSubtitlePreset = all[(idx + 1) % all.count]
    }

    private var compactSyncSummary: String {
        let modeTitle = viewModel.audioEnhancement.displayTitle
        let audioMs = viewModel.audioDelayMs
        if audioMs == 0 && abs(viewModel.subtitleDelaySeconds) < 0.05 {
            return modeTitle
        }
        return "\(modeTitle) · \(ComfortPreferences.formatAudioDelayMs(audioMs))"
    }

    private func chapterCardSubtitle(_ chapter: PlaybackChapter, isActive: Bool) -> String {
        let timeStr = TimelineScrubberLeafView.formatSeconds(chapter.startSeconds)
        if isActive {
            return "\(timeStr) · Spiller nå"
        }
        if let badge = chapter.kind.badgeLabel {
            return "\(timeStr) · \(badge)"
        }
        return timeStr
    }

    private func infoMetadataLine(session: TvPlaybackSession?) -> String {
        var parts: [String] = []
        let season = session?.item.season ?? viewModel.currentRequest?.season
        let episode = session?.item.episode ?? viewModel.currentRequest?.episode
        if let code = LunaCopy.formatCompactEpisodeCode(season: season, episode: episode) {
            let epTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                session?.item.title ?? viewModel.currentRequest?.title,
                seriesTitle: session?.item.seriesTitle ?? viewModel.currentRequest?.seriesTitle,
                season: season,
                episode: episode
            )
            if let epTitle, !epTitle.isEmpty {
                parts.append("\(code) · \(epTitle)")
            } else {
                parts.append(code)
            }
        } else if let year = session?.item.year {
            parts.append(String(year))
        }

        let mins = Int((viewModel.effectiveDurationSeconds / 60.0).rounded())
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            parts.append(m > 0 ? "\(h) t \(m) min" : "\(h) t")
        } else if mins > 0 {
            parts.append("\(mins) min")
        }

        if let cand = session?.selectedCandidate {
            let quality = cand.humanQualitySummary
            if !quality.isEmpty {
                parts.append(quality)
            }
        }
        if let badge = viewModel.activeMetalFXBadge {
            parts.append(badge)
        }
        return parts.joined(separator: " · ")
    }

    private func infoSourceSummaryLine(session: TvPlaybackSession?) -> String? {
        guard let session else { return nil }
        let benefit = LunaCopy.tierBenefitLabel(
            tier: session.selectedCandidate.tier ?? session.selectedCandidate.source
        )
        let eq = LunaCopy.roomEquipmentLabel(
            hardwareProfile: session.hardwareProfile,
            roomName: session.roomName,
            serverLabel: roomEquipmentOverride
        )
        return "\(benefit) · Tilpasset \(session.roomName) (\(eq))"
    }
}
