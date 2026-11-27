import Foundation
import ImageIO
import CoreGraphics
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

/// Off-main-thread WebP/JPEG/PNG artwork loader, GPU-ready bitmap cache, and adaptive NVMe disk cache.
public actor ArtworkPipeline {
    public static let shared = ArtworkPipeline()

    public nonisolated static let didPurgeMemoryNotification = Notification.Name("LunaArtworkPipelineDidPurgeMemory")
    public nonisolated static let didExitPlaybackMemoryModeNotification = Notification.Name("LunaArtworkPipelineDidExitPlaybackMemoryMode")

    private final class DecodeWaiterBox: Sendable {
        private enum Resolution: Sendable {
            case waiting(CheckedContinuation<Bool, Never>?)
            case resolved(Bool)
        }

        let key: String
        private let state = Mutex<Resolution>(.waiting(nil))

        init(key: String) {
            self.key = key
        }

        func resolve(_ granted: Bool) {
            let cont: CheckedContinuation<Bool, Never>? = state.withLock { current in
                switch current {
                case .waiting(let maybeCont):
                    current = .resolved(granted)
                    return maybeCont
                case .resolved:
                    return nil
                }
            }
            cont?.resume(returning: granted)
        }

        func awaitPermit() async -> Bool {
            await withCheckedContinuation { continuation in
                let immediate: Bool? = state.withLock { current in
                    switch current {
                    case .waiting:
                        current = .waiting(continuation)
                        return nil
                    case .resolved(let granted):
                        return granted
                    }
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                }
            }
        }
    }

    private struct DecodePermitState: Sendable {
        var activeDecodeCount: Int = 0
        var interactiveWaiters: [DecodeWaiterBox] = []
        var prefetchWaiters: [DecodeWaiterBox] = []
    }

    private nonisolated let ramCache = ThreadSafeImageMemoryCache(
        totalCostLimit: DeviceMemoryProfile.current.artworkMemoryBytes,
        countLimit: DeviceMemoryProfile.current.artworkMemoryCountLimit
    )
    private nonisolated let diskTouchTracker = DiskTouchTracker()
    private nonisolated let inflightImages = InflightTaskCoalescer<String, CGImage?>()
    private nonisolated let inflightRawFetches = InflightTaskCoalescer<String, RawDataFetchResult?>()
    private nonisolated let isPlaybackActiveFlag = Mutex(false)
    private static let memoryEpochCounter = Mutex<UInt64>(0)
    private nonisolated let activePrefetchTasks = Mutex<[UUID: Task<Void, Never>]>([:])

    public nonisolated var isPlaybackActive: Bool {
        isPlaybackActiveFlag.withLock { $0 }
    }

    public nonisolated var memoryEpoch: UInt64 {
        Self.memoryEpochCounter.withLock { $0 }
    }

    internal final class DiskKeyLease: Sendable {
        private let coordinator: DiskMutationCoordinator
        private let key: String
        private let clearEpoch: UInt64
        fileprivate init(coordinator: DiskMutationCoordinator, key: String, clearEpoch: UInt64) {
            self.coordinator = coordinator; self.key = key; self.clearEpoch = clearEpoch
        }
        deinit { coordinator.unpin(key: key, clearEpoch: clearEpoch) }
    }

    internal final class DiskMutationCoordinator: Sendable {
        struct State: Sendable {
            var clearEpoch: UInt64 = 0, minFloor: UInt64 = 0, nextGeneration: UInt64 = 1, nextSequence: UInt64 = 1
            var keyGenerations: [String: (generation: UInt64, sequence: UInt64)] = [:]
            var activeCounts: [String: Int] = [:]

            mutating func generation(for key: String) -> UInt64 { keyGenerations[key]?.generation ?? minFloor }

            private mutating func evictIdleKeysIfNeeded(excluding currentKey: String) {
                guard keyGenerations.count >= 2048 else { return }
                let idle = keyGenerations.filter { activeCounts[$0.key] == nil && $0.key != currentKey }
                    .sorted { $0.value.sequence < $1.value.sequence }
                let removeCount = min(idle.count, max(512, keyGenerations.count - 1024))
                guard removeCount > 0 else { return }
                for item in idle.prefix(removeCount) { keyGenerations.removeValue(forKey: item.key) }
                minFloor = nextGeneration; nextGeneration &+= 1
            }

            mutating func pin(key: String) -> (clearEpoch: UInt64, generation: UInt64) {
                let seq = nextSequence; nextSequence &+= 1
                if keyGenerations[key] == nil { evictIdleKeysIfNeeded(excluding: key) }
                let gen = keyGenerations[key]?.generation ?? minFloor
                keyGenerations[key] = (gen, seq)
                activeCounts[key, default: 0] += 1
                return (clearEpoch, gen)
            }

            @discardableResult
            mutating func advanceGeneration(for key: String) -> UInt64 {
                evictIdleKeysIfNeeded(excluding: key)
                let gen = nextGeneration; nextGeneration &+= 1
                let seq = nextSequence; nextSequence &+= 1
                keyGenerations[key] = (gen, seq)
                return gen
            }
        }

        private let state = Mutex(State())
        var trackedKeyCount: Int { state.withLock { $0.keyGenerations.count } }
        func generation(for key: String) -> UInt64 { state.withLock { $0.generation(for: key) } }
        func withLock<R>(_ body: (inout State) -> R) -> R { state.withLock { body(&$0) } }
        @discardableResult func advanceGeneration(for key: String) -> UInt64 { state.withLock { $0.advanceGeneration(for: key) } }

        func pin(key: String) -> (clearEpoch: UInt64, generation: UInt64, lease: DiskKeyLease) {
            let (epoch, gen) = state.withLock { $0.pin(key: key) }
            return (epoch, gen, DiskKeyLease(coordinator: self, key: key, clearEpoch: epoch))
        }

        fileprivate func unpin(key: String, clearEpoch expectedEpoch: UInt64) {
            state.withLock { s in
                guard s.clearEpoch == expectedEpoch, let count = s.activeCounts[key] else { return }
                if count <= 1 { s.activeCounts.removeValue(forKey: key) } else { s.activeCounts[key] = count - 1 }
            }
        }

        func reset(after body: () -> Void) {
            state.withLock { s in
                s.clearEpoch &+= 1; s.minFloor = 0; s.nextGeneration = 1; s.nextSequence = 1
                s.keyGenerations.removeAll(keepingCapacity: false); s.activeCounts.removeAll(keepingCapacity: false)
                body()
            }
        }
    }

    private struct RawDataFetchResult: Sendable {
        let data: Data
        let fromDisk: Bool
        let clearEpoch: UInt64
        let generation: UInt64
        let lease: DiskKeyLease
    }

    private nonisolated let writesSinceLastTrimCounter = Mutex<Int>(0)
    private nonisolated let cacheDirInitLock = Mutex<Bool>(false)
    internal nonisolated let diskMutation = DiskMutationCoordinator()

    private nonisolated let maxConcurrentDecodes = DeviceMemoryProfile.current.maxConcurrentDecodes
    private nonisolated let trimWriteInterval = DeviceMemoryProfile.current.artworkDiskTrimWriteInterval

    public nonisolated static var defaultDiskMaxBytes: Int64 {
        DeviceMemoryProfile.current.artworkDiskMaxBytes
    }

    private nonisolated let decodePermitState = Mutex(DecodePermitState())

    private init() {
        let cache = self.ramCache
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil,
            queue: nil
        ) { _ in
            cache.removeAll()
            BlurHashDecoder.clearCache()
            ArtworkPipeline.memoryEpochCounter.withLock { $0 &+= 1 }
            Task { @MainActor in
                NotificationCenter.default.post(name: ArtworkPipeline.didPurgeMemoryNotification, object: nil)
            }
        }
    }

    private nonisolated func recordAndPostMemoryPurge() {
        Self.memoryEpochCounter.withLock { $0 &+= 1 }
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.didPurgeMemoryNotification, object: nil)
        }
    }

    public nonisolated static func rawIdentity(for url: URL) -> String {
        ArtworkSubjectKey.rawIdentity(for: url)
    }

    public nonisolated static func canonicalSubjectIdentity(for url: URL) -> String {
        ArtworkSubjectKey.canonicalSubjectIdentity(for: url)
    }

    public nonisolated static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        ArtworkSubjectKey.cacheKey(for: url, maxPixelSize: maxPixelSize)
    }

    public nonisolated func memoryCachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        return ramCache.image(forKey: key)
    }

    private nonisolated static let candidateCachedPixelSizes: [Int] = ArtworkSubjectKey.candidateCachedPixelSizes

    /// Looks up any already-decoded bitmap in RAM for `url` (checking exact `preferredMaxPixelSize`,
    /// canonical size-agnostic subject match, and standard pixel buckets) in `0 ms`.
    public nonisolated func anyMemoryCachedImage(
        for url: URL,
        preferredMaxPixelSize: Int
    ) -> (key: String, image: CGImage)? {
        let preferredKey = Self.cacheKey(for: url, maxPixelSize: preferredMaxPixelSize)
        if let exact = ramCache.image(forKey: preferredKey) {
            return (preferredKey, exact)
        }
        let subjectKey = Self.canonicalSubjectIdentity(for: url)
        if let subjectHit = ramCache.bestImage(forSubjectKey: subjectKey) {
            return (subjectKey, subjectHit)
        }
        for bucket in Self.candidateCachedPixelSizes where bucket != preferredMaxPixelSize {
            let key = Self.cacheKey(for: url, maxPixelSize: bucket)
            if let hit = ramCache.image(forKey: key) {
                return (key, hit)
            }
        }
        return nil
    }

    internal nonisolated func insertMemoryCachedImage(_ image: CGImage, url: URL, maxPixelSize: Int) {
        ramCache.insert(
            image,
            forKey: Self.cacheKey(for: url, maxPixelSize: maxPixelSize),
            subjectKey: Self.canonicalSubjectIdentity(for: url)
        )
    }

    public nonisolated func loadImage(
        url: URL,
        maxPixelSize: Int,
        client: LunaCoreClient?,
        priority: ArtworkLoadPriority = .interactive
    ) async -> CGImage? {
        let key = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let memHit = ramCache.image(forKey: key) {
            return memHit
        }

        let taskPriority: TaskPriority = priority == .interactive ? .userInitiated : .utility
        let rawKey = Self.rawIdentity(for: url)
        let subjectKey = Self.canonicalSubjectIdentity(for: url)
        let ramCacheRef = self.ramCache
        if priority == .interactive {
            promotePrefetchWaiterIfNeeded(forKey: key)
        }

        guard let outcome = await inflightImages.coalesceNonThrowing(
            key: key,
            priority: taskPriority,
            operation: { [self] () -> CGImage? in
                if let memHit = ramCacheRef.image(forKey: key) {
                    return memHit
                }
                guard !Task.isCancelled,
                      let rawResult = await self.acquireRawData(
                          url: url,
                          rawKey: rawKey,
                          client: client,
                          priority: taskPriority
                      ),
                      !Task.isCancelled else {
                    return nil
                }
                guard await self.acquireDecodePermit(key: key, priority: priority) else {
                    return nil
                }
                var didAttemptDecode = false
                let decoded: CGImage?
                if Task.isCancelled {
                    decoded = nil
                } else {
                    didAttemptDecode = true
                    decoded = await Self.downsampleAndDecode(data: rawResult.data, maxPixelSize: maxPixelSize)
                }
                self.releaseDecodePermit()
                guard let decoded else {
                    if didAttemptDecode && !Task.isCancelled {
                        withExtendedLifetime(rawResult.lease) {
                            self.evictCorruptDiskFile(
                                at: Self.diskFileURL(for: url),
                                rawKey: rawKey,
                                clearEpoch: rawResult.clearEpoch,
                                expectedGeneration: rawResult.generation
                            )
                        }
                    }
                    return nil
                }
                ramCacheRef.insert(decoded, forKey: key, subjectKey: subjectKey)
                if !rawResult.fromDisk {
                    self.scheduleDiskWrite(
                        data: rawResult.data,
                        to: Self.diskFileURL(for: url),
                        rawKey: rawKey,
                        clearEpoch: rawResult.clearEpoch,
                        expectedGeneration: rawResult.generation,
                        lease: rawResult.lease
                    )
                }
                return decoded
            }
        ) else {
            return nil
        }
        return outcome.value
    }

    /// Viewport lookahead prefetching for horizontal shelves and 6-column poster grids.
    /// Automatically pauses during active video playback and yields decode permits to interactive views.
    public nonisolated func prefetchUpcomingCards(
        in cards: [TvMediaCard],
        afterIndex index: Int,
        isBackdrop: Bool = false,
        maxLookahead: Int? = nil,
        client: LunaCoreClient?
    ) {
        guard let client,
              !(isPlaybackActiveFlag.withLock { $0 }),
              index >= 0,
              index + 1 < cards.count else {
            return
        }
        let strideStep = isBackdrop ? 2 : 3
        guard index == 0 || index % strideStep == 0 else { return }

        let window = min(maxLookahead ?? DeviceMemoryProfile.current.scrollPrefetchCardWindow, DeviceMemoryProfile.current.scrollPrefetchCardWindow)
        guard window > 0 else { return }
        let targetPixelSize = isBackdrop
            ? ArtworkDecodeTargets.backdropCardMaxPixelSize
            : ArtworkDecodeTargets.posterCardMaxPixelSize
        let urls = ArtworkDiskCache.prefetchArtworkURLs(
            in: cards,
            afterIndex: index,
            isBackdrop: isBackdrop,
            window: window,
            client: client
        )
        prefetchImages(urls: urls, maxPixelSize: targetPixelSize, client: client)
    }

    public nonisolated func prefetchImages(
        urls: [URL],
        maxPixelSize: Int,
        client: LunaCoreClient?
    ) {
        guard !urls.isEmpty, !(isPlaybackActiveFlag.withLock { $0 }) else { return }
        let missingURLs = urls.filter { memoryCachedImage(for: $0, maxPixelSize: maxPixelSize) == nil }
        guard !missingURLs.isEmpty else { return }

        let taskID = UUID()
        let created = Task.detached(priority: .utility) { [self] in
            defer {
                _ = self.activePrefetchTasks.withLock { $0.removeValue(forKey: taskID) }
            }
            let floorBytes = DeviceMemoryProfile.current.playbackMemoryShedFloorBytes
            for url in missingURLs {
                guard !Task.isCancelled, !(self.isPlaybackActiveFlag.withLock { $0 }) else {
                    return
                }
                if self.memoryCachedImage(for: url, maxPixelSize: maxPixelSize) != nil {
                    continue
                }
                if DeviceHardwareCapabilities.availableMemoryBytes() > floorBytes {
                    _ = await self.loadImage(
                        url: url,
                        maxPixelSize: maxPixelSize,
                        client: client,
                        priority: .prefetch
                    )
                } else {
                    let rawKey = Self.rawIdentity(for: url)
                    if let rawResult = await self.acquireRawData(url: url, rawKey: rawKey, client: client, priority: .utility),
                       !rawResult.fromDisk {
                        let permitKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
                        if await self.acquireDecodePermit(key: permitKey, priority: .prefetch) {
                            let isValid = !Task.isCancelled && Self.isDecodableImagePayload(rawResult.data)
                            self.releaseDecodePermit()
                            let diskURL = Self.diskFileURL(for: url)
                            if isValid {
                                self.scheduleDiskWrite(
                                    data: rawResult.data, to: diskURL, rawKey: rawKey,
                                    clearEpoch: rawResult.clearEpoch, expectedGeneration: rawResult.generation, lease: rawResult.lease
                                )
                            } else if !Task.isCancelled {
                                withExtendedLifetime(rawResult.lease) {
                                    self.evictCorruptDiskFile(
                                        at: diskURL, rawKey: rawKey,
                                        clearEpoch: rawResult.clearEpoch, expectedGeneration: rawResult.generation
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        activePrefetchTasks.withLock { map in
            if map.count >= 8 {
                let oldest = Array(map.values)
                map.removeAll(keepingCapacity: true)
                for task in oldest { task.cancel() }
            }
            map[taskID] = created
        }
    }

    /// Cancels background artwork prefetches and proactively frees RAM bitmaps before heavy `.softwareHost`
    /// (4K Dolby Vision Profile 7 FEL / AV1) frame pools allocate when headroom is tight, while keeping
    /// any active curtain backdrop/logo bitmaps resident (`0 ms` curtain reveal).
    public nonisolated func enterPlaybackMemoryMode(
        isHeavySoftwareStream: Bool,
        preservedURLs: [URL] = []
    ) {
        isPlaybackActiveFlag.withLock { $0 = true }
        cancelAllPrefetchTasks()

        let profile = DeviceMemoryProfile.current
        let available = DeviceHardwareCapabilities.availableMemoryBytes()
        let shouldShed = available < profile.playbackMemoryShedFloorBytes
            || (isHeavySoftwareStream && profile.tier == .standard)
        if shouldShed {
            var preservedEntries: [(key: String, subjectKey: String, image: CGImage)] = []
            for url in preservedURLs {
                let subjectKey = Self.canonicalSubjectIdentity(for: url)
                var matchedForURL = false
                for px in Self.candidateCachedPixelSizes {
                    let key = Self.cacheKey(for: url, maxPixelSize: px)
                    if let img = ramCache.image(forKey: key) {
                        preservedEntries.append((key: key, subjectKey: subjectKey, image: img))
                        matchedForURL = true
                    }
                }
                if !matchedForURL, let best = ramCache.bestImage(forSubjectKey: subjectKey) {
                    let fallbackPx = max(best.width, best.height)
                    let key = Self.cacheKey(for: url, maxPixelSize: fallbackPx)
                    preservedEntries.append((key: key, subjectKey: subjectKey, image: best))
                }
            }
            ramCache.removeAll()
            for entry in preservedEntries {
                ramCache.insert(entry.image, forKey: entry.key, subjectKey: entry.subjectKey)
            }
            BlurHashDecoder.clearCache()
            recordAndPostMemoryPurge()
        }
    }

    public nonisolated func exitPlaybackMemoryMode() {
        isPlaybackActiveFlag.withLock { $0 = false }
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.didExitPlaybackMemoryModeNotification, object: nil)
        }
    }

    public nonisolated func handleSceneDidEnterBackground() {
        cancelAllPrefetchTasks()
        ramCache.removeAll()
        BlurHashDecoder.clearCache()
        recordAndPostMemoryPurge()
    }

    private nonisolated func cancelAllPrefetchTasks() {
        let tasks = activePrefetchTasks.withLock { map -> [Task<Void, Never>] in
            let running = Array(map.values)
            map.removeAll()
            return running
        }
        for task in tasks {
            task.cancel()
        }
    }

    private nonisolated func acquireRawData(
        url: URL,
        rawKey: String,
        client: LunaCoreClient?,
        priority: TaskPriority = .userInitiated
    ) async -> RawDataFetchResult? {
        let diskFileURL = Self.diskFileURL(for: url)
        let externalSession = LunaCoreSessionPool.shared.externalArtworkSession()
        let diskTouchTracker = self.diskTouchTracker

        guard let outcome = await inflightRawFetches.coalesceNonThrowing(
            key: rawKey,
            priority: priority,
            operation: { [self] () -> RawDataFetchResult? in
                guard !Task.isCancelled else { return nil }
                do {
                    let diskPin = self.diskMutation.pin(key: rawKey)
                    if let diskData = try? Data(contentsOf: diskFileURL), !diskData.isEmpty {
                        ArtworkDiskCache.touchDiskFileIfNeeded(at: diskFileURL, key: rawKey, tracker: diskTouchTracker)
                        return RawDataFetchResult(
                            data: diskData, fromDisk: true,
                            clearEpoch: diskPin.clearEpoch, generation: diskPin.generation, lease: diskPin.lease
                        )
                    }
                }

                guard !Task.isCancelled else { return nil }
                let fetchedData: Data?
                if let client {
                    fetchedData = (try? await client.fetchRawImageData(from: url))?.0
                } else if let (raw, resp) = try? await externalSession.data(from: url) {
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    fetchedData = status < 400 ? raw : nil
                } else {
                    fetchedData = nil
                }
                guard !Task.isCancelled, let data = fetchedData, !data.isEmpty else {
                    return nil
                }

                let netPin = self.diskMutation.pin(key: rawKey)
                return RawDataFetchResult(
                    data: data, fromDisk: false,
                    clearEpoch: netPin.clearEpoch, generation: netPin.generation, lease: netPin.lease
                )
            }
        ) else {
            return nil
        }
        return outcome.value
    }

    internal nonisolated func scheduleDiskWrite(
        data: Data,
        to diskFileURL: URL,
        rawKey: String,
        clearEpoch: UInt64,
        expectedGeneration: UInt64,
        lease: DiskKeyLease
    ) {
        let diskTouchTracker = self.diskTouchTracker
        Task.detached(priority: .utility) { [self, diskFileURL, data, rawKey, diskTouchTracker, clearEpoch, expectedGeneration, lease] in
            let didWrite = withExtendedLifetime(lease) {
                self.diskMutation.withLock { state -> Bool in
                    guard state.clearEpoch == clearEpoch, state.generation(for: rawKey) == expectedGeneration else {
                        return false
                    }
                    self.ensureCacheDirectoryIfNeeded()
                    do {
                        try data.write(to: diskFileURL, options: .atomic)
                        _ = state.advanceGeneration(for: rawKey)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            if didWrite {
                diskTouchTracker.recordWrite(rawKey, now: Date().timeIntervalSinceReferenceDate)
                self.recordDiskWriteCompleted()
            }
        }
    }

    internal nonisolated func evictCorruptDiskFile(
        at diskFileURL: URL, rawKey: String, clearEpoch: UInt64, expectedGeneration: UInt64
    ) {
        diskMutation.withLock { state in
            guard state.clearEpoch == clearEpoch, state.generation(for: rawKey) == expectedGeneration else { return }
            _ = state.advanceGeneration(for: rawKey)
            let fm = FileManager.default
            guard fm.fileExists(atPath: diskFileURL.path) else { return }
            try? fm.removeItem(at: diskFileURL) // Best-effort corrupt cache eviction
        }
    }

    internal nonisolated static func isDecodableImagePayload(_ data: Data) -> Bool {
        decodeThumbnail(from: data, maxPixelSize: 128, cacheImmediately: false) != nil
    }

    private nonisolated func ensureCacheDirectoryIfNeeded() {
        cacheDirInitLock.withLock { didEnsure in
            guard !didEnsure else { return }
            ArtworkDiskCache.migrateLegacyCacheDirectoryIfNeeded()
            try? FileManager.default.createDirectory(at: Self.imageCacheDirectoryURL, withIntermediateDirectories: true)
            didEnsure = true
        }
    }

    private nonisolated func promotePrefetchWaiterIfNeeded(forKey key: String) {
        decodePermitState.withLock { s in
            if let idx = s.prefetchWaiters.firstIndex(where: { $0.key == key }) {
                let promoted = s.prefetchWaiters.remove(at: idx)
                s.interactiveWaiters.append(promoted)
            }
        }
    }

    private nonisolated func acquireDecodePermit(key: String, priority: ArtworkLoadPriority) async -> Bool {
        let box = DecodeWaiterBox(key: key)
        enum EnqueueOutcome {
            case acquired
            case cancelledBeforeQueue
            case queued
        }
        let outcome: EnqueueOutcome = decodePermitState.withLock { s in
            if Task.isCancelled {
                return .cancelledBeforeQueue
            }
            if s.activeDecodeCount < maxConcurrentDecodes {
                s.activeDecodeCount += 1
                return .acquired
            }
            switch priority {
            case .interactive:
                s.interactiveWaiters.append(box)
            case .prefetch:
                s.prefetchWaiters.append(box)
            }
            return .queued
        }
        switch outcome {
        case .acquired:
            return true
        case .cancelledBeforeQueue:
            return false
        case .queued:
            return await withTaskCancellationHandler {
                await box.awaitPermit()
            } onCancel: {
                self.cancelDecodeWaiter(box)
            }
        }
    }

    private nonisolated func cancelDecodeWaiter(_ box: DecodeWaiterBox) {
        let removed: DecodeWaiterBox? = decodePermitState.withLock { s in
            if let idx = s.interactiveWaiters.firstIndex(where: { $0 === box }) {
                return s.interactiveWaiters.remove(at: idx)
            }
            if let idx = s.prefetchWaiters.firstIndex(where: { $0 === box }) {
                return s.prefetchWaiters.remove(at: idx)
            }
            return nil
        }
        removed?.resolve(false)
    }

    private nonisolated func releaseDecodePermit() {
        let next: DecodeWaiterBox? = decodePermitState.withLock { s in
            if !s.interactiveWaiters.isEmpty {
                return s.interactiveWaiters.removeFirst()
            }
            if !s.prefetchWaiters.isEmpty {
                return s.prefetchWaiters.removeFirst()
            }
            s.activeDecodeCount = max(0, s.activeDecodeCount - 1)
            return nil
        }
        next?.resolve(true)
    }

    private nonisolated func recordDiskWriteCompleted() {
        let shouldTrim = writesSinceLastTrimCounter.withLock { count -> Bool in
            count += 1
            if count >= trimWriteInterval {
                count = 0
                return true
            }
            return false
        }
        if shouldTrim {
            let maxBytes = Self.defaultDiskMaxBytes
            Task.detached(priority: .utility) {
                Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
            }
        }
    }

    public func trimDiskCacheIfNeeded(maxBytes: Int64 = ArtworkPipeline.defaultDiskMaxBytes) {
        Task.detached(priority: .utility) {
            Self.trimDiskCacheSynchronously(maxBytes: maxBytes)
        }
    }

    public func clearAll() {
        cancelAllPrefetchTasks()
        inflightImages.cancelAll()
        inflightRawFetches.cancelAll()
        ramCache.removeAll()
        BlurHashDecoder.clearCache()
        diskTouchTracker.removeAll()
        diskMutation.reset {
            cacheDirInitLock.withLock { $0 = false }
            writesSinceLastTrimCounter.withLock { $0 = 0 }
            try? FileManager.default.removeItem(at: Self.imageCacheDirectoryURL)
        }
    }

    private nonisolated static func decodeThumbnail(
        from data: Data,
        maxPixelSize: Int,
        cacheImmediately: Bool
    ) -> CGImage? {
        guard !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        var effectiveMax = maxPixelSize
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let nativeMax = max(
                (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
                (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            )
            if nativeMax > 0 {
                effectiveMax = max(1, min(effectiveMax, nativeMax))
            }
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: cacheImmediately,
            kCGImageSourceShouldCacheImmediately: cacheImmediately,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: effectiveMax
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary)
    }

    /// Hardware-accelerated ImageIO thumbnail creation & GPU-ready bitmap preparation
    /// on a background worker thread, falling back cleanly to `ImageIO` `CGImage` if
    /// `byPreparingForDisplay()` returns `nil` (grayscale / indexed / special color profiles).
    private nonisolated static func downsampleAndDecode(data: Data, maxPixelSize: Int) async -> CGImage? {
        guard let decoded = decodeThumbnail(from: data, maxPixelSize: max(128, maxPixelSize), cacheImmediately: true) else {
            return nil
        }
        #if canImport(UIKit)
        if let displayReady = await UIImage(cgImage: decoded).byPreparingForDisplay()?.cgImage {
            return displayReady
        }
        #endif
        return decoded
    }
}

extension ArtworkPipeline {
    internal static nonisolated var imageCacheDirectoryURL: URL {
        ArtworkDiskCache.imageCacheDirectoryURL
    }

    public nonisolated static func diskUsageBytesAsync() async -> Int64 {
        await ArtworkDiskCache.diskUsageBytesAsync()
    }

    internal nonisolated static func diskFileURL(for url: URL) -> URL {
        ArtworkDiskCache.diskFileURL(for: url)
    }

    internal nonisolated static func trimDiskCacheSynchronously(maxBytes: Int64) {
        ArtworkDiskCache.trimDiskCacheSynchronously(maxBytes: maxBytes)
    }
}
