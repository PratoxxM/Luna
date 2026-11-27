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
            "url": "/api/tv/v2/stream/\(sessionId)/tok-switch-secret-998877/video.mkv"\(startField)
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

        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.audioEnhancementModeKey), "nightMode")
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

    @MainActor
    func testOriginalLanguageNorwegianToggleSofaSubtitlesAutoAlignDelayMemoryAndHDR10BaseLayer() async throws {
        let host = "m3-features-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.v1.test.m3features.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let autoAlignBodies = TestLockedBox<[Data]>([])
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/subtitles/search-and-attach") {
                let body = #"""
                {"ok":true,"sessionId":"sess-m3-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-m3-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk (SubDL)","isDefault":true},"externalSubtitles":[{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-m3-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk (SubDL)","isDefault":true}],"subtitleDelayMs":200}
                """#
                return (resp, Data(body.utf8))
            }
            if url.path.hasSuffix("/subtitles/auto-align") {
                autoAlignBodies.withLock { $0.append(MockURLProtocol.bodyData(for: request)) }
                let body = #"{"ok":true,"sessionId":"sess-m3-1","applied":true,"mode":"reference_srt","offsetMs":-150,"scale":1.0,"subtitleDelayMs":-150}"#
                return (resp, Data(body.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let sessionJSON = #"""
        {
          "sessionId": "sess-m3-1",
          "streamToken": "tok-m3-secret-556677",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": {
            "itemId": "movie:tmdb:129",
            "mediaType": "movie",
            "ids": { "tmdb": 129 },
            "title": "Chihiro og heksene",
            "originalLanguage": "ja"
          },
          "selectedCandidate": {
            "candidateId": "cand-jp-1",
            "displayHeadline": "4K DV P7 FEL",
            "releaseTitle": "Spirited.Away.2160p",
            "source": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/sess-m3-1/tok-m3-secret-556677/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": true,
            "foldsDolbyVisionFEL": true,
            "dolbyVisionHandling": "automatic",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        let client = try MockURLProtocol.makeClient(host: host)
        let comfort = ComfortPreferences(defaults: defaults)
        let prefStore = PlaybackPreferenceStore(suiteName: suite)
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software)
        transport.audioTrackDescriptors = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Norsk 5.1", codec: "eac3", language: "nob", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese TrueHD Atmos", codec: "truehd", language: "jpn", channels: 8, isAtmos: true),
        ]
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
        ]

        let opts = PlayerViewModel.buildLoadOptions(
            session: session,
            client: client,
            comfort: comfort,
            audioEnhancement: .reference,
            audioDelaySeconds: 0
        )
        XCTAssertEqual(opts.preferredAudioLanguages, ["jpn", "ja", "eng"])

        let vm = PlayerViewModel(
            engine: engine,
            comfort: comfort,
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: prefStore,
            bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.videoFormat = .dolbyVision
        vm.qosReporter.sourceDVProfile = 7

        XCTAssertTrue(vm.hasNorwegianAudioTrack)
        XCTAssertFalse(vm.preferNorwegianAudio)
        vm.togglePreferNorwegianAudio()
        XCTAssertTrue(vm.preferNorwegianAudio)
        XCTAssertTrue(prefStore.preferNorwegianAudio(forItemId: "movie:tmdb:129"))
        XCTAssertEqual(vm.activeAudioTrackIndex, 0)
        XCTAssertEqual(vm.activeSubtitleTrackIndex, 11)

        // Sofa search-and-attach reloads in place without restarting stream
        let attached = await vm.trackController.performSearchAndAttachSubtitles()
        XCTAssertTrue(attached)
        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(transport.lastReloadedOptions?.externalSubtitles.count, 1)
        XCTAssertEqual(vm.subtitleDelayMs, 200)
        XCTAssertEqual(prefStore.subtitleDelayMs(forCandidateId: "cand-jp-1"), 200)

        // Auto-align omits subtitleDelayMs (both when non-zero and when zero) so LunaCore runs automatic alignment
        let aligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertTrue(aligned)
        XCTAssertEqual(vm.subtitleDelayMs, -150)
        XCTAssertEqual(prefStore.subtitleDelayMs(forCandidateId: "cand-jp-1"), -150)

        vm.trackController.resetSubtitleDelay()
        XCTAssertEqual(vm.subtitleDelayMs, 0)
        let alignedFromZero = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertTrue(alignedFromZero)

        let capturedAlignBodies = autoAlignBodies.withLock { $0 }
        XCTAssertEqual(capturedAlignBodies.count, 2)
        for bodyData in capturedAlignBodies {
            let alignJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertNil(alignJSON["subtitleDelayMs"])
            XCTAssertNil(alignJSON["delayMs"])
        }

        // HDR10 base-layer fallback via telemetry threshold + reloadAtCurrentPosition
        XCTAssertTrue(vm.qosReporter.isProfile7FELActive)
        vm.qosReporter.recordDolbyVisionTelemetrySample(droppedFrameCount: 30)
        XCTAssertTrue(vm.suggestsHDR10BaseLayer)
        XCTAssertTrue(vm.canSwitchToHDR10BaseLayer)
        await vm.trackController.performSwitchToHDR10BaseLayer()
        XCTAssertEqual(comfort.dualLayerOverride, .forceOff)
        XCTAssertEqual(transport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertEqual(transport.lastReloadedOptions?.preferDualLayerDolbyVision, false)
        XCTAssertFalse(vm.suggestsHDR10BaseLayer)
    }

    @MainActor
    func testLoadAlternativesCoalescesConcurrentRequestsAndDiscardsStaleSession() async throws {
        let host = "alt-coalesce-\(UUID().uuidString.lowercased()).local"
        defer { MockURLProtocol.unregister(host: host) }

        let altFetchCount = TestLockedBox(0)
        let altGate = TestStepGate()
        let altLog = TestLockedBox<[String]>([])
        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/alternatives") {
                altFetchCount.withLock { $0 += 1 }
                await altGate.wait(label: "alt", log: altLog)
                let body = #"""
                {"ok":true,"sessionId":"sess-alt-1","roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","activeCandidateId":"cand-1","alternatives":[{"candidateId":"cand-1","displayHeadline":"4K HDR10","releaseTitle":"Dune.2160p","source":"nvme"}]}
                """#
                return (resp, Data(body.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let suite = "luna.test.altcoalesce.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: FakePlayerTransport(), bindOnInit: false)
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makePlaybackSessionJSON(sessionId: "sess-alt-1", candidateId: "cand-1", headline: "4K")
        )

        // Two concurrent loadAlternatives() calls coalesce into 1 HTTP request
        async let callA: Void = vm.loadAlternatives()
        await altGate.waitUntilStarted()
        async let callB: Void = vm.loadAlternatives()
        await altGate.finish()
        _ = await (callA, callB)

        XCTAssertEqual(altFetchCount.withLock { $0 }, 1)
        XCTAssertEqual(vm.alternativesSessionId, "sess-alt-1")
        XCTAssertEqual(vm.alternatives.count, 1)

        // Idempotent repeat call for the same session skips HTTP fetch
        await vm.loadAlternatives()
        XCTAssertEqual(altFetchCount.withLock { $0 }, 1)

        // Stale session change while request is in flight discards result
        await altGate.reset()
        vm.activeSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makePlaybackSessionJSON(sessionId: "sess-alt-2", candidateId: "cand-2", headline: "4K")
        )
        let staleTask = Task { @MainActor in
            await vm.loadAlternatives()
        }
        await altGate.waitUntilStarted()
        vm.activeSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makePlaybackSessionJSON(sessionId: "sess-alt-3", candidateId: "cand-3", headline: "4K")
        )
        await altGate.finish()
        await staleTask.value
        XCTAssertNotEqual(vm.alternativesSessionId, "sess-alt-2")
    }

    private static func makeSeriesEpisodeSessionJSON(
        sessionId: String,
        itemId: String,
        episode: Int,
        nextEpisodeItemId: String? = nil
    ) -> Data {
        let nextField = nextEpisodeItemId.map {
            ", \"nextEpisode\": { \"itemId\": \"\($0)\", \"season\": 1, \"episode\": \(episode + 1), \"title\": \"Episode \(episode + 1)\" }"
        } ?? ""
        let raw = """
        {
          "sessionId": "\(sessionId)",
          "streamToken": "tok-ep-secret-\(episode)-998877",
          "roomName": "Kjellerstua",
          "hardwareProfile": "dv-fel-714",
          "item": { "itemId": "\(itemId)", "mediaType": "episode", "ids": { "tmdb": 95396 }, "title": "Episode \(episode)", "seriesTitle": "Severance", "season": 1, "episode": \(episode), "runtimeSeconds": 2800 },
          "selectedCandidate": { "candidateId": "cand-ep-\(episode)", "displayHeadline": "4K DV", "releaseTitle": "Severance.S01E0\(episode).2160p", "source": "nvme", "tier": "nvme" },
          "stream": { "url": "/api/tv/v2/stream/\(sessionId)/tok-ep-secret-\(episode)-998877/video.mkv" },
          "aetherConfig": { "preferDualLayerDolbyVision": true, "dolbyVisionHandling": "automatic", "matchContentEnabled": true, "audioBridgeMode": "lossless" }\(nextField)
        }
        """
        return Data(raw.utf8)
    }

    @MainActor
    func testSeamlessSourceSwitchHoldsOutgoingPictureBeforeReplacementAndWaitsForFirstFrameAndDisplaySwitch() async throws {
        let host = "switch-hold-\(UUID().uuidString.lowercased()).invalid"
        defer { MockURLProtocol.unregister(host: host) }
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/switch") {
                let switched = try JSONSerialization.jsonObject(with: Self.makePlaybackSessionJSON(
                    sessionId: "sess-hold-1", candidateId: "cand-remux-2", headline: "4K DV FEL"
                ))
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switched]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let suite = "luna.test.switch.hold.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software, currentTime: 500)
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Self.makePlaybackSessionJSON(sessionId: "sess-hold-1", candidateId: "cand-1", headline: "4K WEB-DL"))
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true

        let stillView = AetherStillView()
        vm.sessionController.attachStillView(stillView)
        XCTAssertTrue(transport.attachedStillView === stillView)

        var sawHoldDuringLoad = false
        transport.onLoadStream = { _, _, _ in
            sawHoldDuringLoad = vm.sessionController.isHoldingOutgoingPicture && vm.sessionController.isReplacingSourceItem && vm.isPictureReadyForReveal
        }
        vm.isAwaitingDisplaySwitch = true
        await vm.switchSource(to: "cand-remux-2")

        XCTAssertTrue(sawHoldDuringLoad)
        XCTAssertEqual(transport.holdOutgoingPictureCallCount, 1)
        let holdIdx = try XCTUnwrap(transport.events.firstIndex(of: "holdOutgoingPicture"))
        let prepIdx = try XCTUnwrap(transport.events.firstIndex(of: "prepareForItemReplacement"))
        XCTAssertLessThan(holdIdx, prepIdx)

        // Remains held and curtain stays hidden while awaiting first frame & HDMI display switch
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertTrue(vm.isPictureReadyForReveal)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 0)

        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        vm.isAwaitingDisplaySwitch = false
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(transport.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)
    }

    @MainActor
    func testSwitchSourceCurtainFallbackErrorReleaseAndWatchdogTimeoutOnServerSwitch() async throws {
        let host = "switch-fallback-\(UUID().uuidString.lowercased()).invalid"
        defer { MockURLProtocol.unregister(host: host) }
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/switch") {
                let switched = try JSONSerialization.jsonObject(with: Self.makePlaybackSessionJSON(
                    sessionId: "sess-fb-1", candidateId: "cand-2", headline: "4K"
                ))
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switched]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let suite = "luna.test.switch.fb.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software, currentTime: 250)
        transport.holdOutgoingPictureResult = false
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        let client = try MockURLProtocol.makeClient(host: host)
        vm.activeClient = client
        let s1 = try JSONDecoder().decode(TvPlaybackSession.self, from: Self.makePlaybackSessionJSON(sessionId: "sess-fb-1", candidateId: "cand-1", headline: "4K"))
        let s2 = try JSONDecoder().decode(TvPlaybackSession.self, from: Self.makePlaybackSessionJSON(sessionId: "sess-fb-1", candidateId: "cand-2", headline: "4K Remux"))
        vm.activeSession = s1
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true

        // 1. holdOutgoingPicture == false falls back to ResolvingCurtainView until first frame ready
        var curtainShownDuringLoad = false
        transport.onLoadStream = { _, _, _ in
            curtainShownDuringLoad = !vm.isPictureReadyForReveal
        }
        await vm.switchSource(to: "cand-2")
        XCTAssertTrue(curtainShownDuringLoad)
        XCTAssertFalse(vm.isPictureReadyForReveal)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertTrue(vm.isPictureReadyForReveal)

        // 2. Error during applyServerSwitchedSession releases hold cleanly
        transport.holdOutgoingPictureResult = true
        transport.onLoadStream = { _, _, _ in throw URLError(.cannotConnectToHost) }
        await vm.sessionController.applyServerSwitchedSession(s2, client: client, fallbackPosition: 250)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(vm.isSwitchingSource)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)

        // 3. Watchdog timeout unlocks and releases stuck hold when first frame never arrives
        transport.onLoadStream = nil
        transport.heldPictureFrameWaitSeconds = 0.05
        await vm.sessionController.applyServerSwitchedSession(s2, client: client, fallbackPosition: 250)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertTrue(vm.firstFrameFallbackUnlocked)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 2)
    }

    @MainActor
    func testWarmPlayNextEpisodeHoldsPictureAndReleasesOnCancelOrFallbackResolve() async throws {
        let host = "playnext-warm-\(UUID().uuidString.lowercased()).invalid"
        defer { MockURLProtocol.unregister(host: host) }

        let resolveGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let fallbackMode = TestLockedBox(false)
        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                if fallbackMode.withLock({ $0 }) {
                    let body = #"{"ok":true,"status":"resolving","resolveId":"res-next-fb","wsPath":"/api/tv/v2/ws/playback/res-next-fb"}"#
                    return (resp, Data(body.utf8))
                }
                await resolveGate.wait(label: "next", log: gateLog)
                let ep2 = try JSONSerialization.jsonObject(with: Self.makeSeriesEpisodeSessionJSON(sessionId: "sess-ep2", itemId: "ep-2", episode: 2))
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "status": "ready", "resolveId": "res-next-ep2", "playbackSession": ep2]))
            }
            if url.path == "/api/tv/v2/playback/resolve/res-next-fb" {
                let ep2 = try JSONSerialization.jsonObject(with: Self.makeSeriesEpisodeSessionJSON(sessionId: "sess-ep2", itemId: "ep-2", episode: 2))
                return (resp, try JSONSerialization.data(withJSONObject: ["type": "resolve.ready", "resolveId": "res-next-fb", "playbackSession": ep2]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let suite = "luna.test.playnext.warm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software, currentTime: 2650)
        let holdGate = TestStepGate()
        let holdLog = TestLockedBox<[String]>([])
        transport.onHoldOutgoingPicture = {
            await holdGate.wait(label: "hold", log: holdLog)
            return true
        }
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makeSeriesEpisodeSessionJSON(sessionId: "sess-ep1", itemId: "ep-1", episode: 1, nextEpisodeItemId: "ep-2")
        )
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true

        // 1. Cancellation while holdOutgoingPicture() is suspended never leaves orphaned held still
        vm.qosReporter.prewarmedNextEpisodeItemId = "ep-2"
        vm.qosReporter.prewarmedNextEpisodeSessionId = "prep-ep2"
        let nextEp = TvNextEpisodeSummary(itemId: "ep-2", season: 1, episode: 2, title: "Episode 2")
        vm.playNextEpisode(nextEp)
        XCTAssertEqual(transport.state, .paused)
        await holdGate.waitUntilStarted()
        vm.sessionController.resolveTask?.cancel()
        await holdGate.finish()
        await vm.sessionController.resolveTask?.value
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(transport.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)

        // 2. Fallback to slow resolveId releases held picture so ResolvingCurtainView is shown
        transport.onHoldOutgoingPicture = nil
        fallbackMode.withLock { $0 = true }
        vm.activeSession = try JSONDecoder().decode(
            TvPlaybackSession.self,
            from: Self.makeSeriesEpisodeSessionJSON(sessionId: "sess-ep1", itemId: "ep-1", episode: 1, nextEpisodeItemId: "ep-2")
        )
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true
        vm.qosReporter.prewarmedNextEpisodeItemId = "ep-2"
        vm.qosReporter.prewarmedNextEpisodeSessionId = "prep-ep2"
        let releaseExp = expectation(description: "Fallback resolveId releases outgoing hold")
        transport.onReleaseOutgoingPicture = { releaseExp.fulfill() }
        vm.playNextEpisode(nextEp)
        await fulfillment(of: [releaseExp], timeout: 3.0)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        vm.sessionController.resolveTask?.cancel()
    }

    @MainActor
    func testOverlappingHoldATrueThenHoldBFalseReleasesOrphanedHold() async throws {
        let suite = "luna.test.holdoverlap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try AetherEngine()
        defer { PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset(); engine.stop(resetDisplayCriteria: true) }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let gateA = TestStepGate(), gateB = TestStepGate(), log = TestLockedBox<[String]>([])
        let calls = TestLockedBox(0)
        transport.onHoldOutgoingPicture = {
            let n = calls.withLock { $0 += 1; return $0 }
            if n == 1 { await gateA.wait(label: "A", log: log); return true }
            await gateB.wait(label: "B", log: log); return false
        }
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, bindOnInit: false)
        let taskA = Task { @MainActor in await vm.sessionController.beginOutgoingPictureHold() }
        await gateA.waitUntilStarted()
        let taskB = Task { @MainActor in await vm.sessionController.beginOutgoingPictureHold() }
        await gateB.waitUntilStarted()
        await gateA.finish(); let tokA = await taskA.value
        await gateB.finish(); let tokB = await taskB.value
        XCTAssertNil(tokA); XCTAssertNil(tokB)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(transport.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)
    }
}
