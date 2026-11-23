import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PlayerQuickPanelAndSwitchTests: XCTestCase {
    private static func makePlaybackSessionJSON(
        sessionId: String,
        candidateId: String,
        headline: String,
        startPositionSeconds: Double? = nil
    ) -> Data {
        let startField = startPositionSeconds.map { ", \"startPositionSeconds\": \($0)" } ?? ""
        let raw = """
        {
          "sessionId": "\(sessionId)",
          "streamToken": "tok-switch-secret-998877",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:693134",
            "mediaType": "movie",
            "ids": { "tmdb": 693134 },
            "title": "Dune: Part Two",
            "runtimeSeconds": 9960
          },
          "selectedCandidate": {
            "candidateId": "\(candidateId)",
            "displayHeadline": "\(headline)",
            "releaseTitle": "Dune.Part.Two.2160p",
            "source": "nvme",
            "tier": "nvme",
            "resolution": "2160p",
            "videoCodec": "hevc",
            "audioCodec": "TrueHD Atmos"
          },
          "stream": {
            "url": "/api/tv/v1/stream/\(sessionId)/tok-switch-secret-998877/video.mkv"\(startField)
          },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless",
            "objectAudioRendering": { "mode": "render", "layout": "7.1.4" }
          }
        }
        """
        return Data(raw.utf8)
    }

    @MainActor
    func testSwitchSourceAgainstFakeTransportPreservesTimecodeTrackLanguageSubtitleDelayAndAudioEnhancement() async throws {
        let host = "switch-etappe3-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let switchBodies = TestLockedBox<[Data]>([])
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/switch") {
                switchBodies.withLock { $0.append(MockURLProtocol.bodyData(for: request)) }
                let switchedData = Self.makePlaybackSessionJSON(
                    sessionId: "sess-etappe3-1",
                    candidateId: "cand-remux-2",
                    headline: "4K HDR10+ TrueHD Atmos"
                )
                let wrapper = try JSONSerialization.jsonObject(with: switchedData)
                let payload = try JSONSerialization.data(withJSONObject: [
                    "ok": true,
                    "playbackSession": wrapper,
                ])
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (resp, payload)
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true,"sessionId":"sess-etappe3-1","state":"playing","vfsLockActive":false}"#.utf8))
        }

        let suite = "luna.test.switch.etappe3.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(
            state: .playing,
            playbackPhase: .playing,
            videoRoute: .software,
            currentTime: 1842.5
        )
        transport.audioTrackDescriptors = [
            PlaybackAudioTrackDescriptor(id: 0, name: "English 5.1", codec: "eac3", language: "eng", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese Master", codec: "dts-hd", language: "jpn", channels: 6),
        ]
        transport.activeAudioTrackIndex = 1
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
        ]
        transport.activeSubtitleTrackIndex = 11

        let client = try MockURLProtocol.makeClient(host: host)
        let initialSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makePlaybackSessionJSON(
                sessionId: "sess-etappe3-1",
                candidateId: "cand-webdl-1",
                headline: "4K WEB-DL"
            )
        )

        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = initialSession
        vm.isResolving = false
        vm.selectAudioTrack(1)
        vm.selectSubtitleManually(11)
        vm.setAudioEnhancement(.dialogueLift)
        vm.adjustSubtitleDelay(byMs: 150)

        XCTAssertEqual(comfort.audioEnhancement, .dialogueLift)
        XCTAssertEqual(vm.subtitleDelayMs, 150)
        XCTAssertEqual(vm.subtitleDelaySeconds, 0.15, accuracy: 0.0001)

        // When MKV #2 loads, audio and subtitle track indices are completely permuted
        transport.onLoadStream = { _, _, _ in
            transport.audioTrackDescriptors = [
                PlaybackAudioTrackDescriptor(id: 4, name: "English TrueHD Atmos", codec: "truehd", language: "eng", channels: 8, isAtmos: true),
                PlaybackAudioTrackDescriptor(id: 5, name: "Japanese FLAC", codec: "flac", language: "ja-JP", channels: 6),
            ]
            transport.activeAudioTrackIndex = 4
            transport.subtitleTrackDescriptors = [
                SmartTrackDescriptor(id: 30, name: "English", codec: "srt", language: "eng"),
                SmartTrackDescriptor(id: 31, name: "Norsk Full", codec: "srt", language: "nor"),
                SmartTrackDescriptor(id: 32, name: "Norsk Tvungen", codec: "srt", language: "nob", isForced: true),
            ]
            transport.activeSubtitleTrackIndex = 30
        }

        await vm.switchSource(to: "cand-remux-2")

        // Verify switch POST body carried exact currentPos
        let recordedSwitchBody = try XCTUnwrap(switchBodies.withLock { $0.first })
        let switchJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: recordedSwitchBody) as? [String: Any])
        XCTAssertEqual(switchJSON["candidateId"] as? String, "cand-remux-2")
        XCTAssertEqual(try XCTUnwrap(switchJSON["positionSeconds"] as? Double), 1842.5, accuracy: 0.01)

        // Verify seamless replacement, timecode, persisted audioEnhancement, re-mapped tracks & ms subtitle delay
        XCTAssertTrue(transport.events.contains("prepareForItemReplacement"))
        XCTAssertEqual(try XCTUnwrap(transport.lastLoadedStartPosition), 1842.5, accuracy: 0.01)
        XCTAssertEqual(vm.audioEnhancement, .dialogueLift)
        XCTAssertEqual(try XCTUnwrap(transport.lastLoadedOptions?.audioShaping.dialogueGainDB), 4.0, accuracy: 0.01)
        XCTAssertEqual(vm.activeAudioTrackIndex, 5)
        XCTAssertEqual(transport.activeAudioTrackIndex, 5)
        XCTAssertEqual(vm.activeSubtitleTrackIndex, 32)
        XCTAssertEqual(transport.activeSubtitleTrackIndex, 32)
        XCTAssertEqual(vm.subtitleDelayMs, 150)
        XCTAssertEqual(vm.subtitleDelaySeconds, 0.15, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(transport.lastSubtitleDelaySeconds), 0.15, accuracy: 0.0001)

        // Verify explicit "Av" survives a subsequent edition switch
        vm.clearSubtitleManually()
        await vm.switchSource(to: "cand-webdl-1")
        XCTAssertNil(vm.activeSubtitleTrackIndex)
        XCTAssertNil(transport.activeSubtitleTrackIndex)
    }

    @MainActor
    func testAudioEnhancementAndSpeakerLayoutPersistenceInComfortPreferences() throws {
        let suite = "luna.test.comfort.etappe3.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfortA = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(comfortA.audioEnhancement, .reference)
        XCTAssertEqual(comfortA.speakerLayoutOverride, .auto)

        comfortA.audioEnhancement = .nightMode
        comfortA.speakerLayoutOverride = .atmos512

        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.audioEnhancementModeKey), "night")
        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.speakerLayoutOverrideKey), "5.1.2")

        // Reload from SideloadSafeStorage UserDefaults into a brand-new ComfortPreferences & PlayerViewModel
        let comfortB = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(comfortB.audioEnhancement, .nightMode)
        XCTAssertEqual(comfortB.speakerLayoutOverride, .atmos512)
        XCTAssertEqual(comfortB.speakerLayoutOverride.headerSummary(forAutoLayout: "7.1.4"), "Høyttaleroppsett · 5.1.2")
        XCTAssertEqual(SpeakerLayoutOverrideMode.auto.headerSummary(forAutoLayout: "5.1.2"), "Høyttaleroppsett · Auto (5.1.2)")

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = FakePlayerTransport()
        let vm = PlayerViewModel(engine: engine, comfort: comfortB, transport: transport, bindOnInit: false)
        XCTAssertEqual(vm.audioEnhancement, .nightMode)

        let session = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makePlaybackSessionJSON(sessionId: "sess-spk", candidateId: "cand-1", headline: "4K")
        )
        let client = LunaCoreClient(
            baseURL: try XCTUnwrap(URL(string: "http://lunacore.local:8090")),
            deviceID: "dev-test",
            deviceToken: "tok-test",
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true
        )
        let opts512 = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfortB,
            audioEnhancement: vm.audioEnhancement,
            audioDelaySeconds: 0
        )
        XCTAssertEqual(opts512.objectAudioRendering, .render(.l512))
        XCTAssertEqual(opts512.audioShaping.compressor, .night)

        comfortB.speakerLayoutOverride = .atmos714
        let opts714 = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfortB,
            audioEnhancement: vm.audioEnhancement,
            audioDelaySeconds: 0
        )
        XCTAssertEqual(opts714.objectAudioRendering, .render(.l714))
    }

    @MainActor
    func testSubtitleVisibilityAcrossAllQuickPanelTabsAndDirectTabSwitchingToMenuFocus() throws {
        let suite = "luna.test.osd.etappe3.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: false)
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true
        vm.isAwaitingDisplaySwitch = false
        vm.playbackPhase = .playing

        // 1. SubtitleOverlayView remains visible across nil + all 5 quick-panel tabs when picture is ready
        let osd = PlayerOSDCoordinator()
        for panel in [nil] + PlayerQuickPanelTab.allCases.map(Optional.some) {
            osd.activeQuickPanel = panel
            XCTAssertTrue(
                PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                    hasFatalError: vm.fatalError != nil,
                    hasSuspendedFatalError: osd.suspendedFatalErrorForPanel != nil,
                    isPictureReadyForReveal: vm.isPictureReadyForReveal
                ),
                "SubtitleOverlayView must stay visible when activeQuickPanel == \(String(describing: panel))"
            )
        }

        // Suppressed during fatal error or emergency pre-reveal source recovery
        osd.suspendedFatalErrorForPanel = "Kunne ikke åpne strøm"
        XCTAssertFalse(
            PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                hasFatalError: false,
                hasSuspendedFatalError: osd.suspendedFatalErrorForPanel != nil,
                isPictureReadyForReveal: false
            )
        )
        osd.suspendedFatalErrorForPanel = nil

        // 2. Direct Left/Right tab switching updates activeQuickPanel & lastSelectedQuickTab,
        //    skips .chapters when chapters.isEmpty, and Menu returns focus to the last active tab pill!
        osd.openQuickPanel(.subtitles)
        XCTAssertEqual(osd.activeQuickPanel, .subtitles)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        XCTAssertEqual(osd.activeQuickPanel, .audio)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        XCTAssertEqual(osd.activeQuickPanel, .source)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        XCTAssertEqual(osd.activeQuickPanel, .picture)
        // Without chapters, pressing Right on .picture stays on .picture
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        XCTAssertEqual(osd.activeQuickPanel, .picture)
        XCTAssertEqual(osd.lastSelectedQuickTab, .picture)

        osd.handleExitCommand(viewModel: vm, onClosePlayer: { XCTFail("Should not exit player") })
        XCTAssertNil(osd.activeQuickPanel)
        XCTAssertTrue(osd.isQuickActionsModeActive)
        XCTAssertEqual(osd.requestedBottomBarAction, .panel(.picture))

        // 3. Kveldslys applies identically to SDR and HDR without locking on SDR
        for preset in HDRSubtitlePreset.allCases {
            XCTAssertEqual(preset.foregroundColor(isHDR: false), preset.foregroundColor(isHDR: true))
            XCTAssertEqual(preset.bitmapMultiplyColor(isHDR: false), preset.bitmapMultiplyColor(isHDR: true))
        }
    }
}
