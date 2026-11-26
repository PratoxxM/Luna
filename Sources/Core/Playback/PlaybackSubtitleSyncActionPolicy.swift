import Foundation

/// Pure helpers for sofa subtitle search-and-attach (`POST /api/tv/v2/playback/:id/subtitles/search-and-attach`),
/// auto-align (`POST /api/tv/v2/playback/:id/subtitles/auto-align`), and merging external subtitle lists.
public enum PlaybackSubtitleSyncActionPolicy: Sendable {
    public static let defaultSearchLanguages: [String] = ["nob", "nor", "no", "eng"]

    public static func preferredSearchLanguages(originalLanguage: String?) -> [String] {
        var langs = defaultSearchLanguages
        if let orig = PlaybackTrackIntent.canonicalLanguageKey(originalLanguage),
           !orig.isEmpty,
           orig != "und",
           !langs.contains(orig) {
            langs.append(orig)
        }
        return langs
    }

    public static func mergedExternalSubtitles(
        existing: [TvExternalSubtitle],
        response: TvSubtitleSearchAttachResponse
    ) -> [TvExternalSubtitle] {
        var result = existing
        var incoming = response.externalSubtitles
        if let primary = response.subtitle,
           !incoming.contains(where: { $0.id == primary.id && $0.url == primary.url }) {
            incoming.insert(primary, at: 0)
        }
        for item in incoming {
            if let idx = result.firstIndex(where: { $0.id == item.id || $0.url == item.url }) {
                result[idx] = item
            } else {
                result.append(item)
            }
        }
        return result
    }

    public static func mergedAlignedSubtitle(
        existing: [TvExternalSubtitle],
        updated: TvExternalSubtitle?
    ) -> [TvExternalSubtitle] {
        guard let updated else { return existing }
        var result = existing
        if let idx = result.firstIndex(where: { $0.id == updated.id || $0.url == updated.url }) {
            result[idx] = updated
        } else {
            result.append(updated)
        }
        return result
    }

    public static func matchingExternalSubtitle(
        for track: SmartTrackDescriptor?,
        in externals: [TvExternalSubtitle]
    ) -> TvExternalSubtitle? {
        guard !externals.isEmpty else { return nil }
        guard let track, track.isExternal else { return externals.first }
        let trackLang = PlaybackTrackIntent.canonicalLanguageKey(track.language, fallbackName: track.name)
        if let exactName = externals.first(where: {
            ($0.name ?? "").caseInsensitiveCompare(track.name) == .orderedSame
        }) {
            return exactName
        }
        if let trackLang,
           let langMatch = externals.first(where: {
               PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.name ?? "") == trackLang
           }) {
            return langMatch
        }
        return externals.first
    }
}
