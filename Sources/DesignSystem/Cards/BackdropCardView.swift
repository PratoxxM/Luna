import SwiftUI

public enum BackdropCardVariant: Sendable {
    case continueWatching
    case upcomingEpisode
    case landscapeFeature
}

public struct BackdropCardView: View {
    @EnvironmentObject private var ambient: AmbientBackdropController

    let card: TvMediaCard
    let client: MediaOSClient?
    let variant: BackdropCardVariant
    let width: CGFloat
    let onPrimaryAction: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: MediaOSClient?,
        variant: BackdropCardVariant,
        width: CGFloat = 468,
        onPrimaryAction: @escaping () -> Void
    ) {
        self.card = card
        self.client = client
        self.variant = variant
        self.width = width
        self.onPrimaryAction = onPrimaryAction
    }

    private var height: CGFloat {
        (width * 9.0 / 16.0).rounded()
    }

    public var body: some View {
        let artworkURL = client?.resolveArtworkURL(card.preferredLandscapePath)
        let pct = min(100.0, max(0.0, card.progress?.percent ?? 0))

        Button(action: onPrimaryAction) {
            ZStack(alignment: .bottomLeading) {
                CachedArtworkView(
                    url: artworkURL,
                    client: client,
                    maxPixelSize: 960,
                    blurHash: card.blurHash,
                    dominantColor: card.dominantColor,
                    placeholderSymbol: variant == .upcomingEpisode ? "calendar.badge.clock" : "play.tv",
                    contentMode: .fill
                )
                .frame(width: width, height: height)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.42),
                        Color.black.opacity(0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top-left & Top-right pills
                VStack {
                    HStack(spacing: 8) {
                        if variant == .upcomingEpisode {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.caption2.weight(.bold))
                                Text(card.airDateBadge ?? fallbackUpcomingBadge)
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(LunaTheme.canvas)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(LunaTheme.amber, in: Capsule())
                        } else if variant == .continueWatching {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.caption2.weight(.bold))
                                Text(continuePillLabel)
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.amber)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                isFocused ? LunaTheme.amber : Color.black.opacity(0.68),
                                in: Capsule()
                            )
                        }

                        Spacer()

                        if let badge = topRightBadge {
                            Text(badge)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(LunaTheme.moonlight)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.68), in: Capsule())
                        }
                    }
                    .padding(16)

                    Spacer()
                }

                // Bottom title, episode context & progress bar
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitleLine)
                        .font(.caption)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.86))
                        .lineLimit(1)

                    if variant == .continueWatching && pct > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.22))
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: geo.size.width * CGFloat(pct / 100.0))
                            }
                        }
                        .frame(height: 5)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                ambient.reportFocus(
                    dominantColor: card.dominantColor,
                    backdropURL: artworkURL,
                    blurHash: card.blurHash
                )
            }
        }
    }

    private var continuePillLabel: String {
        if let mode = card.directPlayTarget?.mode, mode == "next_episode" {
            if let code = card.episodeCode {
                return "Neste · \(code)"
            }
            return "Neste episode"
        }
        if let pos = card.progress?.positionSeconds, pos > 30 {
            return "Fortsett"
        }
        if let code = card.episodeCode {
            return "Spill \(code)"
        }
        return "Spill av"
    }

    private var fallbackUpcomingBadge: String {
        if let code = card.episodeCode, let air = card.airDate {
            return "\(air) · \(code)"
        }
        return card.airDate ?? "Kommende episode"
    }

    private var topRightBadge: String? {
        if let first = card.badges?.first, !first.isEmpty {
            return first
        }
        if let avail = card.availability, avail.isLocalNvme {
            return "På NVMe"
        }
        return nil
    }

    private var subtitleLine: String {
        if variant == .upcomingEpisode {
            if let epTitle = card.episodeTitle, !epTitle.isEmpty {
                if let code = card.episodeCode {
                    return "\(code) · \(epTitle)"
                }
                return epTitle
            }
            if let air = card.airDate {
                return "Sendes \(air)"
            }
        }
        return card.formattedSubtitle
    }
}
