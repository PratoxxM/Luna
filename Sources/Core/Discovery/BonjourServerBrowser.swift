import Foundation
import Network

public struct DiscoveredMediaOSServer: Identifiable, Equatable, Sendable {
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
    @Published public private(set) var servers: [DiscoveredMediaOSServer] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private var activeResolvers: [String: NWConnection] = [:]

    public init() {}

    public func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_mediaos._tcp", domain: nil)
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
        for (_, conn) in activeResolvers {
            conn.cancel()
        }
        activeResolvers.removeAll()
        isSearching = false
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

            let conn = NWConnection(to: result.endpoint, using: .tcp)
            activeResolvers[key] = conn
            let capturedTxt = txtDict
            let capturedName = name

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let remoteEndpoint = conn.currentPath?.remoteEndpoint
                    conn.cancel()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.activeResolvers.removeValue(forKey: key)
                        if let resolved = Self.extractServer(
                            id: key,
                            serviceName: capturedName,
                            remoteEndpoint: remoteEndpoint,
                            txt: capturedTxt
                        ) {
                            if let existingIdx = self.servers.firstIndex(where: { $0.id == key }) {
                                self.servers[existingIdx] = resolved
                            } else if !self.servers.contains(where: { $0.baseURL == resolved.baseURL }) {
                                self.servers.append(resolved)
                            }
                        }
                    }
                case .failed, .cancelled:
                    Task { @MainActor [weak self] in
                        self?.activeResolvers.removeValue(forKey: key)
                    }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // Prune servers and pending resolvers that disappeared from the LAN.
        for (staleKey, staleConn) in activeResolvers where !activeKeys.contains(staleKey) {
            staleConn.cancel()
            activeResolvers.removeValue(forKey: staleKey)
        }
        servers.removeAll { !activeKeys.contains($0.id) }
    }

    private static func extractServer(
        id: String,
        serviceName: String,
        remoteEndpoint: NWEndpoint?,
        txt: [String: String]
    ) -> DiscoveredMediaOSServer? {
        guard case let .hostPort(host, port) = remoteEndpoint else { return nil }

        var rawHost: String
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

        if let pctIndex = rawHost.firstIndex(of: "%") {
            rawHost = String(rawHost[..<pctIndex])
        }

        let scheme: String
        let effectivePort: Int
        if let rawHttps = txt["https_port"] ?? txt["tls_port"],
           let httpsPort = Int(rawHttps.trimmingCharacters(in: .whitespacesAndNewlines)),
           httpsPort > 0 {
            scheme = "https"
            effectivePort = httpsPort
        } else {
            scheme = "http"
            effectivePort = Int(port.rawValue)
        }

        guard effectivePort > 0, let url = URL(string: "\(scheme)://\(rawHost):\(effectivePort)") else {
            return nil
        }

        let rawApi = txt["api"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiPath = (rawApi?.isEmpty == false) ? (rawApi ?? "/api/tv/v1") : "/api/tv/v1"

        return DiscoveredMediaOSServer(
            id: id,
            name: serviceName,
            baseURL: url,
            apiPath: apiPath
        )
    }
}
