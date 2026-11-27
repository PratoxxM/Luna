import AetherBridge
import CoreText
import Foundation
import Observation
import SwiftUI
import XCTest
@testable import Luna

final class PlayerQoSStallAndAudioTests: XCTestCase {
    private func makeSessionJSON(sessionId: String, itemId: String = "episode:tmdb:95396:s2:e3") -> String {
        #"""
        {
          "sessionId": "\#(sessionId)",
          "streamToken": "stream_secret_qos_stall_1234",
          "roomName": "Kino",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "\#(itemId)",
            "mediaType": "episode",
            "ids": { "tmdb": 95396 },
            "title": "Who Is Alive?",
            "seriesTitle": "Severance",
            "season": 2,
            "episode": 3,
            "runtimeSeconds": 3180
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K HDR10+",
            "releaseTitle": "Severance.S02E03.2160p",
            "source": "nvme",
            "tier": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/\#(sessionId)/stream_secret_qos_stall_1234/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          },
          "nextEpisode": {
            "itemId": "episode:tmdb:95396:s2:e4",
            "season": 2,
            "episode": 4,
            "title": "Woe's Hollow"
          }
        }
        """#
    }

    @MainActor
    func testQoSStallCounterLifecycleHeartbeatPayloadAndSwitchNextEpisodeResets() async throws {
        let host = "qos-stall-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.qos.stall.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let switchedJSON = makeSessionJSON(sessionId: "sess-switched-2")
        let nextJSON = makeSessionJSON(sessionId: "sess-next-3", itemId: "episode:tmdb:95396:s2:e4")
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.contains("/switch") {
                return (resp, Data(#"{"ok":true,"playbackSession":\#(switchedJSON)}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/resolve" {
                return (resp, Data(#"{"ok":true,"resolveId":"res-next","playbackSession":\#(nextJSON)}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/heartbeat" {
                return (resp, Data(#"{"ok":true,"state":"playing"}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let comfort = ComfortPreferences(defaults: defaults)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .loopback, currentTime: 120)
        let client = try MockURLProtocol.makeClient(host: host)
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(makeSessionJSON(sessionId: "sess-initial-1").utf8))

        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite),
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.qosReporter.playbackPhase = .playing
        vm.qosReporter.lastObservedPhase = .playing

        // 1. Mid-playback rebuffer -> stalled(false) -> stalled(true) counts as 1 stall; playing -> stalled counts as 2
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .rebuffering, isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .rebuffering, to: .stalled(reconnecting: false), isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .stalled(reconnecting: false), to: .stalled(reconnecting: true), isTransientTransition: false)
        XCTAssertEqual(vm.qosReporter.currentStallCount, 1)

        vm.qosReporter.recordPlaybackPhaseTransition(from: .stalled(reconnecting: true), to: .playing, isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .stalled(reconnecting: false), isTransientTransition: false)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .stalled(reconnecting: false), to: .playing, isTransientTransition: false)
        XCTAssertEqual(vm.qosReporter.currentStallCount, 2)

        // 2. Heartbeat sends stallCount even when lastTelemetrySnapshot == nil
        await vm.qosReporter.sendHeartbeatOnce(overrideState: "playing")
        let hbRequests = MockURLProtocol.requests(forHost: host).filter { $0.url?.path == "/api/tv/v2/playback/heartbeat" }
        let lastHBBody = try XCTUnwrap(hbRequests.last.map { String(decoding: MockURLProtocol.bodyData(for: $0), as: UTF8.self) })
        XCTAssertTrue(lastHBBody.contains("\"stallCount\":2"), "Expected stallCount:2 in \(lastHBBody)")

        // 3. Foreground restore preserves stallCount while suppressing restore-phase transients
        vm.isRestoringFromBackground = true
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .loading, isTransientTransition: true)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .loading, to: .rebuffering, isTransientTransition: true)
        vm.qosReporter.recordPlaybackPhaseTransition(from: .rebuffering, to: .playing, isTransientTransition: true)
        vm.isRestoringFromBackground = false
        XCTAssertEqual(vm.qosReporter.currentStallCount, 2)

        // 4. Failed switchSource during loadStream preserves ongoing session stallCount; successful switchSource resets it
        transport.onLoadStream = { _, _, _ in throw URLError(.timedOut) }
        await vm.switchSource(to: "cand-fail-load")
        transport.onLoadStream = nil
        XCTAssertEqual(vm.activeSession?.sessionId, "sess-initial-1")
        XCTAssertEqual(vm.qosReporter.currentStallCount, 2)

        await vm.switchSource(to: "cand-2")
        XCTAssertEqual(vm.activeSession?.sessionId, "sess-switched-2")
        XCTAssertEqual(vm.qosReporter.currentStallCount, 0)

        // Accumulate 1 stall on switched session, then advance to next episode -> resets to 0
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .stalled(reconnecting: false), isTransientTransition: false)
        XCTAssertEqual(vm.qosReporter.currentStallCount, 1)
        let nextEp = try XCTUnwrap(vm.activeSession?.nextEpisode)
        vm.playNextEpisode(nextEp)
        await vm.sessionController.resolveTask?.value
        XCTAssertEqual(vm.qosReporter.currentStallCount, 0)

        // 5. After teardown, stallCount remains readable while heartbeat sends stay guarded
        vm.qosReporter.recordPlaybackPhaseTransition(from: .playing, to: .stalled(reconnecting: false), isTransientTransition: false)
        let countBeforeTeardown = vm.qosReporter.currentStallCount
        XCTAssertEqual(countBeforeTeardown, 1)
        vm.sessionController.teardownAndStop()
        XCTAssertEqual(vm.qosReporter.currentStallCount, 1)
        let hbCountAfterTeardown = MockURLProtocol.requests(forHost: host).filter { $0.url?.path == "/api/tv/v2/playback/heartbeat" }.count
        await vm.qosReporter.sendHeartbeatOnce(overrideState: "playing")
        let hbCountPostGuard = MockURLProtocol.requests(forHost: host).filter { $0.url?.path == "/api/tv/v2/playback/heartbeat" }.count
        XCTAssertEqual(hbCountAfterTeardown, hbCountPostGuard)
    }

    @MainActor
    func testTrackControllerBinauralObservationAndNoticeAndFontRegistryLifecycle() async throws {
        let suite = "luna.v1.test.binaural.obs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: PlaybackPreferenceStore(suiteName: suite),
            bindOnInit: false
        )
        vm.isResolving = false
        vm.trackController.isBinauralAudioRouteActive = false
        XCTAssertEqual(vm.trackController.binauralStatus, .inactive)
        XCTAssertNil(vm.trackController.binauralAudioStatusNotice)

        let observedChange = TestLockedBox(false)
        withObservationTracking {
            _ = vm.trackController.isBinauralAudioRouteActive
        } onChange: {
            observedChange.withLock { $0 = true }
        }
        vm.handleAudioRouteChange(isWirelessOverride: true, isBinauralOverride: true)
        XCTAssertTrue(observedChange.withLock { $0 }, "isBinauralAudioRouteActive must remain @Observable")
        XCTAssertEqual(vm.trackController.binauralStatus, .active)
        XCTAssertEqual(vm.trackController.binauralAudioStatusNotice, "Hodetelefoner · Binaural romlyd aktiv")
        XCTAssertEqual(transport.lastAudioShaping?.binaural, true)

        vm.trackController.setSpeakerLayoutLive(.stereo)
        XCTAssertEqual(vm.trackController.binauralStatus, .suppressedByStereo)
        XCTAssertEqual(
            vm.trackController.binauralAudioStatusNotice,
            "Hodetelefoner · Binaural av (Stereo 2.0 valgt)"
        )
        XCTAssertEqual(transport.lastAudioShaping?.binaural, false)

        // EmbeddedFontRegistry ignores invalid blobs, tracks empty clears safely, and isolates cache dirs
        let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Luna/EmbeddedFonts/test-\(UUID().uuidString.lowercased())", isDirectory: true)
        let registry = EmbeddedFontRegistry(cacheDirectoryURL: tempDir)
        registry.ingestRawAttachments([
            EmbeddedFontRegistry.RawFontAttachment(
                filename: "corrupt.ttf",
                mimeType: "font/ttf",
                data: Data("not-a-valid-ttf".utf8)
            ),
        ])
        await registry.activeIngestTask?.value
        XCTAssertEqual(registry.registeredFontCount, 0)
        XCTAssertNil(registry.descriptor(forFontName: "@CorruptFont"))

        registry.clearAndUnregisterAll()
        XCTAssertEqual(registry.registeredFontCount, 0)
        if let tempDir {
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
        }
    }

    @MainActor
    func testEmbeddedFontRegistryValidTTFRegistrationLookupSubtitleFloorAndUnregister() async throws {
        let familySuffix = String(UUID().uuidString.filter(\.isHexDigit).prefix(8))
        let familyName = "LunaTestFont\(familySuffix)"
        let validTTFData = Self.makeMinimalTrueTypeFontData(familyName: familyName)
        XCTAssertGreaterThan(validTTFData.count, 500)

        let parsedDescriptors = CTFontManagerCreateFontDescriptorsFromData(validTTFData as CFData) as? [CTFontDescriptor]
        XCTAssertEqual(parsedDescriptors?.count, 1)

        let tempDir = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Luna/EmbeddedFonts/valid-ttf-\(UUID().uuidString.lowercased())", isDirectory: true)
        )
        let registry = EmbeddedFontRegistry(cacheDirectoryURL: tempDir)
        defer { registry.clearAndUnregisterAll() }

        let attachment = FontAttachment(
            filename: "LunaTestFont.ttf",
            mimeType: "font/ttf",
            data: validTTFData
        )
        registry.ingest(attachments: [attachment])
        await registry.activeIngestTask?.value

        XCTAssertEqual(registry.registeredFontCount, 1)
        let descriptor = try XCTUnwrap(registry.descriptor(forFontName: "@\(familyName)"))
        XCTAssertEqual(
            CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
            familyName
        )
        XCTAssertNotNil(registry.descriptor(forFontName: "  \"@@\(familyName)\" "))

        let ctFont = LunaTheme.Font.subtitleCueCTFont(
            descriptor: descriptor,
            size: 14,
            isBold: false,
            isItalic: false
        )
        XCTAssertGreaterThanOrEqual(CTFontGetSize(ctFont), 22.0)
        XCTAssertEqual(CTFontGetSize(ctFont), 22.0)
        XCTAssertEqual(CTFontCopyFamilyName(ctFont) as String, familyName)

        let swiftFont = LunaTheme.Font.subtitleCue(
            descriptor: descriptor,
            size: 14,
            isBold: false,
            isItalic: false
        )
        XCTAssertEqual(swiftFont, SwiftUI.Font(ctFont))
        XCTAssertEqual(
            swiftFont,
            LunaTheme.Font.subtitleCue(
                descriptor: descriptor,
                size: 22,
                isBold: false,
                isItalic: false
            )
        )

        registry.clearAndUnregisterAll()
        XCTAssertEqual(registry.registeredFontCount, 0)
        XCTAssertNil(registry.descriptor(forFontName: "@\(familyName)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
    }

    private static func appendBE16(_ data: inout Data, _ value: UInt16) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    private static func appendBE16S(_ data: inout Data, _ value: Int16) {
        appendBE16(&data, UInt16(bitPattern: value))
    }

    private static func appendBE32(_ data: inout Data, _ value: UInt32) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    private static func appendBE64S(_ data: inout Data, _ value: Int64) {
        var big = UInt64(bitPattern: value).bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    private static func sfntChecksum(_ data: Data) -> UInt32 {
        var padded = data
        let rem = padded.count % 4
        if rem != 0 {
            padded.append(contentsOf: repeatElement(UInt8(0), count: 4 - rem))
        }
        var sum: UInt32 = 0
        var idx = padded.startIndex
        while idx < padded.endIndex {
            let word = (UInt32(padded[idx]) << 24)
                | (UInt32(padded[idx + 1]) << 16)
                | (UInt32(padded[idx + 2]) << 8)
                | UInt32(padded[idx + 3])
            sum = sum &+ word
            idx += 4
        }
        return sum
    }

    private static func makeMinimalTrueTypeFontData(familyName: String) -> Data {
        var head = Data()
        appendBE32(&head, 0x00010000)
        appendBE32(&head, 0x00010000)
        appendBE32(&head, 0)
        appendBE32(&head, 0x5F0F3CF5)
        appendBE16(&head, 0x0003)
        appendBE16(&head, 1000)
        appendBE64S(&head, 0)
        appendBE64S(&head, 0)
        appendBE16S(&head, 0)
        appendBE16S(&head, 0)
        appendBE16S(&head, 500)
        appendBE16S(&head, 700)
        appendBE16(&head, 0)
        appendBE16(&head, 8)
        appendBE16S(&head, 2)
        appendBE16S(&head, 0)
        appendBE16S(&head, 0)

        var hhea = Data()
        appendBE32(&hhea, 0x00010000)
        appendBE16S(&hhea, 800)
        appendBE16S(&hhea, -200)
        appendBE16S(&hhea, 0)
        appendBE16(&hhea, 600)
        appendBE16S(&hhea, 0)
        appendBE16S(&hhea, 0)
        appendBE16S(&hhea, 500)
        appendBE16S(&hhea, 1)
        appendBE16S(&hhea, 0)
        appendBE16S(&hhea, 0)
        for _ in 0..<4 { appendBE16S(&hhea, 0) }
        appendBE16S(&hhea, 0)
        appendBE16(&hhea, 2)

        var maxp = Data()
        appendBE32(&maxp, 0x00010000)
        appendBE16(&maxp, 2)
        appendBE16(&maxp, 4)
        appendBE16(&maxp, 1)
        for _ in 0..<3 { appendBE16(&maxp, 0) }
        appendBE16(&maxp, 2)
        for _ in 0..<7 { appendBE16(&maxp, 0) }

        var os2 = Data()
        appendBE16(&os2, 4)
        appendBE16S(&os2, 500)
        appendBE16(&os2, 400)
        appendBE16(&os2, 5)
        appendBE16(&os2, 0)
        appendBE16S(&os2, 650); appendBE16S(&os2, 700); appendBE16S(&os2, 0); appendBE16S(&os2, 140)
        appendBE16S(&os2, 650); appendBE16S(&os2, 700); appendBE16S(&os2, 0); appendBE16S(&os2, 480)
        appendBE16S(&os2, 50); appendBE16S(&os2, 260); appendBE16S(&os2, 0)
        os2.append(contentsOf: [2, 0, 5, 3, 0, 0, 0, 0, 0, 0])
        appendBE32(&os2, 1); appendBE32(&os2, 0); appendBE32(&os2, 0); appendBE32(&os2, 0)
        os2.append(contentsOf: Array("LUNA".utf8))
        appendBE16(&os2, 0x0040); appendBE16(&os2, 0x0041); appendBE16(&os2, 0x0041)
        appendBE16S(&os2, 800); appendBE16S(&os2, -200); appendBE16S(&os2, 0)
        appendBE16(&os2, 800); appendBE16(&os2, 200)
        appendBE32(&os2, 1); appendBE32(&os2, 0)
        appendBE16S(&os2, 500); appendBE16S(&os2, 700)
        appendBE16(&os2, 0); appendBE16(&os2, 0x0020); appendBE16(&os2, 0)

        var hmtx = Data()
        appendBE16(&hmtx, 600); appendBE16S(&hmtx, 0)
        appendBE16(&hmtx, 600); appendBE16S(&hmtx, 0)

        var fmt4 = Data()
        appendBE16(&fmt4, 4); appendBE16(&fmt4, 32); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 4); appendBE16(&fmt4, 4); appendBE16(&fmt4, 1); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 0x0041); appendBE16(&fmt4, 0xFFFF); appendBE16(&fmt4, 0)
        appendBE16(&fmt4, 0x0041); appendBE16(&fmt4, 0xFFFF)
        appendBE16S(&fmt4, -64); appendBE16S(&fmt4, 1)
        appendBE16(&fmt4, 0); appendBE16(&fmt4, 0)

        var cmap = Data()
        appendBE16(&cmap, 0); appendBE16(&cmap, 1)
        appendBE16(&cmap, 3); appendBE16(&cmap, 1); appendBE32(&cmap, 12)
        cmap.append(fmt4)

        var glyf = Data()
        appendBE16S(&glyf, 1); appendBE16S(&glyf, 0); appendBE16S(&glyf, 0); appendBE16S(&glyf, 500); appendBE16S(&glyf, 700)
        appendBE16(&glyf, 3); appendBE16(&glyf, 0)
        glyf.append(contentsOf: [0x01, 0x01, 0x01, 0x01])
        appendBE16S(&glyf, 0); appendBE16S(&glyf, 0); appendBE16S(&glyf, 500); appendBE16S(&glyf, 0)
        appendBE16S(&glyf, 0); appendBE16S(&glyf, 700); appendBE16S(&glyf, 0); appendBE16S(&glyf, -700)

        var loca = Data()
        appendBE16(&loca, 0); appendBE16(&loca, 0); appendBE16(&loca, UInt16(glyf.count / 2))

        let nameEntries: [(UInt16, String)] = [
            (1, familyName),
            (2, "Regular"),
            (3, "\(familyName)-Regular"),
            (4, familyName),
            (6, familyName),
        ]
        var nameStrings = Data()
        var nameRecords = Data()
        for (nameID, value) in nameEntries {
            let encoded = value.data(using: .utf16BigEndian) ?? Data()
            appendBE16(&nameRecords, 3)
            appendBE16(&nameRecords, 1)
            appendBE16(&nameRecords, 0x0409)
            appendBE16(&nameRecords, nameID)
            appendBE16(&nameRecords, UInt16(encoded.count))
            appendBE16(&nameRecords, UInt16(nameStrings.count))
            nameStrings.append(encoded)
        }
        var nameTable = Data()
        appendBE16(&nameTable, 0)
        appendBE16(&nameTable, UInt16(nameEntries.count))
        appendBE16(&nameTable, UInt16(6 + nameEntries.count * 12))
        nameTable.append(nameRecords)
        nameTable.append(nameStrings)

        var post = Data()
        appendBE32(&post, 0x00030000); appendBE32(&post, 0)
        appendBE16S(&post, -100); appendBE16S(&post, 50)
        for _ in 0..<5 { appendBE32(&post, 0) }

        let tables: [(String, Data)] = [
            ("OS/2", os2),
            ("cmap", cmap),
            ("glyf", glyf),
            ("head", head),
            ("hhea", hhea),
            ("hmtx", hmtx),
            ("loca", loca),
            ("maxp", maxp),
            ("name", nameTable),
            ("post", post),
        ]

        var font = Data()
        appendBE32(&font, 0x00010000)
        appendBE16(&font, UInt16(tables.count))
        appendBE16(&font, 128)
        appendBE16(&font, 3)
        appendBE16(&font, 32)

        var offset = UInt32(12 + tables.count * 16)
        var directory = Data()
        var body = Data()
        var headOffset = 0
        for (tag, tableData) in tables {
            if tag == "head" {
                headOffset = Int(offset)
            }
            directory.append(contentsOf: Array(tag.utf8))
            appendBE32(&directory, sfntChecksum(tableData))
            appendBE32(&directory, offset)
            appendBE32(&directory, UInt32(tableData.count))
            body.append(tableData)
            let pad = (4 - (tableData.count % 4)) % 4
            if pad > 0 {
                body.append(contentsOf: repeatElement(UInt8(0), count: pad))
            }
            offset += UInt32(tableData.count + pad)
        }
        font.append(directory)
        font.append(body)

        let adjustment = UInt32(0xB1B0AFBA) &- sfntChecksum(font)
        var bigAdj = adjustment.bigEndian
        withUnsafeBytes(of: &bigAdj) { raw in
            font.replaceSubrange((headOffset + 8)..<(headOffset + 12), with: raw)
        }
        return font
    }
}
