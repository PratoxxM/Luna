import Foundation
import XCTest
@testable import Luna

final class BonjourServerBrowserTests: XCTestCase {
    func testParseDiscoveredServiceHandlesIPv4IPv6TLSOverrideAndTxtApiPath() {
        XCTAssertFalse(BonjourDiscoveryPolicy.restrictsToIPv4Only)
        XCTAssertTrue(BonjourDiscoveryPolicy.allowsIPv4)
        XCTAssertTrue(BonjourDiscoveryPolicy.allowsIPv6)

        let httpServer = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore._lunacore._tcp.local.",
            serviceName: "LunaCore",
            rawHost: "lunacore.local",
            port: 8090,
            txt: [:]
        )
        XCTAssertEqual(httpServer?.baseURL.absoluteString, "http://lunacore.local:8090")
        XCTAssertEqual(httpServer?.apiPath, "/api/tv/v2")
        XCTAssertEqual(httpServer?.displayAddress, "http://lunacore.local:8090")

        let tlsServer = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore._lunacore._tcp.local.",
            serviceName: "LunaCore",
            rawHost: "lunacore.example.test",
            port: 8090,
            txt: ["https_port": "8920", "api": "/api/tv/v2"]
        )
        XCTAssertEqual(tlsServer?.baseURL.absoluteString, "https://lunacore.example.test:8920")
        XCTAssertEqual(tlsServer?.apiPath, "/api/tv/v2")

        let tlsPortAlias = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore-2._lunacore._tcp.local.",
            serviceName: "LunaCore-2",
            rawHost: "[2001:db8::1]",
            port: 8090,
            txt: ["tls_port": " 8920 ", "api": "  "]
        )
        XCTAssertEqual(tlsPortAlias?.baseURL.absoluteString, "https://[2001:db8::1]:8920")
        XCTAssertEqual(tlsPortAlias?.apiPath, "/api/tv/v2")

        let zoneStrippedHostname = BonjourServerBrowser.parseDiscoveredService(
            id: "svc",
            serviceName: "LunaCore",
            rawHost: "lunacore.local%en0",
            port: 8090,
            txt: [:]
        )
        XCTAssertEqual(zoneStrippedHostname?.baseURL.absoluteString, "http://lunacore.local:8090")

        // Link-local IPv6 with interface scope ID must be rejected
        XCTAssertNil(
            BonjourServerBrowser.parseDiscoveredService(
                id: "link-local-v6",
                serviceName: "LunaCore",
                rawHost: "[fe80::1%en0]",
                port: 8090,
                txt: [:]
            )
        )

        // Invalid port or empty host must be rejected
        XCTAssertNil(
            BonjourServerBrowser.parseDiscoveredService(
                id: "bad-port",
                serviceName: "LunaCore",
                rawHost: "lunacore.local",
                port: 0,
                txt: [:]
            )
        )
        XCTAssertNil(
            BonjourServerBrowser.parseDiscoveredService(
                id: "empty-host",
                serviceName: "LunaCore",
                rawHost: "   ",
                port: 8090,
                txt: [:]
            )
        )
    }

    @MainActor
    func testBrowserStartAndStopUpdateSearchingStateCleanly() {
        let browser = BonjourServerBrowser()
        XCTAssertFalse(browser.isSearching)
        XCTAssertTrue(browser.servers.isEmpty)

        browser.start()
        XCTAssertTrue(browser.isSearching)

        browser.stop()
        XCTAssertFalse(browser.isSearching)
    }

    @MainActor
    func testResolveTimeoutPrunesStalledConnectionCleanly() async {
        let browser = BonjourServerBrowser(resolveTimeoutNanoseconds: 35_000_000)
        browser.beginResolve(
            key: "stalled._lunacore._tcp.local.",
            endpoint: .hostPort(host: "127.0.0.1", port: 9),
            serviceName: "LunaCore",
            txt: [:]
        )
        XCTAssertEqual(browser.activeResolverCount, 1)

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(browser.activeResolverCount, 0)
        browser.stop()
    }

    @MainActor
    func testRapidBeginResolveReplacementIgnoresStaleReadyAndCancellationCallbacks() async throws {
        let key = "lunacore._lunacore._tcp.local."
        let browser = BonjourServerBrowser(resolveTimeoutNanoseconds: 60_000_000)
        defer { browser.stop() }

        browser.beginResolve(
            key: key,
            endpoint: .hostPort(host: .name("stale-host.example.test", nil), port: 8090),
            serviceName: "StaleServer",
            txt: [:]
        )
        let firstConnId = try XCTUnwrap(browser.activeResolverId(for: key))
        let firstToken = try XCTUnwrap(browser.activeResolverToken(for: key))

        browser.beginResolve(
            key: key,
            endpoint: .hostPort(host: .name("active-host.example.test", nil), port: 8090),
            serviceName: "ActiveServer",
            txt: [:]
        )
        let secondConnId = try XCTUnwrap(browser.activeResolverId(for: key))
        let secondToken = try XCTUnwrap(browser.activeResolverToken(for: key))
        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertEqual(browser.activeResolverCount, 1)

        // Late .ready and .cancelled callbacks from the superseded connection must be ignored
        browser.applyResolverReady(
            key: key,
            connId: firstConnId,
            resolverToken: firstToken,
            serviceName: "StaleServer",
            remoteEndpoint: .hostPort(host: .name("stale-host.example.test", nil), port: 8090),
            txt: [:]
        )
        XCTAssertEqual(browser.activeResolverToken(for: key), secondToken)
        XCTAssertEqual(browser.activeResolverCount, 1)
        XCTAssertTrue(browser.servers.isEmpty)

        browser.applyResolverTerminated(key: key, connId: firstConnId, resolverToken: firstToken)
        XCTAssertEqual(browser.activeResolverToken(for: key), secondToken)
        XCTAssertEqual(browser.activeResolverCount, 1)

        // Active connection callback resolves and cleans up cleanly
        browser.applyResolverReady(
            key: key,
            connId: secondConnId,
            resolverToken: secondToken,
            serviceName: "ActiveServer",
            remoteEndpoint: .hostPort(host: .name("active-host.example.test", nil), port: 8090),
            txt: ["https_port": "8920"]
        )
        XCTAssertEqual(browser.activeResolverCount, 0)
        XCTAssertNil(browser.activeResolverId(for: key))
        XCTAssertEqual(browser.servers.count, 1)
        XCTAssertEqual(browser.servers.first?.baseURL.absoluteString, "https://active-host.example.test:8920")

        // Verify replacement resolver timeout also cleans up when not manually completed
        browser.beginResolve(
            key: key,
            endpoint: .hostPort(host: .name("timeout-1.example.test", nil), port: 8090),
            serviceName: "First",
            txt: [:]
        )
        browser.beginResolve(
            key: key,
            endpoint: .hostPort(host: .name("timeout-2.example.test", nil), port: 8090),
            serviceName: "Second",
            txt: [:]
        )
        XCTAssertEqual(browser.activeResolverCount, 1)
        try? await Task.sleep(nanoseconds: 140_000_000)
        XCTAssertEqual(browser.activeResolverCount, 0)
    }

    @MainActor
    func testStopStartBrowserReplacementIgnoresStaleCancelledAndBrowseCallbacks() async throws {
        let browser = BonjourServerBrowser()
        defer { browser.stop() }

        browser.start()
        let firstBrowserId = try XCTUnwrap(browser.activeBrowserId)
        let firstBrowserToken = try XCTUnwrap(browser.activeBrowserToken)
        XCTAssertTrue(browser.isSearching)

        browser.stop()
        XCTAssertNil(browser.activeBrowserId)
        XCTAssertNil(browser.activeBrowserToken)
        XCTAssertFalse(browser.isSearching)

        browser.start()
        let secondBrowserId = try XCTUnwrap(browser.activeBrowserId)
        let secondBrowserToken = try XCTUnwrap(browser.activeBrowserToken)
        XCTAssertNotEqual(firstBrowserToken, secondBrowserToken)
        XCTAssertTrue(browser.isSearching)

        // Late .cancelled/.failed state update from first browser must not clobber new browser's isSearching
        // (even if libmalloc reuses the same heap pointer for NWBrowser)
        browser.applyBrowserStateUpdate(.cancelled, browserId: firstBrowserId, browserToken: firstBrowserToken)
        XCTAssertTrue(browser.isSearching)
        XCTAssertEqual(browser.activeBrowserToken, secondBrowserToken)

        browser.applyBrowserStateUpdate(.failed(.posix(.ECANCELED)), browserId: firstBrowserId, browserToken: firstBrowserToken)
        XCTAssertTrue(browser.isSearching)

        // Populate a resolved server and verify stale browse results from first browser do not prune it
        let key = "svc._lunacore._tcp.local."
        browser.beginResolve(
            key: key,
            endpoint: .hostPort(host: .name("live.example.test", nil), port: 8090),
            serviceName: "Live",
            txt: [:]
        )
        let connId = try XCTUnwrap(browser.activeResolverId(for: key))
        let connToken = try XCTUnwrap(browser.activeResolverToken(for: key))
        browser.applyResolverReady(
            key: key,
            connId: connId,
            resolverToken: connToken,
            serviceName: "Live",
            remoteEndpoint: .hostPort(host: .name("live.example.test", nil), port: 8090),
            txt: [:]
        )
        XCTAssertEqual(browser.servers.count, 1)

        browser.applyBrowseResults([], browserId: firstBrowserId, browserToken: firstBrowserToken)
        XCTAssertEqual(browser.servers.count, 1)

        // Allow main queue to drain real NWBrowser cancellation from first browser
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(browser.isSearching)

        // Matching current browserId & token updates state cleanly
        browser.applyBrowserStateUpdate(.cancelled, browserId: secondBrowserId, browserToken: secondBrowserToken)
        XCTAssertFalse(browser.isSearching)
    }
}
