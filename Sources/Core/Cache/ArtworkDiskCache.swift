import CoreGraphics
import CryptoKit
import Foundation
import Synchronization

internal final class CGImageBox: NSObject, @unchecked Sendable {
    let image: CGImage
    let byteCost: Int

    init(_ image: CGImage) {
        self.image = image
        self.byteCost = max(1, image.bytesPerRow * image.height)
    }
}

internal struct WeakImageBox: @unchecked Sendable {
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

internal final class DiskTouchTracker: Sendable {
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

extension ArtworkPipeline {
    private nonisolated static let hexChars: [UInt8] = Array("0123456789abcdef".utf8)

    internal static nonisolated var imageCacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("img", isDirectory: true)
    }

    public nonisolated static func diskUsageBytesAsync() async -> Int64 {
        await Task.detached(priority: .utility) {
            FileManager.allocatedDirectoryBytes(at: imageCacheDirectoryURL)
        }.value
    }

    internal nonisolated static func diskFileURL(for url: URL) -> URL {
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

    internal nonisolated static func trimDiskCacheSynchronously(maxBytes: Int64) {
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
