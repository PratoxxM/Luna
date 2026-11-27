import Foundation
import Synchronization

public struct CachedHomeSnapshot: Sendable {
    public let etag: String?
    public let payload: TvHomeResponse
    public let visibleRows: [TvShelfRow]

    public init(
        etag: String?,
        payload: TvHomeResponse,
        visibleRows: [TvShelfRow]? = nil
    ) {
        self.etag = etag
        self.payload = payload
        self.visibleRows = visibleRows ?? CatalogShelfIndexer.prepareVisibleRows(from: payload)
    }
}

public struct CachedCatalogSnapshot: Sendable {
    public let etag: String?
    public let payload: TvCatalogResponse

    public init(etag: String?, payload: TvCatalogResponse) {
        self.etag = etag
        self.payload = payload
    }
}

public struct CachedLibrarySnapshot: Sendable {
    public let etag: String?
    public let payload: TvLibraryResponse

    public init(etag: String?, payload: TvLibraryResponse) {
        self.etag = etag
        self.payload = payload
    }
}

private struct SWRCacheMetadata: Codable, Sendable {
    let etag: String?
}

internal actor DiskSWRStorageActor {
    static let shared = DiskSWRStorageActor()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let customDirectoryURL: URL?
    private let maxBytes: Int64
    private let touchTracker = DiskTouchTracker()
    private var accessOrderByBaseName: [String: UInt64] = [:]
    private var lastAccessDateByBaseName: [String: Date] = [:]
    private var accessSequence: UInt64 = 0

    init(
        directoryURL: URL? = nil,
        maxBytes: Int64 = DiskSWRStore.defaultMaxBytes
    ) {
        self.customDirectoryURL = directoryURL
        self.maxBytes = max(0, maxBytes)
    }

    private nonisolated var swrDirectoryURL: URL {
        if let customDirectoryURL {
            return customDirectoryURL
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("swr", isDirectory: true)
    }

    func loadFromDisk<Payload: Decodable & Sendable>(
        baseName: String,
        as type: Payload.Type
    ) -> (etag: String?, payload: Payload)? {
        let dir = swrDirectoryURL
        let payloadURL = dir.appendingPathComponent("\(baseName).json")
        let metaURL = dir.appendingPathComponent("\(baseName).meta.json")
        guard let payloadData = try? Data(contentsOf: payloadURL),
              let decoded = try? decoder.decode(Payload.self, from: payloadData) else {
            return nil
        }
        let meta: SWRCacheMetadata?
        if let metaData = try? Data(contentsOf: metaURL) {
            meta = try? decoder.decode(SWRCacheMetadata.self, from: metaData)
        } else {
            meta = nil
        }

        accessSequence &+= 1
        accessOrderByBaseName[baseName] = accessSequence
        let now = Date()
        lastAccessDateByBaseName[baseName] = now
        if touchTracker.shouldTouchAndRecord(baseName, now: now.timeIntervalSinceReferenceDate) {
            let fm = FileManager.default
            try? fm.setAttributes([.modificationDate: now], ofItemAtPath: payloadURL.path)
            if fm.fileExists(atPath: metaURL.path) {
                try? fm.setAttributes([.modificationDate: now], ofItemAtPath: metaURL.path)
            }
        }

        return (meta?.etag, decoded)
    }

    func saveToDisk(
        rawPayloadData: Data,
        etag: String?,
        baseName: String,
        maxBytesOverride: Int64? = nil
    ) {
        let effectiveMaxBytes = max(0, maxBytesOverride ?? maxBytes)
        if effectiveMaxBytes <= 0 {
            clearAllDiskFiles()
            return
        }

        let fm = FileManager.default
        let dir = swrDirectoryURL
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let payloadURL = dir.appendingPathComponent("\(baseName).json")
        let metaURL = dir.appendingPathComponent("\(baseName).meta.json")

        try? rawPayloadData.write(to: payloadURL, options: .atomic)
        let meta = SWRCacheMetadata(etag: etag)
        if let encodedMeta = try? encoder.encode(meta) {
            try? encodedMeta.write(to: metaURL, options: .atomic)
        }

        let now = Date()
        touchTracker.recordWrite(baseName, now: now.timeIntervalSinceReferenceDate)
        accessSequence &+= 1
        accessOrderByBaseName[baseName] = accessSequence
        lastAccessDateByBaseName[baseName] = now

        pruneIfNeededSynchronously(maxBytes: effectiveMaxBytes, excludingBaseName: baseName)
    }

    func trimDiskCache(maxBytes: Int64) {
        pruneIfNeededSynchronously(maxBytes: max(0, maxBytes), excludingBaseName: nil)
    }

    func diskUsageBytes() -> Int64 {
        FileManager.allocatedDirectoryBytes(at: swrDirectoryURL)
    }

    func clearAllDiskFiles() {
        touchTracker.removeAll()
        accessOrderByBaseName.removeAll()
        lastAccessDateByBaseName.removeAll()
        accessSequence = 0
        try? FileManager.default.removeItem(at: swrDirectoryURL)
    }

    private func pruneIfNeededSynchronously(maxBytes: Int64, excludingBaseName: String?) {
        let fm = FileManager.default
        let dir = swrDirectoryURL
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        struct EntryGroup {
            let baseName: String
            var urls: [URL] = []
            var bytes: Int64 = 0
            var modifiedAt: Date = .distantPast
            let lastAccessDate: Date
            var hasPayload: Bool = false
            var sequence: UInt64 = 0

            var effectiveModifiedAt: Date {
                max(modifiedAt, lastAccessDate)
            }
        }

        var groups: [String: EntryGroup] = [:]
        var totalBytes: Int64 = 0

        for fileURL in urls {
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile != false else {
                continue
            }
            let size = Int64(vals.fileSize ?? 0)
            let mod = vals.contentModificationDate ?? Date.distantPast
            let fileName = fileURL.lastPathComponent
            let baseName: String
            let isPayload: Bool
            if fileName.hasSuffix(".meta.json") {
                baseName = String(fileName.dropLast(".meta.json".count))
                isPayload = false
            } else if fileName.hasSuffix(".json") {
                baseName = String(fileName.dropLast(".json".count))
                isPayload = true
            } else {
                baseName = fileName
                isPayload = false
            }

            totalBytes += size
            var group = groups[baseName] ?? EntryGroup(
                baseName: baseName,
                lastAccessDate: lastAccessDateByBaseName[baseName] ?? .distantPast,
                sequence: accessOrderByBaseName[baseName] ?? 0
            )
            group.urls.append(fileURL)
            group.bytes += size
            if mod > group.modifiedAt {
                group.modifiedAt = mod
            }
            if isPayload {
                group.hasPayload = true
            }
            groups[baseName] = group
        }

        guard totalBytes > maxBytes else { return }
        let targetBytes = maxBytes <= 0 ? 0 : Int64(Double(maxBytes) * 0.80)

        var candidates = groups.values.filter { group in
            guard let excludingBaseName else { return true }
            return group.baseName != excludingBaseName
        }

        candidates.sort { lhs, rhs in
            if lhs.hasPayload != rhs.hasPayload {
                return !lhs.hasPayload
            }
            let timeDiff = lhs.effectiveModifiedAt.timeIntervalSince(rhs.effectiveModifiedAt)
            if abs(timeDiff) > 0.001 {
                return timeDiff < 0
            }
            if lhs.sequence != rhs.sequence {
                return lhs.sequence < rhs.sequence
            }
            return lhs.baseName < rhs.baseName
        }

        for victim in candidates {
            guard totalBytes > targetBytes else { break }
            var removedAny = false
            for url in victim.urls {
                if (try? fm.removeItem(at: url)) != nil {
                    removedAny = true
                }
            }
            if removedAny {
                totalBytes = max(0, totalBytes - victim.bytes)
                accessOrderByBaseName.removeValue(forKey: victim.baseName)
                lastAccessDateByBaseName.removeValue(forKey: victim.baseName)
            }
        }
    }
}

private struct DiskSWRState: Sendable {
    var homeSnapshots: [String: CachedHomeSnapshot] = [:]
    var catalogSnapshots: [String: CachedCatalogSnapshot] = [:]
    var librarySnapshots: [String: CachedLibrarySnapshot] = [:]
    var clearEpoch: UInt64 = 0
    var activeTasks: [UUID: Task<Void, Never>] = [:]
}

/// Sideload-safe Stale-While-Revalidate (SWR) store on tvOS local flash.
///
/// Uses `Caches/LunaV2/swr/` without ever referencing the runtime bundle identifier
/// so free Apple ID re-signing via ATVLoadly keeps cache paths stable across renewals.
/// All disk I/O runs inside `DiskSWRStorageActor`; `@MainActor` reads only from the RAM cache.
public enum DiskSWRStore {
    public static let defaultMaxBytes: Int64 = 16 * 1024 * 1024
    private static let state = Mutex(DiskSWRState())

    private static func sanitize(_ raw: String) -> String {
        String(raw.lowercased().map { ch in
            (ch.isLetter || ch.isNumber || ch == "-" || ch == "_") ? ch : "_"
        })
    }

    private static func scopedBaseName(
        prefix: String,
        serverHost: String?,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        let trimmedHost = serverHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedHost.isEmpty {
            return "\(prefix)-\(sanitize(roomName))-\(sanitize(hardwareProfile))"
        }
        return "\(prefix)-\(sanitize(trimmedHost))-\(sanitize(roomName))-\(sanitize(hardwareProfile))"
    }

    private static func normalizedCatalogKind(_ kind: String) -> String {
        let lower = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (lower == "series" || lower == "tv") ? "series" : "movies"
    }

    private static func homeBaseName(serverHost: String?, roomName: String, hardwareProfile: String) -> String {
        scopedBaseName(prefix: "home", serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
    }

    private static func catalogBaseName(
        kind: String,
        serverHost: String?,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        scopedBaseName(
            prefix: "catalog-\(normalizedCatalogKind(kind))",
            serverHost: serverHost,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
    }

    private static func libraryBaseName(
        section: String,
        mediaType: String,
        serverHost: String?,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        scopedBaseName(
            prefix: "library-\(sanitize(section))-\(sanitize(mediaType))",
            serverHost: serverHost,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
    }

    // MARK: - Home SWR

    /// 0 ms non-blocking memory snapshot lookup for Frame-1 renders without touching disk.
    public static func memorySnapshot(
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) -> CachedHomeSnapshot? {
        let key = homeBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        return state.withLock { $0.homeSnapshots[key] }
    }

    public static func loadHomeAsync(
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) async -> CachedHomeSnapshot? {
        let primaryKey = homeBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let (cachedHit, startEpoch) = state.withLock { ($0.homeSnapshots[primaryKey], $0.clearEpoch) }
        if let cachedHit {
            return cachedHit
        }
        guard let loaded = await DiskSWRStorageActor.shared.loadFromDisk(baseName: primaryKey, as: TvHomeResponse.self) else {
            return nil
        }
        let snapshot = CachedHomeSnapshot(
            etag: loaded.etag,
            payload: loaded.payload,
            visibleRows: CatalogShelfIndexer.prepareVisibleRows(from: loaded.payload)
        )
        return state.withLock { s in
            guard s.clearEpoch == startEpoch, !Task.isCancelled else {
                return nil
            }
            s.homeSnapshots[primaryKey] = snapshot
            return snapshot
        }
    }

    public static func saveHomeInBackground(
        rawPayloadData: Data,
        etag: String?,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String,
        decodedPayload: TvHomeResponse? = nil,
        precomputedRows: [TvShelfRow]? = nil,
        maxDiskBytes: Int64? = nil
    ) {
        let primaryKey = homeBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let taskID = UUID()
        let immediateSnapshot: CachedHomeSnapshot? = decodedPayload.map {
            CachedHomeSnapshot(etag: etag, payload: $0, visibleRows: precomputedRows)
        }
        state.withLock { s in
            if let immediateSnapshot {
                s.homeSnapshots[primaryKey] = immediateSnapshot
            }
            let epoch = s.clearEpoch
            let created = Task.detached(priority: .utility) {
                defer {
                    _ = state.withLock { $0.activeTasks.removeValue(forKey: taskID) }
                }
                guard !Task.isCancelled else { return }
                if immediateSnapshot == nil,
                   let decoded = try? LunaCoreClient.decodeJSON(TvHomeResponse.self, from: rawPayloadData) {
                    let computed = CatalogShelfIndexer.prepareVisibleRows(from: decoded)
                    state.withLock { s in
                        guard s.clearEpoch == epoch, !Task.isCancelled else { return }
                        s.homeSnapshots[primaryKey] = CachedHomeSnapshot(
                            etag: etag,
                            payload: decoded,
                            visibleRows: computed
                        )
                    }
                }
                let shouldWriteDisk = state.withLock { $0.clearEpoch == epoch && !Task.isCancelled }
                guard shouldWriteDisk else { return }
                await DiskSWRStorageActor.shared.saveToDisk(
                    rawPayloadData: rawPayloadData,
                    etag: etag,
                    baseName: primaryKey,
                    maxBytesOverride: maxDiskBytes
                )
            }
            s.activeTasks[taskID] = created
        }
    }

    // MARK: - Catalog Page 1 SWR (`Filmer` / `Serier`)

    public static func catalogMemorySnapshot(
        kind: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) -> CachedCatalogSnapshot? {
        let key = catalogBaseName(kind: kind, serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        return state.withLock { $0.catalogSnapshots[key] }
    }

    public static func loadCatalogAsync(
        kind: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) async -> CachedCatalogSnapshot? {
        let primaryKey = catalogBaseName(kind: kind, serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let (cachedHit, startEpoch) = state.withLock { ($0.catalogSnapshots[primaryKey], $0.clearEpoch) }
        if let cachedHit {
            return cachedHit
        }
        guard let loaded = await DiskSWRStorageActor.shared.loadFromDisk(baseName: primaryKey, as: TvCatalogResponse.self) else {
            return nil
        }
        let snapshot = CachedCatalogSnapshot(etag: loaded.etag, payload: loaded.payload)
        return state.withLock { s in
            guard s.clearEpoch == startEpoch, !Task.isCancelled else {
                return nil
            }
            s.catalogSnapshots[primaryKey] = snapshot
            return snapshot
        }
    }

    public static func saveCatalogInBackground(
        rawPayloadData: Data,
        etag: String?,
        kind: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String,
        decodedPayload: TvCatalogResponse? = nil,
        maxDiskBytes: Int64? = nil
    ) {
        let primaryKey = catalogBaseName(kind: kind, serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let taskID = UUID()
        let immediateSnapshot = decodedPayload.map { CachedCatalogSnapshot(etag: etag, payload: $0) }
        state.withLock { s in
            if let immediateSnapshot {
                s.catalogSnapshots[primaryKey] = immediateSnapshot
            }
            let epoch = s.clearEpoch
            let created = Task.detached(priority: .utility) {
                defer {
                    _ = state.withLock { $0.activeTasks.removeValue(forKey: taskID) }
                }
                guard !Task.isCancelled else { return }
                if immediateSnapshot == nil,
                   let decoded = try? LunaCoreClient.decodeJSON(TvCatalogResponse.self, from: rawPayloadData) {
                    state.withLock { s in
                        guard s.clearEpoch == epoch, !Task.isCancelled else { return }
                        s.catalogSnapshots[primaryKey] = CachedCatalogSnapshot(etag: etag, payload: decoded)
                    }
                }
                let shouldWriteDisk = state.withLock { $0.clearEpoch == epoch && !Task.isCancelled }
                guard shouldWriteDisk else { return }
                await DiskSWRStorageActor.shared.saveToDisk(
                    rawPayloadData: rawPayloadData,
                    etag: etag,
                    baseName: primaryKey,
                    maxBytesOverride: maxDiskBytes
                )
            }
            s.activeTasks[taskID] = created
        }
    }

    // MARK: - Library Page 1 SWR (`Bibliotek`)

    public static func libraryMemorySnapshot(
        section: String,
        mediaType: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) -> CachedLibrarySnapshot? {
        let key = libraryBaseName(
            section: section,
            mediaType: mediaType,
            serverHost: serverHost,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
        return state.withLock { $0.librarySnapshots[key] }
    }

    public static func loadLibraryAsync(
        section: String,
        mediaType: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) async -> CachedLibrarySnapshot? {
        let primaryKey = libraryBaseName(
            section: section,
            mediaType: mediaType,
            serverHost: serverHost,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
        let (cachedHit, startEpoch) = state.withLock { ($0.librarySnapshots[primaryKey], $0.clearEpoch) }
        if let cachedHit {
            return cachedHit
        }
        guard let loaded = await DiskSWRStorageActor.shared.loadFromDisk(baseName: primaryKey, as: TvLibraryResponse.self) else {
            return nil
        }
        let snapshot = CachedLibrarySnapshot(etag: loaded.etag, payload: loaded.payload)
        return state.withLock { s in
            guard s.clearEpoch == startEpoch, !Task.isCancelled else {
                return nil
            }
            s.librarySnapshots[primaryKey] = snapshot
            return snapshot
        }
    }

    public static func saveLibraryInBackground(
        rawPayloadData: Data,
        etag: String?,
        section: String,
        mediaType: String,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String,
        decodedPayload: TvLibraryResponse? = nil,
        maxDiskBytes: Int64? = nil
    ) {
        let primaryKey = libraryBaseName(
            section: section,
            mediaType: mediaType,
            serverHost: serverHost,
            roomName: roomName,
            hardwareProfile: hardwareProfile
        )
        let taskID = UUID()
        let immediateSnapshot = decodedPayload.map { CachedLibrarySnapshot(etag: etag, payload: $0) }
        state.withLock { s in
            if let immediateSnapshot {
                s.librarySnapshots[primaryKey] = immediateSnapshot
            }
            let epoch = s.clearEpoch
            let created = Task.detached(priority: .utility) {
                defer {
                    _ = state.withLock { $0.activeTasks.removeValue(forKey: taskID) }
                }
                guard !Task.isCancelled else { return }
                if immediateSnapshot == nil,
                   let decoded = try? LunaCoreClient.decodeJSON(TvLibraryResponse.self, from: rawPayloadData) {
                    state.withLock { s in
                        guard s.clearEpoch == epoch, !Task.isCancelled else { return }
                        s.librarySnapshots[primaryKey] = CachedLibrarySnapshot(etag: etag, payload: decoded)
                    }
                }
                let shouldWriteDisk = state.withLock { $0.clearEpoch == epoch && !Task.isCancelled }
                guard shouldWriteDisk else { return }
                await DiskSWRStorageActor.shared.saveToDisk(
                    rawPayloadData: rawPayloadData,
                    etag: etag,
                    baseName: primaryKey,
                    maxBytesOverride: maxDiskBytes
                )
            }
            s.activeTasks[taskID] = created
        }
    }

    // MARK: - Maintenance

    public static func diskUsageBytesAsync() async -> Int64 {
        await DiskSWRStorageActor.shared.diskUsageBytes()
    }

    public static func trimDiskCacheAsync(maxBytes: Int64 = defaultMaxBytes) async {
        await DiskSWRStorageActor.shared.trimDiskCache(maxBytes: maxBytes)
    }

    public static func clearMemory() {
        state.withLock {
            $0.homeSnapshots.removeAll()
            $0.catalogSnapshots.removeAll()
            $0.librarySnapshots.removeAll()
        }
    }

    internal static func drainPendingWrites() async {
        while true {
            let tasks = state.withLock { Array($0.activeTasks.values) }
            if tasks.isEmpty { break }
            for task in tasks {
                await task.value
            }
        }
    }

    public static func clearAllAsync() async {
        let tasksToCancel = state.withLock { s -> [Task<Void, Never>] in
            s.clearEpoch &+= 1
            s.homeSnapshots.removeAll()
            s.catalogSnapshots.removeAll()
            s.librarySnapshots.removeAll()
            let tasks = Array(s.activeTasks.values)
            s.activeTasks.removeAll()
            return tasks
        }
        for task in tasksToCancel {
            task.cancel()
        }
        for task in tasksToCancel {
            await task.value
        }
        await DiskSWRStorageActor.shared.clearAllDiskFiles()
        state.withLock { s in
            s.clearEpoch &+= 1
            s.homeSnapshots.removeAll()
            s.catalogSnapshots.removeAll()
            s.librarySnapshots.removeAll()
        }
    }
}
