import SwiftUI
import AetherBridge

extension PlayerTopDrawerView {
    // MARK: - Tab 1: Info

    var infoTabContent: some View {
        let session = viewModel.activeSession
        let item = session?.item
        let headlineTitle = item?.seriesTitle ?? viewModel.currentRequest?.seriesTitle ?? item?.title ?? viewModel.currentRequest?.title ?? "Avspilling"
        let roomDisplay = session.map {
            let eq = LunaCopy.roomEquipmentLabel(
                hardwareProfile: $0.hardwareProfile,
                roomName: $0.roomName,
                serverLabel: roomEquipmentOverride
            )
            return "\($0.roomName) · \(eq)"
        }
        let benefitLine = session.map {
            LunaCopy.tierBenefitLabel(tier: $0.selectedCandidate.tier ?? $0.selectedCandidate.source)
        }
        let subtitleColumns = [
            GridItem(.flexible(minimum: 200), spacing: 10),
            GridItem(.flexible(minimum: 200), spacing: 10),
        ]

        return HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Text(headlineTitle)
                    .font(LunaTheme.Font.heroSerif)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(2)

                if let meta = infoMetadataLine(session: session) {
                    Text(meta)
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.moonlight)
                }

                HStack(spacing: 10) {
                    infoBadgePill(viewModel.videoFormatBadge)
                    if !viewModel.audioFormatBadge.isEmpty {
                        infoBadgePill(viewModel.audioFormatBadge)
                    }
                    if let tierShort = session.map({
                        LunaCopy.tierShortLabel(
                            tier: $0.selectedCandidate.tier,
                            source: $0.selectedCandidate.source
                        )
                    }) {
                        infoBadgePill(tierShort)
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Kveldslys")
                    LazyVGrid(columns: subtitleColumns, alignment: .leading, spacing: 8) {
                        ForEach(HDRSubtitlePreset.allCases) { preset in
                            LunaPillButton(
                                preset.displayTitle,
                                isSelected: comfort.hdrSubtitlePreset == preset,
                                prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                comfort.hdrSubtitlePreset = preset
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                if let roomDisplay {
                    infoSummaryRow(title: "Rom og oppsett", value: roomDisplay)
                }
                if let benefitLine {
                    infoSummaryRow(title: "Levering", value: benefitLine)
                }
                infoSummaryRow(
                    title: "Varighet",
                    value: TimelineScrubberLeafView.formatSeconds(viewModel.effectiveDurationSeconds)
                )
            }
            .frame(width: 600, alignment: .leading)
        }
    }

    // MARK: - Tab 2: Lyd og tekst

    var audioAndSubtitlesTabContent: some View {
        let subtitleColumns = [
            GridItem(.flexible(minimum: 180), spacing: 10),
            GridItem(.flexible(minimum: 180), spacing: 10),
        ]

        return HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Undertekster")

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        DrawerTrackRowButton(
                            title: "Av",
                            subtitle: "Ingen undertekster",
                            badges: [],
                            isSelected: viewModel.activeSubtitleTrackIndex == nil
                        ) {
                            viewModel.clearSubtitleManually()
                        }

                        ForEach(viewModel.subtitleTracks) { track in
                            DrawerTrackRowButton(
                                title: formatSubtitleTitle(track),
                                subtitle: formatSubtitleSubtitle(track),
                                badges: subtitleTrackBadges(track),
                                isSelected: viewModel.activeSubtitleTrackIndex == track.id
                            ) {
                                viewModel.selectSubtitleManually(track.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 280)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Lydspor")

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if viewModel.audioTracks.isEmpty {
                            Text("Ingen separate lydspor funnet.")
                                .font(LunaTheme.Font.caption)
                                .foregroundStyle(LunaTheme.muted)
                        } else {
                            ForEach(viewModel.audioTracks) { track in
                                DrawerTrackRowButton(
                                    title: formatAudioTitle(track),
                                    subtitle: formatAudioSubtitle(track),
                                    badges: audioTrackBadges(track),
                                    isSelected: viewModel.activeAudioTrackIndex == track.id
                                ) {
                                    viewModel.selectAudioTrack(track.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 280)
            }
            .frame(width: 470, alignment: .leading)
            .focusSection()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Kveldslys")
                    LazyVGrid(columns: subtitleColumns, alignment: .leading, spacing: 8) {
                        ForEach(HDRSubtitlePreset.allCases) { preset in
                            LunaPillButton(
                                preset.displayTitle,
                                isSelected: comfort.hdrSubtitlePreset == preset,
                                prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                comfort.hdrSubtitlePreset = preset
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Klang og nattmodus")
                    HStack(spacing: 8) {
                        ForEach(AudioEnhancementMode.allCases) { mode in
                            LunaPillButton(
                                mode.displayTitle,
                                isSelected: viewModel.audioEnhancement == mode,
                                prominence: viewModel.audioEnhancement == mode ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                viewModel.setAudioEnhancement(mode)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        let delay = abs(viewModel.subtitleDelaySeconds) < 0.05 ? 0.0 : viewModel.subtitleDelaySeconds
                        let delayText: String = {
                            if delay == 0 { return "0,0 s" }
                            if delay > 0 { return "+\(LunaCopy.formatDecimal(delay, decimals: 1)) s" }
                            return "−\(LunaCopy.formatDecimal(abs(delay), decimals: 1)) s"
                        }()
                        sectionHeader("Tekstsynk (\(delayText))")
                        HStack(spacing: 6) {
                            LunaPillButton("−0,1 s", prominence: .subtleChip, size: .compact) {
                                viewModel.adjustSubtitleDelay(by: -0.1)
                            }
                            LunaPillButton(
                                "0 s",
                                isSelected: abs(viewModel.subtitleDelaySeconds) < 0.01,
                                prominence: abs(viewModel.subtitleDelaySeconds) < 0.01 ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                viewModel.resetSubtitleDelay()
                            }
                            LunaPillButton("+0,1 s", prominence: .subtleChip, size: .compact) {
                                viewModel.adjustSubtitleDelay(by: 0.1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        let ms = viewModel.audioDelayMs
                        let msHeader = ms < 0 ? "−\(abs(ms)) ms" : (ms > 0 ? "+\(ms) ms" : "0 ms")
                        sectionHeader("Lydsynk (\(msHeader))")
                        HStack(spacing: 6) {
                            LunaPillButton("−25 ms", prominence: .subtleChip, size: .compact) {
                                viewModel.adjustAudioDelay(byMs: -25)
                            }
                            LunaPillButton(
                                "0 ms",
                                isSelected: ms == 0,
                                prominence: ms == 0 ? .glassPill : .subtleChip,
                                size: .compact
                            ) {
                                viewModel.resetAudioDelay()
                            }
                            LunaPillButton("+25 ms", prominence: .subtleChip, size: .compact) {
                                viewModel.adjustAudioDelay(byMs: 25)
                            }
                        }
                    }
                }

                ObjectAudioStatusLeafView(
                    fallbackBadge: formattedAudioChainSummary
                )
            }
            .frame(width: 580, alignment: .leading)
            .focusSection()
        }
    }

    // MARK: - Tab 3: Kilde

    var sourceTabContent: some View {
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader("Velg kilde (bytter på samme tidspunkt)")
                    Spacer()
                    if let room = viewModel.activeSession?.roomName {
                        Text(room)
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                }

                if viewModel.isLoadingAlternatives {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Henter tilgjengelige kilder…")
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.muted)
                    }
                    .padding(.vertical, 16)
                } else if viewModel.alternatives.isEmpty {
                    Text("Ingen alternative kilder funnet for denne tittelen.")
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(LunaTheme.muted)
                        .padding(.vertical, 14)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(viewModel.alternatives) { cand in
                                let isCurrent = activeCandidateId != nil
                                    ? (cand.candidateId == activeCandidateId)
                                    : (cand.isActive == true)
                                DrawerTrackRowButton(
                                    title: cand.displayHeadline,
                                    subtitle: sourceCandidateSubtitle(cand),
                                    badges: cand.capabilityBadges,
                                    isSelected: isCurrent
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .scrollClipDisabled()
                    .frame(maxHeight: 250)
                }
            }
            .focusSection()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Lavoppløst oppskalering (neste start)")

                HStack(spacing: 10) {
                    ForEach(LowResUpscaleMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.lowResUpscaleMode == mode,
                            prominence: comfort.lowResUpscaleMode == mode ? .glassPill : .subtleChip,
                            size: .compact
                        ) {
                            comfort.lowResUpscaleMode = mode
                        }
                    }
                }
            }
            .focusSection()
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
                    .padding(.vertical, 24)
            } else {
                sectionHeader(LunaCopy.chaptersHeader(viewModel.chapters.count))
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.chapters) { ch in
                                ChapterPillCardButton(
                                    chapter: ch,
                                    isActive: ch.id == activeChapterID
                                ) {
                                    viewModel.seekToChapter(ch)
                                    onClose()
                                }
                                .id(ch.id)
                            }
                        }
                        .padding(.vertical, 14)
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

    // MARK: - Info & Track Formatting Helpers

    private var formattedAudioChainSummary: String {
        let badge = viewModel.audioFormatBadge
        if let decoder = viewModel.activeAudioDecoder, !decoder.isEmpty {
            return badge.isEmpty ? decoder : "\(badge) · \(decoder)"
        }
        return badge.isEmpty ? "Direkte lydutgang" : badge
    }

    private func infoMetadataLine(session: TvPlaybackSession?) -> String? {
        var parts: [String] = []
        let season = session?.item.season ?? viewModel.currentRequest?.season
        let episode = session?.item.episode ?? viewModel.currentRequest?.episode
        if let code = LunaCopy.formatListEpisodeCode(season: season, episode: episode) {
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
        }
        if let year = session?.item.year {
            parts.append(String(year))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func infoBadgePill(_ label: String) -> some View {
        Text(label)
            .font(LunaTheme.Font.badge)
            .foregroundStyle(LunaTheme.linen)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(LunaTheme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
    }

    private func infoSummaryRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(LunaTheme.Font.settingsMetaTitle)
                .foregroundStyle(LunaTheme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(LunaTheme.Font.settingsMetaValue)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))
        .lunaTopLightEdge(cornerRadius: LunaTokens.Radius.chip)
    }

    private func sourceCandidateSubtitle(_ cand: TvCandidateInfo) -> String {
        let benefit = LunaCopy.tierBenefitLabel(tier: cand.tier ?? cand.source)
        if let chips = cand.explanationChips, !chips.isEmpty {
            return "\(benefit) · \(chips.joined(separator: " · "))"
        }
        return benefit
    }

    func formatAudioTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty {
            return track.name
        }
        return languageDisplayName(track.language) ?? "Lydspor \(track.id + 1)"
    }

    func formatAudioSubtitle(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = languageDisplayName(track.language) {
            parts.append(lang)
        }
        if let profile = track.profile, !profile.isEmpty {
            parts.append(profile)
        } else if !track.codec.isEmpty {
            parts.append(track.codec.uppercased())
        }
        if let layout = track.channelLayout, !layout.isEmpty {
            parts.append(layout)
        } else if track.channels > 0 {
            parts.append(LunaCopy.plural(track.channels, "kanal", "kanaler"))
        }
        return parts.joined(separator: " · ")
    }

    func audioTrackBadges(_ track: TrackInfo) -> [String] {
        var b: [String] = []
        if track.isAtmos { b.append("Atmos") }
        if track.isDTSX { b.append("DTS:X") }
        if track.isCommentary { b.append("Kommentar") }
        return b
    }

    func formatSubtitleTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty {
            return track.name
        }
        return languageDisplayName(track.language) ?? "Undertekst \(track.id + 1)"
    }

    func formatSubtitleSubtitle(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = languageDisplayName(track.language) {
            parts.append(lang)
        }
        let codecUpper = track.codec.uppercased()
        if !codecUpper.isEmpty && codecUpper != "UNKNOWN" {
            parts.append(codecUpper)
        }
        return parts.joined(separator: " · ")
    }

    func subtitleTrackBadges(_ track: TrackInfo) -> [String] {
        var b: [String] = []
        let c = track.codec.lowercased()
        if track.isExternal {
            b.append("Ekstern")
        } else if c.contains("pgs") {
            b.append("PGS")
        } else if c.contains("ass") || c.contains("ssa") {
            b.append("ASS")
        }
        if track.isForced { b.append("Tvunget") }
        if track.isHearingImpaired { b.append("Hørselshemmede") }
        return b
    }

    func languageDisplayName(_ raw: String?) -> String? {
        guard let norm = SmartTrackRuleEngine.normalizeLanguage(raw) else { return nil }
        switch norm {
        case "nob": return "Norsk"
        case "eng": return "Engelsk"
        case "swe": return "Svensk"
        case "dan": return "Dansk"
        case "jpn": return "Japansk"
        case "kor": return "Koreansk"
        case "fra": return "Fransk"
        case "deu": return "Tysk"
        case "spa": return "Spansk"
        default: return raw?.uppercased()
        }
    }
}
