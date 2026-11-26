import SwiftUI

struct SeriesSkipPromptPillView: View {
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 6
    static let chevronWidth: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let chapter: PlaybackChapter
    let isPromptFocused: Bool
    var labelOverride: String? = nil
    let focusBinding: FocusState<SeriesPromptControl?>.Binding
    let onSkip: () -> Void

    static func resolvedLabel(for kind: TvChapterKind, override: String? = nil) -> String {
        if let override, !override.isEmpty {
            return override
        }
        switch kind {
        case .recap:
            return "Hopp over sammendrag"
        case .credits, .postCredits:
            return LunaCopy.skipToPostCreditsTitle
        case .intro, .chapter:
            return "Hopp over intro"
        }
    }

    var body: some View {
        let baseLabel = Self.resolvedLabel(for: chapter.kind, override: labelOverride)

        HStack(spacing: 10) {
            Image(systemName: "chevron.up")
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
                .frame(width: Self.chevronWidth)
                .opacity(isPromptFocused ? 0 : 1)
                .accessibilityHidden(isPromptFocused)
                .animation(
                    LunaFocusStyle.calmEaseOut(duration: 0.16, reduceMotion: reduceMotion),
                    value: isPromptFocused
                )

            LunaPillButton(
                baseLabel,
                systemImage: "forward.end.fill",
                prominence: .glassPill,
                action: onSkip
            )
            .focused(focusBinding, equals: .skipIntro)
        }
        .shadow(
            color: LunaTheme.pureBlack.opacity(0.56),
            radius: Self.shadowRadius,
            x: 0,
            y: Self.shadowY
        )
    }
}

struct SeriesNextEpisodeCardView: View {
    static let cardWidth: CGFloat = 548
    static let thumbnailWidth: CGFloat = 152
    static let thumbnailHeight: CGFloat = 86
    static let thumbnailCornerRadius: CGFloat = 10
    static let playButtonMinWidthWithCountdown: CGFloat = 244
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 6

    let next: TvNextEpisodeSummary
    let seriesTitle: String?
    let client: LunaCoreClient?
    let autoPlayEnabled: Bool
    let remainingCountdownSeconds: Int?
    let focusBinding: FocusState<SeriesPromptControl?>.Binding
    let onPlayNow: () -> Void
    let onDismiss: () -> Void

    private var trimmedStillPath: String? {
        guard let raw = next.stillUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var resolvedStillURL: URL? {
        guard let raw = trimmedStillPath else { return nil }
        return client?.resolveArtworkURL(raw, target: .landscape2x) ?? URL(string: raw)
    }

    var body: some View {
        let epLabel = "Neste episode · S\(next.season) E\(next.episode)"
        let cleanTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            next.title,
            seriesTitle: seriesTitle,
            season: next.season,
            episode: next.episode
        )
        let primaryLabel = SeriesFlowPolicy.primaryNextButtonTitle(
            autoPlayEnabled: autoPlayEnabled,
            remainingSeconds: remainingCountdownSeconds
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                if trimmedStillPath != nil {
                    CachedArtworkView(
                        url: resolvedStillURL,
                        client: client,
                        maxPixelSize: 480,
                        placeholderSymbol: "play.tv",
                        contentMode: .fill,
                        reuseAnyCachedSize: true,
                        retainDuringPlayback: true
                    )
                    .equatable()
                    .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Self.thumbnailCornerRadius,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: Self.thumbnailCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(LunaTokens.Edge.imageRing, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(epLabel)
                        .font(LunaTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(LunaTheme.muted)
                        .lineLimit(1)

                    if let cleanTitle, !cleanTitle.isEmpty {
                        Text(cleanTitle)
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.linen)
                            .lineLimit(trimmedStillPath != nil ? 2 : 1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                LunaPillButton(
                    primaryLabel,
                    systemImage: "play.fill",
                    prominence: .primary,
                    size: .compact,
                    minWidth: autoPlayEnabled ? Self.playButtonMinWidthWithCountdown : nil,
                    action: onPlayNow
                )
                .focused(focusBinding, equals: .playNext)

                LunaPillButton(
                    "Skjul",
                    prominence: .glassPill,
                    size: .compact,
                    action: onDismiss
                )
                .focused(focusBinding, equals: .dismissNext)
            }
        }
        .padding(20)
        .frame(width: Self.cardWidth, alignment: .leading)
        .lunaCinemaGlassSurface(
            shadowColor: LunaTheme.pureBlack.opacity(0.56),
            shadowRadius: Self.shadowRadius,
            shadowY: Self.shadowY
        )
        .focusSection()
    }
}

struct SeriesResumeBannerView: View {
    static let standardTopPadding: CGFloat = 64
    static let shiftedBelowStatusToastTopPadding: CGFloat = 132

    let seconds: Double
    let focusBinding: FocusState<SeriesPromptControl?>.Binding
    let onRestart: () -> Void

    var body: some View {
        let timeText = TimelineScrubberLeafView.formatSeconds(seconds)
        HStack(spacing: 20) {
            Text("Fortsetter fra \(timeText)")
                .font(LunaTheme.Font.subtitle.monospacedDigit())
                .foregroundStyle(LunaTheme.linen)

            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.muted)
                    .frame(width: 20)

                LunaPillButton(
                    "Start på nytt",
                    systemImage: "arrow.counterclockwise",
                    prominence: .glassPill,
                    size: .compact,
                    action: onRestart
                )
                .focused(focusBinding, equals: .restartFromBeginning)
            }
        }
        .padding(.leading, 26)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .lunaCinemaGlassSurface(
            cornerRadius: LunaTokens.Radius.pill,
            shadowColor: LunaTheme.pureBlack.opacity(0.56),
            shadowRadius: 14,
            shadowY: 6
        )
    }
}
