import Foundation
import AetherBridge

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
        currentRefreshNonce: Int,
        awaitingPostPlaybackRefresh: Bool
    ) -> DetailReloadAction {
        if !hasLoadedDetail || loadedScopeKey != currentScopeKey {
            return .loadInitial
        }
        if currentRefreshNonce != lastSeenRefreshNonce {
            return .reloadPreservingSeason
        }
        if awaitingPostPlaybackRefresh {
            return .skip
        }
        return .skip
    }
}

struct ConsumedPreResolveHandoff: Sendable {
    let prepareToken: String?
    let preparedSession: TvPlaybackSession?
    let inflightPrepareTask: Task<TvPrepareResponse?, Never>?
}

/// Coordinates `0 ms` initial (or `180 ms` debounced) `/api/tv/v1/playback/prepare`
/// + strict NVMe/VFS-only `AetherEngine.prewarm` on detail views without waking archive drives.
@MainActor
final class DetailPreResolveController {
    private(set) var preparedToken: String?
    private(set) var preparedSessionId: String?
    private(set) var preparedPlaybackSession: TvPlaybackSession?
    private(set) var preparedForItemId: String?
    private(set) var preparedStartPosition: Double?
    private(set) var isPreResolvedReady: Bool = false

    private var prewarmedStreamToken: String?
    private var debounceTask: Task<Void, Never>?
    private var inflightNetworkTask: Task<TvPrepareResponse?, Never>?
    private var inflightItemId: String?
    private var inflightStartPosition: Double?
    private var prewarmTask: Task<Void, Never>?

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

    func consumeForPlayback(itemId: String, client: LunaCoreClient?) -> String? {
        consumeHandoffInternal(itemId: itemId, startPosition: nil, enforceStartPosition: false, client: client).prepareToken
    }

    func consumeForPlayback(itemId: String, startPosition: Double?, client: LunaCoreClient?) -> String? {
        consumeHandoffInternal(itemId: itemId, startPosition: startPosition, enforceStartPosition: true, client: client).prepareToken
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
            preparedToken = nil
            preparedSessionId = nil
            preparedPlaybackSession = nil
            preparedForItemId = nil
            preparedStartPosition = nil
            isPreResolvedReady = false
            // Ownership of streamToken masking & session lifecycle transfers to PlayerViewModel.
            prewarmedStreamToken = nil
            cancelAndCleanupInflightPrepare(client: client)
            return ConsumedPreResolveHandoff(
                prepareToken: token,
                preparedSession: session,
                inflightPrepareTask: nil
            )
        }

        // Early click while matching `POST /playback/prepare` is already on the wire:
        // keep the network call alive so LunaCore's `inflightPrepares` coalesces onto it 1:1,
        // and transfer ownership to `PlayerViewModel` so early Back/Menu aborts clean up cleanly.
        if let runningTask = inflightNetworkTask,
           inflightItemId == itemId,
           (!enforceStartPosition || Self.startPositionsMatch(inflightStartPosition, startPosition)) {
            inflightNetworkTask = nil
            inflightItemId = nil
            inflightStartPosition = nil
            if preparedForItemId != nil || preparedSessionId != nil {
                cleanupPreparedSession(client: client)
            }
            return ConsumedPreResolveHandoff(
                prepareToken: nil,
                preparedSession: nil,
                inflightPrepareTask: runningTask
            )
        }

        cancelAndCleanupInflightPrepare(client: client)
        if preparedForItemId != nil || preparedSessionId != nil {
            cleanupPreparedSession(client: client)
        }
        return ConsumedPreResolveHandoff(
            prepareToken: nil,
            preparedSession: nil,
            inflightPrepareTask: nil
        )
    }

    func discardPreparedSession(client: LunaCoreClient?) {
        debounceTask?.cancel()
        debounceTask = nil
        cancelAndCleanupInflightPrepare(client: client)
        cleanupPreparedSession(client: client)
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
        inflightItemId = targetItemId
        inflightStartPosition = startPos

        let netTask = Task<TvPrepareResponse?, Never> {
            guard !Task.isCancelled else { return nil }
            return try? await client.preparePlayback(
                itemId: targetItemId,
                title: apiTitle,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPos
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
            // If `inflightNetworkTask` was handed over to `PlayerViewModel` or superseded,
            // do not overwrite state here; `PlayerViewModel` or `cancelAndCleanupInflightPrepare` owns it.
            guard self.inflightItemId == targetItemId,
                  Self.startPositionsMatch(self.inflightStartPosition, startPos),
                  self.inflightNetworkTask != nil else {
                _ = taskToken
                return
            }

            self.inflightNetworkTask = nil
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
                if let oldTok = self.prewarmedStreamToken, oldTok.count >= 8, oldTok != streamTok {
                    EngineLog.unregisterSecret(oldTok)
                }
                _ = EngineLog.registerSecret(streamTok)
                self.prewarmedStreamToken = streamTok
            }

            // Strictly respect `canClientPrewarmBytes == true` so mechanical archive drives
            // are NEVER spun up merely by opening a detail page!
            if prep.canClientPrewarmBytes == true,
               let relStreamPath = prep.playbackSession?.stream.url,
               let streamURL = client.buildAbsoluteURL(relStreamPath) {
                let headers = client.streamHTTPHeaders()
                let prewarmBudget = DeviceMemoryProfile.current.prewarmByteBudget(
                    availableMemoryBytes: DeviceHardwareCapabilities.availableMemoryBytes()
                )
                guard prewarmBudget > 0 else { return }
                self.prewarmTask?.cancel()
                self.prewarmTask = Task.detached(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    if !AetherEngine.isPrewarmed(url: streamURL) {
                        _ = await AetherEngine.prewarm(
                            url: streamURL,
                            httpHeaders: headers,
                            byteBudget: prewarmBudget
                        )
                    }
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

    private func cancelAndCleanupInflightPrepare(client: LunaCoreClient?) {
        guard let running = inflightNetworkTask else {
            inflightItemId = nil
            inflightStartPosition = nil
            return
        }
        inflightNetworkTask = nil
        inflightItemId = nil
        inflightStartPosition = nil
        running.cancel()
        if let client {
            Task.detached(priority: .utility) {
                if let latePrep = await running.value,
                   let orphanSid = latePrep.playbackSession?.sessionId ?? latePrep.prepareToken,
                   !orphanSid.isEmpty {
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

    private func cleanupPreparedSession(client: LunaCoreClient?) {
        prewarmTask?.cancel()
        prewarmTask = nil
        if let tok = prewarmedStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            prewarmedStreamToken = nil
        }
        if let sid = preparedSessionId ?? preparedToken, !sid.isEmpty, let client {
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
