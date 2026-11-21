import SwiftUI

/// Centered floating pill showing coalesced discrete seek offset (`−10 s` / `+20 s`) during ring clicks.
struct CoalescedSeekFeedbackPillView: View {
    let deltaSeconds: Double

    var body: some View {
        let secs = Int(deltaSeconds.rounded())
        let isForward = secs >= 0
        let displayText = isForward ? "+\(secs) s" : "−\(abs(secs)) s"

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

/// 100% opaque OLED-safe Lampelys error recovery card ensuring zero leaked video/subtitle frames behind errors.
struct PlayerFatalErrorOverlayView: View {
    private enum FatalErrorAction: Hashable {
        case retry
        case pickSource
        case dismiss
    }

    let message: String
    let canPickSource: Bool
    let onRetry: () -> Void
    let onPickSource: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedButton: FatalErrorAction?
    @Namespace private var errorFocusNamespace

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

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
                    LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .primary) {
                        onRetry()
                    }
                    .focused($focusedButton, equals: .retry)
                    .prefersDefaultFocus(true, in: errorFocusNamespace)

                    if canPickSource {
                        LunaPillButton("Velg kilde", systemImage: "film.stack", prominence: .glassPill) {
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
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTokens.Surface.sheet)
            )
            .lunaTopLightEdge(
                cornerRadius: LunaTokens.Radius.panel,
                topColor: LunaTokens.Edge.top3,
                sideColor: LunaTokens.Edge.top1,
                lineWidth: LunaTokens.Layout.hairlineWidth
            )
            .shadow(color: LunaTheme.pureBlack.opacity(0.65), radius: 36, x: 0, y: 18)
        }
        .focusScope(errorFocusNamespace)
        .onAppear {
            focusedButton = .retry
        }
        .task(id: message) {
            try? await Task.sleep(nanoseconds: 24_000_000)
            guard !Task.isCancelled else { return }
            if focusedButton == nil {
                focusedButton = .retry
            }
        }
    }
}
