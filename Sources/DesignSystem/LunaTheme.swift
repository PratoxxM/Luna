import SwiftUI
import CoreGraphics

public enum LunaTheme {
    /// Near-black warm charcoal menu base (`#0A0908`) — protects LG OLED black floor with zero cold blue cast.
    public static let canvas = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0)
    /// Pure black (`#000000`) reserved for OLED video surface & startup curtain.
    public static let pureBlack = Color.black
    /// Calm matte espresso surface (`#14110F`) for cards, panels, and shelves.
    public static let surface = Color(red: 20.0 / 255.0, green: 17.0 / 255.0, blue: 15.0 / 255.0)
    /// Slightly softer matte espresso (`#181412`) for subtle filter & genre chips.
    public static let surfaceSubtle = Color(red: 24.0 / 255.0, green: 20.0 / 255.0, blue: 18.0 / 255.0)
    /// Elevated matte espresso (`#1E1916`) for resting secondary buttons & grouped Settings rows.
    public static let surfaceRaised = Color(red: 30.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0)
    /// Warm roasted espresso (`#2A231E`) for active/selected secondary controls without competing with «Spill av».
    public static let surfaceSelected = Color(red: 42.0 / 255.0, green: 35.0 / 255.0, blue: 30.0 / 255.0)
    /// Elevated roasted espresso (`#241E1A`) for focused wide settings, drawer, and source-picker rows.
    public static let surfaceElevated = Color(red: 36.0 / 255.0, green: 30.0 / 255.0, blue: 26.0 / 255.0)
    /// Dark HDR/Dolby Vision-safe warm cinema glass (`#120F0D` @ 92%) — avoids tvOS `.ultraThinMaterial` 203-nit washout.
    public static let cinemaGlass = Color(red: 18.0 / 255.0, green: 15.0 / 255.0, blue: 13.0 / 255.0).opacity(0.92)

    /// Warm linen (`#F5F0E8`) for crisp, non-glaring primary titles & headings.
    public static let linen = Color(red: 245.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0)
    /// Warm parchment (`#C8BFB6`) for secondary labels and resting button copy.
    public static let moonlight = Color(red: 200.0 / 255.0, green: 191.0 / 255.0, blue: 182.0 / 255.0)
    /// Daylight-calibrated warm taupe (`#A0968C`) — readable in bright rooms (Frame Pro) while gentle in dark OLED rooms.
    public static let muted = Color(red: 160.0 / 255.0, green: 150.0 / 255.0, blue: 140.0 / 255.0)
    /// Non-glaring warm-white cinema pause timeline fill (`#DDD6CC`).
    public static let pauseWarmLine = Color(red: 221.0 / 255.0, green: 214.0 / 255.0, blue: 204.0 / 255.0)

    /// Muted antique bronze-brass (`#C48C3A`) — primary accent reserved for Siri Remote focus & «Spill av» (`6.78:1` vs `#0A0908`).
    public static let amber = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0)
    /// Deeper warm bronze (`#9E6E27`) for subtle primary gradient depth.
    public static let amberDeep = Color(red: 158.0 / 255.0, green: 110.0 / 255.0, blue: 39.0 / 255.0)
    /// Calm sage-emerald (`#5EBF8E`) reserved strictly for NVMe storage badges & Sett checkmarks.
    public static let emerald = Color(red: 94.0 / 255.0, green: 191.0 / 255.0, blue: 142.0 / 255.0)
    /// Warm terracotta (`#D96B52`) reserved strictly for destructive/reset actions.
    public static let coral = Color(red: 217.0 / 255.0, green: 107.0 / 255.0, blue: 82.0 / 255.0)

    /// Base warm cream border tint (`#FFF4E6`) used at 10–18% opacity for 1 pt matte hairlines.
    public static let warmBorderBase = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0)
    public static let warmBorderSubtle = warmBorderBase.opacity(0.10)
    public static let warmBorder = warmBorderBase.opacity(0.14)
    public static let warmBorderStrong = warmBorderBase.opacity(0.18)

    /// Calm antique bronze Siri Remote focus fill (`#C48C3A -> #9E6E27`) without bright lemon-yellow glare.
    public static let focusGoldTop = amber
    public static let focusGoldBottom = amberDeep
    public static let focusGoldBorder = Color(red: 214.0 / 255.0, green: 170.0 / 255.0, blue: 99.0 / 255.0)
    /// Subtle warm bronze highlight reserved for focused `PrimaryPlayButton` («Spill av»).
    public static let playFocusTop = Color(red: 204.0 / 255.0, green: 150.0 / 255.0, blue: 68.0 / 255.0)

    public static let horizontalGutter: CGFloat = 64
    public static let cardRadius: CGFloat = 18

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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    case coral

    public var color: Color {
        switch self {
        case .amber: return LunaTheme.amber
        case .emerald: return LunaTheme.emerald
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
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isFocused)
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

// MARK: - Off-Main-Thread Cached Artwork View (Zero 1-Frame Stale Reuse Flash)

public struct CachedArtworkView: View {
    private struct TaggedCGImage {
        let key: String
        let image: CGImage
    }

    let url: URL?
    let client: LunaCoreClient?
    let maxPixelSize: Int
    let blurHash: String?
    let dominantColor: String?
    let placeholderSymbol: String
    let contentMode: ContentMode
    let reuseAnyCachedSize: Bool

    @State private var loadedArtwork: TaggedCGImage?
    @State private var decodedBlur: TaggedCGImage?

    public init(
        url: URL?,
        client: LunaCoreClient? = nil,
        maxPixelSize: Int = 720,
        blurHash: String? = nil,
        dominantColor: String? = nil,
        placeholderSymbol: String = "film",
        contentMode: ContentMode = .fill,
        reuseAnyCachedSize: Bool = false
    ) {
        self.url = url
        self.client = client
        self.maxPixelSize = maxPixelSize
        self.blurHash = blurHash
        self.dominantColor = dominantColor
        self.placeholderSymbol = placeholderSymbol
        self.contentMode = contentMode
        self.reuseAnyCachedSize = reuseAnyCachedSize

        let expectedImgKey = Self.imageSlotKey(url: url, maxPixelSize: maxPixelSize, reuseAnyCachedSize: reuseAnyCachedSize)
        if let url, let expectedImgKey, let hit = Self.lookupMemoryImage(
            url: url,
            maxPixelSize: maxPixelSize,
            reuseAnyCachedSize: reuseAnyCachedSize
        ) {
            _loadedArtwork = State(initialValue: TaggedCGImage(key: expectedImgKey, image: hit))
        } else {
            _loadedArtwork = State(initialValue: nil)
        }

        let cleanBlur = Self.normalizedBlurKey(blurHash)
        if let cleanBlur, let blurHit = BlurHashDecoder.cachedImage(cleanBlur, width: 32, height: 24) {
            _decodedBlur = State(initialValue: TaggedCGImage(key: cleanBlur, image: blurHit))
        } else {
            _decodedBlur = State(initialValue: nil)
        }
    }

    /// Pure key-verified resolver ensuring recycled `LazyVGrid` / `LazyHStack` cells never flash
    /// the previous card's bitmap for 1 frame before `.task(id:)` runs.
    public nonisolated static func selectKeyMatchedImage(
        expectedKey: String?,
        stateKey: String?,
        stateImage: CGImage?,
        memoryFallback: () -> CGImage?
    ) -> CGImage? {
        guard let expectedKey else {
            return nil
        }
        if stateKey == expectedKey, let stateImage {
            return stateImage
        }
        return memoryFallback()
    }

    private nonisolated static func imageSlotKey(url: URL?, maxPixelSize: Int, reuseAnyCachedSize: Bool) -> String? {
        guard let url else { return nil }
        return reuseAnyCachedSize
            ? ArtworkPipeline.rawIdentity(for: url)
            : ArtworkPipeline.cacheKey(for: url, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func normalizedBlurKey(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count >= 6 else {
            return nil
        }
        return trimmed
    }

    private nonisolated static func lookupMemoryImage(
        url: URL,
        maxPixelSize: Int,
        reuseAnyCachedSize: Bool
    ) -> CGImage? {
        if reuseAnyCachedSize {
            return ArtworkPipeline.shared.anyMemoryCachedImage(
                for: url,
                preferredMaxPixelSize: maxPixelSize
            )?.image
        }
        return ArtworkPipeline.shared.memoryCachedImage(for: url, maxPixelSize: maxPixelSize)
    }

    private var currentImageKey: String? {
        Self.imageSlotKey(url: url, maxPixelSize: maxPixelSize, reuseAnyCachedSize: reuseAnyCachedSize)
    }

    private var currentBlurKey: String? {
        Self.normalizedBlurKey(blurHash)
    }

    public var body: some View {
        ZStack {
            if let cgImage = resolvedImage {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholderLayer
            }
        }
        .task(id: "\(currentImageKey ?? "nil")#\(currentBlurKey ?? "")") {
            let targetBlurKey = currentBlurKey
            if let targetBlurKey {
                if let cachedBlur = BlurHashDecoder.cachedImage(targetBlurKey, width: 32, height: 24) {
                    if decodedBlur?.key != targetBlurKey || decodedBlur?.image !== cachedBlur {
                        decodedBlur = TaggedCGImage(key: targetBlurKey, image: cachedBlur)
                    }
                } else if decodedBlur?.key != targetBlurKey {
                    decodedBlur = nil
                }
            } else if decodedBlur != nil {
                decodedBlur = nil
            }

            guard let url, let targetImageKey = currentImageKey else {
                loadedArtwork = nil
                if let targetBlurKey, decodedBlur?.key != targetBlurKey, contentMode != .fit {
                    if let blurImg = await BlurHashDecoder.decodeAsync(targetBlurKey, width: 32, height: 24),
                       !Task.isCancelled {
                        decodedBlur = TaggedCGImage(key: targetBlurKey, image: blurImg)
                    }
                }
                return
            }

            if let hit = Self.lookupMemoryImage(
                url: url,
                maxPixelSize: maxPixelSize,
                reuseAnyCachedSize: reuseAnyCachedSize
            ) {
                if loadedArtwork?.key != targetImageKey || loadedArtwork?.image !== hit {
                    loadedArtwork = TaggedCGImage(key: targetImageKey, image: hit)
                }
                return
            }

            loadedArtwork = nil
            if let targetBlurKey, decodedBlur?.key != targetBlurKey, contentMode != .fit {
                if let blurImg = await BlurHashDecoder.decodeAsync(targetBlurKey, width: 32, height: 24),
                   !Task.isCancelled {
                    decodedBlur = TaggedCGImage(key: targetBlurKey, image: blurImg)
                }
            }

            let fetched = await ArtworkPipeline.shared.loadImage(
                url: url,
                maxPixelSize: maxPixelSize,
                client: client
            )
            guard !Task.isCancelled else { return }
            if let fetched {
                withAnimation(.easeOut(duration: 0.18)) {
                    loadedArtwork = TaggedCGImage(key: targetImageKey, image: fetched)
                }
            } else {
                loadedArtwork = nil
            }
        }
    }

    private var resolvedImage: CGImage? {
        Self.selectKeyMatchedImage(
            expectedKey: currentImageKey,
            stateKey: loadedArtwork?.key,
            stateImage: loadedArtwork?.image,
            memoryFallback: {
                guard let url else { return nil }
                return Self.lookupMemoryImage(
                    url: url,
                    maxPixelSize: maxPixelSize,
                    reuseAnyCachedSize: reuseAnyCachedSize
                )
            }
        )
    }

    private var resolvedBlurImage: CGImage? {
        Self.selectKeyMatchedImage(
            expectedKey: currentBlurKey,
            stateKey: decodedBlur?.key,
            stateImage: decodedBlur?.image,
            memoryFallback: {
                guard let currentBlurKey else { return nil }
                return BlurHashDecoder.cachedImage(currentBlurKey, width: 32, height: 24)
            }
        )
    }

    @ViewBuilder
    private var placeholderLayer: some View {
        if contentMode == .fit {
            Color.clear
        } else if let blurCG = resolvedBlurImage {
            Image(decorative: blurCG, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let tint = LunaTheme.color(fromHex: dominantColor) ?? LunaTheme.surfaceRaised
            ZStack {
                LinearGradient(
                    colors: [
                        tint.opacity(0.32),
                        LunaTheme.surface,
                        LunaTheme.canvas,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: placeholderSymbol)
                    .font(.title2)
                    .foregroundStyle(LunaTheme.muted.opacity(0.45))
            }
        }
    }
}
