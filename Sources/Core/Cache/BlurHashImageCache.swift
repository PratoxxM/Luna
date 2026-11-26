import CoreGraphics
import Foundation

private enum BlurHashImageCacheStore {
    static let cache = ThreadSafeImageMemoryCache(totalCostLimit: 4 * 1024 * 1024)
    static let inflightDecodes = InflightTaskCoalescer<String, CGImage?>()
}

public extension BlurHashDecoder {
    static func cachedImage(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) -> CGImage? {
        guard let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        return BlurHashImageCacheStore.cache.image(forKey: makeCacheKey(raw, width: width, height: height, punch: punch))
    }

    static func clearCache() {
        BlurHashImageCacheStore.inflightDecodes.cancelAll()
        BlurHashImageCacheStore.cache.removeAll()
    }

    static func decodeAsync(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) async -> CGImage? {
        guard !Task.isCancelled,
              width > 0, height > 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        let cacheKey = makeCacheKey(raw, width: width, height: height, punch: punch)
        if let hit = BlurHashImageCacheStore.cache.image(forKey: cacheKey) {
            return hit
        }

        guard let outcome = await BlurHashImageCacheStore.inflightDecodes.coalesceNonThrowing(
            key: cacheKey,
            priority: .utility,
            operation: {
                guard !Task.isCancelled else { return nil }
                return decode(raw, width: width, height: height, punch: punch)
            }
        ) else {
            return nil
        }
        return outcome.value
    }

    static func decode(_ blurHash: String?, width: Int = 32, height: Int = 18, punch: Float = 1.0) -> CGImage? {
        guard width > 0, height > 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }
        let cacheKey = makeCacheKey(raw, width: width, height: height, punch: punch)
        if let hit = BlurHashImageCacheStore.cache.image(forKey: cacheKey) {
            return hit
        }
        guard let decoded = decodePixels(raw, width: width, height: height, punch: punch) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(decoded.rgbaBytes) as CFData),
              let cgImage = CGImage(
                  width: decoded.width,
                  height: decoded.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: decoded.width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        BlurHashImageCacheStore.cache.insert(cgImage, forKey: cacheKey)
        return cgImage
    }
}
