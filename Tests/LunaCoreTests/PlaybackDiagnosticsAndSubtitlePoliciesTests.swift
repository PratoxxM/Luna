import Foundation
import XCTest
@testable import LunaCore

final class PlaybackDiagnosticsAndSubtitlePoliciesTests: XCTestCase {
    // MARK: - EmbeddedFontNamePolicy & SubtitleOCRPolicy

    func testEmbeddedFontNameAndSubtitleOCRPolicies() {
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Font.TTF", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Custom.otf", mimeType: "application/octet-stream"))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "CJK.ttc", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "Open.otc", mimeType: ""))
        XCTAssertTrue(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "blob", mimeType: "font/ttf; charset=utf-8"))
        XCTAssertFalse(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "poster.png", mimeType: "image/png"))
        XCTAssertFalse(EmbeddedFontNamePolicy.isSupportedFontAttachment(filename: "", mimeType: ""))

        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "blob", mimeType: "font/otf"), "otf")
        XCTAssertEqual(EmbeddedFontNamePolicy.preferredFontExtension(filename: "blob", mimeType: "font/collection"), "ttc")
        XCTAssertEqual(EmbeddedFontNamePolicy.stripAssVerticalPrefix("  \"@@Noto Sans CJK JP\" "), "Noto Sans CJK JP")
        XCTAssertEqual(EmbeddedFontNamePolicy.normalizedLookupKeys(for: "@DFKai-SB"), ["dfkai-sb", "dfkaisb"])
        XCTAssertEqual(EmbeddedFontNamePolicy.sha256Hex(for: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let bottomRect = SubtitleOCRRectInput(minX: 0.25, minY: 0.80, width: 0.50, height: 0.10)
        let topRect = SubtitleOCRRectInput(minX: 0.25, minY: 0.08, width: 0.50, height: 0.08)
        let midSignRect = SubtitleOCRRectInput(minX: 0.30, minY: 0.40, width: 0.40, height: 0.08)
        let sideSignRect = SubtitleOCRRectInput(minX: 0.04, minY: 0.78, width: 0.20, height: 0.08)
        let goodLines = [
            SubtitleOCRLineInput(text: "  Hei på deg! ", confidence: 0.92),
            SubtitleOCRLineInput(text: "Hvordan går det?", confidence: 0.88),
        ]

        XCTAssertNil(SubtitleOCRPolicy.resolveTextCue(recognizedText: "Hei", lines: goodLines, imagePosition: bottomRect, isOCRPrompted: false))
        XCTAssertEqual(
            SubtitleOCRPolicy.resolveTextCue(recognizedText: "Hei på deg!\nHvordan går det?", lines: goodLines, imagePosition: bottomRect, isOCRPrompted: true),
            "Hei på deg!\nHvordan går det?"
        )
        XCTAssertEqual(
            SubtitleOCRPolicy.resolveTextCue(recognizedText: "Topptekst", lines: [SubtitleOCRLineInput(text: "Topptekst", confidence: 0.90)], imagePosition: topRect, isOCRPrompted: true),
            "Topptekst"
        )
        XCTAssertNil(SubtitleOCRPolicy.resolveTextCue(recognizedText: "| ... -", lines: [SubtitleOCRLineInput(text: "| ... -", confidence: 0.95)], imagePosition: bottomRect, isOCRPrompted: true))
        XCTAssertNil(SubtitleOCRPolicy.resolveTextCue(recognizedText: "Lav", lines: [SubtitleOCRLineInput(text: "Lav", confidence: 0.40)], imagePosition: bottomRect, isOCRPrompted: true))
        XCTAssertNil(SubtitleOCRPolicy.resolveTextCue(recognizedText: "CAFE TOKYO", lines: [SubtitleOCRLineInput(text: "CAFE TOKYO", confidence: 0.96)], imagePosition: midSignRect, isOCRPrompted: true))
        XCTAssertNil(SubtitleOCRPolicy.resolveTextCue(recognizedText: "Skilt", lines: [SubtitleOCRLineInput(text: "Skilt", confidence: 0.96)], imagePosition: sideSignRect, isOCRPrompted: true))
    }

    // MARK: - AudioBinauralPolicy, AudioChainSummaryFormatter & PlaybackStallCounter

    func testAudioBinauralSummaryFormatterAndPlaybackStallCounter() {
        XCTAssertEqual(AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: false, effectiveSpeakerLayout: "7.1.4"), .inactive)
        XCTAssertEqual(AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: true, effectiveSpeakerLayout: "7.1.4"), .active)
        XCTAssertEqual(AudioBinauralPolicy.resolveStatus(isBinauralRouteActive: true, effectiveSpeakerLayout: "2.0"), .suppressedByStereo)
        XCTAssertEqual(AudioBinauralPolicy.quickPanelNotice(for: .active), "Hodetelefoner · Binaural romlyd aktiv")
        XCTAssertEqual(AudioBinauralPolicy.quickPanelNotice(for: .suppressedByStereo), "Hodetelefoner · Binaural av (Stereo 2.0 valgt)")

        XCTAssertEqual(
            AudioChainSummaryFormatter.summary(
                speakerLayoutOverride: .auto, sessionRoomAutoLayout: "7.1.4", audioFormatBadge: "7.1.4 Atmos",
                audioDecoderLabel: "bridged", audioEnhancement: .dialogueLift, audioDelayDisplay: "-50 ms", binauralStatus: .active
            ),
            "Auto 7.1.4 Atmos (bridged) · Binaural · Dialogløft · -50 ms"
        )
        XCTAssertEqual(
            AudioChainSummaryFormatter.summary(
                speakerLayoutOverride: .stereo, sessionRoomAutoLayout: "7.1.4", audioFormatBadge: "Stereo 2.0",
                audioDecoderLabel: "decoded", audioEnhancement: .reference, audioDelayDisplay: nil, binauralStatus: .suppressedByStereo
            ),
            "Stereo 2.0 (decoded) · Binaural av (2.0)"
        )

        var counter = PlaybackStallCounter()
        counter.recordTransition(from: .normal, to: .loadingOrSeeking, suppressCounting: false)
        counter.recordTransition(from: .loadingOrSeeking, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .normal, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 0)

        counter.recordTransition(from: .normal, to: .loadingOrSeeking, suppressCounting: false)
        counter.recordTransition(from: .loadingOrSeeking, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .stalled, suppressCounting: false)
        counter.recordTransition(from: .stalled, to: .stalled, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 1)

        counter.recordTransition(from: .stalled, to: .normal, suppressCounting: false)
        counter.recordTransition(from: .normal, to: .rebuffering, suppressCounting: false)
        counter.recordTransition(from: .rebuffering, to: .stalled, suppressCounting: false)
        XCTAssertEqual(counter.stallCount, 2)

        counter.recordTransition(from: .stalled, to: .loadingOrSeeking, suppressCounting: true)
        counter.recordTransition(from: .loadingOrSeeking, to: .stalled, suppressCounting: true)
        counter.recordTransition(from: .stalled, to: .normal, suppressCounting: true)
        XCTAssertEqual(counter.stallCount, 2)

        counter.reset()
        XCTAssertEqual(counter.stallCount, 0)
    }

    // MARK: - DolbyVisionFallbackPolicy, UpscaleSummaryFormatter & PlaybackErrorGuidancePolicy

    func testDolbyVisionFallbackUpscaleSummaryAndErrorGuidancePolicies() {
        var dv = DolbyVisionFallbackPolicy()
        XCTAssertFalse(dv.recordTelemetrySample(droppedFrames: 50, isProfile7FEL: false, isBaseLayerForced: false))
        XCTAssertFalse(dv.recordTelemetrySample(droppedFrames: 4, isProfile7FEL: true, isBaseLayerForced: false))
        XCTAssertFalse(dv.recordTelemetrySample(droppedFrames: 14, isProfile7FEL: true, isBaseLayerForced: false))
        XCTAssertTrue(dv.recordTelemetrySample(droppedFrames: 20, isProfile7FEL: true, isBaseLayerForced: false))
        XCTAssertFalse(dv.recordTelemetrySample(droppedFrames: 45, isProfile7FEL: true, isBaseLayerForced: true))
        XCTAssertFalse(dv.shouldSuggestBaseLayer)
        XCTAssertTrue(dv.recordTelemetrySample(droppedFrames: 28, isProfile7FEL: true, isBaseLayerForced: false))
        dv.reset()
        XCTAssertFalse(dv.shouldSuggestBaseLayer)

        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(sourceWidth: 1920, sourceHeight: 1080, targetWidth: 3840, targetHeight: 2160, scaler: .lanczos),
                disabledReason: nil, lowResUpscaleMode: .off, upscalesFullHDVideo: true, isSDR: true, sourceVideoWidth: 1920, sourceVideoHeight: 1080
            ),
            "1920×1080 → 3840×2160 (Lanczos)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: ActiveUpscaleSummaryInfo(sourceWidth: 1280, sourceHeight: 720, targetWidth: 3840, targetHeight: 2160, scaler: .automatic, mlScale: 1.5, isDegraded: false),
                disabledReason: nil, lowResUpscaleMode: .auto, upscalesFullHDVideo: false, isSDR: true, sourceVideoWidth: 1280, sourceVideoHeight: 720
            ),
            "1280×720 → 3840×2160 (ANE 1,5× + MetalFX)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: nil, disabledReason: nil, lowResUpscaleMode: .auto, upscalesFullHDVideo: true, isSDR: false, sourceVideoWidth: 1920, sourceVideoHeight: 1080
            ),
            "Nativ (HDR-fallback)"
        )
        XCTAssertEqual(
            UpscaleSummaryFormatter.summary(
                activeUpscale: nil, disabledReason: nil, lowResUpscaleMode: .auto, upscalesFullHDVideo: false, isSDR: true, sourceVideoWidth: 1920, sourceVideoHeight: 1080
            ),
            "Nativ (1080p-oppskalering av)"
        )

        XCTAssertTrue(PlaybackErrorGuidancePolicy.userMessage(category: .sourceOpenFailed, underlyingCode: 401, rawMessage: "err").contains("HTTP 401"))
        XCTAssertTrue(PlaybackErrorGuidancePolicy.userMessage(category: .sourceRefused, underlyingCode: 403, rawMessage: "err").contains("HTTP 403"))
        XCTAssertTrue(PlaybackErrorGuidancePolicy.userMessage(category: .sourceOpenFailed, ffmpegErrorCode: -541478725, rawMessage: "err").contains("-541478725"))
        for category in PlaybackErrorCategory.allCases where category != .unknown {
            let msg = PlaybackErrorGuidancePolicy.userMessage(category: category, rawMessage: "raw error")
            XCTAssertFalse(msg.isEmpty)
            XCTAssertNotEqual(msg, "raw error")
        }
        XCTAssertEqual(
            PlaybackErrorGuidancePolicy.userMessage(category: .unknown, rawMessage: "404 Not Found"),
            LunaCopy.friendlyEngineErrorMessage("404 Not Found")
        )
    }
}
