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
        guard let track else { return externals.first }
        guard track.isExternal else { return nil }
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

    public static func resolvedEmbeddedTrackIndex(
        for track: SmartTrackDescriptor?,
        embeddedSubtitles: [TvSessionEmbeddedSubtitleTrack],
        allDescriptors: [SmartTrackDescriptor]
    ) -> Int? {
        guard let track, !track.isExternal else { return nil }
        let embeddedDescriptors = allDescriptors.filter { !$0.isExternal }
        let allDescriptorsUseStreamIndices = !embeddedDescriptors.isEmpty && embeddedDescriptors.allSatisfy { desc in
            embeddedSubtitles.contains(where: { $0.streamIndex == desc.id })
        }
        let directMatch = embeddedSubtitles.first(where: { $0.streamIndex == track.id })
        let ordinalMatch: TvSessionEmbeddedSubtitleTrack? = {
            guard let ordinal = embeddedDescriptors.firstIndex(where: { $0.id == track.id }),
                  embeddedSubtitles.indices.contains(ordinal) else {
                return nil
            }
            return embeddedSubtitles[ordinal]
        }()

        let trackLang = PlaybackTrackIntent.canonicalLanguageKey(track.language, fallbackName: track.name)
        let directLang = directMatch.flatMap {
            PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.displayTitle ?? "")
        }
        let ordinalLang = ordinalMatch.flatMap {
            PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.displayTitle ?? "")
        }

        if allDescriptorsUseStreamIndices {
            if let directMatch,
               trackLang == nil || directLang == nil || trackLang == directLang {
                return directMatch.streamIndex
            }
            if let ordinalMatch,
               trackLang == nil || ordinalLang == nil || trackLang == ordinalLang {
                return ordinalMatch.streamIndex
            }
        } else {
            if let ordinalMatch,
               trackLang == nil || ordinalLang == nil || trackLang == ordinalLang {
                return ordinalMatch.streamIndex
            }
            if let directMatch,
               trackLang == nil || directLang == nil || trackLang == directLang {
                return directMatch.streamIndex
            }
        }

        if let trackLang,
           let langMatch = embeddedSubtitles.first(where: {
               PlaybackTrackIntent.canonicalLanguageKey($0.language, fallbackName: $0.displayTitle ?? "") == trackLang
           }) {
            return langMatch.streamIndex
        }
        return directMatch?.streamIndex ?? ordinalMatch?.streamIndex ?? track.id
    }

    public static func friendlyAlignReasonMessage(_ reason: String?) -> String {
        let code = (reason ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch code {
        case "":
            return "Kunne ikke synkronisere"
        case "bitmap_subtitle_not_supported":
            return "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk"
        case "archive_spindown_protected":
            return "Arkivfil er beskyttet mot spindown"
        case "unsupported_subtitle_codec":
            return "Undertekstformatet støttes ikke for auto-synk"
        case "embedded_subtitle_not_found":
            return "Fant ingen innebygd undertekst å synkronisere"
        case "vfs_source_unavailable", "nvme_video_required":
            return "Kilden støtter ikke synkronisering av innebygd undertekst"
        case "invalid_extracted_srt":
            return "Kunne ikke lese innebygd undertekst"
        case "align_unavailable":
            return "Kunne ikke synkronisere"
        default:
            if code.contains("_") && !code.contains(" ") {
                return "Kunne ikke synkronisere"
            }
            return (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func friendlyAlignErrorMessage(
        statusCode: Int,
        code: String?,
        serverMessage: String?
    ) -> String {
        let normalizedCode = (code ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !normalizedCode.isEmpty {
            let mapped = friendlyAlignReasonMessage(normalizedCode)
            if mapped != "Kunne ikke synkronisere" || (serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                return mapped
            }
        }
        if let serverMessage {
            let trimmed = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "HTTP \(statusCode)"
    }
}
