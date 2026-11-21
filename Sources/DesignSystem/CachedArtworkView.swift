import CoreGraphics
import SwiftUI

// MARK: - Off-Main-Thread Cached Artwork View (Zero 1-Frame Stale Reuse Flash)

public struct CachedArtworkView: View, Equatable {
    private struct TaggedCGImage: Equatable {
        let key: String
        let image: CGImage

        static func == (lhs: TaggedCGImage, rhs: TaggedCGImage) -> Bool {
            lhs.key == rhs.key && lhs.image === rhs.image
        }
    }

    let url: URL?
    let client: LunaCoreClient?
    let maxPixelSize: Int
    let blurHash: String?
    let dominantColor: String?
    let placeholderSymbol: String
    let contentMode: ContentMode
    let reuseAnyCachedSize: Bool

    @State private var loadedArtwork: TaggedCGImage? = nil
    @State private var decodedBlur: TaggedCGImage? = nil

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
    }

    public nonisolated static func == (lhs: CachedArtworkView, rhs: CachedArtworkView) -> Bool {
        lhs.url == rhs.url &&
            lhs.maxPixelSize == rhs.maxPixelSize &&
            lhs.blurHash == rhs.blurHash &&
            lhs.dominantColor == rhs.dominantColor &&
            lhs.placeholderSymbol == rhs.placeholderSymbol &&
            lhs.contentMode == rhs.contentMode &&
            lhs.reuseAnyCachedSize == rhs.reuseAnyCachedSize &&
            lhs.client?.baseURL == rhs.client?.baseURL &&
            lhs.client?.deviceToken == rhs.client?.deviceToken
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
                if loadedArtwork != nil {
                    loadedArtwork = nil
                }
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

            if loadedArtwork != nil {
                loadedArtwork = nil
            }
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
            } else if loadedArtwork != nil {
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
                    .font(LunaTheme.Font.cardPlaceholderIcon)
                    .foregroundStyle(LunaTheme.muted.opacity(0.45))
            }
        }
    }
}
