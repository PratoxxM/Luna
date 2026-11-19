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
    var onToggleMonitor: () -> Void = {}
    var onPickSource: () -> Void = {}
    var onDeleteTitle: (() -> Void)? = nil
    var onOpenMore: (() -> Void)? = nil
    var onReadMore: ((String) -> Void)? = nil

    private var heroMinHeight: CGFloat {
        item.mediaType == "movie" ? 860 : 730
    }

    var body: some View {
        let landscapeURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl)
        let fallbackPosterURL = landscapeURL == nil ? client?.resolveArtworkURL(item.posterUrl) : nil

        VStack(alignment: .leading, spacing: 18) {
            if let orig = item.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !orig.isEmpty,
               orig.caseInsensitiveCompare(item.title) != .orderedSame {
                Text(orig.uppercased())
                    .font(LunaTheme.Font.badge)
                    .tracking(2)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            }

            // Editorial serif hero title (max 1 serif element per screen)
            Text(item.title)
                .font(LunaTheme.Font.heroSerif)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(2)
                .frame(maxWidth: 980, alignment: .leading)

            // Single calm metadata line
            Text(detailMetadataLine)
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)

            // Subtle technical release badges & availability benefit
            HStack(spacing: 12) {
                ForEach(displayedBadges, id: \.self) { badge in
                    Text(badge)
                        .font(LunaTheme.Font.badge)
                        .foregroundStyle(LunaTheme.moonlight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(LunaTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1))
                }

                if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text("Kommer: \(upcomingBadge)")
                    }
                    .font(LunaTheme.Font.badge)
                    .foregroundStyle(LunaTheme.canvas)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(LunaTheme.amber, in: Capsule())
                } else if let avail = item.availability {
                    HStack(spacing: 8) {
                        LunaTierMarkView(availability: avail)
                        Text(avail.resolvedBenefitLabel)
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.leading, displayedBadges.isEmpty ? 0 : 8)
                }
            }

            // Overview preview + «Les mer»
            if let overview = item.preferredOverview {
                VStack(alignment: .leading, spacing: 10) {
                    Text(overview)
                        .font(LunaTheme.Font.body)
                        .foregroundStyle(LunaTheme.moonlight)
                        .lineLimit(3)
                        .frame(maxWidth: 980, alignment: .leading)

                    if overview.count > 160, let onReadMore {
                        LunaPillButton("Les mer", prominence: .subtleChip, size: .compact) {
                            onReadMore(overview)
                        }
                    }
                }
            }

            // Action row: 1 gold primary CTA + Huskeliste icon + Sett icon + Mer icon
            HStack(spacing: 18) {
                PrimaryPlayButton(
                    title: primaryPlayTitle,
                    isWarmReady: isPreResolvedReady,
                    action: onPlay
                )
                .prefersDefaultFocus(true, in: focusNamespace)

                DetailCircleIconButton(
                    systemImage: item.inWatchlist ? "bookmark.fill" : "bookmark",
                    isSelected: item.inWatchlist,
                    accentColor: LunaTheme.amber,
                    accessibilityLabel: item.inWatchlist ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                    action: onToggleWatchlist
                )

                DetailCircleIconButton(
                    systemImage: item.watched ? "checkmark.circle.fill" : "checkmark",
                    isSelected: item.watched,
                    accentColor: LunaTheme.emerald,
                    accessibilityLabel: watchedButtonTitle,
                    action: onToggleWatched
                )

                DetailCircleIconButton(
                    systemImage: "ellipsis",
                    isSelected: false,
                    accentColor: LunaTheme.amber,
                    accessibilityLabel: "Mer",
                    action: {
                        if let onOpenMore {
                            onOpenMore()
                        } else {
                            onPickSource()
                        }
                    }
                )
            }
            .padding(.top, 10)
            .onPlayPauseCommand {
                onPlay()
            }
        }
        .padding(.top, item.mediaType == "movie" ? 180 : 190)
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

                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas.opacity(0.62), location: 0.0),
                            .init(color: LunaTheme.canvas.opacity(0.18), location: 0.14),
                            .init(color: .clear, location: 0.28),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        stops: [
                            .init(color: LunaTheme.canvas.opacity(0.92), location: 0.0),
                            .init(color: LunaTheme.canvas.opacity(0.60), location: 0.42),
                            .init(color: LunaTheme.canvas.opacity(0.14), location: 0.72),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.34),
                            .init(color: LunaTheme.canvas.opacity(0.48), location: 0.58),
                            .init(color: LunaTheme.canvas.opacity(0.90), location: 0.82),
                            .init(color: LunaTheme.canvas, location: 0.97),
                            .init(color: LunaTheme.canvas, location: 1.0),
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
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        } else if let seasons = item.seasons, !seasons.isEmpty {
            parts.append(LunaCopy.plural(seasons.count, "sesong", "sesonger"))
        }
        if let disp = item.displayRating {
            parts.append(LunaCopy.formatRating(disp.value, prefix: disp.isImdb ? "IMDb ★" : "★"))
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
        HStack(spacing: 12) {
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
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
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

private struct DetailCircleIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let accentColor: Color
    let accessibilityLabel: String
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(
                    isFocused
                        ? LunaTheme.linen
                        : (isSelected ? accentColor : LunaTheme.moonlight)
                )
                .frame(width: 76, height: 76)
                .background(
                    Circle()
                        .fill(isFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isFocused
                                ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
                                : (isSelected ? accentColor.opacity(0.45) : LunaTheme.warmBorder),
                            lineWidth: isFocused ? LunaFocusStyle.borderWidth : 1.0
                        )
                )
                .shadow(
                    color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                    radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                    x: 0,
                    y: isFocused ? LunaFocusStyle.glowOffsetY : 0
                )
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Circle())
        .focusEffectDisabled(true)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel)
    }
}
