import Foundation
import Synchronization

public struct CachedHomeSnapshot: Sendable {
    public let etag: String?
    public let savedAt: Date
    public let payload: TvHomeResponse
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
            return CachedHomeSnapshot(
                etag: meta?.etag,
                savedAt: meta?.savedAt ?? Date.distantPast,
                payload: decoded
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
        let dir = swrDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for url in urls {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func clearAllDiskFiles() {
        try? FileManager.default.removeItem(at: swrDirectoryURL)
    }
}

private struct DiskSWRPendingWrites: Sendable {
    var clearEpoch: UInt64 = 0
    var activeTasks: [UUID: Task<Void, Never>] = [:]
}

/// Sideload-safe Stale-While-Revalidate (SWR) store on tvOS local flash.
///
/// Uses `Caches/LunaV2/swr/` without ever referencing the runtime bundle identifier
/// so free Apple ID re-signing via ATVLoadly keeps cache paths stable across renewals.
/// All disk I/O runs inside `DiskSWRStorageActor`; `@MainActor` reads only from the RAM cache.
public enum DiskSWRStore {
    private static let memoryCache = Mutex<[String: CachedHomeSnapshot]>([:])
    private static let pendingWrites = Mutex(DiskSWRPendingWrites())

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
        return memoryCache.withLock { $0[key] }
    }

    private static func storeMemorySnapshot(_ snap: CachedHomeSnapshot, forKey key: String) {
        memoryCache.withLock { $0[key] = snap }
    }

    public static func loadHomeAsync(
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String
    ) async -> CachedHomeSnapshot? {
        let primaryKey = fileBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        if let hit = memorySnapshot(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile) {
            return hit
        }
        let startEpoch = pendingWrites.withLock { $0.clearEpoch }
        let legacyKey = legacyFileBaseName(roomName: roomName, hardwareProfile: hardwareProfile)
        guard let loaded = await DiskSWRStorageActor.shared.loadFromDisk(
            primaryBaseName: primaryKey,
            legacyBaseName: legacyKey
        ) else {
            return nil
        }
        let stillValid = pendingWrites.withLock { $0.clearEpoch == startEpoch } && !Task.isCancelled
        guard stillValid else {
            return nil
        }
        storeMemorySnapshot(loaded, forKey: primaryKey)
        return loaded
    }

    public static func saveHomeInBackground(
        rawPayloadData: Data,
        etag: String?,
        serverHost: String? = nil,
        roomName: String,
        hardwareProfile: String,
        decodedPayload: TvHomeResponse? = nil
    ) {
        let primaryKey = fileBaseName(serverHost: serverHost, roomName: roomName, hardwareProfile: hardwareProfile)
        if let decodedPayload {
            let snap = CachedHomeSnapshot(etag: etag, savedAt: Date(), payload: decodedPayload)
            storeMemorySnapshot(snap, forKey: primaryKey)
        }
        let taskID = UUID()
        pendingWrites.withLock { state in
            let epoch = state.clearEpoch
            let created = Task.detached(priority: .utility) {
                defer {
                    _ = pendingWrites.withLock { $0.activeTasks.removeValue(forKey: taskID) }
                }
                guard !Task.isCancelled else { return }
                if decodedPayload == nil,
                   let decoded = try? LunaCoreClient.decodeJSON(TvHomeResponse.self, from: rawPayloadData) {
                    let shouldStore = pendingWrites.withLock { $0.clearEpoch == epoch && !Task.isCancelled }
                    if shouldStore {
                        let snap = CachedHomeSnapshot(etag: etag, savedAt: Date(), payload: decoded)
                        storeMemorySnapshot(snap, forKey: primaryKey)
                    }
                }
                let shouldWriteDisk = pendingWrites.withLock { $0.clearEpoch == epoch && !Task.isCancelled }
                guard shouldWriteDisk else { return }
                await DiskSWRStorageActor.shared.saveToDisk(
                    rawPayloadData: rawPayloadData,
                    etag: etag,
                    baseName: primaryKey
                )
            }
            state.activeTasks[taskID] = created
        }
    }

    public static func diskUsageBytesAsync() async -> Int64 {
        await DiskSWRStorageActor.shared.diskUsageBytes()
    }

    public static func clearMemory() {
        memoryCache.withLock { $0.removeAll() }
    }

    internal static func drainPendingWrites() async {
        while true {
            let tasks = pendingWrites.withLock { Array($0.activeTasks.values) }
            if tasks.isEmpty { break }
            for task in tasks {
                await task.value
            }
        }
    }

    public static func clearAllAsync() async {
        let tasksToCancel = pendingWrites.withLock { state -> [Task<Void, Never>] in
            state.clearEpoch &+= 1
            let tasks = Array(state.activeTasks.values)
            state.activeTasks.removeAll()
            return tasks
        }
        clearMemory()
        for task in tasksToCancel {
            task.cancel()
        }
        for task in tasksToCancel {
            await task.value
        }
        await DiskSWRStorageActor.shared.clearAllDiskFiles()
    }
}
