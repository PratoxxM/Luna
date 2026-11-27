import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class SessionCoreURLProtocolMock: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])
    private static let recordedRequests = Mutex<[String: [URLRequest]]>([:])

    static func register(host: String, handler: @escaping Handler) {
        let key = host.lowercased()
        handlers.withLock { $0[key] = handler }
        recordedRequests.withLock { $0[key] = [] }
    }

    static func unregister(host: String) {
        let key = host.lowercased()
        _ = handlers.withLock { $0.removeValue(forKey: key) }
        _ = recordedRequests.withLock { $0.removeValue(forKey: key) }
    }

    static func requests(forHost host: String) -> [URLRequest] {
        recordedRequests.withLock { $0[host.lowercased()] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordedRequests.withLock { $0[host, default: []].append(request) }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSharedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SessionCoreURLProtocolMock.self]
        return URLSession(configuration: config)
    }
}

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

    init(session: URLSession = SessionCoreURLProtocolMock.makeSharedSession()) {
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

private final class CancellationMockSourcePickerClient: SourcePickerSessionClient, @unchecked Sendable {
    let lock = Mutex<[String]>([])

    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        prepareToken: String?
    ) async throws -> TvPrepareResponse {
        let candidate = TvCandidateInfo(
            candidateId: "cand-1",
            displayHeadline: "4K HDR10",
            releaseTitle: "Movie.2024.2160p",
            source: "nvme",
            tier: "nvme",
            resolution: "2160p",
            videoRangeType: "HDR10",
            dvProfile: nil,
            dvEnhancementLayer: nil,
            audioCodec: "TrueHD",
            sizeBytes: nil,
            tvScore: 1200,
            isActive: true,
            explanationChips: nil,
            releaseGroup: nil,
            isNorwegian: false
        )
        let session = TvPlaybackSession(
            sessionId: "sess-cancel-linux-1",
            streamToken: "stream-tok-cancel-1234",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            item: TvPlaybackItemContext(itemId: itemId, mediaType: "movie", ids: TvMediaIds(tmdb: 550), title: title),
            selectedCandidate: candidate,
            stream: TvStreamEndpoint(url: "/api/tv/v2/streams/sess-cancel-linux-1/master"),
            aetherConfig: TvAetherConfig(preferDualLayerDolbyVision: false, dolbyVisionHandling: "baseLayerOnly", matchContentEnabled: true, audioBridgeMode: "lossless")
        )
        return TvPrepareResponse(ok: true, prepareToken: "prep-cancel-linux", playbackSession: session)
    }

    func cancelInflightPlayback(sessionId: String?, resolveId: String?, itemId: String?, prepareToken: String?) async throws {}

    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse {
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
    }

    func sendHeartbeat(sessionId: String, state: String, positionSeconds: Double, durationSeconds: Double, completed: Bool?) async throws -> TvHeartbeatResponse {
        if state == "stopped" {
            lock.withLock { $0.append(sessionId) }
        }
        return TvHeartbeatResponse(ok: true, sessionId: sessionId, state: state)
    }
}

final class ServerSessionAndComfortTests: XCTestCase {
    @MainActor
    func testComfortPreferencesPersistenceOverridesDelayClampingAndAudioShaping() async throws {
        let suite = "luna.v1.test.comfort.linux.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("7.1", forKey: SideloadSafeStorage.speakerLayoutOverrideKey)

        let stdComfort = ComfortPreferences(defaults: defaults, memoryTier: .standard)
        XCTAssertEqual(stdComfort.lowResUpscaleMode, .off)
        XCTAssertFalse(stdComfort.upscalesFullHDVideo)
        XCTAssertEqual(stdComfort.speakerLayoutOverride, .auto)
        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.speakerLayoutOverrideKey), "auto")

        let highSuite = "luna.v1.test.comfort.high.\(UUID().uuidString)"
        let highDefaults = try XCTUnwrap(UserDefaults(suiteName: highSuite))
        defer { highDefaults.removePersistentDomain(forName: highSuite) }
        let highComfort = ComfortPreferences(defaults: highDefaults, memoryTier: .high2026)
        XCTAssertEqual(highComfort.lowResUpscaleMode, .auto)
        XCTAssertTrue(highComfort.upscalesFullHDVideo)

        var syncCalls: [TvDeviceOverrides] = []
        stdComfort.onSyncRequested = { syncCalls.append($0) }

        stdComfort.upscalesFullHDVideo = true
        XCTAssertEqual(syncCalls.count, 1, "upscalesFullHDVideo must trigger server comfort sync")
        XCTAssertEqual(syncCalls.last?.upscalesFullHDVideo, true)
        XCTAssertEqual(defaults.object(forKey: SideloadSafeStorage.fullHDUpscaleEnabledKey) as? Bool, true)
        XCTAssertTrue(ComfortPreferences(defaults: defaults, memoryTier: .standard).upscalesFullHDVideo)
        syncCalls.removeAll()

        stdComfort.adoptServerOverrides(
            TvDeviceOverrides(
                dualLayerOverride: "force_off",
                speakerLayoutOverride: "512",
                hdrSubtitlePreset: "soft_50",
                subtitleFontScale: 1.25,
                subtitleBoxOpacity: 0.4,
                autoPlayNextEpisode: false,
                smartNordicSubtitleRule: false
            )
        )
        XCTAssertTrue(syncCalls.isEmpty, "adoptServerOverrides must suppress sync echo")
        XCTAssertEqual(stdComfort.dualLayerOverride, .forceOff)
        XCTAssertEqual(stdComfort.speakerLayoutOverride, .atmos512)
        XCTAssertEqual(stdComfort.hdrSubtitlePreset, .soft50)
        XCTAssertEqual(stdComfort.subtitleFontSize, .large)
        XCTAssertEqual(stdComfort.subtitleBoxOpacity, .subtle35)
        XCTAssertFalse(stdComfort.autoPlayNextEpisode)
        XCTAssertFalse(stdComfort.smartNordicSubtitleRule)

        stdComfort.hdrSubtitlePreset = .soft50
        XCTAssertTrue(syncCalls.isEmpty, "Setting identical value must not trigger sync")
        stdComfort.hdrSubtitlePreset = .warm60
        XCTAssertEqual(syncCalls.count, 1)

        stdComfort.audioDelayMs = -5_000
        XCTAssertEqual(stdComfort.audioDelayMs, -2_000)
        stdComfort.adjustAudioDelay(byMs: 5_000)
        XCTAssertEqual(stdComfort.audioDelayMs, 2_000)
        stdComfort.resetAudioDelay()
        XCTAssertEqual(stdComfort.audioDelayMs, 0)

        stdComfort.speakerLayoutOverride = .auto
        stdComfort.roomAutoSpeakerLayout = "2.0"
        XCTAssertEqual(stdComfort.effectiveSpeakerLayout, "2.0")
        let stereoParams = AudioEnhancementMode.nightMode.shapingParameters(effectiveSpeakerLayout: stdComfort.effectiveSpeakerLayout)
        XCTAssertEqual(stereoParams.maxChannels, 2)
        XCTAssertTrue(stereoParams.usesNightCompressor)

        let reloaded = ComfortPreferences(defaults: defaults, memoryTier: .standard)
        XCTAssertEqual(reloaded.hdrSubtitlePreset, .warm60)
        XCTAssertEqual(reloaded.dualLayerOverride, .forceOff)
    }

    @MainActor
    func testServerSessionCorePairingUnpairAndShortTokenGuard() async throws {
        let suite = "luna.v1.test.session.pairing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let spy = SpySessionPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        XCTAssertFalse(core.isPaired)
        XCTAssertTrue(core.allowSelfSignedLanTLS)

        // K-4: Short token (< 8 chars) completes pairing without registering secret
        let primaryURL = try XCTUnwrap(URL(string: "https://media-box.local:8920"))
        core.completePairing(
            baseURL: primaryURL,
            token: "short",
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Stua TV",
                roomName: "Stua",
                hardwareProfile: "hdr10-512",
                speakerLayout: "5.1.2"
            )
        )
        XCTAssertTrue(core.isPaired)
        XCTAssertTrue(spy.state.withLock { $0.registeredSecrets }.isEmpty)
        XCTAssertEqual(core.serverLocalHostnameURL, primaryURL)
        XCTAssertEqual(core.effectiveRoomSpeakerLayout, "5.1.2")
        XCTAssertEqual(core.comfort.roomAutoSpeakerLayout, "5.1.2")
        XCTAssertEqual(core.appliedTLSConfiguredHost, "media-box.local")

        // Valid token (>= 8 chars) registers secret; re-pairing unregisters old secret
        let longToken1 = "device-token-alpha-1234"
        core.completePairing(
            baseURL: primaryURL,
            token: longToken1,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Stua TV",
                roomName: "Stua",
                hardwareProfile: "hdr10-512"
            )
        )
        XCTAssertEqual(spy.state.withLock { $0.registeredSecrets }, [longToken1])

        let longToken2 = "device-token-bravo-5678"
        core.completePairing(
            baseURL: primaryURL,
            token: longToken2,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Stua TV",
                roomName: "Stua",
                hardwareProfile: "hdr10-512"
            )
        )
        XCTAssertEqual(spy.state.withLock { $0.unregisteredSecrets }, [longToken1])
        XCTAssertEqual(spy.state.withLock { $0.registeredSecrets }, [longToken1, longToken2])

        core.unpairDevice()
        XCTAssertFalse(core.isPaired)
        XCTAssertNil(core.deviceToken)
        XCTAssertEqual(spy.state.withLock { $0.unregisteredSecrets }, [longToken1, longToken2])
        XCTAssertEqual(spy.state.withLock { $0.discardCacheCount }, 1)
        XCTAssertEqual(spy.state.withLock { $0.flushCriteriaCount }, 1)
        XCTAssertNotNil(core.serverBaseURL)

        core.resetAllConnectionSettings()
        XCTAssertNil(core.serverBaseURL)
        XCTAssertNil(core.serverLocalHostnameURL)
        XCTAssertNil(core.fallbackServerURL)
        XCTAssertNil(core.appliedTLSConfiguredHost)
    }

    @MainActor
    func testServerSessionCoreFailoverProbingBootstrapSyncAndProfileErrors() async throws {
        let primaryHost = "primary-\(UUID().uuidString.lowercased()).invalid"
        let backupHost = "backup-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.v1.test.session.failover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            SessionCoreURLProtocolMock.unregister(host: primaryHost)
            SessionCoreURLProtocolMock.unregister(host: backupHost)
            defaults.removePersistentDomain(forName: suite)
        }

        let patchStatus = Mutex(500)
        SessionCoreURLProtocolMock.register(host: primaryHost) { request in
            if request.url?.path == "/api/tv/v2/bootstrap" {
                throw URLError(.cannotConnectToHost)
            }
            let url = try XCTUnwrap(request.url)
            let code = patchStatus.withLock { $0 }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"error":"Profile sync error"}"#.utf8))
        }
        SessionCoreURLProtocolMock.register(host: backupHost) { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/api/tv/v2/bootstrap" {
                let json = #"""
                {
                  "ok": true,
                  "device": {
                    "deviceId": "dev-1",
                    "deviceName": "Loft TV",
                    "roomName": "Loft",
                    "hardwareProfile": "hdr10-512",
                    "speakerLayout": "5.1.2",
                    "atmosphere": "cinema"
                  },
                  "defaultRooms": [
                    {
                      "roomName": "Loft",
                      "hardwareProfile": "hdr10-512",
                      "atmosphere": "cinema",
                      "speakerLayout": "5.1.2"
                    }
                  ]
                }
                """#
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, Data(json.utf8))
            }
            let code = patchStatus.withLock { $0 }
            if code == -999 {
                throw URLError(.cancelled)
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"error":"sync failed"}"#.utf8))
        }

        let spy = SpySessionPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        core.overrideSyncDebounceNs = 10_000_000
        let secretToken = "super-secret-bearer-token-9999"
        core.completePairing(
            baseURL: try XCTUnwrap(URL(string: "https://\(primaryHost):8920")),
            token: secretToken,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Old TV",
                roomName: "Stua",
                hardwareProfile: "dv-fel-714",
                capabilities: DeviceHardwareCapabilities.asTvCapabilities
            )
        )
        core.setFallbackServerURL("https://\(backupHost):8920")

        let failedOver = await core.probeAndFailoverServerURLIfNeeded(timeoutSeconds: 2.0)
        XCTAssertTrue(failedOver)
        XCTAssertEqual(core.serverBaseURL?.host?.lowercased(), backupHost)
        XCTAssertEqual(core.roomName, "Loft")
        XCTAssertEqual(core.comfort.roomAutoSpeakerLayout, "5.1.2")
        XCTAssertEqual(core.effectiveAtmosphereRawValue, "cinema")
        await core.capabilitiesSyncTask?.value

        // K-1 Case 1: Non-fatal 500 logs warning without leaking secret token or URL
        core.comfort.hdrSubtitlePreset = .soft50
        await core.overrideSyncTask?.value
        XCTAssertTrue(core.isPaired)
        let warningsAfter500 = spy.state.withLock { $0.warnings }
        XCTAssertEqual(warningsAfter500.count, 1)
        XCTAssertTrue(warningsAfter500[0].contains("http_status=500"))
        XCTAssertFalse(warningsAfter500[0].contains(secretToken))
        XCTAssertFalse(warningsAfter500[0].contains(backupHost))

        // K-1 Case 2: Cancellation does not log warning or unpair
        patchStatus.withLock { $0 = -999 }
        core.setRoomAndProfile(roomName: "Loft", hardwareProfile: "hdr10-512")
        await core.profileSyncTask?.value
        XCTAssertTrue(core.isPaired)
        XCTAssertEqual(spy.state.withLock { $0.warnings }.count, 1)

        // K-1 Case 3: 401 unauthorized unpairs cleanly
        patchStatus.withLock { $0 = 401 }
        core.setRoomAndProfile(roomName: "Loft", hardwareProfile: "hdr10-512")
        await core.profileSyncTask?.value
        XCTAssertFalse(core.isPaired)
        XCTAssertEqual(spy.state.withLock { $0.unregisteredSecrets }, [secretToken])
    }

    @MainActor
    func testPlaybackPreferenceStoreConcurrentSafetyAndSourcePickerNSURLErrorCancelled() async throws {
        // K-5: Concurrent TaskGroup reads & writes via Mutex<UserDefaults>
        let suite = "luna.v1.test.prefs.concurrent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PlaybackPreferenceStore(suiteName: suite)
        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<24 {
                group.addTask {
                    let item = "movie:tmdb:\(idx)"
                    let cand = "cand-\(idx)"
                    store.setPreferNorwegianAudio(idx.isMultiple(of: 2), forItemId: item)
                    store.setSubtitleDelayMs(idx * 50, forCandidateId: cand)
                    _ = store.preferNorwegianAudio(forItemId: item)
                    _ = store.subtitleDelayMs(forCandidateId: cand)
                }
            }
        }
        XCTAssertTrue(store.preferNorwegianAudio(forItemId: "movie:tmdb:4"))
        XCTAssertFalse(store.preferNorwegianAudio(forItemId: "movie:tmdb:5"))
        XCTAssertEqual(store.subtitleDelayMs(forCandidateId: "cand-10"), 500)

        // K-6: SourcePickerViewModel catches NSURLErrorCancelled via LunaCoreError.isCancellation
        let pickerClient = CancellationMockSourcePickerClient()
        let vm = SourcePickerViewModel()
        let context = SourcePickerContext(itemId: "movie:tmdb:550", title: "Fight Club")
        var unauthCalls = 0
        await vm.loadCandidates(
            context: context,
            client: pickerClient,
            onUnauthorized: { unauthCalls += 1 }
        )
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.createdOrphanSessionId)
        XCTAssertEqual(unauthCalls, 0)
        XCTAssertEqual(pickerClient.lock.withLock { $0 }, ["sess-cancel-linux-1"])
    }
}
