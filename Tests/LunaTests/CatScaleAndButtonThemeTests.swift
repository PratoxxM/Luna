import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class CatScaleAndButtonThemeTests: XCTestCase {
    func testCatCompanionTenFootLayoutScalesAndClampedStartupTrack() {
        XCTAssertEqual(CatCompanionLayout.loadingTrackWidth, 640)
        XCTAssertEqual(CatCompanionLayout.loadingTrackHeight, 7)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingContainerHeight, 84)
        XCTAssertEqual(CatCompanionLayout.loadingBlackCatSize, CGSize(width: 96, height: 67))
        XCTAssertEqual(CatCompanionLayout.loadingTabbyCatSize, CGSize(width: 92, height: 64))
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingBlackOffset, 54)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingTabbySpacing, 88)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.pauseCatSize.width, 190)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.pauseCatSize.height, 190)
        XCTAssertEqual(CatCompanionLayout.pauseCatSize, CGSize(width: 204, height: 194))
        XCTAssertEqual(CatCompanionLayout.prowlingCatSize, CGSize(width: 122, height: 85))
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.moonSceneSize.width, 225)
        XCTAssertEqual(CatCompanionLayout.moonSceneSize, CGSize(width: 232, height: 232))
        XCTAssertEqual(CatCompanionLayout.moonCatSize, CGSize(width: 152, height: 144))
        XCTAssertEqual(CatCompanionLayout.playheadDiameter, 24)
        XCTAssertEqual(CatCompanionLayout.playheadEarsSize, CGSize(width: 28, height: 14))

        // Verify playhead ear outer base fits inside the 24pt circle chord at y=-7 overlap
        let r = CatCompanionLayout.playheadDiameter * 0.5
        let overlapY: CGFloat = 7.0
        let circleChordHalf = sqrt(r * r - (r - overlapY) * (r - overlapY))
        let earHalfWidth = CatCompanionLayout.playheadEarsSize.width * 0.5 - 2.4 * (CatCompanionLayout.playheadEarsSize.width / 18.0)
        XCTAssertLessThan(earHalfWidth, circleChordHalf)

        let initial = LoadingSprintInterpolator.makeInitial(targetFraction: 0.04, now: 50.0)
        XCTAssertGreaterThanOrEqual(initial.anchorFraction, 0.12)
        XCTAssertGreaterThanOrEqual(initial.goalFraction, 0.14)
        XCTAssertGreaterThanOrEqual(initial.duration, 0.32)
        XCTAssertGreaterThanOrEqual(initial.fraction(at: 50.0), 0.12)

        // Startup positions at low fractions MUST NOT clip off the left edge of the 640pt track
        for frac in [0.0, 0.08, 0.12, 0.16, 0.50, 0.99] {
            let pos = LoadingTrackPositions.compute(fraction: frac)
            let tabbyLeft = pos.tabbyCatX - CatCompanionLayout.loadingTabbyCatSize.width * 0.5
            let blackLeft = pos.blackCatX - CatCompanionLayout.loadingBlackCatSize.width * 0.5
            let blackRight = pos.blackCatX + CatCompanionLayout.loadingBlackCatSize.width * 0.5
            XCTAssertGreaterThanOrEqual(tabbyLeft, 0.0, "Tabby clipped left at fraction \(frac)")
            XCTAssertGreaterThanOrEqual(blackLeft, 0.0, "Black cat clipped left at fraction \(frac)")
            XCTAssertLessThanOrEqual(blackRight, CatCompanionLayout.loadingTrackWidth)
            XCTAssertLessThanOrEqual(pos.sparkX, CatCompanionLayout.loadingTrackWidth)
            XCTAssertGreaterThanOrEqual(pos.sparkX, pos.blackCatX + 36.0 - 0.01)
        }
    }

    func testPauseCatFasterIdleThresholdAndPlayheadCollisionAvoidance() {
        XCTAssertEqual(PauseCatLifecycle.idleThresholdSeconds, 6.0, accuracy: 0.001)

        // Typical 4K 1080p-point tvOS bottom track (1920 - 128 = 1792 pt)
        let catW = CatCompanionLayout.pauseCatSize.width
        let wideAnchor = PauseCatLifecycle.centeredAnchorX(trackWidth: 1792, catWidth: catW)
        let expectedCenter = (1792.0 - catW) * 0.5
        XCTAssertEqual(wideAnchor, expectedCenter, accuracy: 0.5)

        // When playhead is far from center, cats stay centered
        XCTAssertEqual(
            PauseCatLifecycle.safeAnchorX(trackWidth: 1792, playheadX: 140, catWidth: catW),
            expectedCenter,
            accuracy: 0.5
        )
        XCTAssertEqual(
            PauseCatLifecycle.safeAnchorX(trackWidth: 1792, playheadX: 1650, catWidth: catW),
            expectedCenter,
            accuracy: 0.5
        )

        // When playhead is anywhere near center, cats shift cleanly away without colliding
        for centerPlayheadX in [780.0, 896.0, 960.0, 1020.0] {
            let shifted = PauseCatLifecycle.safeAnchorX(
                trackWidth: 1792,
                playheadX: centerPlayheadX,
                catWidth: catW
            )
            XCTAssertGreaterThanOrEqual(shifted, 0)
            XCTAssertLessThanOrEqual(shifted + catW, 1792)
            let overlapsPlayhead = (shifted + catW) > (centerPlayheadX - 30) && shifted < (centerPlayheadX + 30)
            XCTAssertFalse(overlapsPlayhead, "Cats overlapped playhead at x=\(centerPlayheadX): anchor=\(shifted)")
        }

        // Narrower width still stays cleanly within bounds
        let compactAnchor = PauseCatLifecycle.safeAnchorX(trackWidth: 480, playheadX: 240, catWidth: catW)
        XCTAssertGreaterThanOrEqual(compactAnchor, 0)
        XCTAssertLessThanOrEqual(compactAnchor + catW, 480)
    }

    func testActiveCatPosesStayUnclippedInside80x56Canvas() {
        let phases = stride(from: 0.0, through: 1.0, by: 0.05)
        for p in phases {
            let poses: [CatPose] = [
                .running(stridePhase: p, sprintIntensity: 1.0),
                .pounceCrouch(wigglePhase: p, crouchBlend: 1.0),
                .prowling(stridePhase: p, sniffProgress: 0.0),
                .prowling(stridePhase: p, sniffProgress: 1.0),
                .stretching(progress: p),
                .alertPerk(hopProgress: p),
            ]
            for pose in poses {
                let bounds = CatMascotCanvasView.activeCanvasBounds(for: pose)
                XCTAssertGreaterThanOrEqual(bounds.minX, 0.0, "Left clip for \(pose): \(bounds)")
                XCTAssertLessThanOrEqual(bounds.maxX, 80.0, "Right clip for \(pose): \(bounds)")
                XCTAssertGreaterThanOrEqual(bounds.minY, 0.0, "Top clip for \(pose): \(bounds)")
                XCTAssertLessThanOrEqual(bounds.maxY, 56.0, "Bottom clip for \(pose): \(bounds)")
            }
        }
    }

    func testCatMascotPalettesAndAssetCatalogMascotImagesLoad() throws {
        let blackPalette = CatMascotCanvasView.palette(for: .blackNightFury)
        let blackCoat = try rgbComponents(blackPalette.coat)
        XCTAssertEqual(blackCoat.r, 56.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(blackCoat.g, 51.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(blackCoat.b, 77.0 / 255.0, accuracy: 0.01)

        let scarletFin = try rgbComponents(blackPalette.tailFin)
        XCTAssertEqual(scarletFin.r, 230.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(scarletFin.g, 56.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(scarletFin.b, 51.0 / 255.0, accuracy: 0.01)

        let tabbyPalette = CatMascotCanvasView.palette(for: .brownTabby)
        let tabbyCoat = try rgbComponents(tabbyPalette.coat)
        XCTAssertEqual(tabbyCoat.r, 148.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(tabbyCoat.g, 105.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(tabbyCoat.b, 66.0 / 255.0, accuracy: 0.01)

        let tabbyIris = try rgbComponents(tabbyPalette.eyeIris)
        XCTAssertEqual(tabbyIris.r, 133.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(tabbyIris.g, 166.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(tabbyIris.b, 87.0 / 255.0, accuracy: 0.01)

        // Genuine extracted illustrations must compile cleanly into Assets.car
        XCTAssertNotNil(UIImage(named: "MascotCatsDuo"))
        XCTAssertNotNil(UIImage(named: "LunaMoonCrescent"))
        XCTAssertNotNil(UIImage(named: "LunaMoonCatsEmblem"))
    }

    func testLunaButtonThemeColorsContrastAndSemanticTokens() throws {
        // Warm golden Luna focus glow (#FCE19E -> #F2B544) & Play sheen vs midnight #07090E
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.focusGoldTop), 10.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.focusGoldBottom), 10.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.playFocusTop), 10.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.playFocusBottom), 9.0)

        // Resting .glassPill (#34466C -> #293858) achieves elevated starry-blue L* ≈ 24–30 above #0E131D
        let restTopLStar = try cieLStar(LunaTheme.buttonGlassTop)
        let restBotLStar = try cieLStar(LunaTheme.buttonGlassBottom)
        XCTAssertGreaterThanOrEqual(restTopLStar, 26.0)
        XCTAssertLessThanOrEqual(restTopLStar, 32.0)
        XCTAssertGreaterThanOrEqual(restBotLStar, 22.0)

        let restTopLum = try relativeLuminance(LunaTheme.buttonGlassTop)
        let panelLum = try relativeLuminance(LunaTheme.surface)
        XCTAssertGreaterThan(restTopLum, panelLum * 5.0)
        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.moonlight, background: LunaTheme.buttonGlassTop), 7.0)

        // Semantic accent hex values
        let periwinkle = try rgbComponents(LunaTheme.periwinkle)
        XCTAssertEqual(periwinkle.r, 148.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(periwinkle.g, 168.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(periwinkle.b, 255.0 / 255.0, accuracy: 0.01)

        let coral = try rgbComponents(LunaTheme.coral)
        XCTAssertEqual(coral.r, 240.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(coral.g, 113.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(coral.b, 103.0 / 255.0, accuracy: 0.01)

        // Selected 30% semantic tint over buttonSelectedBaseTop maintains >= 6.5:1 crisp white text contrast
        let baseRgb = try rgbComponents(LunaTheme.buttonSelectedBaseTop)
        for accentColor in [LunaTheme.amber, LunaTheme.emerald, LunaTheme.periwinkle, LunaTheme.coral] {
            let aRgb = try rgbComponents(accentColor)
            let selectedBg = Color(
                red: aRgb.r * 0.30 + baseRgb.r * 0.70,
                green: aRgb.g * 0.30 + baseRgb.g * 0.70,
                blue: aRgb.b * 0.30 + baseRgb.b * 0.70
            )
            XCTAssertGreaterThanOrEqual(try contrastRatio(foreground: .white, background: selectedBg), 6.5)
        }
    }

    @MainActor
    func testScrubPreviewBubbleAndPillButtonVariantsConstructCleanly() {
        let bubble = ScrubPreviewBubbleView(
            targetSeconds: 120,
            originSeconds: 90,
            chapterTitle: "Kapittel 1",
            previewImage: nil,
            drawsInCompositorView: false,
            showCatCompanion: true,
            onMountCompositorView: { _ in }
        )
        XCTAssertTrue(bubble.showCatCompanion)
        XCTAssertEqual(bubble.preferredWidth, ScrubPreviewBubbleView.compactWidth)
        XCTAssertGreaterThanOrEqual(ScrubPreviewBubbleView.compactWidth, 212)

        let compactWatchlist = LunaPillButton(
            "Huskeliste",
            systemImage: "bookmark.fill",
            isSelected: true,
            prominence: .glassPill,
            accent: .periwinkle,
            size: .compact
        ) {}
        XCTAssertEqual(compactWatchlist.accent, .periwinkle)
        XCTAssertEqual(compactWatchlist.size, .compact)

        let coralAction = LunaPillButton(
            "Nullstill tilkobling",
            systemImage: "xmark.circle",
            prominence: .subtleChip,
            accent: .coral
        ) {}
        XCTAssertEqual(coralAction.accent, .coral)
    }

    private func rgbComponents(_ color: Color) throws -> (r: Double, g: Double, b: Double) {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            throw NSError(domain: "ColorTest", code: 1)
        }
        return (Double(r), Double(g), Double(b))
    }

    private func relativeLuminance(_ color: Color) throws -> Double {
        let (r, g, b) = try rgbComponents(color)
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func cieLStar(_ color: Color) throws -> Double {
        let y = try relativeLuminance(color)
        return y > 0.008856 ? 116.0 * pow(y, 1.0 / 3.0) - 16.0 : 903.3 * y
    }

    private func contrastRatio(foreground: Color, background: Color) throws -> Double {
        let l1 = try relativeLuminance(foreground)
        let l2 = try relativeLuminance(background)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
