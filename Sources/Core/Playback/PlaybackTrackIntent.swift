import Foundation
#if canImport(AetherBridge)
import AetherBridge
#endif

/// Unified millisecond (`ms`) sync formatting, step arithmetic, and safe memory-bounded
/// clamp ranges for both `Tekstsynk` (`±50 ms`, `−5 000 ... +10 000 ms`) and `Lydsynk` (`±25 ms`, `−2 000 ... +2 000 ms`).
public enum PlaybackSyncTimingPolicy: Sendable {
    public static let subtitleDelayRangeMs: ClosedRange<Int> = -5000...10_000
    public static let subtitleStepMs: Int = 50
    public static let audioDelayRangeMs: ClosedRange<Int> = -2000...2000
    public static let audioStepMs: Int = 25

    public static func clampSubtitleDelayMs(_ rawMs: Int) -> Int {
        min(max(rawMs, subtitleDelayRangeMs.lowerBound), subtitleDelayRangeMs.upperBound)
    }

    public static func clampAudioDelayMs(_ rawMs: Int) -> Int {
        min(max(rawMs, audioDelayRangeMs.lowerBound), audioDelayRangeMs.upperBound)
    }

    public static func stepSubtitleDelayMs(from currentMs: Int, deltaMs: Int) -> Int {
        let (sum, overflow) = Int64(currentMs).addingReportingOverflow(Int64(deltaMs))
        if overflow {
            return deltaMs >= 0 ? subtitleDelayRangeMs.upperBound : subtitleDelayRangeMs.lowerBound
        }
        return Int(min(max(sum, Int64(subtitleDelayRangeMs.lowerBound)), Int64(subtitleDelayRangeMs.upperBound)))
    }

    public static func stepAudioDelayMs(from currentMs: Int, deltaMs: Int) -> Int {
        let (sum, overflow) = Int64(currentMs).addingReportingOverflow(Int64(deltaMs))
        if overflow {
            return deltaMs >= 0 ? audioDelayRangeMs.upperBound : audioDelayRangeMs.lowerBound
        }
        return Int(min(max(sum, Int64(audioDelayRangeMs.lowerBound)), Int64(audioDelayRangeMs.upperBound)))
    }

    /// Formats a millisecond offset with explicit sign (`0 ms`, `+100 ms`, `−50 ms` using Unicode minus).
    public static func formatSignedDelayMs(_ ms: Int) -> String {
        if ms == 0 {
            return "0 ms"
        }
        return ms > 0 ? "+\(ms) ms" : "−\(ms.magnitude) ms"
    }

    public static func headerTitle(baseTitle: String, delayMs: Int) -> String {
        "\(baseTitle) · \(formatSignedDelayMs(delayMs))"
    }
}

public struct PlaybackAudioTrackDescriptor: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let codec: String
    public let language: String?
    public let channels: Int
    public let isAtmos: Bool
    public let isDTSX: Bool
    public let isCommentary: Bool
    public let isDefault: Bool

    public init(
        id: Int,
        name: String = "",
        codec: String = "eac3",
        language: String? = nil,
        channels: Int = 6,
        isAtmos: Bool = false,
        isDTSX: Bool = false,
        isCommentary: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.codec = codec
        self.language = language
        self.channels = channels
        self.isAtmos = isAtmos
        self.isDTSX = isDTSX
        self.isCommentary = isCommentary
        self.isDefault = isDefault
    }

    #if canImport(AetherBridge)
    public init(track: TrackInfo) {
        self.id = track.id
        self.name = track.name
        self.codec = track.codec
        self.language = track.language
        self.channels = Int(track.channels)
        self.isAtmos = track.isAtmos
        self.isDTSX = track.isDTSX
        self.isCommentary = track.isCommentary
        self.isDefault = track.isDefault
    }
    #endif

    public var asSmartDescriptor: SmartTrackDescriptor {
        SmartTrackDescriptor(
            id: id,
            name: name,
            codec: codec,
            language: language,
            isCommentary: isCommentary,
            isDefault: isDefault
        )
    }
}

/// Captures the viewer's active audio, subtitle, and sync intent prior to an in-place
/// `switchSource(to:)` reload so language/forced/off choices survive arbitrary track-ID
/// permutations between MKV releases.
public struct PlaybackTrackIntent: Equatable, Sendable {
    public enum AudioIntent: Equatable, Sendable {
        case automatic
        case matching(
            languageCode: String?,
            isCommentary: Bool,
            prefersObjectAudio: Bool,
            preferredChannels: Int
        )
    }

    public enum SubtitleIntent: Equatable, Sendable {
        case automatic
        case off
        case matching(
            languageCode: String?,
            isForced: Bool,
            isHearingImpaired: Bool,
            wasUserExplicit: Bool
        )
    }

    public enum SubtitleResolution: Equatable, Sendable {
        case clear
        case select(Int)
        case keepCurrent
    }

    public struct Resolution: Equatable, Sendable {
        public let selectedAudioTrackID: Int?
        public let subtitleResolution: SubtitleResolution
        public let preserveManualSubtitleLock: Bool

        public init(
            selectedAudioTrackID: Int?,
            subtitleResolution: SubtitleResolution,
            preserveManualSubtitleLock: Bool
        ) {
            self.selectedAudioTrackID = selectedAudioTrackID
            self.subtitleResolution = subtitleResolution
            self.preserveManualSubtitleLock = preserveManualSubtitleLock
        }
    }

    public let audioIntent: AudioIntent
    public let subtitleIntent: SubtitleIntent
    public let subtitleDelayMs: Int
    public let audioDelayMs: Int

    public init(
        audioIntent: AudioIntent,
        subtitleIntent: SubtitleIntent,
        subtitleDelayMs: Int = 0,
        audioDelayMs: Int = 0
    ) {
        self.audioIntent = audioIntent
        self.subtitleIntent = subtitleIntent
        self.subtitleDelayMs = PlaybackSyncTimingPolicy.clampSubtitleDelayMs(subtitleDelayMs)
        self.audioDelayMs = PlaybackSyncTimingPolicy.clampAudioDelayMs(audioDelayMs)
    }

    private static let canonicalISO639Aliases: [String: String] = [
        "ja": "jpn", "jpn": "jpn",
        "fr": "fra", "fra": "fra", "fre": "fra",
        "de": "deu", "deu": "deu", "ger": "deu",
        "es": "spa", "spa": "spa",
        "it": "ita", "ita": "ita",
        "pt": "por", "por": "por",
        "ko": "kor", "kor": "kor",
        "zh": "zho", "zho": "zho", "chi": "zho",
        "fi": "fin", "fin": "fin",
        "is": "isl", "isl": "isl", "ice": "isl",
        "nl": "nld", "nld": "nld", "dut": "nld",
        "pl": "pol", "pol": "pol",
        "ru": "rus", "rus": "rus",
        "uk": "ukr", "ukr": "ukr",
        "ar": "ara", "ara": "ara",
        "hi": "hin", "hin": "hin",
        "tr": "tur", "tur": "tur",
        "el": "ell", "ell": "ell", "gre": "ell",
        "cs": "ces", "ces": "ces", "cze": "ces",
        "hu": "hun", "hun": "hun",
        "ro": "ron", "ron": "ron", "rum": "ron",
        "he": "heb", "heb": "heb",
        "th": "tha", "tha": "tha",
        "vi": "vie", "vie": "vie",
    ]

    /// Normalizes BCP-47 (`ja-JP`, `en-US`, `nb-NO`), ISO 639-1 (`ja`, `fr`, `de`), and
    /// ISO 639-2B/T (`jpn`, `fre`/`fra`, `ger`/`deu`) codes to a single canonical key.
    public static func canonicalLanguageKey(_ rawCode: String?, fallbackName: String = "") -> String? {
        guard let norm = SmartTrackRuleEngine.normalizeLanguage(rawCode, fallbackName: fallbackName) else {
            return nil
        }
        return canonicalISO639Aliases[norm] ?? norm
    }

    public static func capture(
        audioTracks: [PlaybackAudioTrackDescriptor],
        activeAudioTrackID: Int?,
        subtitleTracks: [SmartTrackDescriptor],
        activeSubtitleTrackID: Int?,
        userManuallySelectedSubtitle: Bool,
        subtitleDelayMs: Int,
        audioDelayMs: Int
    ) -> PlaybackTrackIntent {
        let resolvedAudioIntent: AudioIntent = {
            guard let activeAudioTrackID,
                  let activeAudio = audioTracks.first(where: { $0.id == activeAudioTrackID }) else {
                return .automatic
            }
            let normLang = canonicalLanguageKey(
                activeAudio.language,
                fallbackName: activeAudio.name
            )
            return .matching(
                languageCode: normLang,
                isCommentary: activeAudio.isCommentary,
                prefersObjectAudio: activeAudio.isAtmos || activeAudio.isDTSX,
                preferredChannels: activeAudio.channels
            )
        }()

        let resolvedSubtitleIntent: SubtitleIntent = {
            if let activeSubtitleTrackID,
               let activeSub = subtitleTracks.first(where: { $0.id == activeSubtitleTrackID }) {
                let normLang = canonicalLanguageKey(
                    activeSub.language,
                    fallbackName: activeSub.name
                )
                let forced = SmartTrackRuleEngine.isTrackForced(activeSub)
                let sdh = activeSub.isHearingImpaired || SmartTrackRuleEngine.isNameSDH(activeSub.name)
                return .matching(
                    languageCode: normLang,
                    isForced: forced,
                    isHearingImpaired: sdh,
                    wasUserExplicit: userManuallySelectedSubtitle
                )
            }
            if userManuallySelectedSubtitle {
                return .off
            }
            return .automatic
        }()

        return PlaybackTrackIntent(
            audioIntent: resolvedAudioIntent,
            subtitleIntent: resolvedSubtitleIntent,
            subtitleDelayMs: subtitleDelayMs,
            audioDelayMs: audioDelayMs
        )
    }

    public func resolve(
        audioTracks: [PlaybackAudioTrackDescriptor],
        currentActiveAudioID: Int?,
        subtitleTracks: [SmartTrackDescriptor],
        smartNordicRuleEnabled: Bool
    ) -> Resolution {
        let pickedAudioID = resolveAudioTrackID(
            in: audioTracks,
            currentActiveAudioID: currentActiveAudioID
        )
        let activeAudioForRules = audioTracks.first(where: { $0.id == pickedAudioID })
            ?? audioTracks.first(where: { $0.id == currentActiveAudioID })
            ?? audioTracks.first

        switch subtitleIntent {
        case .off:
            return Resolution(
                selectedAudioTrackID: pickedAudioID,
                subtitleResolution: .clear,
                preserveManualSubtitleLock: true
            )

        case .matching(let lang, let wantsForced, let wantsHI, let wasExplicit):
            if let matchedID = matchSubtitleTrackID(
                languageCode: lang,
                wantsForced: wantsForced,
                wantsHearingImpaired: wantsHI,
                in: subtitleTracks
            ) {
                return Resolution(
                    selectedAudioTrackID: pickedAudioID,
                    subtitleResolution: .select(matchedID),
                    preserveManualSubtitleLock: wasExplicit
                )
            }
            // Requested subtitle language does not exist in the new release -> fall back to SmartTrackRuleEngine
            let fallback = fallbackSubtitleResolution(
                activeAudio: activeAudioForRules,
                subtitleTracks: subtitleTracks,
                smartNordicRuleEnabled: smartNordicRuleEnabled
            )
            return Resolution(
                selectedAudioTrackID: pickedAudioID,
                subtitleResolution: fallback,
                preserveManualSubtitleLock: false
            )

        case .automatic:
            let fallback = fallbackSubtitleResolution(
                activeAudio: activeAudioForRules,
                subtitleTracks: subtitleTracks,
                smartNordicRuleEnabled: smartNordicRuleEnabled
            )
            return Resolution(
                selectedAudioTrackID: pickedAudioID,
                subtitleResolution: fallback,
                preserveManualSubtitleLock: false
            )
        }
    }

    private func resolveAudioTrackID(
        in tracks: [PlaybackAudioTrackDescriptor],
        currentActiveAudioID: Int?
    ) -> Int? {
        guard !tracks.isEmpty else { return nil }
        guard case let .matching(lang, isCommentary, prefersObject, prefChannels) = audioIntent else {
            return currentActiveAudioID ?? tracks.first?.id
        }

        let matching = tracks.filter { cand in
            guard cand.isCommentary == isCommentary else { return false }
            guard let lang else { return true }
            return Self.canonicalLanguageKey(cand.language, fallbackName: cand.name) == lang
        }
        guard !matching.isEmpty else {
            return currentActiveAudioID
                ?? tracks.first(where: { !$0.isCommentary })?.id
                ?? tracks.first?.id
        }

        let winner = matching.max { a, b in
            scoreAudio(a, prefersObject: prefersObject, preferredChannels: prefChannels) <
                scoreAudio(b, prefersObject: prefersObject, preferredChannels: prefChannels)
        }
        return winner?.id
    }

    private func scoreAudio(
        _ track: PlaybackAudioTrackDescriptor,
        prefersObject: Bool,
        preferredChannels: Int
    ) -> Int {
        var score = 0
        let hasObject = track.isAtmos || track.isDTSX
        if prefersObject && hasObject {
            score += 50
        } else if !prefersObject && !hasObject {
            score += 12
        }
        let codecLower = track.codec.lowercased()
        if codecLower.contains("truehd") || codecLower.contains("dts-hd") || codecLower.contains("flac") || codecLower.contains("pcm") {
            score += 20
        }
        if preferredChannels > 0 {
            let (rawDiff, overflow) = Int64(track.channels).subtractingReportingOverflow(Int64(preferredChannels))
            if !overflow {
                let absDiff: Int64 = rawDiff == Int64.min ? Int64.max : abs(rawDiff)
                if absDiff < 5 {
                    score += Int(max(0, 15 - absDiff * 3))
                }
            }
        }
        if track.isDefault {
            score += 4
        }
        return score
    }

    private func matchSubtitleTrackID(
        languageCode: String?,
        wantsForced: Bool,
        wantsHearingImpaired: Bool,
        in tracks: [SmartTrackDescriptor]
    ) -> Int? {
        let matching = tracks.filter { cand in
            guard !cand.isCommentary else { return false }
            guard let languageCode else { return true }
            return Self.canonicalLanguageKey(cand.language, fallbackName: cand.name) == languageCode
        }
        guard !matching.isEmpty else { return nil }

        let best = matching.max { a, b in
            scoreSubtitleCandidate(a, wantsForced: wantsForced, wantsHI: wantsHearingImpaired) <
                scoreSubtitleCandidate(b, wantsForced: wantsForced, wantsHI: wantsHearingImpaired)
        }
        return best?.id
    }

    private func scoreSubtitleCandidate(
        _ track: SmartTrackDescriptor,
        wantsForced: Bool,
        wantsHI: Bool
    ) -> Int {
        var score = 0
        let forced = SmartTrackRuleEngine.isTrackForced(track)
        let sdh = track.isHearingImpaired || SmartTrackRuleEngine.isNameSDH(track.name)
        if forced == wantsForced {
            score += 120
        }
        if sdh == wantsHI {
            score += 45
        }
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

    private func fallbackSubtitleResolution(
        activeAudio: PlaybackAudioTrackDescriptor?,
        subtitleTracks: [SmartTrackDescriptor],
        smartNordicRuleEnabled: Bool
    ) -> SubtitleResolution {
        guard smartNordicRuleEnabled else { return .keepCurrent }
        let decision = SmartTrackRuleEngine.evaluate(
            activeAudio: activeAudio?.asSmartDescriptor,
            subtitleTracks: subtitleTracks
        )
        switch decision {
        case .clearSubtitles:
            return .clear
        case .selectTrack(let id):
            return .select(id)
        case .keepCurrent:
            return .keepCurrent
        }
    }
}
