import SwiftUI

struct CatalogBrowseView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let mediaType: String
    let initialGenre: TvGenreChip?

    @State private var selectedGenreSlug: String?
    @State private var selectedGenreLabel: String?
    @State private var selectedSort: String = "popular"
    @State private var localOnly: Bool = false
    @State private var unwatchedOnly: Bool = false

    @State private var availableGenres: [TvGenreChip] = []
    @State private var items: [TvMediaCard] = []
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?

    @State private var selectedCard: TvMediaCard?

    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    private let sortOptions: [(id: String, label: String, icon: String)] = [
        ("popular", "Mest populære", "flame.fill"),
        ("top_rated", "Høyest rangert", "star.fill"),
        ("newest", "Nyeste", "sparkles"),
        ("local_recent", "Lokalt hos oss", "internaldrive.fill")
    ]

    init(mediaType: String, initialGenre: TvGenreChip?) {
        self.mediaType = mediaType
        self.initialGenre = initialGenre
        _selectedGenreSlug = State(initialValue: initialGenre?.slug)
        _selectedGenreLabel = State(initialValue: initialGenre?.label)
    }

    private var headerTitle: String {
        let kindLabel = (mediaType == "series" || mediaType == "tv") ? "Serier" : "Filmer"
        if let label = selectedGenreLabel, !label.isEmpty {
            return "\(label) · \(kindLabel)"
        }
        return kindLabel
    }

    private var reloadTriggerKey: String {
        "\(mediaType)#\(selectedGenreSlug ?? "all")#\(selectedSort)#\(localOnly)#\(unwatchedOnly)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(headerTitle)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Velg rekkefølge, sjanger eller begrens til innhold som allerede ligger på NAS-en.")
                        .font(.callout)
                        .foregroundStyle(LunaTheme.muted)
                }
                .padding(.horizontal, LunaTheme.horizontalGutter)
                .padding(.top, 26)

                // Sort & quick filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(sortOptions, id: \.id) { opt in
                            LunaPillButton(
                                opt.label,
                                systemImage: opt.icon,
                                isSelected: selectedSort == opt.id
                            ) {
                                guard selectedSort != opt.id else { return }
                                selectedSort = opt.id
                            }
                        }

                        Rectangle()
                            .fill(LunaTheme.moonlight.opacity(0.16))
                            .frame(width: 1, height: 28)
                            .padding(.horizontal, 6)

                        LunaPillButton(
                            "Kun lokalt",
                            systemImage: localOnly ? "checkmark.circle.fill" : "internaldrive",
                            isSelected: localOnly
                        ) {
                            localOnly.toggle()
                        }

                        LunaPillButton(
                            "Skjul sette",
                            systemImage: unwatchedOnly ? "eye.slash.fill" : "eye.slash",
                            isSelected: unwatchedOnly
                        ) {
                            unwatchedOnly.toggle()
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 8)
                }

                // Genre strip
                if !availableGenres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            LunaPillButton(
                                "Alle sjangre",
                                systemImage: "square.grid.2x2",
                                isSelected: selectedGenreSlug == nil,
                                prominence: .subtleChip
                            ) {
                                selectedGenreSlug = nil
                                selectedGenreLabel = nil
                            }

                            ForEach(availableGenres) { chip in
                                let active = selectedGenreSlug == chip.slug
                                LunaPillButton(
                                    chip.label,
                                    systemImage: LunaTheme.symbolForGenre(slug: chip.slug, serverIcon: chip.icon),
                                    isSelected: active,
                                    prominence: .subtleChip
                                ) {
                                    if active {
                                        selectedGenreSlug = nil
                                        selectedGenreLabel = nil
                                    } else {
                                        selectedGenreSlug = chip.slug
                                        selectedGenreLabel = chip.label
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 6)
                    }
                }

                // Content Grid
                if isLoading && items.isEmpty {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Henter utvalg…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 60)
                } else if let errorMessage, items.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .foregroundStyle(LunaTheme.amber)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            Task { await loadFirstPage() }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                } else if items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ingen treff med valgte filtre.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LunaTheme.moonlight)
                        if localOnly || unwatchedOnly {
                            LunaPillButton("Nullstill hurtigfiltre", systemImage: "xmark.circle") {
                                localOnly = false
                                unwatchedOnly = false
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 42) {
                        ForEach(items) { card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 244,
                                showStorageBadge: localOnly || selectedSort == "local_recent"
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
                                    Task { await toggleWatchlist(card) }
                                } label: {
                                    Label(
                                        card.inWatchlist == true ? "Fjern fra huskeliste" : "Legg til i huskeliste",
                                        systemImage: card.inWatchlist == true ? "bookmark.slash" : "bookmark"
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
                            }
                            .onAppear {
                                if card.id == items.last?.id && hasMore && !isLoadingMore {
                                    Task { await loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.bottom, 32)

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.bottom, 48)
                    }
                }
            }
            .padding(.bottom, 64)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .task(id: reloadTriggerKey) {
            await loadFirstPage()
        }
    }

    private func loadFirstPage() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let res = try await client.fetchCatalog(
                kind: mediaType,
                genre: selectedGenreSlug,
                sort: selectedSort,
                localOnly: localOnly,
                unwatchedOnly: unwatchedOnly,
                page: 1,
                limit: 30
            )
            items = res.items
            hasMore = res.hasMore
            if let genres = res.availableGenres, !genres.isEmpty {
                availableGenres = genres
            }
            if let serverGenre = res.genre {
                selectedGenreLabel = serverGenre.label
            }
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadNextPage() async {
        guard !isLoadingMore, hasMore, let client = sessionStore.makeClient() else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        defer { isLoadingMore = false }

        guard let res = try? await client.fetchCatalog(
            kind: mediaType,
            genre: selectedGenreSlug,
            sort: selectedSort,
            localOnly: localOnly,
            unwatchedOnly: unwatchedOnly,
            page: nextPage,
            limit: 30
        ) else {
            return
        }

        currentPage = nextPage
        hasMore = res.hasMore
        let existingIDs = Set(items.map(\.id))
        let fresh = res.items.filter { !existingIDs.contains($0.id) }
        items.append(contentsOf: fresh)
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
        await loadFirstPage()
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
        await loadFirstPage()
    }
}

/// Full-grid explorer for custom MediaLogg shelves or "Se alle" row links.
struct CustomRowBrowseView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let title: String
    let pathOrRowId: String

    @State private var items: [TvMediaCard] = []
    @State private var hasMore: Bool = false
    @State private var offset: Int = 0
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var selectedCard: TvMediaCard?

    private let pageSize = 36
    private let columns = [
        GridItem(.adaptive(minimum: 236, maximum: 272), spacing: 34)
    ]

    var body: some View {
        let client = sessionStore.makeClient()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.top, 28)

                if isLoading && items.isEmpty {
                    ProgressView()
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                        .padding(.vertical, 48)
                } else if items.isEmpty {
                    Text("Denne listen har ingen titler ennå.")
                        .foregroundStyle(LunaTheme.muted)
                        .padding(.horizontal, LunaTheme.horizontalGutter)
                } else {
                    LazyVGrid(columns: columns, spacing: 42) {
                        ForEach(items) { card in
                            PosterCardView(
                                card: card,
                                client: client,
                                width: 244,
                                showStorageBadge: true
                            ) {
                                selectedCard = card
                            }
                            .onAppear {
                                if card.id == items.last?.id && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                }
            }
            .padding(.bottom, 72)
        }
        .navigationDestination(item: $selectedCard) { card in
            MediaDetailView(mediaType: card.mediaType, itemId: card.itemId, initialTitle: card.title)
        }
        .task {
            await loadInitial()
        }
    }

    private func loadInitial() async {
        guard let client = sessionStore.makeClient() else { return }
        isLoading = true
        offset = 0
        if let res = try? await client.fetchRow(pathOrRowId: pathOrRowId, offset: 0, limit: pageSize) {
            items = res.items
            hasMore = res.hasMore
            offset = res.items.count
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, let client = sessionStore.makeClient() else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if let res = try? await client.fetchRow(pathOrRowId: pathOrRowId, offset: offset, limit: pageSize) {
            let existing = Set(items.map(\.id))
            items.append(contentsOf: res.items.filter { !existing.contains($0.id) })
            hasMore = res.hasMore
            offset += res.items.count
        }
    }
}
