import AetherBridge
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import XCTest
@testable import Luna

final class PreviewRenderingAndLaunchTests: XCTestCase {
    func testAetherBridgePinnedVersionMatchesUpgrade() {
        XCTAssertEqual(AetherBridgeInfo.pinnedAetherEngineVersion, "7.76.0")
    }

    func testPreviewMockArtworkRendererGeneratesExpectedPNGDimensionsAndScrubPreview() throws {
        let heroData = PreviewMockArtworkRenderer.artworkPNG(named: "/preview-art/sand-backdrop.png")
        XCTAssertGreaterThan(heroData.count, 100)
        XCTAssertEqual(Array(heroData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let heroRepeat = PreviewMockArtworkRenderer.artworkPNG(named: "/preview-art/sand-backdrop.png")
        XCTAssertEqual(heroData, heroRepeat)

        let heroSrc = try XCTUnwrap(CGImageSourceCreateWithData(heroData as CFData, nil))
        let heroImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(heroSrc, 0, nil))
        XCTAssertEqual(heroImg.width, 1920)
        XCTAssertEqual(heroImg.height, 1080)

        let backdropData = PreviewMockArtworkRenderer.artworkPNG(named: "/preview-art/teal-backdrop.png")
        let backdropSrc = try XCTUnwrap(CGImageSourceCreateWithData(backdropData as CFData, nil))
        let backdropImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(backdropSrc, 0, nil))
        XCTAssertEqual(backdropImg.width, 1280)
        XCTAssertEqual(backdropImg.height, 720)

        let posterData = PreviewMockArtworkRenderer.artworkPNG(named: "/preview-art/ochre-poster.png")
        let posterSrc = try XCTUnwrap(CGImageSourceCreateWithData(posterData as CFData, nil))
        let posterImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(posterSrc, 0, nil))
        XCTAssertEqual(posterImg.width, 640)
        XCTAssertEqual(posterImg.height, 960)

        let cinemaData = PreviewMockArtworkRenderer.artworkPNG(named: "/preview-art/cinema-stage-backdrop.png")
        let cinemaSrc = try XCTUnwrap(CGImageSourceCreateWithData(cinemaData as CFData, nil))
        let cinemaImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(cinemaSrc, 0, nil))
        XCTAssertEqual(cinemaImg.width, 1920)
        XCTAssertEqual(cinemaImg.height, 1080)

        let scrubCG = try XCTUnwrap(PreviewMockURLProtocol.makeScrubPreviewImage(width: 640, height: 360))
        XCTAssertEqual(scrubCG.width, 640)
        XCTAssertEqual(scrubCG.height, 360)
    }

    func testPreviewMockURLProtocolHandlesExpandedOfflineRoutesAndRichP32Fixtures() async throws {
        let client = PreviewMockFixtures.makeClient()

        let rowPage = try await client.fetchRow(pathOrRowId: "/api/tv/v2/rows/custom%3Anordic-noir", offset: 0, limit: 36)
        XCTAssertTrue(rowPage.ok)
        XCTAssertFalse(rowPage.items.isEmpty)

        let preflight = try await client.deletePreflight(
            target: TvDeleteRequestTarget(
                kind: "movie",
                itemId: "movie:tmdb:693134",
                tmdbId: 693134,
                title: "Dune: Part Two",
                scope: .title
            )
        )
        XCTAssertEqual(preflight.preflightId, "preview-pf-1")
        XCTAssertEqual(preflight.files.count, 1)

        let pairReq = try await client.requestPairingCode(
            model: "AppleTV14,1",
            osVersion: "tvOS 26.0",
            appVersion: "3.0.0",
            capabilities: DeviceHardwareCapabilities.asTvCapabilities
        )
        XCTAssertEqual(pairReq.displayCode, "482 917")

        let (pollStatus, pollRes) = try await client.pollPairingCode(pairReq.pairingCode)
        XCTAssertEqual(pollStatus, 200)
        XCTAssertEqual(pollRes.status, "pending")

        let season0 = try await client.fetchSeasonEpisodes(tmdbId: 246810, seasonNumber: 0)
        XCTAssertEqual(season0.seasonNumber, 0)
        XCTAssertEqual(season0.title, "Spesialer")
        XCTAssertFalse(season0.episodes.isEmpty)

        let movieDetail = try await client.fetchItemDetail(mediaType: "movie", itemId: "movie:tmdb:693134")
        XCTAssertFalse(movieDetail.castMembers?.isEmpty ?? true)
        XCTAssertEqual(movieDetail.rottenTomatoesScore, 92)
        XCTAssertEqual(movieDetail.metacriticScore, 79)
    }

    @MainActor
    func testExpandedPreviewTargetsConfigureSessionAndLaunchViewsCleanly() throws {
        let nerdStore = AppSessionStore(previewConfiguration: PreviewLaunchConfiguration(screen: .playerNerdHud))
        XCTAssertTrue(nerdStore.comfort.showNerdHUD)

        let curtainReq = PreviewMockFixtures.playerLaunchRequest(for: .playerCurtain)
        XCTAssertNil(curtainReq.prepareToken)

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        for target in [
            PreviewScreenTarget.customRow,
            .settingsSubtitles,
            .settingsPlayback,
            .settingsAudio,
            .settingsDiagnostics,
            .detailSeasons,
            .detailMore,
            .detailOverview,
            .detailDelete,
            .playerCurtain,
            .playerNerdHud,
        ] {
            let shell = MainNavigationShell(
                engine: engine,
                previewConfiguration: PreviewLaunchConfiguration(screen: target)
            )
            XCTAssertEqual(shell.previewConfiguration?.screen, target)
        }

        let onboarding = PairingOnboardingView(isPreviewMode: true)
        _ = onboarding
    }
}
