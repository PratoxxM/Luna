import Foundation

public enum ArtworkLoadPriority: Sendable {
    case interactive
    case prefetch
}

public enum ArtworkSubjectKey: Sendable {
    public static let candidateCachedPixelSizes: [Int] = [
        3840, 2880, 2400, 1920, 1280, 1120, 1092, 1040, 960, 900, 896, 882, 820, 800, 780, 750, 720, 640, 480, 220,
    ]

    public static func rawIdentity(for url: URL) -> String {
        let pathPart: String
        if let query = url.query, !query.isEmpty {
            pathPart = "\(url.path)?\(query)"
        } else {
            pathPart = url.path
        }
        if pathPart.hasPrefix("/api/tv/v2")
            || pathPart.hasPrefix("/api/media/v2")
            || pathPart.hasPrefix("/api/tv/v1") {
            return pathPart
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        guard !host.isEmpty else { return pathPart }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)\(pathPart)"
        }
        return "\(scheme)://\(host)\(pathPart)"
    }

    /// Size-agnostic subject identity bridging `/api/tv/v2/img/(card|still|backdrop)/<bucket>/<file>`,
    /// `/api/media/v2/img/...`, legacy `/api/tv/v1/img/...`, TMDB `/t/p/w1280/...` <-> `/t/p/original/...`,
    /// and query-width `/api/tv/v2/artwork?...&w=1280` for instant progressive upgrades.
    public static func canonicalSubjectIdentity(for url: URL) -> String {
        let path = url.path
        let imgPrefixes = ["/api/tv/v2/img/", "/api/media/v2/img/", "/api/tv/v1/img/"]
        for prefix in imgPrefixes where path.hasPrefix(prefix) {
            let suffix = path.dropFirst(prefix.count)
            let parts = suffix.split(separator: "/", maxSplits: 1)
            if parts.count == 2 {
                let variant = parts[0].lowercased()
                let tail = parts[1]
                switch variant {
                case "card", "still", "backdrop":
                    return "tvimg-landscape:\(tail)"
                case "poster":
                    return "tvimg-poster:\(tail)"
                case "logo":
                    return "tvimg-logo:\(tail)"
                default:
                    return "tvimg:\(variant)/\(tail)"
                }
            }
        }
        let segments = path.components(separatedBy: "/")
        if let pIdx = segments.firstIndex(of: "p"),
           pIdx >= 1,
           segments[pIdx - 1] == "t",
           pIdx + 2 < segments.count {
            let tail = segments[(pIdx + 2)...].joined(separator: "/")
            return "tmdb:/\(tail)"
        }
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = comps.queryItems,
           !items.isEmpty {
            let filtered = items.filter { item in
                let lower = item.name.lowercased()
                return lower != "w" && lower != "width"
            }
            comps.queryItems = filtered.isEmpty ? nil : filtered
            if let stripped = comps.url {
                return rawIdentity(for: stripped)
            }
        }
        return rawIdentity(for: url)
    }

    public static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        "\(rawIdentity(for: url))#px\(maxPixelSize)"
    }
}
