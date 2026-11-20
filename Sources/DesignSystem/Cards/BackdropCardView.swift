import SwiftUI

public enum BackdropCardVariant: Sendable {
    case continueWatching
    case upcomingEpisode
    case standard
}

public struct BackdropCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        width: CGFloat = LunaTokens.Layout.backdropW,
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
                .scaleEffect((isFocused && !reduceMotion) ? 1.025 : 1.0)
                .opacity(isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness)
                .clipped()
                .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.34),
                        .init(color: LunaTheme.canvas.opacity(0.68), location: 0.72),
                        .init(color: LunaTheme.canvas.opacity(0.92), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if let badgeText = originBadgeText {
                            originPill(label: badgeText, isPhone: card.origin == "phone")
                        } else if variant == .upcomingEpisode {
                            upcomingDatePill
                        }

                        Spacer(minLength: 4)

                        if showStorageBadge, let avail = card.availability,
                           avail.isPhysicalLocal || avail.isLocalVfs {
                            LunaTierMarkView(availability: avail)
                        }
                    }
                    .padding(18)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                    .font(LunaTheme.Font.backdropTitle)
                                    .foregroundStyle(LunaTheme.linen)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text(subtitleLine)
                                    .font(LunaTheme.Font.backdropSubtitle)
                                    .foregroundStyle(LunaTheme.moonlight)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if variant != .upcomingEpisode {
                                Image(systemName: "play.fill")
                                    .font(LunaTheme.Font.pillIcon)
                                    .foregroundStyle(LunaTheme.canvas)
                                    .frame(
                                        width: LunaTokens.Layout.playBadgeSize,
                                        height: LunaTokens.Layout.playBadgeSize
                                    )
                                    .background(LunaTheme.amber, in: Circle())
                                    .opacity(isFocused ? 1.0 : 0.0)
                                    .scaleEffect(isFocused ? 1.0 : 0.84)
                                    .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
                            }
                        }

                        if pct > 0 {
                            let trackWidth = max(0, width - 44)
                            ZStack(alignment: .leading) {
                                Capsule().fill(LunaTokens.Edge.progressTrack)
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: trackWidth * CGFloat(pct / 100.0))
                            }
                            .frame(width: trackWidth, height: 6)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, pct > 0 ? 14 : 20)
                }
            }
            .frame(width: width, height: height)
            .lunaCardFocusFrame(
                cornerRadius: LunaTheme.cardRadius,
                isFocused: isFocused,
                showRestingTopEdge: false
            )
        }
        .buttonStyle(.card)
        .lunaCardLampGlow(isFocused: isFocused)
        .focused($isFocused)
        .accessibilityLabel(card.title)
        .onPlayPauseCommand {
            if variant == .continueWatching {
                onPrimaryAction()
            } else {
                onPlayShortcut?()
            }
        }
    }

    private var originBadgeText: String? {
        if card.origin == "phone" {
            let trimmed = (card.originLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Fra iPhone" : trimmed
        }
        if card.origin == "tonight" {
            let trimmed = (card.originLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "I kveld" : trimmed
        }
        return nil
    }

    private func originPill(label: String, isPhone: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPhone ? LunaTheme.amber : LunaTheme.moonlight)
                .frame(width: 9, height: 9)

            Text(label)
                .font(LunaTheme.Font.cardMicroLabel)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(
            Capsule().strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1)
        )
    }

    private var upcomingDatePill: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(LunaTheme.Font.cardMicroIcon)
                .foregroundStyle(LunaTheme.moonlight)
            Text(card.upcomingPillText)
                .font(LunaTheme.Font.cardMicroLabel)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1)
        )
    }

    private var subtitleLine: String {
        switch variant {
        case .upcomingEpisode:
            return card.cleanUpcomingSubtitle
        case .continueWatching:
            let base = card.cleanContinueSubtitle
            if card.origin == "phone", let avail = card.availability, avail.isLocalNvme {
                let benefit = avail.resolvedBenefitLabel
                return base.isEmpty ? benefit : "\(base) · \(benefit)"
            }
            return base
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
}
