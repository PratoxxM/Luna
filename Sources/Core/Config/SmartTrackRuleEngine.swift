import Foundation
import AetherBridge

public struct SmartTrackDescriptor: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let codec: String
    public let language: String?
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isCommentary: Bool
    public let isExternal: Bool
    public let isDefault: Bool

    public init(
        id: Int,
        name: String = "",
        codec: String = "srt",
        language: String? = nil,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isCommentary: Bool = false,
        isExternal: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.codec = codec
        self.language = language
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isCommentary = isCommentary
        self.isExternal = isExternal
        self.isDefault = isDefault
    }

    public init(track: TrackInfo) {
        self.id = track.id
        self.name = track.name
        self.codec = track.codec
        self.language = track.language
        self.isForced = track.isForced
        self.isHearingImpaired = track.isHearingImpaired
        self.isCommentary = track.isCommentary
        self.isExternal = track.isExternal
        self.isDefault = track.isDefault
    }
}

/// Automatic language comfort rules:
/// - Rule A: Norwegian audio -> subtitles off (unless a Norwegian forced track exists).
/// - Rule B: Foreign audio -> best Norwegian subtitle (non-SDH preferred, text preferred over bitmap),
///   falling back to English if Norwegian is unavailable.
public enum SmartTrackRuleEngine {
    public enum Decision: Equatable, Sendable {
        case clearSubtitles
        case selectTrack(Int)
        case keepCurrent
    }

    nonisolated(unsafe) private static let negatedForcedRegex: NSRegularExpression = {
        // Guard against titles like "Non-Forced", "Not Forced", "Unforced", "Ikke tvungen".
        try! NSRegularExpression(
            pattern: #"\b(?:non[\s\-_]*forced|not[\s\-_]*forced|unforced|ikke[\s\-_]*tvungen)\b"#,
            options: []
        )
    }()

    nonisolated(unsafe) private static let forcedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b(?:forced|tvungen)\b"#, options: [])
    }()

    nonisolated(unsafe) private static let sdhWordRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:sdh|cc|closed[\s\-_]*captions?)\b"#,
            options: []
        )
    }()

    public static func evaluate(
        activeAudio: TrackInfo?,
        subtitleTracks: [TrackInfo]
    ) -> Decision {
        evaluate(
            activeAudio: activeAudio.map(SmartTrackDescriptor.init(track:)),
            subtitleTracks: subtitleTracks.map(SmartTrackDescriptor.init(track:))
        )
    }

    public static func evaluate(
        activeAudio: SmartTrackDescriptor?,
        subtitleTracks: [SmartTrackDescriptor]
    ) -> Decision {
        guard let activeAudio else { return .keepCurrent }
        let audioLang = normalizeLanguage(activeAudio.language, fallbackName: activeAudio.name)

        // Rule A: Norwegian dialogue -> turn off full subtitles, keep forced translations only
        if audioLang == "nob" {
            if let forcedNo = subtitleTracks.first(where: {
                isTrackForced($0) && normalizeLanguage($0.language, fallbackName: $0.name) == "nob"
            }) {
                return .selectTrack(forcedNo.id)
            }
            return .clearSubtitles
        }

        // Rule B: Foreign dialogue -> prefer Norwegian, fallback to English
        if let bestNo = pickBestSubtitle(forLanguage: "nob", in: subtitleTracks) {
            return .selectTrack(bestNo.id)
        }
        if let bestEn = pickBestSubtitle(forLanguage: "eng", in: subtitleTracks) {
            return .selectTrack(bestEn.id)
        }
        return .keepCurrent
    }

    public static func isTrackForced(_ track: TrackInfo) -> Bool {
        isTrackForced(SmartTrackDescriptor(track: track))
    }

    public static func isTrackForced(_ track: SmartTrackDescriptor) -> Bool {
        if track.isForced { return true }
        let lower = track.name.lowercased()
        guard !lower.isEmpty else { return false }
        let fullRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        if negatedForcedRegex.firstMatch(in: lower, options: [], range: fullRange) != nil {
            return false
        }
        return forcedRegex.firstMatch(in: lower, options: [], range: fullRange) != nil
    }

    public static func isNameSDH(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.isEmpty else { return false }
        if lower.contains("hearing") || lower.contains("hørsel") {
            return true
        }
        let fullRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return sdhWordRegex.firstMatch(in: lower, options: [], range: fullRange) != nil
    }

    public static func normalizeLanguage(_ rawCode: String?, fallbackName: String = "") -> String? {
        let code = (rawCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["no", "nb", "nn", "nor", "nob", "nno", "norwegian", "norsk", "bokmål", "nynorsk"].contains(code) {
            return "nob"
        }
        if ["en", "eng", "english", "engelsk"].contains(code) {
            return "eng"
        }
        if ["sv", "swe", "swedish", "svensk"].contains(code) {
            return "swe"
        }
        if ["da", "dan", "danish", "dansk"].contains(code) {
            return "dan"
        }

        let nameLower = fallbackName.lowercased()
        if nameLower.contains("norsk") || nameLower.contains("norwegian") || nameLower.contains("bokmål") || nameLower.contains("nynorsk") {
            return "nob"
        }
        if nameLower.contains("english") || nameLower.contains("engelsk") {
            return "eng"
        }
        return code.isEmpty ? nil : code
    }

    private static func pickBestSubtitle(forLanguage targetLang: String, in tracks: [SmartTrackDescriptor]) -> SmartTrackDescriptor? {
        let candidates = tracks.filter {
            normalizeLanguage($0.language, fallbackName: $0.name) == targetLang && !$0.isCommentary
        }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { a, b in
            scoreSubtitle(a) < scoreSubtitle(b)
        }
    }

    private static func scoreSubtitle(_ track: SmartTrackDescriptor) -> Int {
        var score = 0
        // Full dialogue subtitles strongly beat forced-only tracks for foreign audio
        if !isTrackForced(track) {
            score += 100
        }
        // Clean standard captions beat SDH/HI when both exist
        if !track.isHearingImpaired && !isNameSDH(track.name) {
            score += 40
        }
        // Crisp scalable text subtitles (.srt / ASS) slightly beat bitmap PGS when both exist
        let codecLower = track.codec.lowercased()
        let isBitmap = codecLower.contains("pgs") || codecLower.contains("dvd") || codecLower.contains("dvb")
        if !isBitmap {
            score += 18
        }
        if track.isExternal {
            score += 8
        }
        if track.isDefault {
            score += 4
        }
        return score
    }
}
