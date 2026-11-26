import SwiftUI

public enum LunaToastTone: Sendable {
    case ok
    case warn
    case danger

    public var dotColor: Color {
        switch self {
        case .ok: return LunaTheme.statusOk
        case .warn: return LunaTheme.warn
        case .danger: return LunaTheme.danger
        }
    }
}

/// Left-aligned loading row positioned along the `90 pt` grid axis.
public struct LunaLoadingRow: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-aligned empty state with calm `64 pt` crescent mark, `pageTitle` headline,
/// zero explanatory paragraphs, and at most one secondary action button.
public struct LunaEmptyState: View {
    let headline: String
    let actionTitle: String?
    let actionSymbol: String?
    let actionProminence: LunaButtonProminence
    let onAction: (() -> Void)?

    public init(
        headline: String,
        actionTitle: String? = nil,
        actionSymbol: String? = nil,
        actionProminence: LunaButtonProminence = .glassPill,
        onAction: (() -> Void)? = nil
    ) {
        self.headline = headline
        self.actionTitle = actionTitle
        self.actionSymbol = actionSymbol
        self.actionProminence = actionProminence
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LunaCrescentMarkView(size: 64, color: LunaTheme.moonlight.opacity(0.50))

            Text(headline)
                .font(LunaTheme.Font.pageTitle)
                .foregroundStyle(LunaTheme.linen)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let onAction {
                LunaPillButton(
                    actionTitle,
                    systemImage: actionSymbol,
                    prominence: actionProminence
                ) {
                    onAction()
                }
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-aligned inline error with calm `8 pt` coral dot, warm `linen` body copy (never red text),
/// and a single focusable secondary retry pill.
public struct LunaInlineError: View {
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    public init(
        message: String,
        retryTitle: String = "Prøv igjen",
        onRetry: @escaping () -> Void
    ) {
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(LunaTheme.coral)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(LunaTheme.Font.body)
                    .foregroundStyle(LunaTheme.linen)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LunaPillButton(retryTitle, systemImage: "arrow.clockwise", prominence: .glassPill) {
                onRetry()
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Borderless bottom-left transient toast capsule (`x = 90`, `bottom = 60`), avoiding top bar & shelf headers.
public struct LunaToast: View {
    let message: String
    let tone: LunaToastTone

    public init(message: String, tone: LunaToastTone = .danger) {
        self.message = message
        self.tone = tone
    }

    public nonisolated static func shouldDisplayMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return !message.isEmpty
    }

    public var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tone.dotColor)
                .frame(width: 8, height: 8)
            Text(message)
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(2)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(LunaTokens.Surface.glass, in: Capsule())
        .shadow(color: LunaTheme.pureBlack.opacity(0.55), radius: 20, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}

public extension View {
    func lunaBottomToast(message: String?, tone: LunaToastTone = .danger) -> some View {
        overlay(alignment: .bottomLeading) {
            if LunaToast.shouldDisplayMessage(message), let message {
                LunaToast(message: message, tone: tone)
                    .padding(.leading, LunaTheme.horizontalGutter)
                    .padding(.bottom, LunaTokens.Layout.safeBottom)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    func lunaBottomToast(
        message: Binding<String?>,
        tone: LunaToastTone = .danger,
        autoClearNanoseconds: UInt64 = 4_000_000_000
    ) -> some View {
        lunaBottomToast(message: message.wrappedValue, tone: tone)
            .task(id: message.wrappedValue) {
                guard let active = message.wrappedValue, !active.isEmpty else { return }
                try? await Task.sleep(nanoseconds: autoClearNanoseconds)
                guard !Task.isCancelled, message.wrappedValue == active else { return }
                message.wrappedValue = nil
            }
    }
}

/// Unified top-center HDR-comfortable player status capsule replacing competing banner/toast overlays.
public struct PlayerStatusPill: View {
    let message: String
    let tone: LunaToastTone
    let showsSpinner: Bool

    public init(
        message: String,
        tone: LunaToastTone = .ok,
        showsSpinner: Bool = false
    ) {
        self.message = message
        self.tone = tone
        self.showsSpinner = showsSpinner
    }

    public var body: some View {
        VStack {
            HStack(spacing: 12) {
                if showsSpinner {
                    ProgressView()
                } else {
                    Circle()
                        .fill(tone.dotColor)
                        .frame(width: 8, height: 8)
                }

                Text(message)
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.moonlight)
                    .lineLimit(2)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(LunaTokens.Surface.glass, in: Capsule())
            .shadow(color: LunaTheme.pureBlack.opacity(0.60), radius: 24, x: 0, y: 10)
            .padding(.top, LunaTokens.Layout.safeTop)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
