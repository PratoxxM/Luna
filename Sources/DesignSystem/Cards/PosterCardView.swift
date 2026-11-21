import SwiftUI

/// Poster artwork card (`280×420` shelf / `260×390` grid).
/// Shelves hide resting titles (`showRestingTitle: false`) for calm artwork rows,
/// whereas catalog, library, and search grids display resting titles (`showRestingTitle: true`).
public struct PosterCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let card: TvMediaCard
    let client: LunaCoreClient?
    let width: CGFloat
    let showStorageBadge: Bool
    let showRestingTitle: Bool
    let onSelect: () -> Void
    let onPlayShortcut: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: LunaCoreClient?,
        width: CGFloat = LunaTokens.Layout.posterW,
        showStorageBadge: Bool = false,
        showRestingTitle: Bool = false,
        onSelect: @escaping () -> Void,
        onPlayShortcut: (() -> Void)? = nil
    ) {
        self.card = card
        self.client = client
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.showRestingTitle = showRestingTitle
        self.onSelect = onSelect
        self.onPlayShortcut = onPlayShortcut
    }

    private var height: CGFloat {
        (width * 1.5).rounded()
    }

    public var body: some View {
        let posterURL = client?.resolveArtworkURL(card.preferredPosterPath, target: .poster2x)
        let pct = min(100.0, max(0.0, card.progress?.percent ?? 0))
        let captionHeight: CGFloat = showRestingTitle ? 60 : 66

        VStack(alignment: .leading, spacing: 14) {
            Button(action: onSelect) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: posterURL,
                        client: client,
                        maxPixelSize: 900,
                        blurHash: card.blurHash,
                        dominantColor: card.dominantColor,
                        placeholderSymbol: card.mediaType == "series" ? "tv" : "film",
                        contentMode: .fill
                    )
                    .frame(width: width, height: height)
                    .opacity(isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness)
                    .clipped()

                    VStack {
                        HStack(alignment: .top, spacing: 6) {
                            if card.progress?.watched == true {
                                LunaArtBadge.watchedCheckmark()
                            }
                            Spacer(minLength: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)

                        Spacer()

                        if pct > 2 && pct < 95 {
                            let trackWidth = max(0, width - 28)
                            ZStack(alignment: .leading) {
                                Capsule().fill(LunaTokens.Edge.progressTrack)
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: trackWidth * CGFloat(pct / 100.0))
                            }
                            .frame(width: trackWidth, height: 6)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                        }
                    }
                }
                .frame(width: width, height: height)
                .lunaCardFocusFrame(
                    cornerRadius: LunaTheme.posterRadius,
                    isFocused: isFocused,
                    showRestingTopEdge: false
                )
            }
            .buttonStyle(LunaChromelessButtonStyle())
            .contentShape(RoundedRectangle(cornerRadius: LunaTheme.posterRadius, style: .continuous))
            .focusEffectDisabled(true)
            .lunaCardLampGlow(isFocused: isFocused)
            .focused($isFocused)
            .accessibilityLabel(card.title)
            .onPlayPauseCommand {
                onPlayShortcut?()
            }

            let showCaption = showRestingTitle || isFocused
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(showRestingTitle ? LunaTheme.Font.subtitle : LunaTheme.Font.cardTitle)
                    .foregroundStyle(isFocused ? LunaTheme.linen : (showRestingTitle ? LunaTheme.moonlight : LunaTheme.linen))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(showCaption ? 1.0 : 0.0)

                HStack(spacing: 6) {
                    if showCaption && showStorageBadge,
                       let avail = card.availability,
                       avail.isPhysicalLocal {
                        LunaTierDotView(availability: avail)
                            .opacity(isFocused ? 1.0 : 0.88)
                    }

                    Text(subtitleText)
                        .font(showRestingTitle ? LunaTheme.Font.caption : LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.cardSubtitleColor(isFocused: isFocused))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .opacity(showCaption ? 1.0 : 0.0)
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: captionHeight, maxHeight: captionHeight, alignment: .topLeading)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : (isFocused ? LunaFocusStyle.focusFade.delay(0.06) : .easeOut(duration: 0.12)),
                value: isFocused
            )
            .allowsHitTesting(false)
        }
    }

    private var subtitleText: String {
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
