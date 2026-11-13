import SwiftUI
import AetherBridge

enum PlayerTopDrawerTab: String, CaseIterable, Identifiable, Sendable {
    case subtitles
    case audio
    case sourcesAndChapters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtitles: return "Undertekster"
        case .audio: return "Lyd"
        case .sourcesAndChapters: return "Kilde & Kapitler"
        }
    }

    var icon: String {
        switch self {
        case .subtitles: return "captions.bubble"
        case .audio: return "waveform"
        case .sourcesAndChapters: return "list.bullet.film"
        }
    }
}

/// Compact 3-tab top drawer rendered in dark HDR-safe cinema glass when swiping down.
/// Built exclusively with focus-safe custom buttons (`.focusEffectDisabled()`, never SwiftUI `Menu`).
struct PlayerTopDrawerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var comfort: ComfortPreferences
    @Binding var selectedTab: PlayerTopDrawerTab
    let onClose: () -> Void

    @FocusState private var focusedTab: PlayerTopDrawerTab?
    @State private var chapterSnapshotTime: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ForEach(PlayerTopDrawerTab.allCases) { tab in
                        LunaPillButton(
                            tab.title,
                            systemImage: tab.icon,
                            isSelected: selectedTab == tab,
                            prominence: selectedTab == tab ? .primaryAmber : .subtleChip
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedTab = tab
                            }
                        }
                        .focused($focusedTab, equals: tab)
                    }

                    Spacer()

                    LunaPillButton(
                        "",
                        systemImage: comfort.showNerdHUD ? "info.circle.fill" : "info.circle",
                        isSelected: comfort.showNerdHUD,
                        prominence: .subtleChip
                    ) {
                        comfort.showNerdHUD.toggle()
                    }

                    LunaPillButton("Lukk", systemImage: "chevron.up", prominence: .subtleChip) {
                        onClose()
                    }
                }

                Divider()
                    .overlay(LunaTheme.moonlight.opacity(0.12))

                Group {
                    switch selectedTab {
                    case .subtitles:
                        subtitlesTabContent
                    case .audio:
                        audioTabContent
                    case .sourcesAndChapters:
                        sourcesAndChaptersTabContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 38)
            .padding(.bottom, 30)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 9.0 / 255.0, green: 12.0 / 255.0, blue: 19.0 / 255.0).opacity(0.96),
                        Color(red: 13.0 / 255.0, green: 17.0 / 255.0, blue: 26.0 / 255.0).opacity(0.94),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LunaTheme.amber.opacity(0.28))
                    .frame(height: 1)
            }
            .shadow(color: .black.opacity(0.72), radius: 28, x: 0, y: 14)

            Spacer()
        }
        .onAppear {
            focusedTab = selectedTab
        }
    }

    // MARK: - Tab 1: Undertekster

    private var subtitlesTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Undertekstspor")

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
                            let isSelected = (viewModel.activeSubtitleTrackIndex == track.id)
                            DrawerTrackRowButton(
                                title: formatSubtitleTitle(track),
                                subtitle: formatSubtitleSubtitle(track),
                                badges: subtitleTrackBadges(track),
                                isSelected: isSelected
                            ) {
                                viewModel.selectSubtitleManually(track.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(String(format: "Tekstsynk (%+.1f s)", viewModel.subtitleDelaySeconds))
                    HStack(spacing: 12) {
                        LunaPillButton("-0.1 s", systemImage: "minus", prominence: .subtleChip) {
                            viewModel.adjustSubtitleDelay(by: -0.1)
                        }
                        LunaPillButton(
                            "0.0 s",
                            isSelected: abs(viewModel.subtitleDelaySeconds) < 0.01,
                            prominence: abs(viewModel.subtitleDelaySeconds) < 0.01 ? .glassPill : .subtleChip
                        ) {
                            viewModel.resetSubtitleDelay()
                        }
                        LunaPillButton("+0.1 s", systemImage: "plus", prominence: .subtleChip) {
                            viewModel.adjustSubtitleDelay(by: 0.1)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Kveldslys i HDR / Dolby Vision")
                    HStack(spacing: 10) {
                        ForEach(HDRSubtitlePreset.allCases) { preset in
                            LunaPillButton(
                                preset.displayTitle,
                                isSelected: comfort.hdrSubtitlePreset == preset,
                                prominence: comfort.hdrSubtitlePreset == preset ? .glassPill : .subtleChip
                            ) {
                                comfort.hdrSubtitlePreset = preset
                            }
                        }
                    }
                }
            }
            .frame(width: 680, alignment: .leading)
        }
    }

    // MARK: - Tab 2: Lyd

    private var audioTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Lydspor")

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if viewModel.audioTracks.isEmpty {
                            Text("Ingen separate lydspor rapportert av strømmen.")
                                .font(.callout)
                                .foregroundStyle(LunaTheme.muted)
                        } else {
                            ForEach(viewModel.audioTracks) { track in
                                let isSelected = (viewModel.activeAudioTrackIndex == track.id)
                                DrawerTrackRowButton(
                                    title: formatAudioTitle(track),
                                    subtitle: formatAudioSubtitle(track),
                                    badges: audioTrackBadges(track),
                                    isSelected: isSelected
                                ) {
                                    viewModel.selectAudioTrack(track.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    let ms = Int((viewModel.audioDelaySeconds * 1000).rounded())
                    sectionHeader(String(format: "Lydsynk (%+d ms)", ms))

                    HStack(spacing: 12) {
                        LunaPillButton("-50 ms", systemImage: "minus", prominence: .subtleChip) {
                            viewModel.adjustAudioDelay(by: -0.05)
                        }
                        LunaPillButton(
                            "0 ms",
                            isSelected: ms == 0,
                            prominence: ms == 0 ? .glassPill : .subtleChip
                        ) {
                            viewModel.resetAudioDelay()
                        }
                        LunaPillButton("+50 ms", systemImage: "plus", prominence: .subtleChip) {
                            viewModel.adjustAudioDelay(by: 0.05)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Klang & Nattmodus")

                    HStack(spacing: 12) {
                        ForEach(AudioEnhancementMode.allCases) { mode in
                            LunaPillButton(
                                mode.displayTitle,
                                isSelected: viewModel.audioEnhancement == mode,
                                prominence: viewModel.audioEnhancement == mode ? .glassPill : .subtleChip
                            ) {
                                viewModel.setAudioEnhancement(mode)
                            }
                        }
                    }
                }

                ObjectAudioStatusLeafView(
                    engine: viewModel.engine,
                    fallbackBadge: viewModel.audioFormatBadge
                )
            }
            .frame(width: 640, alignment: .leading)
        }
    }

    // MARK: - Tab 3: Kilde & Kapitler

    private var sourcesAndChaptersTabContent: some View {
        let activeChapterID = viewModel.activeChapter(at: chapterSnapshotTime)?.id
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId

        return VStack(alignment: .leading, spacing: 20) {
            if !viewModel.chapters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Kapitler (\(viewModel.chapters.count))")
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
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
                            .padding(.vertical, 6)
                        }
                        .scrollClipDisabled()
                        .onAppear {
                            chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                            if let targetID = viewModel.activeChapter(at: chapterSnapshotTime)?.id {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("Avspillingskilde (sømløst bytte på samme tidskode)")
                    Spacer()
                    if let room = viewModel.activeSession?.roomName {
                        Text(room)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LunaTheme.amber)
                    }
                }

                if viewModel.isLoadingAlternatives {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Henter tilgjengelige kilder…")
                            .font(.callout)
                            .foregroundStyle(LunaTheme.muted)
                    }
                    .padding(.vertical, 18)
                } else if viewModel.alternatives.isEmpty {
                    Text("Ingen alternative kilder funnet.")
                        .font(.callout)
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
                                    subtitle: cand.releaseTitle,
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
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: viewModel.chapters.isEmpty ? 280 : 200)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Lavoppløst oppskalering (neste start)")

                HStack(spacing: 10) {
                    ForEach(LowResUpscaleMode.allCases) { mode in
                        LunaPillButton(
                            mode.displayTitle,
                            isSelected: comfort.lowResUpscaleMode == mode,
                            prominence: comfort.lowResUpscaleMode == mode ? .glassPill : .subtleChip
                        ) {
                            comfort.lowResUpscaleMode = mode
                        }
                    }
                }
            }
        }
        .task(id: viewModel.activeSession?.sessionId) {
            chapterSnapshotTime = max(0, viewModel.engine.currentTime)
            if viewModel.alternativesSessionId != viewModel.activeSession?.sessionId || viewModel.alternatives.isEmpty {
                await viewModel.loadAlternatives()
            }
        }
    }

    // MARK: - Formatting Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(LunaTheme.muted)
    }

    private func formatAudioTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty {
            return track.name
        }
        return languageDisplayName(track.language) ?? "Lydspor \(track.id + 1)"
    }

    private func formatAudioSubtitle(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = languageDisplayName(track.language) {
            parts.append(lang)
        }
        if let profile = track.profile, !profile.isEmpty {
            parts.append(profile)
        } else {
            parts.append(track.codec.uppercased())
        }
        if let layout = track.channelLayout, !layout.isEmpty {
            parts.append(layout)
        } else if track.channels > 0 {
            parts.append("\(track.channels) ch")
        }
        return parts.joined(separator: " · ")
    }

    private func audioTrackBadges(_ track: TrackInfo) -> [String] {
        var b: [String] = []
        if track.isAtmos { b.append("Atmos") }
        if track.isDTSX { b.append("DTS:X") }
        if track.isCommentary { b.append("Kommentar") }
        return b
    }

    private func formatSubtitleTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty {
            return track.name
        }
        return languageDisplayName(track.language) ?? "Undertekst \(track.id + 1)"
    }

    private func formatSubtitleSubtitle(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = languageDisplayName(track.language) {
            parts.append(lang)
        }
        parts.append(track.codec.uppercased())
        return parts.joined(separator: " · ")
    }

    private func subtitleTrackBadges(_ track: TrackInfo) -> [String] {
        var b: [String] = []
        let c = track.codec.lowercased()
        if track.isExternal {
            b.append("Ekstern .srt")
        } else if c.contains("pgs") {
            b.append("PGS")
        } else if c.contains("ass") || c.contains("ssa") {
            b.append("ASS")
        } else {
            b.append("SRT")
        }
        if track.isForced { b.append("Forced") }
        if track.isHearingImpaired { b.append("SDH") }
        return b
    }

    private func languageDisplayName(_ raw: String?) -> String? {
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

// MARK: - Focus-Safe Row & Chapter Cards (`.focusEffectDisabled()`)

private struct DrawerTrackRowButton: View {
    let title: String
    let subtitle: String
    let badges: [String]
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LunaTheme.amber : LunaTheme.muted.opacity(0.65))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LunaTheme.amber)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.amber.opacity(0.22)
                            : (isSelected ? LunaTheme.amber.opacity(0.12) : Color.white.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.amber : (isSelected ? LunaTheme.amber.opacity(0.45) : Color.white.opacity(0.08)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

private struct ChapterPillCardButton: View {
    let chapter: PlaybackChapter
    var isActive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(TimelineScrubberLeafView.formatSeconds(chapter.startSeconds))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(LunaTheme.amber)

                    if isActive {
                        Text("Spiller nå")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LunaTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(LunaTheme.amber.opacity(0.18), in: Capsule())
                    } else if let kindLabel = chapter.kind.badgeLabel {
                        Text(kindLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LunaTheme.canvas)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(LunaTheme.amber, in: Capsule())
                    }
                }

                Text(chapter.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minWidth: 204, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.amber.opacity(0.24)
                            : (isActive ? LunaTheme.amber.opacity(0.12) : Color.white.opacity(0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused ? LunaTheme.amber : (isActive ? LunaTheme.amber.opacity(0.55) : Color.white.opacity(0.12)),
                        lineWidth: isFocused ? 2 : (isActive ? 1.5 : 1)
                    )
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

private struct ObjectAudioStatusLeafView: View {
    let engine: AetherEngine
    let fallbackBadge: String

    @State private var telemetry: LiveTelemetry?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(telemetry?.objectAudio != nil ? LunaTheme.emerald : LunaTheme.amber)
            if let obj = telemetry?.objectAudio {
                Text("Objektlyd · \(obj.layout.rawValue) · \(obj.activeObjects) objekter")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LunaTheme.moonlight)
            } else {
                Text("Aktiv lydkjede: \(fallbackBadge)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: Capsule())
        .onAppear { telemetry = engine.diagnostics.liveTelemetry }
        .onChange(of: fallbackBadge) { _, _ in
            telemetry = engine.diagnostics.liveTelemetry
        }
    }
}
