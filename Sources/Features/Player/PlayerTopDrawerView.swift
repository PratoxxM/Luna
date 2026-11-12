import SwiftUI
import AetherBridge

enum PlayerTopDrawerTab: String, CaseIterable, Identifiable, Sendable {
    case audio
    case subtitles
    case sources
    case chaptersAndInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: return "Lyd"
        case .subtitles: return "Undertekster"
        case .sources: return "Kilder"
        case .chaptersAndInfo: return "Kapitler & info"
        }
    }

    var icon: String {
        switch self {
        case .audio: return "waveform"
        case .subtitles: return "captions.bubble"
        case .sources: return "arrow.triangle.2.circlepath"
        case .chaptersAndInfo: return "list.bullet.film"
        }
    }
}

/// Swipe-down Liquid Glass top drawer rendered over live playing video.
/// Built exclusively with native tvOS buttons (never SwiftUI `Menu`) so Focus Engine
/// stays responsive at 60/120 fps.
struct PlayerTopDrawerView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var comfort: ComfortPreferences
    let client: MediaOSClient?
    @Binding var selectedTab: PlayerTopDrawerTab
    let onClose: () -> Void

    @FocusState private var defaultTabFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                // Header tab bar
                HStack(spacing: 14) {
                    ForEach(PlayerTopDrawerTab.allCases) { tab in
                        let isFirst = (tab == selectedTab)
                        LunaPillButton(
                            tab.title,
                            systemImage: tab.icon,
                            isSelected: selectedTab == tab,
                            prominence: selectedTab == tab ? .primaryAmber : .subtleChip
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        }
                        .focused($defaultTabFocused, equals: isFirst)
                    }

                    Spacer()

                    LunaPillButton(
                        comfort.showNerdHUD ? "Nerde-HUD: På" : "Nerde-HUD",
                        systemImage: "gauge.with.dots.needle.67percent",
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
                    .overlay(LunaTheme.moonlight.opacity(0.14))

                // Active tab content
                Group {
                    switch selectedTab {
                    case .audio:
                        audioTabContent
                    case .subtitles:
                        subtitlesTabContent
                    case .sources:
                        sourcesTabContent
                    case .chaptersAndInfo:
                        chaptersAndInfoTabContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 42)
            .padding(.bottom, 34)
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            LunaTheme.canvas.opacity(0.92),
                            LunaTheme.surface.opacity(0.88),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LunaTheme.amber.opacity(0.28))
                    .frame(height: 1)
            }
            .shadow(color: .black.opacity(0.65), radius: 28, x: 0, y: 14)

            Spacer()
        }
        .onAppear {
            defaultTabFocused = true
        }
    }

    // MARK: - Tab 1: Lyd

    private var audioTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            // Left: Audio tracks
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
                .frame(maxHeight: 300)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: Audio sync (±50ms), Shaping & Object Audio status
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    let ms = Int((viewModel.audioDelaySeconds * 1000).rounded())
                    sectionHeader(String(format: "Lydsynkronisering (%+d ms)", ms))

                    HStack(spacing: 12) {
                        LunaPillButton("-50 ms", systemImage: "minus", prominence: .subtleChip) {
                            viewModel.adjustAudioDelay(by: -0.05)
                        }
                        LunaPillButton("0 ms", prominence: ms == 0 ? .glassPill : .subtleChip) {
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
                    Text(viewModel.audioEnhancement.subtitle)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.muted)
                }

                ObjectAudioStatusLeafView(
                    engine: viewModel.engine,
                    fallbackBadge: viewModel.audioFormatBadge
                )
            }
            .frame(width: 640, alignment: .leading)
        }
    }

    // MARK: - Tab 2: Undertekster (inkl. HDR/OLED-lysdemping)

    private var subtitlesTabContent: some View {
        HStack(alignment: .top, spacing: 40) {
            // Left: Subtitle track picker
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
                .frame(maxHeight: 320)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: Sync (±0.1s), OLED/HDR luminance dimming, Font Size & Box
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(String(format: "Tekstsynkronisering (%+.1f s)", viewModel.subtitleDelaySeconds))
                    HStack(spacing: 12) {
                        LunaPillButton("-0.1 s", systemImage: "minus", prominence: .subtleChip) {
                            viewModel.adjustSubtitleDelay(by: -0.1)
                        }
                        LunaPillButton("0.0 s", prominence: abs(viewModel.subtitleDelaySeconds) < 0.01 ? .glassPill : .subtleChip) {
                            viewModel.resetSubtitleDelay()
                        }
                        LunaPillButton("+0.1 s", systemImage: "plus", prominence: .subtleChip) {
                            viewModel.adjustSubtitleDelay(by: 0.1)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("OLED / HDR-komfortlys (gjelder tekst & PGS)")
                    ScrollView(.horizontal, showsIndicators: false) {
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
                        .padding(.vertical, 4)
                    }
                }

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Størrelse")
                        HStack(spacing: 10) {
                            ForEach(SubtitleFontSizePreset.allCases) { sz in
                                LunaPillButton(
                                    sz.displayTitle,
                                    isSelected: comfort.subtitleFontSize == sz,
                                    prominence: comfort.subtitleFontSize == sz ? .glassPill : .subtleChip
                                ) {
                                    comfort.subtitleFontSize = sz
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Bakgrunnsboks")
                        HStack(spacing: 10) {
                            ForEach(SubtitleBoxOpacityPreset.allCases) { box in
                                LunaPillButton(
                                    box.displayTitle,
                                    isSelected: comfort.subtitleBoxOpacity == box,
                                    prominence: comfort.subtitleBoxOpacity == box ? .glassPill : .subtleChip
                                ) {
                                    comfort.subtitleBoxOpacity = box
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 760, alignment: .leading)
        }
    }

    // MARK: - Tab 3: Kilder (Sømløst tidskodebytte)

    private var sourcesTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("Tilgjengelige kilder (bytter sømløst uten å miste tidskode)")
                Spacer()
                if let room = viewModel.activeSession?.roomName {
                    Text("Rangert for \(room)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.amber)
                }
            }

            if viewModel.isLoadingAlternatives {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("Henter rangerte lokale og Usenet VFS-kilder…")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.vertical, 28)
            } else if viewModel.alternatives.isEmpty {
                Text("Fant ingen alternative kilder for denne tittelen.")
                    .font(.callout)
                    .foregroundStyle(LunaTheme.muted)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.alternatives) { cand in
                            let isCurrent = cand.isActive == true ||
                                cand.candidateId == viewModel.activeSession?.selectedCandidate.candidateId
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
                                onClose()
                                Task {
                                    await viewModel.switchSource(to: cand.candidateId)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }
        }
        .task {
            if viewModel.alternatives.isEmpty {
                await viewModel.loadAlternatives()
            }
        }
    }

    // MARK: - Tab 4: Kapitler & info

    private var chaptersAndInfoTabContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !viewModel.chapters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Kapitler (\(viewModel.chapters.count))")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.chapters) { ch in
                                ChapterPillCardButton(chapter: ch) {
                                    viewModel.seekToChapter(ch)
                                    onClose()
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Om tittelen")
                    let synopsis = viewModel.itemDetail?.overviewNo
                        ?? viewModel.itemDetail?.overview
                        ?? viewModel.itemDetail?.overviewEn
                        ?? "Ingen beskrivelse tilgjengelig."
                    Text(synopsis)
                        .font(.callout)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.9))
                        .lineLimit(4)
                        .frame(maxWidth: 780, alignment: .leading)
                }

                if let cast = viewModel.itemDetail?.castMembers, !cast.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("I rollene")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(cast.prefix(8)) { member in
                                    HStack(spacing: 10) {
                                        if let raw = member.profileUrl, let url = client?.buildAbsoluteURL(raw) {
                                            CachedArtworkView(
                                                url: url,
                                                client: client,
                                                maxPixelSize: 160,
                                                placeholderSymbol: "person.fill",
                                                contentMode: .fill
                                            )
                                            .frame(width: 48, height: 48)
                                            .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(LunaTheme.surfaceRaised)
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    Image(systemName: "person.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(LunaTheme.muted)
                                                )
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.name)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            if let role = member.character, !role.isEmpty {
                                                Text(role)
                                                    .font(.caption2)
                                                    .foregroundStyle(LunaTheme.muted)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.06), in: Capsule())
                                }
                            }
                        }
                    }
                }
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
            b.append("NVMe .srt")
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

// MARK: - Focus-Safe Row & Chapter Cards

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
                            .foregroundStyle(badge.contains("NVMe") ? LunaTheme.emerald : LunaTheme.amber)
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
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

private struct ChapterPillCardButton: View {
    let chapter: PlaybackChapter
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(TimelineScrubberLeafView.formatSeconds(chapter.startSeconds))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(LunaTheme.amber)

                    if let kindLabel = chapter.kind.badgeLabel {
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
            .frame(minWidth: 210, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? LunaTheme.amber.opacity(0.24) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isFocused ? LunaTheme.amber : Color.white.opacity(0.12), lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(.plain)
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
                Text("Objektlyd aktiv · \(obj.layout.rawValue) · \(obj.activeObjects) aktive objekter (\(obj.elevatedObjects) i høyden)")
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
        .onReceive(engine.diagnostics.$liveTelemetry) { telemetry = $0 }
    }
}
