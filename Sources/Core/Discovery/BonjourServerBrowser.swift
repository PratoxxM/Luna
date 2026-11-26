import Foundation
import Network
import Observation

@MainActor
@Observable
public final class BonjourServerBrowser: ServerDiscoveryProviding {
    public private(set) var servers: [DiscoveredLunaCoreServer] = []
    public private(set) var isSearching: Bool = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var nextBrowserToken: UInt64 = 0
    @ObservationIgnored private var currentBrowserToken: UInt64?
    @ObservationIgnored private var activeResolvers: [String: NWConnection] = [:]
    @ObservationIgnored private var nextResolverToken: UInt64 = 0
    @ObservationIgnored private var resolverTokens: [String: UInt64] = [:]
    @ObservationIgnored private var resolveTimeouts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored internal let resolveTimeoutNanoseconds: UInt64

    public init(resolveTimeoutNanoseconds: UInt64 = 8_000_000_000) {
        self.resolveTimeoutNanoseconds = resolveTimeoutNanoseconds
    }

    internal var activeResolverCount: Int {
        activeResolvers.count
    }

    internal var activeBrowserId: ObjectIdentifier? {
        browser.map(ObjectIdentifier.init)
    }

    internal var activeBrowserToken: UInt64? {
        currentBrowserToken
    }

    internal func activeResolverId(for key: String) -> ObjectIdentifier? {
        activeResolvers[key].map(ObjectIdentifier.init)
    }

    internal func activeResolverToken(for key: String) -> UInt64? {
        resolverTokens[key]
    }

    public func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_lunacore._tcp", domain: nil)
        let nwBrowser = NWBrowser(for: descriptor, using: params)
        let browserId = ObjectIdentifier(nwBrowser)
        nextBrowserToken &+= 1
        let browserToken = nextBrowserToken
        self.currentBrowserToken = browserToken

        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self,
                      self.browser.map(ObjectIdentifier.init) == browserId,
                      self.currentBrowserToken == browserToken else { return }
                self.applyBrowserStateUpdate(state, browserId: browserId, browserToken: browserToken)
            }
        }

        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.browser.map(ObjectIdentifier.init) == browserId,
                      self.currentBrowserToken == browserToken else { return }
                self.applyBrowseResults(results, browserId: browserId, browserToken: browserToken)
            }
        }

        self.browser = nwBrowser
        self.isSearching = true
        nwBrowser.start(queue: .main)
    }

    internal func applyBrowserStateUpdate(_ state: NWBrowser.State, browserId: ObjectIdentifier, browserToken: UInt64) {
        guard self.browser.map(ObjectIdentifier.init) == browserId,
              self.currentBrowserToken == browserToken else { return }
        switch state {
        case .ready:
            self.isSearching = true
        case .failed, .cancelled:
            self.isSearching = false
        default:
            break
        }
    }

    internal func applyBrowseResults(_ results: Set<NWBrowser.Result>, browserId: ObjectIdentifier, browserToken: UInt64) {
        guard self.browser.map(ObjectIdentifier.init) == browserId,
              self.currentBrowserToken == browserToken else { return }
        self.handleBrowseResults(results)
    }

    public func stop() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        currentBrowserToken = nil
        for (_, timeoutTask) in resolveTimeouts {
            timeoutTask.cancel()
        }
        resolveTimeouts.removeAll()
        for (_, conn) in activeResolvers {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        activeResolvers.removeAll()
        resolverTokens.removeAll()
        isSearching = false
    }

    internal func cancelResolver(for key: String) {
        resolverTokens.removeValue(forKey: key)
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
        let conn = NWConnection(to: endpoint, using: params)
        let connId = ObjectIdentifier(conn)
        nextResolverToken &+= 1
        let resolverToken = nextResolverToken
        resolverTokens[key] = resolverToken
        activeResolvers[key] = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            switch state {
            case .ready:
                let remoteEndpoint = conn?.currentPath?.remoteEndpoint
                conn?.stateUpdateHandler = nil
                conn?.cancel()
                Task { @MainActor [weak self] in
                    guard let self,
                          self.activeResolvers[key].map(ObjectIdentifier.init) == connId,
                          self.resolverTokens[key] == resolverToken else { return }
                    self.applyResolverReady(
                        key: key,
                        connId: connId,
                        resolverToken: resolverToken,
                        serviceName: serviceName,
                        remoteEndpoint: remoteEndpoint,
                        txt: txt
                    )
                }
            case .failed, .cancelled:
                conn?.stateUpdateHandler = nil
                Task { @MainActor [weak self] in
                    guard let self,
                          self.activeResolvers[key].map(ObjectIdentifier.init) == connId,
                          self.resolverTokens[key] == resolverToken else { return }
                    self.applyResolverTerminated(key: key, connId: connId, resolverToken: resolverToken)
                }
            default:
                break
            }
        }

        let timeoutNs = resolveTimeoutNanoseconds
        resolveTimeouts[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNs)
            guard !Task.isCancelled,
                  let self,
                  self.activeResolvers[key].map(ObjectIdentifier.init) == connId,
                  self.resolverTokens[key] == resolverToken else { return }
            self.cancelResolver(for: key)
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    internal func applyResolverReady(
        key: String,
        connId: ObjectIdentifier,
        resolverToken: UInt64,
        serviceName: String,
        remoteEndpoint: NWEndpoint?,
        txt: [String: String]
    ) {
        guard self.activeResolvers[key].map(ObjectIdentifier.init) == connId,
              self.resolverTokens[key] == resolverToken else { return }
        self.resolverTokens.removeValue(forKey: key)
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

    internal func applyResolverTerminated(key: String, connId: ObjectIdentifier, resolverToken: UInt64) {
        guard self.activeResolvers[key].map(ObjectIdentifier.init) == connId,
              self.resolverTokens[key] == resolverToken else { return }
        self.resolverTokens.removeValue(forKey: key)
        self.resolveTimeouts.removeValue(forKey: key)?.cancel()
        self.activeResolvers.removeValue(forKey: key)
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
        BonjourServiceParser.parseDiscoveredService(
            id: id,
            serviceName: serviceName,
            rawHost: rawHost,
            port: port,
            txt: txt
        )
    }
}
