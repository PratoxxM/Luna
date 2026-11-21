import SwiftUI

/// Poster artwork card (`280×420` shelf / `260×390` grid).
/// Shelves hide resting titles (`showRestingTitle: false`) for calm artwork rows,
/// whereas catalog, library, and search grids display resting titles (`showRestingTitle: true`).
public struct PosterCardView: View {
    let card: TvMediaCard
    let client: LunaCoreClient?
    let width: CGFloat
    let showStorageBadge: Bool
    let showRestingTitle: Bool
    let focusRequestNonce: Int
    let onSelect: () -> Void
    let onPlayShortcut: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: LunaCoreClient?,
        width: CGFloat = LunaTokens.Layout.posterW,
        showStorageBadge: Bool = false,
        showRestingTitle: Bool = false,
        focusRequestNonce: Int = 0,
        onSelect: @escaping () -> Void,
        onPlayShortcut: (() -> Void)? = nil
    ) {
        self.card = card
        self.client = client
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.showRestingTitle = showRestingTitle
        self.focusRequestNonce = focusRequestNonce
        self.onSelect = onSelect
        self.onPlayShortcut = onPlayShortcut
    }

    private var height: CGFloat {
        (width * 1.5).rounded()
    }

    public var body: some View {
        let posterURL = client?.resolveArtworkURL(card.preferredPosterPath, target: .poster2x)
        let captionHeight: CGFloat = showRestingTitle ? 60 : 66
        let showCaption = showRestingTitle || isFocused

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
                    .equatable()
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

                        LunaCardProgressBar(percent: card.progress?.percent, trackWidth: width - 28)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
                .frame(width: width, height: height)
                .lunaCardFocusFrame(
                    cornerRadius: LunaTheme.posterRadius,
                    isFocused: isFocused
                )
            }
            .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTheme.posterRadius, style: .continuous))
            .lunaCardLampGlow(isFocused: isFocused)
            .focused($isFocused)
            .lunaRequestDirectFocus(nonce: focusRequestNonce, isFocused: $isFocused)
            .accessibilityLabel(card.title)
            .onPlayPauseCommand {
                onPlayShortcut?()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(showRestingTitle ? LunaTheme.Font.subtitle : LunaTheme.Font.cardTitle)
                    .foregroundStyle(isFocused ? LunaTheme.linen : (showRestingTitle ? LunaTheme.moonlight : LunaTheme.linen))
                    .lineLimit(1)
                    .truncationMode(.tail)

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
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: captionHeight, maxHeight: captionHeight, alignment: .topLeading)
            .lunaFocusCaptionReveal(isVisible: showCaption, isFocused: isFocused)
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
