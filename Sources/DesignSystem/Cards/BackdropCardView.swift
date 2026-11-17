import SwiftUI

public enum BackdropCardVariant: Sendable {
    case continueWatching
    case upcomingEpisode
    case standard
}

public struct BackdropCardView: View {
    let card: TvMediaCard
    let client: LunaCoreClient?
    let variant: BackdropCardVariant
    let width: CGFloat
    let showStorageBadge: Bool
    let onPrimaryAction: () -> Void
    let onPlayShortcut: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: LunaCoreClient?,
        variant: BackdropCardVariant,
        width: CGFloat = 468,
        showStorageBadge: Bool = false,
        onPrimaryAction: @escaping () -> Void,
        onPlayShortcut: (() -> Void)? = nil
    ) {
        self.card = card
        self.client = client
        self.variant = variant
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.onPrimaryAction = onPrimaryAction
        self.onPlayShortcut = onPlayShortcut
    }

    private var height: CGFloat {
        (width * 9.0 / 16.0).rounded()
    }

    public var body: some View {
        let artworkURL = client?.resolveArtworkURL(card.preferredLandscapePath)
        let pct = min(100.0, max(0.0, card.progress?.percent ?? 0))

        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPrimaryAction) {
                ZStack {
                    LunaTheme.surface

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

                    VStack(spacing: 0) {
                        if variant == .upcomingEpisode || storageBadgeLabel != nil {
                            HStack(spacing: 6) {
                                if variant == .upcomingEpisode {
                                    upcomingDatePill
                                }
                                Spacer(minLength: 4)
                                if let storageBadge = storageBadgeLabel {
                                    Text(storageBadge)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(storageBadgeForeground)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(LunaTheme.cinemaGlass, in: Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(storageBadgeForeground.opacity(0.32), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(14)
                        }

                        Spacer(minLength: 0)

                        if variant == .continueWatching && (pct > 0 || isFocused) {
                            VStack(spacing: 8) {
                                if isFocused {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "play.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(LunaTheme.canvas)
                                            .frame(width: 34, height: 34)
                                            .background(LunaTheme.amber, in: Circle())
                                    }
                                    .padding(.horizontal, 14)
                                }

                                if pct > 0 {
                                    let trackWidth = max(0, width - 28)
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(LunaTheme.warmBorderBase.opacity(0.24))
                                        Capsule()
                                            .fill(LunaTheme.amber)
                                            .frame(width: trackWidth * CGFloat(pct / 100.0))
                                    }
                                    .frame(width: trackWidth, height: 5)
                                    .padding(.horizontal, 14)
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 10)
                            .background(
                                LinearGradient(
                                    colors: [.clear, Color.black.opacity(0.72)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                        .strokeBorder(LunaTheme.cardBorderColor(isFocused: isFocused), lineWidth: 1)
                )
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onPlayPauseCommand {
                if variant == .continueWatching {
                    onPrimaryAction()
                } else {
                    onPlayShortcut?()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LunaTheme.cardTitleColor(isFocused: isFocused))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleLine)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(LunaTheme.cardSubtitleColor(isFocused: isFocused))
                    .lineLimit(1)
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: 68, alignment: .topLeading)
            .offset(y: isFocused ? 7 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
    }

    private var upcomingDatePill: some View {
        let urgent = card.isUrgentUpcoming
        return HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(urgent ? LunaTheme.canvas : LunaTheme.amber)
            Text(card.upcomingPillText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(urgent ? LunaTheme.canvas : LunaTheme.linen)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            urgent ? LunaTheme.amber : LunaTheme.cinemaGlass,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    urgent ? Color.clear : LunaTheme.warmBorder,
                    lineWidth: 1
                )
        )
    }

    private var subtitleLine: String {
        switch variant {
        case .upcomingEpisode:
            return card.cleanUpcomingSubtitle
        case .continueWatching:
            return card.cleanContinueSubtitle
        case .standard:
            let meta = card.compactMetaLine
            if !meta.isEmpty {
                return meta
            }
            if let year = card.year {
                return String(year)
            }
            return ""
        }
    }

    private var storageBadgeLabel: String? {
        guard showStorageBadge, let avail = card.availability else {
            return nil
        }
        if avail.isPhysicalLocal {
            return avail.householdBadgeLabel
        }
        return nil
    }

    private var storageBadgeForeground: Color {
        if let avail = card.availability, avail.isLocalNvme {
            return LunaTheme.emerald
        }
        return LunaTheme.moonlight
    }
}
