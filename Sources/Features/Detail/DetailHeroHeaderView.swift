import SwiftUI

struct DetailHeroHeaderView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

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
        item.mediaType == "movie" ? 860 : 760
    }

    var body: some View {
        let landscapeURL = client?.resolveArtworkURL(item.backdropUrl ?? item.cardBackdropUrl)
        let fallbackPosterURL = landscapeURL == nil ? client?.resolveArtworkURL(item.posterUrl) : nil

        VStack(alignment: .leading, spacing: 18) {
            if let kicker = item.studioOrNetworkKicker, !kicker.isEmpty {
                Text(kicker.uppercased())
                    .font(LunaTheme.Font.detailKicker)
                    .tracking(2.4)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            }

            // Editorial New York serif hero title
            Text(item.title)
                .font(LunaTheme.Font.detailHeroSerif)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(2)
                .frame(maxWidth: 920, alignment: .leading)

            // Single calm metadata line (no "IMDb" prefix)
            Text(detailMetadataLine)
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)

            // Small rectangular monochrome capability badges directly under metadata
            if !displayedBadges.isEmpty {
                HStack(spacing: 12) {
                    ForEach(displayedBadges, id: \.self) { badge in
                        Text(badge.uppercased())
                            .font(LunaTheme.Font.badge)
                            .tracking(0.8)
                            .foregroundStyle(LunaTheme.moonlight)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(LunaTokens.Edge.badgeOutline, lineWidth: 1)
                            )
                    }
                }
            }

            // Overview preview + optional «Les mer»
            if let overview = item.preferredOverview {
                VStack(alignment: .leading, spacing: 10) {
                    Text(overview)
                        .font(LunaTheme.Font.body)
                        .foregroundStyle(LunaTheme.moonlight)
                        .lineSpacing(5)
                        .lineLimit(3)
                        .frame(maxWidth: 920, alignment: .leading)

                    if overview.count > 165, let onReadMore {
                        LunaPillButton("Les mer", prominence: .subtleChip, size: .compact) {
                            onReadMore(overview)
                        }
                    }
                }
            }

            // Availability line placed BELOW overview, directly above action buttons
            if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
                HStack(spacing: 10) {
                    Circle()
                        .fill(LunaTheme.moonlight)
                        .frame(width: 8, height: 8)
                    Text("Kommer: \(upcomingBadge)")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.moonlight)
                }
                .padding(.top, 2)
            } else if let avail = item.availability {
                HStack(spacing: 10) {
                    Circle()
                        .fill(tierDotColor(for: avail))
                        .frame(width: 8, height: 8)
                        .shadow(color: tierDotColor(for: avail).opacity(0.45), radius: 5, x: 0, y: 0)
                    Text("\(avail.resolvedBenefitLabel) · klar for \(sessionStore.roomName)")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.moonlight)
                }
                .padding(.top, 2)
            }

            // Action row: rounded-rect gold PrimaryPlayButton + 3 borderless matte circles
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
                    accessibilityLabel: item.inWatchlist ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                    action: onToggleWatchlist
                )

                DetailCircleIconButton(
                    systemImage: "checkmark",
                    isSelected: item.watched,
                    accessibilityLabel: watchedButtonTitle,
                    action: onToggleWatched
                )

                DetailCircleIconButton(
                    systemImage: "ellipsis",
                    isSelected: false,
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
            .padding(.top, 12)
            .focusSection()
            .onPlayPauseCommand {
                onPlay()
            }
        }
        .padding(.top, item.mediaType == "movie" ? 170 : 180)
        .padding(.bottom, 34)
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
                            contentMode: .fill
                        )
                        .frame(width: geo.size.width * 0.76, height: geo.size.height, alignment: .center)
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

    private func tierDotColor(for avail: TvAvailabilityInfo) -> Color {
        if avail.isLocalNvme { return LunaTheme.tierNvme }
        if avail.isLocalArchive { return LunaTheme.tierArchive }
        return LunaTheme.tierStream
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
            parts.append(LunaCopy.seasonsCount(seasons.count))
        } else if let runtime = item.formattedRuntime, !runtime.isEmpty {
            parts.append(runtime)
        }
        if let disp = item.displayRating {
            parts.append(LunaCopy.formatRating(disp.value, prefix: "★"))
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
        ]
        if let upcomingBadge = item.nextAirDateBadge, !upcomingBadge.isEmpty {
            seen.insert("kommer")
            seen.insert("kommer: \(upcomingBadge.lowercased())")
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
    }
}

private struct PrimaryPlayLabel: View {
    @Environment(\.isFocused) private var focused

    let title: String
    let isWarmReady: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.fill")
                .font(LunaTheme.Font.primaryPlayIcon)
            Text(title)
                .font(LunaTheme.Font.primaryPlayLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            if isWarmReady {
                Circle()
                    .fill(LunaTheme.canvas.opacity(0.60))
                    .frame(width: 7, height: 7)
            }
        }
        .foregroundStyle(LunaTheme.canvas)
        .transaction { $0.animation = nil }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LunaTheme.primaryAmberGradient)
                    .opacity(focused ? 0 : 1)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LunaTheme.playFocusGradient)
                    .opacity(focused ? 1 : 0)
            }
            .transaction { $0.animation = nil }
        )
        .lunaFocusSurface(.primaryPlay, isFocused: focused, cornerRadius: 16)
    }
}

private struct DetailCircleIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(LunaTheme.Font.cardTitle)
                .foregroundStyle(
                    isSelected ? LunaTheme.amber : (isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                )
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(isFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                )
                .overlay(
                    Group {
                        if isFocused {
                            Circle()
                                .strokeBorder(
                                    LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity),
                                    lineWidth: LunaFocusStyle.borderWidth
                                )
                        }
                    }
                )
                .shadow(
                    color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                    radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                    x: 0,
                    y: isFocused ? LunaFocusStyle.glowOffsetY : 0
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Circle())
        .focusEffectDisabled(true)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel)
    }
}
