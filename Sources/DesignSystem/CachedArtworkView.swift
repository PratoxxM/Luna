import CoreGraphics
import Foundation
import Observation
import SwiftUI

// MARK: - Shared Memory Notification Relay (2 Observers App-Wide Instead of 2N Per-Card)

@MainActor
@Observable
fileprivate final class ArtworkMemoryNotificationRelay {
    static let shared = ArtworkMemoryNotificationRelay()

    private(set) var purgeEpoch: UInt64 = 0
    private(set) var rehydrateEpoch: UInt64 = 0

    @ObservationIgnored private var purgeObserver: NSObjectProtocol?
    @ObservationIgnored private var exitPlaybackObserver: NSObjectProtocol?

    private init() {
        purgeObserver = NotificationCenter.default.addObserver(
            forName: ArtworkPipeline.didPurgeMemoryNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeEpoch &+= 1
            }
        }
        exitPlaybackObserver = NotificationCenter.default.addObserver(
            forName: ArtworkPipeline.didExitPlaybackMemoryModeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rehydrateEpoch &+= 1
            }
        }
    }
}

// MARK: - Off-Main-Thread Cached Artwork View (Zero 1-Frame Stale Reuse Flash)

public struct CachedArtworkView: View, Equatable {
    private struct TaggedCGImage: Equatable {
        let key: String
        let image: CGImage
        let isExact: Bool
        let epoch: UInt64

        static func == (lhs: TaggedCGImage, rhs: TaggedCGImage) -> Bool {
            lhs.key == rhs.key &&
                lhs.image === rhs.image &&
                lhs.isExact == rhs.isExact &&
                lhs.epoch == rhs.epoch
        }
    }

    @MainActor
    private final class SyncArtworkHitBox {
        var hit: TaggedCGImage?

        nonisolated init() {}
    }

    let url: URL?
    let client: LunaCoreClient?
    let maxPixelSize: Int
    let blurHash: String?
    let dominantColor: String?
    let placeholderSymbol: String
    let contentMode: ContentMode
    let reuseAnyCachedSize: Bool
    let progressiveFallback: Bool
    let retainDuringPlayback: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedArtwork: TaggedCGImage?
    @State private var decodedBlur: TaggedCGImage?
    @State private var syncHitBox = SyncArtworkHitBox()

    public init(
        url: URL?,
        client: LunaCoreClient? = nil,
        maxPixelSize: Int = 720,
        blurHash: String? = nil,
        dominantColor: String? = nil,
        placeholderSymbol: String = "film",
        contentMode: ContentMode = .fill,
        reuseAnyCachedSize: Bool = false,
        progressiveFallback: Bool = false,
        retainDuringPlayback: Bool = false
    ) {
        self.url = url
        self.client = client
        self.maxPixelSize = maxPixelSize
        self.blurHash = blurHash
        self.dominantColor = dominantColor
        self.placeholderSymbol = placeholderSymbol
        self.contentMode = contentMode
        self.reuseAnyCachedSize = reuseAnyCachedSize
        self.progressiveFallback = progressiveFallback
        self.retainDuringPlayback = retainDuringPlayback

        if retainDuringPlayback,
           let url,
           let slotKey = Self.imageSlotKey(url: url, maxPixelSize: maxPixelSize, reuseAnyCachedSize: reuseAnyCachedSize),
           let immediateHit = Self.lookupMemoryHit(
               url: url,
               maxPixelSize: maxPixelSize,
               reuseAnyCachedSize: reuseAnyCachedSize,
               progressiveFallback: progressiveFallback
           ) {
            _loadedArtwork = State(
                initialValue: TaggedCGImage(
                    key: slotKey,
                    image: immediateHit.image,
                    isExact: immediateHit.isExact,
                    epoch: ArtworkPipeline.shared.memoryEpoch
                )
            )
        } else {
            _loadedArtwork = State(initialValue: nil)
        }
        _decodedBlur = State(initialValue: nil)
    }

    public nonisolated static func == (lhs: CachedArtworkView, rhs: CachedArtworkView) -> Bool {
        lhs.url == rhs.url &&
            lhs.maxPixelSize == rhs.maxPixelSize &&
            lhs.blurHash == rhs.blurHash &&
            lhs.dominantColor == rhs.dominantColor &&
            lhs.placeholderSymbol == rhs.placeholderSymbol &&
            lhs.contentMode == rhs.contentMode &&
            lhs.reuseAnyCachedSize == rhs.reuseAnyCachedSize &&
            lhs.progressiveFallback == rhs.progressiveFallback &&
            lhs.retainDuringPlayback == rhs.retainDuringPlayback &&
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

    internal nonisolated static func shouldSkipAsyncLoad(
        targetImageKey: String?,
        currentMemoryEpoch: UInt64,
        retainDuringPlayback: Bool,
        loadedKey: String?,
        loadedIsExact: Bool,
        loadedEpoch: UInt64,
        syncHitKey: String?,
        syncHitIsExact: Bool,
        syncHitEpoch: UInt64
    ) -> Bool {
        guard let targetImageKey else {
            return false
        }
        if loadedKey == targetImageKey,
           loadedIsExact,
           retainDuringPlayback || loadedEpoch == currentMemoryEpoch {
            return true
        }
        if syncHitKey == targetImageKey,
           syncHitIsExact,
           retainDuringPlayback || syncHitEpoch == currentMemoryEpoch {
            return true
        }
        return false
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

    private nonisolated static func lookupMemoryHit(
        url: URL,
        maxPixelSize: Int,
        reuseAnyCachedSize: Bool,
        progressiveFallback: Bool
    ) -> (image: CGImage, isExact: Bool)? {
        if reuseAnyCachedSize || progressiveFallback {
            guard let hit = ArtworkPipeline.shared.anyMemoryCachedImage(
                for: url,
                preferredMaxPixelSize: maxPixelSize
            ) else {
                return nil
            }
            let exactKey = ArtworkPipeline.cacheKey(for: url, maxPixelSize: maxPixelSize)
            let isExact = reuseAnyCachedSize || hit.key == exactKey
            return (image: hit.image, isExact: isExact)
        }
        guard let exact = ArtworkPipeline.shared.memoryCachedImage(
            for: url,
            maxPixelSize: maxPixelSize
        ) else {
            return nil
        }
        return (image: exact, isExact: true)
    }

    private var currentImageKey: String? {
        Self.imageSlotKey(url: url, maxPixelSize: maxPixelSize, reuseAnyCachedSize: reuseAnyCachedSize)
    }

    private var currentBlurKey: String? {
        Self.normalizedBlurKey(blurHash)
    }

    public var body: some View {
        let currentEpoch = ArtworkPipeline.shared.memoryEpoch
        let purgeEpoch = retainDuringPlayback ? 0 : ArtworkMemoryNotificationRelay.shared.purgeEpoch
        let cgImage = resolveCurrentImage(expectedKey: currentImageKey, memoryEpoch: currentEpoch)
        let rehydrateToken: UInt64 = (cgImage == nil && url != nil)
            ? ArtworkMemoryNotificationRelay.shared.rehydrateEpoch
            : 0

        ZStack {
            if let cgImage {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                placeholderLayer
            }
        }
        .onChange(of: purgeEpoch) { _, _ in
            guard !retainDuringPlayback else { return }
            syncHitBox.hit = nil
            if loadedArtwork != nil {
                loadedArtwork = nil
            }
            if decodedBlur != nil {
                decodedBlur = nil
            }
        }
        .task(id: "\(currentImageKey ?? "nil")#\(currentBlurKey ?? "")#\(purgeEpoch)#\(rehydrateToken)") {
            guard retainDuringPlayback || !ArtworkPipeline.shared.isPlaybackActive else {
                return
            }

            let taskEpoch = ArtworkPipeline.shared.memoryEpoch
            let targetImageKey = currentImageKey
            if Self.shouldSkipAsyncLoad(
                targetImageKey: targetImageKey,
                currentMemoryEpoch: taskEpoch,
                retainDuringPlayback: retainDuringPlayback,
                loadedKey: loadedArtwork?.key,
                loadedIsExact: loadedArtwork?.isExact ?? false,
                loadedEpoch: loadedArtwork?.epoch ?? 0,
                syncHitKey: syncHitBox.hit?.key,
                syncHitIsExact: syncHitBox.hit?.isExact ?? false,
                syncHitEpoch: syncHitBox.hit?.epoch ?? 0
            ) {
                return
            }

            let targetBlurKey = currentBlurKey
            guard let url, let targetImageKey else {
                if loadedArtwork != nil {
                    loadedArtwork = nil
                }
                await ensureBlurHashDecoded(targetBlurKey: targetBlurKey, epoch: taskEpoch)
                return
            }

            let hasCurrentPreview =
                (loadedArtwork?.key == targetImageKey && (retainDuringPlayback || loadedArtwork?.epoch == taskEpoch)) ||
                (syncHitBox.hit?.key == targetImageKey && (retainDuringPlayback || syncHitBox.hit?.epoch == taskEpoch))

            if !hasCurrentPreview {
                if let ramHit = Self.lookupMemoryHit(
                    url: url,
                    maxPixelSize: maxPixelSize,
                    reuseAnyCachedSize: reuseAnyCachedSize,
                    progressiveFallback: progressiveFallback
                ) {
                    let tagged = TaggedCGImage(
                        key: targetImageKey,
                        image: ramHit.image,
                        isExact: ramHit.isExact,
                        epoch: taskEpoch
                    )
                    syncHitBox.hit = tagged
                    if ramHit.isExact {
                        loadedArtwork = tagged
                        return
                    }
                } else {
                    if loadedArtwork != nil {
                        loadedArtwork = nil
                    }
                    await ensureBlurHashDecoded(targetBlurKey: targetBlurKey, epoch: taskEpoch)
                }
            }

            let epochBeforeLoad = ArtworkPipeline.shared.memoryEpoch
            let fetched = await ArtworkPipeline.shared.loadImage(
                url: url,
                maxPixelSize: maxPixelSize,
                client: client
            )
            guard !Task.isCancelled,
                  retainDuringPlayback || !ArtworkPipeline.shared.isPlaybackActive else {
                return
            }
            if let fetched {
                let tag = TaggedCGImage(
                    key: targetImageKey,
                    image: fetched,
                    isExact: true,
                    epoch: epochBeforeLoad
                )
                syncHitBox.hit = tag
                withAnimation(LunaFocusStyle.calmEaseOut(duration: 0.18, reduceMotion: reduceMotion)) {
                    loadedArtwork = tag
                }
            } else if !progressiveFallback, loadedArtwork != nil {
                loadedArtwork = nil
            }
        }
    }

    @MainActor
    private func ensureBlurHashDecoded(targetBlurKey: String?, epoch: UInt64) async {
        guard let targetBlurKey else {
            if decodedBlur != nil {
                decodedBlur = nil
            }
            return
        }
        if let cachedBlur = BlurHashDecoder.cachedImage(targetBlurKey, width: 32, height: 24) {
            if decodedBlur?.key != targetBlurKey || decodedBlur?.image !== cachedBlur {
                decodedBlur = TaggedCGImage(key: targetBlurKey, image: cachedBlur, isExact: true, epoch: epoch)
            }
            return
        }
        if decodedBlur?.key != targetBlurKey {
            decodedBlur = nil
        }
        guard contentMode != .fit else { return }
        if let blurImg = await BlurHashDecoder.decodeAsync(targetBlurKey, width: 32, height: 24),
           !Task.isCancelled {
            decodedBlur = TaggedCGImage(key: targetBlurKey, image: blurImg, isExact: true, epoch: epoch)
        }
    }

    private func resolveCurrentImage(expectedKey: String?, memoryEpoch: UInt64) -> CGImage? {
        guard let expectedKey else {
            return nil
        }
        if let loaded = loadedArtwork,
           loaded.key == expectedKey,
           (retainDuringPlayback || loaded.epoch == memoryEpoch) {
            return loaded.image
        }
        if let sync = syncHitBox.hit,
           sync.key == expectedKey,
           (retainDuringPlayback || sync.epoch == memoryEpoch) {
            return sync.image
        }
        return Self.selectKeyMatchedImage(
            expectedKey: expectedKey,
            stateKey: nil,
            stateImage: nil,
            memoryFallback: {
                guard let url,
                      let hit = Self.lookupMemoryHit(
                          url: url,
                          maxPixelSize: maxPixelSize,
                          reuseAnyCachedSize: reuseAnyCachedSize,
                          progressiveFallback: progressiveFallback
                      ) else {
                    return nil
                }
                syncHitBox.hit = TaggedCGImage(
                    key: expectedKey,
                    image: hit.image,
                    isExact: hit.isExact,
                    epoch: memoryEpoch
                )
                return hit.image
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
