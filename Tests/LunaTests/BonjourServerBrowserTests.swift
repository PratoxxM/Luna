import Foundation
import XCTest
@testable import Luna

final class BonjourServerBrowserTests: XCTestCase {
    @MainActor
    func testBrowserStartStopAndDiscoveredServiceBridge() {
        let parsed = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore._lunacore._tcp.local.",
            serviceName: "LunaCore",
            rawHost: "lunacore.example.test",
            port: 8090,
            txt: ["https_port": "8920", "api": "/api/tv/v2"]
        )
        XCTAssertEqual(parsed?.baseURL.absoluteString, "https://lunacore.example.test:8920")
        XCTAssertEqual(parsed?.apiPath, "/api/tv/v2")
        XCTAssertNil(
            BonjourServerBrowser.parseDiscoveredService(
                id: "link-local-v6",
                serviceName: "LunaCore",
                rawHost: "[fe80::1%en0]",
                port: 8090,
                txt: [:]
            )
        )

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

        browser.applyResolverReady(
            key: key,
            connId: firstConnId,
            resolverToken: firstToken,
            serviceName: "StaleServer",
            remoteEndpoint: .hostPort(host: .name("stale-host.example.test", nil), port: 8090),
            txt: [:]
        )
        XCTAssertEqual(browser.activeResolverToken(for: key), secondToken)
        XCTAssertTrue(browser.servers.isEmpty)

        browser.applyResolverTerminated(key: key, connId: firstConnId, resolverToken: firstToken)
        XCTAssertEqual(browser.activeResolverToken(for: key), secondToken)
        XCTAssertEqual(browser.activeResolverCount, 1)

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

        browser.applyBrowserStateUpdate(.cancelled, browserId: firstBrowserId, browserToken: firstBrowserToken)
        XCTAssertTrue(browser.isSearching)
        XCTAssertEqual(browser.activeBrowserToken, secondBrowserToken)

        browser.applyBrowserStateUpdate(.failed(.posix(.ECANCELED)), browserId: firstBrowserId, browserToken: firstBrowserToken)
        XCTAssertTrue(browser.isSearching)

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

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(browser.isSearching)

        browser.applyBrowserStateUpdate(.cancelled, browserId: secondBrowserId, browserToken: secondBrowserToken)
        XCTAssertFalse(browser.isSearching)
    }
}
