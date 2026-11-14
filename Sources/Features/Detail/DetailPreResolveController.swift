import Foundation
import AetherBridge

/// Coordinates debounced 180ms `/api/tv/v1/playback/prepare` + strict NVMe/VFS-only
/// 8 MiB `AetherEngine.prewarm` on detail views without waking mechanical archive drives.
@MainActor
final class DetailPreResolveController: ObservableObject {
    @Published private(set) var preparedToken: String?
    @Published private(set) var preparedSessionId: String?
    @Published private(set) var preparedForItemId: String?
    @Published private(set) var isPreResolvedReady: Bool = false

    private var prewarmedStreamToken: String?
    private var preResolveTask: Task<Void, Never>?
    private var consumedItemId: String?

    func matchingToken(for itemId: String) -> String? {
        guard preparedForItemId == itemId, let tok = preparedToken, !tok.isEmpty else {
            return nil
        }
        return tok
    }

    func consumeForPlayback(itemId: String, client: LunaCoreClient?) -> String? {
        consumedItemId = itemId
        preResolveTask?.cancel()
        preResolveTask = nil

        if preparedForItemId == itemId, let token = preparedToken, !token.isEmpty {
            preparedToken = nil
            preparedSessionId = nil
            preparedForItemId = nil
            isPreResolvedReady = false
            // Ownership of streamToken masking transfers to PlayerViewModel.
            prewarmedStreamToken = nil
            return token
        }

        if preparedForItemId != itemId {
            cleanupPreparedSession(client: client)
        }
        return nil
    }

    func discardPreparedSession(client: LunaCoreClient?) {
        consumedItemId = nil
        preResolveTask?.cancel()
        preResolveTask = nil
        cleanupPreparedSession(client: client)
    }

    func schedule(
        targetItemId: String,
        title: String,
        seriesTitle: String?,
        startPos: Double?,
        client: LunaCoreClient?
    ) {
        if preparedForItemId == targetItemId,
           let existingToken = preparedToken,
           !existingToken.isEmpty {
            return
        }

        consumedItemId = nil
        preResolveTask?.cancel()
        if preparedForItemId != targetItemId {
            cleanupPreparedSession(client: client)
        }

        guard let client else { return }

        preResolveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }

            guard let prep = try? await client.preparePlayback(
                itemId: targetItemId,
                title: title,
                seriesTitle: seriesTitle,
                startPositionSeconds: startPos
            ) else {
                return
            }

            if Task.isCancelled {
                // Keep an in-flight prepared session alive when playback already
                // consumed this itemId so `/playback/resolve` promotes it in < 1 ms.
                if self.consumedItemId != targetItemId,
                   let orphanSid = prep.playbackSession?.sessionId {
                    Self.stopSessionDetached(sessionId: orphanSid, client: client)
                }
                return
            }

            if let token = prep.prepareToken, !token.isEmpty {
                self.preparedToken = token
                self.preparedSessionId = prep.playbackSession?.sessionId
                self.preparedForItemId = targetItemId
                self.isPreResolvedReady = true
            }

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
                Task.detached(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    if !AetherEngine.isPrewarmed(url: streamURL) {
                        _ = await AetherEngine.prewarm(
                            url: streamURL,
                            httpHeaders: headers,
                            byteBudget: 8 * 1024 * 1024
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
        preResolveTask?.cancel()
        preResolveTask = nil

        guard !isLaunchingPlayback, !isShowingSourcePicker else { return }
        cleanupPreparedSession(client: client)
    }

    private func cleanupPreparedSession(client: LunaCoreClient?) {
        if let tok = prewarmedStreamToken, tok.count >= 8 {
            EngineLog.unregisterSecret(tok)
            prewarmedStreamToken = nil
        }
        if let sid = preparedSessionId, let client {
            Self.stopSessionDetached(sessionId: sid, client: client)
        }
        preparedToken = nil
        preparedSessionId = nil
        preparedForItemId = nil
        isPreResolvedReady = false
    }

    private static func stopSessionDetached(sessionId: String, client: LunaCoreClient) {
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
