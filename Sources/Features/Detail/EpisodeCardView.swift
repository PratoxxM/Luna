import SwiftUI

struct EpisodeCardView: View {
    let episode: TvEpisodeCard
    let client: MediaOSClient?
    let onPlay: () -> Void
    let onPickSource: () -> Void
    let onToggleWatched: () -> Void

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
                    .opacity(upcoming ? 0.65 : 1.0)

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
                                    .background(Color.black.opacity(0.65), in: Circle())
                            }
                        }
                        .padding(12)

                        Spacer()

                        if pct > 1 && !upcoming {
                            let trackWidth: CGFloat = 392
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.24))
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: trackWidth * CGFloat(pct / 100.0))
                            }
                            .frame(width: trackWidth, height: 5)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .frame(width: 420, height: 236)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                }
            }

            HStack(spacing: 8) {
                Text("\(episode.codeLabel) · \(episode.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isFocused ? .white : LunaTheme.moonlight)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if episode.watched {
                    Text("Sett")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LunaTheme.emerald)
                } else if isFocused && !upcoming {
                    Text("Hold inne: Sett")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LunaTheme.amber.opacity(0.9))
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
