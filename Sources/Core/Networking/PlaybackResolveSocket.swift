import Foundation

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

    public func events() -> AsyncThrowingStream<TvResolveSocketEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let wsURL = Self.makeWebSocketURL(baseURL: baseURL, wsPath: wsPath) else {
                continuation.finish(throwing: MediaOSError.invalidURL(wsPath))
                return
            }

            let urlSession = MediaOSSessionPool.shared.webSocketSession(
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
                        let data: Data
                        switch msg {
                        case .string(let text):
                            data = Data(text.utf8)
                        case .data(let raw):
                            data = raw
                        @unknown default:
                            continue
                        }
                        let event: TvResolveSocketEvent
                        do {
                            event = try JSONDecoder().decode(TvResolveSocketEvent.self, from: data)
                        } catch {
                            continuation.finish(throwing: MediaOSError.decodingFailed(error.localizedDescription))
                            return
                        }
                        continuation.yield(event)
                        if event.type == "resolve.ready" || event.type == "resolve.failed" {
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

    private static func makeWebSocketURL(baseURL: URL, wsPath: String) -> URL? {
        if wsPath.hasPrefix("ws://") || wsPath.hasPrefix("wss://") {
            return URL(string: wsPath)
        }
        let cleanBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanRel = wsPath.hasPrefix("/") ? wsPath : "/\(wsPath)"
        guard var comps = URLComponents(string: "\(cleanBase)\(cleanRel)") else {
            return nil
        }
        let isSecure = comps.scheme?.lowercased() == "https"
        comps.scheme = isSecure ? "wss" : "ws"
        return comps.url
    }
}
