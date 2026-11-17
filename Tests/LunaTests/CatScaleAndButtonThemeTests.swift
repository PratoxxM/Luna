import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class CatScaleAndButtonThemeTests: XCTestCase {
    func testWarmEspressoAndHoneyBrassPaletteHexAndContrast() throws {
        // 1. Exact LunaCore Warm Espresso & Honey-Brass hex values
        try assertRGB(LunaTheme.canvas, r: 10, g: 9, b: 8)            // #0A0908 OLED warm charcoal
        try assertRGB(LunaTheme.surface, r: 20, g: 17, b: 15)         // #14110F matte espresso
        try assertRGB(LunaTheme.surfaceRaised, r: 30, g: 25, b: 22)   // #1E1916 elevated matte espresso
        try assertRGB(LunaTheme.linen, r: 245, g: 240, b: 232)        // #F5F0E8 warm linen primary text
        try assertRGB(LunaTheme.moonlight, r: 200, g: 191, b: 182)    // #C8BFB6 warm parchment secondary text
        try assertRGB(LunaTheme.muted, r: 160, g: 150, b: 140)        // #A0968C daylight-calibrated Frame Pro taupe
        try assertRGB(LunaTheme.amber, r: 229, g: 169, b: 60)         // #E5A93C muted honey-brass
        try assertRGB(LunaTheme.warmBorderBase, r: 255, g: 244, b: 230) // #FFF4E6 warm border base

        // Verify cinemaGlass is #120F0D @ 92% alpha
        let glass = try rgbaComponents(LunaTheme.cinemaGlass)
        XCTAssertEqual(glass.r, 18.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(glass.g, 15.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(glass.b, 13.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(glass.a, 0.92, accuracy: 0.01)

        // Verify 1 pt warm border opacities sit strictly inside 10–18%
        XCTAssertEqual(try rgbaComponents(LunaTheme.warmBorderSubtle).a, 0.10, accuracy: 0.01)
        XCTAssertEqual(try rgbaComponents(LunaTheme.warmBorder).a, 0.14, accuracy: 0.01)
        XCTAssertEqual(try rgbaComponents(LunaTheme.warmBorderStrong).a, 0.18, accuracy: 0.01)

        // Zero cold blue dominance across surfaces & text (R >= G >= B warmth invariant)
        for warmToken in [
            LunaTheme.canvas,
            LunaTheme.surface,
            LunaTheme.surfaceRaised,
            LunaTheme.surfaceSelected,
            LunaTheme.linen,
            LunaTheme.moonlight,
            LunaTheme.muted,
            LunaTheme.pauseWarmLine,
            LunaTheme.amber,
        ] {
            let c = try rgbaComponents(warmToken)
            XCTAssertGreaterThanOrEqual(c.r + 0.002, c.g)
            XCTAssertGreaterThanOrEqual(c.g + 0.002, c.b)
        }

        // WCAG contrast checks for both dark OLED rooms and bright Frame Pro daylight rooms
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.linen, background: LunaTheme.canvas), 15.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.moonlight, background: LunaTheme.surfaceRaised), 8.5)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.muted, background: LunaTheme.canvas), 6.2)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.muted, background: LunaTheme.surface), 5.8)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.amber), 8.5)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.focusGoldTop), 9.5)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.focusGoldBottom), 8.0)
    }

    func testInAppCatAssetsRemovedWhileAccentColorAndHomeScreenBrandAssetsRemainIntact() throws {
        // Cropped in-app cat imagesets must no longer exist in Assets.car
        XCTAssertNil(UIImage(named: "MascotCatsDuo"))
        XCTAssertNil(UIImage(named: "LunaMoonCrescent"))
        XCTAssertNil(UIImage(named: "LunaMoonCatsEmblem"))

        // Global AccentColor.colorset must resolve to warm honey-brass (#E5A93C)
        let accentUI = try XCTUnwrap(UIColor(named: "AccentColor"))
        let resolved = accentUI.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(Double(r), 0.898, accuracy: 0.015)
        XCTAssertEqual(Double(g), 0.663, accuracy: 0.015)
        XCTAssertEqual(Double(b), 0.235, accuracy: 0.015)
        XCTAssertEqual(Double(a), 1.0, accuracy: 0.01)
    }

    func testCachedArtworkKeyMatchedResolverPreventsOneFrameStaleImageReuseAndReusesAnySize() throws {
        let staleImg = try makeSolidTestCGImage(width: 8, height: 12, byte: 40)
        let freshMemImg = try makeSolidTestCGImage(width: 16, height: 9, byte: 200)

        // Matching key returns existing @State image immediately
        let kept = CachedArtworkView.selectKeyMatchedImage(
            expectedKey: "movie-A#px750",
            stateKey: "movie-A#px750",
            stateImage: staleImg,
            memoryFallback: { nil }
        )
        XCTAssertTrue(kept === staleImg)

        // Recycled cell with new URL MUST discard stale @State image on Frame 0 (returning nil if uncached)
        let discarded = CachedArtworkView.selectKeyMatchedImage(
            expectedKey: "movie-B#px750",
            stateKey: "movie-A#px750",
            stateImage: staleImg,
            memoryFallback: { nil }
        )
        XCTAssertNil(discarded)

        // Recycled cell with new URL that hits RAM cache returns new image on Frame 0
        let instantSwap = CachedArtworkView.selectKeyMatchedImage(
            expectedKey: "movie-B#px750",
            stateKey: "movie-A#px750",
            stateImage: staleImg,
            memoryFallback: { freshMemImg }
        )
        XCTAssertTrue(instantSwap === freshMemImg)

        // Nil URL always resolves to nil
        XCTAssertNil(
            CachedArtworkView.selectKeyMatchedImage(
                expectedKey: nil,
                stateKey: "movie-A#px750",
                stateImage: staleImg,
                memoryFallback: { freshMemImg }
            )
        )

        // ResolvingCurtainView cross-bucket backdrop reuse in ArtworkPipeline
        let backdropURL = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v1/artwork/backdrop-99"))
        ArtworkPipeline.shared.insertMemoryCachedImageForTesting(freshMemImg, url: backdropURL, maxPixelSize: 1920)
        let reusedHit = ArtworkPipeline.shared.anyMemoryCachedImage(for: backdropURL, preferredMaxPixelSize: 960)
        XCTAssertTrue(reusedHit?.image === freshMemImg)
    }

    @MainActor
    func testScrubPreviewBubbleCrescentMarkAndMattePillButtonVariantsConstructCleanly() throws {
        let bubble = ScrubPreviewBubbleView(
            targetSeconds: 120,
            originSeconds: 90,
            chapterTitle: "Kapittel 1",
            previewImage: nil,
            drawsInCompositorView: false,
            onMountCompositorView: { _ in }
        )
        XCTAssertFalse(bubble.hasVisualFrame)
        XCTAssertEqual(bubble.preferredWidth, ScrubPreviewBubbleView.compactWidth)
        XCTAssertGreaterThanOrEqual(ScrubPreviewBubbleView.compactWidth, 212)

        let crescent = LunaCrescentMarkView(size: 28, color: LunaTheme.amber)
        XCTAssertEqual(crescent.size, 28)

        let compactWatchlist = LunaPillButton(
            "Huskeliste",
            systemImage: "bookmark.fill",
            isSelected: true,
            prominence: .glassPill,
            size: .compact
        ) {}
        XCTAssertEqual(compactWatchlist.accent, .amber)
        XCTAssertEqual(compactWatchlist.size, .compact)

        // Resting selected secondary buttons MUST stay warm linen/cream (zero resting brass leak)
        let selectedSecondaryIcon = LunaPillButton.resolveIconForeground(
            isFocused: false,
            isSelected: true,
            prominence: .glassPill,
            accent: .amber
        )
        let selectedSecondaryBorder = LunaPillButton.resolveBorderColor(
            isFocused: false,
            isSelected: true,
            prominence: .glassPill,
            accent: .amber
        )
        try assertRGB(selectedSecondaryIcon, r: 245, g: 240, b: 232) // #F5F0E8 linen, NOT brass
        XCTAssertEqual(try rgbaComponents(selectedSecondaryBorder).a, 0.18, accuracy: 0.015)

        let watchedButton = LunaPillButton(
            "Sett",
            systemImage: "checkmark.circle.fill",
            isSelected: true,
            prominence: .glassPill,
            accent: .emerald,
            size: .compact
        ) {}
        XCTAssertEqual(watchedButton.accent, .emerald)

        // Sett checkmark uses calm emerald (#5EBF8E) without a clashing brass border
        let watchedIcon = LunaPillButton.resolveIconForeground(
            isFocused: false,
            isSelected: true,
            prominence: .glassPill,
            accent: .emerald
        )
        let watchedBorder = LunaPillButton.resolveBorderColor(
            isFocused: false,
            isSelected: true,
            prominence: .glassPill,
            accent: .emerald
        )
        try assertRGB(watchedIcon, r: 94, g: 191, b: 142)
        let wb = try rgbaComponents(watchedBorder)
        XCTAssertGreaterThan(wb.g, wb.r, "Sett selected border must tint emerald, not brass")

        let destructiveAction = LunaPillButton(
            "Nullstill tilkobling",
            systemImage: "xmark.circle",
            prominence: .subtleChip,
            accent: .coral
        ) {}
        XCTAssertEqual(destructiveAction.accent, .coral)
        let coralLabel = LunaPillButton.resolveLabelForeground(
            isFocused: false,
            isSelected: false,
            prominence: .subtleChip,
            accent: .coral
        )
        try assertRGB(coralLabel, r: 217, g: 107, b: 82)

        // Card title & subtitle resolvers must stay warm linen (#F5F0E8) in both resting and focused states (never #FFFFFF)
        try assertRGB(LunaTheme.cardTitleColor(isFocused: false), r: 245, g: 240, b: 232)
        try assertRGB(LunaTheme.cardTitleColor(isFocused: true), r: 245, g: 240, b: 232)
        try assertRGB(LunaTheme.cardSubtitleColor(isFocused: false), r: 160, g: 150, b: 140)
        try assertRGB(LunaTheme.cardSubtitleColor(isFocused: true), r: 229, g: 169, b: 60)

        // Centered top-dock tab pills keep calm warm espresso resting tokens & dark ink on brass focus
        try assertRGB(TopBarTabPillButton.resolveIconColor(isActive: false, isFocused: false), r: 160, g: 150, b: 140)
        try assertRGB(TopBarTabPillButton.resolveTextColor(isActive: false, isFocused: false), r: 200, g: 191, b: 182)
        try assertRGB(TopBarTabPillButton.resolveIconColor(isActive: true, isFocused: false), r: 245, g: 240, b: 232)
        try assertRGB(TopBarTabPillButton.resolveTextColor(isActive: true, isFocused: false), r: 245, g: 240, b: 232)
        try assertRGB(TopBarTabPillButton.resolveIconColor(isActive: true, isFocused: true), r: 10, g: 9, b: 8)
        try assertRGB(TopBarTabPillButton.resolveTextColor(isActive: true, isFocused: true), r: 10, g: 9, b: 8)

        // Card views construct cleanly with warm linen titles
        let sampleCard = TvMediaCard(
            itemId: "movie:tmdb:550",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 550),
            title: "Fight Club",
            year: 1999
        )
        let posterCard = PosterCardView(card: sampleCard, client: nil, onSelect: {})
        let backdropCard = BackdropCardView(card: sampleCard, client: nil, variant: .standard, onPrimaryAction: {})
        let sampleEpisode = TvEpisodeCard(
            itemId: "episode:tmdb:95396:s1:e1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Good News About Hell",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 3420,
            watched: false,
            availability: nil,
            progress: nil
        )
        let episodeCard = EpisodeCardView(
            episode: sampleEpisode,
            seriesTitle: "Severance",
            client: nil,
            onPlay: {},
            onPickSource: {},
            onToggleWatched: {}
        )
        let castStrip = DetailCastStripView(
            members: [TvCastMember(name: "Adam Scott", character: "Mark Scout", profileUrl: nil)],
            castNames: nil,
            client: nil,
            onSelectActor: { _ in }
        )
        XCTAssertEqual(posterCard.card.title, "Fight Club")
        XCTAssertEqual(backdropCard.card.title, "Fight Club")
        XCTAssertEqual(episodeCard.episode.episodeNumber, 1)
        XCTAssertEqual(castStrip.members?.count, 1)
    }

    private func makeSolidTestCGImage(width: Int, height: Int, byte: UInt8) throws -> CGImage {
        let pixels = [UInt8](repeating: byte, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw NSError(domain: "ImageAlloc", code: 1)
        }
        return cg
    }

    private func assertRGB(_ color: Color, r: Double, g: Double, b: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try rgbaComponents(color)
        XCTAssertEqual(c.r, r / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.g, g / 255.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.b, b / 255.0, accuracy: 0.01, file: file, line: line)
    }

    private func rgbaComponents(_ color: Color) throws -> (r: Double, g: Double, b: Double, a: Double) {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            throw NSError(domain: "ColorTest", code: 1)
        }
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func relativeLuminance(_ color: Color) throws -> Double {
        let (r, g, b, _) = try rgbaComponents(color)
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(foreground: Color, background: Color) throws -> Double {
        let l1 = try relativeLuminance(foreground)
        let l2 = try relativeLuminance(background)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
