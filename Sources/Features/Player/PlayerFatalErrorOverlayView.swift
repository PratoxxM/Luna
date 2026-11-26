import SwiftUI

/// Centered floating pill showing coalesced discrete seek offset (`−10 s` / `+20 s`) during ring clicks.
struct CoalescedSeekFeedbackPillView: View {
    let deltaSeconds: Double

    var body: some View {
        let rounded = deltaSeconds.isFinite ? deltaSeconds.rounded() : 0
        let secs = Int(exactly: rounded) ?? (rounded >= 0 ? Int.max : Int.min)
        let isForward = secs >= 0
        let displayText = isForward ? "+\(secs) s" : "−\(secs.magnitude) s"

        HStack(spacing: 12) {
            Image(systemName: isForward ? "goforward" : "gobackward")
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.moonlight)
            Text(displayText)
                .font(LunaTheme.Font.sectionTitle.monospacedDigit())
                .foregroundStyle(LunaTheme.linen)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(LunaTheme.cinemaGlass, in: Capsule())
        .allowsHitTesting(false)
    }
}

/// 100% opaque OLED-safe Lampelys error recovery curtain reusing `PlayerCurtainBackdropView`
/// on startup errors so the background never hard-cuts to flat `#000000`.
struct PlayerFatalErrorOverlayView: View {
    static let cardShadowRadius: CGFloat = 18
    static let cardShadowY: CGFloat = 8
    static let primaryRetryTitle: String = "Prøv på nytt"

    private enum FatalErrorAction: Hashable {
        case retry
        case pickSource
        case dismiss
    }

    let message: String
    let canPickSource: Bool
    var showsCurtainBackdrop: Bool = true
    var backdropURL: URL? = nil
    var client: LunaCoreClient? = nil
    let onRetry: () -> Void
    let onPickSource: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedButton: FatalErrorAction?
    @Namespace private var errorFocusNamespace

    var body: some View {
        ZStack {
            if showsCurtainBackdrop {
                PlayerCurtainBackdropView(
                    backdropURL: backdropURL,
                    client: client
                )
            } else {
                LunaTheme.canvas.ignoresSafeArea()
            }

            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(LunaTheme.Font.largeStatusIcon)
                    .foregroundStyle(LunaTheme.danger)

                Text("Avspilling kunne ikke starte")
                    .font(LunaTheme.Font.pageTitle)
                    .foregroundStyle(LunaTheme.linen)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 740)

                HStack(spacing: 16) {
                    LunaPillButton(
                        Self.primaryRetryTitle,
                        systemImage: "arrow.clockwise",
                        prominence: .primary
                    ) {
                        onRetry()
                    }
                    .focused($focusedButton, equals: .retry)
                    .prefersDefaultFocus(true, in: errorFocusNamespace)

                    if canPickSource {
                        LunaPillButton("Velg utgave", systemImage: "film.stack", prominence: .glassPill) {
                            onPickSource()
                        }
                        .focused($focusedButton, equals: .pickSource)
                    }

                    LunaPillButton("Avslutt", systemImage: "xmark", prominence: .glassPill) {
                        onDismiss()
                    }
                    .focused($focusedButton, equals: .dismiss)
                }
                .padding(.top, 8)
            }
            .padding(LunaTokens.Layout.sheetPadding)
            .frame(maxWidth: LunaTokens.Layout.sheetNarrowW)
            .lunaCinemaGlassSurface(
                fill: LunaTokens.Surface.sheet,
                shadowColor: LunaTheme.pureBlack.opacity(0.58),
                shadowRadius: Self.cardShadowRadius,
                shadowY: Self.cardShadowY
            )
        }
        .focusScope(errorFocusNamespace)
        .onExitCommand {
            onDismiss()
        }
        .onAppear {
            focusedButton = .retry
        }
        .task(id: message) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            if focusedButton == nil {
                focusedButton = .retry
            }
            for delayNs: UInt64 in [24_000_000, 60_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if focusedButton == nil {
                    focusedButton = .retry
                } else {
                    return
                }
            }
        }
    }
}
