import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canonical Norwegian copy, pluralization, decimal formatting & glossary helpers (`LunaCopy`).
public enum LunaCopy: Sendable {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let norwegianLocale = Locale(identifier: "nb")

    #if canImport(Darwin)
    private nonisolated static func localizedCount(
        _ value: String.LocalizationValue,
        fallbackCount: Int,
        singular: String,
        pluralForm: String
    ) -> String {
        let resolved = String(localized: value, bundle: .main, locale: norwegianLocale)
        if resolved.contains("%lld") || resolved.contains("_count") || resolved.contains("_total") {
            return plural(fallbackCount, singular, pluralForm)
        }
        return resolved
    }
    #else
    private nonisolated static func localizedCount(
        _ _: String,
        fallbackCount: Int,
        singular: String,
        pluralForm: String
    ) -> String {
        plural(fallbackCount, singular, pluralForm)
    }
    #endif

    public nonisolated static func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
        abs(count) == 1 ? "\(count) \(singular)" : "\(count) \(pluralForm)"
    }

    public nonisolated static func formatDecimal(_ value: Double, decimals: Int = 1) -> String {
        let safeDecimals = max(0, min(4, decimals))
        let formatted = String(format: "%.\(safeDecimals)f", locale: posixLocale, value)
        return formatted.replacingOccurrences(of: ".", with: ",")
    }

    public nonisolated static func formatRating(_ rating: Double, prefix: String = "★") -> String {
        "\(prefix) \(formatDecimal(rating, decimals: 1))"
    }

    public nonisolated static func formatGigabytes(_ gb: Double, decimals: Int = 1) -> String {
        "\(formatDecimal(gb, decimals: decimals)) GB"
    }

    public nonisolated static func formatMegabytes(_ mb: Double, decimals: Int = 1) -> String {
        "\(formatDecimal(mb, decimals: decimals)) MB"
    }

    public nonisolated static func searchHits(_ count: Int) -> String {
        localizedCount(
            "search_hits_total \(Int64(count))",
            fallbackCount: count,
            singular: "treff",
            pluralForm: "treff"
        )
    }

    public nonisolated static func episodesCount(_ count: Int) -> String {
        localizedCount(
            "episodes_count \(Int64(count))",
            fallbackCount: count,
            singular: "episode",
            pluralForm: "episoder"
        )
    }

    public nonisolated static func seasonsCount(_ count: Int) -> String {
        localizedCount(
            "seasons_count \(Int64(count))",
            fallbackCount: count,
            singular: "sesong",
            pluralForm: "sesonger"
        )
    }

    public nonisolated static func mediaFilesCount(_ count: Int) -> String {
        localizedCount(
            "media_files_count \(Int64(count))",
            fallbackCount: count,
            singular: "mediefil",
            pluralForm: "mediefiler"
        )
    }

    public nonisolated static func localizedSeasonTitle(_ rawName: String?, seasonNumber: Int) -> String {
        let trimmed = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if seasonNumber == 0 || lower == "specials" || lower == "season 0" || lower == "spesialer" {
            return "Spesialer"
        }
        if lower.hasPrefix("season ") {
            let tail = String(trimmed.dropFirst("season ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let num = Int(tail), num > 0 {
                return "Sesong \(num)"
            }
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        return seasonNumber > 0 ? "Sesong \(seasonNumber)" : "Spesialer"
    }

    private static let norwegianLanguageNamesByCode: [String: String] = [
        "nob": "Norsk",
        "nor": "Norsk",
        "no": "Norsk",
        "nb": "Norsk",
        "nno": "Norsk nynorsk",
        "nn": "Norsk nynorsk",
        "swe": "Svensk",
        "sv": "Svensk",
        "dan": "Dansk",
        "da": "Dansk",
        "eng": "Engelsk",
        "en": "Engelsk",
        "ara": "Arabisk",
        "ar": "Arabisk",
        "bul": "Bulgarsk",
        "bg": "Bulgarsk",
        "fin": "Finsk",
        "fi": "Finsk",
        "isl": "Islandsk",
        "ice": "Islandsk",
        "is": "Islandsk",
        "deu": "Tysk",
        "ger": "Tysk",
        "de": "Tysk",
        "fra": "Fransk",
        "fre": "Fransk",
        "fr": "Fransk",
        "spa": "Spansk",
        "es": "Spansk",
        "ita": "Italiensk",
        "it": "Italiensk",
        "por": "Portugisisk",
        "pt": "Portugisisk",
        "nld": "Nederlandsk",
        "dut": "Nederlandsk",
        "nl": "Nederlandsk",
        "pol": "Polsk",
        "pl": "Polsk",
        "rus": "Russisk",
        "ru": "Russisk",
        "ukr": "Ukrainsk",
        "uk": "Ukrainsk",
        "tur": "Tyrkisk",
        "tr": "Tyrkisk",
        "jpn": "Japansk",
        "ja": "Japansk",
        "kor": "Koreansk",
        "ko": "Koreansk",
        "zho": "Kinesisk",
        "chi": "Kinesisk",
        "zh": "Kinesisk",
        "hin": "Hindi",
        "hi": "Hindi",
        "tha": "Thai",
        "th": "Thai",
        "vie": "Vietnamesisk",
        "vi": "Vietnamesisk",
        "ell": "Gresk",
        "gre": "Gresk",
        "el": "Gresk",
        "ces": "Tsjekkisk",
        "cze": "Tsjekkisk",
        "cs": "Tsjekkisk",
        "hun": "Ungarsk",
        "hu": "Ungarsk",
        "ron": "Rumensk",
        "rum": "Rumensk",
        "ro": "Rumensk",
        "hrv": "Kroatisk",
        "hr": "Kroatisk",
        "srp": "Serbisk",
        "sr": "Serbisk",
        "heb": "Hebraisk",
        "he": "Hebraisk",
        "und": "Original",
    ]

    public nonisolated static func localizedLanguageName(_ rawCode: String?) -> String? {
        guard let rawCode else { return nil }
        let cleaned = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !cleaned.isEmpty else { return nil }
        let primary = cleaned.split(separator: "-").first.map(String.init) ?? cleaned
        if let mapped = norwegianLanguageNamesByCode[primary] {
            return mapped
        }
        if let localized = norwegianLocale.localizedString(forLanguageCode: primary) {
            let trimmed = localized.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
            }
        }
        return rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public nonisolated static func formatListEpisodeCode(season: Int?, episode: Int?) -> String? {
        guard let season, let episode, season > 0, episode > 0 else { return nil }
        return "S\(season) · E\(episode)"
    }

    public nonisolated static func formatListEpisodeCode(_ rawCode: String?) -> String? {
        guard let rawCode else { return nil }
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = EpisodeTitleFormatter.parseEpisodeCode(trimmed) {
            return "S\(parsed.season) · E\(parsed.episode)"
        }
        return trimmed
    }

    public nonisolated static func tierBenefitLabel(tier: String?, state: String? = nil) -> String {
        if state == "upcoming" { return "Kommer" }
        let norm = (tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if norm == "ssd" || norm == "nvme" { return "Starter umiddelbart" }
        if norm == "archive" { return "Fra arkivet" }
        if norm == "local" { return "Lokalt" }
        return "Strømmes ved start"
    }

    public nonisolated static func friendlyErrorMessage(
        _ error: Error,
        fallback: String = "Kunne ikke nå LunaCore akkurat nå. Prøv igjen om litt."
    ) -> String {
        if let lcError = error as? LunaCoreError {
            switch lcError {
            case .unauthorized:
                return "TV-paringen er utløpt. Par på nytt i LunaCore."
            case .serverMessage(_, let msg):
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? fallback : trimmed
            case .decodingFailed:
                return "Kunne ikke lese svaret fra LunaCore akkurat nå."
            case .invalidURL:
                return "Ugyldig serveradresse. Sjekk tilkoblingen under Innstillinger."
            }
        }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:
                return "LunaCore svarte ikke i tide. Prøv igjen om et øyeblikk."
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Får ikke kontakt med LunaCore på lokalnettet."
            case .serverCertificateUntrusted, .secureConnectionFailed, .clientCertificateRejected:
                return "Sikker tilkobling feilet. Sjekk sertifikatvalget under Innstillinger."
            default:
                return fallback
            }
        }
        return fallback
    }

    public nonisolated static func roomEquipmentLabel(hardwareProfile: String) -> String {
        roomEquipmentLabel(hardwareProfile: hardwareProfile, roomName: nil, serverLabel: nil)
    }

    public nonisolated static func roomEquipmentLabel(
        hardwareProfile: String,
        roomName: String? = nil,
        serverLabel: String? = nil
    ) -> String {
        if let serverLabel {
            let trimmed = serverLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let clean = hardwareProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean == "hdr10-512" || clean == "stua" {
            return "Samsung Frame Pro · HDR10+ · Sonos 5.1.2"
        }
        if clean == "dv-fel-714" || clean == "kjellerstua" {
            return "LG OLED · Dolby Vision · Sonos 7.1.4"
        }
        let roomClean = (roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if roomClean.contains("stua") && !roomClean.contains("kjeller") {
            return "Samsung Frame Pro · HDR10+ · Sonos 5.1.2"
        }
        if roomClean.contains("kjeller") || roomClean.contains("kino") {
            return "LG OLED · Dolby Vision · Sonos 7.1.4"
        }
        return "Apple TV 4K · Direkte avspilling"
    }
}
