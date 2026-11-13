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

    public static var fallbackRooms: [TvRoomDefinition] {
        allCases.map { preset in
            TvRoomDefinition(
                roomName: preset.defaultRoomName,
                hardwareProfile: preset.rawValue,
                label: preset.displayTitle,
                description: preset.technicalSummary
            )
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
    @Published public private(set) var availableRooms: [TvRoomDefinition] = HardwareProfilePreset.fallbackRooms
    @Published public private(set) var homeRefreshNonce: Int = 0
    public let comfort: ComfortPreferences

    @Published public var allowSelfSignedLanTLS: Bool {
        didSet {
            defaults.set(allowSelfSignedLanTLS, forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey)
            MediaOSSessionPool.shared.invalidateAll()
            applyEngineTLSPolicy()
            rebuildCachedClient()
        }
    }

    @Published public var activePlaybackTarget: PlaybackLaunchRequest? = nil

    private let defaults: UserDefaults
    private let cachedAppVersion: String
    private let cachedOSVersion: String
    private var cachedClient: MediaOSClient?
    private var overrideSyncTask: Task<Void, Never>?

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
        self.comfort = ComfortPreferences(defaults: defaults)
        self.deviceID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)
        self.cachedAppVersion = Self.currentAppVersionString()
        self.cachedOSVersion = Self.currentSystemVersionString()

        if let rawURL = defaults.string(forKey: SideloadSafeStorage.serverURLKey),
           let parsed = Self.normalizeServerURL(rawURL) {
            self.serverBaseURL = parsed
        } else {
            self.serverBaseURL = nil
        }

        let loadedToken = SideloadSafeStorage.loadDeviceToken(defaults: defaults)
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
        rebuildCachedClient()

        self.comfort.onSyncRequested = { [weak self] updatedOverrides in
            self?.scheduleOverridesSync(updatedOverrides)
        }
    }

    private func rebuildCachedClient() {
        guard let base = serverBaseURL else {
            cachedClient = nil
            return
        }
        cachedClient = MediaOSClient(
            baseURL: base,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: effectiveHardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            appVersion: cachedAppVersion,
            osVersion: cachedOSVersion
        )
    }

    private func scheduleOverridesSync(_ overrides: TvDeviceOverrides) {
        self.deviceOverrides = overrides
        overrideSyncTask?.cancel()
        overrideSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, let client = self.makeClient() else { return }
            try? await client.updateDeviceProfile(overrides: overrides)
            if !Task.isCancelled {
                self.overrideSyncTask = nil
            }
        }
    }

    public func notifyContentMutated() {
        homeRefreshNonce &+= 1
    }

    public func makeClient(overrideBaseURL: URL? = nil) -> MediaOSClient? {
        if let overrideBaseURL {
            return MediaOSClient(
                baseURL: overrideBaseURL,
                deviceID: deviceID,
                deviceToken: deviceToken,
                roomName: roomName,
                hardwareProfile: effectiveHardwareProfile,
                allowSelfSignedLanTLS: allowSelfSignedLanTLS,
                appVersion: cachedAppVersion,
                osVersion: cachedOSVersion
            )
        }
        return cachedClient
    }

    public func completePairing(baseURL: URL, token: String, pairedDevice: TvPairedDeviceInfo) {
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        _ = EngineLog.registerSecret(token)
        SideloadSafeStorage.saveDeviceToken(token, defaults: defaults)

        self.serverBaseURL = baseURL
        self.deviceToken = token
        self.deviceName = pairedDevice.deviceName
        self.roomName = pairedDevice.roomName
        self.hardwareProfile = pairedDevice.hardwareProfile
        self.deviceOverrides = pairedDevice.overrides
        self.comfort.adoptServerOverrides(pairedDevice.overrides)
        self.localProfileOverride = nil

        defaults.set(baseURL.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
        defaults.set(pairedDevice.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        defaults.set(pairedDevice.roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(pairedDevice.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        defaults.removeObject(forKey: SideloadSafeStorage.localProfileOverrideKey)
        applyEngineTLSPolicy()
        rebuildCachedClient()
        homeRefreshNonce &+= 1
    }

    public func syncFromBootstrap(_ device: TvPairedDeviceInfo, defaultRooms: [TvRoomDefinition]? = nil) {
        var clientInputsChanged = false
        if device.deviceName != deviceName {
            self.deviceName = device.deviceName
            defaults.set(device.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        }
        if localProfileOverride == nil {
            if device.roomName != roomName {
                self.roomName = device.roomName
                defaults.set(device.roomName, forKey: SideloadSafeStorage.roomNameKey)
                clientInputsChanged = true
            }
            if device.hardwareProfile != hardwareProfile {
                self.hardwareProfile = device.hardwareProfile
                defaults.set(device.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
                clientInputsChanged = true
            }
        }
        if overrideSyncTask == nil {
            if device.overrides != deviceOverrides {
                self.deviceOverrides = device.overrides
            }
            self.comfort.adoptServerOverrides(device.overrides)
        }
        if let defaultRooms, !defaultRooms.isEmpty, defaultRooms != availableRooms {
            self.availableRooms = defaultRooms
        }
        if clientInputsChanged || cachedClient == nil {
            rebuildCachedClient()
        }
    }

    public func setRoomAndProfile(roomName: String, hardwareProfile: String, persistAsLocalOverride: Bool = false) {
        self.roomName = roomName
        self.hardwareProfile = hardwareProfile
        defaults.set(roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)

        if persistAsLocalOverride {
            self.localProfileOverride = hardwareProfile
            defaults.set(hardwareProfile, forKey: SideloadSafeStorage.localProfileOverrideKey)
            rebuildCachedClient()
        } else {
            self.localProfileOverride = nil
            defaults.removeObject(forKey: SideloadSafeStorage.localProfileOverrideKey)
            rebuildCachedClient()
            if let client = makeClient() {
                Task {
                    try? await client.updateDeviceProfile(roomName: roomName, hardwareProfile: hardwareProfile)
                }
            }
        }
        homeRefreshNonce &+= 1
    }

    public func restoreServerManagedRoomAndProfile() async {
        self.localProfileOverride = nil
        defaults.removeObject(forKey: SideloadSafeStorage.localProfileOverrideKey)
        rebuildCachedClient()
        if let client = makeClient() {
            do {
                let boot = try await client.fetchBootstrap()
                syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
            } catch MediaOSError.unauthorized {
                unpairDevice()
                return
            } catch {
                // Keep cached server values until next bootstrap succeeds
            }
        }
        homeRefreshNonce &+= 1
    }

    public nonisolated static func currentAppVersionString() -> String {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = ver.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "2.2.10"
    }

    public func unpairDevice() {
        overrideSyncTask?.cancel()
        overrideSyncTask = nil
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
        AetherEngine.discardPrewarmedSources()
        MediaOSSessionPool.shared.invalidateAll()
        DiskSWRStore.clearMemory()
        Task { await DiskSWRStore.clearAllAsync() }
        deviceToken = nil
        availableRooms = HardwareProfilePreset.fallbackRooms
        activePlaybackTarget = nil
        rebuildCachedClient()
    }

    public func resetAllConnectionSettings() {
        unpairDevice()
        serverBaseURL = nil
        defaults.removeObject(forKey: SideloadSafeStorage.serverURLKey)
        rebuildCachedClient()
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
