import SwiftUI
import AetherBridge

/// Calm cinema curtain held above `AetherPlayerSurface` (`zIndex: 2`) until
/// `hasFirstFrameReadyForDisplay == true && isAwaitingDisplaySwitch == false`,
/// eliminating black blinks during VFS mount and HDMI HDR/24p handshake.
struct ResolvingCurtainView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let initialRequest: PlaybackLaunchRequest
    let client: LunaCoreClient?

    var body: some View {
        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            if let backdropURL = resolvedBackdropURL {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 480,
                    placeholderSymbol: "film",
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .opacity(0.28)
                .blur(radius: 14)
            }

            RadialGradient(
                colors: [
                    LunaTheme.pureBlack.opacity(0.32),
                    LunaTheme.pureBlack.opacity(0.84),
                    LunaTheme.pureBlack.opacity(0.97),
                ],
                center: .center,
                startRadius: 120,
                endRadius: 960
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                if let logoURL = resolvedLogoURL {
                    CachedArtworkView(
                        url: logoURL,
                        client: client,
                        maxPixelSize: 800,
                        contentMode: .fit
                    )
                    .frame(maxWidth: 540, maxHeight: 144)
                    .shadow(color: .black.opacity(0.82), radius: 18, x: 0, y: 6)

                    if let episodeContext = curtainDisplay.mainLine {
                        Text(episodeContext)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight.opacity(0.88))
                    }
                } else {
                    VStack(spacing: 8) {
                        if let series = curtainDisplay.seriesLine {
                            Text(series)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(LunaTheme.amber)
                        }
                        if let mainTitle = curtainDisplay.mainLine {
                            Text(mainTitle)
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: 960)
                        }
                    }
                }

                VStack(spacing: 14) {
                    LoadingCatTrackView(
                        comfort: viewModel.comfort,
                        targetFraction: effectiveProgressFraction,
                        isPreparingReveal: !viewModel.isResolving,
                        trackWidth: CatCompanionLayout.loadingTrackWidth
                    )
                    .id(initialRequest.id)

                    Text(statusLineText)
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)

                    if let headline = viewModel.resolveHeadline, !headline.isEmpty {
                        Text(headline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LunaTheme.amber.opacity(0.92))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 80)
        }
        .allowsHitTesting(false)
    }

    private var resolvedBackdropURL: URL? {
        let raw = initialRequest.backdropUrl ?? viewModel.activeSession?.item.backdropUrl
        guard let raw, !raw.isEmpty else { return nil }
        return client?.buildAbsoluteURL(raw)
    }

    private var resolvedLogoURL: URL? {
        let raw = viewModel.activeSession?.item.logoUrl ?? initialRequest.logoUrl
        guard let raw, !raw.isEmpty else { return nil }
        return client?.buildAbsoluteURL(raw)
    }

    private var curtainDisplay: (seriesLine: String?, mainLine: String?) {
        let item = viewModel.activeSession?.item
        return EpisodeTitleFormatter.curtainLabels(
            title: item?.title ?? initialRequest.title,
            seriesTitle: item?.seriesTitle ?? initialRequest.seriesTitle,
            itemId: item?.itemId ?? initialRequest.itemId,
            season: item?.season ?? initialRequest.season,
            episode: item?.episode ?? initialRequest.episode,
            hasLogo: resolvedLogoURL != nil
        )
    }

    private var effectiveProgressFraction: Double {
        if !viewModel.isResolving {
            let startupFrac = viewModel.hasFirstFrameReadyForDisplay
                ? 1.0
                : min(1.0, max(0.0, viewModel.startupProgress?.fraction ?? 0.5))
            return min(0.99, 0.92 + startupFrac * 0.07)
        }
        return min(0.92, max(0.15, Double(viewModel.resolvePercent) / 100.0))
    }

    private var statusLineText: String {
        if viewModel.isRestoringFromBackground {
            if viewModel.isAwaitingDisplaySwitch {
                return "Tilpasser skjermens HDR og bildefrekvens…"
            }
            return "Gjenoppretter avspilling…"
        }
        if !viewModel.isResolving {
            if !viewModel.hasFirstFrameReadyForDisplay {
                return "Klargjør første bilde…"
            }
            if viewModel.isAwaitingDisplaySwitch {
                return "Tilpasser skjermens HDR og bildefrekvens…"
            }
            return "Starter avspilling…"
        }
        let stage = viewModel.resolveStageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return stage.isEmpty ? "Klargjør strøm…" : stage
    }
}
