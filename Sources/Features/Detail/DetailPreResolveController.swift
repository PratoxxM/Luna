import Foundation

public protocol DetailStreamPrewarming: Sendable {
    func registerStreamSecret(_ secret: String)
    func unregisterStreamSecret(_ secret: String)
    func prewarmIfNeeded(url: URL, httpHeaders: [String: String], byteBudget: Int) async
}

public struct NoopDetailStreamPrewarmer: DetailStreamPrewarming {
    public init() {}
    public func registerStreamSecret(_ secret: String) {}
    public func unregisterStreamSecret(_ secret: String) {}
    public func prewarmIfNeeded(url: URL, httpHeaders: [String: String], byteBudget: Int) async {}
}

enum DetailReloadAction: Equatable, Sendable {
    case skip
    case loadInitial
    case reloadPreservingSeason
}

enum DetailReloadPolicy: Sendable {
    static func actionForTaskAppearance(
        hasLoadedDetail: Bool,
        loadedScopeKey: String?,
        currentScopeKey: String,
        lastSeenRefreshNonce: Int,
        currentRefreshNonce: Int
    ) -> DetailReloadAction {
        if !hasLoadedDetail || loadedScopeKey != currentScopeKey {
            return .loadInitial
        }
        if currentRefreshNonce != lastSeenRefreshNonce {
            return .reloadPreservingSeason
        }
        return .skip
    }
}

struct ConsumedPreResolveHandoff: Sendable {
    let prepareToken: String?
    let preparedSession: TvPlaybackSession?
    let inflightPrepareTask: Task<TvPrepareResponse?, Never>?
    let inflightPrepareToken: String?
    let preparedStreamSecretRegistered: Bool

    init(
        prepareToken: String?,
        preparedSession: TvPlaybackSession?,
        inflightPrepareTask: Task<TvPrepareResponse?, Never>?,
        inflightPrepareToken: String?,
        preparedStreamSecretRegistered: Bool = false
    ) {
        self.prepareToken = prepareToken
        self.preparedSession = preparedSession
        self.inflightPrepareTask = inflightPrepareTask
        self.inflightPrepareToken = inflightPrepareToken
        self.preparedStreamSecretRegistered = preparedStreamSecretRegistered
    }
}

/// Coordinates `0 ms` initial (or `180 ms` debounced) `/api/tv/v2/playback/prepare`
/// + strict NVMe/VFS-only stream prewarm on detail views without waking archive drives.
@MainActor
final class DetailPreResolveController {
    private(set) var preparedToken: String?
    private(set) var preparedSessionId: String?
    private(set) var preparedPlaybackSession: TvPlaybackSession?
    private(set) var preparedForItemId: String?
    private(set) var preparedStartPosition: Double?
    private(set) var isPreResolvedReady: Bool = false

    private var prewarmer: any DetailStreamPrewarming
    private var prewarmedStreamToken: String?
    private var debounceTask: Task<Void, Never>?
    private var inflightNetworkTask: Task<TvPrepareResponse?, Never>?
    private var inflightTaskToken: UUID?
    private var inflightItemId: String?
    private var inflightStartPosition: Double?
    private var prewarmTask: Task<Void, Never>?
    private var handedOverSessionIds: [String] = []

    init(prewarmer: any DetailStreamPrewarming = NoopDetailStreamPrewarmer()) {
        self.prewarmer = prewarmer
    }

    func configure(prewarmer: any DetailStreamPrewarming) {
        self.prewarmer = prewarmer
    }

    private func markSessionHandedOver(_ sessionId: String?) {
        guard let sid = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty else {
            return
        }
        if !handedOverSessionIds.contains(sid) {
            handedOverSessionIds.append(sid)
            if handedOverSessionIds.count > 8 {
                handedOverSessionIds.removeFirst(handedOverSessionIds.count - 8)
            }
        }
    }

    private func isHandedOverSession(_ sessionId: String?) -> Bool {
        guard let sid = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty else {
            return false
        }
        return handedOverSessionIds.contains(sid)
    }

    nonisolated static func canReusePreparedSession(
        preparedItemId: String?,
        preparedToken: String?,
        preparedStartPosition: Double?,
        requestedItemId: String,
        requestedStartPosition: Double?
    ) -> Bool {
        guard preparedItemId == requestedItemId,
              let token = preparedToken,
              !token.isEmpty else {
            return false
        }
        return startPositionsMatch(preparedStartPosition, requestedStartPosition)
    }

    nonisolated static func startPositionsMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        let existingStart = max(0, lhs ?? 0)
        let requestedStart = max(0, rhs ?? 0)
        return abs(existingStart - requestedStart) <= 1.0
    }

    func matchingToken(for itemId: String, startPosition: Double?) -> String? {
        guard Self.canReusePreparedSession(
            preparedItemId: preparedForItemId,
            preparedToken: preparedToken,
            preparedStartPosition: preparedStartPosition,
            requestedItemId: itemId,
            requestedStartPosition: startPosition
        ) else {
            return nil
        }
        return preparedToken
    }

    func consumeHandoffForPlayback(
        itemId: String,
        startPosition: Double?,
        client: LunaCoreClient?
    ) -> ConsumedPreResolveHandoff {
        consumeHandoffInternal(
            itemId: itemId,
            startPosition: startPosition,
            enforceStartPosition: true,
            client: client
        )
    }

    private func consumeHandoffInternal(
        itemId: String,
        startPosition: Double?,
        enforceStartPosition: Bool,
        client: LunaCoreClient?
    ) -> ConsumedPreResolveHandoff {
        debounceTask?.cancel()
        debounceTask = nil

        let matchesPreparedItem = preparedForItemId == itemId
        let matchesPreparedStart = !enforceStartPosition || Self.canReusePreparedSession(
            preparedItemId: preparedForItemId,
            preparedToken: preparedToken,
            preparedStartPosition: preparedStartPosition,
            requestedItemId: itemId,
            requestedStartPosition: startPosition
        )

        if matchesPreparedItem, matchesPreparedStart, let token = preparedToken, !token.isEmpty {
            let session = preparedPlaybackSession
            let handedSessionId = session?.sessionId ?? preparedSessionId ?? token
            let didTransferRegisteredSecret = (session?.streamToken.count ?? 0) >= 8
                && prewarmedStreamToken == session?.streamToken
            markSessionHandedOver(handedSessionId)
            preparedToken = nil
            preparedSessionId = nil
            preparedPlaybackSession = nil
            preparedForItemId = nil
            preparedStartPosition = nil
            isPreResolvedReady = false
            // Ownership of streamToken masking & session lifecycle transfers to PlayerViewModel.
            prewarmedStreamToken = nil
            cancelAndCleanupInflightPrepare(excludingSessionId: handedSessionId, client: client)
            return ConsumedPreResolveHandoff(
                prepareToken: token,
                preparedSession: session,
                inflightPrepareTask: nil,
                inflightPrepareToken: nil,
                preparedStreamSecretRegistered: didTransferRegisteredSecret
            )
        }

        // Early click while matching `POST /playback/prepare` is already on the wire:
        // keep the network call alive so LunaCore's `inflightPrepares` coalesces onto it 1:1,
        // and transfer ownership to `PlayerViewModel` so early Back/Menu aborts clean up cleanly.
        if let runningTask = inflightNetworkTask,
           inflightItemId == itemId,
           (!enforceStartPosition || Self.startPositionsMatch(inflightStartPosition, startPosition)) {
            let handedToken = inflightTaskToken?.uuidString
            inflightNetworkTask = nil
            inflightTaskToken = nil
            inflightItemId = nil
            inflightStartPosition = nil
            if preparedForItemId != nil || preparedSessionId != nil {
                cleanupPreparedSession(client: client)
            }
            return ConsumedPreResolveHandoff(
                prepareToken: nil,
                preparedSession: nil,
                inflightPrepareTask: runningTask,
                inflightPrepareToken: handedToken
            )
        }

        cancelAndCleanupInflightPrepare(client: client)
        if preparedForItemId != nil || preparedSessionId != nil {
            cleanupPreparedSession(client: client)
        }
        return ConsumedPreResolveHandoff(
            prepareToken: nil,
            preparedSession: nil,
            inflightPrepareTask: nil,
            inflightPrepareToken: nil
        )
    }

    func discardPreparedSession(
        excludingSessionId: String? = nil,
        client: LunaCoreClient?
    ) {
        markSessionHandedOver(excludingSessionId)
        debounceTask?.cancel()
        debounceTask = nil
        cancelAndCleanupInflightPrepare(excludingSessionId: excludingSessionId, client: client)
        cleanupPreparedSession(excludingSessionId: excludingSessionId, client: client)
    }

    func schedule(
        targetItemId: String,
        title: String,
        seriesTitle: String?,
        startPos: Double?,
        immediate: Bool = false,
        client: LunaCoreClient?
    ) {
        if Self.canReusePreparedSession(
            preparedItemId: preparedForItemId,
            preparedToken: preparedToken,
            preparedStartPosition: preparedStartPosition,
            requestedItemId: targetItemId,
            requestedStartPosition: startPos
        ) {
            return
        }

        if inflightNetworkTask != nil,
           inflightItemId == targetItemId,
           Self.startPositionsMatch(inflightStartPosition, startPos) {
            return
        }

        debounceTask?.cancel()
        debounceTask = nil
        cancelAndCleanupInflightPrepare(client: client)
        if preparedForItemId != nil || preparedSessionId != nil {
            cleanupPreparedSession(client: client)
        }

        guard let client else { return }

        if immediate {
            startNetworkPrepare(
                targetItemId: targetItemId,
                title: title,
                seriesTitle: seriesTitle,
                startPos: startPos,
                client: client
            )
        } else {
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled, let self else { return }
                self.debounceTask = nil
                self.startNetworkPrepare(
                    targetItemId: targetItemId,
                    title: title,
                    seriesTitle: seriesTitle,
                    startPos: startPos,
                    client: client
                )
            }
        }
    }

    private func startNetworkPrepare(
        targetItemId: String,
        title: String,
        seriesTitle: String?,
        startPos: Double?,
        client: LunaCoreClient
    ) {
        let apiTitle = EpisodeTitleFormatter.apiEpisodeTitle(
            rawTitle: title,
            seriesTitle: seriesTitle,
            itemId: targetItemId,
            season: nil,
            episode: nil
        )
        let taskToken = UUID()
        let prepareTokenString = taskToken.uuidString
        inflightTaskToken = taskToken
        inflightItemId = targetItemId
        inflightStartPosition = startPos

        let netTask = Task<TvPrepareResponse?, Never> {
            guard !Task.isCancelled else { return nil }
            return try? await client.preparePlayback(
                itemId: targetItemId,
                title: apiTitle,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPos,
                prepareToken: prepareTokenString
            )
        }
        inflightNetworkTask = netTask

        Task { @MainActor [weak self] in
            let prep = await netTask.value
            guard let self else {
                if let orphanSid = prep?.playbackSession?.sessionId ?? prep?.prepareToken {
                    Self.stopSessionDetached(sessionId: orphanSid, client: client)
                }
                return
            }
            // Enforce exact `taskToken` identity so an `A -> B -> A` cycle never adopts stale `A1`
            // over a newer `A2`, and handed-over tasks never overwrite controller state.
            guard self.inflightTaskToken == taskToken,
                  self.inflightItemId == targetItemId,
                  Self.startPositionsMatch(self.inflightStartPosition, startPos),
                  self.inflightNetworkTask != nil else {
                if let orphanSid = prep?.playbackSession?.sessionId ?? prep?.prepareToken,
                   !orphanSid.isEmpty,
                   self.preparedSessionId != orphanSid,
                   !self.isHandedOverSession(orphanSid) {
                    Self.stopSessionDetached(sessionId: orphanSid, client: client)
                }
                return
            }

            self.inflightNetworkTask = nil
            self.inflightTaskToken = nil
            self.inflightItemId = nil
            self.inflightStartPosition = nil

            guard let prep, let token = prep.prepareToken, !token.isEmpty else {
                return
            }

            self.preparedToken = token
            self.preparedSessionId = prep.playbackSession?.sessionId ?? token
            self.preparedPlaybackSession = prep.playbackSession
            self.preparedForItemId = targetItemId
            self.preparedStartPosition = startPos
            self.isPreResolvedReady = true

            if let streamTok = prep.playbackSession?.streamToken, streamTok.count >= 8 {
                if self.prewarmedStreamToken != streamTok {
                    if let oldTok = self.prewarmedStreamToken, oldTok.count >= 8 {
                        self.prewarmer.unregisterStreamSecret(oldTok)
                    }
                    self.prewarmer.registerStreamSecret(streamTok)
                    self.prewarmedStreamToken = streamTok
                }
            }

            // Strictly respect `canClientPrewarmBytes == true` so mechanical archive drives
            // are NEVER spun up merely by opening a detail page!
            if prep.playbackSession?.stream.canClientPrewarmBytes == true,
               let relStreamPath = prep.playbackSession?.stream.url,
               let streamURL = client.buildAbsoluteURL(relStreamPath) {
                let headers = client.streamHTTPHeaders(for: streamURL)
                let cand = prep.playbackSession?.selectedCandidate
                let sourceLower = (cand?.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let tierLower = (cand?.tier ?? cand?.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let isFastLocal = !sourceLower.contains("easynews")
                    && (tierLower == "ssd" || tierLower == "nvme" || tierLower == "local")
                let prewarmBudget = DeviceMemoryProfile.current.prewarmByteBudget(
                    availableMemoryBytes: DeviceHardwareCapabilities.availableMemoryBytes(),
                    isFastLocalTier: isFastLocal
                )
                guard prewarmBudget > 0 else { return }
                let activePrewarmer = self.prewarmer
                self.prewarmTask?.cancel()
                self.prewarmTask = Task.detached(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    await activePrewarmer.prewarmIfNeeded(
                        url: streamURL,
                        httpHeaders: headers,
                        byteBudget: prewarmBudget
                    )
                }
            }
        }
    }

    func handleDisappear(
        isLaunchingPlayback: Bool,
        isShowingSourcePicker: Bool,
        client: LunaCoreClient?
    ) {
        debounceTask?.cancel()
        debounceTask = nil

        guard !isLaunchingPlayback, !isShowingSourcePicker else { return }
        cancelAndCleanupInflightPrepare(client: client)
        cleanupPreparedSession(client: client)
    }

    private func cancelAndCleanupInflightPrepare(
        excludingSessionId: String? = nil,
        client: LunaCoreClient?
    ) {
        guard let running = inflightNetworkTask else {
            inflightTaskToken = nil
            inflightItemId = nil
            inflightStartPosition = nil
            return
        }
        let cancelledItemId = inflightItemId
        let cancelledToken = inflightTaskToken?.uuidString
        let excludedSid = excludingSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        inflightNetworkTask = nil
        inflightTaskToken = nil
        inflightItemId = nil
        inflightStartPosition = nil
        running.cancel()
        if let client {
            Task.detached(priority: .utility) {
                if let cancelledItemId, (excludedSid == nil || excludedSid?.isEmpty == true) {
                    try? await client.cancelInflightPlayback(
                        itemId: cancelledItemId,
                        prepareToken: cancelledToken
                    )
                }
                if let latePrep = await running.value,
                   let orphanSid = latePrep.playbackSession?.sessionId ?? latePrep.prepareToken,
                   !orphanSid.isEmpty,
                   orphanSid != excludedSid {
                    _ = try? await client.sendHeartbeat(
                        sessionId: orphanSid,
                        state: "stopped",
                        positionSeconds: 0,
                        durationSeconds: 0
                    )
                }
            }
        }
    }

    private func cleanupPreparedSession(
        excludingSessionId: String? = nil,
        client: LunaCoreClient?
    ) {
        prewarmTask?.cancel()
        prewarmTask = nil
        let currentSid = preparedSessionId ?? preparedToken
        let isExcluded = currentSid != nil && currentSid == excludingSessionId
        if let tok = prewarmedStreamToken, tok.count >= 8 {
            if !isExcluded {
                prewarmer.unregisterStreamSecret(tok)
            }
            prewarmedStreamToken = nil
        }
        if let sid = currentSid,
           !sid.isEmpty,
           !isExcluded,
           !isHandedOverSession(sid),
           let client {
            Self.stopSessionDetached(sessionId: sid, client: client)
        }
        preparedToken = nil
        preparedSessionId = nil
        preparedPlaybackSession = nil
        preparedForItemId = nil
        preparedStartPosition = nil
        isPreResolvedReady = false
    }

    static func stopSessionDetached(sessionId: String, client: LunaCoreClient) {
        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: sessionId,
                state: "stopped",
                positionSeconds: 0,
                durationSeconds: 0
            )
        }
    }
}
