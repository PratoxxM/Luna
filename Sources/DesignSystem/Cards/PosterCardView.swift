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
                    CachedArtworkView(
                        url: posterURL,
                        client: client,
                        maxPixelSize: 540,
                        blurHash: card.blurHash,
                        dominantColor: card.dominantColor,
                        placeholderSymbol: card.mediaType == "series" ? "tv" : "film",
                        contentMode: .fill
                    )
                    .frame(width: width, height: height)
                    .clipped()

                    // Top badges
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

                            if let topBadge = preferredBadgeText {
                                Text(topBadge)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(topBadgeForeground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.72), in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(topBadgeForeground.opacity(0.35), lineWidth: 0.8)
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

                Text(card.compactMetaLine)
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

    private var preferredBadgeText: String? {
        if showStorageBadge, let avail = card.availability {
            return avail.householdBadgeLabel
        }
        if let badge = card.badges?.first, !badge.isEmpty {
            return badge
        }
        if let avail = card.availability, avail.isLocalNvme {
            return "NVMe"
        }
        return nil
    }

    private var topBadgeForeground: Color {
        if let avail = card.availability, avail.isLocalNvme && showStorageBadge {
            return LunaTheme.emerald
        }
        if let badge = card.badges?.first, badge.contains("DV") || badge.contains("FEL") {
            return LunaTheme.amber
        }
        return LunaTheme.moonlight
    }
}
