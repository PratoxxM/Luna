import AetherBridge
import CoreGraphics
import CoreText
import Foundation
import Observation
import SwiftUI
import XCTest
@testable import Luna

final class PlayerSeriesAndQoSTests: XCTestCase {
    // MARK: - PGS Bitmap Lifting, OCR Cue Placement & Quick-Panel / NerdHUD Geometry

    @MainActor
    func testChapterAdapterPGSBitmapLiftingOCRCuePlacementAndQuickPanelAnchoring() {
        let aetherMerged = PlaybackChapter.merge(
            probeChapters: [TvProbeChapter(index: 0, idString: "c1", title: "Prolog", startSeconds: 0, endSeconds: 90, kind: "intro")],
            engineChapters: [],
            mediaDuration: 1800
        )
        XCTAssertEqual(aetherMerged.map(\.kind), [.intro])

        let screen = CGSize(width: 1920, height: 1080)
        let baseBottomPGS = CGRect(x: 560, y: 900, width: 800, height: 96)

        let liftedForSkip = SubtitleOverlayView.adjustedBitmapRect(
            baseRect: baseBottomPGS, containerSize: screen,
            placement: SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: false, isQuickPanelOpen: false, isNerdHUDVisible: false, activeSeriesOverlay: .skipPrompt),
            isNerdHUDVisible: false
        )
        XCTAssertLessThanOrEqual(liftedForSkip.maxY, 1080 - 168 + 0.01)

        let relocatedPGS = SubtitleOverlayView.adjustedBitmapRect(
            baseRect: baseBottomPGS, containerSize: screen,
            placement: SubtitleOverlayLayout.verticalPlacement(isBottomBarVisible: true, isQuickPanelOpen: true, isNerdHUDVisible: true, activeSeriesOverlay: .none),
            isNerdHUDVisible: true
        )
        XCTAssertFalse(relocatedPGS.intersects(SubtitleOverlayLayout.nerdHUDProtectedRect))
        XCTAssertGreaterThanOrEqual(relocatedPGS.minX, 856 - 0.01)

        XCTAssertEqual(PlayerQuickPanelView.resolvedPanelLeadingX(triggerFrame: CGRect(x: 412, y: 950, width: 130, height: 48), tab: .source), 412, accuracy: 0.1)
        XCTAssertEqual(PlayerQuickPanelView.resolvedPanelLeadingX(triggerFrame: CGRect(x: 1700, y: 950, width: 120, height: 48), tab: .source), 910, accuracy: 0.1)
        XCTAssertEqual(SeriesSkipPromptPillView.resolvedLabel(for: .postCredits), LunaCopy.skipToPostCreditsTitle)
        XCTAssertEqual(NerdHUDView.formatSessionCacheBytes(2_621_440), "+2,5 MiB RAM-buffer")

        let bottomPos = CGRect(x: 0.25, y: 0.80, width: 0.50, height: 0.10)
        let goodLines = [SubtitleOCRLineInput(text: "Dialoglinje", confidence: 0.90)]
        XCTAssertEqual(
            SubtitleOverlayView.resolveOCRCuePlacement(recognizedText: "Dialoglinje", lines: goodLines, imagePosition: bottomPos, placementAlignment: nil, relocateToTop: true, useBitmapOCR: true)?.slot,
            .top
        )
        XCTAssertNil(SubtitleOverlayView.resolveOCRCuePlacement(
            recognizedText: "SKILT", lines: [SubtitleOCRLineInput(text: "SKILT", confidence: 0.98)],
            imagePosition: CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.08), placementAlignment: nil, relocateToTop: false, useBitmapOCR: true
        ))
    }

    // MARK: - Series EOF Flow, SystemCaptionRequest & Post-Dismissal Prewarm Guard

    @MainActor
    func testIsolatedStartupObservationSystemCaptionRequestDismissedNextEOFAndHeartbeatGuard() async throws {
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.series")
        let engineScope = try SharedTestEngineScope()
        defer {
            engineScope.stop()
            scope.cleanup()
        }
        let engine = engineScope.engine
        let comfort = ComfortPreferences(defaults: scope.defaults, memoryTier: .standard)
        let vm = PlayerViewModel(engine: engine, comfort: comfort)
        vm.isResolving = false

        let vmChanges = TestLockedBox(0)
        withObservationTracking {
            _ = vm.isResolving
            _ = vm.playbackPhase
            _ = vm.hasFirstFrameReadyForDisplay
        } onChange: {
            vmChanges.withLock { $0 += 1 }
        }
        vm.resolvePercent = 45
        vm.resolveStageLabel = "Buffrer segmenter…"
        vm.startupState.updateEngineStartupFraction(0.642)
        XCTAssertEqual(vmChanges.withLock { $0 }, 0)
        XCTAssertEqual(vm.startupState.engineStartupPercentBucket, 64)

        // Kveldslys lock & tvOS SystemCaptionRequest track activation
        vm.activeSubtitleTrackIndex = nil
        XCTAssertEqual(vm.kveldslysLockReason, "Slå på undertekst for å justere")
        vm.previewSubtitleOptions = [
            PlayerDrawerSubtitleOption(id: 10, languageCode: "en", rawTitle: "English", isForced: false, isHearingImpaired: false, isExternal: false),
            PlayerDrawerSubtitleOption(id: 11, languageCode: "nob", rawTitle: "Norsk", isForced: false, isHearingImpaired: false, isExternal: true),
        ]
        vm.subtitleTracks = [
            TrackInfo(id: 10, name: "English", codec: "subrip", language: "eng", channels: 0, isDefault: false),
            TrackInfo(id: 11, name: "Norsk", codec: "subrip", language: "nob", channels: 0, isDefault: false, isExternal: true),
        ]
        engine.systemCaptionRequest.send(SystemCaptionRequest(language: "nb-NO"))
        XCTAssertEqual(vm.activeSubtitleTrackIndex, 11)
        XCTAssertNil(vm.kveldslysLockReason)
        vm.teardownAndStop()

        // Explicitly dismissed Neste episode closes cleanly at EOF instead of forcing advance
        let nextEp = TvNextEpisodeSummary(itemId: "episode:tmdb:95396:s2:e4", season: 2, episode: 4, title: "Woe's Hollow")
        let eofSession = PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-series-eof-1", nextEpisode: nextEp)
        let eofVM = PlayerViewModel(engine: engine, comfort: comfort, transport: FakePlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 3179), bindOnInit: false)
        eofVM.activeSession = eofSession
        eofVM.isResolving = false
        let osd = PlayerOSDCoordinator()
        osd.dismissedNextForSessionID = "sess-series-eof-1"
        var closeCount = 0
        osd.handlePlaybackPhaseChange(oldPhase: .playing, newPhase: .ended, viewModel: eofVM, autoPlayNextEpisode: true, onClosePlayer: { closeCount += 1 })
        XCTAssertEqual(closeCount, 1)

        // In-flight heartbeat completing after prepareForDismissal() / teardownAndStop() skips nextEpisodePrewarm & secret registration
        let hbPrewarmBody = #"{"ok":true,"sessionId":"sess-hb-1","state":"playing","vfsTelemetry":{"streamSource":"vfs"},"nextEpisodePrewarm":{"itemId":"episode:tmdb:95396:s2:e4","sessionId":"sess-next-prewarm-1","streamToken":"next_ep_secret_token_987654","streamUrl":"/api/tv/v2/stream/sess-next-prewarm-1/next_ep_secret_token_987654/video.mkv","canClientPrewarmBytes":true,"nextEpisode":{"itemId":"episode:tmdb:95396:s2:e4","season":2,"episode":4,"title":"Woe's Hollow"}},"pendingCommand":{"type":"subtitles_on","language":"nob"}}"#
        for triggerTeardown in [false, true] {
            let host = "hb-guard-\(UUID().uuidString.lowercased()).local"
            defer { MockURLProtocol.unregister(host: host) }
            let gate = TestStepGate()
            let log = TestLockedBox<[String]>([])
            MockURLProtocol.registerAsync(host: host) { request in
                let url = try XCTUnwrap(request.url)
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let bodyStr = String(data: MockURLProtocol.bodyData(for: request), encoding: .utf8) ?? ""
                if url.path == "/api/tv/v2/playback/heartbeat", bodyStr.contains("\"state\":\"playing\"") {
                    await gate.wait(label: "hb", log: log)
                    return (resp, Data(hbPrewarmBody.utf8))
                }
                return (resp, Data(#"{"ok":true,"state":"stopped"}"#.utf8))
            }

            let guardVM = PlayerViewModel(
                engine: engine, comfort: comfort,
                transport: MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 120),
                audioActivator: MockNativeAudioActivator { _ in },
                preferenceStore: PlaybackPreferenceStore(suiteName: scope.suiteName), bindOnInit: false
            )
            guardVM.activeClient = try MockURLProtocol.makeClient(host: host)
            guardVM.activeSession = PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-hb-1")
            guardVM.isResolving = false
            guardVM.qosReporter.playbackPhase = .playing

            let hbTask = Task { @MainActor in await guardVM.qosReporter.sendHeartbeatOnce(overrideState: nil) }
            await gate.waitUntilStarted()
            if triggerTeardown { guardVM.sessionController.teardownAndStop() } else { guardVM.sessionController.prepareForDismissal() }
            await gate.finish()
            await hbTask.value

            XCTAssertNil(guardVM.qosReporter.prewarmedNextEpisodeStreamToken)
            XCTAssertNil(guardVM.qosReporter.prewarmedNextEpisodeSessionId)
            XCTAssertNil(guardVM.qosReporter.remoteCommandToastMessage)
        }
    }

    // MARK: - QoS Stall Heartbeats, Memory Pressure, Binaural Observation & Embedded Fonts

    @MainActor
    func testQoSStallHeartbeatsMemoryPressureBinauralObservationAndEmbeddedFonts() async throws {
        let host = "qos-stall-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.v1.test.qos")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            ArtworkPipeline.shared.exitPlaybackMemoryMode()
            engineScope.stop()
            scope.cleanup()
        }

        let nextSummary = TvNextEpisodeSummary(itemId: "episode:tmdb:95396:s2:e4", season: 2, episode: 4, title: "Woe's Hollow")
        let switchedObj = try PlayerTestFixtures.sessionJSONObject(
            PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-switched-2", nextEpisode: nextSummary)
        )
        let nextObj = try PlayerTestFixtures.sessionJSONObject(
            PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-next-3", itemId: "episode:tmdb:95396:s2:e4", episode: 4)
        )

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/switch") { return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switchedObj])) }
            if url.path == "/api/tv/v2/playback/resolve" { return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "resolveId": "res-next", "playbackSession": nextObj])) }
            return (resp, Data(#"{"ok":true,"state":"playing"}"#.utf8))
        }

        let comfort = ComfortPreferences(defaults: scope.defaults)
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .loopback, currentTime: 120)
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: scope.suiteName), bindOnInit: false
        )
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-initial-1", nextEpisode: nextSummary)
        vm.isResolving = false
        vm.qosReporter.playbackPhase = .playing
        vm.qosReporter.lastObservedPhase = .playing

        // Stall counter increments on playback stalls, ignores restore transitions, and resets on switch / next episode
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .rebuffering, isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .rebuffering, to: .stalled(reconnecting: true), isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .stalled(reconnecting: true), to: .playing, isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .stalled(reconnecting: false), isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .stalled(reconnecting: false), to: .playing, isTransientTransition: false)
        XCTAssertEqual(vm.qosReporter.currentStallCount, 2)

        await vm.qosReporter.sendHeartbeatOnce(overrideState: "playing")
        let hbRequests = MockURLProtocol.requests(forHost: host).filter { $0.url?.path == "/api/tv/v2/playback/heartbeat" }
        let lastHBBody = try XCTUnwrap(hbRequests.last.map { String(decoding: MockURLProtocol.bodyData(for: $0), as: UTF8.self) })
        XCTAssertTrue(lastHBBody.contains("\"stallCount\":2"))

        vm.isRestoringFromBackground = true
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .rebuffering, isTransientTransition: true)
        vm.isRestoringFromBackground = false
        XCTAssertEqual(vm.qosReporter.currentStallCount, 2)

        await vm.switchSource(to: "cand-2")
        XCTAssertEqual(vm.qosReporter.currentStallCount, 0)

        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .stalled(reconnecting: false), isTransientTransition: false)
        vm.playNextEpisode(nextSummary)
        await vm.sessionController.resolveTask?.value
        XCTAssertEqual(vm.qosReporter.currentStallCount, 0)

        await vm.handleHeartbeatPendingCommand(TvPendingCommand(type: "subtitles_on", language: "no"), client: nil, currentPosition: 120)
        XCTAssertEqual(vm.remoteCommandToastMessage, "Ingen undertekster tilgjengelig")

        // ArtworkPipeline playback memory pressure purge & exit restoration
        let sampleCG = try XCTUnwrap(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 18))
        let artURL = try XCTUnwrap(URL(string: "http://lunacore.local:8090/api/tv/v2/artwork/mem-test"))
        ArtworkPipeline.shared.insertMemoryCachedImage(sampleCG, url: artURL, maxPixelSize: 480)
        ArtworkPipeline.shared.enterPlaybackMemoryMode(heavyStream: true)
        XCTAssertTrue(ArtworkPipeline.shared.isPlaybackActive)
        XCTAssertNil(ArtworkPipeline.shared.anyMemoryCachedImage(for: artURL, preferredMaxPixelSize: 480))
        ArtworkPipeline.shared.exitPlaybackMemoryMode()
        XCTAssertFalse(ArtworkPipeline.shared.isPlaybackActive)

        // Binaural @Observable route tracking + EmbeddedFontRegistry CoreText lifecycle
        let observedBinaural = TestLockedBox(false)
        withObservationTracking { _ = vm.trackController.isBinauralAudioRouteActive } onChange: { observedBinaural.withLock { $0 = true } }
        vm.handleAudioRouteChange(isWirelessOverride: true, isBinauralOverride: true)
        XCTAssertTrue(observedBinaural.withLock { $0 })
        XCTAssertEqual(vm.trackController.binauralStatus, .active)
        vm.trackController.setSpeakerLayoutLive(.stereo)
        XCTAssertEqual(vm.trackController.binauralStatus, .suppressedByStereo)
        vm.sessionController.teardownAndStop()

        let familyName = "LunaTestFont\(UUID().uuidString.filter(\.isHexDigit).prefix(8))"
        let tempDir = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Luna/EmbeddedFonts/ttf-\(UUID().uuidString.lowercased())", isDirectory: true)
        )
        let registry = EmbeddedFontRegistry(cacheDirectoryURL: tempDir)
        defer { registry.clearAndUnregisterAll() }

        registry.ingestRawAttachments([EmbeddedFontRegistry.RawFontAttachment(filename: "corrupt.ttf", mimeType: "font/ttf", data: Data("invalid".utf8))])
        await registry.activeIngestTask?.value
        XCTAssertEqual(registry.registeredFontCount, 0)

        registry.ingest(attachments: [FontAttachment(filename: "LunaTestFont.ttf", mimeType: "font/ttf", data: Self.makeMinimalTrueTypeFontData(familyName: familyName))])
        await registry.activeIngestTask?.value
        XCTAssertEqual(registry.registeredFontCount, 1)
        let descriptor = try XCTUnwrap(registry.descriptor(forFontName: "@\(familyName)"))
        XCTAssertEqual(CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String, familyName)
        XCTAssertEqual(CTFontGetSize(LunaTheme.Font.subtitleCueCTFont(descriptor: descriptor, size: 14, isBold: false, isItalic: false)), 22.0)

        registry.clearAndUnregisterAll()
        XCTAssertEqual(registry.registeredFontCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
    }

    // MARK: - Minimal Valid SFNT TrueType Generator

    private static func appendBE16(_ data: inout Data, _ value: UInt16) {
        var big = value.bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
    private static func appendBE16S(_ data: inout Data, _ value: Int16) { appendBE16(&data, UInt16(bitPattern: value)) }
    private static func appendBE32(_ data: inout Data, _ value: UInt32) {
        var big = value.bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
    private static func appendBE64S(_ data: inout Data, _ value: Int64) {
        var big = UInt64(bitPattern: value).bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    private static func sfntChecksum(_ data: Data) -> UInt32 {
        var padded = data
        let rem = padded.count % 4
        if rem != 0 { padded.append(contentsOf: repeatElement(UInt8(0), count: 4 - rem)) }
        var sum: UInt32 = 0, idx = padded.startIndex
        while idx < padded.endIndex {
            let word = (UInt32(padded[idx]) << 24) | (UInt32(padded[idx + 1]) << 16) | (UInt32(padded[idx + 2]) << 8) | UInt32(padded[idx + 3])
            sum = sum &+ word; idx += 4
        }
        return sum
    }

    private static func makeMinimalTrueTypeFontData(familyName: String) -> Data {
        var head = Data()
        appendBE32(&head, 0x00010000); appendBE32(&head, 0x00010000); appendBE32(&head, 0); appendBE32(&head, 0x5F0F3CF5)
        appendBE16(&head, 0x0003); appendBE16(&head, 1000); appendBE64S(&head, 0); appendBE64S(&head, 0)
        appendBE16S(&head, 0); appendBE16S(&head, 0); appendBE16S(&head, 500); appendBE16S(&head, 700)
        appendBE16(&head, 0); appendBE16(&head, 8); appendBE16S(&head, 2); appendBE16S(&head, 0); appendBE16S(&head, 0)

        var hhea = Data()
        appendBE32(&hhea, 0x00010000); appendBE16S(&hhea, 800); appendBE16S(&hhea, -200); appendBE16S(&hhea, 0)
        appendBE16(&hhea, 600); appendBE16S(&hhea, 0); appendBE16S(&hhea, 0); appendBE16S(&hhea, 500)
        appendBE16S(&hhea, 1); appendBE16S(&hhea, 0); appendBE16S(&hhea, 0)
        for _ in 0..<5 { appendBE16S(&hhea, 0) }
        appendBE16(&hhea, 2)

        var maxp = Data()
        appendBE32(&maxp, 0x00010000); appendBE16(&maxp, 2); appendBE16(&maxp, 4); appendBE16(&maxp, 1)
        for _ in 0..<3 { appendBE16(&maxp, 0) }
        appendBE16(&maxp, 2)
        for _ in 0..<7 { appendBE16(&maxp, 0) }

        var os2 = Data()
        appendBE16(&os2, 4); appendBE16S(&os2, 500); appendBE16(&os2, 400); appendBE16(&os2, 5); appendBE16(&os2, 0)
        appendBE16S(&os2, 650); appendBE16S(&os2, 700); appendBE16S(&os2, 0); appendBE16S(&os2, 140)
        appendBE16S(&os2, 650); appendBE16S(&os2, 700); appendBE16S(&os2, 0); appendBE16S(&os2, 480)
        appendBE16S(&os2, 50); appendBE16S(&os2, 260); appendBE16S(&os2, 0)
        os2.append(contentsOf: [2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
        appendBE32(&os2, 1); appendBE32(&os2, 0); appendBE32(&os2, 0); appendBE32(&os2, 0)
        os2.append(contentsOf: Array("LUNA".utf8))
        appendBE16(&os2, 0x0040); appendBE16(&os2, 0x0041); appendBE16(&os2, 0x0041)
        appendBE16S(&os2, 800); appendBE16S(&os2, -200); appendBE16S(&os2, 0)
        appendBE16(&os2, 800); appendBE16(&os2, 200); appendBE32(&os2, 1); appendBE32(&os2, 0)
        appendBE16S(&os2, 500); appendBE16S(&os2, 700); appendBE16(&os2, 0); appendBE16(&os2, 0x0020); appendBE16(&os2, 0)

        var hmtx = Data()
        appendBE16(&hmtx, 600); appendBE16S(&hmtx, 0); appendBE16(&hmtx, 600); appendBE16S(&hmtx, 0)

        var fmt4 = Data()
        appendBE16(&fmt4, 4); appendBE16(&fmt4, 32); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 4); appendBE16(&fmt4, 4); appendBE16(&fmt4, 1); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 0x0041); appendBE16(&fmt4, 0xFFFF); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 0x0041); appendBE16(&fmt4, 0xFFFF)
        appendBE16S(&fmt4, -64); appendBE16S(&fmt4, 1); appendBE16(&fmt4, 0); appendBE16(&fmt4, 0)

        var cmap = Data()
        appendBE16(&cmap, 0); appendBE16(&cmap, 1); appendBE16(&cmap, 3); appendBE16(&cmap, 1); appendBE32(&cmap, 12)
        cmap.append(fmt4)

        var glyf = Data()
        appendBE16S(&glyf, 1); appendBE16S(&glyf, 0); appendBE16S(&glyf, 0); appendBE16S(&glyf, 500); appendBE16S(&glyf, 700)
        appendBE16(&glyf, 3); appendBE16(&glyf, 0)
        glyf.append(contentsOf: [0x01, 0x01, 0x01, 0x01])
        appendBE16S(&glyf, 0); appendBE16S(&glyf, 0); appendBE16S(&glyf, 500); appendBE16S(&glyf, 0)
        appendBE16S(&glyf, 0); appendBE16S(&glyf, 700); appendBE16S(&glyf, 0); appendBE16S(&glyf, -700)

        var loca = Data()
        appendBE16(&loca, 0); appendBE16(&loca, 0); appendBE16(&loca, UInt16(glyf.count / 2))

        let nameEntries: [(UInt16, String)] = [(1, familyName), (2, "Regular"), (3, "\(familyName)-Regular"), (4, familyName), (6, familyName)]
        var nameStrings = Data(), nameRecords = Data()
        for (nameID, value) in nameEntries {
            let encoded = value.data(using: .utf16BigEndian) ?? Data()
            appendBE16(&nameRecords, 3); appendBE16(&nameRecords, 1); appendBE16(&nameRecords, 0x0409)
            appendBE16(&nameRecords, nameID); appendBE16(&nameRecords, UInt16(encoded.count)); appendBE16(&nameRecords, UInt16(nameStrings.count))
            nameStrings.append(encoded)
        }
        var nameTable = Data()
        appendBE16(&nameTable, 0); appendBE16(&nameTable, UInt16(nameEntries.count)); appendBE16(&nameTable, UInt16(6 + nameEntries.count * 12))
        nameTable.append(nameRecords); nameTable.append(nameStrings)

        var post = Data()
        appendBE32(&post, 0x00030000); appendBE32(&post, 0); appendBE16S(&post, -100); appendBE16S(&post, 50)
        for _ in 0..<5 { appendBE32(&post, 0) }

        let tables: [(String, Data)] = [
            ("OS/2", os2), ("cmap", cmap), ("glyf", glyf), ("head", head), ("hhea", hhea),
            ("hmtx", hmtx), ("loca", loca), ("maxp", maxp), ("name", nameTable), ("post", post),
        ]
        var font = Data()
        appendBE32(&font, 0x00010000); appendBE16(&font, UInt16(tables.count)); appendBE16(&font, 128); appendBE16(&font, 3); appendBE16(&font, 32)
        var offset = UInt32(12 + tables.count * 16), directory = Data(), body = Data(), headOffset = 0
        for (tag, tableData) in tables {
            if tag == "head" { headOffset = Int(offset) }
            directory.append(contentsOf: Array(tag.utf8))
            appendBE32(&directory, sfntChecksum(tableData))
            appendBE32(&directory, offset)
            appendBE32(&directory, UInt32(tableData.count))
            body.append(tableData)
            let pad = (4 - (tableData.count % 4)) % 4
            if pad > 0 { body.append(contentsOf: repeatElement(UInt8(0), count: pad)) }
            offset += UInt32(tableData.count + pad)
        }
        font.append(directory); font.append(body)
        let adjustment = UInt32(0xB1B0AFBA) &- sfntChecksum(font)
        var bigAdj = adjustment.bigEndian
        withUnsafeBytes(of: &bigAdj) { raw in font.replaceSubrange((headOffset + 8)..<(headOffset + 12), with: raw) }
        return font
    }
}
