import SwiftUI

public enum BackdropCardVariant: Sendable {
    case continueWatching
    case upcomingEpisode
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
                        if variant == .upcomingEpisode {
                            upcomingDatePill
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                                            .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
                                    }
                                    .padding(.horizontal, 14)
                                }

                                if pct > 0 {
                                    let trackWidth = max(0, width - 28)
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.26))
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
                                    colors: [.clear, Color.black.opacity(0.68)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.28 : 0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onPlayPauseCommand {
                if variant == .continueWatching {
                    onPrimaryAction()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(isFocused ? .white : LunaTheme.moonlight)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleLine)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: width, minHeight: 68, alignment: .topLeading)
            .offset(y: isFocused ? 7 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                ambient.reportFocus(
                    dominantColor: card.dominantColor,
                    blurHash: card.blurHash
                )
            }
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
                .foregroundStyle(urgent ? LunaTheme.canvas : LunaTheme.moonlight)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            urgent ? LunaTheme.amber : Color.black.opacity(0.76),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    urgent ? Color.clear : LunaTheme.amber.opacity(0.35),
                    lineWidth: 0.9
                )
        )
    }

    private var subtitleLine: String {
        if variant == .upcomingEpisode {
            return card.cleanUpcomingSubtitle
        }
        return card.cleanContinueSubtitle
    }
}
