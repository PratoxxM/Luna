import Foundation
import XCTest
@testable import LunaCore

final class PlaybackM3BPolicyTests: XCTestCase {
    func testEmbeddedFontNamePolicyFiltersNormalizesAndHashes() {
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Font.TTF", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Custom.otf", mimeType: "application/octet-stream"))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "CJK.ttc", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Open.otc", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "blob", mimeType: "font/ttf; charset=utf-8"))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "blob", mimeType: "application/x-truetype-font"))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "blob", mimeType: "application/vnd.ms-opentype"))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "blob", mimeType: "application/font-sfnt"))
        XCTAssertFalse(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "poster.png", mimeType: "image/png"))
        XCTAssertFalse(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "subs.srt", mimeType: "text/plain"))
        XCTAssertFalse(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "", mimeType: ""))

        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "font.OTF", mimeType: ""), "otf")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "font.ttc", mimeType: ""), "ttc")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "font.otc", mimeType: ""), "otc")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "blob", mimeType: "font/otf"), "otf")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "blob", mimeType: "font/collection"), "ttc")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "blob", mimeType: "application/octet-stream"), "ttf")

        XCTAssertEqual(EmbeddedFontNamePolicy.stripAssVerticalPrefix("@DFKai-SB"), "DFKai-SB")
        XCTAssertEqual(EmbeddedFontNamePolicy.stripAssVerticalPrefix("  \"@@Noto Sans CJK JP\" "), "Noto Sans CJK JP")
        XCTAssertEqual(EmbeddedFontNamePolicy.normalizedLookupKeys(for: "@DFKai-SB"), ["dfkai-sb", "dfkaisb"])
        XCTAssertEqual(EmbeddedFontNamePolicy.normalizedLookupKeys(for: "   @@@  "), [])

        let abcHash = EmbeddedFontNamePolicy.sha256Hex(for: Data("abc".utf8))
        XCTAssertEqual(abcHash, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSubtitleOCRPolicyPromotesCleanDialogueAndFallsBackOnNoiseLowConfidenceOrSigns() {
        let bottomRect = SubtitleOCRRectInput(minX: 0.25, minY: 0.80, width: 0.50, height: 0.10)
        let topRect = SubtitleOCRRectInput(minX: 0.25, minY: 0.08, width: 0.50, height: 0.08)
        let goodLines = [
            SubtitleOCRLineInput(text: "  Hei på deg! ", confidence: 0.92),
            SubtitleOCRLineInput(text: "Hvordan går det?", confidence: 0.88),
        ]

        // Gated off -> nil
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Hei på deg!\nHvordan går det?",
                lines: goodLines,
                imagePosition: bottomRect,
                isOCRPrompted: false
            )
        )

        // Valid bottom dialogue -> normalized multiline string
        XCTAssertEqual(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Hei på deg!\nHvordan går det?",
                lines: goodLines,
                imagePosition: bottomRect,
                isOCRPrompted: true
            ),
            "Hei på deg!\nHvordan går det?"
        )

        // Valid top dialogue -> promoted
        XCTAssertEqual(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Topptekst",
                lines: [SubtitleOCRLineInput(text: "Topptekst", confidence: 0.90)],
                imagePosition: topRect,
                isOCRPrompted: true
            ),
            "Topptekst"
        )

        // Empty or punctuation-only noise -> nil
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "   ",
                lines: [SubtitleOCRLineInput(text: "   ", confidence: 0.99)],
                imagePosition: bottomRect,
                isOCRPrompted: true
            )
        )
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "| ... -",
                lines: [SubtitleOCRLineInput(text: "| ... -", confidence: 0.95)],
                imagePosition: bottomRect,
                isOCRPrompted: true
            )
        )

        // Low single-line confidence (< 0.45) or low mean (< 0.62) -> nil
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Lav linje",
                lines: [
                    SubtitleOCRLineInput(text: "Bra linje", confidence: 0.95),
                    SubtitleOCRLineInput(text: "Lav linje", confidence: 0.40),
                ],
                imagePosition: bottomRect,
                isOCRPrompted: true
            )
        )
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Lavt snitt",
                lines: [
                    SubtitleOCRLineInput(text: "Linje en", confidence: 0.58),
                    SubtitleOCRLineInput(text: "Linje to", confidence: 0.60),
                ],
                imagePosition: bottomRect,
                isOCRPrompted: true
            )
        )

        // > 4 lines -> nil
        let fiveLines = (1...5).map { SubtitleOCRLineInput(text: "Linje \($0)", confidence: 0.95) }
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "1\n2\n3\n4\n5",
                lines: fiveLines,
                imagePosition: bottomRect,
                isOCRPrompted: true
            )
        )

        // Mid-screen sign or off-center side annotation -> nil
        let midSignRect = SubtitleOCRRectInput(minX: 0.30, minY: 0.40, width: 0.40, height: 0.08)
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "CAFE TOKYO",
                lines: [SubtitleOCRLineInput(text: "CAFE TOKYO", confidence: 0.96)],
                imagePosition: midSignRect,
                isOCRPrompted: true
            )
        )
        let sideSignRect = SubtitleOCRRectInput(minX: 0.04, minY: 0.78, width: 0.20, height: 0.08)
        XCTAssertNil(
            SubtitleOCRPolicy.resolveTextCue(
                recognizedText: "Skilt",
                lines: [SubtitleOCRLineInput(text: "Skilt", confidence: 0.96)],
                imagePosition: sideSignRect,
                isOCRPrompted: true
            )
        )
    }

    func testComfortPreferencesRecognizesBitmapSubtitleTextPersistenceAndTierGating() async throws {
        try await MainActor.run {
            let suite = "luna.test.ocr.pref.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let initial = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
            XCTAssertFalse(initial.recognizesBitmapSubtitleText)
            XCTAssertFalse(initial.effectiveRecognizesBitmapSubtitleText(memoryTier: .high2026))
            XCTAssertFalse(initial.effectiveRecognizesBitmapSubtitleText(memoryTier: .standard))

            initial.recognizesBitmapSubtitleText = true
            XCTAssertTrue(defaults.bool(forKey: SideloadSafeStorage.recognizesBitmapSubtitleTextKey))
            XCTAssertTrue(initial.effectiveRecognizesBitmapSubtitleText(memoryTier: .high2026))
            XCTAssertFalse(initial.effectiveRecognizesBitmapSubtitleText(memoryTier: .standard))

            let reloaded = ComfortPreferences(defaults: defaults, memoryTier: .high2026)
            XCTAssertTrue(reloaded.recognizesBitmapSubtitleText)
            XCTAssertTrue(reloaded.effectiveRecognizesBitmapSubtitleText(memoryTier: .high2026))
        }
    }

    func testAudioBinauralPolicyAndAudioChainSummaryFormatter() {
        XCTAssertEqual(
            AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: false, effectiveSpeakerLayout: "7.1.4"),
            .inactive
        )
        XCTAssertFalse(
            AudioBinauralPolicy.effectiveBinauralFlag(isBinauralRouteActive: false, effectiveSpeakerLayout: "7.1.4")
        )
        XCTAssertNil(AudioBinauralPolicy.quickPanelNotice(for: .inactive))

        XCTAssertEqual(
            AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: true, effectiveSpeakerLayout: "7.1.4"),
            .active
        )
        XCTAssertTrue(
            AudioBinauralPolicy.effectiveBinauralFlag(isBinauralRouteActive: true, effectiveSpeakerLayout: "5.1.2")
        )
        XCTAssertEqual(
            AudioBinauralPolicy.quickPanelNotice(for: .active),
            "Hodetelefoner · Binaural romlyd aktiv"
        )

        XCTAssertEqual(
            AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: true, effectiveSpeakerLayout: "2.0"),
            .suppressedByStereo
        )
        XCTAssertFalse(
            AudioBinauralPolicy.effectiveBinauralFlag(isBinauralRouteActive: true, effectiveSpeakerLayout: "2.0")
        )
        XCTAssertEqual(
            AudioBinauralPolicy.quickPanelNotice(for: .suppressedByStereo),
            "Hodetelefoner · Binaural av (Stereo 2.0 valgt)"
        )

        XCTAssertEqual(
            AudioChainSummaryFormatter.summary(
                speakerLayoutOverride: .auto,
                sessionRoomAutoLayout: "7.1.4",
                audioFormatBadge: "7.1.4 Atmos",
                audioDecoderLabel: "bridged",
                audioEnhancement: .dialogueLift,
                audioDelayDisplay: "-50 ms",
                binauralStatus: .active
            ),
            "Auto 7.1.4 Atmos (bridged) · Binaural · Dialogløft · -50 ms"
        )
        XCTAssertEqual(
            AudioChainSummaryFormatter.summary(
                speakerLayoutOverride: .stereo,
                sessionRoomAutoLayout: "7.1.4",
                audioFormatBadge: "Stereo 2.0",
                audioDecoderLabel: "decoded",
                audioEnhancement: .reference,
                audioDelayDisplay: nil,
                binauralStatus: .suppressedByStereo
            ),
            "Stereo 2.0 (decoded) · Binaural av (2.0)"
        )
    }

    func testPlaybackStallCounterDeduplicatesAndSuppressesExpectedTransitions() {
        var counter = PlaybackStallCounter()
        XCTAssertEqual(counter.stallCount, 0)

        // Normal startup & normal seek (including duplicate .rebuffering emissions) -> 0 stalls
        counter.recordTransition(from: .normal, to: .loadingOrSeeking, suppressCounting: false)
        counter.recordTransition(from: .loadingOrSeeking, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .normal, suppressCounting: false)
        counter.recordTransition(from: .normal, to: .loadingOrSeeking, suppressCounting: false)
        counter.recordTransition(from: .loadingOrSeeking, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .normal, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 0)

        // Seek with duplicate .rebuffering that turns into .stalled -> 1 stall
        counter.recordTransition(from: .normal, to: .loadingOrSeeking, suppressCounting: false)
        counter.recordTransition(from: .loadingOrSeeking, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .stalled, suppressCounting: false)
        counter.recordTransition(from: .stalled, to: .stalled, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 1)

        // Recover to playing, then mid-playback rebuffer + stall -> 2 stalls
        counter.recordTransition(from: .stalled, to: .normal, suppressCounting: false)
        counter.recordTransition(from: .normal, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .stalled, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 2)

        // Transient switch/restore suppresses counting and clears active episode on .normal
        counter.recordTransition(from: .stalled, to: .loadingOrSeeking, suppressCounting: true)
        counter.recordTransition(from: .loadingOrSeeking, to: .stalled, suppressCounting: true)
        counter.recordTransition(from: .stalled, to: .normal, suppressCounting: true)
        XCTAssertEqual(counter.stallCount, 2)

        // Next real mid-playback stall counts as 3
        counter.recordTransition(from: .normal, to: .stalled, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 3)

        counter.reset()
        XCTAssertEqual(counter.stallCount, 0)
    }

    func testBackgroundScrubPreviewPolicyFailClosedMatrix() {
        let highTierFloor = UInt64(1_500 * 1024 * 1024)
        let plentyRAM = UInt64(2_200 * 1024 * 1024)

        XCTAssertTrue(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: 8,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        XCTAssertTrue(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "ssd",
                tier: nil,
                supportsByteRanges: nil,
                preferDualLayerDolbyVision: false,
                dvProfile: 7,
                dvEnhancementLayer: "MEL",
                requiresSoftwareVideoDecode: false,
                serverConfigured: nil
            )
        )

        // Fail closed on .standard, low RAM, explicit server false, byte ranges false, SW decode, FEL, or non-NVMe tiers
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .standard,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: 900 * 1024 * 1024,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: nil,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: highTierFloor - 1,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: nil,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        for badTier in ["archive", "vfs", "infinidysk", "easynews", "usenet", "nzb", "remote", "http", ""] {
            XCTAssertFalse(
                BackgroundScrubPreviewPolicy.shouldGenerate(
                    memoryTier: .high2026,
                    availableMemoryBytes: plentyRAM,
                    playbackMemoryShedFloorBytes: highTierFloor,
                    source: badTier,
                    tier: badTier,
                    supportsByteRanges: true,
                    preferDualLayerDolbyVision: false,
                    dvProfile: nil,
                    dvEnhancementLayer: nil,
                    requiresSoftwareVideoDecode: false,
                    serverConfigured: true
                ),
                "Expected fail-closed false for source/tier '\(badTier)'"
            )
        }
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: true,
                dvProfile: 7,
                dvEnhancementLayer: "FEL",
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: 7,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: nil,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: true,
                serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: false,
                preferDualLayerDolbyVision: false,
                dvProfile: nil,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: true
            )
        )
        XCTAssertFalse(
            BackgroundScrubPreviewPolicy.shouldGenerate(
                memoryTier: .high2026,
                availableMemoryBytes: plentyRAM,
                playbackMemoryShedFloorBytes: highTierFloor,
                source: "nvme",
                tier: "nvme",
                supportsByteRanges: true,
                preferDualLayerDolbyVision: false,
                dvProfile: nil,
                dvEnhancementLayer: nil,
                requiresSoftwareVideoDecode: false,
                serverConfigured: false
            )
        )
    }
}
