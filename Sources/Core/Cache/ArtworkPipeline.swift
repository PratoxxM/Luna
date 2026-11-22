import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

public enum ArtworkLoadPriority: Sendable {
    case interactive
    case prefetch
}

private final class CGImageBox: NSObject, @unchecked Sendable {
    let image: CGImage
    let byteCost: Int

    init(_ image: CGImage) {
        self.image = image
        self.byteCost = max(1, image.bytesPerRow * image.height)
    }
}

private struct WeakImageBox: @unchecked Sendable {
    weak var box: CGImageBox?
}

internal final class ThreadSafeImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImageBox>()
    private let subjectBoxes = Mutex<[String: WeakImageBox]>([:])

    init(totalCostLimit: Int, countLimit: Int = 420) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func image(forKey key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func bestImage(forSubjectKey subjectKey: String) -> CGImage? {
        subjectBoxes.withLock { map in
            guard let entry = map[subjectKey] else { return nil }
            guard let live = entry.box else {
                map.removeValue(forKey: subjectKey)
                return nil
            }
            return live.image
        }
    }

    func insert(_ image: CGImage, forKey key: String, subjectKey: String? = nil) {
        let box = CGImageBox(image)
        cache.setObject(box, forKey: key as NSString, cost: box.byteCost)
        guard let subjectKey else { return }
        subjectBoxes.withLock { map in
            if map.count >= 1024 {
                map = map.filter { $0.value.box != nil }
            }
            let existingWidth = map[subjectKey]?.box?.image.width ?? 0
            if existingWidth <= image.width {
                map[subjectKey] = WeakImageBox(box: box)
            }
        }
    }

    func removeAll() {
        cache.removeAllObjects()
        subjectBoxes.withLock { $0.removeAll() }
    }
}

private final class DiskTouchTracker: Sendable {
    private let lastTouchByKey = Mutex<[String: TimeInterval]>([:])

    func shouldTouchAndRecord(_ key: String, now: TimeInterval) -> Bool {
        lastTouchByKey.withLock { map in
            if let prev = map[key], now - prev <= 3600 {
                return false
            }
            if map.count >= 1024 {
                map.removeAll(keepingCapacity: true)
            }
            map[key] = now
            return true
        }
    }

    func recordWrite(_ key: String, now: TimeInterval) {
        lastTouchByKey.withLock { map in
            if map.count >= 1024 {
                map.removeAll(keepingCapacity: true)
            }
            map[key] = now
        }
    }

    func removeAll() {
        lastTouchByKey.withLock { $0.removeAll() }
    }
}

/// Off-main-thread WebP/JPEG/PNG artwork loader, GPU-ready bitmap cache, and adaptive NVMe disk cache.
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    private struct DecodeWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private nonisolated let ramCache = ThreadSafeImageMemoryCache(
        totalCostLimit: DeviceMemoryProfile.current.artworkMemoryBytes,
        countLimit: DeviceMemoryProfile.current.artworkMemoryCountLimit
    )
    private nonisolated let diskTouchTracker = DiskTouchTracker()
    private nonisolated static let hexChars: [UInt8] = Array("0123456789abcdef".utf8)
    private nonisolated let inflightImages = InflightTaskCoalescer<String, CGImage?>()
    private nonisolated let inflightRawFetches = InflightTaskCoalescer<String, Data?>()
    private nonisolated let isPlaybackActiveFlag = Mutex(false)
    private nonisolated let activePrefetchTasks = Mutex<[UUID: Task<Void, Never>]>([:])

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
        }
    }

    private static nonisolated var imageCacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("img", isDirectory: true)
    }

    public nonisolated static func rawIdentity(for url: URL) -> String {
        let pathPart: String
        if let query = url.query, !query.isEmpty {
            pathPart = "\(url.path)?\(query)"
        } else {
            pathPart = url.path
        }
        if pathPart.hasPrefix("/api/tv/v1") {
            return pathPart
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return pathPart }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)\(pathPart)"
        }
        return "\(scheme)://\(host)\(pathPart)"
    }

    /// Size-agnostic subject identity bridging TMDB `/t/p/w1280/...` <-> `/t/p/original/...`
    /// and query-width `/api/tv/v1/artwork?...&w=1280` <-> `...&w=3840` for instant progressive 4K upgrades.
    public nonisolated static func canonicalSubjectIdentity(for url: URL) -> String {
        let segments = url.path.components(separatedBy: "/")
        if let pIdx = segments.firstIndex(of: "p"),
           pIdx >= 1,
           segments[pIdx - 1] == "t",
           pIdx + 2 < segments.count {
            let tail = segments[(pIdx + 2)...].joined(separator: "/")
            return "tmdb:/\(tail)"
        }
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = comps.queryItems,
           !items.isEmpty {
            let filtered = items.filter { item in
                let lower = item.name.lowercased()
                return lower != "w" && lower != "width"
            }
            comps.queryItems = filtered.isEmpty ? nil : filtered
            if let stripped = comps.url {
                return rawIdentity(for: stripped)
            }
        }
        return rawIdentity(for: url)
    }

    public nonisolated static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        "\(rawIdentity(for: url))#px\(maxPixelSize)"
    }

    public nonisolated func memoryCachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        return ramCache.image(forKey: key)
    }

    private nonisolated static let candidateCachedPixelSizes: [Int] = [
        3840, 1920, 1280, 1120, 1040, 960, 900, 896, 800, 780, 750, 720, 640, 480, 220,
    ]

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
                guard await self.acquireDecodePermit(priority: priority) else {
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
        let targetPixelSize = isBackdrop ? 1280 : 900
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
    /// (4K Dolby Vision Profile 7 FEL / AV1) frame pools allocate when headroom is tight.
    public nonisolated func enterPlaybackMemoryMode(isHeavySoftwareStream: Bool) {
        isPlaybackActiveFlag.withLock { $0 = true }
        cancelAllPrefetchTasks()

        let profile = DeviceMemoryProfile.current
        let available = DeviceHardwareCapabilities.availableMemoryBytes()
        let shouldShed = available < profile.playbackMemoryShedFloorBytes
            || (isHeavySoftwareStream && profile.tier == .standard)
        if shouldShed {
            ramCache.removeAll()
            BlurHashDecoder.clearCache()
        }
    }

    public nonisolated func exitPlaybackMemoryMode() {
        isPlaybackActiveFlag.withLock { $0 = false }
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
                    let now = Date().timeIntervalSinceReferenceDate
                    if diskTouchTracker.shouldTouchAndRecord(rawKey, now: now) {
                        let path = diskFileURL.path
                        Task.detached(priority: .background) {
                            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
                        }
                    }
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
        try? FileManager.default.createDirectory(at: Self.imageCacheDirectoryURL, withIntermediateDirectories: true)
        didEnsureCacheDir = true
    }

    private func acquireDecodePermit(priority: ArtworkLoadPriority) async -> Bool {
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
                let waiter = DecodeWaiter(id: waiterID, continuation: continuation)
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

    public nonisolated static func diskUsageBytesAsync() async -> Int64 {
        await Task.detached(priority: .utility) {
            FileManager.allocatedDirectoryBytes(at: imageCacheDirectoryURL)
        }.value
    }

    private nonisolated static func diskFileURL(for url: URL) -> URL {
        let identity = rawIdentity(for: url)
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hexBytes = [UInt8](unsafeUninitializedCapacity: 64) { buffer, count in
            var idx = 0
            for byte in digest {
                buffer[idx] = hexChars[Int(byte >> 4)]
                buffer[idx + 1] = hexChars[Int(byte & 0x0F)]
                idx += 2
            }
            count = 64
        }
        let hex = String(decoding: hexBytes, as: UTF8.self)
        return imageCacheDirectoryURL.appendingPathComponent("\(hex).img")
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

        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(128, maxPixelSize)
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

    private nonisolated static func trimDiskCacheSynchronously(maxBytes: Int64) {
        let dir = imageCacheDirectoryURL
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        struct FileEntry {
            let url: URL
            let size: Int64
            let modifiedAt: Date
        }

        var entries: [FileEntry] = []
        var totalBytes: Int64 = 0
        for fileURL in urls {
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let size = Int64(vals.fileSize ?? 0)
            let mod = vals.contentModificationDate ?? Date.distantPast
            totalBytes += size
            entries.append(FileEntry(url: fileURL, size: size, modifiedAt: mod))
        }

        guard totalBytes > maxBytes else { return }
        let targetBytes = Int64(Double(maxBytes) * 0.80)
        entries.sort { $0.modifiedAt < $1.modifiedAt }

        for entry in entries {
            guard totalBytes > targetBytes else { break }
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                totalBytes -= entry.size
            }
        }
    }
}
