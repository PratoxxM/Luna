import SwiftUI

internal struct LibraryBrowseSnapshot {
    var payload: TvLibraryResponse
    var localItems: [TvMediaCard]
    var localOffset: Int
    var localHasMore: Bool
    var fetchedAt: Date
    var refreshNonce: Int
}

@MainActor
internal final class LibraryBrowseMemoryCache {
    static let shared = LibraryBrowseMemoryCache()
    private let maxEntries = DeviceHardwareCapabilities.isHighMemoryDevice ? 32 : 12
    private var entries: [String: LibraryBrowseSnapshot] = [:]
    private var order: [String] = []

    var entryCount: Int { entries.count }

    func snapshot(for key: String) -> LibraryBrowseSnapshot? {
        guard let hit = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    func store(_ snapshot: LibraryBrowseSnapshot, for key: String) {
        entries[key] = snapshot
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    func clear() {
        entries.removeAll()
        order.removeAll()
    }
}

public enum LibraryFilterSection: String, CaseIterable, Identifiable, Sendable {
    case movies
    case series
    case watchlist

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .watchlist: return "Huskeliste"
        }
    }

    public var apiSection: String {
        switch self {
        case .movies, .series: return "local"
        case .watchlist: return "watchlist"
        }
    }

    public var apiMediaType: String {
        switch self {
        case .movies: return "movie"
        case .series: return "series"
        case .watchlist: return "all"
        }
    }

    public func countValue(from counts: TvLibraryCounts?) -> Int? {
        guard let counts else { return nil }
        switch self {
        case .movies: return counts.localMovies ?? 0
        case .series: return counts.localSeries ?? 0
        case .watchlist: return counts.watchlist
        }
    }

    public func pillTitle(counts: TvLibraryCounts?) -> String {
        guard let count = countValue(from: counts) else { return label }
        return "\(label) (\(count))"
    }

    public static func resolveInitialSection(
        counts: TvLibraryCounts?,
        didApplyInitialFallback: Bool,
        current: LibraryFilterSection
    ) -> (section: LibraryFilterSection, didApplyInitialFallback: Bool) {
        guard !didApplyInitialFallback, let counts else {
            return (current, didApplyInitialFallback)
        }
        if current == .movies, (counts.localMovies ?? 0) == 0, (counts.localSeries ?? 0) > 0 {
            return (.series, true)
        }
        return (current, true)
    }

    public var emptyHeadline: String {
        switch self {
        case .movies: return "Ingen lokale filmer"
        case .series: return "Ingen lokale serier"
        case .watchlist: return "Huskelisten venter"
        }
    }

    public var emptySubtitle: String {
        switch self {
        case .movies:
            return "Filmer som er lagret lokalt vises her så snart de er på plass."
        case .series:
            return "Serier som er lagret lokalt vises her så snart de er klare."
        case .watchlist:
            return "Legg til noe dere vil se, så ligger det klart her."
        }
    }

    public var emptyActionTitle: String {
        switch self {
        case .series: return "Utforsk serier"
        case .movies, .watchlist: return "Utforsk filmer"
        }
    }

    public var emptyTargetTab: MainNavigationTab {
        switch self {
        case .series: return .series
        case .movies, .watchlist: return .movies
        }
    }
}

struct LibraryEmptyStateView: View {
    let headline: String
    let subtitle: String
    var actionTitle: String? = nil
    var actionSymbol: String = "film"
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 22) {
            LunaCrescentMarkView(size: 80, color: LunaTheme.moonlight.opacity(0.65))

            Text(headline)
                .font(LunaTheme.Font.pageTitle)
                .foregroundStyle(LunaTheme.linen)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(LunaTheme.Font.body)
                .foregroundStyle(LunaTheme.moonlight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            if let actionTitle, let onAction {
                LunaPillButton(actionTitle, systemImage: actionSymbol, prominence: .glassPill) {
                    onAction()
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
        .padding(.horizontal, 40)
    }
}
