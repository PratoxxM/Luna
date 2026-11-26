#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import Synchronization

#if canImport(CoreGraphics)
internal final class ThreadSafeImageMemoryCache: Sendable {
    private struct Entry: Sendable {
        let image: CGImage
        let cost: Int
        let subjectKey: String?
        var accessTick: UInt64
    }

    private struct State: Sendable {
        var entries: [String: Entry] = [:]
        var subjectBest: [String: (key: String, width: Int)] = [:]
        var totalCost: Int = 0
        var tick: UInt64 = 0
        var totalCostLimit: Int
        var countLimit: Int
    }

    private let state: Mutex<State>

    init(totalCostLimit: Int, countLimit: Int = 420) {
        self.state = Mutex(State(
            totalCostLimit: max(0, totalCostLimit),
            countLimit: max(0, countLimit)
        ))
    }

    var totalCostLimit: Int {
        get { state.withLock { $0.totalCostLimit } }
        set {
            state.withLock { s in
                s.totalCostLimit = max(0, newValue)
                Self.evictIfNeeded(&s)
            }
        }
    }

    func object(forKey key: String) -> CGImage? {
        image(forKey: key)
    }

    func setObject(_ image: CGImage, forKey key: String, cost: Int? = nil, subjectKey: String? = nil) {
        let resolvedCost = cost ?? max(1, image.bytesPerRow * image.height)
        state.withLock { s in
            s.tick &+= 1
            if let old = s.entries.removeValue(forKey: key) {
                s.totalCost = max(0, s.totalCost - old.cost)
            }
            let entry = Entry(
                image: image,
                cost: max(1, resolvedCost),
                subjectKey: subjectKey,
                accessTick: s.tick
            )
            s.entries[key] = entry
            s.totalCost += entry.cost
            if let subjectKey {
                let existingWidth = s.subjectBest[subjectKey]?.width ?? 0
                if existingWidth <= image.width {
                    s.subjectBest[subjectKey] = (key: key, width: image.width)
                }
            }
            Self.evictIfNeeded(&s)
        }
    }

    func image(forKey key: String) -> CGImage? {
        state.withLock { s in
            guard var entry = s.entries[key] else { return nil }
            s.tick &+= 1
            entry.accessTick = s.tick
            s.entries[key] = entry
            return entry.image
        }
    }

    func bestImage(forSubjectKey subjectKey: String) -> CGImage? {
        state.withLock { s in
            guard let best = s.subjectBest[subjectKey] else { return nil }
            guard var entry = s.entries[best.key] else {
                s.subjectBest.removeValue(forKey: subjectKey)
                return nil
            }
            s.tick &+= 1
            entry.accessTick = s.tick
            s.entries[best.key] = entry
            return entry.image
        }
    }

    func insert(_ image: CGImage, forKey key: String, subjectKey: String? = nil) {
        setObject(image, forKey: key, cost: max(1, image.bytesPerRow * image.height), subjectKey: subjectKey)
    }

    func removeAll() {
        state.withLock { s in
            s.entries.removeAll()
            s.subjectBest.removeAll()
            s.totalCost = 0
        }
    }

    private static func evictIfNeeded(_ s: inout State) {
        while (s.totalCostLimit > 0 && s.totalCost > s.totalCostLimit)
            || (s.countLimit > 0 && s.entries.count > s.countLimit) {
            guard let victimKey = s.entries.min(by: { $0.value.accessTick < $1.value.accessTick })?.key,
                  let removed = s.entries.removeValue(forKey: victimKey) else {
                break
            }
            s.totalCost = max(0, s.totalCost - removed.cost)
            if let subjectKey = removed.subjectKey, s.subjectBest[subjectKey]?.key == victimKey {
                s.subjectBest.removeValue(forKey: subjectKey)
            }
        }
    }
}
#endif

public final class DiskTouchTracker: Sendable {
    private let lastTouchByKey = Mutex<[String: TimeInterval]>([:])

    public init() {}

    public func shouldTouchAndRecord(_ key: String, now: TimeInterval) -> Bool {
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

    public func recordWrite(_ key: String, now: TimeInterval) {
        lastTouchByKey.withLock { map in
            if map.count >= 1024 {
                map.removeAll(keepingCapacity: true)
            }
            map[key] = now
        }
    }

    public func removeAll() {
        lastTouchByKey.withLock { $0.removeAll() }
    }
}

public enum ArtworkDiskCache: Sendable {
    private static let hexChars: [UInt8] = Array("0123456789abcdef".utf8)
    private static let migrationAttempted = Mutex(false)

    public static var imageCacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Luna", isDirectory: true)
            .appendingPathComponent("img", isDirectory: true)
    }

    public static func legacyImageCacheDirectoryURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("img", isDirectory: true)
    }

    public static func migrateLegacyCacheDirectoryIfNeeded(fileManager: FileManager = .default) {
        let shouldCheck = migrationAttempted.withLock { done -> Bool in
            if done { return false }
            done = true
            return true
        }
        guard shouldCheck else { return }
        let legacy = legacyImageCacheDirectoryURL(fileManager: fileManager)
        let current = imageCacheDirectoryURL
        migrateLegacyDirectory(from: legacy, to: current, fileManager: fileManager)
    }

    internal static func migrateLegacyDirectory(
        from legacy: URL,
        to current: URL,
        fileManager: FileManager = .default
    ) {
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        if !fileManager.fileExists(atPath: current.path) {
            try? fileManager.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.moveItem(at: legacy, to: current)
        } else {
            try? fileManager.removeItem(at: legacy)
        }
    }

    public static func diskUsageBytesAsync() async -> Int64 {
        migrateLegacyCacheDirectoryIfNeeded()
        let dir = imageCacheDirectoryURL
        return await Task.detached(priority: .utility) {
            FileManager.allocatedDirectoryBytes(at: dir)
        }.value
    }

    public static func diskFileURL(for url: URL, directoryURL: URL? = nil) -> URL {
        let identity = ArtworkSubjectKey.rawIdentity(for: url)
        let digest = sha256Bytes(Array(identity.utf8))
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
        return (directoryURL ?? imageCacheDirectoryURL).appendingPathComponent("\(hex).img")
    }

    @discardableResult
    public static func touchDiskFileIfNeeded(
        at fileURL: URL,
        key: String,
        tracker: DiskTouchTracker,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Bool {
        guard tracker.shouldTouchAndRecord(key, now: now.timeIntervalSinceReferenceDate) else {
            return false
        }
        do {
            try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    public static func trimDiskCacheSynchronously(
        maxBytes: Int64,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let dir = directoryURL ?? imageCacheDirectoryURL
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
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
            if (try? fileManager.removeItem(at: entry.url)) != nil {
                totalBytes -= entry.size
            }
        }
    }

    internal static func sha256Bytes(_ input: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(input)))
        #else
        return pureSwiftSHA256(input)
        #endif
    }

    private static let sha256K: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    internal static func pureSwiftSHA256(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var padded = message
        let bitLen = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 {
            padded.append(0x00)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLen >> shift) & 0xff))
        }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
            (x >> n) | (x << (32 - n))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            for i in 0..<16 {
                let b = chunkStart + i * 4
                w[i] = (UInt32(padded[b]) << 24)
                    | (UInt32(padded[b + 1]) << 16)
                    | (UInt32(padded[b + 2]) << 8)
                    | UInt32(padded[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = hh &+ s1 &+ ch &+ sha256K[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }

        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }
}
