import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif
import Synchronization

public final class LanURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    public let trustedHost: String?
    public let allowSelfSignedTLS: Bool

    public init(trustedHost: String?, allowSelfSignedTLS: Bool) {
        self.trustedHost = trustedHost?.lowercased()
        self.allowSelfSignedTLS = allowSelfSignedTLS
    }

    public static func shouldTrustServer(
        host: String,
        trustedHost: String?,
        allowSelfSignedTLS: Bool
    ) -> Bool {
        guard allowSelfSignedTLS else { return false }
        let normalized = host.lowercased()
        guard !normalized.isEmpty else { return false }
        if let trustedHost = trustedHost?.lowercased(), normalized == trustedHost {
            return true
        }
        return normalized.hasSuffix(".local")
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if canImport(Security)
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              Self.shouldTrustServer(
                  host: challenge.protectionSpace.host,
                  trustedHost: trustedHost,
                  allowSelfSignedTLS: allowSelfSignedTLS
              ) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        #else
        _ = session
        _ = challenge
        completionHandler(.performDefaultHandling, nil)
        #endif
    }
}

/// Shared URLSession pool keyed by `(lane, scheme, host, port, allowSelfSignedLanTLS)`.
/// Prevents leaking ephemeral URLSessions across SwiftUI view body evaluations and
/// preserves HTTP keep-alive / TLS session resumption against LunaCore Caddy.
public final class LunaCoreSessionPool: Sendable {
    public static let shared = LunaCoreSessionPool()

    private let sessions = Mutex<[String: URLSession]>([:])

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
        return sessions.withLock { map in
            if let existing = map[key] {
                return existing
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 45
            config.httpMaximumConnectionsPerHost = 6
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData

            let created = URLSession(configuration: config)
            map[key] = created
            return created
        }
    }

    private func makeOrReuseSession(
        for baseURL: URL,
        allowSelfSignedLanTLS: Bool,
        lane: String,
        maxConnections: Int,
        requestTimeout: TimeInterval
    ) -> URLSession {
        let key = "\(lane)|\(baseURL.scheme?.lowercased() ?? "http")://\(baseURL.host?.lowercased() ?? ""):\(baseURL.port ?? -1)|tls:\(allowSelfSignedLanTLS)"
        return sessions.withLock { map in
            if let existing = map[key] {
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
            map[key] = created
            return created
        }
    }

    public func invalidateAll() {
        let old = sessions.withLock { map in
            let values = Array(map.values)
            map.removeAll()
            return values
        }
        for session in old {
            session.invalidateAndCancel()
        }
    }
}
