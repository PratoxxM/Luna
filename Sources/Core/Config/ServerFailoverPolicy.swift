import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HardwareProfilePreset: String, CaseIterable, Identifiable, Sendable {
    case dvFel714 = "dv-fel-714"
    case hdr10512 = "hdr10-512"

    public var id: String { rawValue }

    public var defaultRoomName: String {
        switch self {
        case .dvFel714: return "Kjellerstua"
        case .hdr10512: return "Stua"
        }
    }

    public var displayTitle: String {
        switch self {
        case .dvFel714:
            return "Kjellerstua — Dolby Vision FEL + 7.1.4"
        case .hdr10512:
            return "Stua — HDR10+ / HDR10 + 5.1.2"
        }
    }

    public var technicalSummary: String {
        switch self {
        case .dvFel714:
            return "4K BluRay Remux · Dual-Layer DV P7 FEL / P8 · TrueHD Atmos og DTS:X (7.1.4)"
        case .hdr10512:
            return "4K HDR10+ / HDR10 · DV Base-Layer · Atmos og tapsfri lyd (5.1.2)"
        }
    }

    public var defaultSpeakerLayout: String {
        switch self {
        case .dvFel714: return "7.1.4"
        case .hdr10512: return "5.1.2"
        }
    }

    public static var fallbackRooms: [TvRoomDefinition] {
        allCases.map { preset in
            TvRoomDefinition(
                roomId: preset.rawValue,
                roomName: preset.defaultRoomName,
                hardwareProfile: preset.rawValue,
                equipmentLabel: LunaCopy.roomEquipmentLabel(hardwareProfile: preset.rawValue),
                atmosphere: preset == .hdr10512 ? "living" : "cinema",
                speakerLayout: preset.defaultSpeakerLayout,
                label: preset.displayTitle,
                description: preset.technicalSummary
            )
        }
    }
}

public enum ServerFailoverPolicy: Sendable {
    public static func isFailoverEligibleError(_ error: any Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    public static func orderedFailoverCandidates(
        primary: URL,
        localHostnameURL: URL?,
        fallbackServerURL: URL?
    ) -> [URL] {
        var seen: Set<String> = [primary.absoluteString.lowercased()]
        var candidates: [URL] = []

        func appendCandidate(_ candidate: URL?) {
            guard let candidate else { return }
            let norm = candidate.absoluteString.lowercased()
            if seen.insert(norm).inserted {
                candidates.append(candidate)
            }
        }

        if let host = primary.host {
            let urlHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            let scheme = primary.scheme?.lowercased() ?? "http"
            let port = primary.port ?? (scheme == "https" ? 443 : 80)
            if scheme == "https" && port == 8920 {
                appendCandidate(URL(string: "http://\(urlHost):8090"))
            } else if scheme == "http" && port == 8090 {
                appendCandidate(URL(string: "https://\(urlHost):8920"))
            }
        }
        appendCandidate(localHostnameURL)
        appendCandidate(fallbackServerURL)
        return candidates
    }

    public static func normalizeServerURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        for apiSuffix in ["/api/tv/v2", "/api/tv/v1"] {
            if trimmed.hasSuffix(apiSuffix) {
                trimmed = String(trimmed.dropLast(apiSuffix.count))
                break
            }
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    public static func shouldTrustServerHost(
        _ host: String,
        configuredHost: String?,
        allowSelfSignedLanTLS: Bool
    ) -> Bool {
        LanURLSessionDelegate.shouldTrustServer(
            host: host,
            trustedHost: configuredHost,
            allowSelfSignedTLS: allowSelfSignedLanTLS
        )
    }
}
