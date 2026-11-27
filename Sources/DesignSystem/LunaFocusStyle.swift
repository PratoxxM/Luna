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

    public nonisolated static func calmEaseOut(duration: Double = 0.22, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
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

        let showsGlow: Bool = {
            switch kind {
            case .listRow:
                return false
            case .control:
                return !isDestructive
            case .card:
                return true
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
            .background {
                if showsGlow {
                    glowBackdrop(
                        color: resolvedGlow,
                        strength: resolvedStrength,
                        cornerRadius: cornerRadius,
                        isFocused: isFocused
                    )
                }
            }
            .scaleEffect(scale)
            .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: isFocused)
    }

    @ViewBuilder
    private func glowBackdrop(
        color: Color,
        strength: Double,
        cornerRadius: CGFloat,
        isFocused: Bool
    ) -> some View {
        if cornerRadius >= LunaTokens.Radius.pill {
            Capsule()
                .fill(LunaTheme.surface)
                .shadow(
                    color: color.opacity(strength),
                    radius: LunaFocusStyle.glowBlur,
                    x: 0,
                    y: LunaFocusStyle.glowOffsetY
                )
                .opacity(isFocused ? 1.0 : 0.0)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LunaTheme.surface)
                .shadow(
                    color: color.opacity(strength),
                    radius: LunaFocusStyle.glowBlur,
                    x: 0,
                    y: LunaFocusStyle.glowOffsetY
                )
                .opacity(isFocused ? 1.0 : 0.0)
                .allowsHitTesting(false)
        }
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
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let scale = reduceMotion ? 1.0 : LunaFocusStyle.scaleEffect(for: .card, isFocused: isFocused)

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LunaTheme.surface)
                    .shadow(
                        color: roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength),
                        radius: LunaFocusStyle.glowBlur,
                        x: 0,
                        y: LunaFocusStyle.glowOffsetY
                    )
                    .scaleEffect(scale)
                    .opacity(isFocused ? 1.0 : 0.0)
                    .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: isFocused)
                    .allowsHitTesting(false)
            }
    }
}

@MainActor
private struct LunaFocusCaptionRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isVisible: Bool
    let isFocused: Bool
    let animate: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(
                animate
                    ? LunaFocusStyle.captionRevealAnimation(isFocused: isFocused, reduceMotion: reduceMotion)
                    : nil,
                value: isFocused
            )
            .allowsHitTesting(false)
    }
}

/// Lightweight per-card memoization box for `resolveArtworkURL` so focus transitions or parent
/// re-renders with identical `(path, baseURL, target)` never re-run `URLComponents` parsing.
@MainActor
internal final class ArtworkURLMemoBox {
    private var hasCachedResult: Bool = false
    private var lastPath: String?
    private var lastBaseURL: URL?
    private var lastTarget: LunaCoreClient.ArtworkTargetWidth?
    private var lastResolvedURL: URL?

    nonisolated init() {}

    func resolve(
        path: String?,
        client: LunaCoreClient?,
        target: LunaCoreClient.ArtworkTargetWidth
    ) -> URL? {
        guard let client else {
            return resolve(path: path, baseURL: nil, target: target) { nil }
        }
        return resolve(path: path, baseURL: client.baseURL, target: target) {
            client.resolveArtworkURL(path, target: target)
        }
    }

    func resolve(
        path: String?,
        baseURL: URL?,
        target: LunaCoreClient.ArtworkTargetWidth,
        resolver: () -> URL?
    ) -> URL? {
        if hasCachedResult,
           lastPath == path,
           lastBaseURL == baseURL,
           lastTarget == target {
            return lastResolvedURL
        }
        let resolved = resolver()
        hasCachedResult = true
        lastPath = path
        lastBaseURL = baseURL
        lastTarget = target
        lastResolvedURL = resolved
        return resolved
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

    func lunaCardLampGlow(
        isFocused: Bool,
        cornerRadius: CGFloat = LunaTokens.Radius.card
    ) -> some View {
        modifier(LunaCardLampGlowModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }

    func lunaFocusCaptionReveal(
        isVisible: Bool,
        isFocused: Bool,
        animate: Bool = true
    ) -> some View {
        modifier(
            LunaFocusCaptionRevealModifier(
                isVisible: isVisible,
                isFocused: isFocused,
                animate: animate
            )
        )
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
