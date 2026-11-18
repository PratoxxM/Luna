import Foundation
import CoreGraphics
import Synchronization

private struct InflightBlurHashDecode: Sendable {
    let id: UUID
    let task: Task<CGImage?, Never>
    var waiters: Set<UUID>
}

internal struct BlurHashDecodeMetrics: Equatable, Sendable {
    var cacheHits: Int = 0
    var coalescedWaiters: Int = 0
    var actualDecodes: Int = 0
}

/// Fast pure-Swift BlurHash decoder producing tiny 32x18 smooth placeholders off or on demand,
/// with Swift 6 `Mutex`-backed in-flight task deduplication across concurrent shelf cards.
public enum BlurHashDecoder {
    private static let cache = ThreadSafeImageMemoryCache(totalCostLimit: 4 * 1024 * 1024)
    private static let inflightDecodes = Mutex<[String: InflightBlurHashDecode]>([:])
    private static let metricsState = Mutex(BlurHashDecodeMetrics())

    internal static func metricsSnapshot() -> BlurHashDecodeMetrics {
        metricsState.withLock { $0 }
    }

    internal static func resetMetrics() {
        metricsState.withLock { $0 = BlurHashDecodeMetrics() }
    }

    private static let base83Table: [Int16] = {
        var table = [Int16](repeating: -1, count: 256)
        for (idx, byte) in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".utf8.enumerated() {
            table[Int(byte)] = Int16(idx)
        }
        return table
    }()

    private static let linearTosRGBTable: [UInt8] = {
        var lut = [UInt8](repeating: 0, count: 4097)
        for i in 0...4096 {
            let v = Float(i) / 4096.0
            let encoded: Float = v <= 0.0031308
                ? (v * 12.92)
                : (1.055 * pow(v, 1.0 / 2.4) - 0.055)
            lut[i] = UInt8(max(0, min(255, Int(encoded * 255.0 + 0.5))))
        }
        return lut
    }()

    private static func makeCacheKey(_ raw: String, width: Int, height: Int, punch: Float) -> String {
        let roundedPunch = Int((punch * 100).rounded())
        return "\(raw)#\(width)x\(height)#p\(roundedPunch)"
    }

    public static func cachedImage(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) -> CGImage? {
        guard let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        return cache.image(forKey: makeCacheKey(raw, width: width, height: height, punch: punch))
    }

    public static func clearCache() {
        let running = inflightDecodes.withLock { map in
            let tasks = map.values.map(\.task)
            map.removeAll()
            return tasks
        }
        for task in running {
            task.cancel()
        }
        cache.removeAll()
    }

    public static func decodeAsync(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) async -> CGImage? {
        guard width > 0, height > 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        let cacheKey = makeCacheKey(raw, width: width, height: height, punch: punch)
        if let hit = cache.image(forKey: cacheKey) {
            metricsState.withLock { $0.cacheHits += 1 }
            return hit
        }

        let waiterID = UUID()
        enum Lookup {
            case cached(CGImage)
            case joined(entryID: UUID, task: Task<CGImage?, Never>, coalesced: Bool)
        }

        let lookup: Lookup = inflightDecodes.withLock { map in
            if let hit = cache.image(forKey: cacheKey) {
                return .cached(hit)
            }
            if var existing = map[cacheKey] {
                existing.waiters.insert(waiterID)
                map[cacheKey] = existing
                return .joined(entryID: existing.id, task: existing.task, coalesced: true)
            }
            let entryID = UUID()
            let created = Task.detached(priority: .utility) { () -> CGImage? in
                defer {
                    inflightDecodes.withLock { current in
                        if current[cacheKey]?.id == entryID {
                            current.removeValue(forKey: cacheKey)
                        }
                    }
                }
                guard !Task.isCancelled else { return nil }
                return decode(raw, width: width, height: height, punch: punch)
            }
            map[cacheKey] = InflightBlurHashDecode(id: entryID, task: created, waiters: [waiterID])
            return .joined(entryID: entryID, task: created, coalesced: false)
        }

        switch lookup {
        case .cached(let hit):
            metricsState.withLock { $0.cacheHits += 1 }
            return hit
        case .joined(let entryID, let task, let coalesced):
            if coalesced {
                metricsState.withLock { $0.coalescedWaiters += 1 }
            }
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                releaseInflightWaiter(waiterID, forKey: cacheKey, entryID: entryID)
            }
            releaseInflightWaiter(waiterID, forKey: cacheKey, entryID: entryID)
            return Task.isCancelled ? nil : result
        }
    }

    private static func releaseInflightWaiter(_ waiterID: UUID, forKey cacheKey: String, entryID: UUID) {
        let taskToCancel: Task<CGImage?, Never>? = inflightDecodes.withLock { map in
            guard var entry = map[cacheKey], entry.id == entryID else { return nil }
            guard entry.waiters.remove(waiterID) != nil else { return nil }
            if entry.waiters.isEmpty {
                map.removeValue(forKey: cacheKey)
                return entry.task
            }
            map[cacheKey] = entry
            return nil
        }
        taskToCancel?.cancel()
    }

    public static func decode(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) -> CGImage? {
        guard width > 0, height > 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        let cacheKey = makeCacheKey(raw, width: width, height: height, punch: punch)
        if let hit = cache.image(forKey: cacheKey) {
            return hit
        }

        let bytes = Array(raw.utf8)
        guard let sizeFlag = decode83(bytes, from: 0, to: 1) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        let expectedLength = 4 + 2 * numX * numY
        guard bytes.count == expectedLength else { return nil }

        guard let quantisedMaxValue = decode83(bytes, from: 1, to: 2) else { return nil }
        let maximumValue = Float(quantisedMaxValue + 1) / 166.0

        metricsState.withLock { $0.actualDecodes += 1 }

        var colors: [(Float, Float, Float)] = []
        colors.reserveCapacity(numX * numY)

        for i in 0..<(numX * numY) {
            if i == 0 {
                guard let val = decode83(bytes, from: 2, to: 6) else { return nil }
                colors.append(decodeDC(val))
            } else {
                let start = 4 + i * 2
                guard let val = decode83(bytes, from: start, to: start + 2) else { return nil }
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
                pixels[offset] = linearTosRGB(r)
                pixels[offset + 1] = linearTosRGB(g)
                pixels[offset + 2] = linearTosRGB(b)
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

    private static func decode83(_ bytes: [UInt8], from: Int, to: Int) -> Int? {
        var value = 0
        for idx in from..<to {
            let digit = Int(base83Table[Int(bytes[idx])])
            guard digit >= 0 else { return nil }
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

    private static func linearTosRGB(_ value: Float) -> UInt8 {
        let v = max(0.0, min(1.0, value))
        return linearTosRGBTable[Int((v * 4096.0).rounded())]
    }
}
