import SwiftUI

struct DetailHeroHeaderView: View {
    let item: TvItemDetail
    let client: MediaOSClient?
    let primaryPlayTitle: String
    let watchedButtonTitle: String
    let isPreResolvedReady: Bool
    let focusNamespace: Namespace.ID

    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void
    let onPickSource: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        let bgURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl ?? item.posterUrl)
        let logoURL = client?.resolveArtworkURL(item.logoUrl)

        return ZStack(alignment: .bottomLeading) {
            CachedArtworkView(
                url: bgURL,
                client: client,
                maxPixelSize: 1920,
                blurHash: item.blurHash,
                dominantColor: item.dominantColor,
                placeholderSymbol: "film.stack",
                contentMode: .fill
            )
            .frame(maxWidth: .infinity)
            .frame(height: 610)
            .clipped()

            LinearGradient(
                colors: [
                    LunaTheme.canvas.opacity(0.05),
                    LunaTheme.canvas.opacity(0.62),
                    LunaTheme.canvas.opacity(0.97),
                    LunaTheme.canvas
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    LunaTheme.canvas.opacity(0.82),
                    LunaTheme.canvas.opacity(0.32),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 18) {
                // ClearLogo or clean typography title
                if let logoURL {
                    CachedArtworkView(
                        url: logoURL,
                        client: client,
                        maxPixelSize: 800,
                        placeholderSymbol: "sparkles.tv",
                        contentMode: .fit
                    )
                    .frame(maxWidth: 520, maxHeight: 118, alignment: .bottomLeading)
                } else {
                    Text(item.title)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: 980, alignment: .leading)
                }

                if let tagline = item.tagline?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !tagline.isEmpty {
                    Text(tagline)
                        .font(.callout.italic().weight(.medium))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.76))
                        .lineLimit(1)
                        .frame(maxWidth: 980, alignment: .leading)
                }

                // Clean metadata + optional availability + technical release badges
                HStack(spacing: 12) {
                    Text(detailMetadataLine)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.88))

                    if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text("Kommer: \(upcomingBadge)")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LunaTheme.canvas)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(LunaTheme.amber, in: Capsule())
                    } else if let avail = item.availability,
                              avail.isLocalNvme || avail.isLocalArchive || avail.isLocalVfs {
                        Text(avail.householdBadgeLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle((avail.isLocalNvme || avail.isLocalVfs) ? LunaTheme.emerald : LunaTheme.moonlight)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }

                    ForEach(displayedBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }

                // Overview
                if let overview = item.preferredOverview {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.88))
                        .lineLimit(3)
                        .frame(maxWidth: 1020, alignment: .leading)
                }

                // Streamlined Action Bar: Focus lands directly on Primary Play!
                HStack(spacing: 16) {
                    PrimaryPlayButton(
                        title: primaryPlayTitle,
                        isWarmReady: isPreResolvedReady,
                        action: onPlay
                    )
                    .prefersDefaultFocus(true, in: focusNamespace)

                    LunaPillButton(
                        item.inWatchlist ? "I huskeliste" : "Huskeliste",
                        systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark",
                        isSelected: item.inWatchlist,
                        action: onToggleWatchlist
                    )

                    LunaPillButton(
                        watchedButtonTitle,
                        systemImage: item.watched ? "checkmark.circle.fill" : "checkmark.circle",
                        isSelected: item.watched,
                        action: onToggleWatched
                    )

                    LunaPillButton(
                        "Bytt kilde",
                        systemImage: "arrow.triangle.2.circlepath",
                        action: onPickSource
                    )

                    LunaPillButton(
                        "",
                        systemImage: item.favoriteFlag ? "star.fill" : "star",
                        isSelected: item.favoriteFlag,
                        prominence: .subtleChip,
                        action: onToggleFavorite
                    )
                }
                .padding(.top, 6)
                .onPlayPauseCommand {
                    onPlay()
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.bottom, 34)
        }
    }

    private var detailMetadataLine: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let vote = item.voteAverage, vote > 0 {
            parts.append(String(format: "★ %.1f", vote))
        }
        if let genres = item.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private var displayedBadges: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in item.badges ?? [] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count >= 4 { break }
        }
        return result
    }
}

private struct PrimaryPlayButton: View {
    let title: String
    let isWarmReady: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryPlayLabel(title: title, isWarmReady: isWarmReady)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }
}

private struct PrimaryPlayLabel: View {
    @Environment(\.isFocused) private var focused

    let title: String
    let isWarmReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.headline.weight(.black))
            Text(title)
                .font(.headline.weight(.bold))
            if isWarmReady {
                Circle()
                    .fill(LunaTheme.canvas.opacity(0.65))
                    .frame(width: 7, height: 7)
            }
        }
        .foregroundStyle(LunaTheme.canvas)
        .padding(.horizontal, 32)
        .padding(.vertical, 15)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: focused
                            ? [Color.white, LunaTheme.amber]
                            : [LunaTheme.amber, LunaTheme.amberDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(focused ? 0.95 : 0.35), lineWidth: focused ? 2.5 : 1.0)
        )
        .shadow(
            color: LunaTheme.amber.opacity(focused ? 0.55 : 0.22),
            radius: focused ? 22 : 10,
            x: 0,
            y: focused ? 8 : 4
        )
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: focused)
    }
}
