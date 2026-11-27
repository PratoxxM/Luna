import Foundation

extension EpisodeTitleFormatter {
    // MARK: - Internal Parsing Helpers

    private static func isAsciiDigits<S: StringProtocol>(_ slice: S) -> Bool {
        !slice.isEmpty && slice.allSatisfy { ch in
            guard let ascii = ch.asciiValue else { return false }
            return ascii >= 48 && ascii <= 57
        }
    }

    private static func stripTrailingPlaceholderPunctuation(_ text: String) -> String {
        let trailingPunctuation: Set<Character> = [".", ",", ":", ";", "-", "–", "—", "!", "?"]
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.last, trailingPunctuation.contains(last) || last.isWhitespace {
            result.removeLast()
        }
        return result
    }

    internal static func parseSeasonEpisodeToken(_ lower: String) -> (season: Int, episode: Int)? {
        guard lower.hasPrefix("s"), let eIdx = lower.firstIndex(of: "e") else {
            return nil
        }
        let sRaw = lower[lower.index(after: lower.startIndex)..<eIdx]
        let sDigits = sRaw.hasSuffix(" ") ? sRaw.dropLast() : sRaw
        let eDigits = lower[lower.index(after: eIdx)...]
        guard isAsciiDigits(sDigits), isAsciiDigits(eDigits),
              let s = Int(sDigits), let e = Int(eDigits),
              s >= 0, e > 0 else {
            return nil
        }
        return (s, e)
    }

    internal static func parseSeasonXEpisodeToken(_ lower: String) -> (season: Int, episode: Int)? {
        guard let xIdx = lower.firstIndex(of: "x") else {
            return nil
        }
        let sDigits = lower[..<xIdx]
        let eDigits = lower[lower.index(after: xIdx)...]
        guard isAsciiDigits(sDigits), isAsciiDigits(eDigits),
              sDigits.count <= 3,
              eDigits.count >= 2, eDigits.count <= 4,
              let s = Int(sDigits), let e = Int(eDigits),
              s >= 0, e > 0 else {
            return nil
        }
        return (s, e)
    }

    internal static func isGenericEpisodePlaceholder(
        _ candidate: String,
        episode: Int?,
        targetCode: String?
    ) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let strippedPunctuation = stripTrailingPlaceholderPunctuation(trimmed)
        let normalized = strippedPunctuation.isEmpty ? trimmed : strippedPunctuation

        if let targetCode, !targetCode.isEmpty,
           normalized.caseInsensitiveCompare(targetCode) == .orderedSame {
            return true
        }

        let lower = normalized.lowercased()
        if ["tba", "tbd", "ukjent", "unknown", "episode", "avsnitt", "untitled", "n/a"].contains(lower) {
            return true
        }

        // Generic "S01E04", "S1E4", or "S01 E04"
        if parseSeasonEpisodeToken(lower) != nil {
            return true
        }

        // Generic "1x04" / "01x04" (requires 2+ digit episode part so titles like "4x4" stay untouched)
        if parseSeasonXEpisodeToken(lower) != nil {
            return true
        }

        // Generic "E04" / "E4"
        if lower.hasPrefix("e"), lower.count > 1, isAsciiDigits(lower.dropFirst()) {
            return true
        }

        // Generic numbered placeholders ("Episode 4", "Episode 4.", "Ep. 4", "Ep.4", "Ep4", "Del 2", "Avsnitt 3", etc.)
        for prefix in ["episode #", "episode ", "ep. #", "ep. ", "ep #", "ep ", "ep.", "ep", "del #", "del ", "avsnitt #", "avsnitt "] {
            if lower.hasPrefix(prefix) {
                let tail = lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty, isAsciiDigits(tail) {
                    return true
                }
            }
        }

        // Bare episode numbers equal to target episode (e.g., "4", "04", "#4" when episode == 4),
        // while preserving real numeric titles such as "101" (for episode 1) or "1917".
        if let episode, episode > 0 {
            let numberToken = lower.hasPrefix("#")
                ? lower.dropFirst().trimmingCharacters(in: .whitespaces)
                : lower
            if isAsciiDigits(numberToken), Int(numberToken) == episode {
                return true
            }
        }

        return false
    }

    internal static func isSeriesPlusGenericFallback(
        _ candidate: String,
        seriesName: String,
        code: String?,
        episode: Int?
    ) -> Bool {
        let lowerCand = candidate.lowercased()
        let lowerSeries = seriesName.lowercased()
        guard lowerCand.hasPrefix(lowerSeries), lowerCand.count > lowerSeries.count else {
            return false
        }
        let afterSeries = lowerCand.dropFirst(lowerSeries.count)
        guard let boundaryChar = afterSeries.first,
              boundaryChar.isWhitespace || ["·", "-", "–", "—", ":", "|", "(", "["].contains(String(boundaryChar)) else {
            return false
        }

        var tail = afterSeries.trimmingCharacters(in: .whitespaces)
        for sep in ["·", "-", "–", "—", ":", "|"] where tail.hasPrefix(sep) {
            tail = tail.dropFirst(sep.count).trimmingCharacters(in: .whitespaces)
            break
        }
        if (tail.hasPrefix("(") && tail.hasSuffix(")")) || (tail.hasPrefix("[") && tail.hasSuffix("]")) {
            tail = String(tail.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !tail.isEmpty else { return false }
        return isGenericEpisodePlaceholder(tail, episode: episode, targetCode: code)
    }

    internal static func stripLeadingEpisodeCodePrefix(
        from candidate: String,
        season: Int?,
        episode: Int?,
        episodeCode: String?
    ) -> (title: String, parsedCode: (season: Int, episode: Int)?)? {
        let lower = candidate.lowercased()
        var tokensToCheck: [String] = []
        if let episodeCode, !episodeCode.isEmpty {
            tokensToCheck.append(episodeCode.lowercased())
        }
        if let season, let episode, season >= 0, episode > 0 {
            for candidateToken in [
                "s\(season)e\(episode)",
                String(format: "%02dx%02d", season, episode),
                "\(season)x\(String(format: "%02d", episode))",
                String(format: "e%02d", episode),
                "e\(episode)"
            ] where !tokensToCheck.contains(candidateToken) {
                tokensToCheck.append(candidateToken)
            }
        }

        // Also match general leading `sXXeYY` or `1x04` / `01x04` token when separating from a title
        if let firstSep = lower.indices.first(where: { idx in
            let ch = lower[idx]
            if ch == " " || ch == "·" || ch == "-" || ch == "–" || ch == "—" || ch == ":" || ch == "|" {
                return true
            }
            if ch == "." {
                let nextIdx = lower.index(after: idx)
                return nextIdx < lower.endIndex && lower[nextIdx].isWhitespace
            }
            return false
        }) {
            let leading = String(lower[..<firstSep])
            if (parseSeasonEpisodeToken(leading) != nil || parseSeasonXEpisodeToken(leading) != nil),
               !tokensToCheck.contains(leading) {
                tokensToCheck.append(leading)
            }
        }

        for token in tokensToCheck where candidate.count >= token.count {
            let prefixSlice = candidate.prefix(token.count)
            guard prefixSlice.caseInsensitiveCompare(token) == .orderedSame else { continue }
            let parsedCode = parseSeasonEpisodeToken(token) ?? parseSeasonXEpisodeToken(token)
            let remainder = candidate.dropFirst(token.count)
            let trimmedRem = remainder.trimmingCharacters(in: .whitespaces)
            if trimmedRem.isEmpty {
                return ("", parsedCode)
            }
            for sep in ["·", "-", "–", "—", ":", "|"] where trimmedRem.hasPrefix(sep) {
                let afterSep = trimmedRem.dropFirst(sep.count).trimmingCharacters(in: .whitespacesAndNewlines)
                return (afterSep, parsedCode)
            }
            if trimmedRem.hasPrefix(".") {
                let afterDotIdx = trimmedRem.index(after: trimmedRem.startIndex)
                if afterDotIdx < trimmedRem.endIndex, trimmedRem[afterDotIdx].isWhitespace {
                    let afterSep = trimmedRem[afterDotIdx...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (afterSep, parsedCode)
                }
            }
            if remainder.first?.isWhitespace == true {
                if parsedCode != nil {
                    return (trimmedRem, parsedCode)
                }
                if isGenericEpisodePlaceholder(trimmedRem, episode: episode, targetCode: episodeCode) {
                    return ("", parsedCode)
                }
            }
        }

        return nil
    }
}
