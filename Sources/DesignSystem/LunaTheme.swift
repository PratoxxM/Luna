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

    public static let horizontalGutter: CGFloat = 64

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

public struct LunaPillButton: View {
    let title: String
    let systemImage: String?
    let badgeText: String?
    let isSelected: Bool
    let prominence: LunaButtonProminence
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        badgeText: String? = nil,
        isSelected: Bool = false,
        prominence: LunaButtonProminence = .glassPill,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.isSelected = isSelected
        self.prominence = prominence
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LunaPillLabel(
                title: title,
                systemImage: systemImage,
                badgeText: badgeText,
                isSelected: isSelected,
                prominence: prominence
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

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.callout.weight(.bold))
            }
            if !title.isEmpty {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeBackground, in: Capsule())
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, title.isEmpty ? 18 : 24)
        .padding(.vertical, 13)
        .background(backgroundView)
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: isFocused ? 2.2 : 1.0)
        )
        .shadow(
            color: isFocused ? LunaTheme.amber.opacity(0.38) : Color.black.opacity(0.28),
            radius: isFocused ? 18 : 8,
            x: 0,
            y: isFocused ? 8 : 4
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isFocused)
    }

    private var foregroundColor: Color {
        switch prominence {
        case .primaryAmber:
            return isFocused ? LunaTheme.canvas : Color(red: 0.06, green: 0.06, blue: 0.08)
        case .glassPill, .subtleChip:
            if isFocused {
                return .white
            }
            if isSelected {
                return LunaTheme.amber
            }
            return LunaTheme.moonlight.opacity(0.92)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch prominence {
        case .primaryAmber:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: isFocused
                            ? [Color.white, LunaTheme.amber]
                            : [LunaTheme.amber, LunaTheme.amberDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .glassPill:
            ZStack {
                Capsule().fill(LunaTheme.surfaceRaised.opacity(0.95))
                if isFocused {
                    Capsule().fill(LunaTheme.amber.opacity(0.24))
                } else if isSelected {
                    Capsule().fill(LunaTheme.amber.opacity(0.16))
                }
            }
        case .subtleChip:
            ZStack {
                Capsule().fill(LunaTheme.surface.opacity(0.94))
                if isFocused {
                    Capsule().fill(LunaTheme.amber.opacity(0.22))
                } else if isSelected {
                    Capsule().fill(LunaTheme.amber.opacity(0.14))
                }
            }
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .primaryAmber:
            return isFocused ? Color.white.opacity(0.95) : LunaTheme.amber.opacity(0.8)
        case .glassPill, .subtleChip:
            if isFocused {
                return LunaTheme.amber
            }
            if isSelected {
                return LunaTheme.amber.opacity(0.65)
            }
            return LunaTheme.moonlight.opacity(0.16)
        }
    }

    private var badgeBackground: Color {
        if prominence == .primaryAmber {
            return Color.black.opacity(0.18)
        }
        return isSelected || isFocused ? LunaTheme.amber.opacity(0.26) : Color.white.opacity(0.12)
    }
}

// MARK: - Off-Main-Thread Cached Artwork View

public struct CachedArtworkView: View {
    let url: URL?
    let client: MediaOSClient?
    let maxPixelSize: Int
    let blurHash: String?
    let dominantColor: String?
    let placeholderSymbol: String
    let contentMode: ContentMode

    @State private var loadedCGImage: CGImage?
    @State private var decodedBlurCGImage: CGImage?

    public init(
        url: URL?,
        client: MediaOSClient? = nil,
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
        .task(id: url) {
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

/// Backwards-compatible wrapper used by existing views.
struct MediaArtworkImage: View {
    let url: URL?
    let placeholderSymbol: String
    var client: MediaOSClient? = nil
    var maxPixelSize: Int = 720
    var blurHash: String? = nil
    var dominantColor: String? = nil

    var body: some View {
        CachedArtworkView(
            url: url,
            client: client,
            maxPixelSize: maxPixelSize,
            blurHash: blurHash,
            dominantColor: dominantColor,
            placeholderSymbol: placeholderSymbol,
            contentMode: .fill
        )
    }
}
