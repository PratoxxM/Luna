import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import XCTest
@testable import LunaCore

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class RaceURLProtocolMock: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])
    private let stoppedState = Mutex(false)

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host.lowercased()] = handler }
    }

    static func unregister(host: String) {
        _ = handlers.withLock { $0.removeValue(forKey: host.lowercased()) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let protoBox = UncheckedBox(self)
        let reqBox = UncheckedBox(request)
        DispatchQueue.global().async {
            let proto = protoBox.value
            do {
                let (response, data) = try handler(reqBox.value)
                proto.stoppedState.withLock { stopped in
                    guard !stopped else { return }
                    proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
                    proto.client?.urlProtocol(proto, didLoad: data)
                    proto.client?.urlProtocolDidFinishLoading(proto)
                }
            } catch {
                proto.stoppedState.withLock { stopped in
                    guard !stopped else { return }
                    proto.client?.urlProtocol(proto, didFailWithError: error)
                }
            }
        }
    }

    override func stopLoading() {
        stoppedState.withLock { $0 = true }
    }

    static func makeSharedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RaceURLProtocolMock.self]
        return URLSession(configuration: config)
    }
}

private final class RaceSpyPlatformAdapter: SessionPlatformAdapting {
    struct State: Sendable {
        var registeredSecrets: [String] = []
        var unregisteredSecrets: [String] = []
        var warnings: [String] = []
    }

    let state = Mutex(State())
    let session: URLSession

    init(session: URLSession = RaceURLProtocolMock.makeSharedSession()) {
        self.session = session
    }

    func registerSecret(_ secret: String) {
        state.withLock { $0.registeredSecrets.append(secret) }
    }

    func unregisterSecret(_ secret: String) {
        state.withLock { $0.unregisteredSecrets.append(secret) }
    }

    func discardEngineSessionCaches() {}
    func flushDeferredDisplayCriteriaResetIfIdle() {}
    func applyLANServerTrustPolicy(configuredHost: String?, allowSelfSignedLanTLS: Bool) {}
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

private final class WireGate: Sendable {
    private let entered = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let didEnter = Mutex(false)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func waitUntilRequestOnWire() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alreadyEntered = didEnter.withLock { enteredFlag -> Bool in
                if enteredFlag { return true }
                entered.withLock { $0 = cont }
                return false
            }
            if alreadyEntered {
                cont.resume()
            }
        }
    }

    func suspendHandlerOnWire() {
        let cont = didEnter.withLock { flag -> CheckedContinuation<Void, Never>? in
            flag = true
            return entered.withLock { c in
                let saved = c
                c = nil
                return saved
            }
        }
        cont?.resume()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(5))
    }

    func release() {
        releaseSemaphore.signal()
    }
}

final class ServerSessionLifecycleRaceTests: XCTestCase {
    @MainActor
    func testRepairingToHostBWhileHostAOverrideSyncReturns401KeepsHostBPaired() async throws {
        let hostA = "host-a-\(UUID().uuidString.lowercased()).invalid"
        let hostB = "host-b-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.v1.test.race.2b.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            RaceURLProtocolMock.unregister(host: hostA)
            RaceURLProtocolMock.unregister(host: hostB)
            defaults.removePersistentDomain(forName: suite)
        }

        let gate = WireGate()
        RaceURLProtocolMock.register(host: hostA) { request in
            gate.suspendHandlerOnWire()
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"error":"unauthorized"}"#.utf8))
        }
        RaceURLProtocolMock.register(host: hostB) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let spy = RaceSpyPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        core.overrideSyncDebounceNs = 1_000_000

        let hostAURL = try XCTUnwrap(URL(string: "https://\(hostA):8920"))
        let hostBURL = try XCTUnwrap(URL(string: "https://\(hostB):8920"))
        let hostAToken = "host-a-token-12345678"
        let hostBToken = "host-b-token-87654321"

        core.completePairing(
            baseURL: hostAURL,
            token: hostAToken,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Host A TV",
                roomName: "Stua",
                hardwareProfile: "hdr10-512"
            )
        )

        // Trigger debounced overrideSyncTask (PATCH /api/tv/v2/device/profile) against hostA
        core.comfort.hdrSubtitlePreset = .soft50
        await gate.waitUntilRequestOnWire()
        let suspendedOverrideTask = try XCTUnwrap(core.overrideSyncTask)

        // Re-pair to hostB while hostA's PATCH is suspended on the wire
        core.completePairing(
            baseURL: hostBURL,
            token: hostBToken,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Host B TV",
                roomName: "Loft",
                hardwareProfile: "dv-fel-714"
            )
        )
        XCTAssertNil(core.overrideSyncTask)

        // Release hostA returning 401 Unauthorized and await task termination
        gate.release()
        await suspendedOverrideTask.value

        XCTAssertTrue(core.isPaired)
        XCTAssertEqual(core.deviceToken, hostBToken)
        XCTAssertEqual(core.serverBaseURL, hostBURL)
        XCTAssertTrue(spy.state.withLock { $0.warnings }.isEmpty)

        // Also verify pairingEpoch prevents an uncancelled performProfileSync 401 from unpairing hostB
        let epochGate = WireGate()
        RaceURLProtocolMock.register(host: hostA) { request in
            epochGate.suspendHandlerOnWire()
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":false,"error":"unauthorized"}"#.utf8))
        }
        let staleClient = try XCTUnwrap(core.makeClient(overrideBaseURL: hostAURL))
        let staleOverrides = core.comfort.toDeviceOverrides()
        let uncancelledSync = Task { @MainActor in
            await core.performProfileSync(context: "overrides") {
                try await staleClient.updateDeviceProfile(
                    overrides: staleOverrides,
                    capabilities: DeviceHardwareCapabilities.asTvCapabilities
                )
            }
        }
        await epochGate.waitUntilRequestOnWire()
        core.completePairing(
            baseURL: hostBURL,
            token: hostBToken,
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Host B TV",
                roomName: "Loft",
                hardwareProfile: "dv-fel-714"
            )
        )
        epochGate.release()
        await uncancelledSync.value

        XCTAssertTrue(core.isPaired)
        XCTAssertEqual(core.deviceToken, hostBToken)
        XCTAssertTrue(spy.state.withLock { $0.warnings }.isEmpty)
    }

    @MainActor
    func testUnpairWhileFailoverProbeAndBootstrapRefreshInFlightIgnores200Responses() async throws {
        let primaryHost = "primary-2c-\(UUID().uuidString.lowercased()).invalid"
        let backupHost = "backup-2c-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.v1.test.race.2c.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            RaceURLProtocolMock.unregister(host: primaryHost)
            RaceURLProtocolMock.unregister(host: backupHost)
            defaults.removePersistentDomain(forName: suite)
        }

        let ghostBootstrapJSON = #"""
        {
          "ok": true,
          "device": {
            "deviceId": "dev-ghost",
            "deviceName": "GhostTV",
            "roomName": "GhostRoom",
            "hardwareProfile": "hdr10-512",
            "atmosphere": "cinema",
            "overrides": {
              "dualLayerOverride": "force_off"
            }
          }
        }
        """#

        let failoverGate = WireGate()
        RaceURLProtocolMock.register(host: primaryHost) { _ in
            throw URLError(.cannotConnectToHost)
        }
        RaceURLProtocolMock.register(host: backupHost) { request in
            failoverGate.suspendHandlerOnWire()
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(ghostBootstrapJSON.utf8))
        }

        let spy = RaceSpyPlatformAdapter()
        let core = ServerSessionCore(defaults: defaults, platform: spy)
        let primaryURL = try XCTUnwrap(URL(string: "https://\(primaryHost):8920"))
        core.completePairing(
            baseURL: primaryURL,
            token: "valid-token-primary-1234",
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Old TV",
                roomName: "Stua",
                hardwareProfile: "dv-fel-714",
                atmosphere: "living",
                capabilities: DeviceHardwareCapabilities.asTvCapabilities
            )
        )
        core.setFallbackServerURL("https://\(backupHost):8920")

        let probeTask = Task { @MainActor in
            await core.probeAndFailoverServerURLIfNeeded(timeoutSeconds: 2.0)
        }
        await failoverGate.waitUntilRequestOnWire()

        core.unpairDevice()
        failoverGate.release()

        let failoverApplied = await probeTask.value
        XCTAssertFalse(failoverApplied)
        XCTAssertFalse(core.isPaired)
        XCTAssertNil(core.deviceToken)
        XCTAssertEqual(core.deviceName, "Old TV")
        XCTAssertEqual(core.roomName, "Stua")
        XCTAssertNil(core.serverAtmosphere)
        XCTAssertEqual(core.comfort.dualLayerOverride, .auto)

        // Calling failover when already unpaired must immediately return false
        let unpairedProbeResult = await core.probeAndFailoverServerURLIfNeeded(timeoutSeconds: 2.0)
        XCTAssertFalse(unpairedProbeResult)

        // Also verify refreshProfileFromServer() ignores 200 OK bootstrap if unpaired mid-flight
        let refreshGate = WireGate()
        RaceURLProtocolMock.register(host: primaryHost) { request in
            refreshGate.suspendHandlerOnWire()
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(ghostBootstrapJSON.utf8))
        }
        core.completePairing(
            baseURL: primaryURL,
            token: "valid-token-refresh-5678",
            pairedDevice: TvPairedDeviceInfo(
                deviceId: core.deviceID,
                deviceName: "Old TV",
                roomName: "Stua",
                hardwareProfile: "dv-fel-714",
                atmosphere: "living",
                capabilities: DeviceHardwareCapabilities.asTvCapabilities
            )
        )

        let refreshTask = Task { @MainActor in
            await core.refreshProfileFromServer()
        }
        await refreshGate.waitUntilRequestOnWire()

        core.unpairDevice()
        refreshGate.release()
        await refreshTask.value

        XCTAssertFalse(core.isPaired)
        XCTAssertNil(core.deviceToken)
        XCTAssertEqual(core.deviceName, "Old TV")
        XCTAssertEqual(core.roomName, "Stua")
        XCTAssertNil(core.serverAtmosphere)
        XCTAssertEqual(core.comfort.dualLayerOverride, .auto)
    }
}
