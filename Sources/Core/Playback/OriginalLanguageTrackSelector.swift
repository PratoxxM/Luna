import Foundation

/// Pure-Swift audio track selector prioritizing the release's `originalLanguage`
/// in highest audio fidelity (`TrueHD Atmos` > `DTS:X` > `TrueHD`/`DTS-HD MA`/`FLAC`/`LPCM` > lossy)
/// while excluding commentary tracks and supporting the per-title «Norsk tale» toggle.
public enum OriginalLanguageTrackSelector: Sendable {
    public static func preferredAudioLanguageCodes(
        forOriginalLanguage rawCode: String?,
        preferNorwegianAudio: Bool = false
    ) -> [String] {
        if preferNorwegianAudio {
            return ["nob", "nor", "no", "nb", "eng"]
        }
        guard let canonical = PlaybackTrackIntent.canonicalLanguageKey(rawCode),
              !canonical.isEmpty,
              canonical != "und" else {
            return ["nob", "nor", "no", "eng"]
        }
        var codes: [String] = [canonical]
        if let rawLower = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rawLower.isEmpty,
           !codes.contains(rawLower) {
            codes.append(rawLower)
        }
        if canonical == "nob" {
            for alias in ["nor", "no", "nb"] where !codes.contains(alias) {
                codes.append(alias)
            }
        }
        if !codes.contains("eng") {
            codes.append("eng")
        }
        return codes
    }

    public static func containsNorwegianTrack(in tracks: [PlaybackAudioTrackDescriptor]) -> Bool {
        let nonCommentary = tracks.filter { !$0.isCommentary }
        let pool = nonCommentary.isEmpty ? tracks : nonCommentary
        return pool.contains {
            PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.name) == "nob"
        }
    }

    public static func selectPreferredAudioTrack(
        in tracks: [PlaybackAudioTrackDescriptor],
        originalLanguage: String?,
        preferNorwegianAudio: Bool = false
    ) -> PlaybackAudioTrackDescriptor? {
        guard !tracks.isEmpty else { return nil }
        let nonCommentary = tracks.filter { !$0.isCommentary }
        let pool = nonCommentary.isEmpty ? tracks : nonCommentary

        if preferNorwegianAudio {
            let norwegianMatches = pool.filter {
                PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.name) == "nob"
            }
            if let bestNo = norwegianMatches.max(by: { qualityScore($0) < qualityScore($1) }) {
                return bestNo
            }
        }

        if let targetLang = PlaybackTrackIntent.canonicalLanguageKey(originalLanguage),
           targetLang != "und" {
            let originalMatches = pool.filter {
                PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.name) == targetLang
            }
            if let bestOriginal = originalMatches.max(by: { qualityScore($0) < qualityScore($1) }) {
                return bestOriginal
            }
        }

        return pool.max(by: { qualityScore($0) < qualityScore($1) })
    }

    public static func qualityScore(_ track: PlaybackAudioTrackDescriptor) -> Int {
        let codecLower = track.codec.lowercased()
        let nameLower = track.name.lowercased()
        let isTrueHD = codecLower.contains("truehd") || codecLower.contains("mlp") || nameLower.contains("truehd")
        let isDTSHDMA = codecLower.contains("dts-hd") || codecLower.contains("dtshd") || nameLower.contains("dts-hd ma") || nameLower.contains("dts-hd")
        let isLosslessPCM = codecLower.contains("flac") || codecLower.contains("pcm") || codecLower.contains("lpcm")
        let isEAC3 = codecLower.contains("eac3") || codecLower.contains("eac-3") || codecLower.contains("ec-3") || codecLower.contains("ddp") || codecLower.contains("dd+")
        let isDTS = codecLower.contains("dts") || codecLower.contains("dca")
        let isAC3 = codecLower == "ac3" || codecLower.contains("ac-3")
        let isAAC = codecLower.contains("aac")

        var score: Int
        if track.isAtmos && isTrueHD {
            score = 1000
        } else if track.isDTSX || nameLower.contains("dts:x") || nameLower.contains("dtsx") {
            score = 950
        } else if isTrueHD || isDTSHDMA || isLosslessPCM {
            score = 850
        } else if track.isAtmos {
            score = 750
        } else if isEAC3 {
            score = 600
        } else if isDTS {
            score = 500
        } else if isAC3 {
            score = 400
        } else if isAAC {
            score = 300
        } else {
            score = 200
        }

        let safeChannels = min(16, max(0, track.channels))
        score += safeChannels * 10
        if track.isDefault {
            score += 4
        }
        return score
    }
}
