import Foundation
import AetherBridge

public enum TvChapterKind: String, Codable, Equatable, Sendable {
    case intro
    case recap
    case credits
    case chapter

    public var badgeLabel: String? {
        switch self {
        case .intro: return "Intro"
        case .recap: return "Sammendrag"
        case .credits: return "Rulletekst"
        case .chapter: return nil
        }
    }

    private static let recapRegex = try? NSRegularExpression(
        pattern: #"\b(?:recap|previously|tidligere|sammendrag)\b"#,
        options: .caseInsensitive
    )
    private static let introPrefixRegex = try? NSRegularExpression(
        pattern: #"^(?:intro|opening|op|main\s*title|title\s*sequence|åpning|vignett)\b"#,
        options: .caseInsensitive
    )
    private static let introPhraseRegex = try? NSRegularExpression(
        pattern: #"\b(?:opening\s*credits|intro\s*credits|theme\s*song)\b"#,
        options: .caseInsensitive
    )
    private static let unconditionalCreditsRegex = try? NSRegularExpression(
        pattern: #"\b(?:end\s*credits|closing\s*credits|outro|rulletekst)\b"#,
        options: .caseInsensitive
    )
    private static let lateCreditsRegex = try? NSRegularExpression(
        pattern: #"\b(?:credits|slutt)\b"#,
        options: .caseInsensitive
    )
    private static let animeEndingTitleRegex = try? NSRegularExpression(
        pattern: #"^(?:ed|ending)(?:\s*\d+[a-z]?)?$"#,
        options: .caseInsensitive
    )

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    public static func classify(
        title rawTitle: String,
        startSeconds: Double,
        durationSeconds: Double = 0
    ) -> TvChapterKind {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .chapter }

        if matches(recapRegex, in: trimmed) {
            return .recap
        }
        if matches(introPrefixRegex, in: trimmed) || matches(introPhraseRegex, in: trimmed) {
            return .intro
        }
        if matches(unconditionalCreditsRegex, in: trimmed) {
            return .credits
        }
        let isInLateWindow = durationSeconds <= 0 || startSeconds >= durationSeconds * 0.72
        if isInLateWindow && (matches(lateCreditsRegex, in: trimmed) || matches(animeEndingTitleRegex, in: trimmed)) {
            return .credits
        }
        return .chapter
    }
}

public struct TvProbeChapter: Codable, Identifiable, Equatable, Sendable {
    public let index: Int?
    public let idString: String
    public let title: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let kind: String?

    public var id: String { idString }

    enum CodingKeys: String, CodingKey {
        case index
        case id
        case title
        case name
        case startSeconds
        case endSeconds
        case durationSeconds
        case kind
    }

    public init(
        index: Int?,
        idString: String,
        title: String,
        startSeconds: Double,
        endSeconds: Double,
        kind: String?
    ) {
        self.index = index
        self.idString = idString
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedIndex = try c.decodeIfPresent(Int.self, forKey: .index)
        self.index = decodedIndex

        if let strId = try? c.decodeIfPresent(String.self, forKey: .id), !strId.isEmpty {
            self.idString = strId
        } else if let intId = try? c.decodeIfPresent(Int.self, forKey: .id) {
            self.idString = String(intId)
        } else {
            self.idString = "ch-\(decodedIndex ?? 0)"
        }

        let t = (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
            ?? "Kapittel \((decodedIndex ?? 0) + 1)"
        self.title = t

        let start = (try? c.decodeIfPresent(Double.self, forKey: .startSeconds)) ?? 0
        self.startSeconds = start
        if let end = try? c.decodeIfPresent(Double.self, forKey: .endSeconds), end > start {
            self.endSeconds = end
        } else if let dur = try? c.decodeIfPresent(Double.self, forKey: .durationSeconds), dur > 0 {
            self.endSeconds = start + dur
        } else {
            self.endSeconds = start + 1
        }
        self.kind = try? c.decodeIfPresent(String.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(index, forKey: .index)
        try c.encode(idString, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(startSeconds, forKey: .startSeconds)
        try c.encode(endSeconds, forKey: .endSeconds)
        try c.encodeIfPresent(kind, forKey: .kind)
    }
}

public struct PlaybackChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let index: Int
    public let title: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let kind: TvChapterKind

    public var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    public init(
        id: String,
        index: Int,
        title: String,
        startSeconds: Double,
        endSeconds: Double,
        kind: TvChapterKind
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.kind = kind
    }

    public static func merge(
        probeChapters: [TvProbeChapter],
        engineChapters: [ChapterInfo],
        mediaDuration: Double
    ) -> [PlaybackChapter] {
        // Prefer live container chapters from AetherEngine when available, enriched with probe kind
        if !engineChapters.isEmpty {
            return engineChapters.enumerated().map { idx, ch in
                let start = max(0, ch.startSeconds)
                let end: Double
                if ch.durationSeconds > 0 {
                    end = start + ch.durationSeconds
                } else if idx + 1 < engineChapters.count {
                    end = max(start + 1, engineChapters[idx + 1].startSeconds)
                } else {
                    end = max(start + 1, mediaDuration)
                }

                let matchedProbe = probeChapters.first { abs($0.startSeconds - start) < 1.5 }
                let resolvedKind: TvChapterKind
                if let rawKind = matchedProbe?.kind, let parsed = TvChapterKind(rawValue: rawKind) {
                    resolvedKind = parsed
                } else {
                    resolvedKind = TvChapterKind.classify(
                        title: ch.name,
                        startSeconds: start,
                        durationSeconds: mediaDuration
                    )
                }

                let cleanTitle = ch.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return PlaybackChapter(
                    id: "eng-\(ch.id)-\(idx)",
                    index: idx,
                    title: cleanTitle.isEmpty ? (matchedProbe?.title ?? "Kapittel \(idx + 1)") : cleanTitle,
                    startSeconds: start,
                    endSeconds: end,
                    kind: resolvedKind
                )
            }
        }

        let sortedProbes = probeChapters.sorted { a, b in
            if a.startSeconds != b.startSeconds {
                return a.startSeconds < b.startSeconds
            }
            return (a.index ?? 0) < (b.index ?? 0)
        }
        return sortedProbes.enumerated().map { idx, ch in
            let start = max(0, ch.startSeconds)
            let rawEnd = max(start + 1, ch.endSeconds)
            let end = mediaDuration > start ? min(rawEnd, mediaDuration) : rawEnd
            let parsedKind = ch.kind.flatMap(TvChapterKind.init(rawValue:))
                ?? TvChapterKind.classify(title: ch.title, startSeconds: start, durationSeconds: mediaDuration)
            return PlaybackChapter(
                id: "prb-\(ch.idString)-\(idx)",
                index: ch.index ?? idx,
                title: ch.title,
                startSeconds: start,
                endSeconds: end,
                kind: parsedKind
            )
        }
    }
}
