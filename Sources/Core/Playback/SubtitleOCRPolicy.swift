import Foundation

public struct SubtitleOCRLineInput: Sendable, Equatable {
    public let text: String
    public let confidence: Double
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(
        text: String,
        confidence: Double,
        minX: Double = 0,
        minY: Double = 0,
        width: Double = 0,
        height: Double = 0
    ) {
        self.text = text
        self.confidence = confidence
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

public struct SubtitleOCRRectInput: Sendable, Equatable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var midX: Double { minX + (width * 0.5) }
    public var midY: Double { minY + (height * 0.5) }
}

/// Pure-Swift Vision OCR promotion & intelligent `bitmap.cgImage` fallback policy.
///
/// Promotes clean dialogue cues (1–4 lines, high OCR confidence, centered bottom/top dialogue
/// zones) to crisp Lampelys vector subtitles, while falling back to the original PGS/VobSub
/// bitmap whenever OCR is empty, low-confidence, punctuation-only noise, or positioned as a
/// mid-screen/off-center typesetting sign.
public enum SubtitleOCRPolicy: Sendable {
    public static let minimumLineConfidence: Double = 0.45
    public static let minimumMeanConfidence: Double = 0.62
    public static let maximumLineCount: Int = 4
    public static let signMiddleBandMinY: Double = 0.24
    public static let signMiddleBandMaxY: Double = 0.64
    public static let maxDialogueCenterOffsetX: Double = 0.22

    public static func resolveTextCue(
        recognizedText: String?,
        lines: [SubtitleOCRLineInput],
        imagePosition: SubtitleOCRRectInput?,
        isOCRPrompted: Bool
    ) -> String? {
        guard isOCRPrompted else { return nil }

        guard let rawTrimmed = recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTrimmed.isEmpty else {
            return nil
        }

        if let pos = imagePosition,
           pos.minX.isFinite, pos.minY.isFinite,
           pos.width.isFinite, pos.height.isFinite,
           pos.width > 0, pos.height > 0 {
            if pos.midY > signMiddleBandMinY && pos.midY < signMiddleBandMaxY {
                return nil
            }
            if abs(pos.midX - 0.5) > maxDialogueCenterOffsetX {
                return nil
            }
        }

        guard !lines.isEmpty, lines.count <= maximumLineCount else {
            return nil
        }

        var confidenceSum = 0.0
        var cleanedLines: [String] = []
        cleanedLines.reserveCapacity(lines.count)

        for line in lines {
            guard line.confidence.isFinite, line.confidence >= minimumLineConfidence else {
                return nil
            }
            confidenceSum += line.confidence
            let trimmedLine = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLine.isEmpty {
                cleanedLines.append(trimmedLine)
            }
        }

        let meanConfidence = confidenceSum / Double(lines.count)
        guard meanConfidence >= minimumMeanConfidence,
              !cleanedLines.isEmpty else {
            return nil
        }

        let joined = cleanedLines.joined(separator: "\n")
        let hasReadableCharacter = joined.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        guard hasReadableCharacter else {
            return nil
        }

        return joined
    }
}
