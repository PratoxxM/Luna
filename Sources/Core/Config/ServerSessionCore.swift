import Foundation
import Observation

/// Platform bridge allowing `ServerSessionCore` to run in pure-Swift `LunaCore`
/// on Linux while delegating `AetherEngine`, `EngineTLS`, `UIKit`, and `os.Logger`
/// integrations to the Darwin host adapter.
public protocol SessionPlatformAdapting: Sendable {
    func registerSecret(_ secret: String)
    func unregisterSecret(_ secret: String)
    func discardEngineSessionCaches()
    func flushDeferredDisplayCriteriaResetIfIdle()
    func applyLANServerTrustPolicy(configuredHost: String?, allowSelfSignedLanTLS: Bool)
    func appVersionString() -> String
    func systemVersionString() -> String
    func hardwareModelString() -> String
    func logNonFatalWarning(_ message: String)
    func makeClient(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool,
        appVersion: String,
        osVersion: String
    ) -> LunaCoreClient
}

public struct NoopSessionPlatformAdapter: SessionPlatformAdapting {
    public init() {}

    public func registerSecret(_ secret: String) {}
    public func unregisterSecret(_ secret: String) {}
    public func discardEngineSessionCaches() {}
    public func flushDeferredDisplayCriteriaResetIfIdle() {}
    public func applyLANServerTrustPolicy(configuredHost: String?, allowSelfSignedLanTLS: Bool) {}
    public func appVersionString() -> String { SideloadSafeStorage.currentAppVersionString() }
    public func systemVersionString() -> String { "tvOS" }
    public func hardwareModelString() -> String { "AppleTV" }
    public func logNonFatalWarning(_ message: String) {}

    public func makeClient(
        baseURL: URL,
        deviceID: String,
        deviceToken: String?,
        roomName: String,
        hardwareProfile: String,
        allowSelfSignedLanTLS: Bool,
        appVersion: String,
        osVersion: String
    ) -> LunaCoreClient {
        LunaCoreClient(
            baseURL: baseURL,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            appVersion: appVersion,
            osVersion: osVersion
        )
    }
}

@MainActor
@Observable
public final class ServerSessionCore {
    public internal(set) var serverBaseURL: URL?
    public private(set) var serverLocalHostnameURL: URL?
    public private(set) var fallbackServerURL: URL?
    public private(set) var deviceToken: String?
    public let deviceID: String
    public var roomName: String
    public internal(set) var isRoomUnassigned: Bool = false
    public var hardwareProfile: String
    public var serverAtmosphere: String? = nil
    public internal(set) var serverEquipmentLabel: String? = nil
    public internal(set) var serverSpeakerLayout: String? = nil
    public internal(set) var availableRooms: [TvRoomDefinition] = HardwareProfilePreset.fallbackRooms
    public internal(set) var homeRefreshNonce: Int = 0
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
    public var lastPlaybackStopReceipt: PlaybackStopReceipt? {
        stopReceiptStore.lastReceipt
    }

    @ObservationIgnored internal let platform: any SessionPlatformAdapting
    @ObservationIgnored private let stopReceiptStore = PlaybackStopReceiptStore()
    @ObservationIgnored public internal(set) var deviceName: String
    @ObservationIgnored internal let defaults: UserDefaults
    @ObservationIgnored private let cachedAppVersion: String
    @ObservationIgnored private let cachedOSVersion: String
    @ObservationIgnored internal var cachedClient: LunaCoreClient?
    @ObservationIgnored internal var overrideSyncTask: Task<Void, Never>?
    @ObservationIgnored internal var profileSyncTask: Task<Void, Never>?
    @ObservationIgnored internal var capabilitiesSyncTask: Task<Void, Never>?
    @ObservationIgnored internal var overrideSyncDebounceNs: UInt64 = 350_000_000
    @ObservationIgnored internal var didSyncCapabilitiesThisLaunch: Bool = false
    @ObservationIgnored internal var pairingEpoch: UInt64 = 0
    @ObservationIgnored public private(set) var appliedTLSConfiguredHost: String?

    public var isPaired: Bool {
        serverBaseURL != nil && !(deviceToken ?? "").isEmpty
    }

    public func loadRecentSearches() -> [String] {
        SideloadSafeStorage.loadRecentSearches(defaults: defaults)
    }

    @discardableResult
    public func recordRecentSearch(_ term: String) -> [String] {
        SideloadSafeStorage.recordRecentSearch(term, defaults: defaults)
    }

    public func clearRecentSearches() {
        SideloadSafeStorage.clearRecentSearches(defaults: defaults)
    }

    public var effectiveAtmosphereRawValue: String? {
        if isRoomUnassigned {
            return "neutral"
        }
        return serverAtmosphere ?? matchedRoomDefinition()?.atmosphere
    }

    public var effectiveRoomSpeakerLayout: String {
        let matchedRoom = matchedRoomDefinition()
        return SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(
            speakerLayout: serverSpeakerLayout ?? matchedRoom?.speakerLayout,
            equipmentLabel: serverEquipmentLabel ?? matchedRoom?.equipmentLabel,
            hardwareProfile: hardwareProfile,
            roomName: roomName
        )
    }

    public func matchedRoomDefinition() -> TvRoomDefinition? {
        availableRooms.first {
            $0.roomName == roomName && $0.hardwareProfile == hardwareProfile
        } ?? availableRooms.first {
            $0.roomName.caseInsensitiveCompare(roomName) == .orderedSame
        } ?? availableRooms.first {
            $0.hardwareProfile == hardwareProfile
        }
    }

    internal func syncComfortRoomSpeakerLayout() {
        let resolved = effectiveRoomSpeakerLayout
        if comfort.roomAutoSpeakerLayout != resolved {
            comfort.roomAutoSpeakerLayout = resolved
        }
    }

    public init(
        defaults: UserDefaults = .standard,
        platform: any SessionPlatformAdapting = NoopSessionPlatformAdapter()
    ) {
        self.defaults = defaults
        self.platform = platform
        self.comfort = ComfortPreferences(defaults: defaults)
        self.deviceID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)
        self.cachedAppVersion = platform.appVersionString()
        self.cachedOSVersion = platform.systemVersionString()

        if let rawURL = defaults.string(forKey: SideloadSafeStorage.serverURLKey),
           let parsed = ServerFailoverPolicy.normalizeServerURL(rawURL) {
            self.serverBaseURL = parsed
        } else {
            self.serverBaseURL = nil
        }
        if let rawLocal = defaults.string(forKey: SideloadSafeStorage.serverLocalHostnameURLKey),
           let parsedLocal = ServerFailoverPolicy.normalizeServerURL(rawLocal) {
            self.serverLocalHostnameURL = parsedLocal
        } else {
            self.serverLocalHostnameURL = nil
        }
        if let rawFallback = defaults.string(forKey: SideloadSafeStorage.fallbackServerURLKey),
           let parsedFallback = ServerFailoverPolicy.normalizeServerURL(rawFallback) {
            self.fallbackServerURL = parsedFallback
        } else {
            self.fallbackServerURL = nil
        }

        let loadedToken = SideloadSafeStorage.loadDeviceToken(defaults: defaults)
        self.deviceToken = loadedToken
        if let loadedToken, loadedToken.count >= 8 {
            platform.registerSecret(loadedToken)
        }

        self.deviceName = defaults.string(forKey: SideloadSafeStorage.deviceNameKey) ?? "Apple TV"
        self.roomName = defaults.string(forKey: SideloadSafeStorage.roomNameKey) ?? "Kjellerstua"
        self.hardwareProfile = defaults.string(forKey: SideloadSafeStorage.hardwareProfileKey) ?? HardwareProfilePreset.dvFel714.rawValue
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = defaults.object(forKey: SideloadSafeStorage.allowSelfSignedLanTLSKey) as? Bool ?? true

        applyEngineTLSPolicy()
        rebuildCachedClient()
        syncComfortRoomSpeakerLayout()

        self.comfort.onSyncRequested = { [weak self] updatedOverrides in
            self?.scheduleOverridesSync(updatedOverrides)
        }
    }

    public init(
        previewConfiguration: PreviewLaunchConfiguration,
        platform: any SessionPlatformAdapting = NoopSessionPlatformAdapter()
    ) {
        let suiteName = "luna.v1.preview.\(previewConfiguration.screen.rawValue)"
        let ephemeralDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        ephemeralDefaults.removePersistentDomain(forName: suiteName)
        self.defaults = ephemeralDefaults
        self.platform = platform
        let previewComfort = ComfortPreferences(defaults: ephemeralDefaults)
        if previewConfiguration.screen == .playerNextEpisode {
            previewComfort.showNerdHUD = true
            previewComfort.autoPlayNextEpisode = true
        }
        self.comfort = previewComfort
        self.deviceID = "luna-preview-appletv"
        self.cachedAppVersion = platform.appVersionString()
        self.cachedOSVersion = platform.systemVersionString()
        self.serverBaseURL = PreviewMockFixtures.previewBaseURL
        self.serverLocalHostnameURL = nil
        self.fallbackServerURL = nil
        self.deviceToken = "preview-device-token"
        self.deviceName = "Apple TV 4K"
        self.roomName = "Stua"
        self.hardwareProfile = HardwareProfilePreset.hdr10512.rawValue
        self.serverAtmosphere = "living"
        self.serverEquipmentLabel = LunaCopy.roomEquipmentLabel(hardwareProfile: HardwareProfilePreset.hdr10512.rawValue)
        self.serverSpeakerLayout = HardwareProfilePreset.hdr10512.defaultSpeakerLayout
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = true
        self.cachedClient = PreviewMockFixtures.makeClient()
        syncComfortRoomSpeakerLayout()
        PreviewMockFixtures.prewarmHomeCache()
    }

    internal func rebuildCachedClient() {
        guard let base = serverBaseURL else {
            cachedClient = nil
            return
        }
        cachedClient = platform.makeClient(
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
        let debounceNs = overrideSyncDebounceNs
        let startEpoch = pairingEpoch
        overrideSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled,
                  let self,
                  self.pairingEpoch == startEpoch,
                  let client = self.makeClient() else { return }
            await self.performProfileSync(context: "overrides") {
                try await client.updateDeviceProfile(
                    overrides: overrides,
                    capabilities: DeviceHardwareCapabilities.asTvCapabilities
                )
            }
            if !Task.isCancelled, self.pairingEpoch == startEpoch {
                self.overrideSyncTask = nil
            }
        }
    }

    public func notifyContentMutated() {
        homeRefreshNonce &+= 1
    }

    public func recordPlaybackStopReceipt(_ receipt: PlaybackStopReceipt) {
        stopReceiptStore.record(receipt)
    }

    public func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration = .seconds(3)
    ) async -> PlaybackStopReceipt? {
        await stopReceiptStore.awaitReceipt(for: itemId, timeout: timeout)
    }

    public func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration = .seconds(3),
        recordedAfter: Date?,
        excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt? {
        await stopReceiptStore.awaitReceipt(
            for: itemId,
            timeout: timeout,
            recordedAfter: recordedAfter,
            excluding: preLaunchReceipt
        )
    }

    public func makeClient() -> LunaCoreClient? {
        cachedClient
    }

    public func makeClient(overrideBaseURL: URL) -> LunaCoreClient? {
        platform.makeClient(
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
        if let parsed = ServerFailoverPolicy.normalizeServerURL(trimmed) {
            fallbackServerURL = parsed
            defaults.set(parsed.absoluteString, forKey: SideloadSafeStorage.fallbackServerURLKey)
        }
    }

    public func completePairing(
        baseURL: URL,
        token: String,
        pairedDevice: TvPairedDeviceInfo,
        localHostnameURL: URL? = nil
    ) {
        pairingEpoch &+= 1
        overrideSyncTask?.cancel()
        overrideSyncTask = nil
        profileSyncTask?.cancel()
        profileSyncTask = nil
        capabilitiesSyncTask?.cancel()
        capabilitiesSyncTask = nil

        let previousToken = deviceToken
        if let old = previousToken, old != token, old.count >= 8 {
            platform.unregisterSecret(old)
        }
        if token.count >= 8, token != previousToken {
            platform.registerSecret(token)
        }
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
        self.serverEquipmentLabel = pairedDevice.equipmentLabel
        self.serverSpeakerLayout = pairedDevice.speakerLayout
        self.comfort.adoptServerOverrides(pairedDevice.overrides)
        self.didSyncCapabilitiesThisLaunch = pairedDevice.capabilities == DeviceHardwareCapabilities.asTvCapabilities

        defaults.set(baseURL.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
        defaults.set(pairedDevice.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        defaults.set(pairedDevice.roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(pairedDevice.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        applyEngineTLSPolicy()
        rebuildCachedClient()
        syncComfortRoomSpeakerLayout()
        homeRefreshNonce &+= 1
    }

    public func unpairDevice() {
        pairingEpoch &+= 1
        overrideSyncTask?.cancel()
        overrideSyncTask = nil
        profileSyncTask?.cancel()
        profileSyncTask = nil
        capabilitiesSyncTask?.cancel()
        capabilitiesSyncTask = nil
        if let old = deviceToken, old.count >= 8 {
            platform.unregisterSecret(old)
        }
        SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
        platform.discardEngineSessionCaches()
        platform.flushDeferredDisplayCriteriaResetIfIdle()
        LunaCoreSessionPool.shared.invalidateAll()
        CatalogBrowseMemoryCache.shared.clear()
        LibraryBrowseMemoryCache.shared.clear()
        ItemDetailMemoryCache.shared.clear()
        DiskSWRStore.clearMemory()
        Task { await DiskSWRStore.clearAllAsync() }
        deviceToken = nil
        serverAtmosphere = nil
        serverEquipmentLabel = nil
        serverSpeakerLayout = nil
        availableRooms = HardwareProfilePreset.fallbackRooms
        activePlaybackTarget = nil
        syncComfortRoomSpeakerLayout()
        homeRefreshNonce &+= 1
        rebuildCachedClient()
    }

    public func resetAllConnectionSettings() {
        unpairDevice()
        pairingEpoch &+= 1
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

    internal func applyEngineTLSPolicy() {
        let allowLan = allowSelfSignedLanTLS
        let configuredHost = serverBaseURL?.host?.lowercased()
        appliedTLSConfiguredHost = allowLan ? configuredHost : nil
        platform.applyLANServerTrustPolicy(configuredHost: configuredHost, allowSelfSignedLanTLS: allowLan)
    }
}
