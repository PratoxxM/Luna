#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import Synchronization

public final class ThreadSafeLRUMemoryCache<Value: Sendable>: Sendable {
    private struct Slot: Sendable {
        var key: String
        var value: Value?
        var cost: Int
        var subjectKey: String?
        var qualityRank: Int
        var prev: Int
        var next: Int
    }

    private struct State: Sendable {
        var slots: [Slot] = []
        var freeIndices: [Int] = []
        var keyToIndex: [String: Int] = [:]
        var subjectSlots: [String: [Int]] = [:]
        var subjectBest: [String: Int] = [:]
        var head: Int = -1
        var tail: Int = -1
        var totalCost: Int = 0
        var totalCostLimit: Int
        var countLimit: Int

        mutating func unlink(_ idx: Int) {
            let prevIdx = slots[idx].prev
            let nextIdx = slots[idx].next
            if prevIdx != -1 {
                slots[prevIdx].next = nextIdx
            } else if head == idx {
                head = nextIdx
            }
            if nextIdx != -1 {
                slots[nextIdx].prev = prevIdx
            } else if tail == idx {
                tail = prevIdx
            }
            slots[idx].prev = -1
            slots[idx].next = -1
        }

        mutating func linkAtHead(_ idx: Int) {
            slots[idx].prev = -1
            slots[idx].next = head
            if head != -1 {
                slots[head].prev = idx
            }
            head = idx
            if tail == -1 {
                tail = idx
            }
        }

        mutating func moveToHead(_ idx: Int) {
            guard head != idx else { return }
            unlink(idx)
            linkAtHead(idx)
        }

        mutating func recomputeSubjectBest(for subjectKey: String, in list: [Int]) {
            var bestIdx = list[0]
            var bestRank = slots[bestIdx].qualityRank
            for candidate in list.dropFirst() {
                let rank = slots[candidate].qualityRank
                if rank >= bestRank {
                    bestRank = rank
                    bestIdx = candidate
                }
            }
            subjectBest[subjectKey] = bestIdx
        }

        mutating func removeSlotFromSubject(_ idx: Int, subjectKey: String) {
            if var list = subjectSlots[subjectKey] {
                list.removeAll { $0 == idx }
                if list.isEmpty {
                    subjectSlots.removeValue(forKey: subjectKey)
                    subjectBest.removeValue(forKey: subjectKey)
                } else {
                    subjectSlots[subjectKey] = list
                    if subjectBest[subjectKey] == idx {
                        recomputeSubjectBest(for: subjectKey, in: list)
                    }
                }
            } else if subjectBest[subjectKey] == idx {
                subjectBest.removeValue(forKey: subjectKey)
            }
        }

        mutating func registerSlotInSubject(_ idx: Int, subjectKey: String) {
            var list = subjectSlots[subjectKey] ?? []
            if !list.contains(idx) {
                list.append(idx)
                subjectSlots[subjectKey] = list
            }
            if let currentBestIdx = subjectBest[subjectKey] {
                if currentBestIdx == idx {
                    recomputeSubjectBest(for: subjectKey, in: list)
                } else if slots[idx].qualityRank >= slots[currentBestIdx].qualityRank {
                    subjectBest[subjectKey] = idx
                }
            } else {
                subjectBest[subjectKey] = idx
            }
        }

        mutating func removeSlot(at idx: Int) {
            let key = slots[idx].key
            let cost = slots[idx].cost
            let subjectKey = slots[idx].subjectKey
            unlink(idx)
            keyToIndex.removeValue(forKey: key)
            totalCost = max(0, totalCost - cost)
            if let subjectKey {
                removeSlotFromSubject(idx, subjectKey: subjectKey)
            }
            slots[idx] = Slot(
                key: "",
                value: nil,
                cost: 0,
                subjectKey: nil,
                qualityRank: 0,
                prev: -1,
                next: -1
            )
            freeIndices.append(idx)
        }
    }

    private let state: Mutex<State>

    public init(totalCostLimit: Int, countLimit: Int = 420) {
        self.state = Mutex(State(
            totalCostLimit: max(0, totalCostLimit),
            countLimit: max(0, countLimit)
        ))
    }

    public var totalCostLimit: Int {
        get { state.withLock { $0.totalCostLimit } }
        set {
            state.withLock { s in
                s.totalCostLimit = max(0, newValue)
                Self.evictIfNeeded(&s)
            }
        }
    }

    public var countLimit: Int {
        get { state.withLock { $0.countLimit } }
        set {
            state.withLock { s in
                s.countLimit = max(0, newValue)
                Self.evictIfNeeded(&s)
            }
        }
    }

    public var count: Int {
        state.withLock { $0.keyToIndex.count }
    }

    public var totalCost: Int {
        state.withLock { $0.totalCost }
    }

    public func object(forKey key: String) -> Value? {
        image(forKey: key)
    }

    public func image(forKey key: String) -> Value? {
        state.withLock { s in
            guard let idx = s.keyToIndex[key], let value = s.slots[idx].value else {
                return nil
            }
            s.moveToHead(idx)
            return value
        }
    }

    public func bestImage(forSubjectKey subjectKey: String) -> Value? {
        state.withLock { s in
            guard let bestIdx = s.subjectBest[subjectKey],
                  let value = s.slots[bestIdx].value else {
                return nil
            }
            s.moveToHead(bestIdx)
            return value
        }
    }

    public func insert(
        _ value: Value,
        forKey key: String,
        subjectKey: String? = nil,
        cost: Int,
        qualityRank: Int? = nil
    ) {
        let resolvedCost = max(1, cost)
        let resolvedRank = qualityRank ?? resolvedCost
        state.withLock { s in
            if s.totalCostLimit > 0 && resolvedCost > s.totalCostLimit {
                if let existingIdx = s.keyToIndex[key] {
                    s.removeSlot(at: existingIdx)
                }
                return
            }

            if let existingIdx = s.keyToIndex[key] {
                let oldCost = s.slots[existingIdx].cost
                let oldSubject = s.slots[existingIdx].subjectKey
                if let oldSubject, oldSubject != subjectKey {
                    s.removeSlotFromSubject(existingIdx, subjectKey: oldSubject)
                }
                s.totalCost = max(0, s.totalCost - oldCost) + resolvedCost
                s.slots[existingIdx].value = value
                s.slots[existingIdx].cost = resolvedCost
                s.slots[existingIdx].subjectKey = subjectKey
                s.slots[existingIdx].qualityRank = resolvedRank
                s.moveToHead(existingIdx)
                if let subjectKey {
                    s.registerSlotInSubject(existingIdx, subjectKey: subjectKey)
                }
            } else {
                let idx: Int
                if let reused = s.freeIndices.popLast() {
                    idx = reused
                    s.slots[idx] = Slot(
                        key: key,
                        value: value,
                        cost: resolvedCost,
                        subjectKey: subjectKey,
                        qualityRank: resolvedRank,
                        prev: -1,
                        next: -1
                    )
                } else {
                    idx = s.slots.count
                    s.slots.append(Slot(
                        key: key,
                        value: value,
                        cost: resolvedCost,
                        subjectKey: subjectKey,
                        qualityRank: resolvedRank,
                        prev: -1,
                        next: -1
                    ))
                }
                s.keyToIndex[key] = idx
                s.totalCost += resolvedCost
                s.linkAtHead(idx)
                if let subjectKey {
                    s.registerSlotInSubject(idx, subjectKey: subjectKey)
                }
            }
            Self.evictIfNeeded(&s)
        }
    }

    public func removeAll() {
        state.withLock { s in
            s.slots.removeAll()
            s.freeIndices.removeAll()
            s.keyToIndex.removeAll()
            s.subjectSlots.removeAll()
            s.subjectBest.removeAll()
            s.head = -1
            s.tail = -1
            s.totalCost = 0
        }
    }

    private static func evictIfNeeded(_ s: inout State) {
        while (s.totalCostLimit > 0 && s.totalCost > s.totalCostLimit)
            || (s.countLimit > 0 && s.keyToIndex.count > s.countLimit) {
            let victimIdx = s.tail
            guard victimIdx != -1 else { break }
            s.removeSlot(at: victimIdx)
        }
    }
}

#if canImport(CoreGraphics)
internal typealias ThreadSafeImageMemoryCache = ThreadSafeLRUMemoryCache<CGImage>

extension ThreadSafeLRUMemoryCache where Value == CGImage {
    func setObject(_ image: CGImage, forKey key: String, cost: Int? = nil, subjectKey: String? = nil) {
        let resolvedCost = cost ?? max(1, image.bytesPerRow * image.height)
        insert(image, forKey: key, subjectKey: subjectKey, cost: resolvedCost, qualityRank: image.width)
    }

    func insert(_ image: CGImage, forKey key: String, subjectKey: String? = nil) {
        let resolvedCost = max(1, image.bytesPerRow * image.height)
        insert(image, forKey: key, subjectKey: subjectKey, cost: resolvedCost, qualityRank: image.width)
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

    public static func prefetchArtworkURLs(
        in cards: [TvMediaCard],
        afterIndex index: Int,
        isBackdrop: Bool,
        window: Int,
        client: LunaCoreClient
    ) -> [URL] {
        guard index >= 0, index + 1 < cards.count, window > 0 else { return [] }
        let endIndex = min(cards.count, index + 1 + window)
        let target: LunaCoreClient.ArtworkTargetWidth = isBackdrop ? .landscape2x : .poster2x
        return cards[(index + 1)..<endIndex].compactMap { card in
            let path = isBackdrop ? card.preferredLandscapePath : card.preferredPosterPath
            return client.resolveArtworkURL(path, target: target)
        }
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
