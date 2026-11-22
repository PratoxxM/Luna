import Foundation
import Synchronization

public struct CoalescedTaskOutcome<Value: Sendable>: Sendable {
    public let value: Value
    public let wasCoalesced: Bool
}

private final class CoalescedWaiterBox<Value: Sendable>: Sendable {
    private enum State {
        case waiting(CheckedContinuation<Result<Value, any Error>, Never>?)
        case resolved(Result<Value, any Error>)
    }

    private let state = Mutex<State>(.waiting(nil))

    func resolve(_ result: Result<Value, any Error>) {
        let continuation: CheckedContinuation<Result<Value, any Error>, Never>? = state.withLock { current in
            switch current {
            case .waiting(let maybeCont):
                current = .resolved(result)
                return maybeCont
            case .resolved:
                return nil
            }
        }
        continuation?.resume(returning: result)
    }

    func awaitResult() async -> Result<Value, any Error> {
        await withCheckedContinuation { continuation in
            let immediate: Result<Value, any Error>? = state.withLock { current in
                switch current {
                case .waiting:
                    current = .waiting(continuation)
                    return nil
                case .resolved(let result):
                    return result
                }
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }
}

/// Lock-based in-flight task deduplicator with strict per-waiter cancellation isolation.
///
/// Cancelling an individual caller wakes that caller immediately with `CancellationError`
/// while keeping the shared underlying `Task` alive as long as `!waiters.isEmpty`.
/// Only when the final remaining waiter cancels is the underlying `Task` cancelled.
public final class InflightTaskCoalescer<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CoalescedWaiterBox<Value>]
    }

    private let entries = Mutex<[Key: Entry]>([:])

    public init() {}

    public var inflightCount: Int {
        entries.withLock { $0.count }
    }

    public func coalesce(
        key: Key,
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> CoalescedTaskOutcome<Value> {
        try Task.checkCancellation()

        let waiterID = UUID()
        let waiterBox = CoalescedWaiterBox<Value>()

        let (entryID, wasCoalesced): (UUID, Bool) = entries.withLock { map in
            if var existing = map[key] {
                existing.waiters[waiterID] = waiterBox
                map[key] = existing
                return (existing.id, true)
            }

            let newEntryID = UUID()
            let created = Task.detached(priority: priority) { [weak self] in
                let result: Result<Value, any Error>
                do {
                    let output = try await operation()
                    result = .success(output)
                } catch {
                    result = .failure(error)
                }
                self?.completeEntry(key: key, entryID: newEntryID, result: result)
            }
            map[key] = Entry(id: newEntryID, task: created, waiters: [waiterID: waiterBox])
            return (newEntryID, false)
        }

        let outcome = await withTaskCancellationHandler {
            await waiterBox.awaitResult()
        } onCancel: {
            self.cancelWaiter(waiterID, key: key, entryID: entryID)
        }

        let finalValue = try outcome.get()
        try Task.checkCancellation()
        return CoalescedTaskOutcome(value: finalValue, wasCoalesced: wasCoalesced)
    }

    public func coalesceNonThrowing(
        key: Key,
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async -> Value
    ) async -> CoalescedTaskOutcome<Value>? {
        guard !Task.isCancelled else { return nil }
        return try? await coalesce(key: key, priority: priority) {
            await operation()
        }
    }

    public func cancelAll() {
        let extracted: [(tasks: Task<Void, Never>, boxes: [CoalescedWaiterBox<Value>])] = entries.withLock { map in
            let snapshot = map.values.map { ($0.task, Array($0.waiters.values)) }
            map.removeAll()
            return snapshot
        }
        for item in extracted {
            item.tasks.cancel()
            for box in item.boxes {
                box.resolve(.failure(CancellationError()))
            }
        }
    }

    private func completeEntry(key: Key, entryID: UUID, result: Result<Value, any Error>) {
        let boxes: [CoalescedWaiterBox<Value>] = entries.withLock { map in
            guard let entry = map[key], entry.id == entryID else { return [] }
            map.removeValue(forKey: key)
            return Array(entry.waiters.values)
        }
        for box in boxes {
            box.resolve(result)
        }
    }

    private func cancelWaiter(_ waiterID: UUID, key: Key, entryID: UUID) {
        let cancellation: (box: CoalescedWaiterBox<Value>?, taskToCancel: Task<Void, Never>?) = entries.withLock { map in
            guard var entry = map[key], entry.id == entryID else { return (nil, nil) }
            guard let removedBox = entry.waiters.removeValue(forKey: waiterID) else { return (nil, nil) }
            if entry.waiters.isEmpty {
                map.removeValue(forKey: key)
                return (removedBox, entry.task)
            }
            map[key] = entry
            return (removedBox, nil)
        }
        cancellation.taskToCancel?.cancel()
        cancellation.box?.resolve(.failure(CancellationError()))
    }
}

/// Bounded `@MainActor` LRU snapshot cache shared across catalog, library, and item detail views.
@MainActor
public final class BoundedLRUMemoryCache<Value> {
    public let maxEntries: Int
    private var entries: [String: Value] = [:]
    private var order: [String] = []

    public init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    public var entryCount: Int { entries.count }

    public func snapshot(for key: String) -> Value? {
        guard let hit = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    public func store(_ snapshot: Value, for key: String) {
        entries[key] = snapshot
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    public func removeValue(for key: String) {
        if entries.removeValue(forKey: key) != nil {
            order.removeAll { $0 == key }
        }
    }

    public func removeWhere(_ predicate: (String, Value) -> Bool) {
        var keysToRemove: Set<String> = []
        for (key, value) in entries where predicate(key, value) {
            keysToRemove.insert(key)
        }
        guard !keysToRemove.isEmpty else { return }
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
        order.removeAll { keysToRemove.contains($0) }
    }

    public func clear() {
        entries.removeAll()
        order.removeAll()
    }
}

public struct ItemDetailSnapshot: Sendable {
    public var detail: TvItemDetail
    public var episodesBySeason: [Int: [TvEpisodeCard]]
    public var fetchedAt: Date
    public var refreshNonce: Int

    public init(
        detail: TvItemDetail,
        episodesBySeason: [Int: [TvEpisodeCard]] = [:],
        fetchedAt: Date = Date(),
        refreshNonce: Int = 0
    ) {
        self.detail = detail
        self.episodesBySeason = episodesBySeason
        self.fetchedAt = fetchedAt
        self.refreshNonce = refreshNonce
    }
}

/// Adaptive `@MainActor` LRU cache for `TvItemDetail` + loaded season episodes,
/// with immediate targeted invalidation on title/episode mutations and playback completion.
@MainActor
public enum ItemDetailMemoryCache {
    public static let shared = BoundedLRUMemoryCache<ItemDetailSnapshot>(
        maxEntries: DeviceMemoryProfile.current.itemDetailCacheMaxEntries
    )

    public static func makeKey(
        baseURL: URL?,
        mediaType: String,
        itemId: String,
        roomName: String,
        hardwareProfile: String
    ) -> String {
        "\(baseURL?.absoluteString ?? "")|\(mediaType)|\(itemId)|\(roomName)|\(hardwareProfile)"
    }

    public static func invalidate(itemId: String? = nil, tmdbId: Int? = nil) {
        let resolvedTmdb: Int? = tmdbId ?? extractTmdbId(from: itemId)
        let normalizedItemId = itemId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedItemId.isEmpty || resolvedTmdb != nil else {
            shared.clear()
            return
        }
        shared.removeWhere { key, snapshot in
            if !normalizedItemId.isEmpty {
                if snapshot.detail.itemId == normalizedItemId || key.contains("|\(normalizedItemId)|") {
                    return true
                }
            }
            if let resolvedTmdb {
                if snapshot.detail.ids.tmdb == resolvedTmdb
                    || key.contains(":tmdb:\(resolvedTmdb)")
                    || key.contains("|\(resolvedTmdb)|") {
                    return true
                }
            }
            return false
        }
    }

    private nonisolated static func extractTmdbId(from itemId: String?) -> Int? {
        guard let raw = itemId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let parts = raw.split(separator: ":")
        if let idx = parts.firstIndex(of: "tmdb"), idx + 1 < parts.count, let parsed = Int(parts[idx + 1]) {
            return parsed
        }
        return Int(raw)
    }
}

extension FileManager {
    public static func allocatedDirectoryBytes(at directoryURL: URL) -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
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
}
