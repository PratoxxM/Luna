import AetherBridge
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class V250NavigationSettingsAndDeleteTests: XCTestCase {
    func testSettingsCategoriesOrderAndPreservedDisplayToggleStrings() {
        XCTAssertEqual(
            SettingsCategory.allCases.map(\.title),
            ["Rom & Skjerm", "Lyd & Synk", "Undertekster", "Avspilling", "System"]
        )
        XCTAssertEqual(
            SettingsView.keepDisplayModeToggleTitle,
            "Behold filmens skjerm- og HDR-modus i menyen etter avspilling"
        )
        XCTAssertTrue(SettingsView.keepDisplayModeExplanationText.contains("24p-film"))
    }

    func testDecodeTvDeletePreflightWithPhysicalBytesAndBlockers() throws {
        let preflightJson = #"""
        {
          "checkedAt": "2026-11-18T00:10:00Z",
          "preflightId": "pf_abc123456789",
          "expiresAt": "2026-11-18T00:15:00Z",
          "target": {
            "kind": "series",
            "scope": "season",
            "season": 2,
            "episode": null,
            "title": "Severance",
            "year": 2022,
            "monitored": true,
            "canRemoveFromLibrary": false
          },
          "files": {
            "count": 10,
            "logicalBytes": 53687091200,
            "physicalBytes": 53687091200,
            "ssdBytes": 53687091200,
            "archiveBytes": 0,
            "vfsCount": 0
          },
          "blockers": [],
          "warnings": []
        }
        """#

        let decoded = try JSONDecoder().decode(TvDeletePreflightResponse.self, from: Data(preflightJson.utf8))
        XCTAssertEqual(decoded.preflightId, "pf_abc123456789")
        XCTAssertEqual(decoded.target.kind, "series")
        XCTAssertEqual(decoded.target.scope, "season")
        XCTAssertEqual(decoded.target.season, 2)
        XCTAssertEqual(decoded.files.count, 10)
        XCTAssertEqual(decoded.files.freedDisplayBytes, 53_687_091_200)
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: decoded.files.freedDisplayBytes), "50,00 GB")
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: 42 * 1_048_576), "42 MB")
        XCTAssertEqual(TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: 0), "0 GB")
        XCTAssertTrue(decoded.blockers.isEmpty)

        let blockerJson = #"""
        {
          "preflightId": null,
          "target": {
            "kind": "movie",
            "scope": "title",
            "title": "Fight Club"
          },
          "files": {
            "count": 1,
            "logicalBytes": 10737418240,
            "physicalBytes": 10737418240
          },
          "blockers": [
            {
              "code": "active_playback",
              "message": "Kan ikke slette mens avspilling pågår i Stua",
              "sessionId": "sess-9",
              "roomName": "Stua"
            }
          ]
        }
        """#
        let blocked = try JSONDecoder().decode(TvDeletePreflightResponse.self, from: Data(blockerJson.utf8))
        XCTAssertNil(blocked.preflightId)
        XCTAssertEqual(blocked.blockers.count, 1)
        XCTAssertEqual(blocked.blockers[0].code, "active_playback")
        XCTAssertEqual(blocked.blockers[0].roomName, "Stua")
    }

    func testDeleteTargetScopeHeadingsAndLibraryListsDecoding() throws {
        let movieTarget = TvDeleteRequestTarget(
            kind: "movie",
            itemId: "movie:tmdb:550",
            tmdbId: 550,
            title: "Fight Club",
            scope: .title
        )
        let episodeTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: "episode:tmdb:1399:s1:e2",
            tmdbId: 1399,
            title: "Game of Thrones",
            scope: .episode,
            season: 1,
            episode: 2
        )
        let seasonTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: "series:tmdb:1399",
            tmdbId: 1399,
            title: "Game of Thrones",
            scope: .season,
            season: 3
        )
        let seriesTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: "series:tmdb:1399",
            tmdbId: 1399,
            title: "Game of Thrones",
            scope: .series
        )

        XCTAssertTrue(movieTarget.isWholeTitle)
        XCTAssertEqual(movieTarget.dialogHeading, "Slett filmen")
        XCTAssertFalse(episodeTarget.isWholeTitle)
        XCTAssertEqual(episodeTarget.dialogHeading, "Slett episode")
        XCTAssertFalse(seasonTarget.isWholeTitle)
        XCTAssertEqual(seasonTarget.dialogHeading, "Slett sesong 3")
        XCTAssertTrue(seriesTarget.isWholeTitle)
        XCTAssertEqual(seriesTarget.dialogHeading, "Slett hele serien")

        let libListsJson = #"""
        {
          "ok": true,
          "section": "lists",
          "counts": {
            "favorites": 0,
            "watchlist": 2,
            "localTotal": 5,
            "nvme": 3,
            "archive": 2,
            "vfs": 0,
            "customLists": 2
          },
          "favorites": [],
          "watchlist": [],
          "localItems": [],
          "customLists": [
            {
              "id": "nordic-noir",
              "name": "Nordic Noir",
              "mediaType": "series",
              "listMode": "curated",
              "rowStyle": "poster",
              "itemCount": 6,
              "browsePath": "/api/tv/v1/rows/custom:nordic-noir"
            }
          ]
        }
        """#
        let lib = try JSONDecoder().decode(TvLibraryResponse.self, from: Data(libListsJson.utf8))
        XCTAssertEqual(lib.section, "lists")
        XCTAssertEqual(lib.counts.customLists, 2)
        XCTAssertEqual(lib.customLists?.first?.name, "Nordic Noir")
        XCTAssertEqual(lib.customLists?.first?.itemCount, 6)
        XCTAssertEqual(lib.customLists?.first?.sourceType, nil)
    }

    func testCustomListSourceTypeAndOngoingContextPolicy() throws {
        let listsJson = """
        {
          "ok": true,
          "section": "lists",
          "counts": {
            "favorites": 0,
            "watchlist": 0,
            "localTotal": 0,
            "nvme": 0,
            "archive": 0,
            "vfs": 0,
            "customLists": 1
          },
          "favorites": [],
          "watchlist": [],
          "localItems": [],
          "customLists": [
            {
              "id": "mine-pagaende-serier",
              "name": "Mine pågående serier",
              "mediaType": "series",
              "sourceType": "active_series",
              "listMode": "curated",
              "rowStyle": "poster",
              "itemCount": 3,
              "browsePath": "/api/tv/v1/rows/custom:mine-pagaende-serier"
            }
          ]
        }
        """
        let lib = try JSONDecoder().decode(TvLibraryResponse.self, from: Data(listsJson.utf8))
        XCTAssertEqual(lib.customLists?.first?.sourceType, "active_series")

        let rowJson = """
        {
          "ok": true,
          "rowId": "custom:mine-pagaende-serier",
          "sourceKind": "active_series",
          "title": "Mine pågående serier",
          "offset": 0,
          "limit": 36,
          "totalEstimate": 3,
          "hasMore": false,
          "nextPath": null,
          "items": []
        }
        """
        let rowPage = try JSONDecoder().decode(TvRowPageResponse.self, from: Data(rowJson.utf8))
        XCTAssertEqual(rowPage.sourceKind, "active_series")

        XCTAssertTrue(CustomRowContextPolicy.isOngoingList(
            explicitFlag: false,
            rowId: "custom:mine-pagaende-serier",
            sourceKind: "active_series"
        ))
        XCTAssertEqual(
            CustomRowContextPolicy.removeActionTitle(
                explicitFlag: false,
                rowId: "custom:mine-pagaende-serier",
                sourceKind: "active_series"
            ),
            "Fjern fra pågående"
        )
        XCTAssertNil(
            CustomRowContextPolicy.removeActionTitle(
                explicitFlag: false,
                rowId: "genre:movie:action",
                sourceKind: "genre"
            )
        )
        XCTAssertNil(
            CustomRowContextPolicy.removeActionTitle(
                explicitFlag: false,
                rowId: "local-movies",
                sourceKind: "local_library"
            )
        )
        XCTAssertEqual(
            CustomRowContextPolicy.removeActionTitle(
                explicitFlag: false,
                rowId: "custom:nordic-noir",
                sourceKind: "custom"
            ),
            "Fjern fra listen"
        )
    }

    @MainActor
    func testDetailDeleteSheetAndSettingsViewsConstructCleanly() {
        let target = TvDeleteRequestTarget(
            kind: "movie",
            itemId: "movie:tmdb:550",
            tmdbId: 550,
            title: "Fight Club",
            scope: .title
        )
        let deleteSheet = DetailDeleteSheetView(
            target: target,
            onDeleted: { _ in },
            onCancel: {}
        )
        let settingsView = SettingsView()
        let topBar = LunaTopBarView(selectedTab: .constant(.home))
        let pushedSearchView = SearchView(initialQuery: "dune", isRootTab: false)
        let pushedCatalogView = CatalogBrowseView(mediaType: "movie", initialGenre: nil, isRootTab: false)
        let customRowView = CustomRowBrowseView(title: "Nordic Noir", pathOrRowId: "/api/tv/v1/rows/custom:nordic-noir")
        let detailView = MediaDetailView(mediaType: "movie", itemId: "movie:tmdb:550", initialTitle: "Fight Club")

        XCTAssertEqual(deleteSheet.target.tmdbId, 550)
        XCTAssertEqual(SettingsView.keepDisplayModeToggleTitle.isEmpty, false)
        XCTAssertFalse(pushedSearchView.isRootTab)
        XCTAssertFalse(pushedCatalogView.isRootTab)
        XCTAssertEqual(customRowView.title, "Nordic Noir")
        XCTAssertEqual(detailView.itemId, "movie:tmdb:550")
        _ = settingsView
        _ = topBar
    }

    @MainActor
    func testNavigationContainerBackdropsApplyCanvasColorAcrossUIKitStackAndWindow() async throws {
        let suite = "luna.test.navbackdrop.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let probeView = NonFocusableBackdropProbeView(frame: .zero)
        XCTAssertFalse(probeView.canBecomeFocused)

        let store = AppSessionStore(defaults: defaults)
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = windowScene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // 1. Verify UINavigationController root + pushed views (including simulated tvOS overscan safe areas)
        let rootView = HomeView()
            .environmentObject(store)
            .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: false))
        let rootHost = UIHostingController(rootView: rootView)
        rootHost.additionalSafeAreaInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)

        let nav = UINavigationController(rootViewController: rootHost)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)

        try assertCanvasUIColor(window.backgroundColor)
        try assertCanvasUIColor(nav.view.backgroundColor)
        try assertCanvasUIColor(rootHost.view.backgroundColor)

        let pushedViews: [AnyView] = [
            AnyView(MediaDetailView(mediaType: "movie", itemId: "movie:tmdb:550", initialTitle: "Fight Club").environmentObject(store)),
            AnyView(CustomRowBrowseView(title: "Nordic Noir", pathOrRowId: "/api/tv/v1/rows/custom:nordic-noir").environmentObject(store)),
            AnyView(CatalogBrowseView(mediaType: "movie", initialGenre: nil, isRootTab: false).environmentObject(store)),
            AnyView(SearchView(initialQuery: "dune", isRootTab: false).environmentObject(store)),
        ]

        for pushed in pushedViews {
            let pushedHost = UIHostingController(rootView: pushed)
            pushedHost.additionalSafeAreaInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)
            nav.pushViewController(pushedHost, animated: false)
            window.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 120_000_000)

            try assertCanvasUIColor(nav.view.backgroundColor)
            try assertCanvasUIColor(pushedHost.view.backgroundColor)
            for subview in nav.view.subviews {
                let className = NSStringFromClass(type(of: subview))
                if className.contains("TransitionView") || className.contains("WrapperView") {
                    try assertCanvasUIColor(subview.backgroundColor)
                }
            }
            nav.popViewController(animated: false)
            window.layoutIfNeeded()
        }

        // 2. Verify live MainNavigationShell mounts BackdropInstallerViewController inside TabView/NavigationStack
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let shellHost = UIHostingController(
            rootView: MainNavigationShell(engine: engine)
                .environmentObject(store)
        )
        shellHost.additionalSafeAreaInsets = UIEdgeInsets(top: 60, left: 80, bottom: 60, right: 80)
        window.rootViewController = shellHost
        window.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)

        let installers = collectDescendants(of: shellHost).compactMap { $0 as? BackdropInstallerViewController }
        XCTAssertFalse(installers.isEmpty, "MainNavigationShell must mount BackdropInstallerViewController inside NavigationStack")
        var checkedAncestors = 0
        for installer in installers {
            var cursor = installer.parent
            while let ancestor = cursor {
                if let bg = ancestor.viewIfLoaded?.backgroundColor {
                    try assertCanvasUIColor(bg)
                    checkedAncestors += 1
                }
                cursor = ancestor.parent
            }
            if let navController = installer.navigationController {
                try assertCanvasUIColor(navController.view.backgroundColor)
                checkedAncestors += 1
            }
            if let tabController = installer.tabBarController {
                try assertCanvasUIColor(tabController.view.backgroundColor)
                checkedAncestors += 1
            }
        }
        XCTAssertGreaterThan(checkedAncestors, 0)
        try assertCanvasUIColor(window.backgroundColor)
    }

    @MainActor
    private func collectDescendants(of controller: UIViewController) -> [UIViewController] {
        var result: [UIViewController] = []
        for child in controller.children {
            result.append(child)
            result.append(contentsOf: collectDescendants(of: child))
        }
        return result
    }

    private func assertCanvasUIColor(
        _ color: UIColor?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let resolved = try XCTUnwrap(color, file: file, line: line)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a), file: file, line: line)
        XCTAssertEqual(Double(r), 10.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(g), 9.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(b), 8.0 / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Double(a), 1.0, accuracy: 0.01, file: file, line: line)
    }
}
