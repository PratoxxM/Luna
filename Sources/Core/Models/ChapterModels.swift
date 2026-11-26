import Foundation
#if canImport(AetherBridge)
import AetherBridge
#endif

public enum TvChapterKind: String, Codable, Equatable, Sendable {
    case intro
    case recap
    case credits
    case postCredits = "post_credits"
    case chapter

    public var badgeLabel: String? {
        switch self {
        case .intro: return "Intro"
        case .recap: return "Sammendrag"
        case .credits: return "Rulletekst"
        case .postCredits: return "Etter rulletekst"
        case .chapter: return nil
        }
    }

    public static func parse(rawKind: String?) -> TvChapterKind? {
        guard let rawKind else { return nil }
        let normalized = rawKind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "intro":
            return .intro
        case "recap":
            return .recap
        case "credits":
            return .credits
        case "post_credits", "postcredits", "after_credits", "aftercredits", "stinger", "etter_rulletekst":
            return .postCredits
        case "chapter":
            return .chapter
        default:
            return nil
        }
    }

    private static let postCreditsRegex = try? NSRegularExpression(
        pattern: #"(?:\b(?:post[\s\-_]*credits|after[\s\-_]*credits|stinger)\b|etter\s+rulletekst)"#,
        options: .caseInsensitive
    )
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

        if matches(postCreditsRegex, in: trimmed) {
            return .postCredits
        }
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

    public static func resolve(
        rawKind: String?,
        title: String,
        startSeconds: Double,
        durationSeconds: Double = 0
    ) -> TvChapterKind {
        let titleKind = classify(
            title: title,
            startSeconds: startSeconds,
            durationSeconds: durationSeconds
        )
        let parsed = parse(rawKind: rawKind)
        // «Post-Credits» / «Etter rulletekst» skal aldri klassifiseres som vanlig «credits» (heller ikke fra eldre prober)
        if titleKind == .postCredits || parsed == .postCredits {
            return .postCredits
        }
        if let parsed, parsed != .chapter {
            return parsed
        }
        return titleKind
    }
}

public struct TvProbeChapter: Codable, Identifiable, Equatable, Sendable {
    public let index: Int?
    public let idString: String
    public let title: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let kind: String?
    public let source: String?

    public var id: String { idString }

    enum CodingKeys: String, CodingKey {
        case index
        case id
        case title
        case startSeconds
        case endSeconds
        case kind
        case type
        case source
    }

    public init(
        index: Int?,
        idString: String,
        title: String,
        startSeconds: Double,
        endSeconds: Double,
        kind: String?,
        source: String? = nil
    ) {
        self.index = index
        self.idString = idString
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.kind = kind
        self.source = source
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

        let fallbackIndex = decodedIndex ?? 0
        let (nextIndex, overflow) = fallbackIndex.addingReportingOverflow(1)
        let fallbackTitle = overflow
            ? "Kapittel \(UInt64(max(0, fallbackIndex)) + 1)"
            : "Kapittel \(nextIndex)"
        let t = (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? fallbackTitle
        self.title = t

        let start = (try? c.decodeIfPresent(Double.self, forKey: .startSeconds)) ?? 0
        self.startSeconds = start
        if let end = try? c.decodeIfPresent(Double.self, forKey: .endSeconds), end > start {
            self.endSeconds = end
        } else {
            self.endSeconds = start + 1
        }
        self.kind = (try? c.decodeIfPresent(String.self, forKey: .kind))
            ?? (try? c.decodeIfPresent(String.self, forKey: .type))
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(index, forKey: .index)
        try c.encode(idString, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(startSeconds, forKey: .startSeconds)
        try c.encode(endSeconds, forKey: .endSeconds)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(source, forKey: .source)
    }
}

public struct RawEngineChapter: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(id: Int, name: String, startSeconds: Double, durationSeconds: Double) {
        self.id = id
        self.name = name
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
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

    #if canImport(AetherBridge)
    public static func merge(
        probeChapters: [TvProbeChapter],
        engineChapters: [ChapterInfo],
        mediaDuration: Double
    ) -> [PlaybackChapter] {
        let rawEngine = engineChapters.map {
            RawEngineChapter(
                id: $0.id,
                name: $0.name,
                startSeconds: $0.startSeconds,
                durationSeconds: $0.durationSeconds
            )
        }
        return mergeRaw(
            probeChapters: probeChapters,
            engineChapters: rawEngine,
            mediaDuration: mediaDuration
        )
    }
    #endif

    private static let genericChapterTitleRegex = try? NSRegularExpression(
        pattern: #"^(?:chapter|kapittel)\s+\d+$"#,
        options: .caseInsensitive
    )

    private static func isGenericChapterTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let regex = genericChapterTitleRegex else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private static func kindPriority(_ kind: TvChapterKind) -> Int {
        switch kind {
        case .postCredits: return 3
        case .intro, .recap, .credits: return 2
        case .chapter: return 1
        }
    }

    private static func compareStartSeconds(_ lhs: Double, _ rhs: Double) -> Bool? {
        if lhs.isNaN || rhs.isNaN {
            if lhs.isNaN && rhs.isNaN { return nil }
            return !lhs.isNaN
        }
        if lhs != rhs {
            return lhs < rhs
        }
        return nil
    }

    public static func mergeRaw(
        probeChapters: [TvProbeChapter],
        engineChapters: [RawEngineChapter],
        mediaDuration: Double
    ) -> [PlaybackChapter] {
        // Prefer live container chapters from AetherEngine when available, enriched with probe kind
        // and supplemented with unmatched semantic external segments (e.g. TheIntroDB intro/recap/credits).
        if !engineChapters.isEmpty {
            let sortedEngine = engineChapters.sorted { a, b in
                if let ordered = compareStartSeconds(a.startSeconds, b.startSeconds) {
                    return ordered
                }
                return a.id < b.id
            }
            var combined = sortedEngine.enumerated().map { idx, ch in
                let start = max(0, ch.startSeconds)
                let rawEnd: Double
                if ch.durationSeconds > 0 {
                    rawEnd = start + ch.durationSeconds
                } else if idx + 1 < sortedEngine.count {
                    rawEnd = max(start + 1, sortedEngine[idx + 1].startSeconds)
                } else {
                    rawEnd = max(start + 1, mediaDuration)
                }
                let end = mediaDuration > start ? min(rawEnd, mediaDuration) : rawEnd

                let matchingProbes = probeChapters.filter { abs($0.startSeconds - start) < 1.5 }
                let cleanTitle = ch.name.trimmingCharacters(in: .whitespacesAndNewlines)

                var bestProbe: TvProbeChapter?
                var bestProbeKind: TvChapterKind = .chapter
                for probe in matchingProbes {
                    let probeKind = TvChapterKind.resolve(
                        rawKind: probe.kind,
                        title: probe.title,
                        startSeconds: start,
                        durationSeconds: mediaDuration
                    )
                    if bestProbe == nil || kindPriority(probeKind) > kindPriority(bestProbeKind) {
                        bestProbe = probe
                        bestProbeKind = probeKind
                    }
                }

                let engineKind = TvChapterKind.resolve(
                    rawKind: nil,
                    title: cleanTitle,
                    startSeconds: start,
                    durationSeconds: mediaDuration
                )
                let resolvedKind: TvChapterKind
                if kindPriority(bestProbeKind) > kindPriority(engineKind) {
                    resolvedKind = bestProbeKind
                } else if engineKind != .chapter {
                    resolvedKind = engineKind
                } else {
                    resolvedKind = bestProbeKind
                }

                let engineTitleIsGeneric = isGenericChapterTitle(cleanTitle)
                let resolvedTitle: String
                if engineTitleIsGeneric,
                   bestProbeKind != .chapter,
                   let probeTitle = bestProbe?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                   !isGenericChapterTitle(probeTitle) {
                    resolvedTitle = probeTitle
                } else if !cleanTitle.isEmpty {
                    resolvedTitle = cleanTitle
                } else if let probeTitle = bestProbe?.title.trimmingCharacters(in: .whitespacesAndNewlines),
                          !probeTitle.isEmpty {
                    resolvedTitle = probeTitle
                } else {
                    resolvedTitle = "Kapittel \(idx + 1)"
                }

                var resolvedEnd = end
                if engineTitleIsGeneric,
                   bestProbeKind != .chapter,
                   let bestProbe,
                   (bestProbe.endSeconds - bestProbe.startSeconds) >= 5 {
                    let rawProbeEnd = max(start + 1, bestProbe.endSeconds)
                    let probeEnd = mediaDuration > start ? min(rawProbeEnd, mediaDuration) : rawProbeEnd
                    resolvedEnd = min(end, probeEnd)
                }

                return PlaybackChapter(
                    id: "eng-\(ch.id)-\(idx)",
                    index: idx,
                    title: resolvedTitle,
                    startSeconds: start,
                    endSeconds: resolvedEnd,
                    kind: resolvedKind
                )
            }

            let semanticKinds: Set<TvChapterKind> = [.intro, .recap, .credits, .postCredits]
            for probe in probeChapters {
                let start = max(0, probe.startSeconds)
                let resolvedKind = TvChapterKind.resolve(
                    rawKind: probe.kind,
                    title: probe.title,
                    startSeconds: start,
                    durationSeconds: mediaDuration
                )
                guard semanticKinds.contains(resolvedKind) else {
                    continue
                }
                let nearSameKind = combined.contains { $0.kind == resolvedKind && abs($0.startSeconds - start) < 15 }
                guard !nearSameKind else { continue }

                let rawEnd = max(start + 1, probe.endSeconds)
                let end = mediaDuration > start ? min(rawEnd, mediaDuration) : rawEnd
                combined.append(
                    PlaybackChapter(
                        id: "probe-\(probe.idString)",
                        index: 0,
                        title: probe.title,
                        startSeconds: start,
                        endSeconds: end,
                        kind: resolvedKind
                    )
                )
            }

            let sortedCombined = combined.sorted { a, b in
                if let ordered = compareStartSeconds(a.startSeconds, b.startSeconds) {
                    return ordered
                }
                return a.id < b.id
            }
            return sortedCombined.enumerated().map { idx, ch in
                PlaybackChapter(
                    id: ch.id,
                    index: idx,
                    title: ch.title,
                    startSeconds: ch.startSeconds,
                    endSeconds: ch.endSeconds,
                    kind: ch.kind
                )
            }
        }

        let sortedProbes = probeChapters.sorted { a, b in
            if let ordered = compareStartSeconds(a.startSeconds, b.startSeconds) {
                return ordered
            }
            return (a.index ?? 0) < (b.index ?? 0)
        }
        return sortedProbes.enumerated().map { idx, ch in
            let start = max(0, ch.startSeconds)
            let rawEnd = max(start + 1, ch.endSeconds)
            let end = mediaDuration > start ? min(rawEnd, mediaDuration) : rawEnd
            let parsedKind = TvChapterKind.resolve(
                rawKind: ch.kind,
                title: ch.title,
                startSeconds: start,
                durationSeconds: mediaDuration
            )
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
