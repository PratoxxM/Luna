import SwiftUI

struct PlayerPreviewCinemaStageView: View {
    private static let previewTwoLineCue = "Velkommen tilbake til avdelingen.\nHele etasjen har ventet på dere i hele kveld."

    let client: LunaCoreClient?
    let backdropPath: String?
    let comfort: ComfortPreferences
    let activeQuickPanel: PlayerQuickPanelTab?
    let isBottomBarShown: Bool
    let isQuickPanelOpen: Bool
    var isNerdHUDVisible: Bool = false
    var activeSeriesOverlay: ActiveSeriesOverlayKind = .none
    var isScrubbing: Bool = false

    var body: some View {
        let placement = SubtitleOverlayLayout.verticalPlacement(
            isBottomBarVisible: isBottomBarShown,
            isQuickPanelOpen: isQuickPanelOpen,
            isNerdHUDVisible: isNerdHUDVisible,
            activeSeriesOverlay: activeSeriesOverlay,
            isScrubbing: isScrubbing
        )
        let boxAlpha = comfort.subtitleBoxOpacity.alpha
        let cueText = Text(Self.previewTwoLineCue)
            .font(LunaTheme.Font.subtitleCue(size: comfort.subtitleFontSize.pointSize))
            .foregroundStyle(comfort.hdrSubtitlePreset.foregroundColor(isHDR: true))
            .multilineTextAlignment(.center)

        ZStack {
            if let backdropURL = client?.resolveArtworkURL(backdropPath, target: .hero4K) {
                CachedArtworkView(
                    url: backdropURL,
                    client: client,
                    maxPixelSize: 3840,
                    placeholderSymbol: "film",
                    contentMode: .fill,
                    reuseAnyCachedSize: true,
                    retainDuringPlayback: true
                )
            }
            VStack {
                if !placement.relocateToTop {
                    Spacer()
                }
                Group {
                    if boxAlpha > 0 {
                        cueText
                            .padding(.horizontal, 26)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LunaTheme.pureBlack.opacity(boxAlpha))
                            }
                    } else {
                        cueText
                            .shadow(color: LunaTheme.pureBlack.opacity(0.95), radius: 4, x: 0, y: 2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.leading, placement.relocateToTop ? placement.leadingInset : 120)
                .padding(.trailing, placement.relocateToTop ? placement.trailingInset : 120)
                .padding(.top, placement.relocateToTop ? placement.topInset : 0)
                .padding(.bottom, placement.relocateToTop ? 0 : placement.bottomInset)
                if placement.relocateToTop {
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CoalescedSeekOverlayLeafView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let viewModel: PlayerViewModel

    var body: some View {
        if abs(viewModel.coalescedSeekDelta) >= 1 && !viewModel.isScrubbing {
            CoalescedSeekFeedbackPillView(deltaSeconds: viewModel.coalescedSeekDelta)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.92).combined(with: .opacity)
                )
        }
    }
}
