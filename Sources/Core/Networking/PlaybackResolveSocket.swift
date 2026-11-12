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

            let config = URLSessionConfiguration.ephemeral
            let delegate = LanURLSessionDelegate(
                trustedHost: baseURL.host,
                allowSelfSignedTLS: allowSelfSignedLanTLS
            )
            let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            var request = URLRequest(url: wsURL)
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }

            let wsTask = urlSession.webSocketTask(with: request)
            wsTask.resume()

            let readerTask = Task {
                defer {
                    wsTask.cancel(with: .goingAway, reason: nil)
                    urlSession.invalidateAndCancel()
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
                        if let event = try? JSONDecoder().decode(TvResolveSocketEvent.self, from: data) {
                            continuation.yield(event)
                            if event.type == "resolve.ready" || event.type == "resolve.failed" {
                                continuation.finish()
                                return
                            }
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
                urlSession.invalidateAndCancel()
            }
        }
    }

    private static func makeWebSocketURL(baseURL: URL, wsPath: String) -> URL? {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let isSecure = comps?.scheme?.lowercased() == "https"
        comps?.scheme = isSecure ? "wss" : "ws"
        comps?.path = wsPath.hasPrefix("/") ? wsPath : "/\(wsPath)"
        comps?.query = nil
        return comps?.url
    }
}
