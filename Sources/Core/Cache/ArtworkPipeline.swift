import Foundation
import CryptoKit
import ImageIO
import CoreGraphics
import SwiftUI

private final class CGImageBox: NSObject {
    let image: CGImage
    let byteCost: Int

    init(_ image: CGImage) {
        self.image = image
        self.byteCost = max(1, image.bytesPerRow * image.height)
    }
}

private final class ThreadSafeImageMemoryCache: @unchecked Sendable {
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

/// Fast pure-Swift BlurHash decoder producing tiny 32x32 smooth placeholders off or on demand.
public enum BlurHashDecoder {
    private static let cache = ThreadSafeImageMemoryCache(totalCostLimit: 4 * 1024 * 1024)

    private static let alphabet: [Character: Int] = {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
        var map: [Character: Int] = [:]
        for (idx, ch) in chars.enumerated() {
            map[ch] = idx
        }
        return map
    }()

    private static func makeCacheKey(_ raw: String, width: Int, height: Int, punch: Float) -> String {
        let roundedPunch = Int((punch * 100).rounded())
        return "\(raw)#\(width)x\(height)#p\(roundedPunch)"
    }

    public static func cachedImage(_ blurHash: String?, width: Int = 32, height: Int = 24, punch: Float = 1.0) -> CGImage? {
        guard let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        return cache.image(forKey: makeCacheKey(raw, width: width, height: height, punch: punch))
    }

    public static func decodeAsync(_ blurHash: String?, width: Int = 32, height: Int = 24, punch: Float = 1.0) async -> CGImage? {
        if let hit = cachedImage(blurHash, width: width, height: height, punch: punch) {
            return hit
        }
        guard let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        return await Task.detached(priority: .utility) {
            decode(raw, width: width, height: height, punch: punch)
        }.value
    }

    public static func decode(_ blurHash: String?, width: Int = 32, height: Int = 24, punch: Float = 1.0) -> CGImage? {
        guard width > 0, height > 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        let cacheKey = makeCacheKey(raw, width: width, height: height, punch: punch)
        if let hit = cache.image(forKey: cacheKey) {
            return hit
        }

        let chars = Array(raw)
        guard let sizeFlag = decode83(chars, from: 0, to: 1) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        let expectedLength = 4 + 2 * numX * numY
        guard chars.count == expectedLength else { return nil }

        guard let quantisedMaxValue = decode83(chars, from: 1, to: 2) else { return nil }
        let maximumValue = Float(quantisedMaxValue + 1) / 166.0

        var colors: [(Float, Float, Float)] = []
        colors.reserveCapacity(numX * numY)

        for i in 0..<(numX * numY) {
            if i == 0 {
                guard let val = decode83(chars, from: 2, to: 6) else { return nil }
                colors.append(decodeDC(val))
            } else {
                let start = 4 + i * 2
                guard let val = decode83(chars, from: start, to: start + 2) else { return nil }
                colors.append(decodeAC(val, maximumValue: maximumValue * punch))
            }
        }

        var cosX = [Float](repeating: 0, count: width * numX)
        for x in 0..<width {
            let fx = Float.pi * Float(x) / Float(width)
            let base = x * numX
            for i in 0..<numX {
                cosX[base + i] = cos(fx * Float(i))
            }
        }

        var cosY = [Float](repeating: 0, count: height * numY)
        for y in 0..<height {
            let fy = Float.pi * Float(y) / Float(height)
            let base = y * numY
            for j in 0..<numY {
                cosY[base + j] = cos(fy * Float(j))
            }
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let yBase = y * numY
            for x in 0..<width {
                let xBase = x * numX
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0

                for j in 0..<numY {
                    let basisY = cosY[yBase + j]
                    let rowOffset = j * numX
                    for i in 0..<numX {
                        let basis = cosX[xBase + i] * basisY
                        let color = colors[rowOffset + i]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }

                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(linearTosRGB(r))
                pixels[offset + 1] = UInt8(linearTosRGB(g))
                pixels[offset + 2] = UInt8(linearTosRGB(b))
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        cache.insert(cgImage, forKey: cacheKey)
        return cgImage
    }

    private static func decode83(_ chars: [Character], from: Int, to: Int) -> Int? {
        var value = 0
        for idx in from..<to {
            guard let digit = alphabet[chars[idx]] else { return nil }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        let intR = value >> 16
        let intG = (value >> 8) & 255
        let intB = value & 255
        return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
    }

    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        return (
            signPow((Float(quantR) - 9.0) / 9.0, 2.0) * maximumValue,
            signPow((Float(quantG) - 9.0) / 9.0, 2.0) * maximumValue,
            signPow((Float(quantB) - 9.0) / 9.0, 2.0) * maximumValue
        )
    }

    private static func signPow(_ val: Float, _ exp: Float) -> Float {
        copysign(pow(abs(val), exp), val)
    }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255.0
        if v <= 0.04045 {
            return v / 12.92
        }
        return pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearTosRGB(_ value: Float) -> Int {
        let v = max(0.0, min(1.0, value))
        let encoded: Float
        if v <= 0.0031308 {
            encoded = v * 12.92
        } else {
            encoded = 1.055 * pow(v, 1.0 / 2.4) - 0.055
        }
        return max(0, min(255, Int(encoded * 255.0 + 0.5)))
    }
}

/// Shared off-main-thread WebP/JPEG/PNG artwork loader & disk cache (`< 120 MB`).
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    private nonisolated let ramCache = ThreadSafeImageMemoryCache(totalCostLimit: 96 * 1024 * 1024)
    private var inflightTasks: [String: Task<CGImage?, Never>] = [:]
    private var inflightWaiters: [String: Set<UUID>] = [:]
    private var rawFetchTasks: [String: Task<Data?, Never>] = [:]
    private var rawFetchWaiters: [String: Int] = [:]
    private var writesSinceLastTrim: Int = 0

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

    public func loadImage(
        url: URL,
        maxPixelSize: Int,
        client: MediaOSClient?
    ) async -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let memHit = ramCache.image(forKey: key) {
            return memHit
        }

        let waiterID = UUID()
        inflightWaiters[key, default: []].insert(waiterID)

        let task: Task<CGImage?, Never>
        if let existing = inflightTasks[key] {
            task = existing
        } else {
            let rawKey = Self.rawIdentity(for: url)
            let ramCacheRef = self.ramCache
            let pipeline = self

            let created = Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard !Task.isCancelled,
                      let data = await pipeline.acquireRawData(url: url, rawKey: rawKey, client: client),
                      !Task.isCancelled,
                      let decoded = Self.downsampleAndDecode(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }
                ramCacheRef.insert(decoded, forKey: key)
                return decoded
            }
            inflightTasks[key] = created
            task = created
        }

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task {
                await self.removeWaiter(waiterID, forKey: key)
            }
        }

        removeWaiter(waiterID, forKey: key)
        if inflightWaiters[key]?.isEmpty ?? true {
            inflightTasks.removeValue(forKey: key)
            inflightWaiters.removeValue(forKey: key)
        }

        return result
    }

    private func acquireRawData(url: URL, rawKey: String, client: MediaOSClient?) async -> Data? {
        rawFetchWaiters[rawKey, default: 0] += 1

        let rawTask: Task<Data?, Never>
        if let existing = rawFetchTasks[rawKey] {
            rawTask = existing
        } else {
            let diskFileURL = Self.diskFileURL(for: url)
            let externalSession = MediaOSSessionPool.shared.externalArtworkSession()
            let pipeline = self

            let created = Task.detached(priority: .userInitiated) { () -> Data? in
                let fm = FileManager.default
                if let diskData = try? Data(contentsOf: diskFileURL), !diskData.isEmpty {
                    if let attrs = try? fm.attributesOfItem(atPath: diskFileURL.path),
                       let mtime = attrs[.modificationDate] as? Date {
                        if Date().timeIntervalSince(mtime) > 3600 {
                            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: diskFileURL.path)
                        }
                    } else {
                        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: diskFileURL.path)
                    }
                    return diskData
                }

                let fetchedData: Data?
                if let client {
                    fetchedData = (try? await client.fetchRawImageData(from: url))?.0
                } else {
                    fetchedData = (try? await externalSession.data(from: url))?.0
                }
                guard let data = fetchedData, !data.isEmpty else {
                    return nil
                }

                try? fm.createDirectory(at: Self.imageCacheDirectoryURL, withIntermediateDirectories: true)
                do {
                    try data.write(to: diskFileURL, options: .atomic)
                    await pipeline.recordDiskWriteCompleted()
                } catch {
                    // Best-effort disk cache write; still decode in-memory data
                }
                return data
            }
            rawFetchTasks[rawKey] = created
            rawTask = created
        }

        let data = await rawTask.value
        let remaining = (rawFetchWaiters[rawKey] ?? 1) - 1
        if remaining <= 0 {
            rawFetchWaiters.removeValue(forKey: rawKey)
            rawFetchTasks.removeValue(forKey: rawKey)
        } else {
            rawFetchWaiters[rawKey] = remaining
        }
        return data
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

    private func removeWaiter(_ waiterID: UUID, forKey key: String) {
        guard var set = inflightWaiters[key] else { return }
        set.remove(waiterID)
        if set.isEmpty {
            inflightWaiters.removeValue(forKey: key)
            if let running = inflightTasks.removeValue(forKey: key) {
                running.cancel()
            }
        } else {
            inflightWaiters[key] = set
        }
    }

    public func trimDiskCacheIfNeeded(maxBytes: Int64 = 115 * 1024 * 1024) {
        Task.detached(priority: .utility) {
            Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
        }
    }

    public func clearAll() {
        ramCache.removeAll()
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
        let hex = digest.map { String(format: "%02x", $0) }.joined()
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
