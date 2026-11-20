import Foundation

/// Pure-Swift shelf indexing, row deduplication, continue-watching prioritization,
/// and client-side catalog filtering shared across tvOS views and Linux `LunaCore` tests.
public enum CatalogShelfIndexer: Sendable {
    public static let duplicateWatchlistRowIds: Set<String> = [
        "medialogg-watchlist",
        "custom:medialogg-watchlist",
        "system-watchlist",
        "custom:system-watchlist",
        "watchlist",
    ]

    public static let duplicateGenericLocalRowIds: Set<String> = [
        "medialogg-local",
        "custom:medialogg-local",
        "system-local",
        "custom:system-local",
        "local-library",
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

    public static let upcomingRowIds: Set<String> = [
        "upcoming",
        "upcoming-episodes",
        "medialogg-upcoming",
        "kommende",
        "kommende-episoder",
    ]

    /// Filters out empty shelves, rows belonging exclusively in the Bibliotek hub,
    /// and unreleased `Kommende episoder` rows so playable `Nye episoder` stay near the top.
    public static func filterVisibleRows(_ rows: [TvShelfRow]) -> [TvShelfRow] {
        rows.filter { row in
            guard !row.items.isEmpty else { return false }
            let lowerId = row.rowId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerSource = (row.sourceKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let lowerStyle = row.rowStyle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            if lowerStyle == "upcoming_backdrop"
                || lowerSource == "system_upcoming"
                || lowerSource == "upcoming"
                || upcomingRowIds.contains(lowerId)
                || lowerTitle == "kommende episoder"
                || lowerTitle == "kommende" {
                return false
            }
            return true
        }
    }

    /// Promotes `Fortsett` to row 0 and merges any `Fra iPhone` handoff card at index 0.
    public static func prepareVisibleRows(from payload: TvHomeResponse?) -> [TvShelfRow] {
        var rows = filterVisibleRows(payload?.rows ?? [])
        let continueIdx = rows.firstIndex { row in
            row.rowId == "medialogg-continue" || row.sourceKind == "system_continue"
        }

        if let idx = continueIdx {
            var contRow = rows.remove(at: idx)
            let prioritizedItems = prioritizeContinueCards(
                contRow.items,
                preparedFromPhone: payload?.tonight?.preparedFromPhone
            )
            let normalizedTitle: String = {
                let lower = contRow.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return (lower == "fortsett å se" || lower.isEmpty) ? "Fortsett" : contRow.title
            }()
            contRow = TvShelfRow(
                rowId: contRow.rowId,
                title: normalizedTitle,
                rowStyle: contRow.rowStyle,
                sourceKind: contRow.sourceKind,
                listMode: contRow.listMode,
                hasMore: contRow.hasMore,
                nextPath: contRow.nextPath,
                items: prioritizedItems,
                genres: contRow.genres
            )
            rows.insert(contRow, at: 0)
        } else if let prepared = payload?.tonight?.preparedFromPhone {
            let synthetic = TvShelfRow(
                rowId: "medialogg-continue",
                title: "Fortsett",
                rowStyle: "continue_backdrop",
                sourceKind: "system_continue",
                listMode: "smart",
                hasMore: false,
                nextPath: nil,
                items: [prepared],
                genres: nil
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

    /// Indexes a flat catalog slice by storage tier (`nvme`, `archive`, `stream`) and deduplicates by `itemId`.
    public static func indexByTier(_ cards: [TvMediaCard]) -> (
        nvme: [TvMediaCard],
        archive: [TvMediaCard],
        stream: [TvMediaCard]
    ) {
        var seen = Set<String>()
        var nvme: [TvMediaCard] = []
        var archive: [TvMediaCard] = []
        var stream: [TvMediaCard] = []

        for card in cards where seen.insert(card.itemId).inserted {
            if card.availability?.isLocalNvme == true {
                nvme.append(card)
            } else if card.availability?.isLocalArchive == true {
                archive.append(card)
            } else {
                stream.append(card)
            }
        }
        return (nvme, archive, stream)
    }

    /// Pure client-side filter & sort helper for offline/cached catalog and search views.
    public static func filterAndSortCards(
        _ cards: [TvMediaCard],
        mediaType: String? = nil,
        localOnly: Bool = false,
        unwatchedOnly: Bool = false,
        query: String? = nil,
        sort: String = "popular"
    ) -> [TvMediaCard] {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedType = mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = cards.filter { card in
            if let normalizedType, !normalizedType.isEmpty, normalizedType != "all" {
                let target = (normalizedType == "tv" || normalizedType == "series") ? "series" : "movie"
                if card.mediaType.lowercased() != target {
                    return false
                }
            }
            if localOnly && card.availability?.isPhysicalLocal != true {
                return false
            }
            if unwatchedOnly && card.progress?.watched == true {
                return false
            }
            if !trimmedQuery.isEmpty {
                let inTitle = card.title.lowercased().contains(trimmedQuery)
                let inOverview = (card.overview ?? "").lowercased().contains(trimmedQuery)
                if !inTitle && !inOverview {
                    return false
                }
            }
            return true
        }

        switch sort {
        case "top_rated":
            return filtered.sorted { ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) }
        case "newest":
            return filtered.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case "title":
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            return filtered
        }
    }
}
