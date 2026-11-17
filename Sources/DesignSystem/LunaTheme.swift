import SwiftUI
import CoreGraphics

public enum LunaTheme {
    /// Deep midnight menu canvas (`#07090E`) — calm, warm-neutral dark cinema base.
    public static let canvas = Color(red: 7.0 / 255.0, green: 9.0 / 255.0, blue: 14.0 / 255.0)
    /// Pure black (`#000000`) reserved for OLED video surface & resolving curtain.
    public static let pureBlack = Color.black
    /// Elevated card / panel surface (`#0E131D`).
    public static let surface = Color(red: 14.0 / 255.0, green: 19.0 / 255.0, blue: 29.0 / 255.0)
    /// Slightly lighter elevated surface (`#161E2E`).
    public static let surfaceRaised = Color(red: 22.0 / 255.0, green: 30.0 / 255.0, blue: 46.0 / 255.0)
    /// Dark HDR/Dolby Vision-safe cinema glass (`#0C0F17` @ 90%) — avoids tvOS `.ultraThinMaterial` 203-nit HDR washout.
    public static let cinemaGlass = Color(red: 12.0 / 255.0, green: 15.0 / 255.0, blue: 23.0 / 255.0).opacity(0.90)

    /// Warm amber accent (`#F5C46B`) — primary focus glow, progress bars, favorite stars.
    public static let amber = Color(red: 245.0 / 255.0, green: 196.0 / 255.0, blue: 107.0 / 255.0)
    /// Deeper warm gold (`#D99B38`) for gradients.
    public static let amberDeep = Color(red: 217.0 / 255.0, green: 155.0 / 255.0, blue: 56.0 / 255.0)
    /// Soft moonlight silver-blue (`#E6ECF5`) for crisp readable secondary labels.
    public static let moonlight = Color(red: 230.0 / 255.0, green: 236.0 / 255.0, blue: 245.0 / 255.0)
    /// Muted slate (`#93A2B8`) for metadata subtitles.
    public static let muted = Color(red: 147.0 / 255.0, green: 162.0 / 255.0, blue: 184.0 / 255.0)
    /// Soft emerald (`#62D6A2`) for instant NVMe tier badges & watched checkmarks.
    public static let emerald = Color(red: 98.0 / 255.0, green: 214.0 / 255.0, blue: 162.0 / 255.0)
    /// Celestial periwinkle (`#94A8FF`) for watchlist & follow/monitor states.
    public static let periwinkle = Color(red: 148.0 / 255.0, green: 168.0 / 255.0, blue: 255.0 / 255.0)
    /// Night-Fury coral (`#F07167`) for clear, reset, and unpair actions.
    public static let coral = Color(red: 240.0 / 255.0, green: 113.0 / 255.0, blue: 103.0 / 255.0)

    /// Elevated Twilight Starry-Blue resting button fill (`#34466C -> #293858`, `L* ≈ 24–30`).
    public static let buttonGlassTop = Color(red: 52.0 / 255.0, green: 70.0 / 255.0, blue: 108.0 / 255.0)
    public static let buttonGlassBottom = Color(red: 41.0 / 255.0, green: 56.0 / 255.0, blue: 88.0 / 255.0)
    /// Elevated Celestial Indigo lift for secondary filter & genre chips (`#2F4063 -> #253351`).
    public static let buttonSubtleTop = Color(red: 47.0 / 255.0, green: 64.0 / 255.0, blue: 99.0 / 255.0).opacity(0.94)
    public static let buttonSubtleBottom = Color(red: 37.0 / 255.0, green: 51.0 / 255.0, blue: 81.0 / 255.0).opacity(0.92)
    /// Deep Starry-Indigo anchor base underneath rich 28–32% semantic selected tints.
    public static let buttonSelectedBaseTop = Color(red: 31.0 / 255.0, green: 44.0 / 255.0, blue: 71.0 / 255.0)
    public static let buttonSelectedBaseBottom = Color(red: 23.0 / 255.0, green: 33.0 / 255.0, blue: 55.0 / 255.0)
    /// Warm golden Luna Siri Remote focus glow (`#FCE19E -> #F2B544` champagne-amber gradient).
    public static let focusGoldTop = Color(red: 252.0 / 255.0, green: 225.0 / 255.0, blue: 158.0 / 255.0)
    public static let focusGoldBottom = Color(red: 242.0 / 255.0, green: 181.0 / 255.0, blue: 68.0 / 255.0)
    public static let focusGoldBorder = Color(red: 255.0 / 255.0, green: 243.0 / 255.0, blue: 206.0 / 255.0)
    /// Brighter platinum-gold sheen reserved for focused `PrimaryPlayButton` («Spill av»).
    public static let playFocusTop = Color(red: 255.0 / 255.0, green: 245.0 / 255.0, blue: 214.0 / 255.0)
    public static let playFocusBottom = Color(red: 234.0 / 255.0, green: 167.0 / 255.0, blue: 59.0 / 255.0)

    public static let horizontalGutter: CGFloat = 64

    public static var buttonRestGradient: LinearGradient {
        LinearGradient(
            colors: [buttonGlassTop, buttonGlassBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var buttonSubtleGradient: LinearGradient {
        LinearGradient(
            colors: [buttonSubtleTop, buttonSubtleBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var buttonSelectedBaseGradient: LinearGradient {
        LinearGradient(
            colors: [buttonSelectedBaseTop, buttonSelectedBaseBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            colors: [
                playFocusTop,
                Color(red: 249.0 / 255.0, green: 206.0 / 255.0, blue: 110.0 / 255.0),
                playFocusBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var primaryAmberGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 248.0 / 255.0, green: 203.0 / 255.0, blue: 114.0 / 255.0),
                amberDeep,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static func topInnerHighlightGradient(isFocused: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isFocused ? 0.65 : 0.26),
                Color.white.opacity(isFocused ? 0.16 : 0.05),
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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

    public static func symbolForGenre(slug: String, serverIcon: String?) -> String {
        if let icon = serverIcon?.trimmingCharacters(in: .whitespacesAndNewlines),
           !icon.isEmpty,
           icon.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) {
            return icon
        }
        switch slug.lowercased() {
        case "animasjon", "animation": return "sparkles"
        case "action", "action-adventure": return "bolt.fill"
        case "eventyr", "adventure": return "safari.fill"
        case "komedie", "comedy": return "face.smiling.fill"
        case "krim", "crime": return "magnifyingglass.circle.fill"
        case "dokumentar", "documentary": return "globe.europe.africa.fill"
        case "drama": return "theatermasks.fill"
        case "familie", "family": return "house.and.flag.fill"
        case "fantasy", "sci-fi-fantasy": return "wand.and.stars"
        case "historie", "history": return "hourglass"
        case "skrekk", "horror": return "moon.zzz.fill"
        case "musikk", "music": return "music.quarternote.3"
        case "mysterium", "mystery": return "eye.fill"
        case "romantikk", "romance": return "heart.fill"
        case "sci-fi", "science-fiction": return "atom"
        case "thriller": return "waveform.path.ecg"
        case "krig", "war": return "shield.lefthalf.filled"
        case "western": return "sun.dust.fill"
        case "reality": return "tv.and.mediabox"
        default: return "film.stack"
        }
    }
}

// MARK: - Chromeless Focus-Safe tvOS Button Style & Pill Buttons

/// Replaces `.buttonStyle(.plain)` across Luna.
/// On tvOS (including tvOS 18–26+ Liquid Glass), SwiftUI's built-in `PlainButtonStyle`
/// still injects a bright white rectangular platter behind focused labels even when
/// `.focusEffectDisabled()` is set. A custom `ButtonStyle` renders strictly `configuration.label`.
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
    case periwinkle
    case coral

    public var color: Color {
        switch self {
        case .amber: return LunaTheme.amber
        case .emerald: return LunaTheme.emerald
        case .periwinkle: return LunaTheme.periwinkle
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
        HStack(spacing: isCompact ? 8 : 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(isCompact ? .system(size: 22, weight: .bold) : .callout.weight(.bold))
                    .foregroundStyle(iconForegroundColor)
            }
            if !title.isEmpty {
                Text(title)
                    .font(isCompact ? .system(size: 25, weight: .semibold) : .callout.weight(.semibold))
                    .foregroundStyle(labelForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(badgeForegroundColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeBackground, in: Capsule())
            }
        }
        .padding(.horizontal, title.isEmpty ? (isCompact ? 15 : 18) : (isCompact ? 18 : 22))
        .padding(.vertical, isCompact ? 11 : 12)
        .background(backgroundView)
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.topInnerHighlightGradient(isFocused: isFocused), lineWidth: 1.0)
        )
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .shadow(
            color: shadowColor,
            radius: isFocused ? 20 : (isSelected ? 12 : 8),
            x: 0,
            y: isFocused ? 8 : 4
        )
        .scaleEffect(isFocused ? 1.055 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isFocused)
    }

    private var iconForegroundColor: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if isSelected || accent == .coral {
            return accent.color
        }
        return LunaTheme.moonlight
    }

    private var labelForegroundColor: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if isSelected {
            return .white
        }
        return LunaTheme.moonlight
    }

    private var badgeForegroundColor: Color {
        if isFocused || prominence == .primaryAmber {
            return LunaTheme.canvas
        }
        if isSelected {
            return .white
        }
        return LunaTheme.moonlight
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            Capsule().fill(LunaTheme.focusGoldGradient)
        } else {
            switch prominence {
            case .primaryAmber:
                Capsule().fill(LunaTheme.primaryAmberGradient)
            case .glassPill:
                ZStack {
                    Capsule().fill(isSelected ? LunaTheme.buttonSelectedBaseGradient : LunaTheme.buttonRestGradient)
                    if isSelected {
                        Capsule().fill(accent.color.opacity(0.30))
                    } else if accent == .coral {
                        Capsule().fill(LunaTheme.coral.opacity(0.16))
                    }
                }
            case .subtleChip:
                ZStack {
                    Capsule().fill(isSelected ? LunaTheme.buttonSelectedBaseGradient : LunaTheme.buttonSubtleGradient)
                    if isSelected {
                        Capsule().fill(accent.color.opacity(0.28))
                    } else if accent == .coral {
                        Capsule().fill(LunaTheme.coral.opacity(0.15))
                    }
                }
            }
        }
    }

    private var borderColor: Color {
        if isFocused {
            return LunaTheme.focusGoldBorder
        }
        switch prominence {
        case .primaryAmber:
            return LunaTheme.focusGoldBorder.opacity(0.55)
        case .glassPill:
            if isSelected {
                return accent.color.opacity(0.92)
            }
            if accent == .coral {
                return LunaTheme.coral.opacity(0.68)
            }
            return LunaTheme.moonlight.opacity(0.38)
        case .subtleChip:
            if isSelected {
                return accent.color.opacity(0.90)
            }
            if accent == .coral {
                return LunaTheme.coral.opacity(0.62)
            }
            return LunaTheme.moonlight.opacity(0.30)
        }
    }

    private var borderWidth: CGFloat {
        if isFocused { return 2.3 }
        if isSelected { return 1.75 }
        return prominence == .glassPill ? 1.2 : 1.05
    }

    private var shadowColor: Color {
        if isFocused {
            return LunaTheme.amber.opacity(0.54)
        }
        if prominence == .primaryAmber {
            return LunaTheme.amber.opacity(0.30)
        }
        if isSelected {
            return accent.color.opacity(0.30)
        }
        return Color.black.opacity(0.36)
    }

    private var badgeBackground: Color {
        if isFocused || prominence == .primaryAmber {
            return Color.black.opacity(0.18)
        }
        if isSelected {
            return accent.color.opacity(0.34)
        }
        return Color.white.opacity(0.16)
    }
}

// MARK: - Off-Main-Thread Cached Artwork View

public struct CachedArtworkView: View {
    let url: URL?
    let client: LunaCoreClient?
    let maxPixelSize: Int
    let blurHash: String?
    let dominantColor: String?
    let placeholderSymbol: String
    let contentMode: ContentMode

    @State private var loadedCGImage: CGImage?
    @State private var decodedBlurCGImage: CGImage?

    public init(
        url: URL?,
        client: LunaCoreClient? = nil,
        maxPixelSize: Int = 720,
        blurHash: String? = nil,
        dominantColor: String? = nil,
        placeholderSymbol: String = "film",
        contentMode: ContentMode = .fill
    ) {
        self.url = url
        self.client = client
        self.maxPixelSize = maxPixelSize
        self.blurHash = blurHash
        self.dominantColor = dominantColor
        self.placeholderSymbol = placeholderSymbol
        self.contentMode = contentMode

        if let url, let memHit = ArtworkPipeline.shared.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) {
            _loadedCGImage = State(initialValue: memHit)
        } else {
            _loadedCGImage = State(initialValue: nil)
        }
        _decodedBlurCGImage = State(initialValue: BlurHashDecoder.cachedImage(blurHash, width: 32, height: 24))
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
        .task(id: "\(url?.absoluteString ?? "nil")#\(blurHash ?? "")") {
            let targetBlur = BlurHashDecoder.cachedImage(blurHash, width: 32, height: 24)
            if decodedBlurCGImage !== targetBlur {
                decodedBlurCGImage = targetBlur
            }

            guard let url else {
                loadedCGImage = nil
                if decodedBlurCGImage == nil, contentMode != .fit, blurHash != nil {
                    if let blurImg = await BlurHashDecoder.decodeAsync(blurHash, width: 32, height: 24), !Task.isCancelled {
                        decodedBlurCGImage = blurImg
                    }
                }
                return
            }
            if let hit = ArtworkPipeline.shared.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) {
                if loadedCGImage !== hit {
                    loadedCGImage = hit
                }
                return
            }
            // Clear previous cell's artwork while loading the new URL.
            loadedCGImage = nil
            if decodedBlurCGImage == nil, contentMode != .fit, blurHash != nil {
                if let blurImg = await BlurHashDecoder.decodeAsync(blurHash, width: 32, height: 24), !Task.isCancelled {
                    decodedBlurCGImage = blurImg
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
                    loadedCGImage = fetched
                }
            } else {
                loadedCGImage = nil
            }
        }
    }

    private var resolvedImage: CGImage? {
        if let loadedCGImage {
            return loadedCGImage
        }
        if let url {
            return ArtworkPipeline.shared.memoryCachedImage(for: url, maxPixelSize: maxPixelSize)
        }
        return nil
    }

    @ViewBuilder
    private var placeholderLayer: some View {
        if contentMode == .fit {
            Color.clear
        } else if let blurCG = decodedBlurCGImage ?? BlurHashDecoder.cachedImage(blurHash, width: 32, height: 24) {
            Image(decorative: blurCG, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let tint = LunaTheme.color(fromHex: dominantColor) ?? LunaTheme.surfaceRaised
            ZStack {
                LinearGradient(
                    colors: [
                        tint.opacity(0.65),
                        LunaTheme.surface,
                        LunaTheme.canvas
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: placeholderSymbol)
                    .font(.title2)
                    .foregroundStyle(LunaTheme.moonlight.opacity(0.28))
            }
        }
    }
}
