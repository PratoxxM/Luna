import Foundation
import Synchronization

public struct CachedHomeSnapshot: Sendable {
    public let etag: String?
    public let savedAt: Date
    public let payload: TvHomeResponse
    public let visibleRows: [TvShelfRow]

    public init(
        etag: String?,
        savedAt: Date,
        payload: TvHomeResponse,
        visibleRows: [TvShelfRow]? = nil
    ) {
        self.etag = etag
        self.savedAt = savedAt
        self.payload = payload
        self.visibleRows = visibleRows ?? CatalogShelfIndexer.prepareVisibleRows(from: payload)
    }
}

private struct HomeCacheMetadata: Codable, Sendable {
    let etag: String?
    let savedAt: Date
}

private actor DiskSWRStorageActor {
    static let shared = DiskSWRStorageActor()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private nonisolated var swrDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("swr", isDirectory: true)
    }

    func loadFromDisk(primaryBaseName: String, legacyBaseName: String) -> CachedHomeSnapshot? {
        let dir = swrDirectoryURL
        let candidates = primaryBaseName == legacyBaseName ? [primaryBaseName] : [primaryBaseName, legacyBaseName]

        for baseName in candidates {
            let payloadURL = dir.appendingPathComponent("\(baseName).json")
            let metaURL = dir.appendingPathComponent("\(baseName).meta.json")
            guard let payloadData = try? Data(contentsOf: payloadURL),
                  let decoded = try? decoder.decode(TvHomeResponse.self, from: payloadData) else {
                continue
            }
            let meta: HomeCacheMetadata?
            if let metaData = try? Data(contentsOf: metaURL) {
                meta = try? decoder.decode(HomeCacheMetadata.self, from: metaData)
            } else {
                meta = nil
            }
            let rows = CatalogShelfIndexer.prepareVisibleRows(from: decoded)
            return CachedHomeSnapshot(
                etag: meta?.etag,
                savedAt: meta?.savedAt ?? Date.distantPast,
                payload: decoded,
                visibleRows: rows
            )
        }
        return nil
    }

    func saveToDisk(rawPayloadData: Data, etag: String?, baseName: String) {
        let fm = FileManager.default
        let dir = swrDirectoryURL
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let payloadURL = dir.appendingPathComponent("\(baseName).json")
        let metaURL = dir.appendingPathComponent("\(baseName).meta.json")

        try? rawPayloadData.write(to: payloadURL, options: .atomic)
        let meta = HomeCacheMetadata(etag: etag, savedAt: Date())
        if let encodedMeta = try? encoder.encode(meta) {
            try? encodedMeta.write(to: metaURL, options: .atomic)
        }
    }

    func diskUsageBytes() -> Int64 {
        FileManager.allocatedDirectoryBytes(at: swrDirectoryURL)
    }

    func clearAllDiskFiles() {
        try? FileManager.default.removeItem(at: swrDirectoryURL)
    }
}

private struct DiskSWRState: Sendable {
    var snapshots: [String: CachedHomeSnapshot] = [:]
    var clearEpoch: UInt64 = 0
    var activeTasks: [UUID: Task<Void, Never>] = [:]
}

/// Sideload-safe Stale-While-Revalidate (SWR) store on tvOS local flash.
///
/// Uses `Caches/LunaV2/swr/` without ever referencing the runtime bundle identifier
/// so free Apple ID re-signing via ATVLoadly keeps cache paths stable across renewals.
/// All disk I/O runs inside `DiskSWRStorageActor`; `@MainActor` reads only from the RAM cache.
public enum DiskSWRStore {
    private static let state = Mutex(DiskSWRState())

    private static func sanitize(_ raw: String) -> String {
        String(raw.lowercased().map { ch in
            (ch.isLetter || ch.isNumber || ch == "-" || ch == "_") ? ch : "_"
        })
    }

    private static func legacyFileBaseName(roomName: String, hardwareProfile: String) -> String {
        "home-\(sanitize(roomName))-\(sanitize(hardwareProfile))"
    }

    private static func fileBaseName(serverHost: String?, roomName: String, hardwareProfile: String) -> String {
        let trimmedHost = serverHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedHost.isEmpty {
            return legacyFileBaseName(roomName: roomName, hardwareProfile: hardwareProfile)
        }
        return "home-\(sanitize(trimmedHost))-\(sanitize(roomName))-\(sanitize(hardwareProfile))"
    }

    /// 0 ms non-blocking memory snapshot lookup for Frame-1 renders without touching disk.
    public static func memorySnapshot(
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) -> CachedHomeSnapshot? {
        let key = fileBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        return state.withLock { $0.snapshots[key] }
    }

    public static func loadHomeAsync(
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) async -> CachedHomeSnapshot? {
        let primaryKey = fileBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let (cachedHit, startEpoch) = state.withLock { ($0.snapshots[primaryKey], $0.clearEpoch) }
        if let cachedHit {
            return cachedHit
        }
        let legacyKey = legacyFileBaseName(roomName: roomName, hardwareProfile: hardwareProfile)
        guard let loaded = await DiskSWRStorageActor.shared.loadFromDisk(
            primaryBaseName: primaryKey,
            legacyBaseName: legacyKey
        ) else {
            return nil
        }
        return state.withLock { s in
            guard s.clearEpoch == startEpoch, !Task.isCancelled else {
                return nil
            }
            s.snapshots[primaryKey] = loaded
            return loaded
        }
    }

    public static func saveHomeInBackground(
        rawPayloadData: Data,
        etag: String?,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String,
        decodedPayload: TvHomeResponse? = nil,
        precomputedRows: [TvShelfRow]? = nil
    ) {
        let primaryKey = fileBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        let taskID = UUID()
        let immediateSnapshot: CachedHomeSnapshot? = decodedPayload.map {
            CachedHomeSnapshot(etag: etag, savedAt: Date(), payload: $0, visibleRows: precomputedRows)
        }
        state.withLock { s in
            if let immediateSnapshot {
                s.snapshots[primaryKey] = immediateSnapshot
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
                        s.snapshots[primaryKey] = CachedHomeSnapshot(
                            etag: etag,
                            savedAt: Date(),
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
                    baseName: primaryKey
                )
            }
            s.activeTasks[taskID] = created
        }
    }

    public static func diskUsageBytesAsync() async -> Int64 {
        await DiskSWRStorageActor.shared.diskUsageBytes()
    }

    public static func clearMemory() {
        state.withLock { $0.snapshots.removeAll() }
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
            s.snapshots.removeAll()
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
            s.snapshots.removeAll()
        }
    }
}
