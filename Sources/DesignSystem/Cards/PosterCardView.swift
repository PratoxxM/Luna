import SwiftUI

public struct PosterCardView: View {
    @Environment(\.ambientFocusSink) private var ambientFocus

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
        width: CGFloat = 248,
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

        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: posterURL,
                        client: client,
                        maxPixelSize: 640,
                        blurHash: card.blurHash,
                        dominantColor: card.dominantColor,
                        placeholderSymbol: card.mediaType == "series" ? "tv" : "film",
                        contentMode: .fill
                    )
                    .frame(width: width, height: height)
                    .clipped()

                    VStack {
                        HStack(alignment: .top, spacing: 6) {
                            if card.isFavorite == true {
                                Image(systemName: "star.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(LunaTheme.amber)
                                    .padding(7)
                                    .background(Color.black.opacity(0.66), in: Circle())
                            } else if card.progress?.watched == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(LunaTheme.emerald)
                                    .padding(6)
                                    .background(Color.black.opacity(0.66), in: Circle())
                            }

                            Spacer(minLength: 4)

                            if let storageBadge = storageBadgeLabel {
                                Text(storageBadge)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(storageBadgeForeground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.72), in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(storageBadgeForeground.opacity(0.35), lineWidth: 0.8)
                                    )
                            }
                        }
                        .padding(10)

                        Spacer()

                        if pct > 2 && pct < 95 {
                            let trackWidth = max(0, width - 24)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.55))
                                Capsule()
                                    .fill(LunaTheme.amber)
                                    .frame(width: trackWidth * CGFloat(pct / 100.0))
                            }
                            .frame(width: trackWidth, height: 5)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.28 : 0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onPlayPauseCommand {
                onPlayShortcut?()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isFocused ? .white : LunaTheme.moonlight)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.muted)
                    .lineLimit(1)
            }
            .frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: 92, alignment: .topLeading)
            .offset(y: isFocused ? 6 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                ambientFocus.reportFocus(
                    card.dominantColor,
                    nil,
                    card.blurHash
                )
            }
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
