import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class SpySessionPlatformAdapter: SessionPlatformAdapting {
    struct State: Sendable {
        var registeredSecrets: [String] = []
        var unregisteredSecrets: [String] = []
        var discardCacheCount: Int = 0
        var flushCriteriaCount: Int = 0
        var appliedTLSPolicies: [(host: String?, allowLAN: Bool)] = []
        var warnings: [String] = []
    }

    let state = Mutex(State())
    let session: URLSession

    init(session: URLSession = LunaCoreMockURLProtocol.makeSession()) {
        self.session = session
    }

    func registerSecret(_ secret: String) {
        state.withLock { $0.registeredSecrets.append(secret) }
    }

    func unregisterSecret(_ secret: String) {
        state.withLock { $0.unregisteredSecrets.append(secret) }
    }

    func discardEngineSessionCaches() {
        state.withLock { $0.discardCacheCount += 1 }
    }

    func flushDeferredDisplayCriteriaResetIfIdle() {
        state.withLock { $0.flushCriteriaCount += 1 }
    }

    func applyLANServerTrustPolicy(configuredHost: String?, allowSelfSignedLanTLS: Bool) {
        state.withLock { $0.appliedTLSPolicies.append((configuredHost, allowSelfSignedLanTLS)) }
    }

    func appVersionString() -> String { SideloadSafeStorage.appMarketingVersion }
    func systemVersionString() -> String { "tvOS 26.0" }
    func hardwareModelString() -> String { "AppleTV14,1" }

    func logNonFatalWarning(_ message: String) {
        state.withLock { $0.warnings.append(message) }
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
            osVersion: osVersion,
            session: session,
            imageSession: session,
            externalImageSession: session
        )
    }
}

final class SideloadStorageAndSessionTests: XCTestCase {
    // MARK: - SideloadSafeStorage Keys, Token Roundtrip & Isolated Recent Searches

    func testSideloadSafeStorageLunaV1NamespaceTokenFallbackAndRecentSearches() throws {
        let allKeys = [
            SideloadSafeStorage.serverURLKey,
            SideloadSafeStorage.serverLocalHostnameURLKey,
            SideloadSafeStorage.fallbackServerURLKey,
            SideloadSafeStorage.deviceIDKey,
            SideloadSafeStorage.deviceNameKey,
            SideloadSafeStorage.roomNameKey,
            SideloadSafeStorage.hardwareProfileKey,
            SideloadSafeStorage.allowSelfSignedLanTLSKey,
            SideloadSafeStorage.hdrSubtitlePresetKey,
            SideloadSafeStorage.subtitleFontScaleKey,
            SideloadSafeStorage.subtitleBoxOpacityKey,
            SideloadSafeStorage.dualLayerOverrideKey,
            SideloadSafeStorage.speakerLayoutOverrideKey,
            SideloadSafeStorage.autoPlayNextEpisodeKey,
            SideloadSafeStorage.smartNordicSubtitleRuleKey,
            SideloadSafeStorage.recognizesBitmapSubtitleTextKey,
            SideloadSafeStorage.showNerdHUDKey,
            SideloadSafeStorage.lowResUpscaleModeKey,
            SideloadSafeStorage.fullHDUpscaleEnabledKey,
            SideloadSafeStorage.audioDelayMsKey,
            SideloadSafeStorage.audioEnhancementModeKey,
            SideloadSafeStorage.menuDisplayModeKey,
            SideloadSafeStorage.recentSearchesKey,
            SideloadSafeStorage.preferNorwegianAudioPrefix,
            SideloadSafeStorage.candidateSubtitleDelayPrefix,
        ]
        XCTAssertEqual(allKeys.count, 25)
        XCTAssertEqual(Set(allKeys).count, 25)
        for key in allKeys {
            XCTAssertTrue(key.hasPrefix("luna.v1."), "Key \(key) must keep luna.v1. namespace")
            XCTAssertFalse(key.contains("local.lunacore"))
            XCTAssertFalse(key.contains("lunacore.luna"))
        }
        XCTAssertEqual(SideloadSafeStorage.keychainService, "luna.v1.credentials")
        XCTAssertEqual(SideloadSafeStorage.tokenAccount, "device_bearer_token")
        XCTAssertEqual(SideloadSafeStorage.fallbackPrefix, "luna.v1.keychain_fallback.")

        let suiteA = "luna.v1.test.sideload.a.\(UUID().uuidString)"
        let suiteB = "luna.v1.test.sideload.b.\(UUID().uuidString)"
        let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteA))
        let defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        let previousToken = SideloadSafeStorage.loadDeviceToken(defaults: defaultsA)
        defer {
            if let previousToken {
                SideloadSafeStorage.saveDeviceToken(previousToken, defaults: defaultsA)
            } else {
                SideloadSafeStorage.deleteDeviceToken(defaults: defaultsA)
            }
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        let firstID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaultsA)
        XCTAssertTrue(firstID.hasPrefix("luna-"))
        XCTAssertEqual(SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaultsA), firstID)
        #if !canImport(Security)
        XCTAssertEqual(defaultsA.string(forKey: "luna.v1.keychain_fallback.device_id"), firstID)
        #endif

        let customID = "luna-custom-\(UUID().uuidString.lowercased())"
        defaultsA.set(customID, forKey: SideloadSafeStorage.deviceIDKey)
        XCTAssertEqual(SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaultsA), customID)

        let sampleToken = "tok_\(UUID().uuidString)"
        SideloadSafeStorage.saveDeviceToken(sampleToken, defaults: defaultsA)
        XCTAssertEqual(SideloadSafeStorage.loadDeviceToken(defaults: defaultsA), sampleToken)
        SideloadSafeStorage.deleteDeviceToken(defaults: defaultsA)
        XCTAssertNil(SideloadSafeStorage.loadDeviceToken(defaults: defaultsA))

        // Isolated recent searches
        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsA), [])
        _ = SideloadSafeStorage.recordRecentSearch("  Dune  ", defaults: defaultsA)
        _ = SideloadSafeStorage.recordRecentSearch("Lykkeland", defaults: defaultsA)
        XCTAssertEqual(SideloadSafeStorage.recordRecentSearch("dune", defaults: defaultsA), ["dune", "Lykkeland"])
        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsB), [])
        SideloadSafeStorage.clearRecentSearches(defaults: defaultsA)
        XCTAssertEqual(SideloadSafeStorage.loadRecentSearches(defaults: defaultsA), [])
    }

    // MARK: - BonjourServiceParser & ServerFailoverPolicy

    func testBonjourServiceParserDualStackAndServerFailoverPolicy() throws {
        XCTAssertFalse(BonjourDiscoveryPolicy.restrictsToIPv4Only)
        XCTAssertTrue(BonjourDiscoveryPolicy.allowsIPv4 && BonjourDiscoveryPolicy.allowsIPv6)
        XCTAssertEqual(BonjourDiscoveryPolicy.defaultAPIPath, "/api/tv/v2")

        let ipv4 = BonjourServiceParser.parseDiscoveredService(id: "svc-v4", serviceName: "LunaCore", rawHost: "192.0.2.10", port: 8090, txt: [:])
        XCTAssertEqual(ipv4?.baseURL.absoluteString, "http://192.0.2.10:8090")
        XCTAssertNil(ipv4?.localHostnameURL)

        let ipv6 = BonjourServiceParser.parseDiscoveredService(
            id: "svc-v6", serviceName: "LunaCore-v6", rawHost: "[2001:db8::10]", port: 8090,
            txt: ["https_port": "8920", "hostname": "lunacore"]
        )
        XCTAssertEqual(ipv6?.baseURL.absoluteString, "https://[2001:db8::10]:8920")
        XCTAssertEqual(ipv6?.localHostnameURL?.absoluteString, "https://lunacore.local:8920")
        XCTAssertNil(BonjourServiceParser.parseDiscoveredService(id: "svc-ll", serviceName: "LunaCore", rawHost: "[fe80::1%en0]", port: 8090, txt: [:]))

        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.timedOut)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.cannotConnectToHost)))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(URLError(.cancelled)))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(CancellationError()))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(LunaCoreError.unauthorized))

        let primary = try XCTUnwrap(URL(string: "https://media.example.test:8920"))
        let candidates = ServerFailoverPolicy.orderedFailoverCandidates(
            primary: primary,
            localHostnameURL: URL(string: "http://lunacore.local:8090"),
            fallbackServerURL: URL(string: "https://backup.example.test:8920")
        )
        XCTAssertEqual(candidates.map(\.absoluteString), [
            "http://media.example.test:8090",
            "http://lunacore.local:8090",
            "https://backup.example.test:8920",
        ])
        XCTAssertEqual(
            ServerFailoverPolicy.normalizeServerURL("  https://media.example.test:8920/api/tv/v2/ ")?.absoluteString,
            "https://media.example.test:8920"
        )
        XCTAssertEqual(
            ServerFailoverPolicy.normalizeServerURL("media.example.test:8090/api/tv/v1/")?.absoluteString,
            "http://media.example.test:8090"
        )
        XCTAssertNil(ServerFailoverPolicy.normalizeServerURL("ftp://media.example.test"))
    }

    // MARK: - ComfortPreferences, UpscaleLoadPolicy & Audio Shaping Parameters

    @MainActor
    func testComfortPreferencesSyncNilPreservationTierGatingAndAudioShaping() throws {
        let suite = "luna.v1.test.comfort.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(HardwareProfilePreset.dvFel714.defaultRoomName, "Kjellerstua")
        XCTAssertEqual(HardwareProfilePreset.hdr10512.defaultRoomName, "Stua")
        XCTAssertEqual(SubtitleFontSizePreset.fromScale(1.2).pointSizeValue, 50)
        XCTAssertEqual(SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "hdr10-512"), "Auto (5.1.2)")
        XCTAssertEqual(SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "dv-fel-714"), "Auto (7.1.4)")
        XCTAssertEqual(UpscaleLoadPolicy.resolve(lowResMode: .off, upscalesFullHDVideo: true), UpscaleLoadPolicy(upscalesLowResolutionVideo: false, scaler: .lanczos, upscalesFullHDVideo: true))
        XCTAssertEqual(UpscaleLoadPolicy.resolve(lowResMode: .animeLineArt, upscalesFullHDVideo: true), UpscaleLoadPolicy(upscalesLowResolutionVideo: true, scaler: .lineArt, upscalesFullHDVideo: false))

        defaults.set("7.1", forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
        let stdComfort = ComfortPreferences(defaults: defaults, memoryTier: .standard)
        XCTAssertEqual(stdComfort.lowResUpscaleMode, .off)
        XCTAssertFalse(stdComfort.upscalesFullHDVideo)
        XCTAssertEqual(stdComfort.speakerLayoutOverride, .auto)

        let highSuite = "luna.v1.test.comfort.high.\(UUID().uuidString)"
        let highDefaults = try XCTUnwrap(UserDefaults(suiteName: highSuite))
        defer { highDefaults.removePersistentDomain(forName: highSuite) }
        let highComfort = ComfortPreferences(defaults: highDefaults, memoryTier: .high2026)
        XCTAssertEqual(highComfort.lowResUpscaleMode, .auto)
        XCTAssertTrue(highComfort.upscalesFullHDVideo)
        XCTAssertNil(highComfort.toDeviceOverrides().lowResUpscaleMode)
        XCTAssertNil(highComfort.toDeviceOverrides().upscalesFullHDVideo)

        var syncCalls: [TvDeviceOverrides] = []
        highComfort.onSyncRequested = { syncCalls.append($0) }

        // Adopting nil upscale fields preserves .high2026 defaults without sync echo
        highComfort.adoptServerOverrides(
            TvDeviceOverrides(
                lowResUpscaleMode: nil,
                upscalesFullHDVideo: nil,
                menuDisplayMode: "hdr_60hz_qms",
                audioEnhancement: "dialogue_lift",
                showNerdHUD: true,
                recognizesBitmapSubtitleText: true
            )
        )
        XCTAssertTrue(syncCalls.isEmpty)
        XCTAssertEqual(highComfort.lowResUpscaleMode, .auto)
        XCTAssertTrue(highComfort.upscalesFullHDVideo)
        XCTAssertEqual(highComfort.menuDisplayMode, .preserveHDR60HzQMS)
        XCTAssertEqual(highComfort.audioEnhancement, .dialogueLift)
        XCTAssertTrue(highComfort.effectiveRecognizesBitmapSubtitleText(memoryTier: .high2026))
        XCTAssertFalse(highComfort.effectiveRecognizesBitmapSubtitleText(memoryTier: .standard))

        // Mutating all 6 synced keys emits onSyncRequested; audioDelayMs stays local
        highComfort.lowResUpscaleMode = .off
        highComfort.upscalesFullHDVideo = false
        highComfort.menuDisplayMode = .preserveExactMatch
        highComfort.audioEnhancement = .reference
        highComfort.showNerdHUD = false
        highComfort.recognizesBitmapSubtitleText = false
        XCTAssertEqual(syncCalls.count, 6)
        highComfort.audioDelayMs = -5_000
        XCTAssertEqual(highComfort.audioDelayMs, -2_000)
        highComfort.adjustAudioDelay(byMs: 5_000)
        XCTAssertEqual(highComfort.audioDelayMs, 2_000)
        highComfort.resetAudioDelay()
        XCTAssertEqual(highComfort.audioDelayMs, 0)
        XCTAssertEqual(syncCalls.count, 6)

        // Stereo 2.0 auto speaker layout downmix vs 7.1.4 object layout
        let autoStereo = SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout(speakerLayout: "2.0", equipmentLabel: "TV Stereo", hardwareProfile: "hdr10-512", roomName: "Soverom")
        let stereoNight = AudioEnhancementMode.nightMode.shapingParameters(effectiveSpeakerLayout: autoStereo)
        XCTAssertEqual(stereoNight.maxChannels, 2)
        XCTAssertEqual(stereoNight.lfeMixDB, -6.0)
        XCTAssertEqual(stereoNight.loudnessTargetLUFS, -20.0)
        XCTAssertTrue(stereoNight.usesNightCompressor)

        let atmosRef = AudioEnhancementMode.reference.shapingParameters(effectiveSpeakerLayout: "7.1.4")
        XCTAssertNil(atmosRef.maxChannels)
        XCTAssertNil(atmosRef.lfeMixDB)
    }

    // MARK: - ServerSessionCore Pairing, Failover & Lifecycle Races

    @MainActor
    func testServerSessionCorePairingShortTokenGuardAndFailoverProfileSync() async throws {
        let primaryHost = "primary-\(UUID().uuidString.lowercased()).invalid"
        let backupHost = "backup-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.v1.test.session.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            LunaCoreMockURLProtocol.unregister(host: primaryHost)
            LunaCoreMockURLProtocol.unregister(host: backupHost)
            defaults.removePersistentDomain(forName: suite)
        }

        let patchStatus = CoreLockedBox(500)
        LunaCoreMockURLProtocol.register(host: primaryHost) { req in
            if req.url?.path == "/api/tv/v2/bootstrap" { throw URLError(.cannotConnectToHost) }
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: patchStatus.get(), httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"error":"sync error"}"#.utf8))
        }
        LunaCoreMockURLProtocol.register(host: backupHost) { req in
            let url = try XCTUnwrap(req.url)
            if url.path == "/api/tv/v2/bootstrap" {
                let json = #"{"ok":true,"device":{"deviceId":"dev-1","deviceName":"Loft TV","roomName":"Loft","hardwareProfile":"hdr10-512","hardwareProfileExplicit":false,"speakerLayout":"5.1.2","atmosphere":"cinema"},"defaultRooms":[{"roomName":"Loft","hardwareProfile":"hdr10-512","atmosphere":"cinema","speakerLayout":"5.1.2"}]}"#
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(json.utf8))
            }
            let code = patchStatus.get()
            if code == -999 { throw URLError(.cancelled) }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"error":"sync failed"}"#.utf8))
        }

        let spy = SpySessionPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        core.overrideSyncDebounceNs = 10_000_000

        // Short token (< 8 chars) skips secret registration
        let primaryURL = try XCTUnwrap(URL(string: "https://\(primaryHost):8920"))
        core.completePairing(
            baseURL: primaryURL,
            token: "short",
            pairedDevice: TvPairedDeviceInfo(deviceId: core.deviceID, deviceName: "Stua TV", roomName: "Stua", hardwareProfile: "hdr10-512", speakerLayout: "5.1.2")
        )
        XCTAssertTrue(core.isPaired)
        XCTAssertTrue(spy.state.withLock { $0.registeredSecrets }.isEmpty)

        // Valid token registers secret and fails over to backupHost
        let secretToken = "super-secret-bearer-token-9999"
        core.completePairing(
            baseURL: primaryURL,
            token: secretToken,
            pairedDevice: TvPairedDeviceInfo(deviceId: core.deviceID, deviceName: "Old TV", roomName: "Stua", hardwareProfile: "dv-fel-714", capabilities: DeviceHardwareCapabilities.asTvCapabilities)
        )
        core.setFallbackServerURL("https://\(backupHost):8920")

        let failedOver = await core.probeAndFailoverServerURLIfNeeded(timeoutSeconds: 2.0)
        XCTAssertTrue(failedOver)
        XCTAssertEqual(core.serverBaseURL?.host?.lowercased(), backupHost)
        XCTAssertEqual(core.roomName, "Loft")
        XCTAssertFalse(core.isHardwareProfileExplicit)
        await core.capabilitiesSyncTask?.value

        // Non-fatal 500 logs redacted warning; cancellation is silent; 401 unpairs cleanly
        core.comfort.hdrSubtitlePreset = .soft50
        await core.overrideSyncTask?.value
        let warnings = spy.state.withLock { $0.warnings }
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("http_status=500"))
        XCTAssertFalse(warnings[0].contains(secretToken))
        XCTAssertFalse(warnings[0].contains(backupHost))

        patchStatus.set(-999)
        core.setRoomAndProfile(roomName: "Loft", hardwareProfile: "hdr10-512")
        await core.profileSyncTask?.value
        XCTAssertTrue(core.isPaired)

        patchStatus.set(401)
        core.setRoomAndProfile(roomName: "Loft", hardwareProfile: "hdr10-512")
        await core.profileSyncTask?.value
        XCTAssertFalse(core.isPaired)
        XCTAssertEqual(spy.state.withLock { $0.unregisteredSecrets }, [secretToken])

        core.resetAllConnectionSettings()
        XCTAssertNil(core.serverBaseURL)
        XCTAssertNil(core.fallbackServerURL)
    }

    @MainActor
    func testServerSessionCoreRepairingAndUnpairMidFlightRaces() async throws {
        let hostA = "race-a-\(UUID().uuidString.lowercased()).invalid"
        let hostB = "race-b-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.v1.test.race.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            LunaCoreMockURLProtocol.unregister(host: hostA)
            LunaCoreMockURLProtocol.unregister(host: hostB)
            defaults.removePersistentDomain(forName: suite)
        }

        let gateA = WireGate()
        LunaCoreMockURLProtocol.register(host: hostA, background: true) { req in
            gateA.suspendHandlerOnWire()
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"error":"unauthorized"}"#.utf8))
        }
        LunaCoreMockURLProtocol.register(host: hostB, background: true) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let spy = SpySessionPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        core.overrideSyncDebounceNs = 1_000_000
        let urlA = try XCTUnwrap(URL(string: "https://\(hostA):8920"))
        let urlB = try XCTUnwrap(URL(string: "https://\(hostB):8920"))

        core.completePairing(
            baseURL: urlA,
            token: "host-a-token-12345678",
            pairedDevice: TvPairedDeviceInfo(deviceId: core.deviceID, deviceName: "Host A", roomName: "Stua", hardwareProfile: "hdr10-512")
        )
        core.comfort.hdrSubtitlePreset = .soft50
        await gateA.waitUntilRequestOnWire()
        let suspendedTask = try XCTUnwrap(core.overrideSyncTask)

        core.completePairing(
            baseURL: urlB,
            token: "host-b-token-87654321",
            pairedDevice: TvPairedDeviceInfo(deviceId: core.deviceID, deviceName: "Host B", roomName: "Loft", hardwareProfile: "dv-fel-714")
        )
        gateA.release()
        await suspendedTask.value
        XCTAssertTrue(core.isPaired)
        XCTAssertEqual(core.deviceToken, "host-b-token-87654321")
        XCTAssertEqual(core.serverBaseURL, urlB)

        // Unpair while refreshProfileFromServer is suspended on wire ignores 200 OK ghost payload
        let refreshGate = WireGate()
        LunaCoreMockURLProtocol.register(host: hostB, background: true) { req in
            refreshGate.suspendHandlerOnWire()
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true,"device":{"deviceId":"ghost","deviceName":"GhostTV","roomName":"GhostRoom","hardwareProfile":"hdr10-512","atmosphere":"cinema"}}"#.utf8))
        }
        let refreshTask = Task { @MainActor in await core.refreshProfileFromServer() }
        await refreshGate.waitUntilRequestOnWire()
        core.unpairDevice()
        refreshGate.release()
        await refreshTask.value

        XCTAssertFalse(core.isPaired)
        XCTAssertNil(core.deviceToken)
        XCTAssertEqual(core.roomName, "Loft")
        XCTAssertNil(core.serverAtmosphere)
    }
}
