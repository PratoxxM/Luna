import Foundation

/// Pure-Swift shelf indexing, row deduplication, and continue-watching prioritization
/// shared across tvOS views and Linux `LunaCore` tests.
public enum CatalogShelfIndexer: Sendable {
    public static let duplicateWatchlistRowIds: Set<String> = [
        "medialogg-watchlist",
        "custom:medialogg-watchlist",
        "system-watchlist",
        "custom:system-watchlist",
        "watchlist",
    ]

    public static let duplicateGenericLocalRowIds: Set<String> = [
        "system-local",
        "custom:system-local",
    ]

    public static let duplicateGenericLocalTitles: Set<String> = [
        "lokalt",
        "lokalt på nas",
        "lokalt hos oss",
        "lokal samling",
        "mitt bibliotek",
        "bibliotek",
        "hele samlingen",
    ]

    /// Filters out empty shelves and generic Bibliotek-only duplicate rows (`Huskeliste` / full local library),
    /// while preserving `Kommende episoder` and server-ordered shelves configured on `/api/tv/v1/home`.
    public static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        rows.filter { row in
            guard !row.items.isEmpty else { return false }
            let lowerId = row.rowId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerSource = (row.sourceKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if lowerSource == "watchlist" || duplicateWatchlistRowIds.contains(lowerId) {
                return false
            }
            if duplicateGenericLocalRowIds.contains(lowerId) {
                return false
            }
            if lowerSource == "local_library" && duplicateGenericLocalTitles.contains(lowerTitle) {
                return false
            }
            return true
        }
    }

    /// Prioritizes `Fortsett` cards (`Fra iPhone` first, `I kveld` second), keeps server row order by default,
    /// and promotes `Fortsett` to row 0 when an active `Fra iPhone` handoff is waiting.
    public static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        var rows = filterVisibleRows(payload?.rows ?? [])
        let continueIdx = rows.firstIndex { row in
            row.rowId == "medialogg-continue" || row.sourceKind == "system_continue"
        }
        let preparedFromPhone = payload?.tonight?.preparedFromPhone

        if let idx = continueIdx {
            let existing = rows[idx]
            let prioritizedItems = prioritizeContinueCards(
                existing.items,
                preparedFromPhone: preparedFromPhone
            )
            let normalizedTitle: String = {
                let lower = existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return (lower == "fortsett å se" || lower.isEmpty) ? "Fortsett" : existing.title
            }()
            let contRow = TvShelfRow(
                rowId: existing.rowId,
                title: normalizedTitle,
                rowStyle: existing.rowStyle,
                sourceKind: existing.sourceKind,
                listMode: existing.listMode,
                hasMore: existing.hasMore,
                nextPath: existing.nextPath,
                items: prioritizedItems
            )
            if preparedFromPhone != nil && idx != 0 {
                rows.remove(at: idx)
                rows.insert(contRow, at: 0)
            } else {
                rows[idx] = contRow
            }
        } else if let prepared = preparedFromPhone {
            let synthetic = TvShelfRow(
                rowId: "medialogg-continue",
                title: "Fortsett",
                rowStyle: "continue_backdrop",
                sourceKind: "system_continue",
                listMode: "smart",
                hasMore: false,
                nextPath: nil,
                items: [prepared]
            )
            rows.insert(synthetic, at: 0)
        }

        return rows
    }

    /// Orders continue-watching items with `Fra iPhone` (`phone`) first, `I kveld` (`tonight`) second,
    /// and remaining active progress items in server order without duplicates.
    public static func prioritizeContinueCards(
        _ items: [TvMediaCard],
        preparedFromPhone: TvMediaCard?
    ) -> [TvMediaCard] {
        var merged = items
        if let prepared = preparedFromPhone {
            merged.removeAll { $0.itemId == prepared.itemId }
            merged.insert(prepared, at: 0)
        }
        let phone = merged.filter { $0.origin == "phone" }
        let tonight = merged.filter { $0.origin == "tonight" }
        let rest = merged.filter { $0.origin != "phone" && $0.origin != "tonight" }
        return phone + tonight + rest
    }
}
