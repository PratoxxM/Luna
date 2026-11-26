import Foundation

public enum CustomRowContextPolicy: Sendable {
    public nonisolated static func extractRowId(from pathOrRowId: String) -> String {
        let stripped = pathOrRowId
            .replacingOccurrences(of: "/api/tv/v2/rows/", with: "")
            .replacingOccurrences(of: "/api/tv/v1/rows/", with: "")
            .split(separator: "?").first.map(String.init) ?? pathOrRowId
        return stripped.removingPercentEncoding ?? stripped
    }

    public nonisolated static func isOngoingList(
        explicitFlag: Bool,
        rowId: String,
        sourceKind: String?
    ) -> Bool {
        if explicitFlag { return true }
        if sourceKind == "active_series" || sourceKind == "system_continue" || sourceKind == "system_upcoming" {
            return true
        }
        let lower = rowId.lowercased()
        return lower == "medialogg-continue"
            || lower == "continue-watching"
            || lower == "upcoming-episodes"
            || lower == "medialogg-upcoming"
            || lower.contains("pagaende")
            || lower.contains("active")
            || lower.contains("continue")
    }

    public nonisolated static func removeActionTitle(
        explicitFlag: Bool,
        rowId: String,
        sourceKind: String?
    ) -> String? {
        if isOngoingList(explicitFlag: explicitFlag, rowId: rowId, sourceKind: sourceKind) {
            return "Fjern fra pågående"
        }
        if rowId.hasPrefix("genre:") || sourceKind == "genre" || sourceKind == "local_library" {
            return nil
        }
        return "Fjern fra listen"
    }
}
