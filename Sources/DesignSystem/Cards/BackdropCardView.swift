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
    let focusRequestNonce: Int
    let onPrimaryAction: () -> Void
    let onPlayShortcut: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: LunaCoreClient?,
        variant: BackdropCardVariant,
        width: CGFloat = LunaTokens.Layout.backdropW,
        showStorageBadge: Bool = false,
        focusRequestNonce: Int = 0,
        onPrimaryAction: @escaping () -> Void,
        onPlayShortcut: (() -> Void)? = nil
    ) {
        self.card = card
        self.client = client
        self.variant = variant
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.focusRequestNonce = focusRequestNonce
        self.onPrimaryAction = onPrimaryAction
        self.onPlayShortcut = onPlayShortcut
    }

    private var height: CGFloat {
        (width * 9.0 / 16.0).rounded()
    }

    public var body: some View {
        let artworkURL = client?.resolveArtworkURL(card.preferredLandscapePath, target: .landscape2x)
        let effectivePercent: Double? = variant == .upcomingEpisode ? nil : card.progress?.percent
        let progressBar = LunaCardProgressBar(percent: effectivePercent, trackWidth: width - 44)

        Button(action: onPrimaryAction) {
            ZStack {
                LunaTheme.surface

                CachedArtworkView(
                    url: artworkURL,
                    client: client,
                    maxPixelSize: ArtworkDecodeTargets.backdropCardMaxPixelSize,
                    blurHash: card.blurHash,
                    dominantColor: card.dominantColor,
                    placeholderSymbol: variant == .upcomingEpisode ? "calendar.badge.clock" : "play.tv",
                    contentMode: .fill
                )
                .equatable()
                .frame(width: width, height: height)
                .opacity(isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness)
                .clipped()

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
                            LunaArtBadge(
                                label: badgeText,
                                dotColor: card.origin == "phone" ? LunaTheme.amber : LunaTheme.moonlight
                            )
                        } else if variant == .upcomingEpisode {
                            LunaArtBadge(label: card.upcomingPillText)
                        }

                        Spacer(minLength: 4)
                    }
                    .padding(14)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .bottom, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                    .font(LunaTheme.Font.cardTitle)
                                    .foregroundStyle(LunaTheme.linen)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                HStack(spacing: 6) {
                                    if isFocused && variant != .upcomingEpisode && (showStorageBadge || variant == .continueWatching),
                                       let avail = card.availability,
                                       avail.isPhysicalLocal {
                                        LunaTierDotView(availability: avail)
                                    }

                                    Text(subtitleLine)
                                        .font(LunaTheme.Font.subtitle)
                                        .foregroundStyle(LunaTheme.moonlight)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if variant != .upcomingEpisode {
                                Image(systemName: "play.fill")
                                    .font(LunaTheme.Font.pillIcon)
                                    .foregroundStyle(LunaTokens.Text.onAccent)
                                    .frame(
                                        width: LunaTokens.Layout.playBadgeSize,
                                        height: LunaTokens.Layout.playBadgeSize
                                    )
                                    .background(LunaTheme.amber, in: Circle())
                                    .opacity(isFocused ? 1.0 : 0.0)
                                    .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusFade, value: isFocused)
                            }
                        }

                        progressBar
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, progressBar.isVisible ? 14 : 20)
                }
            }
            .frame(width: width, height: height)
            .lunaCardFocusFrame(
                cornerRadius: LunaTheme.cardRadius,
                isFocused: isFocused
            )
        }
        .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .lunaCardLampGlow(isFocused: isFocused)
        .focused($isFocused)
        .lunaRequestDirectFocus(nonce: focusRequestNonce, isFocused: $isFocused)
        .accessibilityLabel(card.title)
        .onPlayPauseCommand {
            switch variant {
            case .continueWatching, .upcomingEpisode:
                onPrimaryAction()
            case .standard:
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

    private var subtitleLine: String {
        switch variant {
        case .continueWatching:
            return card.cleanContinueSubtitle
        case .upcomingEpisode:
            return card.cleanUpcomingSubtitle
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
