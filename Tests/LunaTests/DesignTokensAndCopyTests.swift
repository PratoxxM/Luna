import Foundation
import SwiftUI
import XCTest
@testable import Luna

final class DesignTokensAndCopyTests: XCTestCase {
    func testTokensChecksumAndTypographyScaleFloor() {
        XCTAssertEqual(
            LunaTokens.tokensSha256,
            "93300ad9c5c654cdeb77827205f72d1145440d93680ccca63ccac8ba3530bc6f"
        )
        XCTAssertGreaterThanOrEqual(LunaTokens.Typography.badge, 22.0)
        XCTAssertGreaterThanOrEqual(LunaTokens.Typography.caption, 22.0)
        XCTAssertGreaterThanOrEqual(LunaTokens.Typography.body, 28.0)
        XCTAssertEqual(LunaTokens.Layout.posterW, 280.0)
        XCTAssertEqual(LunaTokens.Layout.posterH, 420.0)
        XCTAssertEqual(LunaTokens.Layout.gridPosterW, 260.0)
        XCTAssertEqual(LunaTokens.Layout.gridPosterH, 390.0)
        XCTAssertEqual(LunaTokens.Layout.gridCardGap, 36.0)
        XCTAssertEqual(6.0 * LunaTokens.Layout.gridPosterW + 5.0 * LunaTokens.Layout.gridCardGap, 1740.0)
        XCTAssertEqual(LunaTokens.Layout.backdropW, 520.0)
        XCTAssertEqual(LunaTokens.Layout.backdropH, 293.0)

        let _ = LunaTheme.Font.heroSerif
        let _ = LunaTheme.Font.titleSerif
        let _ = LunaTheme.Font.pageTitle
        let _ = LunaTheme.Font.sectionTitle
        let _ = LunaTheme.Font.cardTitle
        let _ = LunaTheme.Font.body
        let _ = LunaTheme.Font.subtitle
        let _ = LunaTheme.Font.caption
        let _ = LunaTheme.Font.badge
        let _ = LunaTheme.Font.brandSerif
        let _ = LunaTheme.Font.pairingCode
        let _ = LunaTheme.Font.subtitleCue(size: 42)
        let _ = LunaTheme.Font.tabTitle
        let _ = LunaTheme.Font.primaryPlayLabel

        XCTAssertGreaterThanOrEqual(LunaTheme.Font.minimumPointSizeFloor, 22.0)
        XCTAssertFalse(LunaTheme.Font.allFixedPointSizes.isEmpty)
        for (role, size) in LunaTheme.Font.allFixedPointSizes {
            XCTAssertGreaterThanOrEqual(size, LunaTheme.Font.minimumPointSizeFloor, "Role \(role) below 22 pt floor")
        }
    }

    func testRoomAtmosphereCalibrationAndEquipmentLabels() {
        XCTAssertEqual(
            LunaRoomAtmosphere.resolve(atmosphere: nil, hardwareProfile: "dv-fel-714", roomName: "Kjellerstua"),
            .cinema
        )
        XCTAssertEqual(
            LunaRoomAtmosphere.resolve(atmosphere: nil, hardwareProfile: "hdr10-512", roomName: "Stua"),
            .living
        )
        XCTAssertEqual(
            LunaRoomAtmosphere.resolve(atmosphere: "living", hardwareProfile: "custom", roomName: "Loft"),
            .living
        )
        XCTAssertEqual(
            LunaCopy.roomEquipmentLabel(hardwareProfile: "dv-fel-714", roomName: "Kjellerstua", serverLabel: "Egen kino"),
            "Egen kino"
        )
    }

    @MainActor
    func testFocusStyleSpringAndSurfaceModifier() {
        XCTAssertEqual(LunaFocusStyle.springResponse, 0.32, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.springDamping, 0.86, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.borderWidth, 2.0, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.borderOpacity, 0.85, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .card, isFocused: true), 1.05, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .listRow, isFocused: true), 1.0, accuracy: 0.001)
        XCTAssertEqual(LunaFocusStyle.scaleEffect(for: .control, isFocused: true), 1.04, accuracy: 0.001)

        let _ = Color.clear.lunaFocusSurface(.card, isFocused: true)
        let warnIcon = LunaPillButton.resolveIconForeground(
            isFocused: false,
            isSelected: false,
            prominence: .glassPill,
            accent: .warn
        )
        XCTAssertEqual(warnIcon, LunaTheme.warn)
    }

    func testNorwegianCopyPluralDecimalsAndBenefits() {
        XCTAssertEqual(LunaCopy.plural(0, "mediefil", "mediefiler"), "0 mediefiler")
        XCTAssertEqual(LunaCopy.plural(1, "mediefil", "mediefiler"), "1 mediefil")
        XCTAssertEqual(LunaCopy.plural(3, "mediefil", "mediefiler"), "3 mediefiler")

        XCTAssertEqual(LunaCopy.pinnedCount(1), "1 tittel festet")
        XCTAssertEqual(LunaCopy.pinnedCount(4), "4 titler festet")
        XCTAssertEqual(LunaCopy.chaptersHeader(1), "1 kapittel")
        XCTAssertEqual(LunaCopy.chaptersHeader(8), "8 kapitler")
        XCTAssertEqual(LunaCopy.searchHits(1), "1 treff")
        XCTAssertEqual(LunaCopy.episodesCount(1), "1 episode")
        XCTAssertEqual(LunaCopy.episodesCount(6), "6 episoder")
        XCTAssertEqual(LunaCopy.seasonsCount(1), "1 sesong")
        XCTAssertEqual(LunaCopy.seasonsCount(3), "3 sesonger")
        XCTAssertEqual(LunaCopy.mediaFilesCount(1), "1 mediefil")
        XCTAssertEqual(LunaCopy.mediaFilesCount(2), "2 mediefiler")
        XCTAssertEqual(LunaCopy.formatListEpisodeCode("S28E06"), "S28 · E6")

        XCTAssertEqual(LunaCopy.formatDays(1.0, suffix: "igjen"), "1 dag igjen")
        XCTAssertEqual(LunaCopy.formatDays(4.8, suffix: "igjen"), "5 dager igjen")
        XCTAssertEqual(LunaCopy.formatDecimal(7.9), "7,9")
        XCTAssertEqual(LunaCopy.formatRating(8.4), "★ 8,4")
        XCTAssertEqual(LunaCopy.formatGigabytes(50.0), "50,0 GB")
        XCTAssertEqual(LunaCopy.formatMegabytes(12.3), "12,3 MB")

        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "nvme"), "Starter umiddelbart")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "archive"), "Fra arkivet")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "vfs"), "Strømmes ved start")
        XCTAssertEqual(LunaCopy.tierBenefitLabel(tier: "usenet", state: "upcoming"), "Kommer")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "dv-fel-714"), "LG OLED · Dolby Vision · 7.1.4")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "hdr10-512"), "Samsung Frame · HDR10+ · 7.1.4")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "livingroom"), "Samsung Frame · HDR10+ · 7.1.4")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "living"), "Samsung Frame · HDR10+ · 7.1.4")
        XCTAssertEqual(LunaCopy.roomEquipmentLabel(hardwareProfile: "Stua"), "Samsung Frame · HDR10+ · 7.1.4")
        XCTAssertEqual(
            LunaCopy.roomEquipmentLabel(hardwareProfile: "custom", roomName: "Gjestestue"),
            "Apple TV 4K · Direkte avspilling"
        )
        XCTAssertEqual(
            LunaCopy.friendlyErrorMessage(LunaCoreError.serverMessage(503, "Database opptatt")),
            "Database opptatt"
        )
        XCTAssertEqual(
            LunaCopy.friendlyErrorMessage(URLError(.timedOut)),
            "LunaCore svarte ikke i tide. Prøv igjen om et øyeblikk."
        )

        var osloCal = Calendar(identifier: .gregorian)
        osloCal.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        let friEvening = osloCal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 19, minute: 0))!
        XCTAssertEqual(LunaCopy.timeGreeting(for: friEvening, calendar: osloCal), "Fredagskveld")
    }
}
