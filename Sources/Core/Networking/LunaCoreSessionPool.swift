import Foundation

public final class LanURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    public let trustedHost: String?
    public let allowSelfSignedTLS: Bool

    public init(trustedHost: String?, allowSelfSignedTLS: Bool) {
        self.trustedHost = trustedHost?.lowercased()
        self.allowSelfSignedTLS = allowSelfSignedTLS
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowSelfSignedTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()
        if host == trustedHost || host.hasSuffix(".local") {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Shared URLSession pool keyed by `(lane, scheme, host, port, allowSelfSignedLanTLS)`.
/// Prevents leaking ephemeral URLSessions across SwiftUI view body evaluations and
/// preserves HTTP keep-alive / TLS session resumption against LunaCore Caddy.
public final class LunaCoreSessionPool: @unchecked Sendable {
    public static let shared = LunaCoreSessionPool()

    private let lock = NSLock()
    private var sessions: [String: URLSession] = [:]

    private init() {}

    public func session(for baseURL: URL, allowSelfSignedLanTLS: Bool) -> URLSession {
        makeOrReuseSession(
            for: baseURL,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            lane: "api",
            maxConnections: 8,
            requestTimeout: 25
        )
    }

    public func artworkSession(for baseURL: URL, allowSelfSignedLanTLS: Bool) -> URLSession {
        makeOrReuseSession(
            for: baseURL,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            lane: "artwork",
            maxConnections: 6,
            requestTimeout: 15
        )
    }

    public func webSocketSession(for baseURL: URL, allowSelfSignedLanTLS: Bool) -> URLSession {
        makeOrReuseSession(
            for: baseURL,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            lane: "ws",
            maxConnections: 4,
            requestTimeout: 30
        )
    }

    public func externalArtworkSession() -> URLSession {
        let key = "external|artwork"
        lock.lock()
        defer { lock.unlock() }

        if let existing = sessions[key] {
            return existing
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let created = URLSession(configuration: config)
        sessions[key] = created
        return created
    }

    private func makeOrReuseSession(
        for baseURL: URL,
        allowSelfSignedLanTLS: Bool,
        lane: String,
        maxConnections: Int,
        requestTimeout: TimeInterval
    ) -> URLSession {
        let key = "\(lane)|\(baseURL.scheme?.lowercased() ?? "http")://\(baseURL.host?.lowercased() ?? ""):\(baseURL.port ?? -1)|tls:\(allowSelfSignedLanTLS)"
        lock.lock()
        defer { lock.unlock() }

        if let existing = sessions[key] {
            return existing
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = 90
        config.httpMaximumConnectionsPerHost = maxConnections
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let delegate = LanURLSessionDelegate(
            trustedHost: baseURL.host,
            allowSelfSignedTLS: allowSelfSignedLanTLS
        )
        let created = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions[key] = created
        return created
    }

    public func invalidateAll() {
        lock.lock()
        let old = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()

        for session in old {
            session.invalidateAndCancel()
        }
    }
}
