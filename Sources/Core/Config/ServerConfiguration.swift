import Foundation
import Observation
import UIKit
import AetherBridge
import os

private struct DarwinSessionPlatformAdapter: SessionPlatformAdapting {
    private static let logger = Logger(subsystem: "local.lunacore.luna", category: "SessionSync")

    func registerSecret(_ secret: String) {
        _ = EngineLog.registerSecret(secret)
    }

    func unregisterSecret(_ secret: String) {
        EngineLog.unregisterSecret(secret)
    }

    func discardEngineSessionCaches() {
        MainActor.assumeIsolated {
            AetherEngine.discardPrewarmedSources()
            AetherEngine.discardRetainedSessionCache()
        }
    }

    func flushDeferredDisplayCriteriaResetIfIdle() {
        MainActor.assumeIsolated {
            PlayerAudioSessionCoordinator.shared.flushDeferredDisplayCriteriaResetIfIdle()
        }
    }

    func applyLANServerTrustPolicy(configuredHost: String?, allowSelfSignedLanTLS: Bool) {
        if allowSelfSignedLanTLS {
            EngineTLS.serverTrustEvaluator = { space in
                ServerFailoverPolicy.shouldTrustServerHost(
                    space.host,
                    configuredHost: configuredHost,
                    allowSelfSignedLanTLS: true
                )
            }
        } else {
            EngineTLS.serverTrustEvaluator = nil
        }
    }

    func appVersionString() -> String {
        SideloadSafeStorage.currentAppVersionString()
    }

    func systemVersionString() -> String {
        MainActor.assumeIsolated {
            "tvOS \(UIDevice.current.systemVersion)"
        }
    }

    func hardwareModelString() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }
        return machine ?? MainActor.assumeIsolated { UIDevice.current.model }
    }

    func logNonFatalWarning(_ message: String) {
        Self.logger.warning("\(message, privacy: .public)")
    }

    func makeClient(
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
public final class AppSessionStore {
    public let core: ServerSessionCore

    public var serverBaseURL: URL? { core.serverBaseURL }
    public var serverLocalHostnameURL: URL? { core.serverLocalHostnameURL }
    public var fallbackServerURL: URL? { core.fallbackServerURL }
    public var deviceToken: String? { core.deviceToken }
    public var deviceID: String { core.deviceID }
    public var roomName: String {
        get { core.roomName }
        set { core.roomName = newValue }
    }
    public var isRoomUnassigned: Bool { core.isRoomUnassigned }
    public var hardwareProfile: String {
        get { core.hardwareProfile }
        set { core.hardwareProfile = newValue }
    }
    public var serverAtmosphere: String? {
        get { core.serverAtmosphere }
        set { core.serverAtmosphere = newValue }
    }
    public var serverEquipmentLabel: String? { core.serverEquipmentLabel }
    public var serverSpeakerLayout: String? { core.serverSpeakerLayout }
    public var availableRooms: [TvRoomDefinition] { core.availableRooms }
    public var homeRefreshNonce: Int { core.homeRefreshNonce }
    public var comfort: ComfortPreferences { core.comfort }

    public var allowSelfSignedLanTLS: Bool {
        get { core.allowSelfSignedLanTLS }
        set { core.allowSelfSignedLanTLS = newValue }
    }

    public var activePlaybackTarget: PlaybackLaunchRequest? {
        get { core.activePlaybackTarget }
        set { core.activePlaybackTarget = newValue }
    }

    public var lastPlaybackStopReceipt: PlaybackStopReceipt? {
        core.lastPlaybackStopReceipt
    }

    internal var appliedTLSConfiguredHost: String? {
        core.appliedTLSConfiguredHost
    }

    public var isPaired: Bool {
        core.isPaired
    }

    public var effectiveRoomAtmosphere: LunaRoomAtmosphere {
        if core.isRoomUnassigned {
            return .neutral
        }
        return LunaRoomAtmosphere.resolve(
            atmosphere: core.effectiveAtmosphereRawValue,
            hardwareProfile: core.hardwareProfile,
            roomName: core.roomName
        )
    }

    public var effectiveRoomSpeakerLayout: String {
        core.effectiveRoomSpeakerLayout
    }

    public init(defaults: UserDefaults = .standard) {
        self.core = ServerSessionCore(defaults: defaults, platform: DarwinSessionPlatformAdapter())
    }

    init(previewConfiguration: PreviewLaunchConfiguration) {
        self.core = ServerSessionCore(
            previewConfiguration: previewConfiguration,
            platform: DarwinSessionPlatformAdapter()
        )
    }

    public func loadRecentSearches() -> [String] { core.loadRecentSearches() }

    @discardableResult
    public func recordRecentSearch(_ term: String) -> [String] { core.recordRecentSearch(term) }

    public func clearRecentSearches() { core.clearRecentSearches() }

    public func notifyContentMutated() { core.notifyContentMutated() }

    public func recordPlaybackStopReceipt(_ receipt: PlaybackStopReceipt) {
        core.recordPlaybackStopReceipt(receipt)
    }

    public func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration = .seconds(3)
    ) async -> PlaybackStopReceipt? {
        await core.awaitPlaybackStopReceipt(for: itemId, timeout: timeout)
    }

    public func awaitPlaybackStopReceipt(
        for itemId: String,
        timeout: Duration = .seconds(3),
        recordedAfter: Date?,
        excluding preLaunchReceipt: PlaybackStopReceipt?
    ) async -> PlaybackStopReceipt? {
        await core.awaitPlaybackStopReceipt(
            for: itemId,
            timeout: timeout,
            recordedAfter: recordedAfter,
            excluding: preLaunchReceipt
        )
    }

    public func makeClient() -> LunaCoreClient? { core.makeClient() }

    public func makeClient(overrideBaseURL: URL) -> LunaCoreClient? {
        core.makeClient(overrideBaseURL: overrideBaseURL)
    }

    public func setFallbackServerURL(_ rawURL: String?) {
        core.setFallbackServerURL(rawURL)
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
        await core.probeAndFailoverServerURLIfNeeded(timeoutSeconds: timeoutSeconds)
    }

    public func completePairing(
        baseURL: URL,
        token: String,
        pairedDevice: TvPairedDeviceInfo,
        localHostnameURL: URL? = nil
    ) {
        core.completePairing(
            baseURL: baseURL,
            token: token,
            pairedDevice: pairedDevice,
            localHostnameURL: localHostnameURL
        )
    }

    public func syncFromBootstrap(_ device: TvPairedDeviceInfo, defaultRooms: [TvRoomDefinition]? = nil) {
        core.syncFromBootstrap(device, defaultRooms: defaultRooms)
    }

    public func setRoomAndProfile(roomName: String, hardwareProfile: String) {
        core.setRoomAndProfile(roomName: roomName, hardwareProfile: hardwareProfile)
    }

    public func refreshProfileFromServer() async {
        await core.refreshProfileFromServer()
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

    public func unpairDevice() { core.unpairDevice() }

    public func resetAllConnectionSettings() { core.resetAllConnectionSettings() }

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
}

extension AppSessionStore: TabSessionContext, SearchSessionContext, PairingSessionContext {
    public var hasActivePlayback: Bool {
        core.hasActivePlayback
    }

    public func makeHomeClient() -> (any HomeClientProviding)? { core.makeHomeClient() }
    public func makeCatalogClient() -> (any CatalogClientProviding)? { core.makeCatalogClient() }
    public func makeLibraryClient() -> (any LibraryClientProviding)? { core.makeLibraryClient() }
    public func makeSearchClient() -> (any SearchClientProviding)? { core.makeSearchClient() }

    public func probeAndFailoverServerURLIfNeeded() async -> Bool {
        await core.probeAndFailoverServerURLIfNeeded()
    }

    public var deviceMetadata: PairingDeviceMetadata {
        PairingDeviceMetadata(
            model: Self.currentHardwareModelString(),
            osVersion: Self.currentSystemVersionString(),
            appVersion: Self.currentAppVersionString()
        )
    }

    public func makePairingClient(baseURL: URL) -> (any PairingClientProviding)? {
        core.makePairingClient(baseURL: baseURL)
    }
}
