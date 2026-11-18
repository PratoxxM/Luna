import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import Synchronization

private final class CGImageBox: NSObject {
    let image: CGImage
    let byteCost: Int

    init(_ image: CGImage) {
        self.image = image
        self.byteCost = max(1, image.bytesPerRow * image.height)
    }
}

internal final class ThreadSafeImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImageBox>()

    init(totalCostLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = 360
    }

    func image(forKey key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func insert(_ image: CGImage, forKey key: String) {
        let box = CGImageBox(image)
        cache.setObject(box, forKey: key as NSString, cost: box.byteCost)
    }

    func removeAll() {
        cache.removeAllObjects()
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

private struct InflightTaskEntry<Value: Sendable>: Sendable {
    let id: UUID
    let task: Task<Value?, Never>
    var waiters: Set<UUID>
}

/// Shared off-main-thread WebP/JPEG/PNG artwork loader & disk cache (`< 120 MB`).
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    private nonisolated let ramCache = ThreadSafeImageMemoryCache(totalCostLimit: 96 * 1024 * 1024)
    private nonisolated let diskTouchTracker = DiskTouchTracker()
    private nonisolated static let hexChars: [UInt8] = Array("0123456789abcdef".utf8)
    private nonisolated let inflightImages = Mutex<[String: InflightTaskEntry<CGImage>]>([:])
    private nonisolated let inflightRawFetches = Mutex<[String: InflightTaskEntry<Data>]>([:])
    private var writesSinceLastTrim: Int = 0
    private var didEnsureCacheDir: Bool = false

    private let maxConcurrentDecodes = 4
    private var activeDecodeCount: Int = 0
    private var decodeWaiters: [CheckedContinuation<Void, Never>] = []

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

    public nonisolated static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        "\(rawIdentity(for: url))#px\(maxPixelSize)"
    }

    public nonisolated func memoryCachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        return ramCache.image(forKey: key)
    }

    private nonisolated static let candidateCachedPixelSizes: [Int] = [
        1920, 960, 896, 800, 750, 720, 640, 480, 220,
    ]

    /// Looks up any already-decoded bitmap in RAM for `url` (checking `preferredMaxPixelSize` first,
    /// then standard hero/card/still pixel buckets) so player startup curtains can reuse already-rendered
    /// detail or shelf backdrops in `0 ms` without re-decoding.
    public nonisolated func anyMemoryCachedImage(
        for url: URL,
        preferredMaxPixelSize: Int
    ) -> (key: String, image: CGImage)? {
        let preferredKey = Self.cacheKey(for: url, maxPixelSize: preferredMaxPixelSize)
        if let exact = ramCache.image(forKey: preferredKey) {
            return (preferredKey, exact)
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
        ramCache.insert(image, forKey: Self.cacheKey(for: url, maxPixelSize: maxPixelSize))
    }

    public nonisolated func loadImage(
        url: URL,
        maxPixelSize: Int,
        client: LunaCoreClient?
    ) async -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let memHit = ramCache.image(forKey: key) {
            return memHit
        }

        let waiterID = UUID()
        enum Lookup {
            case cached(CGImage)
            case joined(entryID: UUID, task: Task<CGImage?, Never>)
        }

        let lookup: Lookup = inflightImages.withLock { map in
            if let memHit = ramCache.image(forKey: key) {
                return .cached(memHit)
            }
            if var existing = map[key] {
                existing.waiters.insert(waiterID)
                map[key] = existing
                return .joined(entryID: existing.id, task: existing.task)
            }
            let entryID = UUID()
            let rawKey = Self.rawIdentity(for: url)
            let ramCacheRef = self.ramCache
            let pipeline = self

            let created = Task.detached(priority: .userInitiated) { () -> CGImage? in
                defer {
                    pipeline.inflightImages.withLock { current in
                        if current[key]?.id == entryID {
                            current.removeValue(forKey: key)
                        }
                    }
                }
                guard !Task.isCancelled,
                      let data = await pipeline.acquireRawData(url: url, rawKey: rawKey, client: client),
                      !Task.isCancelled else {
                    return nil
                }
                await pipeline.acquireDecodePermit()
                let decoded: CGImage?
                if Task.isCancelled {
                    decoded = nil
                } else {
                    decoded = Self.downsampleAndDecode(data: data, maxPixelSize: maxPixelSize)
                }
                await pipeline.releaseDecodePermit()
                guard let decoded else { return nil }
                ramCacheRef.insert(decoded, forKey: key)
                return decoded
            }
            map[key] = InflightTaskEntry(id: entryID, task: created, waiters: [waiterID])
            return .joined(entryID: entryID, task: created)
        }

        switch lookup {
        case .cached(let memHit):
            return memHit
        case .joined(let entryID, let task):
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                Self.releaseWaiter(waiterID, key: key, entryID: entryID, in: self.inflightImages)
            }
            Self.releaseWaiter(waiterID, key: key, entryID: entryID, in: self.inflightImages)
            return result
        }
    }

    private nonisolated func acquireRawData(url: URL, rawKey: String, client: LunaCoreClient?) async -> Data? {
        let rawWaiterID = UUID()
        let (entryID, rawTask): (UUID, Task<Data?, Never>) = inflightRawFetches.withLock { map in
            if var existing = map[rawKey] {
                existing.waiters.insert(rawWaiterID)
                map[rawKey] = existing
                return (existing.id, existing.task)
            }
            let newID = UUID()
            let diskFileURL = Self.diskFileURL(for: url)
            let externalSession = LunaCoreSessionPool.shared.externalArtworkSession()
            let pipeline = self
            let diskTouchTracker = self.diskTouchTracker

            let created = Task.detached(priority: .userInitiated) { () -> Data? in
                defer {
                    pipeline.inflightRawFetches.withLock { current in
                        if current[rawKey]?.id == newID {
                            current.removeValue(forKey: rawKey)
                        }
                    }
                }
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

                await pipeline.ensureCacheDirectoryIfNeeded()
                do {
                    try data.write(to: diskFileURL, options: .atomic)
                    diskTouchTracker.recordWrite(rawKey, now: Date().timeIntervalSinceReferenceDate)
                    await pipeline.recordDiskWriteCompleted()
                } catch {
                    // Best-effort disk cache write; still decode in-memory data
                }
                return data
            }
            map[rawKey] = InflightTaskEntry(id: newID, task: created, waiters: [rawWaiterID])
            return (newID, created)
        }

        let data = await withTaskCancellationHandler {
            await rawTask.value
        } onCancel: {
            Self.releaseWaiter(rawWaiterID, key: rawKey, entryID: entryID, in: self.inflightRawFetches)
        }
        Self.releaseWaiter(rawWaiterID, key: rawKey, entryID: entryID, in: self.inflightRawFetches)
        return data
    }

    private nonisolated static func releaseWaiter<Value: Sendable>(
        _ waiterID: UUID,
        key: String,
        entryID: UUID,
        in mutex: borrowing Mutex<[String: InflightTaskEntry<Value>]>
    ) {
        let taskToCancel: Task<Value?, Never>? = mutex.withLock { map in
            guard var entry = map[key], entry.id == entryID else { return nil }
            guard entry.waiters.remove(waiterID) != nil else { return nil }
            if entry.waiters.isEmpty {
                map.removeValue(forKey: key)
                return entry.task
            }
            map[key] = entry
            return nil
        }
        taskToCancel?.cancel()
    }

    private func ensureCacheDirectoryIfNeeded() {
        guard !didEnsureCacheDir else { return }
        try? FileManager.default.createDirectory(at: Self.imageCacheDirectoryURL, withIntermediateDirectories: true)
        didEnsureCacheDir = true
    }

    private func acquireDecodePermit() async {
        if activeDecodeCount < maxConcurrentDecodes {
            activeDecodeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            decodeWaiters.append(continuation)
        }
    }

    private func releaseDecodePermit() {
        if !decodeWaiters.isEmpty {
            let next = decodeWaiters.removeFirst()
            next.resume()
        } else {
            activeDecodeCount = max(0, activeDecodeCount - 1)
        }
    }

    private func recordDiskWriteCompleted() {
        writesSinceLastTrim += 1
        if writesSinceLastTrim >= 28 {
            writesSinceLastTrim = 0
            Task.detached(priority: .utility) {
                Self.trimDiskCacheSynchronously(maxBytes: 115 * 1024 * 1024)
            }
        }
    }

    public func trimDiskCacheIfNeeded(maxBytes: Int64 = 115 * 1024 * 1024) {
        Task.detached(priority: .utility) {
            Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
        }
    }

    public func clearAll() {
        let imgTasks = inflightImages.withLock { map in
            let tasks = map.values.map(\.task)
            map.removeAll()
            return tasks
        }
        let rawTasks = inflightRawFetches.withLock { map in
            let tasks = map.values.map(\.task)
            map.removeAll()
            return tasks
        }
        for task in imgTasks { task.cancel() }
        for task in rawTasks { task.cancel() }

        ramCache.removeAll()
        BlurHashDecoder.clearCache()
        diskTouchTracker.removeAll()
        didEnsureCacheDir = false
        try? FileManager.default.removeItem(at: Self.imageCacheDirectoryURL)
    }

    public nonisolated static func diskUsageBytesAsync() async -> Int64 {
        await Task.detached(priority: .utility) {
            diskUsageBytes()
        }.value
    }

    public nonisolated static func diskUsageBytes() -> Int64 {
        let dir = imageCacheDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for url in urls {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
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

    /// Hardware-accelerated ImageIO thumbnail creation & immediate bitmap decompression
    /// on a background worker thread so `@MainActor` spends 0 ms decoding pixels.
    private nonisolated static func downsampleAndDecode(data: Data, maxPixelSize: Int) -> CGImage? {
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
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary)
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
