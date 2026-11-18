import Foundation
import Network

public struct DiscoveredLunaCoreServer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: URL
    public let apiPath: String

    public var displayAddress: String {
        baseURL.absoluteString
    }
}

@MainActor
public final class BonjourServerBrowser: ObservableObject {
    @Published public private(set) var servers: [DiscoveredLunaCoreServer] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private var activeResolvers: [String: NWConnection] = [:]
    private var resolveTimeouts: [String: Task<Void, Never>] = [:]
    internal let resolveTimeoutNanoseconds: UInt64

    public init(resolveTimeoutNanoseconds: UInt64 = 8_000_000_000) {
        self.resolveTimeoutNanoseconds = resolveTimeoutNanoseconds
    }

    internal var activeResolverCount: Int {
        activeResolvers.count
    }

    public func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_lunacore._tcp", domain: nil)
        let nwBrowser = NWBrowser(for: descriptor, using: params)

        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed, .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }

        self.browser = nwBrowser
        self.isSearching = true
        nwBrowser.start(queue: .main)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        for (_, timeoutTask) in resolveTimeouts {
            timeoutTask.cancel()
        }
        resolveTimeouts.removeAll()
        for (_, conn) in activeResolvers {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        activeResolvers.removeAll()
        isSearching = false
    }

    internal func cancelResolver(for key: String) {
        resolveTimeouts.removeValue(forKey: key)?.cancel()
        if let conn = activeResolvers.removeValue(forKey: key) {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
    }

    internal func beginResolve(
        key: String,
        endpoint: NWEndpoint,
        serviceName: String,
        txt: [String: String]
    ) {
        cancelResolver(for: key)

        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let conn = NWConnection(to: endpoint, using: params)
        activeResolvers[key] = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            switch state {
            case .ready:
                let remoteEndpoint = conn?.currentPath?.remoteEndpoint
                conn?.stateUpdateHandler = nil
                conn?.cancel()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.resolveTimeouts.removeValue(forKey: key)?.cancel()
                    self.activeResolvers.removeValue(forKey: key)
                    if let resolved = Self.extractServer(
                        id: key,
                        serviceName: serviceName,
                        remoteEndpoint: remoteEndpoint,
                        txt: txt
                    ) {
                        if let existingIdx = self.servers.firstIndex(where: { $0.id == key }) {
                            self.servers[existingIdx] = resolved
                        } else if !self.servers.contains(where: { $0.baseURL == resolved.baseURL }) {
                            self.servers.append(resolved)
                        }
                    }
                }
            case .failed, .cancelled:
                conn?.stateUpdateHandler = nil
                Task { @MainActor [weak self] in
                    self?.resolveTimeouts.removeValue(forKey: key)?.cancel()
                    self?.activeResolvers.removeValue(forKey: key)
                }
            default:
                break
            }
        }

        let timeoutNs = resolveTimeoutNanoseconds
        resolveTimeouts[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNs)
            guard !Task.isCancelled, let self else { return }
            self.cancelResolver(for: key)
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var activeKeys = Set<String>()
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let key = "\(name).\(type).\(domain)"
            activeKeys.insert(key)
            if servers.contains(where: { $0.id == key }) || activeResolvers[key] != nil {
                continue
            }

            var txtDict: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                txtDict = record.dictionary
            }
            beginResolve(key: key, endpoint: result.endpoint, serviceName: name, txt: txtDict)
        }

        // Prune servers and pending resolvers that disappeared from the LAN.
        for staleKey in Array(activeResolvers.keys) where !activeKeys.contains(staleKey) {
            cancelResolver(for: staleKey)
        }
        servers.removeAll { !activeKeys.contains($0.id) }
    }

    internal nonisolated static func extractServer(
        id: String,
        serviceName: String,
        remoteEndpoint: NWEndpoint?,
        txt: [String: String]
    ) -> DiscoveredLunaCoreServer? {
        guard case let .hostPort(host, port) = remoteEndpoint else { return nil }

        let rawHost: String
        switch host {
        case .ipv4(let v4):
            rawHost = "\(v4)"
        case .ipv6(let v6):
            let s = "\(v6)"
            if s.contains("%") {
                return nil
            }
            rawHost = "[\(s)]"
        case .name(let hostname, _):
            rawHost = hostname
        @unknown default:
            return nil
        }

        return parseDiscoveredService(
            id: id,
            serviceName: serviceName,
            rawHost: rawHost,
            port: Int(port.rawValue),
            txt: txt
        )
    }

    internal nonisolated static func parseDiscoveredService(
        id: String,
        serviceName: String,
        rawHost: String,
        port: Int,
        txt: [String: String]
    ) -> DiscoveredLunaCoreServer? {
        var cleanHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return nil }
        if cleanHost.hasPrefix("["), cleanHost.hasSuffix("]"), cleanHost.contains("%") {
            return nil
        }
        if let pctIndex = cleanHost.firstIndex(of: "%") {
            cleanHost = String(cleanHost[..<pctIndex])
        }
        guard !cleanHost.isEmpty else { return nil }

        let scheme: String
        let effectivePort: Int
        if let rawHttps = txt["https_port"] ?? txt["tls_port"],
           let httpsPort = Int(rawHttps.trimmingCharacters(in: .whitespacesAndNewlines)),
           httpsPort > 0 {
            scheme = "https"
            effectivePort = httpsPort
        } else {
            scheme = "http"
            effectivePort = port
        }

        guard effectivePort > 0, let url = URL(string: "\(scheme)://\(cleanHost):\(effectivePort)") else {
            return nil
        }

        let rawApi = txt["api"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiPath = (rawApi?.isEmpty == false) ? (rawApi ?? "/api/tv/v1") : "/api/tv/v1"

        return DiscoveredLunaCoreServer(
            id: id,
            name: serviceName,
            baseURL: url,
            apiPath: apiPath
        )
    }
}
