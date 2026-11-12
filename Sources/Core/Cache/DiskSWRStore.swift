import Foundation

public struct CachedHomeSnapshot: Sendable {
    public let etag: String?
    public let savedAt: Date
    public let payload: TvHomeResponse
}

private struct HomeCacheMetadata: Codable, Sendable {
    let etag: String?
    let savedAt: Date
}

/// Sideload-safe Stale-While-Revalidate (SWR) store on tvOS local flash.
///
/// Uses `Caches/LunaV2/swr/` without ever referencing the runtime bundle identifier
/// so free Apple ID re-signing via ATVLoadly keeps cache paths stable across renewals.
public enum DiskSWRStore {
    private static var swrDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("LunaV2", isDirectory: true)
            .appendingPathComponent("swr", isDirectory: true)
    }

    private static func fileBaseName(roomName: String, hardwareProfile: String) -> String {
        let raw = "\(roomName.lowercased())-\(hardwareProfile.lowercased())"
        let sanitized = raw.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                return ch
            }
            return "_"
        }
        return "home-\(String(sanitized))"
    }

    /// Synchronous `< 1 ms` read for Frame-1 cold boot with zero spinner.
    public static func loadHomeSynchronously(roomName: String, hardwareProfile: String) -> CachedHomeSnapshot? {
        let dir = swrDirectoryURL
        let baseName = fileBaseName(roomName: roomName, hardwareProfile: hardwareProfile)
        let payloadURL = dir.appendingPathComponent("\(baseName).json")
        let metaURL = dir.appendingPathComponent("\(baseName).meta.json")

        guard let payloadData = try? Data(contentsOf: payloadURL),
              let decoded = try? JSONDecoder().decode(TvHomeResponse.self, from: payloadData) else {
            return nil
        }

        let meta: HomeCacheMetadata?
        if let metaData = try? Data(contentsOf: metaURL) {
            meta = try? JSONDecoder().decode(HomeCacheMetadata.self, from: metaData)
        } else {
            meta = nil
        }

        return CachedHomeSnapshot(
            etag: meta?.etag,
            savedAt: meta?.savedAt ?? Date.distantPast,
            payload: decoded
        )
    }

    public static func loadHomeAsync(roomName: String, hardwareProfile: String) async -> CachedHomeSnapshot? {
        await Task.detached(priority: .userInitiated) {
            loadHomeSynchronously(roomName: roomName, hardwareProfile: hardwareProfile)
        }.value
    }

    public static func saveHomeInBackground(
        rawPayloadData: Data,
        etag: String?,
        roomName: String,
        hardwareProfile: String
    ) {
        let dir = swrDirectoryURL
        let baseName = fileBaseName(roomName: roomName, hardwareProfile: hardwareProfile)
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let payloadURL = dir.appendingPathComponent("\(baseName).json")
            let metaURL = dir.appendingPathComponent("\(baseName).meta.json")

            try? rawPayloadData.write(to: payloadURL, options: .atomic)
            let meta = HomeCacheMetadata(etag: etag, savedAt: Date())
            if let encodedMeta = try? JSONEncoder().encode(meta) {
                try? encodedMeta.write(to: metaURL, options: .atomic)
            }
        }
    }

    public static func diskUsageBytes() -> Int64 {
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

    public static func clearAll() {
        try? FileManager.default.removeItem(at: swrDirectoryURL)
    }
}
