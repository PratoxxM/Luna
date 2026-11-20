import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlaybackResolveSocket: Sendable {
    public let baseURL: URL
    public let wsPath: String
    public let headers: [String: String]
    public let allowSelfSignedLanTLS: Bool

    public init(
        baseURL: URL,
        wsPath: String,
        headers: [String: String],
        allowSelfSignedLanTLS: Bool
    ) {
        self.baseURL = baseURL
        self.wsPath = wsPath
        self.headers = headers
        self.allowSelfSignedLanTLS = allowSelfSignedLanTLS
    }

    #if !os(Linux)
    public func events() -> AsyncThrowingStream<TvResolveSocketEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let wsURL = Self.makeWebSocketURL(baseURL: baseURL, wsPath: wsPath) else {
                continuation.finish(throwing: LunaCoreError.invalidURL(wsPath))
                return
            }

            let urlSession = LunaCoreSessionPool.shared.webSocketSession(
                for: baseURL,
                allowSelfSignedLanTLS: allowSelfSignedLanTLS
            )

            var request = URLRequest(url: wsURL)
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }

            let wsTask = urlSession.webSocketTask(with: request)
            wsTask.resume()

            let readerTask = Task {
                defer {
                    wsTask.cancel(with: .goingAway, reason: nil)
                }
                while !Task.isCancelled {
                    do {
                        let msg = try await wsTask.receive()
                        guard let event = try Self.parseMessage(msg) else {
                            continue
                        }
                        continuation.yield(event)
                        if Self.isTerminalEvent(event) {
                            continuation.finish()
                            return
                        }
                    } catch {
                        if !Task.isCancelled {
                            continuation.finish(throwing: error)
                        }
                        return
                    }
                }
            }

            continuation.onTermination = { _ in
                readerTask.cancel()
                wsTask.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    internal static func parseMessage(_ message: URLSessionWebSocketTask.Message) throws -> TvResolveSocketEvent? {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            return nil
        }
        return try decodeEventData(data)
    }
    #endif

    public static func decodeEventData(_ data: Data) throws -> TvResolveSocketEvent {
        do {
            return try LunaCoreClient.decodeJSON(TvResolveSocketEvent.self, from: data)
        } catch {
            throw LunaCoreError.decodingFailed(error.localizedDescription)
        }
    }

    public static func isTerminalEvent(_ event: TvResolveSocketEvent) -> Bool {
        event.type == "resolve.ready" || event.type == "resolve.failed"
    }

    public static func makeWebSocketURL(baseURL: URL, wsPath: String) -> URL? {
        let trimmed = wsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        if trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://") {
            guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
                return nil
            }
            return url
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard var comps = URLComponents(string: trimmed),
                  let host = comps.host, !host.isEmpty else {
                return nil
            }
            comps.scheme = (comps.scheme?.lowercased() == "https") ? "wss" : "ws"
            return comps.url
        }
        let cleanBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanRel = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        guard var comps = URLComponents(string: "\(cleanBase)\(cleanRel)"),
              let host = comps.host, !host.isEmpty else {
            return nil
        }
        let isSecure = comps.scheme?.lowercased() == "https"
        comps.scheme = isSecure ? "wss" : "ws"
        return comps.url
    }
}
