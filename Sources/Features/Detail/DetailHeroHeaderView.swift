import SwiftUI

struct DetailHeroHeaderView: View {
    let item: TvItemDetail
    let client: LunaCoreClient?
    let primaryPlayTitle: String
    let watchedButtonTitle: String
    let isPreResolvedReady: Bool
    var horizontalGutter: CGFloat = LunaTheme.horizontalGutter
    let focusNamespace: Namespace.ID

    var hasLocalEpisodes: Bool = false
    let onPlay: () -> Void
    let onToggleWatchlist: () -> Void
    let onToggleWatched: () -> Void
    let onToggleMonitor: () -> Void
    let onPickSource: () -> Void
    var onDeleteTitle: (() -> Void)? = nil

    private var monitorButtonTitle: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Følger serie" : "Følg serie"
        }
        return item.isMonitoredFlag ? "Henter til NAS" : "Last ned"
    }

    private var monitorButtonIcon: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "bell.fill" : "bell"
        }
        return item.isMonitoredFlag ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    private var shouldShowMonitorButton: Bool {
        if item.mediaType == "series" { return true }
        return item.availability?.isPhysicalLocal != true
    }

    private var shouldShowDeleteButton: Bool {
        onDeleteTitle != nil && (
            item.availability?.isPhysicalLocal == true ||
            item.availability?.isLocalVfs == true ||
            hasLocalEpisodes ||
            item.isMonitoredFlag
        )
    }

    private var heroMinHeight: CGFloat {
        item.mediaType == "movie" ? 900 : 750
    }

    var body: some View {
        let landscapeURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl)
        let fallbackPosterURL = landscapeURL == nil ? client?.resolveArtworkURL(item.posterUrl) : nil
        let logoURL = client?.resolveArtworkURL(item.logoUrl)

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
                    .font(LunaTheme.Font.heroSerif)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(2)
                    .frame(maxWidth: 980, alignment: .leading)
            }

            if let tagline = item.tagline?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tagline.isEmpty {
                Text(tagline)
                    .font(.callout.italic().weight(.medium))
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 980, alignment: .leading)
            }

            // Clean metadata + optional availability + technical release badges
            HStack(spacing: 12) {
                Text(detailMetadataLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(LunaTheme.moonlight)

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
                          avail.isPhysicalLocal {
                    Text(avail.householdBadgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(avail.isLocalNvme ? LunaTheme.emerald : LunaTheme.moonlight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(LunaTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                }

                ForEach(displayedBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LunaTheme.moonlight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(LunaTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                }
            }

            // Overview
            if let overview = item.preferredOverview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(LunaTheme.moonlight)
                    .lineLimit(3)
                    .frame(maxWidth: 1020, alignment: .leading)
            }

            // Streamlined Action Bar: Only «Spill av» shines in brass-gold; secondary actions stay warm matte espresso
            HStack(spacing: 12) {
                PrimaryPlayButton(
                    title: primaryPlayTitle,
                    isWarmReady: isPreResolvedReady,
                    action: onPlay
                )
                .prefersDefaultFocus(true, in: focusNamespace)

                LunaPillButton(
                    "Huskeliste",
                    systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark",
                    isSelected: item.inWatchlist,
                    size: .compact,
                    action: onToggleWatchlist
                )

                LunaPillButton(
                    watchedButtonTitle,
                    systemImage: item.watched ? "checkmark.circle.fill" : "checkmark.circle",
                    isSelected: item.watched,
                    accent: .emerald,
                    size: .compact,
                    action: onToggleWatched
                )

                if shouldShowMonitorButton {
                    LunaPillButton(
                        monitorButtonTitle,
                        systemImage: monitorButtonIcon,
                        isSelected: item.isMonitoredFlag,
                        size: .compact,
                        action: onToggleMonitor
                    )
                }

                LunaPillButton(
                    "Bytt kilde",
                    systemImage: "arrow.triangle.2.circlepath",
                    size: .compact,
                    action: onPickSource
                )

                if shouldShowDeleteButton, let onDeleteTitle {
                    LunaPillButton(
                        item.mediaType == "series" ? "Slett serie" : "Slett film",
                        systemImage: "trash",
                        accent: .coral,
                        size: .compact,
                        action: onDeleteTitle
                    )
                }
            }
            .padding(.top, 6)
            .onPlayPauseCommand {
                onPlay()
            }
        }
        .padding(.top, item.mediaType == "movie" ? 180 : 210)
        .padding(.bottom, 38)
        .padding(.horizontal, horizontalGutter)
        .frame(maxWidth: .infinity, minHeight: heroMinHeight, alignment: .bottomLeading)
        .background {
            GeometryReader { geo in
                ZStack {
                    LunaTheme.canvas

                    if let landscapeURL {
                        CachedArtworkView(
                            url: landscapeURL,
                            client: client,
                            maxPixelSize: 1920,
                            blurHash: item.blurHash,
                            dominantColor: item.dominantColor,
                            placeholderSymbol: "film.stack",
                            contentMode: .fill
                        )
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                    } else if let fallbackPosterURL {
                        CachedArtworkView(
                            url: fallbackPosterURL,
                            client: client,
                            maxPixelSize: 320,
                            blurHash: item.blurHash,
                            dominantColor: item.dominantColor,
                            placeholderSymbol: "film.stack",
                            contentMode: .fill
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(0.22)
                        .clipped()
                    }

                    // Top vignette for clean tvOS navigation/top edge blending
                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas.opacity(0.62), location: 0.0),
                            .init(color: LunaTheme.canvas.opacity(0.18), location: 0.14),
                            .init(color: .clear, location: 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Leading cinematic scrim behind logo, metadata, overview & buttons
                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas.opacity(0.88), location: 0.0),
                            .init(color: LunaTheme.canvas.opacity(0.52), location: 0.42),
                            .init(color: LunaTheme.canvas.opacity(0.12), location: 0.72),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    // Seamless multi-stop bottom dissolve into LunaTheme.canvas (zero hard cut)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.34),
                            .init(color: LunaTheme.canvas.opacity(0.46), location: 0.58),
                            .init(color: LunaTheme.canvas.opacity(0.88), location: 0.82),
                            .init(color: LunaTheme.canvas, location: 0.97),
                            .init(color: LunaTheme.canvas, location: 1.0)
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
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let disp = item.displayRating {
            parts.append(LunaCopy.formatRating(disp.value, prefix: disp.isImdb ? "IMDb ★" : "★"))
        }
        if let rt = item.rottenTomatoesScore, rt > 0 {
            parts.append("RT \(rt)%")
        }
        if let mc = item.metacriticScore, mc > 0 {
            parts.append("MC \(mc)")
        }
        if let genres = item.genres, !genres.isEmpty {
            parts.append(genres.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private var displayedBadges: [String] {
        var seen: Set<String> = ["klar i vfs", "infinidysk vfs"]
        if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
            seen.insert("kommer")
            seen.insert("kommer: \(upcomingBadge.lowercased())")
        } else if let avail = item.availability, avail.isPhysicalLocal {
            seen.insert(avail.householdBadgeLabel.lowercased())
            seen.insert("på nvme")
            seen.insert("i arkiv")
        }
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
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(LunaTheme.Font.primaryPlayIcon)
            Text(title)
                .font(LunaTheme.Font.primaryPlayLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            if isWarmReady {
                Circle()
                    .fill(LunaTheme.canvas.opacity(0.68))
                    .frame(width: 7, height: 7)
            }
        }
        .foregroundStyle(LunaTheme.canvas)
        .transaction { $0.animation = nil }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(
            ZStack {
                Capsule()
                    .fill(LunaTheme.primaryAmberGradient)
                    .opacity(focused ? 0 : 1)
                Capsule()
                    .fill(LunaTheme.playFocusGradient)
                    .opacity(focused ? 1 : 0)
            }
            .transaction { $0.animation = nil }
        )
        .lunaFocusSurface(.primaryPlay, isFocused: focused, cornerRadius: LunaTokens.Radius.pill)
    }
}
