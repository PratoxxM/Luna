import Foundation
#if canImport(AetherBridge)
import AetherBridge
#endif

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

    #if canImport(AetherBridge)
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
    #endif
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

    private static let negatedForcedRegex: NSRegularExpression = {
        // Guard against titles like "Non-Forced", "Not Forced", "Unforced", "Ikke tvungen".
        try! NSRegularExpression(
            pattern: #"\b(?:non[\s\-_]*forced|not[\s\-_]*forced|unforced|ikke[\s\-_]*tvungen)\b"#,
            options: []
        )
    }()

    private static let forcedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b(?:forced|tvungen)\b"#, options: [])
    }()

    private static let sdhWordRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:sdh|cc|closed[\s\-_]*captions?)\b"#,
            options: []
        )
    }()

    #if canImport(AetherBridge)
    public static func evaluate(
        activeAudio: TrackInfo?,
        subtitleTracks: [TrackInfo]
    ) -> Decision {
        evaluate(
            activeAudio: activeAudio.map(SmartTrackDescriptor.init(track:)),
            subtitleTracks: subtitleTracks.map(SmartTrackDescriptor.init(track:))
        )
    }
    #endif

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

        // Rule B: Foreign dialogue -> prefer full Norwegian, then full English, before forced-only tracks
        if let fullNo = pickBestSubtitle(forLanguage: "nob", in: subtitleTracks, onlyForced: false) {
            return .selectTrack(fullNo.id)
        }
        if let fullEn = pickBestSubtitle(forLanguage: "eng", in: subtitleTracks, onlyForced: false) {
            return .selectTrack(fullEn.id)
        }
        if let forcedNo = pickBestSubtitle(forLanguage: "nob", in: subtitleTracks, onlyForced: true) {
            return .selectTrack(forcedNo.id)
        }
        if let forcedEn = pickBestSubtitle(forLanguage: "eng", in: subtitleTracks, onlyForced: true) {
            return .selectTrack(forcedEn.id)
        }
        return .keepCurrent
    }

    #if canImport(AetherBridge)
    public static func selectBestSubtitleTrack(
        forLanguage rawLanguage: String?,
        in subtitleTracks: [TrackInfo]
    ) -> TrackInfo? {
        guard !subtitleTracks.isEmpty else { return nil }
        let descriptors = subtitleTracks.map(SmartTrackDescriptor.init(track:))
        guard let selectedId = selectBestSubtitleID(forLanguage: rawLanguage, in: descriptors) else {
            return nil
        }
        return subtitleTracks.first(where: { $0.id == selectedId })
    }
    #endif

    public static func selectBestSubtitleID(
        forLanguage rawLanguage: String?,
        in subtitleTracks: [SmartTrackDescriptor]
    ) -> Int? {
        guard !subtitleTracks.isEmpty else { return nil }
        let targetLang = normalizeLanguage(rawLanguage) ?? "nob"
        if let preferred = pickBestSubtitle(forLanguage: targetLang, in: subtitleTracks, onlyForced: false)
            ?? pickBestSubtitle(forLanguage: targetLang, in: subtitleTracks) {
            return preferred.id
        }
        if targetLang != "nob",
           let norwegian = pickBestSubtitle(forLanguage: "nob", in: subtitleTracks, onlyForced: false)
            ?? pickBestSubtitle(forLanguage: "nob", in: subtitleTracks) {
            return norwegian.id
        }
        if targetLang != "eng",
           let english = pickBestSubtitle(forLanguage: "eng", in: subtitleTracks, onlyForced: false)
            ?? pickBestSubtitle(forLanguage: "eng", in: subtitleTracks) {
            return english.id
        }
        if let nonCommentary = subtitleTracks.first(where: { !$0.isCommentary }) {
            return nonCommentary.id
        }
        return subtitleTracks.first?.id
    }

    #if canImport(AetherBridge)
    public static func isTrackForced(_ track: TrackInfo) -> Bool {
        isTrackForced(SmartTrackDescriptor(track: track))
    }
    #endif

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

    private static let iso639Aliases: [String: String] = [
        "no": "nob", "nb": "nob", "nn": "nob", "nor": "nob", "nob": "nob", "nno": "nob",
        "en": "eng", "eng": "eng",
        "sv": "swe", "swe": "swe",
        "da": "dan", "dan": "dan",
        "fr": "fra", "fra": "fra", "fre": "fra",
        "de": "deu", "deu": "deu", "ger": "deu",
        "es": "spa", "spa": "spa",
        "it": "ita", "ita": "ita",
        "pt": "por", "por": "por",
        "nl": "nld", "nld": "nld", "dut": "nld",
        "ja": "jpn", "jpn": "jpn",
        "ko": "kor", "kor": "kor",
        "zh": "zho", "zho": "zho", "chi": "zho",
        "ru": "rus", "rus": "rus",
        "pl": "pol", "pol": "pol",
        "fi": "fin", "fin": "fin",
        "is": "isl", "isl": "isl", "ice": "isl",
        "ar": "ara", "ara": "ara",
        "hi": "hin", "hin": "hin",
        "tr": "tur", "tur": "tur",
        "el": "ell", "ell": "ell", "gre": "ell",
        "cs": "ces", "ces": "ces", "cze": "ces",
        "ro": "ron", "ron": "ron", "rum": "ron",
        "hu": "hun", "hun": "hun",
        "th": "tha", "tha": "tha",
        "vi": "vie", "vie": "vie",
        "id": "ind", "ind": "ind",
        "uk": "ukr", "ukr": "ukr",
        "he": "heb", "heb": "heb", "iw": "heb",
        "bg": "bul", "bul": "bul",
        "hr": "hrv", "hrv": "hrv",
        "sk": "slk", "slk": "slk", "slo": "slk",
        "sl": "slv", "slv": "slv",
        "sr": "srp", "srp": "srp",
        "et": "est", "est": "est",
        "lv": "lav", "lav": "lav",
        "lt": "lit", "lit": "lit",
        "fa": "fas", "fas": "fas", "per": "fas",
        "ms": "msa", "msa": "msa", "may": "msa",
        "ca": "cat", "cat": "cat",
        "eu": "eus", "eus": "eus", "baq": "eus",
        "gl": "glg", "glg": "glg",
        "ta": "tam", "tam": "tam",
        "te": "tel", "tel": "tel",
        "bn": "ben", "ben": "ben",
        "ur": "urd", "urd": "urd",
    ]

    public static func normalizeLanguage(_ rawCode: String?, fallbackName: String = "") -> String? {
        let code = (rawCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let primary = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code
        if ["norwegian", "norsk", "bokmål", "nynorsk"].contains(code) {
            return "nob"
        }
        if ["english", "engelsk"].contains(code) {
            return "eng"
        }
        if ["swedish", "svensk"].contains(code) {
            return "swe"
        }
        if ["danish", "dansk"].contains(code) {
            return "dan"
        }
        if let mapped = iso639Aliases[code] ?? iso639Aliases[primary] {
            return mapped
        }

        let nameLower = fallbackName.lowercased()
        if nameLower.contains("norsk") || nameLower.contains("norwegian") || nameLower.contains("bokmål") || nameLower.contains("nynorsk") {
            return "nob"
        }
        if nameLower.contains("english") || nameLower.contains("engelsk") {
            return "eng"
        }
        return primary.isEmpty ? nil : primary
    }

    private static func pickBestSubtitle(
        forLanguage targetLang: String,
        in tracks: [SmartTrackDescriptor],
        onlyForced: Bool? = nil
    ) -> SmartTrackDescriptor? {
        let candidates = tracks.filter { track in
            guard normalizeLanguage(track.language, fallbackName: track.name) == targetLang,
                  !track.isCommentary else {
                return false
            }
            if let onlyForced {
                return isTrackForced(track) == onlyForced
            }
            return true
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
