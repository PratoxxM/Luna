import SwiftUI

public enum LunaTheme {
    /// Near-black warm charcoal menu base (`#0A0908`) — protects LG OLED black floor with zero cold blue cast.
    public static let canvas = LunaTokens.Surface.canvas
    /// Pure black (`#000000`) reserved for OLED video surface & startup curtain.
    public static let pureBlack = Color.black
    /// Calm matte espresso surface (`#14110F`) for cards, panels, and shelves.
    public static let surface = LunaTokens.Surface.lv1
    /// Slightly softer matte espresso (`#181412`) for subtle filter & genre chips.
    public static let surfaceSubtle = LunaTokens.Surface.subtle
    /// Elevated matte espresso (`#1E1916`) for resting secondary buttons & grouped Settings rows.
    public static let surfaceRaised = LunaTokens.Surface.lv2
    /// Warm roasted espresso (`#2A231E`) for active/selected secondary controls without competing with «Spill av».
    public static let surfaceSelected = LunaTokens.Surface.selected
    /// Elevated roasted espresso (`#241E1A`) for focused wide settings, drawer, and source-picker rows.
    public static let surfaceElevated = LunaTokens.Surface.lv3
    /// Dark HDR/Dolby Vision-safe warm cinema glass (`#120F0D` @ 92%) — avoids tvOS `.ultraThinMaterial` 203-nit washout.
    public static let cinemaGlass = LunaTokens.Surface.glass

    /// Warm linen (`#F5F0E8`) for crisp, non-glaring primary titles & headings.
    public static let linen = LunaTokens.Text.primary
    /// Warm parchment (`#C8BFB6`) for secondary labels and resting button copy.
    public static let moonlight = LunaTokens.Text.secondary
    /// Daylight-calibrated warm taupe (`#A0968C`) — readable in bright rooms (Frame Pro) while gentle in dark OLED rooms.
    public static let muted = LunaTokens.Text.muted
    /// Non-glaring warm-white cinema pause timeline fill (`#DDD6CC`).
    public static let pauseWarmLine = LunaTokens.Text.pauseLine

    /// Muted antique bronze-brass (`#C48C3A`) — primary accent reserved for Siri Remote focus & «Spill av» (`6.78:1` vs `#0A0908`).
    public static let amber = LunaTokens.Accent.primary
    /// Deeper warm bronze (`#9E6E27`) for subtle primary gradient depth.
    public static let amberDeep = LunaTokens.Accent.deep
    /// Calm sage-emerald (`#5EBF8E`) reserved for healthy status, NVMe badges & Sett checkmarks.
    public static let emerald = LunaTokens.Status.ok
    public static let statusOk = LunaTokens.Status.ok
    /// Dedicated warm ochre warning (`#E0A84B`) — distinct from focus bronze so warnings never reuse focus gold.
    public static let warn = LunaTokens.Status.warn
    /// Warm terracotta (`#D96B52`) reserved for destructive/error actions & alerts.
    public static let coral = LunaTokens.Status.danger
    public static let danger = LunaTokens.Status.danger
    public static let statusInfo = LunaTokens.Status.info

    /// Storage tier colors shared across iPhone & tvOS.
    public static let tierNvme = LunaTokens.Tier.nvme
    public static let tierArchive = LunaTokens.Tier.archive
    public static let tierStream = LunaTokens.Tier.stream

    /// Base warm cream border tint (`#FFF4E6`) used at 10–18% opacity for 1 pt matte hairlines.
    public static let warmBorderBase = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0)
    public static let warmBorderSubtle = LunaTokens.Edge.top1
    public static let warmBorder = LunaTokens.Edge.top2
    public static let warmBorderStrong = LunaTokens.Edge.top3

    /// Calm antique bronze Siri Remote focus fill (`#C48C3A -> #9E6E27`) without bright lemon-yellow glare.
    public static let focusGoldTop = amber
    public static let focusGoldBottom = amberDeep
    public static let focusGoldBorder = LunaTokens.Accent.line
    /// Subtle warm bronze highlight reserved for focused `PrimaryPlayButton` («Spill av»).
    public static let playFocusTop = LunaTokens.Accent.playFocusTop

    public static let horizontalGutter: CGFloat = 64
    public static let cardRadius: CGFloat = LunaTokens.Radius.card

    /// Standardized 10-foot tvOS typography scale (`>= 22 pt` floor).
    public enum Font {
        public static var heroSerif: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.heroSerif,
                weight: .semibold,
                design: .serif
            )
        }
        public static var pageTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.pageTitle,
                weight: .bold
            )
        }
        public static var sectionTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.sectionTitle,
                weight: .semibold
            )
        }
        public static var cardTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.cardTitle,
                weight: .semibold
            )
        }
        public static var body: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.body,
                weight: .regular
            )
        }
        public static var subtitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .medium
            )
        }
        public static var caption: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.caption,
                weight: .medium
            )
        }
        public static var badge: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.badge,
                weight: .semibold
            )
        }
    }

    public static var focusGoldGradient: LinearGradient {
        LinearGradient(
            colors: [focusGoldTop, focusGoldBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var playFocusGradient: LinearGradient {
        LinearGradient(
            colors: [playFocusTop, amber, amberDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var primaryAmberGradient: LinearGradient {
        LinearGradient(
            colors: [amber, amberDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static func cardBorderColor(isFocused: Bool) -> Color {
        isFocused ? warmBorderBase.opacity(0.32) : warmBorderBase.opacity(0.12)
    }

    public static func cardTitleColor(isFocused: Bool) -> Color {
        linen
    }

    public static func cardSubtitleColor(isFocused: Bool) -> Color {
        isFocused ? amber : muted
    }

    public static func color(fromHex rawHex: String?) -> Color? {
        guard var cleaned = rawHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Clean Vector Crescent Moon Mark

public struct LunaCrescentMarkView: View {
    public var size: CGFloat
    public var color: Color

    public init(size: CGFloat = 28, color: Color = LunaTheme.amber) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            let outerR = side * 0.44
            let innerR = side * 0.36
            let cutOffset = CGPoint(x: side * 0.17, y: -side * 0.12)

            var path = Path()
            path.addEllipse(
                in: CGRect(
                    x: center.x - outerR,
                    y: center.y - outerR,
                    width: outerR * 2,
                    height: outerR * 2
                )
            )
            path.addEllipse(
                in: CGRect(
                    x: center.x + cutOffset.x - innerR,
                    y: center.y + cutOffset.y - innerR,
                    width: innerR * 2,
                    height: innerR * 2
                )
            )
            context.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Chromeless Focus-Safe tvOS Button Style & Matte Espresso Pill Buttons

/// Replaces `.buttonStyle(.plain)` across Luna so tvOS 18–26+ never injects a bright
/// white rectangular system platter behind custom pill buttons.
public struct LunaChromelessButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: LunaTokens.Motion.pressDuration), value: configuration.isPressed)
    }
}

public enum LunaButtonProminence: Sendable {
    case primaryAmber
    case glassPill
    case subtleChip
}

public enum LunaButtonAccent: Sendable {
    case amber
    case emerald
    case warn
    case coral

    public var color: Color {
        switch self {
        case .amber: return LunaTheme.amber
        case .emerald: return LunaTheme.emerald
        case .warn: return LunaTheme.warn
        case .coral: return LunaTheme.coral
        }
    }
}

public enum LunaButtonSize: Sendable {
    case regular
    case compact
}

public struct LunaPillButton: View {
    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        badgeText: String? = nil,
        isSelected: Bool = false,
        prominence: LunaButtonProminence = .glassPill,
        accent: LunaButtonAccent = .amber,
        size: LunaButtonSize = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.isSelected = isSelected
        self.prominence = prominence
        self.accent = accent
        self.size = size
        self.action = action
    }

    public nonisolated static func resolveIconForeground(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
        }
        if accent == .warn {
            return LunaTheme.warn
        }
        if isSelected {
            return accent == .emerald ? LunaTheme.emerald : LunaTheme.linen
        }
        return LunaTheme.moonlight
    }

    public nonisolated static func resolveLabelForeground(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if accent == .coral {
            return LunaTheme.coral
        }
        if accent == .warn {
            return LunaTheme.warn
        }
        if isSelected {
            return LunaTheme.linen
        }
        return LunaTheme.moonlight
    }

    public nonisolated static func resolveBorderColor(
        isFocused: Bool,
        isSelected: Bool,
        prominence: LunaButtonProminence,
        accent: LunaButtonAccent
    ) -> Color {
        if isFocused {
            return LunaTheme.focusGoldBorder
        }
        switch prominence {
        case .primaryAmber:
            return LunaTheme.focusGoldBorder.opacity(0.45)
        case .glassPill, .subtleChip:
            if accent == .coral {
                return LunaTheme.coral.opacity(0.42)
            }
            if accent == .warn {
                return LunaTheme.warn.opacity(0.42)
            }
            if isSelected {
                return accent == .emerald ? LunaTheme.emerald.opacity(0.38) : LunaTheme.warmBorderStrong
            }
            return prominence == .glassPill ? LunaTheme.warmBorder : LunaTheme.warmBorderSubtle
        }
    }

    public var body: some View {
        Button(action: action) {
            LunaPillLabel(
                title: title,
                systemImage: systemImage,
                badgeText: badgeText,
                isSelected: isSelected,
                prominence: prominence,
                accent: accent,
                size: size
            )
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }
}

private struct LunaPillLabel: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let accent: LunaButtonAccent
    let size: LunaButtonSize

    var body: some View {
        let isCompact = size == .compact
        HStack(spacing: isCompact ? 7 : 9) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: isCompact ? 15 : 17, weight: .semibold))
                    .foregroundStyle(iconForegroundColor)
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: isCompact ? 17 : 19, weight: .medium))
                    .foregroundStyle(labelForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badgeBackground))
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 13 : 15) : (isCompact ? 16 : 19))
        .padding(.vertical, isCompact ? 8 : 9)
        .background(backgroundView)
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: borderWidth)
                .transaction { $0.animation = nil }
        )
        .shadow(
            color: isFocused ? Color.black.opacity(0.34) : .clear,
            radius: isFocused ? 10 : 0,
            x: 0,
            y: isFocused ? 4 : 0
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(LunaFocusStyle.focusSpring, value: isFocused)
    }

    private var iconForegroundColor: Color {
        LunaPillButton.resolveIconForeground(
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var labelForegroundColor: Color {
        LunaPillButton.resolveLabelForeground(
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var badgeForegroundColor: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if isSelected {
            return LunaTheme.linen
        }
        return LunaTheme.muted
    }

    private var restingSolidColor: Color {
        switch prominence {
        case .primaryAmber:
            return .clear
        case .glassPill:
            return isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised
        case .subtleChip:
            return isSelected ? LunaTheme.surfaceSelected : LunaTheme.surfaceSubtle
        }
    }

    private var backgroundView: some View {
        ZStack {
            Capsule()
                .fill(restingSolidColor)
                .opacity(!isFocused && prominence != .primaryAmber ? 1 : 0)
            Capsule()
                .fill(LunaTheme.primaryAmberGradient)
                .opacity(!isFocused && prominence == .primaryAmber ? 1 : 0)
            Capsule()
                .fill(LunaTheme.focusGoldGradient)
                .opacity(isFocused ? 1 : 0)
        }
        .transaction { $0.animation = nil }
    }

    private var borderColor: Color {
        LunaPillButton.resolveBorderColor(
            isFocused: isFocused,
            isSelected: isSelected,
            prominence: prominence,
            accent: accent
        )
    }

    private var borderWidth: CGFloat {
        if isFocused { return 2.0 }
        return 1.0
    }

    private var badgeBackground: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas.opacity(0.16)
        }
        if isSelected {
            return LunaTheme.warmBorderBase.opacity(0.14)
        }
        return LunaTheme.warmBorderBase.opacity(0.08)
    }
}
