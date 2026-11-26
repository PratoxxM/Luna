import Foundation
import Observation
import UIKit
import AetherBridge

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
    public private(set) var serverEquipmentLabel: String? = nil
    public private(set) var serverSpeakerLayout: String? = nil
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
    public var lastPlaybackStopReceipt: PlaybackStopReceipt? {
        stopReceiptStore.lastReceipt
    }

    @ObservationIgnored private let stopReceiptStore = PlaybackStopReceiptStore()
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

    public var effectiveRoomAtmosphere: LunaRoomAtmosphere {
        if isRoomUnassigned {
            return .neutral
        }
        let matchedRoom = matchedRoomDefinition()
        let rawAtmos = serverAtmosphere ?? matchedRoom?.atmosphere
        return LunaRoomAtmosphere.resolve(
            atmosphere: rawAtmos,
            hardwareProfile: hardwareProfile,
            roomName: roomName
        )
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

    private func matchedRoomDefinition() -> TvRoomDefinition? {
        availableRooms.first {
            $0.roomName == roomName && $0.hardwareProfile == hardwareProfile
        } ?? availableRooms.first {
            $0.roomName.caseInsensitiveCompare(roomName) == .orderedSame
        } ?? availableRooms.first {
            $0.hardwareProfile == hardwareProfile
        }
    }

    private func syncComfortRoomSpeakerLayout() {
        let resolved = effectiveRoomSpeakerLayout
        if comfort.roomAutoSpeakerLayout != resolved {
            comfort.roomAutoSpeakerLayout = resolved
        }
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
        syncComfortRoomSpeakerLayout()

        self.comfort.onSyncRequested = { [weak self] updatedOverrides in
            self?.scheduleOverridesSync(updatedOverrides)
        }
    }

    init(previewConfiguration: PreviewLaunchConfiguration) {
        let suiteName = "luna.v1.preview.\(previewConfiguration.screen.rawValue)"
        let ephemeralDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        ephemeralDefaults.removePersistentDomain(forName: suiteName)
        self.defaults = ephemeralDefaults
        let previewComfort = ComfortPreferences(defaults: ephemeralDefaults)
        if previewConfiguration.screen == .playerNextEpisode {
            previewComfort.showNerdHUD = true
            previewComfort.autoPlayNextEpisode = true
        }
        self.comfort = previewComfort
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
        self.serverEquipmentLabel = LunaCopy.roomEquipmentLabel(hardwareProfile: HardwareProfilePreset.hdr10512.rawValue)
        self.serverSpeakerLayout = HardwareProfilePreset.hdr10512.defaultSpeakerLayout
        self.activePlaybackTarget = nil
        self.allowSelfSignedLanTLS = true
        self.cachedClient = PreviewMockFixtures.makeClient()
        syncComfortRoomSpeakerLayout()
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
        ServerFailoverPolicy.isFailoverEligibleError(error)
    }

    public nonisolated static func orderedFailoverCandidates(
        primary: URL,
        localHostnameURL: URL?,
        fallbackServerURL: URL?
    ) -> [URL] {
        ServerFailoverPolicy.orderedFailoverCandidates(
            primary: primary,
            localHostnameURL: localHostnameURL,
            fallbackServerURL: fallbackServerURL
        )
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
        if device.equipmentLabel != serverEquipmentLabel {
            self.serverEquipmentLabel = device.equipmentLabel
        }
        if device.speakerLayout != serverSpeakerLayout {
            self.serverSpeakerLayout = device.speakerLayout
        }
        if overrideSyncTask == nil {
            self.comfort.adoptServerOverrides(device.overrides)
        }
        if let defaultRooms, !defaultRooms.isEmpty, defaultRooms != availableRooms {
            self.availableRooms = defaultRooms
        }
        syncComfortRoomSpeakerLayout()
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
        self.serverEquipmentLabel = matchedRoom?.equipmentLabel
        self.serverSpeakerLayout = matchedRoom?.speakerLayout
        syncComfortRoomSpeakerLayout()
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
        ServerFailoverPolicy.normalizeServerURL(raw)
    }

    internal nonisolated static func shouldTrustServerHost(
        _ host: String,
        configuredHost: String?,
        allowSelfSignedLanTLS: Bool
    ) -> Bool {
        ServerFailoverPolicy.shouldTrustServerHost(
            host,
            configuredHost: configuredHost,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS
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

extension AppSessionStore: TabSessionContext, SearchSessionContext, PairingSessionContext {
    public var hasActivePlayback: Bool {
        activePlaybackTarget != nil
    }

    public func makeHomeClient() -> (any HomeClientProviding)? {
        makeClient()
    }

    public func makeCatalogClient() -> (any CatalogClientProviding)? {
        makeClient()
    }

    public func makeLibraryClient() -> (any LibraryClientProviding)? {
        makeClient()
    }

    public func makeSearchClient() -> (any SearchClientProviding)? {
        makeClient()
    }

    public func probeAndFailoverServerURLIfNeeded() async -> Bool {
        await probeAndFailoverServerURLIfNeeded(timeoutSeconds: 3.0)
    }

    public var deviceMetadata: PairingDeviceMetadata {
        PairingDeviceMetadata(
            model: Self.currentHardwareModelString(),
            osVersion: Self.currentSystemVersionString(),
            appVersion: Self.currentAppVersionString()
        )
    }

    public func makePairingClient(baseURL: URL) -> (any PairingClientProviding)? {
        makeClient(overrideBaseURL: baseURL)
    }
}
