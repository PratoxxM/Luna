import Foundation

/// Pure, centralized episode-code parsing, generic-title filtering, and display formatting
/// shared across loading curtains, player OSD, Now Playing, detail cards, source picker,
/// and playback launch/prepare/resolve API requests.
public enum EpisodeTitleFormatter: Sendable {
    public static func formatEpisodeCode(season: Int?, episode: Int?) -> String? {
        guard let season, let episode, season > 0, episode > 0 else {
            return nil
        }
        return String(format: "S%02dE%02d", season, episode)
    }

    public static func parseEpisodeCode(_ code: String?) -> (season: Int, episode: Int)? {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        return parseSeasonEpisodeToken(raw) ?? parseSeasonXEpisodeToken(raw)
    }

    public static func parseEpisodeFromItemId(_ itemId: String?) -> (season: Int, episode: Int)? {
        guard let raw = itemId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        guard lower.hasPrefix("episode:") else {
            return nil
        }
        let parts = lower.split(separator: ":")
        var parsedSeason: Int?
        var parsedEpisode: Int?
        for part in parts {
            let token = String(part)
            if let combined = parseSeasonEpisodeToken(token) {
                return combined
            }
            if part.hasPrefix("s"), let num = Int(part.dropFirst()), num > 0 {
                parsedSeason = num
            } else if part.hasPrefix("e"), let num = Int(part.dropFirst()), num > 0 {
                parsedEpisode = num
            }
        }
        guard let s = parsedSeason, let e = parsedEpisode else {
            return nil
        }
        return (s, e)
    }

    public static func resolveSeasonAndEpisode(
        itemId: String?,
        season: Int?,
        episode: Int?
    ) -> (season: Int?, episode: Int?) {
        if let season, let episode, season > 0, episode > 0 {
            return (season, episode)
        }
        if let parsed = parseEpisodeFromItemId(itemId) {
            return (parsed.season, parsed.episode)
        }
        return (
            (season ?? 0) > 0 ? season : nil,
            (episode ?? 0) > 0 ? episode : nil
        )
    }

    public static func isEpisodeTarget(
        itemId: String?,
        mediaType: String? = nil,
        seriesTitle: String? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) -> Bool {
        if let seriesTitle, !seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let season, let episode, season > 0, episode > 0 {
            return true
        }
        if parseEpisodeFromItemId(itemId) != nil {
            return true
        }
        let lowerType = (mediaType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerType == "episode" || lowerType == "series" || lowerType == "tv" {
            return true
        }
        let lowerID = (itemId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowerID.hasPrefix("episode:") || lowerID.hasPrefix("series:")
    }

    /// Returns a clean, non-generic episode title, or `nil` when the title is empty, matches
    /// the series title, or is a generic placeholder such as `"Episode 4"`, `"E04"`, `"S01E04"`,
    /// `"TBA"`, or `"Ukjent"`. Preserves real numeric-leading titles like `"401 Unauthorized"`.
    public static func nonGenericEpisodeTitle(
        _ rawTitle: String?,
        seriesTitle: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeCode: String? = nil
    ) -> String? {
        guard var candidate = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return nil
        }

        let cleanSeries = seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCode = episodeCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? formatEpisodeCode(season: season, episode: episode)

        // Strip redundant leading episode code prefixes (e.g., "S01E04 · Title", "1x04 · Title", or "E04 - Title")
        var effectiveSeason = season
        var effectiveEpisode = episode
        var effectiveTargetCode = targetCode
        if let stripped = stripLeadingEpisodeCodePrefix(
            from: candidate,
            season: season,
            episode: episode,
            episodeCode: targetCode
        ) {
            candidate = stripped.title
            if effectiveSeason == nil { effectiveSeason = stripped.parsedCode?.season }
            if effectiveEpisode == nil { effectiveEpisode = stripped.parsedCode?.episode }
            if effectiveTargetCode == nil {
                effectiveTargetCode = formatEpisodeCode(season: effectiveSeason, episode: effectiveEpisode)
            }
        }

        guard !candidate.isEmpty else {
            return nil
        }

        if let cleanSeries, !cleanSeries.isEmpty {
            if candidate.caseInsensitiveCompare(cleanSeries) == .orderedSame {
                return nil
            }
            if isSeriesPlusGenericFallback(
                candidate,
                seriesName: cleanSeries,
                code: effectiveTargetCode,
                episode: effectiveEpisode
            ) {
                return nil
            }
        }

        if isSeriesPlusGenericFallback(
            candidate,
            seriesName: "Serie",
            code: effectiveTargetCode,
            episode: effectiveEpisode
        ) {
            return nil
        }

        if isGenericEpisodePlaceholder(
            candidate,
            episode: effectiveEpisode,
            targetCode: effectiveTargetCode
        ) {
            return nil
        }

        return candidate
    }

    /// Title value safe to send to `/api/tv/v2/playback/prepare` and `/resolve`.
    /// Never sends `seriesTitle` or a generic placeholder as an episode's `title`, allowing
    /// LunaCore to resolve the real episode title from TMDB when missing locally.
    public static func apiEpisodeTitle(
        rawTitle: String?,
        seriesTitle: String?,
        itemId: String?,
        season: Int?,
        episode: Int?
    ) -> String {
        let resolved = resolveSeasonAndEpisode(itemId: itemId, season: season, episode: episode)
        guard isEpisodeTarget(
            itemId: itemId,
            seriesTitle: seriesTitle,
            season: resolved.season,
            episode: resolved.episode
        ) else {
            return rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return nonGenericEpisodeTitle(
            rawTitle,
            seriesTitle: seriesTitle,
            season: resolved.season,
            episode: resolved.episode
        ) ?? ""
    }

    /// Formatting for `ResolvingCurtainView`, consistent from frame 0 both with and without series logo.
    public static func curtainLabels(
        title: String?,
        seriesTitle: String?,
        itemId: String?,
        season: Int?,
        episode: Int?,
        hasLogo: Bool
    ) -> (seriesLine: String?, mainLine: String?) {
        let cleanSeries = seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveSeasonAndEpisode(itemId: itemId, season: season, episode: episode)
        let isEpisode = isEpisodeTarget(
            itemId: itemId,
            seriesTitle: cleanSeries,
            season: resolved.season,
            episode: resolved.episode
        )

        if isEpisode {
            let code = formatEpisodeCode(season: resolved.season, episode: resolved.episode)
            let cleanEp = nonGenericEpisodeTitle(
                title,
                seriesTitle: cleanSeries,
                season: resolved.season,
                episode: resolved.episode,
                episodeCode: code
            )
            let formattedEpisodeLine: String? = {
                switch (code, cleanEp) {
                case let (.some(c), .some(t)):
                    return "\(c) · \(t)"
                case let (.some(c), .none):
                    return c
                case let (.none, .some(t)):
                    return t
                case (.none, .none):
                    return nil
                }
            }()

            if hasLogo {
                return (nil, formattedEpisodeLine)
            }

            let nonEmptySeries = (cleanSeries?.isEmpty == false) ? cleanSeries : nil
            if let formattedEpisodeLine {
                return (nonEmptySeries, formattedEpisodeLine)
            }
            return (nil, nonEmptySeries)
        }

        let cleanMovie = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLogo {
            return (nil, nil)
        }
        return (nil, (cleanMovie?.isEmpty == false) ? cleanMovie : nil)
    }

    /// Formatting for `PlayerBottomBarView` so `S01E04` and generic titles never appear twice.
    public static func bottomBarLabels(
        sessionItem: TvPlaybackItemContext?,
        request: PlaybackLaunchRequest
    ) -> (seriesLine: String?, titleLine: String) {
        let seriesTitle = (sessionItem?.seriesTitle ?? request.seriesTitle)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveSeasonAndEpisode(
            itemId: sessionItem?.itemId ?? request.itemId,
            season: sessionItem?.season ?? request.season,
            episode: sessionItem?.episode ?? request.episode
        )
        let rawTitle = sessionItem?.title ?? request.title
        let isEpisode = isEpisodeTarget(
            itemId: sessionItem?.itemId ?? request.itemId,
            mediaType: sessionItem?.mediaType,
            seriesTitle: seriesTitle,
            season: resolved.season,
            episode: resolved.episode
        )

        if isEpisode {
            let code = formatEpisodeCode(season: resolved.season, episode: resolved.episode)
            let cleanEp = nonGenericEpisodeTitle(
                rawTitle,
                seriesTitle: seriesTitle,
                season: resolved.season,
                episode: resolved.episode,
                episodeCode: code
            )
            let nonEmptySeries = (seriesTitle?.isEmpty == false) ? seriesTitle : nil
            if let cleanEp {
                let topLine: String? = {
                    switch (nonEmptySeries, code) {
                    case let (.some(s), .some(c)): return "\(s) · \(c)"
                    case let (.some(s), .none): return s
                    case let (.none, .some(c)): return c
                    case (.none, .none): return nil
                    }
                }()
                return (topLine, cleanEp)
            }
            if let code {
                return (nonEmptySeries, code)
            }
            if let nonEmptySeries {
                return (nil, nonEmptySeries)
            }
        }

        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return (nil, trimmed.isEmpty ? "Avspilling" : trimmed)
    }

    /// Formatting for detail episode cards (`EpisodeCardView`):
    /// `"Episode 4"` when generic, `"E04 · Title"` when named.
    public static func episodeCardTitle(
        episode: TvEpisodeCard,
        seriesTitle: String? = nil
    ) -> String {
        if let clean = nonGenericEpisodeTitle(
            episode.title,
            seriesTitle: seriesTitle,
            season: episode.seasonNumber,
            episode: episode.episodeNumber,
            episodeCode: episode.seasonEpisodeCode
        ) {
            return "\(episode.codeLabel) · \(clean)"
        }
        return episode.episodeNumber > 0 ? "Episode \(episode.episodeNumber)" : episode.codeLabel
    }

    /// Header subject for `SourcePickerSheetView` (always includes `S01E04` for episodes).
    public static func sourcePickerSubject(
        title: String?,
        seriesTitle: String?,
        itemId: String?,
        season: Int?,
        episode: Int?
    ) -> String {
        let cleanSeries = seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveSeasonAndEpisode(itemId: itemId, season: season, episode: episode)
        let isEpisode = isEpisodeTarget(
            itemId: itemId,
            seriesTitle: cleanSeries,
            season: resolved.season,
            episode: resolved.episode
        )

        if isEpisode {
            let code = formatEpisodeCode(season: resolved.season, episode: resolved.episode)
            let cleanEp = nonGenericEpisodeTitle(
                title,
                seriesTitle: cleanSeries,
                season: resolved.season,
                episode: resolved.episode,
                episodeCode: code
            )
            var parts: [String] = []
            if let cleanSeries, !cleanSeries.isEmpty { parts.append(cleanSeries) }
            if let code { parts.append(code) }
            if let cleanEp { parts.append(cleanEp) }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }

        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? (cleanSeries ?? "") : trimmed
    }

    /// Clean Control Center / iPhone Remote Now Playing fields without duplicate episode codes.
    public static func nowPlayingMetadata(
        for item: TvPlaybackItemContext
    ) -> (title: String, artist: String?, albumTitle: String?) {
        let cleanSeries = item.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = resolveSeasonAndEpisode(itemId: item.itemId, season: item.season, episode: item.episode)
        let isEpisode = isEpisodeTarget(
            itemId: item.itemId,
            mediaType: item.mediaType,
            seriesTitle: cleanSeries,
            season: resolved.season,
            episode: resolved.episode
        )

        if isEpisode {
            let code = formatEpisodeCode(season: resolved.season, episode: resolved.episode)
            let cleanEp = nonGenericEpisodeTitle(
                item.title,
                seriesTitle: cleanSeries,
                season: resolved.season,
                episode: resolved.episode,
                episodeCode: code
            )
            let artist = (cleanSeries?.isEmpty == false) ? cleanSeries : nil

            if let cleanEp {
                let album: String? = {
                    switch (artist, code) {
                    case let (.some(s), .some(c)): return "\(s) · \(c)"
                    case let (.some(s), .none): return s
                    case let (.none, .some(c)): return c
                    case (.none, .none): return nil
                    }
                }()
                return (cleanEp, artist, album)
            }

            let title = code ?? artist ?? item.title
            return (title, artist, artist)
        }

        let artist = item.year.map(String.init)
        return (item.title, artist, nil)
    }

    // MARK: - Private Parsing Helpers

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

    private static func parseSeasonEpisodeToken(_ lower: String) -> (season: Int, episode: Int)? {
        guard lower.hasPrefix("s"), let eIdx = lower.firstIndex(of: "e") else {
            return nil
        }
        let sRaw = lower[lower.index(after: lower.startIndex)..<eIdx]
        let sDigits = sRaw.hasSuffix(" ") ? sRaw.dropLast() : sRaw
        let eDigits = lower[lower.index(after: eIdx)...]
        guard isAsciiDigits(sDigits), isAsciiDigits(eDigits),
              let s = Int(sDigits), let e = Int(eDigits),
              s > 0, e > 0 else {
            return nil
        }
        return (s, e)
    }

    private static func parseSeasonXEpisodeToken(_ lower: String) -> (season: Int, episode: Int)? {
        guard let xIdx = lower.firstIndex(of: "x") else {
            return nil
        }
        let sDigits = lower[..<xIdx]
        let eDigits = lower[lower.index(after: xIdx)...]
        guard isAsciiDigits(sDigits), isAsciiDigits(eDigits),
              sDigits.count <= 3,
              eDigits.count >= 2, eDigits.count <= 4,
              let s = Int(sDigits), let e = Int(eDigits),
              s > 0, e > 0 else {
            return nil
        }
        return (s, e)
    }

    private static func isGenericEpisodePlaceholder(
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

    private static func isSeriesPlusGenericFallback(
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

    private static func stripLeadingEpisodeCodePrefix(
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
        if let season, let episode, season > 0, episode > 0 {
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
