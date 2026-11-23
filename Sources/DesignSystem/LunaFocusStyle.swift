import SwiftUI

public enum LunaFocusKind: Sendable {
    case card
    case control
    case listRow
}

public enum LunaFocusStyle {
    public static let springResponse: Double = LunaTokens.Motion.focusSpringResponse
    public static let springDamping: Double = LunaTokens.Motion.focusSpringDamping
    public static let borderWidth: CGFloat = LunaTokens.Layout.focusBorderWidth
    public static let borderOpacity: Double = Double(LunaTokens.Layout.focusBorderOpacity)
    public static let glowBlur: CGFloat = LunaTokens.Layout.focusGlowBlur
    public static let glowOffsetY: CGFloat = LunaTokens.Layout.focusGlowOffsetY
    public static let fadeSeconds: Double = LunaTokens.Motion.focusFadeSeconds
    public static let listMarkerWidth: CGFloat = 3.0

    public static var focusSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    public static var focusFade: Animation {
        .easeOut(duration: fadeSeconds)
    }

    public nonisolated static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : focusSpring
    }

    public nonisolated static func captionRevealAnimation(isFocused: Bool, reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : (isFocused ? focusFade.delay(0.06) : .easeOut(duration: 0.12))
    }

    public nonisolated static func scaleEffect(for kind: LunaFocusKind, isFocused: Bool) -> CGFloat {
        guard isFocused else { return 1.0 }
        switch kind {
        case .card:
            return LunaTokens.Layout.focusScaleCard
        case .control:
            return LunaTokens.Layout.focusScaleControl
        case .listRow:
            return LunaTokens.Layout.focusScaleRow
        }
    }

    public nonisolated static func borderColor(
        isFocused: Bool,
        accentColor: Color = LunaTheme.amber
    ) -> Color {
        guard isFocused else { return .clear }
        return accentColor.opacity(borderOpacity)
    }
}

@MainActor
public struct LunaFocusSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let kind: LunaFocusKind
    let isFocused: Bool
    let cornerRadius: CGFloat
    let accentColor: Color
    let customAccent: Bool

    public init(
        kind: LunaFocusKind,
        isFocused: Bool,
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        accentColor: Color = LunaTheme.amber
    ) {
        self.kind = kind
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.customAccent = accentColor != LunaTheme.amber
    }

    public func body(content: Content) -> some View {
        let isDestructive = customAccent && accentColor == LunaTheme.coral
        let resolvedGlow = customAccent ? accentColor : roomAtmosphere.lampColor
        let resolvedStrength = customAccent ? LunaTokens.Glow.lampStrength : roomAtmosphere.lampStrength
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let borderBase = customAccent ? accentColor : LunaTheme.focusGoldBorder
        let activeBorderColor = LunaFocusStyle.borderColor(
            isFocused: isFocused,
            accentColor: borderBase
        )
        let markerColor = customAccent ? accentColor : LunaTheme.amber

        let glowColor: Color = {
            guard isFocused else { return .clear }
            switch kind {
            case .listRow:
                return .clear
            case .control:
                return isDestructive ? .clear : resolvedGlow.opacity(resolvedStrength)
            case .card:
                return resolvedGlow.opacity(resolvedStrength)
            }
        }()

        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: kind, isFocused: isFocused)

        content
            .overlay(
                Group {
                    if isFocused {
                        switch kind {
                        case .listRow:
                            HStack {
                                Capsule()
                                    .fill(markerColor)
                                    .frame(width: LunaFocusStyle.listMarkerWidth)
                                    .padding(.vertical, 12)
                                Spacer(minLength: 0)
                            }
                        case .control:
                            if isDestructive {
                                shape.strokeBorder(
                                    LunaTheme.coral.opacity(LunaFocusStyle.borderOpacity),
                                    lineWidth: LunaFocusStyle.borderWidth
                                )
                            }
                        case .card:
                            shape.strokeBorder(
                                activeBorderColor,
                                lineWidth: LunaFocusStyle.borderWidth
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .shadow(
                color: glowColor,
                radius: glowColor == .clear ? 0 : LunaFocusStyle.glowBlur,
                x: 0,
                y: glowColor == .clear ? 0 : LunaFocusStyle.glowOffsetY
            )
            .scaleEffect(scale)
            .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: isFocused)
    }
}

/// Inner focus frame applied to card labels: zero resting border on posters/backdrops,
/// crisp `2.0 pt` 85% gold frame on focus, and unified `1.05x` card scale.
@MainActor
private struct LunaCardFocusFrameModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cornerRadius: CGFloat
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: .card, isFocused: isFocused)

        content
            .clipShape(shape)
            .overlay(
                Group {
                    if isFocused {
                        shape.strokeBorder(
                            LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity),
                            lineWidth: LunaFocusStyle.borderWidth
                        )
                    }
                }
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
            )
            .scaleEffect(scale)
            .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: isFocused)
    }
}

/// Outer warm lamp glow placed outside card clipping masks so tvOS never clips the under-glow.
@MainActor
private struct LunaCardLampGlowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? LunaFocusStyle.glowBlur : 0,
                x: 0,
                y: isFocused ? LunaFocusStyle.glowOffsetY : 0
            )
            .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: isFocused)
    }
}

@MainActor
private struct LunaFocusCaptionRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isVisible: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(
                LunaFocusStyle.captionRevealAnimation(isFocused: isFocused, reduceMotion: reduceMotion),
                value: isFocused
            )
            .allowsHitTesting(false)
    }
}

/// Lightweight non-observable tracker of currently mounted `LazyVGrid` / `LazyHStack` card IDs.
/// Updating `mountedIDs` in `.onAppear` / `.onDisappear` triggers zero SwiftUI view invalidations,
/// while guaranteeing downward entry focus from `LunaTopBarView` or filter bars lands on the first
/// currently mounted card even when `index == 0` has scrolled offscreen and unmounted.
@MainActor
public final class MountedEntryCardTracker {
    public private(set) var mountedIDs: Set<String> = []

    public init() {}

    public var hasAnyMounted: Bool {
        !mountedIDs.isEmpty
    }

    public func markAppeared(_ id: String) {
        mountedIDs.insert(id)
    }

    public func markDisappeared(_ id: String) {
        mountedIDs.remove(id)
    }

    public func resolveEntryID(orderedIDs: [String]) -> String? {
        if let firstMounted = orderedIDs.first(where: { mountedIDs.contains($0) }) {
            return firstMounted
        }
        return orderedIDs.first
    }
}

public extension View {
    func lunaFocusSurface(
        _ kind: LunaFocusKind,
        isFocused: Bool,
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        accentColor: Color = LunaTheme.amber
    ) -> some View {
        modifier(
            LunaFocusSurfaceModifier(
                kind: kind,
                isFocused: isFocused,
                cornerRadius: cornerRadius,
                accentColor: accentColor
            )
        )
    }

    func lunaCardFocusFrame(
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        isFocused: Bool
    ) -> some View {
        modifier(LunaCardFocusFrameModifier(cornerRadius: cornerRadius, isFocused: isFocused))
    }

    func lunaCardLampGlow(isFocused: Bool) -> some View {
        modifier(LunaCardLampGlowModifier(isFocused: isFocused))
    }

    func lunaFocusCaptionReveal(isVisible: Bool, isFocused: Bool) -> some View {
        modifier(LunaFocusCaptionRevealModifier(isVisible: isVisible, isFocused: isFocused))
    }

    @MainActor
    func lunaTrackMountedCard(id: String, in tracker: MountedEntryCardTracker) -> some View {
        self
            .onAppear { tracker.markAppeared(id) }
            .onDisappear { tracker.markDisappeared(id) }
    }

    @MainActor
    func lunaRequestDirectFocus(
        nonce: Int,
        isFocused: FocusState<Bool>.Binding
    ) -> some View {
        task(id: nonce) {
            guard nonce > 0 else { return }
            isFocused.wrappedValue = true
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                if !isFocused.wrappedValue {
                    isFocused.wrappedValue = true
                } else {
                    return
                }
            }
        }
    }

    @MainActor
    func lunaEntryFocusTarget<Value: Hashable>(
        nonce: Int,
        isActive: Bool = true,
        focus: FocusState<Value?>.Binding,
        target: @escaping @MainActor () -> Value?,
        onTrigger: (@MainActor () -> Void)? = nil
    ) -> some View {
        task(id: nonce) {
            guard nonce > 0, isActive else { return }
            onTrigger?()
            guard let resolvedTarget = target() else { return }
            focus.wrappedValue = resolvedTarget
            for delayNs: UInt64 in [16_000_000, 48_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, isActive else { return }
                if focus.wrappedValue == nil {
                    focus.wrappedValue = resolvedTarget
                } else {
                    return
                }
            }
        }
    }
}
