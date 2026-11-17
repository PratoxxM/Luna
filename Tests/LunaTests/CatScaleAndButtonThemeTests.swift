import CoreGraphics
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Luna

final class CatScaleAndButtonThemeTests: XCTestCase {
    func testCatCompanionTenFootLayoutScalesAndInitialSprintFloor() {
        XCTAssertEqual(CatCompanionLayout.loadingTrackWidth, 640)
        XCTAssertEqual(CatCompanionLayout.loadingTrackHeight, 7)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingContainerHeight, 84)
        XCTAssertEqual(CatCompanionLayout.loadingBlackCatSize, CGSize(width: 94, height: 66))
        XCTAssertEqual(CatCompanionLayout.loadingTabbyCatSize, CGSize(width: 90, height: 63))
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingBlackOffset, 54)
        XCTAssertGreaterThanOrEqual(CatCompanionLayout.loadingTabbySpacing, 88)
        XCTAssertEqual(CatCompanionLayout.pauseCatSize, CGSize(width: 96, height: 68))
        XCTAssertEqual(CatCompanionLayout.prowlingCatSize, CGSize(width: 116, height: 81))
        XCTAssertEqual(CatCompanionLayout.moonSceneSize, CGSize(width: 216, height: 216))
        XCTAssertEqual(CatCompanionLayout.moonCatSize, CGSize(width: 114, height: 80))
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
    }

    func testPauseCatFasterIdleThresholdAndCenteredSafeAnchor() {
        XCTAssertEqual(PauseCatLifecycle.idleThresholdSeconds, 6.0, accuracy: 0.001)

        // Typical 4K 1080p-point tvOS bottom track (1920 - 128 = 1792 pt)
        let wideAnchor = PauseCatLifecycle.centeredAnchorX(trackWidth: 1792)
        let expectedCenter = (1792.0 - 96.0) * 0.5
        XCTAssertEqual(wideAnchor, expectedCenter, accuracy: 0.5)
        // Leaves ample room on the left for long titles and on the right for «Ferdig kl. …» + scamper-off
        XCTAssertGreaterThan(wideAnchor, 600)
        XCTAssertLessThan(wideAnchor + 96 + 145, 1792 - 450)

        // Narrower width still stays cleanly within bounds
        let compactAnchor = PauseCatLifecycle.centeredAnchorX(trackWidth: 480)
        XCTAssertGreaterThanOrEqual(compactAnchor, 0)
        XCTAssertLessThanOrEqual(compactAnchor + 96, 480)
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

    func testCatMascotPalettesMatchAppIconFidelityAndVisibility() throws {
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
    }

    func testLunaButtonThemeColorsContrastAndSemanticTokens() throws {
        // Focus platter (#F4F7FC -> #F3E0B8) vs midnight #07090E text must exceed 13.8:1
        let pearlTopContrast = try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.pearlFocusTop)
        let pearlBotContrast = try contrastRatio(foreground: LunaTheme.canvas, background: LunaTheme.pearlFocusBottom)
        XCTAssertGreaterThan(pearlTopContrast, 13.8)
        XCTAssertGreaterThan(pearlBotContrast, 13.8)

        // Resting .glassPill (#24324F -> #1A253B) must clearly stand out against Settings panel (#0E131D)
        let restTopLum = try relativeLuminance(LunaTheme.buttonGlassTop)
        let restBottomLum = try relativeLuminance(LunaTheme.buttonGlassBottom)
        let panelLum = try relativeLuminance(LunaTheme.surface)
        XCTAssertGreaterThan(restTopLum, panelLum * 2.0)
        XCTAssertGreaterThan(restBottomLum, panelLum * 1.4)

        // Semantic accent hex values
        let periwinkle = try rgbComponents(LunaTheme.periwinkle)
        XCTAssertEqual(periwinkle.r, 148.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(periwinkle.g, 168.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(periwinkle.b, 255.0 / 255.0, accuracy: 0.01)

        let coral = try rgbComponents(LunaTheme.coral)
        XCTAssertEqual(coral.r, 240.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(coral.g, 113.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(coral.b, 103.0 / 255.0, accuracy: 0.01)

        XCTAssertGreaterThan(try contrastRatio(foreground: LunaTheme.moonlight, background: LunaTheme.buttonGlassTop), 9.0)

        // Selected periwinkle tint (11% wash over #24324F) maintains >= 4.5:1 WCAG AA contrast
        let pRgb = try rgbComponents(LunaTheme.periwinkle)
        let gRgb = try rgbComponents(LunaTheme.buttonGlassTop)
        let selectedBg = Color(
            red: pRgb.r * 0.11 + gRgb.r * 0.89,
            green: pRgb.g * 0.11 + gRgb.g * 0.89,
            blue: pRgb.b * 0.11 + gRgb.b * 0.89
        )
        XCTAssertGreaterThanOrEqual(try contrastRatio(foreground: LunaTheme.periwinkle, background: selectedBg), 4.5)
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

    private func contrastRatio(foreground: Color, background: Color) throws -> Double {
        let l1 = try relativeLuminance(foreground)
        let l2 = try relativeLuminance(background)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
