import Foundation

/// Canonical Norwegian copy, pluralization, decimal formatting & glossary helpers (`LunaCopy`).
public enum LunaCopy: Sendable {
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
        let base = plural(rounded, "dag", "dager")
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
        plural(count, "festet", "festede")
    }

    public nonisolated static func searchHits(_ count: Int) -> String {
        plural(count, "treff", "treff")
    }

    public nonisolated static func chaptersHeader(_ count: Int) -> String {
        plural(count, "kapittel", "kapitler")
    }

    public nonisolated static func tierBenefitLabel(tier: String?, state: String? = nil) -> String {
        if state == "upcoming" { return "Kommer" }
        let norm = (tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if norm == "ssd" || norm == "nvme" { return "Starter umiddelbart" }
        if norm == "archive" { return "Fra arkivet" }
        return "Strømmes ved start"
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
        if roomClean.contains("kjeller") {
            return "LG OLED · Dolby Vision · 7.1.4"
        }
        return "LG OLED · Dolby Vision · 7.1.4"
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
