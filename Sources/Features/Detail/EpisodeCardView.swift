import SwiftUI

struct EpisodeCardView: View {
    let episode: TvEpisodeCard
    var seriesTitle: String? = nil
    var isNextForYou: Bool = false
    let client: LunaCoreClient?
    let onPlay: () -> Void
    let onPickSource: () -> Void
    let onToggleWatched: () -> Void
    var onRequestDelete: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        let cardWidth = LunaTokens.Layout.episodeW
        let cardHeight = LunaTokens.Layout.episodeH
        let stillURL = client?.resolveArtworkURL(episode.stillUrl, target: .landscape2x)
        let pct = min(100.0, max(0.0, episode.progress?.percent ?? 0))
        let upcoming = episode.isUpcoming == true
        let displayTitle = EpisodeTitleFormatter.episodeCardTitle(episode: episode, seriesTitle: seriesTitle)
        let overviewText = (episode.overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlay) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: stillURL,
                        client: client,
                        maxPixelSize: 960,
                        placeholderSymbol: upcoming ? "calendar" : "play.tv",
                        contentMode: .fill
                    )
                    .equatable()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .opacity(upcoming ? 0.65 : (isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness))

                    LinearGradient(
                        colors: [.clear, LunaTheme.canvas.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack {
                        HStack {
                            if upcoming {
                                LunaArtBadge(label: episode.airDateBadge ?? "Kommer")
                            } else if episode.watched {
                                LunaArtBadge.watchedCheckmark()
                            } else if isNextForYou {
                                LunaArtBadge(label: "Neste")
                            }

                            Spacer()
                        }
                        .padding(14)

                        Spacer()

                        if pct > 2 && pct < 95 && !episode.watched && !upcoming {
                            LunaCardProgressBar(percent: pct, trackWidth: cardWidth - 28)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                        }
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .lunaCardFocusFrame(
                    cornerRadius: LunaTheme.cardRadius,
                    isFocused: isFocused
                )
            }
            .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
            .lunaCardLampGlow(isFocused: isFocused)
            .focused($isFocused)
            .accessibilityLabel(displayTitle)
            .onPlayPauseCommand {
                if !upcoming {
                    onPlay()
                }
            }
            .contextMenu {
                Button(action: onToggleWatched) {
                    Label(
                        episode.watched ? "Marker som usett" : "Marker som sett",
                        systemImage: episode.watched ? "circle" : "checkmark.circle"
                    )
                }
                if !upcoming {
                    Button(action: onPlay) {
                        Label("Spill av", systemImage: "play.fill")
                    }
                    Button(action: onPickSource) {
                        Label("Velg kilde…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let onRequestDelete,
                       episode.availability?.isPhysicalLocal == true || episode.availability?.isLocalVfs == true {
                        Button(role: .destructive, action: onRequestDelete) {
                            Label("Slett episode…", systemImage: "trash")
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text(displayTitle)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(LunaTheme.cardTitleColor(isFocused: isFocused))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let runtime = episode.formattedRuntime {
                    Text(runtime)
                        .font(LunaTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(LunaTheme.muted)
                }
            }
            .frame(width: cardWidth)

            Text(overviewText.isEmpty ? " " : overviewText)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(2)
                .frame(width: cardWidth, height: 58, alignment: .topLeading)
                .lunaFocusCaptionReveal(isVisible: !overviewText.isEmpty, isFocused: isFocused)
        }
    }
}
