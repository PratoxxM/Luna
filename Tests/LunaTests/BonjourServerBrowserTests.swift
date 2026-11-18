import Foundation
import XCTest
@testable import Luna

final class BonjourServerBrowserTests: XCTestCase {
    func testParseDiscoveredServiceHandlesIPv4IPv6TLSOverrideAndTxtApiPath() {
        let httpServer = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore._lunacore._tcp.local.",
            serviceName: "LunaCore",
            rawHost: "lunacore.local",
            port: 8090,
            txt: [:]
        )
        XCTAssertEqual(httpServer?.baseURL.absoluteString, "http://lunacore.local:8090")
        XCTAssertEqual(httpServer?.apiPath, "/api/tv/v1")
        XCTAssertEqual(httpServer?.displayAddress, "http://lunacore.local:8090")

        let tlsServer = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore._lunacore._tcp.local.",
            serviceName: "LunaCore",
            rawHost: "lunacore.example.test",
            port: 8090,
            txt: ["https_port": "8920", "api": "/api/tv/v1"]
        )
        XCTAssertEqual(tlsServer?.baseURL.absoluteString, "https://lunacore.example.test:8920")
        XCTAssertEqual(tlsServer?.apiPath, "/api/tv/v1")

        let tlsPortAlias = BonjourServerBrowser.parseDiscoveredService(
            id: "LunaCore-2._lunacore._tcp.local.",
            serviceName: "LunaCore-2",
            rawHost: "[fd00::1]",
            port: 8090,
            txt: ["tls_port": " 8920 ", "api": "  "]
        )
        XCTAssertEqual(tlsPortAlias?.baseURL.absoluteString, "https://[fd00::1]:8920")
        XCTAssertEqual(tlsPortAlias?.apiPath, "/api/tv/v1")

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
}
