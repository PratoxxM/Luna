import Foundation
import UIKit
import AetherBridge

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

    public var shortBadgeLabel: String {
        switch self {
        case .dvFel714: return "DV FEL · 7.1.4"
        case .hdr10512: return "HDR10+ · 5.1.2"
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
            return "4K BluRay Remux · Dual-Layer DV P7 FEL / P8 · TrueHD Atmos & DTS:X (7.1.4)"
        case .hdr10512:
            return "4K HDR10+ / HDR10 · DV Base-Layer · Atmos / Lossless (5.1.2)"
        }
    }
}

@MainActor
public final class AppSessionStore: ObservableObject {
    @Published public private(set) var serverBaseURL: URL?
    @Published public private(set) var deviceToken: String?
    public let deviceID: String
    @Published public var deviceName: String
    @Published public var roomName: String
    @Published public var hardwareProfile: String
    @Published public var localProfileOverride: String?
    @Published public var deviceOverrides: TvDeviceOverrides? = nil
    @Published public private(set) var homeRefreshNonce: Int = 0

    @Published public var allowSelfSignedLanTLS: Bool {
        didSet {
            defaults.set(allowSelfSignedLanTLS, forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey)
            MediaOSSessionPool.shared.invalidateAll()
            applyEngineTLSPolicy()
        }
    }

    @Published public var activePlaybackTarget: PlaybackLaunchRequest? = nil {
        didSet {
            // Trigger silent SWR refresh when returning from the video player so
            // «Fortsett å se» reflects latest watch progress immediately.
            if oldValue != nil && activePlaybackTarget == nil {
                homeRefreshNonce &+= 1
            }
        }
    }

    private let defaults: UserDefaults

    public var isPaired: Bool {
        serverBaseURL != nil && !(deviceToken ?? "").isEmpty
    }

    public var effectiveHardwareProfile: String {
        if let localProfileOverride, !localProfileOverride.isEmpty {
            return localProfileOverride
        }
        return hardwareProfile
    }

    public var activePreset: HardwareProfilePreset {
        HardwareProfilePreset(rawValue: effectiveHardwareProfile) ?? .dvFel714
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.deviceID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)

        if let rawURL = defaults.string(forKey: SideloadSafeStorage.serverURLKey),
           let parsed = Self.normalizeServerURL(rawURL) {
            self.serverBaseURL = parsed
        } else {
            self.serverBaseURL = nil
        }

        let loadedToken = SideloadSafeStorage.loadDeviceToken()
        self.deviceToken = loadedToken
        if let loadedToken, loadedToken.count >= 8 {
            _ = EngineLog.registerSecret(loadedToken)
        }

        self.deviceName = defaults.string(forKey: SideloadSafeStorage.deviceNameKey) ?? "Apple TV"
        self.roomName = defaults.string(forKey: SideloadSafeStorage.roomNameKey) ?? "Kjellerstua"
        self.hardwareProfile = defaults.string(forKey: SideloadSafeStorage.hardwareProfileKey) ?? HardwareProfilePreset.dvFel714.rawValue
        self.localProfileOverride = defaults.string(forKey: SideloadSafeStorage.localProfileOverrideKey)
        self.deviceOverrides = nil
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = defaults.object(forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey) as? Bool ?? true

        applyEngineTLSPolicy()
    }

    public func notifyContentMutated() {
        homeRefreshNonce &+= 1
    }

    public func makeClient(overrideBaseURL: URL? = nil) -> MediaOSClient? {
        guard let base = overrideBaseURL ?? serverBaseURL else { return nil }
        return MediaOSClient(
            baseURL: base,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: effectiveHardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS
        )
    }

    public func completePairing(baseURL: URL, token: String, pairedDevice: TvPairedDeviceInfo) {
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        _ = EngineLog.registerSecret(token)
        SideloadSafeStorage.saveDeviceToken(token)

        self.serverBaseURL = baseURL
        self.deviceToken = token
        self.deviceName = pairedDevice.deviceName
        self.roomName = pairedDevice.roomName
        self.hardwareProfile = pairedDevice.hardwareProfile
        self.deviceOverrides = pairedDevice.overrides
        self.localProfileOverride = nil

        defaults.set(baseURL.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
        defaults.set(pairedDevice.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        defaults.set(pairedDevice.roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(pairedDevice.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        defaults.removeObject(forKey: SideloadSafeStorage.localProfileOverrideKey)
        applyEngineTLSPolicy()
        homeRefreshNonce &+= 1
    }

    public func syncFromBootstrap(_ device: TvPairedDeviceInfo) {
        self.deviceName = device.deviceName
        if localProfileOverride == nil {
            self.roomName = device.roomName
            self.hardwareProfile = device.hardwareProfile
            defaults.set(device.roomName, forKey: SideloadSafeStorage.roomNameKey)
            defaults.set(device.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        }
        self.deviceOverrides = device.overrides
        defaults.set(device.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
    }

    public func setRoomAndProfile(roomName: String, hardwareProfile: String, persistAsLocalOverride: Bool = false) {
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        defaults.set(roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)

        if persistAsLocalOverride {
            self.localProfileOverride = hardwareProfile
            defaults.set(hardwareProfile, forKey: SideloadSafeStorage.localProfileOverrideKey)
        } else {
            self.localProfileOverride = nil
            defaults.removeObject(forKey: SideloadSafeStorage.localProfileOverrideKey)
        }

        if let client = makeClient() {
            Task {
                try? await client.updateDeviceProfile(roomName: roomName, hardwareProfile: hardwareProfile)
            }
        }
        homeRefreshNonce &+= 1
    }

    public func unpairDevice() {
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        SideloadSafeStorage.deleteDeviceToken()
        AetherEngine.discardPrewarmedSources()
        MediaOSSessionPool.shared.invalidateAll()
        deviceToken = nil
        activePlaybackTarget = nil
    }

    public func resetAllConnectionSettings() {
        unpairDevice()
        serverBaseURL = nil
        defaults.removeObject(forKey: SideloadSafeStorage.serverURLKey)
    }

    public static func currentSystemVersionString() -> String {
        "tvOS \(UIDevice.current.systemVersion)"
    }

    public static func currentHardwareModelString() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }
        return machine ?? UIDevice.current.model
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
        if trimmed.hasSuffix("/api/tv/v1") {
            trimmed = String(trimmed.dropLast("/api/tv/v1".count))
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    private func applyEngineTLSPolicy() {
        let allowLan = allowSelfSignedLanTLS
        let configuredHost = serverBaseURL?.host?.lowercased()
        if allowLan {
            EngineTLS.serverTrustEvaluator = { space in
                let host = space.host.lowercased()
                if let configuredHost, host == configuredHost {
                    return true
                }
                return host.hasSuffix(".local")
            }
        } else {
            EngineTLS.serverTrustEvaluator = nil
        }
    }
}
