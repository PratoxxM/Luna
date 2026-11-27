import Foundation

// MARK: - Catalog & Genre Filter Models (`/api/tv/v2/catalog/:kind`)

public struct TvGenreChip: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let slug: String
    public let label: String
    public let icon: String?
    public let accentColor: String?
    public let tmdbGenreIds: [Int]?
    public let browsePath: String
    public let catalogPath: String?

    public var id: String { "\(slug)#\(browsePath)" }
}

public struct TvCatalogGenreInfo: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let label: String
    public let icon: String?
    public let tmdbGenreIds: [Int]?

    public init(slug: String, label: String, icon: String? = nil, tmdbGenreIds: [Int]? = nil) {
        self.slug = slug; self.label = label; self.icon = icon; self.tmdbGenreIds = tmdbGenreIds
    }
}

public struct TvCatalogResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let mediaType: String
    public let title: String
    public let genre: TvCatalogGenreInfo?
    public let sort: String
    public let localOnly: Bool
    public let unwatchedOnly: Bool
    public let page: Int
    public let limit: Int
    public let hasMore: Bool
    public let availableGenres: [TvGenreChip]?
    public let items: [TvMediaCard]

    public init(
        ok: Bool, mediaType: String, title: String, genre: TvCatalogGenreInfo? = nil,
        sort: String, localOnly: Bool, unwatchedOnly: Bool, page: Int, limit: Int,
        hasMore: Bool, availableGenres: [TvGenreChip]? = nil, items: [TvMediaCard]
    ) {
        self.ok = ok; self.mediaType = mediaType; self.title = title; self.genre = genre
        self.sort = sort; self.localOnly = localOnly; self.unwatchedOnly = unwatchedOnly
        self.page = page; self.limit = limit; self.hasMore = hasMore
        self.availableGenres = availableGenres; self.items = items
    }
}

// MARK: - Unified Library Hub Models (`/api/tv/v2/library`)

public struct TvLibraryCustomList: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mediaType: String?
    public let sourceType: String?
    public let listMode: String?
    public let rowStyle: String?
    public let itemCount: Int
    public let browsePath: String

    public init(
        id: String, name: String, mediaType: String? = nil, sourceType: String? = nil,
        listMode: String? = nil, rowStyle: String? = nil, itemCount: Int = 0, browsePath: String
    ) {
        self.id = id; self.name = name; self.mediaType = mediaType; self.sourceType = sourceType
        self.listMode = listMode; self.rowStyle = rowStyle; self.itemCount = itemCount
        self.browsePath = browsePath
    }
}

public struct TvLibraryCounts: Codable, Equatable, Sendable {
    public let watchlist: Int
    public let localTotal: Int
    public let localMovies: Int?
    public let localSeries: Int?
    public let nvme: Int
    public let archive: Int
    public let vfs: Int
    public let customLists: Int
    public let customListsCount: Int?

    public var resolvedCustomListsCount: Int {
        customListsCount ?? customLists
    }

    public init(
        watchlist: Int, localTotal: Int, localMovies: Int? = nil, localSeries: Int? = nil,
        nvme: Int, archive: Int, vfs: Int, customLists: Int = 0, customListsCount: Int? = nil
    ) {
        self.watchlist = watchlist; self.localTotal = localTotal; self.localMovies = localMovies
        self.localSeries = localSeries; self.nvme = nvme; self.archive = archive; self.vfs = vfs
        self.customLists = customLists; self.customListsCount = customListsCount
    }

    enum CodingKeys: String, CodingKey {
        case watchlist, localTotal, localMovies, localSeries, nvme, archive, vfs, customLists, customListsCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.watchlist = try c.decode(Int.self, forKey: .watchlist)
        self.localTotal = try c.decode(Int.self, forKey: .localTotal)
        self.localMovies = try c.decodeIfPresent(Int.self, forKey: .localMovies)
        self.localSeries = try c.decodeIfPresent(Int.self, forKey: .localSeries)
        self.nvme = try c.decode(Int.self, forKey: .nvme)
        self.archive = try c.decode(Int.self, forKey: .archive)
        self.vfs = try c.decode(Int.self, forKey: .vfs)
        let explicitCustomLists = try c.decodeIfPresent(Int.self, forKey: .customLists)
        let explicitCount = try c.decodeIfPresent(Int.self, forKey: .customListsCount)
        self.customLists = explicitCustomLists ?? explicitCount ?? 0
        self.customListsCount = explicitCount
    }
}

public struct TvLibraryActiveFilters: Codable, Equatable, Sendable {
    public let tier: String?
    public let mediaType: String?
    public let sort: String?

    public init(tier: String? = nil, mediaType: String? = nil, sort: String? = nil) {
        self.tier = tier
        self.mediaType = mediaType
        self.sort = sort
    }
}

public struct TvLibraryResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let section: String
    public let activeFilters: TvLibraryActiveFilters?
    public let counts: TvLibraryCounts
    public let watchlist: [TvMediaCard]
    public let localItems: [TvMediaCard]
    public let localHasMore: Bool?
    public let customLists: [TvLibraryCustomList]?

    public var resolvedCustomLists: [TvLibraryCustomList] {
        customLists ?? []
    }

    public init(
        ok: Bool, section: String, activeFilters: TvLibraryActiveFilters? = nil,
        counts: TvLibraryCounts, watchlist: [TvMediaCard],
        localItems: [TvMediaCard], localHasMore: Bool? = nil, customLists: [TvLibraryCustomList]? = nil
    ) {
        self.ok = ok; self.section = section; self.activeFilters = activeFilters
        self.counts = counts; self.watchlist = watchlist
        self.localItems = localItems; self.localHasMore = localHasMore; self.customLists = customLists
    }

    enum CodingKeys: String, CodingKey {
        case ok, section, activeFilters, counts, watchlist, localItems, localHasMore, customLists
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try c.decode(Bool.self, forKey: .ok)
        self.section = try c.decode(String.self, forKey: .section)
        self.activeFilters = try c.decodeIfPresent(TvLibraryActiveFilters.self, forKey: .activeFilters)
        self.counts = try c.decode(TvLibraryCounts.self, forKey: .counts)
        self.watchlist = try c.decode([TvMediaCard].self, forKey: .watchlist)
        self.localItems = try c.decode([TvMediaCard].self, forKey: .localItems)
        self.localHasMore = try c.decodeIfPresent(Bool.self, forKey: .localHasMore)
        self.customLists = (try? c.decodeIfPresent([TvLibraryCustomList].self, forKey: .customLists)) ?? []
    }
}

// MARK: - Bootstrap & Room Profile Models

public struct TvRoomDefinition: Codable, Identifiable, Equatable, Sendable {
    public let roomId: String?
    public let roomName: String
    public let hardwareProfile: String
    public let equipmentLabel: String?
    public let atmosphere: String?
    public let speakerLayout: String?
    public let label: String?
    public let description: String?

    public var id: String { roomId ?? roomName }

    public init(
        roomId: String? = nil, roomName: String, hardwareProfile: String,
        equipmentLabel: String? = nil, atmosphere: String? = nil,
        speakerLayout: String? = nil, label: String? = nil, description: String? = nil
    ) {
        self.roomId = roomId; self.roomName = roomName; self.hardwareProfile = hardwareProfile
        self.equipmentLabel = equipmentLabel; self.atmosphere = atmosphere
        self.speakerLayout = speakerLayout; self.label = label; self.description = description
    }
}

public struct TvBootstrapResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let device: TvPairedDeviceInfo
    public let defaultRooms: [TvRoomDefinition]?

    public init(ok: Bool, device: TvPairedDeviceInfo, defaultRooms: [TvRoomDefinition]? = nil) {
        self.ok = ok; self.device = device; self.defaultRooms = defaultRooms
    }
}
