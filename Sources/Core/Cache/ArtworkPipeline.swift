import Foundation
import ImageIO
import CoreGraphics
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

/// Off-main-thread WebP/JPEG/PNG artwork loader, GPU-ready bitmap cache, and adaptive NVMe disk cache.
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    public nonisolated static let didPurgeMemoryNotification = Notification.Name("LunaArtworkPipelineDidPurgeMemory")
    public nonisolated static let didExitPlaybackMemoryModeNotification = Notification.Name("LunaArtworkPipelineDidExitPlaybackMemoryMode")

    private struct DecodeWaiter {
        let id: UUID
        let key: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    private nonisolated let ramCache = ThreadSafeImageMemoryCache(
        totalCostLimit: DeviceMemoryProfile.current.artworkMemoryBytes,
        countLimit: DeviceMemoryProfile.current.artworkMemoryCountLimit
    )
    private nonisolated let diskTouchTracker = DiskTouchTracker()
    private nonisolated let inflightImages = InflightTaskCoalescer<String, CGImage?>()
    private nonisolated let inflightRawFetches = InflightTaskCoalescer<String, Data?>()
    private nonisolated let isPlaybackActiveFlag = Mutex(false)
    private static let memoryEpochCounter = Mutex<UInt64>(0)
    private nonisolated let activePrefetchTasks = Mutex<[UUID: Task<Void, Never>]>([:])

    public nonisolated var isPlaybackActive: Bool {
        isPlaybackActiveFlag.withLock { $0 }
    }

    public nonisolated var memoryEpoch: UInt64 {
        Self.memoryEpochCounter.withLock { $0 }
    }

    private var writesSinceLastTrim: Int = 0
    private var didEnsureCacheDir: Bool = false

    private let maxConcurrentDecodes = DeviceMemoryProfile.current.maxConcurrentDecodes
    private let trimWriteInterval = DeviceMemoryProfile.current.artworkDiskTrimWriteInterval

    public nonisolated static var defaultDiskMaxBytes: Int64 {
        DeviceMemoryProfile.current.artworkDiskMaxBytes
    }

    private var activeDecodeCount: Int = 0
    private var interactiveDecodeWaiters: [DecodeWaiter] = []
    private var prefetchDecodeWaiters: [DecodeWaiter] = []

    private init() {
        let cache = self.ramCache
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil,
            queue: nil
        ) { _ in
            cache.removeAll()
            BlurHashDecoder.clearCache()
            ArtworkPipeline.memoryEpochCounter.withLock { $0 &+= 1 }
            Task { @MainActor in
                NotificationCenter.default.post(name: ArtworkPipeline.didPurgeMemoryNotification, object: nil)
            }
        }
    }

    private nonisolated func recordAndPostMemoryPurge() {
        Self.memoryEpochCounter.withLock { $0 &+= 1 }
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.didPurgeMemoryNotification, object: nil)
        }
    }

    public nonisolated static func rawIdentity(for url: URL) -> String {
        ArtworkSubjectKey.rawIdentity(for: url)
    }

    public nonisolated static func canonicalSubjectIdentity(for url: URL) -> String {
        ArtworkSubjectKey.canonicalSubjectIdentity(for: url)
    }

    public nonisolated static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        ArtworkSubjectKey.cacheKey(for: url, maxPixelSize: maxPixelSize)
    }

    public nonisolated func memoryCachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        return ramCache.image(forKey: key)
    }

    private nonisolated static let candidateCachedPixelSizes: [Int] = ArtworkSubjectKey.candidateCachedPixelSizes

    /// Looks up any already-decoded bitmap in RAM for `url` (checking exact `preferredMaxPixelSize`,
    /// canonical size-agnostic subject match, and standard pixel buckets) in `0 ms`.
    public nonisolated func anyMemoryCachedImage(
        for url: URL,
        preferredMaxPixelSize: Int
    ) -> (key: String, image: CGImage)? {
        let preferredKey = Self.cacheKey(for: url, maxPixelSize: preferredMaxPixelSize)
        if let exact = ramCache.image(forKey: preferredKey) {
            return (preferredKey, exact)
        }
        let subjectKey = Self.canonicalSubjectIdentity(for: url)
        if let subjectHit = ramCache.bestImage(forSubjectKey: subjectKey) {
            return (subjectKey, subjectHit)
        }
        for bucket in Self.candidateCachedPixelSizes where bucket != preferredMaxPixelSize {
            let key = Self.cacheKey(for: url, maxPixelSize: bucket)
            if let hit = ramCache.image(forKey: key) {
                return (key, hit)
            }
        }
        return nil
    }

    internal nonisolated func insertMemoryCachedImage(_ image: CGImage, url: URL, maxPixelSize: Int) {
        ramCache.insert(
            image,
            forKey: Self.cacheKey(for: url, maxPixelSize: maxPixelSize),
            subjectKey: Self.canonicalSubjectIdentity(for: url)
        )
    }

    public nonisolated func loadImage(
        url: URL,
        maxPixelSize: Int,
        client: LunaCoreClient?,
        priority: ArtworkLoadPriority = .interactive
    ) async -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let memHit = ramCache.image(forKey: key) {
            return memHit
        }

        let taskPriority: TaskPriority = priority == .interactive ? .userInitiated : .utility
        let rawKey = Self.rawIdentity(for: url)
        let subjectKey = Self.canonicalSubjectIdentity(for: url)
        let ramCacheRef = self.ramCache
        if priority == .interactive {
            await promotePrefetchWaiterIfNeeded(forKey: key)
        }

        guard let outcome = await inflightImages.coalesceNonThrowing(
            key: key,
            priority: taskPriority,
            operation: { [self] () -> CGImage? in
                if let memHit = ramCacheRef.image(forKey: key) {
                    return memHit
                }
                guard !Task.isCancelled,
                      let data = await self.acquireRawData(
                          url: url,
                          rawKey: rawKey,
                          client: client,
                          priority: taskPriority
                      ),
                      !Task.isCancelled else {
                    return nil
                }
                guard await self.acquireDecodePermit(key: key, priority: priority) else {
                    return nil
                }
                let decoded: CGImage?
                if Task.isCancelled {
                    decoded = nil
                } else {
                    decoded = await Self.downsampleAndDecode(data: data, maxPixelSize: maxPixelSize)
                }
                await self.releaseDecodePermit()
                guard let decoded else { return nil }
                ramCacheRef.insert(decoded, forKey: key, subjectKey: subjectKey)
                return decoded
            }
        ) else {
            return nil
        }
        return outcome.value
    }

    /// Viewport lookahead prefetching for horizontal shelves and 6-column poster grids.
    /// Automatically pauses during active video playback and yields decode permits to interactive views.
    public nonisolated func prefetchUpcomingCards(
        in cards: [TvMediaCard],
        afterIndex index: Int,
        isBackdrop: Bool = false,
        maxLookahead: Int? = nil,
        client: LunaCoreClient?
    ) {
        guard let client,
              !(isPlaybackActiveFlag.withLock { $0 }),
              index >= 0,
              index + 1 < cards.count else {
            return
        }
        let strideStep = isBackdrop ? 2 : 3
        guard index == 0 || index % strideStep == 0 else { return }

        let window = min(maxLookahead ?? DeviceMemoryProfile.current.scrollPrefetchCardWindow, DeviceMemoryProfile.current.scrollPrefetchCardWindow)
        guard window > 0 else { return }
        let endIndex = min(cards.count, index + 1 + window)
        let targetPixelSize = isBackdrop
            ? ArtworkDecodeTargets.backdropCardMaxPixelSize
            : ArtworkDecodeTargets.posterCardMaxPixelSize
        let urls: [URL] = cards[(index + 1)..<endIndex].compactMap { card in
            let path = isBackdrop ? card.preferredLandscapePath : card.posterUrl
            return client.resolveArtworkURL(path, target: isBackdrop ? .landscape2x : .poster2x)
        }
        prefetchImages(urls: urls, maxPixelSize: targetPixelSize, client: client)
    }

    public nonisolated func prefetchImages(
        urls: [URL],
        maxPixelSize: Int,
        client: LunaCoreClient?
    ) {
        guard !urls.isEmpty, !(isPlaybackActiveFlag.withLock { $0 }) else { return }
        let missingURLs = urls.filter { memoryCachedImage(for: $0, maxPixelSize: maxPixelSize) == nil }
        guard !missingURLs.isEmpty else { return }

        let taskID = UUID()
        let created = Task.detached(priority: .utility) { [self] in
            defer {
                _ = self.activePrefetchTasks.withLock { $0.removeValue(forKey: taskID) }
            }
            let floorBytes = DeviceMemoryProfile.current.playbackMemoryShedFloorBytes
            for url in missingURLs {
                guard !Task.isCancelled, !(self.isPlaybackActiveFlag.withLock { $0 }) else {
                    return
                }
                if self.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) != nil {
                    continue
                }
                if DeviceHardwareCapabilities.availableMemoryBytes() > floorBytes {
                    _ = await self.loadImage(
                        url: url,
                        maxPixelSize: maxPixelSize,
                        client: client,
                        priority: .prefetch
                    )
                } else {
                    _ = await self.acquireRawData(
                        url: url,
                        rawKey: Self.rawIdentity(for: url),
                        client: client,
                        priority: .utility
                    )
                }
            }
        }
        activePrefetchTasks.withLock { map in
            if map.count >= 8 {
                let oldest = Array(map.values)
                map.removeAll(keepingCapacity: true)
                for task in oldest { task.cancel() }
            }
            map[taskID] = created
        }
    }

    /// Cancels background artwork prefetches and proactively frees RAM bitmaps before heavy `.softwareHost`
    /// (4K Dolby Vision Profile 7 FEL / AV1) frame pools allocate when headroom is tight, while keeping
    /// any active curtain backdrop/logo bitmaps resident (`0 ms` curtain reveal).
    public nonisolated func enterPlaybackMemoryMode(
        isHeavySoftwareStream: Bool,
        preservedURLs: [URL] = []
    ) {
        isPlaybackActiveFlag.withLock { $0 = true }
        cancelAllPrefetchTasks()

        let profile = DeviceMemoryProfile.current
        let available = DeviceHardwareCapabilities.availableMemoryBytes()
        let shouldShed = available < profile.playbackMemoryShedFloorBytes
            || (isHeavySoftwareStream && profile.tier == .standard)
        if shouldShed {
            var preservedEntries: [(key: String, subjectKey: String, image: CGImage)] = []
            for url in preservedURLs {
                let subjectKey = Self.canonicalSubjectIdentity(for: url)
                var matchedForURL = false
                for px in Self.candidateCachedPixelSizes {
                    let key = Self.cacheKey(for: url, maxPixelSize: px)
                    if let img = ramCache.image(forKey: key) {
                        preservedEntries.append((key: key, subjectKey: subjectKey, image: img))
                        matchedForURL = true
                    }
                }
                if !matchedForURL, let best = ramCache.bestImage(forSubjectKey: subjectKey) {
                    let fallbackPx = max(best.width, best.height)
                    let key = Self.cacheKey(for: url, maxPixelSize: fallbackPx)
                    preservedEntries.append((key: key, subjectKey: subjectKey, image: best))
                }
            }
            ramCache.removeAll()
            for entry in preservedEntries {
                ramCache.insert(entry.image, forKey: entry.key, subjectKey: entry.subjectKey)
            }
            BlurHashDecoder.clearCache()
            recordAndPostMemoryPurge()
        }
    }

    public nonisolated func exitPlaybackMemoryMode() {
        isPlaybackActiveFlag.withLock { $0 = false }
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.didExitPlaybackMemoryModeNotification, object: nil)
        }
    }

    public nonisolated func handleSceneDidEnterBackground() {
        cancelAllPrefetchTasks()
        ramCache.removeAll()
        BlurHashDecoder.clearCache()
        recordAndPostMemoryPurge()
    }

    private nonisolated func cancelAllPrefetchTasks() {
        let tasks = activePrefetchTasks.withLock { map -> [Task<Void, Never>] in
            let running = Array(map.values)
            map.removeAll()
            return running
        }
        for task in tasks {
            task.cancel()
        }
    }

    private nonisolated func acquireRawData(
        url: URL,
        rawKey: String,
        client: LunaCoreClient?,
        priority: TaskPriority = .userInitiated
    ) async -> Data? {
        let diskFileURL = Self.diskFileURL(for: url)
        let externalSession = LunaCoreSessionPool.shared.externalArtworkSession()
        let diskTouchTracker = self.diskTouchTracker

        guard let outcome = await inflightRawFetches.coalesceNonThrowing(
            key: rawKey,
            priority: priority,
            operation: { [self] () -> Data? in
                guard !Task.isCancelled else { return nil }
                if let diskData = try? Data(contentsOf: diskFileURL), !diskData.isEmpty {
                    ArtworkDiskCache.touchDiskFileIfNeeded(
                        at: diskFileURL,
                        key: rawKey,
                        tracker: diskTouchTracker
                    )
                    return diskData
                }

                guard !Task.isCancelled else { return nil }
                let fetchedData: Data?
                if let client {
                    fetchedData = (try? await client.fetchRawImageData(from: url))?.0
                } else {
                    fetchedData = (try? await externalSession.data(from: url))?.0
                }
                guard !Task.isCancelled, let data = fetchedData, !data.isEmpty else {
                    return nil
                }

                await self.ensureCacheDirectoryIfNeeded()
                do {
                    try data.write(to: diskFileURL, options: .atomic)
                    diskTouchTracker.recordWrite(rawKey, now: Date().timeIntervalSinceReferenceDate)
                    await self.recordDiskWriteCompleted()
                } catch {
                    // Best-effort disk cache write; still decode in-memory data
                }
                return data
            }
        ) else {
            return nil
        }
        return outcome.value
    }

    private func ensureCacheDirectoryIfNeeded() {
        guard !didEnsureCacheDir else { return }
        ArtworkDiskCache.migrateLegacyCacheDirectoryIfNeeded()
        try? FileManager.default.createDirectory(at: Self.imageCacheDirectoryURL, withIntermediateDirectories: true)
        didEnsureCacheDir = true
    }

    private func promotePrefetchWaiterIfNeeded(forKey key: String) {
        if let idx = prefetchDecodeWaiters.firstIndex(where: { $0.key == key }) {
            let promoted = prefetchDecodeWaiters.remove(at: idx)
            interactiveDecodeWaiters.append(promoted)
        }
    }

    private func acquireDecodePermit(key: String, priority: ArtworkLoadPriority) async -> Bool {
        guard !Task.isCancelled else { return false }
        if activeDecodeCount < maxConcurrentDecodes {
            activeDecodeCount += 1
            return true
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                let waiter = DecodeWaiter(id: waiterID, key: key, continuation: continuation)
                switch priority {
                case .interactive:
                    interactiveDecodeWaiters.append(waiter)
                case .prefetch:
                    prefetchDecodeWaiters.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancelDecodeWaiter(id: waiterID) }
        }
    }

    private func cancelDecodeWaiter(id: UUID) {
        if let idx = interactiveDecodeWaiters.firstIndex(where: { $0.id == id }) {
            let removed = interactiveDecodeWaiters.remove(at: idx)
            removed.continuation.resume(returning: false)
            return
        }
        if let idx = prefetchDecodeWaiters.firstIndex(where: { $0.id == id }) {
            let removed = prefetchDecodeWaiters.remove(at: idx)
            removed.continuation.resume(returning: false)
        }
    }

    private func releaseDecodePermit() {
        if !interactiveDecodeWaiters.isEmpty {
            let next = interactiveDecodeWaiters.removeFirst()
            next.continuation.resume(returning: true)
        } else if !prefetchDecodeWaiters.isEmpty {
            let next = prefetchDecodeWaiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeDecodeCount = max(0, activeDecodeCount - 1)
        }
    }

    private func recordDiskWriteCompleted() {
        writesSinceLastTrim += 1
        if writesSinceLastTrim >= trimWriteInterval {
            writesSinceLastTrim = 0
            let maxBytes = Self.defaultDiskMaxBytes
            Task.detached(priority: .utility) {
                Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
            }
        }
    }

    public func trimDiskCacheIfNeeded(maxBytes: Int64 = ArtworkPipeline.defaultDiskMaxBytes) {
        Task.detached(priority: .utility) {
            Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
        }
    }

    public func clearAll() {
        cancelAllPrefetchTasks()
        inflightImages.cancelAll()
        inflightRawFetches.cancelAll()
        ramCache.removeAll()
        BlurHashDecoder.clearCache()
        diskTouchTracker.removeAll()
        didEnsureCacheDir = false
        try? FileManager.default.removeItem(at: Self.imageCacheDirectoryURL)
    }

    /// Hardware-accelerated ImageIO thumbnail creation & GPU-ready bitmap preparation
    /// on a background worker thread, falling back cleanly to `ImageIO` `CGImage` if
    /// `byPreparingForDisplay()` returns `nil` (grayscale / indexed / special color profiles).
    private nonisolated static func downsampleAndDecode(data: Data, maxPixelSize: Int) async -> CGImage? {
        let sourceOpts: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOpts as CFDictionary) else {
            return nil
        }

        var effectiveMax = max(128, maxPixelSize)
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let nativeW = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let nativeH = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            let nativeMax = max(nativeW, nativeH)
            if nativeMax > 0 {
                effectiveMax = max(1, min(effectiveMax, nativeMax))
            }
        }

        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: effectiveMax
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
            return nil
        }
        #if canImport(UIKit)
        if let displayReady = await UIImage(cgImage: decoded).byPreparingForDisplay()?.cgImage {
            return displayReady
        }
        #endif
        return decoded
    }
}

extension ArtworkPipeline {
    internal static nonisolated var imageCacheDirectoryURL: URL {
        ArtworkDiskCache.imageCacheDirectoryURL
    }

    public nonisolated static func diskUsageBytesAsync() async -> Int64 {
        await ArtworkDiskCache.diskUsageBytesAsync()
    }

    internal nonisolated static func diskFileURL(for url: URL) -> URL {
        ArtworkDiskCache.diskFileURL(for: url)
    }

    internal nonisolated static func trimDiskCacheSynchronously(maxBytes: Int64) {
        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: maxBytes)
    }
}
