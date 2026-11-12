import SwiftUI
import AetherBridge

/// Opaque cinema curtain held above `AetherPlayerSurface` (`zIndex: 2`) until
/// `hasFirstFrameReadyForDisplay == true && isAwaitingDisplaySwitch == false`,
/// eliminating black blinks during Usenet VFS mount and HDMI HDR/24p handshake.
struct ResolvingCurtainView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let initialRequest: PlaybackLaunchRequest
    let client: MediaOSClient?
    let roomBadgeText: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            LunaTheme.pureBlack.ignoresSafeArea()

            // Softly dimmed 16:9 backdrop
            if let backdropURL = resolvedBackdropURL {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 1920,
                    placeholderSymbol: "film",
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .opacity(0.32)
                .blur(radius: 10)
            }

            RadialGradient(
                colors: [
                    LunaTheme.pureBlack.opacity(0.35),
                    LunaTheme.pureBlack.opacity(0.82),
                    LunaTheme.pureBlack.opacity(0.96),
                ],
                center: .center,
                startRadius: 120,
                endRadius: 960
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Room & capability badge
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.tv")
                        .foregroundStyle(LunaTheme.amber)
                    Text(roomBadgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.moonlight)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.35), lineWidth: 1))

                // ClearLogo or title typography
                if let logoURL = resolvedLogoURL {
                    CachedArtworkView(
                        url: logoURL,
                        client: client,
                        maxPixelSize: 800,
                        contentMode: .fit
                    )
                    .frame(maxWidth: 560, maxHeight: 150)
                    .shadow(color: .black.opacity(0.8), radius: 18, x: 0, y: 6)

                    if let episodeContext = episodeSubtitle {
                        Text(episodeContext)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight.opacity(0.9))
                    }
                } else {
                    VStack(spacing: 8) {
                        if let series = initialRequest.seriesTitle ?? viewModel.activeSession?.item.seriesTitle {
                            Text(series)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(LunaTheme.amber)
                        }
                        Text(viewModel.activeSession?.item.title ?? initialRequest.title)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 980)
                    }
                }

                // Selected stream headline (once chosen)
                if let headline = viewModel.resolveHeadline, !headline.isEmpty {
                    Text(headline)
                        .font(.callout.monospaced().weight(.medium))
                        .foregroundStyle(LunaTheme.amber)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(LunaTheme.surface.opacity(0.75), in: Capsule())
                        .overlay(Capsule().strokeBorder(LunaTheme.amber.opacity(0.28), lineWidth: 1))
                }

                // Step strip + calm amber progress bar
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        stepChip(index: 0, label: "Kildevalg")
                        stepChip(index: 1, label: "Artikkelhelse")
                        stepChip(index: 2, label: "VFS / Lagring")
                        stepChip(index: 3, label: "HDMI & Bilde")
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [LunaTheme.amber, LunaTheme.amberDeep],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                    )
                                )
                                .frame(width: max(24, geo.size.width * CGFloat(effectiveProgressFraction)))
                                .animation(.easeOut(duration: 0.28), value: effectiveProgressFraction)
                        }
                    }
                    .frame(width: 620, height: 7)

                    Text(statusLineText)
                        .font(.callout)
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.84))
                }
                .padding(.top, 8)

                Spacer()

                LunaPillButton("Avbryt", systemImage: "xmark", prominence: .subtleChip) {
                    onCancel()
                }
                .padding(.bottom, 44)
            }
            .padding(.horizontal, 80)
        }
    }

    private var resolvedBackdropURL: URL? {
        let raw = viewModel.activeSession?.item.backdropUrl ?? initialRequest.backdropUrl
        guard let raw, !raw.isEmpty else { return nil }
        return client?.buildAbsoluteURL(raw)
    }

    private var resolvedLogoURL: URL? {
        let raw = viewModel.activeSession?.item.logoUrl ?? initialRequest.logoUrl
        guard let raw, !raw.isEmpty else { return nil }
        return client?.buildAbsoluteURL(raw)
    }

    private var episodeSubtitle: String? {
        if let item = viewModel.activeSession?.item,
           let s = item.season, let e = item.episode, s > 0, e > 0 {
            return String(format: "S%02dE%02d · %@", s, e, item.title)
        }
        if initialRequest.seriesTitle != nil {
            return initialRequest.title
        }
        return nil
    }

    private var activeStepIndex: Int {
        if !viewModel.isResolving {
            return 3
        }
        switch viewModel.resolveStageKey {
        case "searching", "searching_indexers":
            return 0
        case "xml_preflight":
            return 1
        case "mounting_vfs":
            return 2
        default:
            return viewModel.resolvePercent >= 90 ? 3 : 2
        }
    }

    private var effectiveProgressFraction: Double {
        if !viewModel.isResolving {
            let startupFrac = viewModel.startupProgress?.fraction ?? 0.5
            return min(0.99, 0.88 + startupFrac * 0.11)
        }
        return min(0.92, max(0.08, Double(viewModel.resolvePercent) / 100.0))
    }

    private var statusLineText: String {
        if !viewModel.isResolving {
            if viewModel.isAwaitingDisplaySwitch {
                return "Tilpasser TV-skjermens HDR- og bildefrekvens…"
            }
            if let stage = viewModel.startupProgress?.stage {
                switch stage {
                case .connecting, .openingContainer:
                    return "Åpner direktestrøm…"
                case .analyzingStreams:
                    return "Leser lyd- og videostrømmer…"
                case .preparingDisplay:
                    return "Forbereder Dolby Vision / HDR-visning…"
                case .selectingRoute, .buildingSession, .preparingPlayback:
                    return "Bygger avspillingskjede…"
                case .awaitingFirstFrame, .presenting:
                    return "Dekoder første videorute…"
                }
            }
            return "Dekoder første videorute…"
        }
        return viewModel.resolveStageLabel
    }

    private func stepChip(index: Int, label: String) -> some View {
        let current = activeStepIndex
        let isDone = index < current
        let isCurrent = index == current

        return HStack(spacing: 7) {
            Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "record.circle" : "circle"))
                .font(.caption)
                .foregroundStyle(isDone ? LunaTheme.emerald : (isCurrent ? LunaTheme.amber : LunaTheme.muted.opacity(0.5)))
            Text(label)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .white : (isDone ? LunaTheme.moonlight.opacity(0.85) : LunaTheme.muted.opacity(0.55)))
        }
    }
}
