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
    private let maxEntries = 12
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

public enum LibrarySidebarSection: String, CaseIterable, Identifiable, Sendable {
    case localAll
    case localMovies
    case localSeries
    case watchlist
    case lists

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .localAll: return "Lokalt"
        case .localMovies: return "Filmer"
        case .localSeries: return "Serier"
        case .watchlist: return "Huskeliste"
        case .lists: return "Egne lister"
        }
    }

    public var apiSection: String {
        switch self {
        case .localAll, .localMovies, .localSeries:
            return "local"
        case .watchlist:
            return "watchlist"
        case .lists:
            return "lists"
        }
    }

    public var apiMediaType: String {
        switch self {
        case .localMovies: return "movie"
        case .localSeries: return "series"
        default: return "all"
        }
    }

    public var emptyHeadline: String {
        switch self {
        case .watchlist: return "Huskelisten venter"
        case .lists: return "Ingen egne lister ennå"
        case .localMovies: return "Ingen lokale filmer"
        case .localSeries: return "Ingen lokale serier"
        case .localAll: return "Samlingen er tom"
        }
    }

    public var emptySubtitle: String {
        switch self {
        case .watchlist:
            return "Legg til noe dere vil se, så ligger det klart her."
        case .lists:
            return "Opprett egne lister i LunaCore på iPhone, så dukker de opp her."
        case .localMovies:
            return "Filmer som er lagret lokalt vises her så snart de er på plass."
        case .localSeries:
            return "Serier som er lagret lokalt vises her så snart de er klare."
        case .localAll:
            return "Juster filtrene over eller utforsk katalogen for å legge til noe nytt."
        }
    }

    public var emptyActionTitle: String {
        switch self {
        case .localSeries: return "Utforsk serier"
        default: return "Utforsk filmer"
        }
    }

    public var emptyTargetTab: MainNavigationTab {
        switch self {
        case .localSeries: return .series
        default: return .movies
        }
    }
}

struct LibrarySidebarRowButton: View {
    let section: LibrarySidebarSection
    let countText: String?
    let isSelected: Bool
    let onFocusActivate: () -> Void

    @FocusState private var isFocused: Bool
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        Button(action: onFocusActivate) {
            HStack(spacing: 16) {
                Text(section.label)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(isFocused || isSelected ? LunaTheme.linen : LunaTheme.muted)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let countText, !countText.isEmpty {
                    Text(countText)
                        .font(LunaTheme.Font.subtitle.monospacedDigit())
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                }
            }
            .transaction { $0.animation = nil }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceSelected : Color.clear)
                    .transaction { $0.animation = nil }
            )
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTokens.Radius.card)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            focusTask?.cancel()
            focusTask = nil
            guard focused, !isSelected else { return }
            focusTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, isFocused else { return }
                onFocusActivate()
            }
        }
        .onDisappear {
            focusTask?.cancel()
            focusTask = nil
        }
    }
}

struct LibraryCustomListTileButton: View {
    let list: TvCustomListSummary
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private var kindLabel: String {
        switch list.mediaType?.lowercased() {
        case "movie": return "Filmer"
        case "series": return "Serier"
        default: return "Filmer og serier"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.stack.fill")
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                    .frame(width: 48, height: 48)
                    .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(1)

                    Text(list.itemCount > 0 ? "\(kindLabel) · \(LunaCopy.pinnedCount(list.itemCount))" : kindLabel)
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(LunaTheme.Font.microChevron)
                    .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.muted)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surface)
            )
            .lunaFocusSurface(.listRow, isFocused: isFocused, cornerRadius: LunaTheme.cardRadius)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
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
