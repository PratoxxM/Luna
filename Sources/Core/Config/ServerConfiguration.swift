import Foundation
import Observation
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

    public static var fallbackRooms: [TvRoomDefinition] {
        allCases.map { preset in
            TvRoomDefinition(
                roomName: preset.defaultRoomName,
                hardwareProfile: preset.rawValue,
                equipmentLabel: LunaCopy.roomEquipmentLabel(hardwareProfile: preset.rawValue),
                atmosphere: preset == .hdr10512 ? "living" : "cinema",
                label: preset.displayTitle,
                description: preset.technicalSummary
            )
        }
    }
}

@MainActor
@Observable
public final class AppSessionStore {
    public private(set) var serverBaseURL: URL?
    public private(set) var serverLocalHostnameURL: URL?
    public private(set) var fallbackServerURL: URL?
    public private(set) var deviceToken: String?
    public let deviceID: String
    public var roomName: String
    public private(set) var isRoomUnassigned: Bool = false
    public var hardwareProfile: String
    public var serverAtmosphere: String? = nil
    public private(set) var availableRooms: [TvRoomDefinition] = HardwareProfilePreset.fallbackRooms
    public private(set) var homeRefreshNonce: Int = 0
    public let comfort: ComfortPreferences

    public var allowSelfSignedLanTLS: Bool {
        didSet {
            defaults.set(allowSelfSignedLanTLS, forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey)
            LunaCoreSessionPool.shared.invalidateAll()
            applyEngineTLSPolicy()
            rebuildCachedClient()
        }
    }

    public var activePlaybackTarget: PlaybackLaunchRequest? = nil

    @ObservationIgnored private var deviceName: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cachedAppVersion: String
    @ObservationIgnored private let cachedOSVersion: String
    @ObservationIgnored private var cachedClient: LunaCoreClient?
    @ObservationIgnored private var overrideSyncTask: Task<Void, Never>?
    @ObservationIgnored private var profileSyncTask: Task<Void, Never>?
    @ObservationIgnored private var didSyncCapabilitiesThisLaunch: Bool = false
    @ObservationIgnored internal private(set) var appliedTLSConfiguredHost: String?

    public var isPaired: Bool {
        serverBaseURL != nil && !(deviceToken ?? "").isEmpty
    }

    public var effectiveRoomAtmosphere: LunaRoomAtmosphere {
        if isRoomUnassigned {
            return .neutral
        }
        let matchedRoom = availableRooms.first {
            $0.roomName == roomName && $0.hardwareProfile == hardwareProfile
        } ?? availableRooms.first { $0.hardwareProfile == hardwareProfile }
        let rawAtmos = serverAtmosphere ?? matchedRoom?.atmosphere
        return LunaRoomAtmosphere.resolve(
            atmosphere: rawAtmos,
            hardwareProfile: hardwareProfile,
            roomName: roomName
        )
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
        if let rawLocal = defaults.string(forKey: SideloadSafeStorage.serverLocalHostnameURLKey),
           let parsedLocal = Self.normalizeServerURL(rawLocal) {
            self.serverLocalHostnameURL = parsedLocal
        } else {
            self.serverLocalHostnameURL = nil
        }
        if let rawFallback = defaults.string(forKey: SideloadSafeStorage.fallbackServerURLKey),
           let parsedFallback = Self.normalizeServerURL(rawFallback) {
            self.fallbackServerURL = parsedFallback
        } else {
            self.fallbackServerURL = nil
        }

        let loadedToken = SideloadSafeStorage.loadDeviceToken(defaults: defaults)
        self.deviceToken = loadedToken
        if let loadedToken, loadedToken.count >= 8 {
            _ = EngineLog.registerSecret(loadedToken)
        }

        self.deviceName = defaults.string(forKey: SideloadSafeStorage.deviceNameKey) ?? "Apple TV"
        self.roomName = defaults.string(forKey: SideloadSafeStorage.roomNameKey) ?? "Kjellerstua"
        self.hardwareProfile = defaults.string(forKey: SideloadSafeStorage.hardwareProfileKey) ?? HardwareProfilePreset.dvFel714.rawValue
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = defaults.object(forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey) as? Bool ?? true

        applyEngineTLSPolicy()
        rebuildCachedClient()

        self.comfort.onSyncRequested = { [weak self] updatedOverrides in
            self?.scheduleOverridesSync(updatedOverrides)
        }
    }

    init(previewConfiguration: PreviewLaunchConfiguration) {
        let suiteName = "luna.v1.preview.\(previewConfiguration.screen.rawValue)"
        let ephemeralDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        ephemeralDefaults.removePersistentDomain(forName: suiteName)
        self.defaults = ephemeralDefaults
        self.comfort = ComfortPreferences(defaults: ephemeralDefaults)
        self.deviceID = "luna-preview-appletv"
        self.cachedAppVersion = Self.currentAppVersionString()
        self.cachedOSVersion = Self.currentSystemVersionString()
        self.serverBaseURL = PreviewMockFixtures.previewBaseURL
        self.serverLocalHostnameURL = nil
        self.fallbackServerURL = nil
        self.deviceToken = "preview-device-token"
        self.deviceName = "Apple TV 4K"
        self.roomName = "Stua"
        self.hardwareProfile = HardwareProfilePreset.hdr10512.rawValue
        self.serverAtmosphere = "living"
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = true
        self.cachedClient = PreviewMockFixtures.makeClient()
        PreviewMockFixtures.prewarmHomeCache()
    }

    private func rebuildCachedClient() {
        guard let base = serverBaseURL else {
            cachedClient = nil
            return
        }
        cachedClient = LunaCoreClient(
            baseURL: base,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            appVersion: cachedAppVersion,
            osVersion: cachedOSVersion
        )
    }

    private func scheduleOverridesSync(_ overrides: TvDeviceOverrides) {
        overrideSyncTask?.cancel()
        overrideSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, let client = self.makeClient() else { return }
            try? await client.updateDeviceProfile(
                overrides: overrides,
                capabilities: DeviceHardwareCapabilities.asTvCapabilities
            )
            if !Task.isCancelled {
                self.overrideSyncTask = nil
            }
        }
    }

    public func notifyContentMutated() {
        homeRefreshNonce &+= 1
    }

    public func makeClient() -> LunaCoreClient? {
        cachedClient
    }

    public func makeClient(overrideBaseURL: URL) -> LunaCoreClient? {
        LunaCoreClient(
            baseURL: overrideBaseURL,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            appVersion: cachedAppVersion,
            osVersion: cachedOSVersion
        )
    }

    public func setFallbackServerURL(_ rawURL: String?) {
        let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            fallbackServerURL = nil
            defaults.removeObject(forKey: SideloadSafeStorage.fallbackServerURLKey)
            return
        }
        if let parsed = Self.normalizeServerURL(trimmed) {
            fallbackServerURL = parsed
            defaults.set(parsed.absoluteString, forKey: SideloadSafeStorage.fallbackServerURLKey)
        }
    }

    public nonisolated static func isFailoverEligibleError(_ error: any Error) -> Bool {
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

    public nonisolated static func orderedFailoverCandidates(
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
            let scheme = primary.scheme?.lowercased() ?? "http"
            let port = primary.port ?? (scheme == "https" ? 443 : 80)
            if scheme == "https" && port == 8920 {
                appendCandidate(URL(string: "http://\(host):8090"))
            } else if scheme == "http" && port == 8090 {
                appendCandidate(URL(string: "https://\(host):8920"))
            }
        }
        appendCandidate(localHostnameURL)
        appendCandidate(fallbackServerURL)
        return candidates
    }

    @discardableResult
    public func probeAndFailoverServerURLIfNeeded(timeoutSeconds: TimeInterval = 3.0) async -> Bool {
        guard let currentPrimary = serverBaseURL, isPaired else { return false }
        let candidates = Self.orderedFailoverCandidates(
            primary: currentPrimary,
            localHostnameURL: serverLocalHostnameURL,
            fallbackServerURL: fallbackServerURL
        )
        guard !candidates.isEmpty else { return false }

        for candidate in candidates {
            guard !Task.isCancelled,
                  let probeClient = makeClient(overrideBaseURL: candidate) else {
                continue
            }
            do {
                let boot = try await probeClient.probeReachability(timeoutSeconds: timeoutSeconds)
                if serverBaseURL != currentPrimary {
                    return true
                }
                self.serverBaseURL = candidate
                defaults.set(candidate.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
                applyEngineTLSPolicy()
                rebuildCachedClient()
                syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
                homeRefreshNonce &+= 1
                return true
            } catch LunaCoreError.unauthorized {
                unpairDevice()
                return false
            } catch {
                continue
            }
        }
        return false
    }

    public func completePairing(
        baseURL: URL,
        token: String,
        pairedDevice: TvPairedDeviceInfo,
        localHostnameURL: URL? = nil
    ) {
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        _ = EngineLog.registerSecret(token)
        SideloadSafeStorage.saveDeviceToken(token, defaults: defaults)

        self.serverBaseURL = baseURL
        if let localHostnameURL {
            self.serverLocalHostnameURL = localHostnameURL
            defaults.set(localHostnameURL.absoluteString, forKey: SideloadSafeStorage.serverLocalHostnameURLKey)
        } else if baseURL.host?.lowercased().hasSuffix(".local") == true {
            self.serverLocalHostnameURL = baseURL
            defaults.set(baseURL.absoluteString, forKey: SideloadSafeStorage.serverLocalHostnameURLKey)
        }
        self.deviceToken = token
        self.deviceName = pairedDevice.deviceName
        self.roomName = pairedDevice.roomName
        self.isRoomUnassigned = pairedDevice.roomUnassigned ?? false
        self.hardwareProfile = pairedDevice.hardwareProfile
        self.serverAtmosphere = pairedDevice.atmosphere
        self.comfort.adoptServerOverrides(pairedDevice.overrides)
        self.didSyncCapabilitiesThisLaunch = pairedDevice.capabilities == DeviceHardwareCapabilities.asTvCapabilities

        defaults.set(baseURL.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
        defaults.set(pairedDevice.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        defaults.set(pairedDevice.roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(pairedDevice.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
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
        let nextUnassigned = device.roomUnassigned ?? false
        if nextUnassigned != isRoomUnassigned {
            self.isRoomUnassigned = nextUnassigned
        }
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
        if device.atmosphere != serverAtmosphere {
            self.serverAtmosphere = device.atmosphere
        }
        if overrideSyncTask == nil {
            self.comfort.adoptServerOverrides(device.overrides)
        }
        if let defaultRooms, !defaultRooms.isEmpty, defaultRooms != availableRooms {
            self.availableRooms = defaultRooms
        }
        if clientInputsChanged || cachedClient == nil {
            rebuildCachedClient()
        }
        let localCaps = DeviceHardwareCapabilities.asTvCapabilities
        if !didSyncCapabilitiesThisLaunch, device.capabilities != localCaps, let client = makeClient() {
            didSyncCapabilitiesThisLaunch = true
            Task { @MainActor in
                try? await client.updateDeviceProfile(capabilities: localCaps)
            }
        } else if device.capabilities == localCaps {
            didSyncCapabilitiesThisLaunch = true
        }
    }

    public func setRoomAndProfile(roomName: String, hardwareProfile: String) {
        self.roomName = roomName
        self.isRoomUnassigned = false
        self.hardwareProfile = hardwareProfile
        let matchedRoom = availableRooms.first {
            $0.roomName == roomName && $0.hardwareProfile == hardwareProfile
        } ?? availableRooms.first { $0.hardwareProfile == hardwareProfile }
        self.serverAtmosphere = matchedRoom?.atmosphere
        defaults.set(roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        profileSyncTask?.cancel()
        profileSyncTask = nil
        rebuildCachedClient()
        if let client = makeClient() {
            let localCaps = DeviceHardwareCapabilities.asTvCapabilities
            profileSyncTask = Task { @MainActor [weak self] in
                try? await client.updateDeviceProfile(
                    roomName: roomName,
                    hardwareProfile: hardwareProfile,
                    capabilities: localCaps
                )
                if !Task.isCancelled {
                    self?.profileSyncTask = nil
                }
            }
        }
        homeRefreshNonce &+= 1
    }

    public func refreshProfileFromServer() async {
        let previousRoom = roomName
        let previousProfile = hardwareProfile
        if let client = makeClient() {
            do {
                let boot = try await client.fetchBootstrap()
                syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
            } catch LunaCoreError.unauthorized {
                unpairDevice()
                return
            } catch where Self.isFailoverEligibleError(error) {
                if await probeAndFailoverServerURLIfNeeded() {
                    return
                }
            } catch {
                // Keep cached server values until next bootstrap succeeds
            }
        }
        if roomName != previousRoom || hardwareProfile != previousProfile {
            homeRefreshNonce &+= 1
        }
    }

    public nonisolated static func currentAppVersionString() -> String {
        SideloadSafeStorage.currentAppVersionString()
    }

    public nonisolated static func currentAppVersionString(infoDictionary: [String: Any]?) -> String {
        SideloadSafeStorage.currentAppVersionString(infoDictionary: infoDictionary)
    }

    public nonisolated static func currentAppVersionDisplayString() -> String {
        SideloadSafeStorage.currentAppVersionDisplayString()
    }

    public nonisolated static func currentAppVersionDisplayString(infoDictionary: [String: Any]?) -> String {
        SideloadSafeStorage.currentAppVersionDisplayString(infoDictionary: infoDictionary)
    }

    public func unpairDevice() {
        overrideSyncTask?.cancel()
        overrideSyncTask = nil
        profileSyncTask?.cancel()
        profileSyncTask = nil
        if let old = deviceToken, old.count >= 8 {
            EngineLog.unregisterSecret(old)
        }
        SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
        AetherEngine.discardPrewarmedSources()
        AetherEngine.discardRetainedSessionCache()
        PlayerAudioSessionCoordinator.shared.flushDeferredDisplayCriteriaResetIfIdle()
        LunaCoreSessionPool.shared.invalidateAll()
        CatalogBrowseMemoryCache.shared.clear()
        LibraryBrowseMemoryCache.shared.clear()
        ItemDetailMemoryCache.shared.clear()
        DiskSWRStore.clearMemory()
        Task { await DiskSWRStore.clearAllAsync() }
        deviceToken = nil
        serverAtmosphere = nil
        availableRooms = HardwareProfilePreset.fallbackRooms
        activePlaybackTarget = nil
        homeRefreshNonce &+= 1
        rebuildCachedClient()
    }

    public func resetAllConnectionSettings() {
        unpairDevice()
        serverBaseURL = nil
        serverLocalHostnameURL = nil
        fallbackServerURL = nil
        isRoomUnassigned = false
        defaults.removeObject(forKey: SideloadSafeStorage.serverURLKey)
        defaults.removeObject(forKey: SideloadSafeStorage.serverLocalHostnameURLKey)
        defaults.removeObject(forKey: SideloadSafeStorage.fallbackServerURLKey)
        applyEngineTLSPolicy()
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

    internal nonisolated static func shouldTrustServerHost(
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

    private func applyEngineTLSPolicy() {
        let allowLan = allowSelfSignedLanTLS
        let configuredHost = serverBaseURL?.host?.lowercased()
        appliedTLSConfiguredHost = allowLan ? configuredHost : nil
        if allowLan {
            EngineTLS.serverTrustEvaluator = { space in
                Self.shouldTrustServerHost(
                    space.host,
                    configuredHost: configuredHost,
                    allowSelfSignedLanTLS: true
                )
            }
        } else {
            EngineTLS.serverTrustEvaluator = nil
        }
    }
}
