import Foundation
import AetherBridge

struct PendingStopSnapshot {
    let client: LunaCoreClient?
    let sessionId: String?
    let resolveId: String?
    let cancelItemId: String?
    let cancelPrepareToken: String?
    let inflightPrepareTask: Task<TvPrepareResponse?, Never>?
    let finalPos: Double
    let finalDur: Double
    let isCompleted: Bool
    let itemId: String?
    let mediaType: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let subtitleDelayMs: Int
}

private actor ResolveFirstEventLatch {
    private(set) var received = false

    func markReceived() {
        received = true
    }
}

/// Stateless WebSocket/HTTP resolve and asynchronous teardown-receipt helper
/// supporting `PlayerSessionController` while keeping every file `<= 420 LOC`.
@MainActor
enum PlayerResolvePipeline {
    static func extractResolvedSession(
        status: Int,
        startRes: TvResolveStartResponse,
        client: LunaCoreClient,
        onResolveIdChanged: (String?) -> Void,
        onProgress: @escaping @MainActor (TvResolveSocketEvent) -> Void
    ) async throws -> TvPlaybackSession {
        if status == 200, let immediate = startRes.playbackSession {
            onResolveIdChanged(nil)
            return immediate
        }
        if let wsPath = startRes.wsPath {
            onResolveIdChanged(startRes.resolveId)
            let resolved = try await awaitWebSocketResolution(
                wsPath: wsPath,
                resolveId: startRes.resolveId,
                client: client,
                onProgress: onProgress
            )
            onResolveIdChanged(nil)
            return resolved
        }
        onResolveIdChanged(nil)
        throw LunaCoreError.serverMessage(status, startRes.error ?? "Uventet svar ved klargjøring av strøm.")
    }

    static func awaitWebSocketResolution(
        wsPath: String,
        resolveId: String,
        client: LunaCoreClient,
        onProgress: @escaping @MainActor (TvResolveSocketEvent) -> Void
    ) async throws -> TvPlaybackSession {
        let socket = PlaybackResolveSocket(
            baseURL: client.baseURL,
            wsPath: wsPath,
            headers: client.streamHTTPHeaders(),
            allowSelfSignedLanTLS: client.allowSelfSignedLanTLS
        )

        let latch = ResolveFirstEventLatch()
        let streamTask = Task { @MainActor () throws -> TvPlaybackSession? in
            for try await event in socket.events() {
                await latch.markReceived()
                onProgress(event)
                if event.type == "resolve.ready", let readySession = event.playbackSession {
                    return readySession
                }
                if event.type == "resolve.failed" {
                    throw LunaCoreError.serverMessage(502, event.error ?? "Kunne ikke klargjøre strøm.")
                }
            }
            return nil
        }

        let watchdogTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            if await !latch.received {
                streamTask.cancel()
            }
        }

        defer {
            watchdogTask.cancel()
            streamTask.cancel()
        }

        do {
            let ready = try await withTaskCancellationHandler {
                try await streamTask.value
            } onCancel: {
                watchdogTask.cancel()
                streamTask.cancel()
            }
            if let readySession = ready {
                return readySession
            }
        } catch let err as LunaCoreError {
            if case .serverMessage(502, _) = err {
                throw err
            }
            if case .decodingFailed = err {
                throw err
            }
        } catch {
            // Fall through to HTTP snapshot polling if WebSocket stalls or drops
        }

        try Task.checkCancellation()
        return try await pollHttpResolutionFallback(
            resolveId: resolveId,
            client: client,
            onProgress: onProgress
        )
    }

    static func pollHttpResolutionFallback(
        resolveId: String,
        client: LunaCoreClient,
        onProgress: @escaping @MainActor (TvResolveSocketEvent) -> Void
    ) async throws -> TvPlaybackSession {
        let maxAttempts = 248
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 750_000_000)
            }
            let snap = try await client.fetchResolveSnapshot(resolveId: resolveId)
            onProgress(snap)
            if snap.type == "resolve.ready", let readySession = snap.playbackSession {
                return readySession
            }
            if snap.type == "resolve.failed" {
                throw LunaCoreError.serverMessage(502, snap.error ?? "Kunne ikke klargjøre strøm.")
            }
        }
        throw LunaCoreError.serverMessage(504, "Tidsavbrudd under klargjøring av strøm.")
    }

    static func dispatchTeardownNetworkAndReceipt(
        snapshot: PendingStopSnapshot,
        onComplete: (@MainActor @Sendable () -> Void)?,
        onStopReceipt: (@MainActor @Sendable (PlaybackStopReceipt) -> Void)?
    ) {
        if let client = snapshot.client, let sessionId = snapshot.sessionId, !sessionId.isEmpty {
            snapshot.inflightPrepareTask?.cancel()
            let finalPos = snapshot.finalPos
            let finalDur = snapshot.finalDur
            let isCompleted = snapshot.isCompleted
            let cancelResolveId = snapshot.resolveId
            let itemId = snapshot.itemId
            let mediaType = snapshot.mediaType
            let seasonNumber = snapshot.seasonNumber
            let episodeNumber = snapshot.episodeNumber
            let delayMs = snapshot.subtitleDelayMs

            Task.detached {
                if let cancelResolveId, !cancelResolveId.isEmpty {
                    try? await client.cancelInflightPlayback(
                        sessionId: sessionId,
                        resolveId: cancelResolveId
                    )
                }
                let hb = try? await client.sendHeartbeat(
                    sessionId: sessionId,
                    state: "stopped",
                    positionSeconds: finalPos,
                    durationSeconds: finalDur,
                    completed: isCompleted ? true : nil,
                    subtitleDelayMs: delayMs != 0 ? delayMs : nil,
                    qos: nil
                )
                let effectiveCompleted = isCompleted || (hb?.watchCompleted == true)
                let receipt: PlaybackStopReceipt? = if onStopReceipt != nil, let itemId, !itemId.isEmpty {
                    PlaybackStopReceipt(
                        itemId: itemId,
                        mediaType: mediaType,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber,
                        positionSeconds: finalPos,
                        durationSeconds: finalDur,
                        completed: effectiveCompleted,
                        recordedAt: Date()
                    )
                } else {
                    nil
                }
                if receipt != nil || onComplete != nil {
                    await MainActor.run {
                        if let receipt, let onStopReceipt {
                            onStopReceipt(receipt)
                        }
                        onComplete?()
                    }
                }
            }
        } else if let client = snapshot.client,
                  (snapshot.resolveId != nil || snapshot.inflightPrepareTask != nil || snapshot.cancelItemId != nil) {
            let inflightPrep = snapshot.inflightPrepareTask
            inflightPrep?.cancel()
            let cancelResolveId = snapshot.resolveId
            let cancelItemId = snapshot.cancelItemId
            let cancelPrepareToken = snapshot.cancelPrepareToken
            let itemId = snapshot.itemId
            let mediaType = snapshot.mediaType
            let seasonNumber = snapshot.seasonNumber
            let episodeNumber = snapshot.episodeNumber
            let finalPos = snapshot.finalPos
            let finalDur = snapshot.finalDur
            let isCompleted = snapshot.isCompleted

            Task.detached {
                if cancelResolveId != nil || cancelItemId != nil {
                    try? await client.cancelInflightPlayback(
                        resolveId: cancelResolveId,
                        itemId: cancelItemId,
                        prepareToken: cancelPrepareToken
                    )
                }
                if let latePrep = await inflightPrep?.value {
                    if let lateTok = latePrep.playbackSession?.streamToken, lateTok.count >= 8 {
                        EngineLog.unregisterSecret(lateTok)
                    }
                    if let orphanSid = latePrep.playbackSession?.sessionId ?? latePrep.prepareToken,
                       !orphanSid.isEmpty {
                        _ = try? await client.sendHeartbeat(
                            sessionId: orphanSid,
                            state: "stopped",
                            positionSeconds: 0,
                            durationSeconds: 0
                        )
                    }
                }
                let receipt: PlaybackStopReceipt? = if onStopReceipt != nil, let itemId, !itemId.isEmpty {
                    PlaybackStopReceipt(
                        itemId: itemId,
                        mediaType: mediaType,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber,
                        positionSeconds: finalPos,
                        durationSeconds: finalDur,
                        completed: isCompleted,
                        recordedAt: Date()
                    )
                } else {
                    nil
                }
                if receipt != nil || onComplete != nil {
                    await MainActor.run {
                        if let receipt, let onStopReceipt {
                            onStopReceipt(receipt)
                        }
                        onComplete?()
                    }
                }
            }
        } else {
            snapshot.inflightPrepareTask?.cancel()
            if let onStopReceipt, let itemId = snapshot.itemId, !itemId.isEmpty {
                let receipt = PlaybackStopReceipt(
                    itemId: itemId,
                    mediaType: snapshot.mediaType,
                    seasonNumber: snapshot.seasonNumber,
                    episodeNumber: snapshot.episodeNumber,
                    positionSeconds: snapshot.finalPos,
                    durationSeconds: snapshot.finalDur,
                    completed: snapshot.isCompleted,
                    recordedAt: Date()
                )
                onStopReceipt(receipt)
            }
            onComplete?()
        }
    }
}
