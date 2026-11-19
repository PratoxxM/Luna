import SwiftUI

struct EpisodeCardView: View {
    let episode: TvEpisodeCard
    var seriesTitle: String? = nil
    let client: LunaCoreClient?
    let onPlay: () -> Void
    let onPickSource: () -> Void
    let onToggleWatched: () -> Void
    var onRequestDelete: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        let stillURL = client?.resolveArtworkURL(episode.stillUrl)
        let pct = min(100.0, max(0.0, episode.progress?.percent ?? 0))
        let upcoming = episode.isUpcoming == true

        VStack(alignment: .leading, spacing: 10) {
            Button(action: onPlay) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: stillURL,
                        client: client,
                        maxPixelSize: 896,
                        placeholderSymbol: upcoming ? "calendar" : "play.tv",
                        contentMode: .fill
                    )
                    .frame(width: 420, height: 236)
                    .clipped()
                    .opacity(upcoming ? 0.65 : (isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness))

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack {
                        HStack {
                            if upcoming {
                                Text(episode.airDateBadge ?? "Kommer")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(LunaTheme.canvas)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(LunaTheme.amber, in: Capsule())
                            }

                            Spacer()

                            if episode.watched {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout.weight(.bold))
                                    .foregroundStyle(LunaTheme.emerald)
                                    .padding(6)
                                    .background(LunaTheme.cinemaGlass, in: Circle())
                            }
                        }
                        .padding(12)

                        Spacer()

                        if pct > 1 && !upcoming {
                            let trackWidth: CGFloat = 392
                            ZStack(alignment: .leading) {
                                Capsule().fill(LunaTokens.Edge.progressTrack)
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: trackWidth * CGFloat(pct / 100.0))
                            }
                            .frame(width: trackWidth, height: 6)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .frame(width: 420, height: 236)
                .lunaCardFocusFrame(cornerRadius: LunaTheme.cardRadius, isFocused: isFocused)
            }
            .buttonStyle(.card)
            .focused($isFocused)
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
                        Label("Spill episode", systemImage: "play.fill")
                    }
                    Button(action: onPickSource) {
                        Label("Bytt kilde…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if let onRequestDelete,
                       episode.availability?.isPhysicalLocal == true || episode.availability?.isLocalVfs == true {
                        Button(role: .destructive, action: onRequestDelete) {
                            Label("Slett episode…", systemImage: "trash")
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text(EpisodeTitleFormatter.episodeCardTitle(episode: episode, seriesTitle: seriesTitle))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LunaTheme.cardTitleColor(isFocused: isFocused))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if episode.watched {
                    Text("Sett")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LunaTheme.emerald)
                } else if isFocused && !upcoming {
                    Text("Hold inne: Marker som sett")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LunaTheme.moonlight)
                } else if let runtime = episode.formattedRuntime {
                    Text(runtime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LunaTheme.muted)
                }
            }
            .frame(width: 420)

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption2)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(2)
                    .frame(width: 420, alignment: .leading)
            }
        }
    }
}
