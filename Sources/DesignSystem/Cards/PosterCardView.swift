import SwiftUI

public struct LunaTierMarkView: View {
    let availability: TvAvailabilityInfo

    public init(availability: TvAvailabilityInfo) {
        self.availability = availability
    }

    public var body: some View {
        let color = tierColor
        ZStack {
            Circle()
                .fill(LunaTheme.cinemaGlass)
                .frame(width: 34, height: 34)
            Circle()
                .strokeBorder(color.opacity(0.45), lineWidth: 1)
                .frame(width: 34, height: 34)

            if availability.isLocalNvme {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            } else if availability.isLocalArchive {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "waveform")
                    .font(LunaTheme.Font.tierBadge)
                    .foregroundStyle(color)
            }
        }
        .accessibilityLabel(availability.resolvedBenefitLabel)
    }

    private var tierColor: Color {
        if availability.isLocalNvme { return LunaTheme.tierNvme }
        if availability.isLocalArchive { return LunaTheme.tierArchive }
        return LunaTheme.tierStream
    }
}

public struct PosterCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let card: TvMediaCard
    let client: LunaCoreClient?
    let width: CGFloat
    let showStorageBadge: Bool
    let onSelect: () -> Void
    let onPlayShortcut: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: LunaCoreClient?,
        width: CGFloat = LunaTokens.Layout.posterW,
        showStorageBadge: Bool = false,
        onSelect: @escaping () -> Void,
        onPlayShortcut: (() -> Void)? = nil
    ) {
        self.card = card
        self.client = client
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.onSelect = onSelect
        self.onPlayShortcut = onPlayShortcut
    }

    private var height: CGFloat {
        (width * 1.5).rounded()
    }

    public var body: some View {
        let posterURL = client?.resolveArtworkURL(card.preferredPosterPath)
        let pct = min(100.0, max(0.0, card.progress?.percent ?? 0))

        VStack(alignment: .leading, spacing: 24) {
            Button(action: onSelect) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: posterURL,
                        client: client,
                        maxPixelSize: 750,
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
                                Image(systemName: "checkmark.circle.fill")
                                    .font(LunaTheme.Font.cardMicroIcon)
                                    .foregroundStyle(LunaTheme.emerald)
                                    .padding(6)
                                    .background(LunaTheme.cinemaGlass, in: Circle())
                            } else if showStorageBadge, let avail = card.availability,
                                      avail.isPhysicalLocal || avail.isLocalVfs {
                                Spacer(minLength: 4)
                                LunaTierMarkView(availability: avail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)

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
            .buttonStyle(.card)
            .lunaCardLampGlow(isFocused: isFocused)
            .focused($isFocused)
            .accessibilityLabel(card.title)
            .onPlayPauseCommand {
                onPlayShortcut?()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(LunaTheme.Font.posterTitle)
                    .foregroundStyle(LunaTheme.cardTitleColor(isFocused: isFocused))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitleText)
                    .font(LunaTheme.Font.posterSubtitle)
                    .foregroundStyle(LunaTheme.cardSubtitleColor(isFocused: isFocused))
                    .lineLimit(1)
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: 82, maxHeight: 82, alignment: .topLeading)
            .opacity(isFocused ? 1.0 : 0.0)
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
