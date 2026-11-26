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
    /// while preserving `Kommende episoder` and server-ordered shelves configured on `/api/tv/v2/home`.
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

    /// Canonical series identity (`series:tmdb:X` / `series:tvdb:X` / `series:imdb:X` / `series:...`)
    /// matching series across `Fortsett`, `Kommende episoder`, and `Nye episoder` (`active_series`).
    /// Returns `nil` for non-series cards (movies).
    public static func seriesDeduplicationKey(for card: TvMediaCard) -> String? {
        let lowerType = card.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerId = card.itemId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSeriesLike = lowerType == "series"
            || lowerType == "tv"
            || lowerType == "episode"
            || lowerId.hasPrefix("series:")
            || lowerId.hasPrefix("episode:")
        guard isSeriesLike else { return nil }

        if let tmdb = card.ids.tmdb ?? card.directPlayTarget?.tmdbId, tmdb > 0 {
            return "series:tmdb:\(tmdb)"
        }
        if let tvdb = card.ids.tvdb, tvdb > 0 {
            return "series:tvdb:\(tvdb)"
        }
        if let imdb = card.ids.imdb?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !imdb.isEmpty {
            return "series:imdb:\(imdb)"
        }
        if lowerId.hasPrefix("episode:") {
            let parts = lowerId.split(separator: ":")
            if parts.count >= 3, (parts[1] == "tmdb" || parts[1] == "tvdb" || parts[1] == "imdb") {
                return "series:\(parts[1]):\(parts[2])"
            }
        }
        return lowerId.isEmpty ? nil : lowerId
    }

    private static func isContinueOrUpcomingAnchorRow(_ row: TvShelfRow) -> Bool {
        let lowerId = row.rowId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerSource = (row.sourceKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerStyle = row.rowStyle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowerId == "medialogg-continue"
            || lowerSource == "system_continue"
            || lowerStyle == "continue_backdrop"
            || lowerId == "upcoming-episodes"
            || lowerSource == "system_upcoming"
            || lowerSource == "upcoming"
            || lowerStyle == "upcoming_backdrop"
    }

    private static func isActiveSeriesRow(_ row: TvShelfRow) -> Bool {
        let lowerId = row.rowId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerSource = (row.sourceKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerSource == "active_series" || lowerSource == "system_active_series" {
            return true
        }
        if lowerId == "new-episodes"
            || lowerId == "medialogg-active"
            || lowerId == "active-series"
            || lowerId == "custom:medialogg-active" {
            return true
        }
        return lowerTitle == "nye episoder"
            || lowerTitle == "mine pågående serier"
            || lowerTitle == "pågående serier"
    }

    /// Prioritizes `Fortsett` cards (`Fra iPhone` first, `I kveld` second), keeps server row order by default,
    /// promotes `Fortsett` to row 0 when an active `Fra iPhone` handoff is waiting, and removes duplicate
    /// series from `Nye episoder` / `active_series` rows when already shown in `Fortsett` or `Kommende episoder`.
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

        var anchoredSeriesKeys = Set<String>()
        for row in rows where isContinueOrUpcomingAnchorRow(row) {
            for card in row.items {
                if let key = seriesDeduplicationKey(for: card) {
                    anchoredSeriesKeys.insert(key)
                }
            }
        }

        if !anchoredSeriesKeys.isEmpty {
            rows = rows.compactMap { row in
                guard isActiveSeriesRow(row) else { return row }
                let dedupedItems = row.items.filter { card in
                    guard let key = seriesDeduplicationKey(for: card) else { return true }
                    return !anchoredSeriesKeys.contains(key)
                }
                guard !dedupedItems.isEmpty else { return nil }
                guard dedupedItems.count != row.items.count else { return row }
                return TvShelfRow(
                    rowId: row.rowId,
                    title: row.title,
                    rowStyle: row.rowStyle,
                    sourceKind: row.sourceKind,
                    listMode: row.listMode,
                    hasMore: row.hasMore,
                    nextPath: row.nextPath,
                    items: dedupedItems
                )
            }
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
