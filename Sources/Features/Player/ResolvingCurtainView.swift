import Observation
import SwiftUI

/// Isolated startup & WebSocket resolution progress state observed exclusively by
/// `ResolvingProgressClusterLeafView` so progress ticks never re-render `PlayerContainerView`
/// or `ResolvingCurtainView`'s backdrop/logo hierarchy.
@MainActor
@Observable
final class PlayerStartupState {
    var resolveStageLabel: String = "Klargjør avspilling…"
    var resolvePercent: Int = 12
    var resolveHeadline: String?
    private(set) var engineStartupPercentBucket: Int = 50

    var engineStartupFraction: Double {
        Double(engineStartupPercentBucket) / 100.0
    }

    func updateEngineStartupFraction(_ rawFraction: Double?) {
        let clamped = min(1.0, max(0.0, rawFraction ?? 0.5))
        let bucket = Int((clamped * 100.0).rounded())
        if bucket != engineStartupPercentBucket {
            engineStartupPercentBucket = bucket
        }
    }
}

/// Calm cinema curtain held above `AetherPlayerSurface` (`zIndex: 2`) until
/// `hasFirstFrameReadyForDisplay == true && isAwaitingDisplaySwitch == false`,
/// reusing already-cached detail/shelf backdrops with zero 4K Gaussian blur passes.
struct ResolvingCurtainView: View {
    let viewModel: PlayerViewModel
    let initialRequest: PlaybackLaunchRequest
    let client: LunaCoreClient?

    var body: some View {
        let display = curtainDisplay

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            if let backdropURL = resolvedBackdropURL {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 3840,
                    placeholderSymbol: "film",
                    contentMode: .fill,
                    reuseAnyCachedSize: true
                )
                .equatable()
                .ignoresSafeArea()
                .opacity(0.22)
            }

            RadialGradient(
                colors: [
                    LunaTheme.pureBlack.opacity(0.36),
                    LunaTheme.pureBlack.opacity(0.84),
                    LunaTheme.pureBlack.opacity(0.98),
                ],
                center: .center,
                startRadius: 120,
                endRadius: 960
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    LunaTheme.pureBlack.opacity(0.55),
                    Color.clear,
                    LunaTheme.pureBlack.opacity(0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                if let logoURL = resolvedLogoURL {
                    CachedArtworkView(
                        url: logoURL,
                        client: client,
                        maxPixelSize: 1200,
                        contentMode: .fit,
                        reuseAnyCachedSize: true
                    )
                    .equatable()
                    .frame(maxWidth: 520, maxHeight: 140)

                    if let episodeContext = display.mainLine {
                        Text(episodeContext)
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                } else {
                    VStack(spacing: 8) {
                        if let series = display.seriesLine {
                            Text(series)
                                .font(LunaTheme.Font.cardTitle)
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        if let mainTitle = display.mainLine {
                            Text(mainTitle)
                                .font(LunaTheme.Font.titleSerif)
                                .foregroundStyle(LunaTheme.linen)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: 960)
                        }
                    }
                }

                ResolvingProgressClusterLeafView(
                    startupState: viewModel.startupState,
                    isResolving: viewModel.isResolving,
                    hasFirstFrameReadyForDisplay: viewModel.hasFirstFrameReadyForDisplay,
                    isAwaitingDisplaySwitch: viewModel.isAwaitingDisplaySwitch,
                    isRestoringFromBackground: viewModel.isRestoringFromBackground
                )
                .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 80)
        }
        .allowsHitTesting(false)
    }

    private var resolvedBackdropURL: URL? {
        let raw = initialRequest.backdropUrl
            ?? viewModel.activeSession?.item.backdropUrl
            ?? initialRequest.preparedSession?.item.backdropUrl
        return client?.resolveArtworkURL(raw, target: .hero4K)
    }

    private var resolvedLogoURL: URL? {
        let raw = viewModel.activeSession?.item.logoUrl
            ?? initialRequest.logoUrl
            ?? initialRequest.preparedSession?.item.logoUrl
        return client?.resolveArtworkURL(raw)
    }

    private var curtainDisplay: (seriesLine: String?, mainLine: String?) {
        let item = viewModel.activeSession?.item ?? initialRequest.preparedSession?.item
        return EpisodeTitleFormatter.curtainLabels(
            title: item?.title ?? initialRequest.title,
            seriesTitle: item?.seriesTitle ?? initialRequest.seriesTitle,
            itemId: item?.itemId ?? initialRequest.itemId,
            season: item?.season ?? initialRequest.season,
            episode: item?.episode ?? initialRequest.episode,
            hasLogo: resolvedLogoURL != nil
        )
    }
}

private struct ResolvingProgressClusterLeafView: View {
    let startupState: PlayerStartupState
    let isResolving: Bool
    let hasFirstFrameReadyForDisplay: Bool
    let isAwaitingDisplaySwitch: Bool
    let isRestoringFromBackground: Bool

    private static let trackWidth: CGFloat = 520
    private static let trackHeight: CGFloat = 4

    var body: some View {
        let progress = effectiveProgressFraction

        VStack(spacing: 14) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LunaTheme.warmBorder)

                Capsule()
                    .fill(LunaTheme.primaryAmberGradient)
                    .frame(width: max(20, Self.trackWidth * CGFloat(progress)))
                    .animation(.easeOut(duration: 0.24), value: progress)
            }
            .frame(width: Self.trackWidth, height: Self.trackHeight)

            Text(statusLineText)
                .font(LunaTheme.Font.body)
                .foregroundStyle(LunaTheme.muted)

            if let headline = startupState.resolveHeadline, !headline.isEmpty {
                Text(headline)
                    .font(LunaTheme.Font.caption)
                    .foregroundStyle(LunaTheme.moonlight)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(LunaTheme.surfaceRaised, in: Capsule())
            }
        }
    }

    private var effectiveProgressFraction: Double {
        if !isResolving {
            let startupFrac = hasFirstFrameReadyForDisplay
                ? 1.0
                : startupState.engineStartupFraction
            return min(0.99, 0.92 + startupFrac * 0.07)
        }
        return min(0.92, max(0.14, Double(startupState.resolvePercent) / 100.0))
    }

    private var statusLineText: String {
        if isRestoringFromBackground {
            if isAwaitingDisplaySwitch {
                return "Tilpasser skjermen…"
            }
            return "Gjenoppretter avspilling…"
        }
        if !isResolving {
            if !hasFirstFrameReadyForDisplay {
                return "Klargjør første bilde…"
            }
            if isAwaitingDisplaySwitch {
                return "Tilpasser skjermen…"
            }
            return "Starter avspilling…"
        }
        let stage = startupState.resolveStageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return stage.isEmpty ? "Klargjør avspilling…" : stage
    }
}
