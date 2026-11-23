import SwiftUI

struct DetailHeroHeaderView: View {
    let item: TvItemDetail
    let client: LunaCoreClient?
    let primaryPlayTitle: String
    var horizontalGutter: CGFloat = LunaTheme.horizontalGutter
    let focusNamespace: Namespace.ID

    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    var onPickSource: () -> Void = {}
    var onOpenMore: (() -> Void)? = nil

    private var heroMinHeight: CGFloat {
        item.mediaType == "movie" ? 760 : 500
    }

    var body: some View {
        let landscapeURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl, target: .hero4K)
        let fallbackPosterURL = landscapeURL == nil ? client?.resolveArtworkURL(item.posterUrl, target: .poster2x) : nil
        let isMovie = (item.mediaType == "movie")
        let formatBadges = Array(displayedBadges.prefix(3))

        VStack(alignment: .leading, spacing: isMovie ? 18 : 12) {
            // Editorial New York serif hero title
            Text(item.title)
                .font(LunaTheme.Font.heroSerif)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(2)
                .frame(maxWidth: 920, alignment: .leading)

            // Single calm metadata line + discrete inline watched status
            HStack(spacing: 8) {
                if !detailMetadataLine.isEmpty {
                    Text(detailMetadataLine)
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.moonlight)
                        .lineLimit(1)
                }

                if item.watched {
                    if !detailMetadataLine.isEmpty {
                        Text("·")
                            .font(LunaTheme.Font.subtitle)
                            .foregroundStyle(LunaTheme.muted)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.emerald)
                        Text("Sett")
                            .font(LunaTheme.Font.subtitle)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .lineLimit(1)
                }
            }

            // Single calm format summary line with subtle storage tier dot (only NVMe / archive)
            if !formatBadges.isEmpty {
                HStack(spacing: 10) {
                    if let avail = item.availability {
                        LunaTierDotView(availability: avail)
                    }
                    Text(formatBadges.joined(separator: " · "))
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.muted)
                        .lineLimit(1)
                }
            }

            // Overview preview (full overview is available under ⋯)
            if let overview = item.preferredOverview {
                Text(overview)
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.moonlight)
                    .lineSpacing(4)
                    .lineLimit(isMovie ? 3 : 2)
                    .frame(maxWidth: 920, alignment: .leading)
            }

            // Action row: Play (primary) + Kilde + Huskeliste + ⋯
            HStack(spacing: 14) {
                LunaPillButton(
                    primaryPlayTitle,
                    systemImage: "play.fill",
                    prominence: .primary,
                    size: .regular,
                    action: onPlay
                )
                .prefersDefaultFocus(true, in: focusNamespace)

                LunaPillButton(
                    "Kilde",
                    systemImage: "film.stack",
                    prominence: .glassPill
                ) {
                    onPickSource()
                }

                LunaPillButton(
                    "Huskeliste",
                    systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark",
                    isSelected: item.inWatchlist,
                    prominence: .glassPill
                ) {
                    onToggleWatchlist()
                }

                LunaIconButton(
                    systemImage: "ellipsis",
                    accessibilityLabel: "Mer"
                ) {
                    if let onOpenMore {
                        onOpenMore()
                    } else {
                        onPickSource()
                    }
                }
            }
            .padding(.top, isMovie ? 12 : 6)
            .focusSection()
            .onPlayPauseCommand {
                onPlay()
            }
        }
        .padding(.top, isMovie ? 136 : 64)
        .padding(.bottom, isMovie ? 30 : 18)
        .padding(.horizontal, horizontalGutter)
        .frame(maxWidth: .infinity, minHeight: heroMinHeight, alignment: .bottomLeading)
        .background {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    LunaTheme.canvas

                    if let landscapeURL {
                        CachedArtworkView(
                            url: landscapeURL,
                            client: client,
                            maxPixelSize: 1920,
                            blurHash: item.blurHash,
                            dominantColor: item.dominantColor,
                            placeholderSymbol: "film.stack",
                            contentMode: .fill,
                            progressiveFallback: true
                        )
                        .equatable()
                        .frame(width: geo.size.width * 0.76, height: geo.size.height, alignment: .center)
                        .clipped()
                    } else if let fallbackPosterURL {
                        CachedArtworkView(
                            url: fallbackPosterURL,
                            client: client,
                            maxPixelSize: 1280,
                            blurHash: item.blurHash,
                            dominantColor: item.dominantColor,
                            placeholderSymbol: "film.stack",
                            contentMode: .fill
                        )
                        .equatable()
                        .frame(width: geo.size.width * 0.76, height: geo.size.height)
                        .opacity(0.22)
                        .clipped()
                    }

                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas, location: 0.0),
                            .init(color: LunaTheme.canvas.opacity(0.95), location: 0.30),
                            .init(color: LunaTheme.canvas.opacity(0.56), location: 0.54),
                            .init(color: LunaTheme.canvas.opacity(0.10), location: 0.78),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas.opacity(0.36), location: 0.0),
                            .init(color: .clear, location: 0.22),
                            .init(color: .clear, location: 0.52),
                            .init(color: LunaTheme.canvas.opacity(0.88), location: 0.88),
                            .init(color: LunaTheme.canvas, location: 0.98),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
    }

    private var detailMetadataLine: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let genres = item.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if let seasons = item.seasons, !seasons.isEmpty {
            let regularCount = seasons.filter { $0.seasonNumber > 0 }.count
            parts.append(LunaCopy.seasonsCount(regularCount > 0 ? regularCount : seasons.count))
        } else if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let disp = item.displayRating {
            parts.append(LunaCopy.formatRating(disp.value, prefix: "★"))
        }
        if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
            parts.append("Ny episode \(upcomingBadge)")
        }
        return parts.joined(separator: " · ")
    }

    private var displayedBadges: [String] {
        var seen: Set<String> = [
            "klar i vfs",
            "på nvme",
            "i arkiv",
            "strømmes ved start",
            "starter umiddelbart",
            "kommer",
        ]
        if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
            seen.insert("kommer: \(upcomingBadge.lowercased())")
        }
        var result: [String] = []
        for raw in item.badges ?? [] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count >= 3 { break }
        }
        return result
    }
}
