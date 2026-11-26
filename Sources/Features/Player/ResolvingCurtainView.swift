import SwiftUI

/// Shared OLED-safe cinema backdrop (`opacity: 0.22` cached hero + warm/dark vignette)
/// reused seamlessly across both `ResolvingCurtainView` and pre-reveal `PlayerFatalErrorOverlayView`
/// so startup errors never hard-cut to flat `#000000`.
struct PlayerCurtainBackdropView: View {
    let backdropURL: URL?
    let client: LunaCoreClient?

    static func resolveBackdropURL(
        request: PlaybackLaunchRequest,
        session: TvPlaybackSession?,
        client: LunaCoreClient?
    ) -> URL? {
        let raw = request.backdropUrl
            ?? session?.item.backdropUrl
            ?? request.preparedSession?.item.backdropUrl
        return client?.resolveArtworkURL(raw, target: .hero4K)
    }

    var body: some View {
        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            if let backdropURL {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 1920,
                    placeholderSymbol: "film",
                    contentMode: .fill,
                    reuseAnyCachedSize: true,
                    retainDuringPlayback: true
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
        }
    }
}

/// Calm cinema curtain held above `AetherPlayerSurface` (`zIndex: 2`) until
/// `hasFirstFrameReadyForDisplay == true && isAwaitingDisplaySwitch == false`.
///
/// Implements a `180 ms` pure-black `0-RTT` warm-start grace via `PlaybackCurtainPresentationPolicy`
/// so already-prepared LAN sessions that decode their first frame within `180 ms` open directly
/// into live video without flashing curtain chrome.
struct ResolvingCurtainView: View {
    let viewModel: PlayerViewModel
    let initialRequest: PlaybackLaunchRequest
    let client: LunaCoreClient?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var graceElapsed: Bool = false

    private var hasWarmPreparedSession: Bool {
        PlaybackCurtainPresentationPolicy.hasWarmPreparedSession(
            prepareToken: initialRequest.prepareToken,
            hasPreparedSession: initialRequest.preparedSession != nil
        )
    }

    private var showCurtainDetails: Bool {
        PlaybackCurtainPresentationPolicy.shouldShowCurtainContent(
            hasWarmPreparedSession: hasWarmPreparedSession,
            isAwaitingDisplaySwitch: viewModel.isAwaitingDisplaySwitch,
            isRestoringFromBackground: viewModel.isRestoringFromBackground,
            graceElapsed: graceElapsed
        )
    }

    var body: some View {
        let display = curtainDisplay

        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            ZStack {
                PlayerCurtainBackdropView(
                    backdropURL: resolvedBackdropURL,
                    client: client
                )

                VStack(spacing: 26) {
                    Spacer()

                    if let logoURL = resolvedLogoURL {
                        CachedArtworkView(
                            url: logoURL,
                            client: client,
                            maxPixelSize: 800,
                            contentMode: .fit,
                            reuseAnyCachedSize: true,
                            retainDuringPlayback: true
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
            .opacity(showCurtainDetails ? 1 : 0)
        }
        .allowsHitTesting(false)
        .task(id: initialRequest.id) {
            graceElapsed = false
            guard !showCurtainDetails else {
                graceElapsed = true
                return
            }
            try? await Task.sleep(nanoseconds: PlaybackCurtainPresentationPolicy.warmStartGraceNanoseconds)
            guard !Task.isCancelled else { return }
            let anim = LunaFocusStyle.calmEaseOut(
                duration: PlaybackCurtainPresentationPolicy.curtainFadeInDurationSeconds,
                reduceMotion: reduceMotion
            )
            withAnimation(anim) {
                graceElapsed = true
            }
        }
    }

    private var resolvedBackdropURL: URL? {
        PlayerCurtainBackdropView.resolveBackdropURL(
            request: initialRequest,
            session: viewModel.activeSession,
            client: client
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .animation(LunaFocusStyle.calmEaseOut(duration: 0.24, reduceMotion: reduceMotion), value: progress)
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
