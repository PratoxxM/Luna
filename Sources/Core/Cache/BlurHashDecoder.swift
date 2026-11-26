#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

public struct BlurHashDecodedPixels: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgbaBytes: [UInt8]

    public init(width: Int, height: Int, rgbaBytes: [UInt8]) {
        self.width = width
        self.height = height
        self.rgbaBytes = rgbaBytes
    }
}

/// Fast pure-Swift BlurHash decoder producing tiny 32x18 smooth RGBA placeholders on demand.
public enum BlurHashDecoder: Sendable {
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

    public static let maxDecodeDimension = 512

    public static func makeCacheKey(_ raw: String, width: Int, height: Int, punch: Float) -> String {
        let safePunch = punch.isFinite ? max(0, min(10, punch)) : 1.0
        let roundedPunch = Int((safePunch * 100).rounded())
        return "\(raw)#\(width)x\(height)#p\(roundedPunch)"
    }

    public static func decodePixels(
        _ blurHash: String?,
        width: Int = 32,
        height: Int = 18,
        punch: Float = 1.0
    ) -> BlurHashDecodedPixels? {
        guard width > 0, width <= maxDecodeDimension,
              height > 0, height <= maxDecodeDimension,
              punch.isFinite, punch >= 0,
              let raw = blurHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 6 else {
            return nil
        }

        let bytes = Array(raw.utf8)
        guard bytes.count >= 6, let sizeFlag = decode83(bytes, from: 0, to: 1) else { return nil }
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        let expectedLength = 4 + 2 * numX * numY
        guard bytes.count == expectedLength else { return nil }

        guard let quantisedMaxValue = decode83(bytes, from: 1, to: 2) else { return nil }
        let maximumValue = Float(quantisedMaxValue + 1) / 166.0

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

        return BlurHashDecodedPixels(width: width, height: height, rgbaBytes: pixels)
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
