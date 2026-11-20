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
}

/// Compact floating vertical quick-list panel anchored above the bottom OSD.
/// Focus starts deterministically on the active (`✓`) item inside each list and closes back cleanly.
struct PlayerQuickPanelView: View {
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var comfort: ComfortPreferences
    let tab: PlayerQuickPanelTab
    let onClose: (_ returnFocusToPill: Bool) -> Void

    @FocusState private var focusedItemID: String?
    @State private var chapterSnapshotTime: Double = 0
    @State private var contentHeight: CGFloat = 280
    @State private var focusRetryTask: Task<Void, Never>?
    @Namespace private var panelFocusNamespace

    private var panelWidth: CGFloat {
        tab == .source ? 1120 : 680
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack {
                VStack(alignment: .leading, spacing: 14) {
                    panelHeader

                    Rectangle()
                        .fill(LunaTheme.warmBorderSubtle)
                        .frame(height: 1)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                panelListContent
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .onGeometryChange(for: CGFloat.self) { geo in
                                geo.size.height
                            } action: { newHeight in
                                if newHeight > 10, abs(contentHeight - newHeight) > 1 {
                                    contentHeight = newHeight
                                }
                            }
                        }
                        .frame(height: min(max(contentHeight, 120), 540))
                        .onAppear {
                            chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                            focusPreferredActiveItem(proxy: proxy)
                        }
                        .onChange(of: tab) { _, _ in
                            chapterSnapshotTime = max(0, viewModel.engine.currentTime)
                            focusPreferredActiveItem(proxy: proxy)
                        }
                        .onChange(of: viewModel.alternatives.map(\.id)) { _, _ in
                            if tab == .source {
                                focusPreferredActiveItem(proxy: proxy)
                            }
                        }
                    }
                    .focusScope(panelFocusNamespace)
                    .focusSection()
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
                .frame(width: panelWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LunaTheme.cinemaGlass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1)
                )
                .shadow(
                    color: LunaTheme.pureBlack.opacity(0.68),
                    radius: 34,
                    x: 0,
                    y: 16
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, 286)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .onDisappear {
            focusRetryTask?.cancel()
            focusRetryTask = nil
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.systemImage)
                .font(LunaTheme.Font.pillIcon)
                .foregroundStyle(LunaTheme.amber)

            Text(tab.title)
                .font(LunaTheme.Font.cardTitle)
                .foregroundStyle(LunaTheme.linen)

            Spacer(minLength: 12)

            Text(headerSubtitle)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(1)
        }
    }

    private var headerSubtitle: String {
        switch tab {
        case .subtitles:
            if let subId = viewModel.activeSubtitleTrackIndex,
               let active = viewModel.drawerSubtitleOptions.first(where: { $0.id == subId }) {
                return active.humanLanguageTitle
            }
            return "Av"
        case .audio:
            if let audId = viewModel.activeAudioTrackIndex,
               let active = viewModel.drawerAudioOptions.first(where: { $0.id == audId }) {
                return active.humanFormatSubtitle
            }
            return viewModel.audioEnhancement.displayTitle
        case .source:
            let room = (viewModel.activeSession?.roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return room.isEmpty ? "Velg kilde" : "Tilpasset \(room)"
        case .picture:
            return viewModel.metalFXStatusSubtitle
        case .chapters:
            return LunaCopy.chaptersHeader(viewModel.chapters.count)
        }
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
        QuickPanelRowButton(
            title: "Av",
            subtitle: "Ingen undertekster",
            isSelected: viewModel.activeSubtitleTrackIndex == nil,
            isFocused: focusedItemID == "sub-off"
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
            QuickPanelRowButton(
                title: sub.humanLanguageTitle,
                subtitle: sub.humanSubtitleDescription,
                isSelected: selected,
                isFocused: focusedItemID == rowID
            ) {
                viewModel.selectSubtitleManually(sub.id)
                onClose(false)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        Rectangle()
            .fill(LunaTheme.warmBorderSubtle)
            .frame(height: 1)
            .padding(.vertical, 4)

        let kveldslysLock = viewModel.kveldslysLockReason
        QuickPanelRowButton(
            title: "Kveldslys",
            subtitle: kveldslysLock ?? comfort.hdrSubtitlePreset.displayTitle,
            isSelected: kveldslysLock == nil && comfort.hdrSubtitlePreset != .white100,
            isDimmedLocked: kveldslysLock != nil,
            isFocused: focusedItemID == "sub-kveldslys"
        ) {
            guard viewModel.kveldslysLockReason == nil else { return }
            cycleNightLightPreset()
        }
        .id("sub-kveldslys")
        .focused($focusedItemID, equals: "sub-kveldslys")

        HStack(spacing: 10) {
            Text("Tekstsynk")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)

            Spacer(minLength: 8)

            Text(formatSubtitleDelay(viewModel.subtitleDelaySeconds))
                .font(LunaTheme.Font.settingsAudioDelay)
                .foregroundStyle(LunaTheme.moonlight)

            LunaPillButton("−0,1 s", prominence: .subtleChip, size: .compact) {
                viewModel.adjustSubtitleDelay(by: -0.1)
            }
            .focused($focusedItemID, equals: "sub-sync-minus")

            LunaPillButton("0 s", isSelected: abs(viewModel.subtitleDelaySeconds) < 0.01, prominence: .subtleChip, size: .compact) {
                viewModel.resetSubtitleDelay()
            }
            .focused($focusedItemID, equals: "sub-sync-zero")

            LunaPillButton("+0,1 s", prominence: .subtleChip, size: .compact) {
                viewModel.adjustSubtitleDelay(by: 0.1)
            }
            .focused($focusedItemID, equals: "sub-sync-plus")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .focusSection()
    }

    // MARK: - Lyd

    @ViewBuilder
    private var audioList: some View {
        ForEach(viewModel.drawerAudioOptions) { track in
            let rowID = "aud-\(track.id)"
            let selected = viewModel.activeAudioTrackIndex == track.id
            QuickPanelRowButton(
                title: track.humanLanguageTitle,
                subtitle: track.humanFormatSubtitle,
                isSelected: selected,
                isFocused: focusedItemID == rowID
            ) {
                viewModel.selectAudioTrack(track.id)
                onClose(false)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        Rectangle()
            .fill(LunaTheme.warmBorderSubtle)
            .frame(height: 1)
            .padding(.vertical, 4)

        ForEach(AudioEnhancementMode.allCases) { mode in
            let rowID = "aud-mode-\(mode.rawValue)"
            QuickPanelRowButton(
                title: mode.displayTitle,
                subtitle: mode.subtitle,
                isSelected: viewModel.audioEnhancement == mode,
                isFocused: focusedItemID == rowID
            ) {
                viewModel.setAudioEnhancement(mode)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
        }

        HStack(spacing: 10) {
            Text("Lydsynk")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)

            Spacer(minLength: 8)

            Text(ComfortPreferences.formatAudioDelayMs(viewModel.audioDelayMs))
                .font(LunaTheme.Font.settingsAudioDelay)
                .foregroundStyle(LunaTheme.moonlight)

            LunaPillButton("−25 ms", prominence: .subtleChip, size: .compact) {
                viewModel.adjustAudioDelay(byMs: -25)
            }
            .focused($focusedItemID, equals: "aud-sync-minus")

            LunaPillButton("0 ms", isSelected: viewModel.audioDelayMs == 0, prominence: .subtleChip, size: .compact) {
                viewModel.resetAudioDelay()
            }
            .focused($focusedItemID, equals: "aud-sync-zero")

            LunaPillButton("+25 ms", prominence: .subtleChip, size: .compact) {
                viewModel.adjustAudioDelay(byMs: 25)
            }
            .focused($focusedItemID, equals: "aud-sync-plus")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .focusSection()
    }

    // MARK: - Kilde

    @ViewBuilder
    private var sourceList: some View {
        let activeCandidateId = viewModel.activeSession?.selectedCandidate.candidateId
        let room = viewModel.activeSession?.roomName ?? ""

        if viewModel.isLoadingAlternatives && viewModel.alternatives.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                Text("Henter tilgjengelige kilder…")
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.moonlight)
            }
            .padding(20)
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
                QuickPanelRowButton(
                    title: cand.quickRowTitle(roomName: room, isRecommended: idx == 0),
                    subtitle: cand.quickRowMetadata(isActive: isCurrent),
                    badgeText: cand.isNorwegian == true ? "🇳🇴 Norsk" : nil,
                    isSelected: isCurrent,
                    isFocused: focusedItemID == rowID
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
            QuickPanelRowButton(
                title: "MetalFX: \(mode.displayTitle)",
                subtitle: mode.shortDescription,
                isSelected: comfort.lowResUpscaleMode == mode,
                isFocused: focusedItemID == rowID
            ) {
                viewModel.setMetalFXModeLive(mode)
            }
            .id(rowID)
            .focused($focusedItemID, equals: rowID)
            .prefersDefaultFocus(preferredActiveItemID == rowID, in: panelFocusNamespace)
        }

        Rectangle()
            .fill(LunaTheme.warmBorderSubtle)
            .frame(height: 1)
            .padding(.vertical, 4)

        QuickPanelRowButton(
            title: "Teknisk info (HUD)",
            subtitle: comfort.showNerdHUD ? "Vises øverst til venstre under avspilling" : "Skjult",
            isSelected: comfort.showNerdHUD,
            isFocused: focusedItemID == "pic-hud"
        ) {
            comfort.showNerdHUD.toggle()
        }
        .id("pic-hud")
        .focused($focusedItemID, equals: "pic-hud")
    }

    // MARK: - Kapitler

    @ViewBuilder
    private var chaptersList: some View {
        let activeChapterID = viewModel.activeChapter(at: chapterSnapshotTime)?.id
        ForEach(viewModel.chapters) { ch in
            let rowID = "ch-\(ch.id)"
            let isCurrent = ch.id == activeChapterID
            QuickPanelRowButton(
                title: ch.title,
                subtitle: chapterSubtitle(ch, isActive: isCurrent),
                badgeText: TimelineScrubberLeafView.formatSeconds(ch.startSeconds),
                isSelected: isCurrent,
                isFocused: focusedItemID == rowID
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

    private func focusPreferredActiveItem(proxy: ScrollViewProxy) {
        focusRetryTask?.cancel()
        let targetID = preferredActiveItemID
        proxy.scrollTo(targetID, anchor: .center)
        focusedItemID = targetID
        focusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                proxy.scrollTo(targetID, anchor: .center)
                if focusedItemID != targetID {
                    focusedItemID = targetID
                } else {
                    return
                }
            }
        }
    }

    private func cycleNightLightPreset() {
        let all = HDRSubtitlePreset.allCases
        guard let idx = all.firstIndex(of: comfort.hdrSubtitlePreset) else {
            comfort.hdrSubtitlePreset = .warm75
            return
        }
        comfort.hdrSubtitlePreset = all[(idx + 1) % all.count]
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

private struct QuickPanelRowButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let title: String
    var subtitle: String? = nil
    var badgeText: String? = nil
    let isSelected: Bool
    var isDimmedLocked: Bool = false
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(isDimmedLocked ? LunaTheme.muted : LunaTheme.linen)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(LunaTheme.Font.badge.monospacedDigit())
                        .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(LunaTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                }

                if isDimmedLocked {
                    Image(systemName: "lock.fill")
                        .font(LunaTheme.Font.pillIcon)
                        .foregroundStyle(LunaTheme.muted)
                } else if isSelected {
                    Text("✓")
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.amber)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceSelected : (isSelected ? LunaTheme.surfaceRaised : Color.clear))
            )
            .opacity(isDimmedLocked ? (isFocused ? 0.85 : 0.55) : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
                            : (isSelected ? LunaTheme.warmBorder : Color.clear),
                        lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                    )
            )
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength * 0.7) : .clear,
                radius: isFocused ? 20 : 0,
                x: 0,
                y: isFocused ? 6 : 0
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
    }
}
