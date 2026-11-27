import Foundation

/// Pure-Swift MKV/ASS font attachment filtering, key normalization, and SHA-256 fingerprinting.
public enum EmbeddedFontNamePolicy: Sendable {
    private static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    private static let supportedMimeTypes: Set<String> = [
        "application/x-truetype-font",
        "application/vnd.ms-opentype",
        "application/font-sfnt",
        "application/x-font-ttf",
        "application/x-font-otf",
        "application/x-font-truetype",
        "application/font-truetype",
        "application/font-opentype",
        "application/x-font-ttc",
    ]

    public static func isSupportedFontAttachment(filename: String, mimeType: String) -> Bool {
        let ext = normalizedExtension(fromFilename: filename)
        if supportedExtensions.contains(ext) {
            return true
        }
        let cleanMime = normalizedMimeType(mimeType)
        if cleanMime.hasPrefix("font/") {
            return true
        }
        return supportedMimeTypes.contains(cleanMime)
    }

    public static func preferredFontExtension(filename: String, mimeType: String) -> String {
        let ext = normalizedExtension(fromFilename: filename)
        if supportedExtensions.contains(ext) {
            return ext
        }
        let cleanMime = normalizedMimeType(mimeType)
        if cleanMime.contains("otc") {
            return "otc"
        }
        if cleanMime.contains("ttc") || cleanMime.contains("collection") {
            return "ttc"
        }
        if cleanMime.contains("otf") || cleanMime.contains("opentype") {
            return "otf"
        }
        return "ttf"
    }

    public static func stripAssVerticalPrefix(_ rawFontName: String) -> String {
        var cleaned = rawFontName.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.count >= 2 &&
            ((cleaned.hasPrefix("\"") && cleaned.hasSuffix("\""))
                || (cleaned.hasPrefix("'") && cleaned.hasSuffix("'"))) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while cleaned.hasPrefix("@") {
            cleaned.removeFirst()
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedLookupKeys(for rawFontName: String) -> [String] {
        let stripped = stripAssVerticalPrefix(rawFontName)
        guard !stripped.isEmpty else { return [] }
        let primary = stripped.lowercased()
        var keys: [String] = [primary]

        let collapsed = primary.filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        if !collapsed.isEmpty && collapsed != primary {
            keys.append(collapsed)
        }
        return keys
    }

    public static func sha256Hex(for data: Data) -> String {
        let bytes = ArtworkDiskCache.sha256Bytes([UInt8](data))
        var hex = String()
        hex.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            hex.append(contentsOf: String(format: "%02x", byte))
        }
        return hex
    }

    private static func normalizedExtension(fromFilename filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).pathExtension.lowercased()
    }

    private static func normalizedMimeType(_ mimeType: String) -> String {
        let base = mimeType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
        return base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
