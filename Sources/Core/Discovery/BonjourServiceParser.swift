import Foundation

public struct DiscoveredLunaCoreServer: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: URL
    public let apiPath: String
    public let localHostnameURL: URL?

    public init(
        id: String,
        name: String,
        baseURL: URL,
        apiPath: String,
        localHostnameURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiPath = apiPath
        self.localHostnameURL = localHostnameURL
    }

    public var displayAddress: String {
        baseURL.absoluteString
    }
}

public enum BonjourDiscoveryPolicy: Sendable {
    public static let defaultAPIPath = "/api/tv/v2"
    public static let restrictsToIPv4Only = false
    public static let allowsIPv4 = true
    public static let allowsIPv6 = true
}

public enum BonjourServiceParser: Sendable {
    public static func parseDiscoveredService(
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
        let apiPath = (rawApi?.isEmpty == false)
            ? (rawApi ?? BonjourDiscoveryPolicy.defaultAPIPath)
            : BonjourDiscoveryPolicy.defaultAPIPath

        let localHostURL: URL? = {
            if let rawMdns = txt["hostname"] ?? txt["host"] ?? txt["local_host"] {
                var host = rawMdns.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                while host.hasSuffix(".") { host.removeLast() }
                if !host.isEmpty {
                    if !host.contains(".") {
                        host += ".local"
                    }
                    if host.hasSuffix(".local"),
                       let built = URL(string: "\(scheme)://\(host):\(effectivePort)") {
                        return built
                    }
                }
            }
            if cleanHost.lowercased().hasSuffix(".local") {
                return url
            }
            return nil
        }()

        return DiscoveredLunaCoreServer(
            id: id,
            name: serviceName,
            baseURL: url,
            apiPath: apiPath,
            localHostnameURL: localHostURL
        )
    }
}
