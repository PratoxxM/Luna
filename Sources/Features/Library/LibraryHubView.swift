import SwiftUI

private enum LibrarySectionTab: String, CaseIterable, Identifiable, Sendable {
    case watchlist = "watchlist"
    case favorites = "favorites"
    case local = "local"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watchlist: return "Ønsker å se"
        case .favorites: return "Favoritter & Lister"
        case .local: return "Lokalt på NAS"
        }
    }

    var icon: String {
        switch self {
        case .watchlist: return "bookmark.fill"
        case .favorites: return "star.fill"
        case .local: return "externaldrive.fill.badge.checkmark"
        }
    }
}

struct LibraryHubView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    @State private var activeSection: LibrarySectionTab = .watchlist
    @State private var mediaTypeFilter: String = "all"
    @State private var localTierFilter: String = "all"
    @State private var localSort: String = "recent"

    @State private var libraryPayload: TvLibraryResponse?
    @State private var localItems: [TvMediaCard] = []
    @State private var localOffset: Int = 0
    @State private var localHasMore: Bool = false
    @State private var isLoading: Bool = true
    @State private var isLoadingMoreLocal: Bool = false
    @State private var errorMessage: String?

    @State private var selectedCard: TvMediaCard?
    @State private var selectedCustomList: TvCustomListSummary?

    private let pageSize = 36
    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    private var queryKey: String {
        "\(activeSection.rawValue)#\(mediaTypeFilter)#\(localTierFilter)#\(localSort)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)#\(sessionStore.homeRefreshNonce)"
    }

    var body: some View {
        let client = sessionStore.makeClient()
        let counts = libraryPayload?.counts

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Mitt bibliotek")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, 14)

                // Primary 3-section switcher
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        LunaPillButton(
                            LibrarySectionTab.watchlist.label,
                            systemImage: LibrarySectionTab.watchlist.icon,
                            badgeText: counts.map { String($0.watchlist) },
                            isSelected: activeSection == .watchlist
                        ) {
                            activeSection = .watchlist
                        }

                        LunaPillButton(
                            LibrarySectionTab.favorites.label,
                            systemImage: LibrarySectionTab.favorites.icon,
                            badgeText: counts.map { String($0.favorites) },
                            isSelected: activeSection == .favorites
                        ) {
                            activeSection = .favorites
                        }

                        LunaPillButton(
                            LibrarySectionTab.local.label,
                            systemImage: LibrarySectionTab.local.icon,
                            badgeText: counts.map { String($0.localTotal) },
                            isSelected: activeSection == .local
                        ) {
                            activeSection = .local
                        }

                        Rectangle()
                            .fill(LunaTheme.moonlight.opacity(0.16))
                            .frame(width: 1, height: 28)
                            .padding(.horizontal, 6)

                        mediaTypePills
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()

                // Secondary filter bar for "Lokalt på NAS"
                if activeSection == .local {
                    localTierAndSortBar(counts: counts)
                }

                // Custom MediaLogg shelves strip inside "Favoritter & Lister"
                if activeSection == .favorites,
                   let customLists = libraryPayload?.customLists,
                   !customLists.isEmpty {
                    customShelvesSection(customLists)
                }

                // Active Grid Content
                if isLoading && libraryPayload == nil {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter bibliotek fra NVMe-indeks…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 56)
                } else if let errorMessage, libraryPayload == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadLibrary() }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else {
                    sectionGrid(client: client)
                }
            }
            .padding(.bottom, 72)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .navigationDestination(item: $selectedCustomList) { list in
            CustomRowBrowseView(title: list.name, pathOrRowId: list.browsePath)
        }
        .task(id: queryKey) {
            await loadLibrary()
        }
    }

    @ViewBuilder
    private var mediaTypePills: some View {
        LunaPillButton("Alle typer", isSelected: mediaTypeFilter == "all", prominence: .subtleChip) {
            mediaTypeFilter = "all"
        }
        LunaPillButton("Filmer", systemImage: "film", isSelected: mediaTypeFilter == "movie", prominence: .subtleChip) {
            mediaTypeFilter = "movie"
        }
        LunaPillButton("Serier", systemImage: "tv", isSelected: mediaTypeFilter == "series", prominence: .subtleChip) {
            mediaTypeFilter = "series"
        }
    }

    private func localTierAndSortBar(counts: TvLibraryCounts?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                LunaPillButton(
                    "Alle lokale",
                    systemImage: "square.stack.3d.up.fill",
                    badgeText: counts.map { String($0.localTotal) },
                    isSelected: localTierFilter == "all",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "all"
                }

                LunaPillButton(
                    "Hurtiglagring (NVMe)",
                    systemImage: "bolt.fill",
                    badgeText: counts.map { String($0.nvme) },
                    isSelected: localTierFilter == "nvme",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "nvme"
                }

                LunaPillButton(
                    "Arkiv",
                    systemImage: "archivebox.fill",
                    badgeText: counts.map { String($0.archive) },
                    isSelected: localTierFilter == "archive",
                    prominence: .subtleChip
                ) {
                    localTierFilter = "archive"
                }

                Rectangle()
                    .fill(LunaTheme.moonlight.opacity(0.16))
                    .frame(width: 1, height: 26)
                    .padding(.horizontal, 6)

                LunaPillButton("Nylig lagt til", isSelected: localSort == "recent", prominence: .subtleChip) {
                    localSort = "recent"
                }
                LunaPillButton("Høyest rangert", isSelected: localSort == "rating", prominence: .subtleChip) {
                    localSort = "rating"
                }
                LunaPillButton("A–Å", isSelected: localSort == "title", prominence: .subtleChip) {
                    localSort = "title"
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
    }

    private func customShelvesSection(_ lists: [TvCustomListSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Egne samlinger fra MediaLogg")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, LunaTheme.horizontalGutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(lists) { list in
                        LunaPillButton(
                            list.name,
                            systemImage: "rectangle.stack.fill",
                            badgeText: list.itemCount > 0 ? String(list.itemCount) : nil
                        ) {
                            selectedCustomList = list
                        }
                    }
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func sectionGrid(client: MediaOSClient?) -> some View {
        let activeItems: [TvMediaCard] = {
            switch activeSection {
            case .watchlist:
                return libraryPayload?.watchlist ?? []
            case .favorites:
                return libraryPayload?.favorites ?? []
            case .local:
                return localItems
            }
        }()

        if activeItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(emptyStateHeadline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LunaTheme.moonlight)
                Text(emptyStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(LunaTheme.muted)
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.vertical, 48)
        } else {
            LazyVGrid(columns: columns, spacing: 42) {
                ForEach(activeItems) { card in
                    PosterCardView(
                        card: card,
                        client: client,
                        width: 244,
                        showStorageBadge: activeSection == .local
                    ) {
                        selectedCard = card
                    }
                    .contextMenu {
                        Button {
                            selectedCard = card
                        } label: {
                            Label("Åpne detaljer", systemImage: "info.circle")
                        }

                        Button {
                            Task { await toggleWatched(card) }
                        } label: {
                            Label(
                                card.progress?.watched == true ? "Marker som usett" : "Marker som sett",
                                systemImage: card.progress?.watched == true ? "eye.slash" : "checkmark.circle"
                            )
                        }

                        Button {
                            Task { await toggleFavorite(card) }
                        } label: {
                            Label(
                                card.isFavorite == true ? "Fjern favoritt" : "Marker som favoritt",
                                systemImage: card.isFavorite == true ? "star.slash" : "star.fill"
                            )
                        }

                        Button {
                            Task { await toggleWatchlist(card) }
                        } label: {
                            Label(
                                card.inWatchlist == true ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                                systemImage: card.inWatchlist == true ? "bookmark.slash" : "bookmark"
                            )
                        }
                    }
                    .onAppear {
                        if activeSection == .local,
                           card.id == localItems.last?.id,
                           localHasMore,
                           !isLoadingMoreLocal {
                            Task { await loadMoreLocalItems() }
                        }
                    }
                }
            }
            .padding(.horizontal, LunaTheme.horizontalGutter)

            if activeSection == .local && isLoadingMoreLocal {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        }
    }

    private var emptyStateHeadline: String {
        switch activeSection {
        case .watchlist:
            return "Ingen titler i «Ønsker å se» akkurat nå."
        case .favorites:
            return "Ingen lagrede favoritter ennå."
        case .local:
            return "Ingen lokale filer matchet filteret."
        }
    }

    private var emptyStateSubtitle: String {
        switch activeSection {
        case .watchlist:
            return "Trykk på «Huskeliste» inne på en film eller serie for å samle det dere vil se her."
        case .favorites:
            return "Trykk på stjerne-knappen på favorittfilmer og -serier for rask tilgang."
        case .local:
            return "Lokal filoversikt leses rett fra NVMe-indeksen uten å vekke arkivdiskene."
        }
    }

    private func loadLibrary() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil

        do {
            let res = try await client.fetchLibrary(
                section: activeSection.rawValue,
                tier: localTierFilter,
                mediaType: mediaTypeFilter,
                sort: localSort,
                offset: 0,
                limit: pageSize
            )
            libraryPayload = res
            localItems = res.localItems
            localOffset = res.localItems.count
            localHasMore = res.localHasMore ?? false
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMoreLocalItems() async {
        guard !isLoadingMoreLocal, localHasMore, let client = sessionStore.makeClient() else { return }
        isLoadingMoreLocal = true
        defer { isLoadingMoreLocal = false }

        guard let res = try? await client.fetchLibrary(
            section: "local",
            tier: localTierFilter,
            mediaType: mediaTypeFilter,
            sort: localSort,
            offset: localOffset,
            limit: pageSize
        ) else {
            return
        }

        let existing = Set(localItems.map(\.id))
        let fresh = res.localItems.filter { !existing.contains($0.id) }
        localItems.append(contentsOf: fresh)
        localOffset += res.localItems.count
        localHasMore = res.localHasMore ?? false
    }

    private func toggleWatchlist(_ card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        try? await client.setWatchlist(
            listed: !(card.inWatchlist ?? false),
            mediaType: card.mediaType,
            ids: card.ids,
            title: card.title,
            year: card.year
        )
        sessionStore.notifyContentMutated()
        await loadLibrary()
    }

    private func toggleFavorite(_ card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        try? await client.setFavorite(
            favorite: !(card.isFavorite ?? false),
            mediaType: card.mediaType,
            ids: card.ids,
            title: card.title,
            year: card.year
        )
        sessionStore.notifyContentMutated()
        await loadLibrary()
    }

    private func toggleWatched(_ card: TvMediaCard) async {
        guard let client = sessionStore.makeClient() else { return }
        let nextWatched = !(card.progress?.watched ?? false)
        try? await client.setWatched(
            watched: nextWatched,
            mediaType: card.mediaType,
            ids: card.ids,
            title: card.title,
            year: card.year
        )
        sessionStore.notifyContentMutated()
        await loadLibrary()
    }
}
