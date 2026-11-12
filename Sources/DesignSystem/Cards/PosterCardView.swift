import SwiftUI

public struct PosterCardView: View {
    @EnvironmentObject private var ambient: AmbientBackdropController

    let card: TvMediaCard
    let client: MediaOSClient?
    let width: CGFloat
    let showStorageBadge: Bool
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        card: TvMediaCard,
        client: MediaOSClient?,
        width: CGFloat = 248,
        showStorageBadge: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.card = card
        self.client = client
        self.width = width
        self.showStorageBadge = showStorageBadge
        self.onSelect = onSelect
    }

    private var height: CGFloat {
        (width * 1.5).rounded()
    }

    public var body: some View {
        let posterURL = client?.resolveArtworkURL(card.preferredPosterPath)
        let ambientURL = client?.resolveArtworkURL(card.preferredLandscapePath)
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
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.black.opacity(0.55))
                                    Capsule()
                                        .fill(LunaTheme.amber)
                                        .frame(width: geo.size.width * CGFloat(pct / 100.0))
                                }
                            }
                            .frame(height: 5)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.card)
            .focused($isFocused)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isFocused ? .white : LunaTheme.moonlight)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)

                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.muted)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                ambient.reportFocus(
                    dominantColor: card.dominantColor,
                    backdropURL: ambientURL ?? posterURL,
                    blurHash: card.blurHash
                )
            }
        }
    }

    private var subtitleText: String {
        if let year = card.year {
            return String(year)
        }
        return card.compactMetaLine
    }

    private var storageBadgeLabel: String? {
        guard showStorageBadge, let avail = card.availability else {
            return nil
        }
        if avail.isLocalNvme || avail.isLocalArchive || avail.isLocalVfs {
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
