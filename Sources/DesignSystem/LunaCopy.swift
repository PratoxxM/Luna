import Foundation

/// Canonical Norwegian copy, pluralization, decimal formatting & glossary helpers (`LunaCopy`).
public enum LunaCopy: Sendable {
    private static let norwegianLocale = Locale(identifier: "nb")

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

    public nonisolated static func plural(_ count: Int, _ singular: String, _ pluralForm: String) -> String {
        abs(count) == 1 ? "\(count) \(singular)" : "\(count) \(pluralForm)"
    }

    public nonisolated static func formatDays(_ rawDays: Double, suffix: String = "") -> String {
        let rounded: Int
        if rawDays > 0 && rawDays < 1 {
            rounded = 1
        } else {
            rounded = max(0, Int(rawDays.rounded()))
        }
        let base = localizedCount(
            "days_count \(Int64(rounded))",
            fallbackCount: rounded,
            singular: "dag",
            pluralForm: "dager"
        )
        let cleanSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanSuffix.isEmpty ? base : "\(base) \(cleanSuffix)"
    }

    public nonisolated static func formatDecimal(_ value: Double, decimals: Int = 1) -> String {
        let safeDecimals = max(0, min(4, decimals))
        let formatted = String(format: "%.\(safeDecimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
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

    public nonisolated static func pinnedCount(_ count: Int) -> String {
        localizedCount(
            "pinned_items_count \(Int64(count))",
            fallbackCount: count,
            singular: "tittel festet",
            pluralForm: "titler festet"
        )
    }

    public nonisolated static func searchHits(_ count: Int) -> String {
        localizedCount(
            "search_hits_total \(Int64(count))",
            fallbackCount: count,
            singular: "treff",
            pluralForm: "treff"
        )
    }

    public nonisolated static func chaptersHeader(_ count: Int) -> String {
        localizedCount(
            "chapters_count \(Int64(count))",
            fallbackCount: count,
            singular: "kapittel",
            pluralForm: "kapitler"
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

    public nonisolated static func tierShortLabel(tier: String?, source: String? = nil, state: String? = nil) -> String {
        if state == "upcoming" { return "Kommer" }
        let normTier = (tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normSource = (source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normTier == "ssd" || normTier == "nvme" || normSource == "ssd" || normSource == "nvme" {
            return "På NVMe"
        }
        if normTier == "archive" || normSource == "archive" {
            return "I Arkiv"
        }
        if normTier == "local" || normSource == "local" {
            return "Lokalt"
        }
        return "Strøm"
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
        if clean == "hdr10-512" || clean == "livingroom" || clean == "living" || clean == "stua" {
            return "Samsung Frame · HDR10+ · 5.1.2"
        }
        if clean == "dv-fel-714" || clean == "cinema" || clean == "kjellerstua" {
            return "LG OLED · Dolby Vision · 7.1.4"
        }
        let roomClean = (roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if roomClean.contains("stua") && !roomClean.contains("kjeller") {
            return "Samsung Frame · HDR10+ · 5.1.2"
        }
        if roomClean.contains("kjeller") || roomClean.contains("kino") {
            return "LG OLED · Dolby Vision · 7.1.4"
        }
        return "Apple TV 4K · Direkte avspilling"
    }

    public nonisolated static func timeGreeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date) // 1=Sun, 6=Fri, 7=Sat
        let hour = calendar.component(.hour, from: date)
        if weekday == 6 && hour >= 16 { return "Fredagskveld" }
        if weekday == 7 && (5..<12).contains(hour) { return "God lørdag" }
        if weekday == 7 && hour >= 17 { return "Lørdagskveld" }
        if weekday == 1 && hour >= 17 { return "Søndagskveld" }
        if (5..<11).contains(hour) { return "God morgen" }
        if (11..<17).contains(hour) { return "God dag" }
        return "God kveld"
    }
}
