import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PlayerQuickPanelAndSwitchTests: XCTestCase {
    // MARK: - Seamless Source/Room Switch & Track Intent Preservation

    @MainActor
    func testSwitchSourcePreservesTimecodeTrackLanguageSubtitleDelayAndSpeakerLayout() async throws {
        let host = "switch-source-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.switch")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let switchedSession = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-switch-1", candidateId: "cand-remux-2", headline: "4K HDR10+ TrueHD Atmos", objectAudioLayout: "7.1.4"
        )
        let switchedObj = try PlayerTestFixtures.sessionJSONObject(switchedSession)
        let switchBodies = TestLockedBox<[Data]>([])

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/switch") {
                switchBodies.withLock { $0.append(MockURLProtocol.bodyData(for: request)) }
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switchedObj]))
            }
            return (resp, Data(#"{"ok":true,"sessionId":"sess-switch-1","state":"playing"}"#.utf8))
        }

        let comfort = ComfortPreferences(defaults: scope.defaults)
        comfort.speakerLayoutOverride = .atmos512
        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software, currentTime: 1842.5)
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
        let initialSession = PlayerTestFixtures.makeMovieSession(sessionId: "sess-switch-1", candidateId: "cand-webdl-1", headline: "4K WEB-DL")
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = initialSession
        vm.isResolving = false
        vm.selectAudioTrack(1)
        vm.selectSubtitleManually(11)
        vm.setAudioEnhancement(.dialogueLift)
        vm.adjustSubtitleDelay(byMs: 150)

        // Permute audio & subtitle track IDs on switched edition
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

        let switchJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(switchBodies.withLock { $0.first })) as? [String: Any])
        XCTAssertEqual(switchJSON["candidateId"] as? String, "cand-remux-2")
        XCTAssertEqual(try XCTUnwrap(switchJSON["positionSeconds"] as? Double), 1842.5, accuracy: 0.01)

        XCTAssertTrue(transport.events.contains("prepareForItemReplacement"))
        XCTAssertEqual(try XCTUnwrap(transport.lastLoadedStartPosition), 1842.5, accuracy: 0.01)
        XCTAssertEqual(transport.lastLoadedOptions?.objectAudioRendering, .render(.l512))
        XCTAssertEqual(try XCTUnwrap(transport.lastLoadedOptions?.audioShaping.dialogueGainDB), 4.0, accuracy: 0.01)
        XCTAssertEqual(vm.activeAudioTrackIndex, 5)
        XCTAssertEqual(vm.activeSubtitleTrackIndex, 32)
        XCTAssertEqual(try XCTUnwrap(transport.lastSubtitleDelaySeconds), 0.15, accuracy: 0.0001)

        vm.clearSubtitleManually()
        await vm.switchSource(to: "cand-webdl-1")
        XCTAssertNil(vm.activeSubtitleTrackIndex)
        XCTAssertNil(transport.activeSubtitleTrackIndex)
    }

    // MARK: - Quick Panel OSD Tabs, Sofa Subtitles, Auto-Align & HDR10 Base-Layer Fallback

    @MainActor
    func testQuickPanelTabsSofaSubtitlesAutoAlignAndHDR10BaseLayerFallback() async throws {
        let host = "quickpanel-subs-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.v1.test.qp")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let autoAlignBodies = TestLockedBox<[Data]>([])
        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/subtitles/search-and-attach") {
                return (resp, Data(#"{"ok":true,"sessionId":"sess-qp-1","attached":true,"status":"attached","subtitle":{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-qp-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk (SubDL)","isDefault":true},"externalSubtitles":[{"id":"ext-nob-1","url":"/api/tv/v2/subtitles/sess-qp-1/0/nob.srt","format":"srt","language":"nob","name":"Norsk (SubDL)","isDefault":true}],"subtitleDelayMs":200}"#.utf8))
            }
            if url.path.hasSuffix("/subtitles/auto-align") {
                autoAlignBodies.withLock { $0.append(MockURLProtocol.bodyData(for: request)) }
                return (resp, Data(#"{"ok":true,"sessionId":"sess-qp-1","applied":true,"mode":"reference_srt","offsetMs":-150,"scale":1.0,"subtitleDelayMs":-150}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let comfort = ComfortPreferences(defaults: scope.defaults)
        let prefStore = PlaybackPreferenceStore(suiteName: scope.suiteName)
        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software)
        transport.audioTrackDescriptors = [
            PlaybackAudioTrackDescriptor(id: 0, name: "Norsk 5.1", codec: "eac3", language: "nob", channels: 6),
            PlaybackAudioTrackDescriptor(id: 1, name: "Japanese TrueHD Atmos", codec: "truehd", language: "jpn", channels: 8, isAtmos: true),
        ]
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 10, name: "Norsk", codec: "srt", language: "nob"),
            SmartTrackDescriptor(id: 11, name: "Norsk (Tvungen)", codec: "srt", language: "nob", isForced: true),
        ]

        let session = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-qp-1", itemId: "movie:tmdb:129", tmdbId: 129, title: "Chihiro og heksene",
            originalLanguage: "ja", candidateId: "cand-jp-1", preferDualLayerDolbyVision: true, foldsDolbyVisionFEL: true
        )
        let client = try MockURLProtocol.makeClient(host: host)
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in }, preferenceStore: prefStore, bindOnInit: false
        )
        vm.activeClient = client
        vm.activeSession = session
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true
        vm.playbackPhase = .playing
        vm.videoFormat = .dolbyVision
        vm.qosReporter.sourceDVProfile = 7

        // 1. OSD Quick Panel tab cycling skips .chapters when empty and Menu restores tab pill focus
        let osd = PlayerOSDCoordinator()
        for panel in [nil] + PlayerQuickPanelTab.allCases.map(Optional.some) {
            osd.activeQuickPanel = panel
            XCTAssertTrue(PlayerOSDVisibilityPolicy.shouldShowSubtitleOverlay(
                hasFatalError: vm.fatalError != nil,
                hasSuspendedFatalError: osd.suspendedFatalErrorForPanel != nil,
                isPictureReadyForReveal: vm.isPictureReadyForReveal
            ))
        }
        osd.openQuickPanel(.subtitles)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        osd.switchQuickPanelTab(direction: .right, hasChapters: false)
        XCTAssertEqual(osd.activeQuickPanel, .picture)
        osd.handleExitCommand(viewModel: vm, onClosePlayer: { XCTFail("Should not exit player") })
        XCTAssertNil(osd.activeQuickPanel)
        XCTAssertEqual(osd.requestedBottomBarAction, .panel(.picture))
        for preset in HDRSubtitlePreset.allCases {
            XCTAssertEqual(preset.foregroundColor(isHDR: false), preset.foregroundColor(isHDR: true))
        }

        // 2. Original language audio + "Norsk tale" toggle + sofa search-and-attach + auto-align + HDR10 base-layer
        let opts = PlayerViewModel.buildLoadOptions(session: session, client: client, comfort: comfort, audioEnhancement: .reference, audioDelaySeconds: 0)
        XCTAssertEqual(opts.preferredAudioLanguages, ["jpn", "ja", "eng"])

        vm.togglePreferNorwegianAudio()
        XCTAssertTrue(vm.preferNorwegianAudio)
        XCTAssertEqual(vm.activeAudioTrackIndex, 0)
        XCTAssertEqual(vm.activeSubtitleTrackIndex, 11)

        let attached = await vm.trackController.performSearchAndAttachSubtitles()
        XCTAssertTrue(attached)
        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(vm.subtitleDelayMs, 200)

        let aligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertTrue(aligned)
        XCTAssertEqual(vm.subtitleDelayMs, -150)
        let alignJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(autoAlignBodies.withLock { $0.first })) as? [String: Any])
        XCTAssertNil(alignJSON["subtitleDelayMs"])

        vm.qosReporter.recordDolbyVisionTelemetrySample(droppedFrameCount: 30)
        XCTAssertTrue(vm.suggestsHDR10BaseLayer && vm.canSwitchToHDR10BaseLayer)
        await vm.trackController.performSwitchToHDR10BaseLayer()
        XCTAssertEqual(comfort.dualLayerOverride, .forceOff)
        XCTAssertEqual(transport.lastReloadedOptions?.dolbyVisionHandling, .baseLayerOnly)
        XCTAssertFalse(vm.suggestsHDR10BaseLayer)
    }

    // MARK: - Alternatives Coalescing & Seamless Outgoing Picture Hold Lifecycle

    @MainActor
    func testLoadAlternativesCoalescingAndOutgoingPictureHoldSwitchAndNextEpisodeGuards() async throws {
        let host = "switch-hold-\(UUID().uuidString.lowercased()).invalid"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.holdswitch")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }

        let altGate = TestStepGate()
        let altLog = TestLockedBox<[String]>([])
        let altFetches = TestLockedBox(0)
        let fallbackResolveMode = TestLockedBox(false)
        let switchedObj = try PlayerTestFixtures.sessionJSONObject(
            PlayerTestFixtures.makeMovieSession(sessionId: "sess-hold-1", candidateId: "cand-remux-2", headline: "4K DV FEL")
        )
        let ep2Obj = try PlayerTestFixtures.sessionJSONObject(
            PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-ep2", itemId: "ep-2", episode: 2)
        )

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path.hasSuffix("/alternatives") {
                altFetches.withLock { $0 += 1 }
                await altGate.wait(label: "alt", log: altLog)
                return (resp, Data(#"{"ok":true,"sessionId":"sess-hold-1","roomName":"Kjellerstua","hardwareProfile":"dv-fel-714","activeCandidateId":"cand-1","alternatives":[{"candidateId":"cand-1","displayHeadline":"4K HDR10","releaseTitle":"Dune.2160p","source":"nvme"}]}"#.utf8))
            }
            if url.path.hasSuffix("/switch") {
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switchedObj]))
            }
            if url.path == "/api/tv/v2/playback/resolve" {
                if fallbackResolveMode.withLock({ $0 }) {
                    return (resp, Data(#"{"ok":true,"status":"resolving","resolveId":"res-next-fb","wsPath":"/api/tv/v2/ws/playback/res-next-fb"}"#.utf8))
                }
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "status": "ready", "resolveId": "res-next-ep2", "playbackSession": ep2Obj]))
            }
            if url.path == "/api/tv/v2/playback/resolve/res-next-fb" {
                return (resp, try JSONSerialization.data(withJSONObject: ["type": "resolve.ready", "resolveId": "res-next-fb", "playbackSession": ep2Obj]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let comfort = ComfortPreferences(defaults: scope.defaults)
        let client = try MockURLProtocol.makeClient(host: host)
        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .software, currentTime: 500)
        let vm = PlayerViewModel(
            engine: engineScope.engine, comfort: comfort, transport: transport,
            audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false
        )
        let s1 = PlayerTestFixtures.makeMovieSession(sessionId: "sess-hold-1", candidateId: "cand-1", headline: "4K WEB-DL")
        vm.activeClient = client
        vm.activeSession = s1
        vm.isResolving = false
        vm.hasFirstFrameReadyForDisplay = true

        // 1. Concurrent loadAlternatives() coalesces into 1 HTTP request
        async let callA: Void = vm.loadAlternatives()
        await altGate.waitUntilStarted()
        async let callB: Void = vm.loadAlternatives()
        await altGate.finish()
        _ = await (callA, callB)
        XCTAssertEqual(altFetches.withLock { $0 }, 1)
        XCTAssertEqual(vm.alternativesSessionId, "sess-hold-1")

        // 2. holdOutgoingPicture precedes prepareForItemReplacement and waits for firstFrame + !isAwaitingDisplaySwitch
        let stillView = AetherStillView()
        vm.sessionController.attachStillView(stillView)
        XCTAssertTrue(transport.attachedStillView === stillView)
        vm.isAwaitingDisplaySwitch = true
        await vm.switchSource(to: "cand-remux-2")
        let holdIdx = try XCTUnwrap(transport.events.firstIndex(of: "holdOutgoingPicture"))
        let prepIdx = try XCTUnwrap(transport.events.firstIndex(of: "prepareForItemReplacement"))
        XCTAssertLessThan(holdIdx, prepIdx)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture && vm.isPictureReadyForReveal)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        vm.isAwaitingDisplaySwitch = false
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)

        // 3. holdOutgoingPicture == false falls back to curtain; error & watchdog timeout release stuck holds
        transport.holdOutgoingPictureResult = false
        await vm.switchSource(to: "cand-remux-2")
        XCTAssertFalse(vm.isPictureReadyForReveal)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertTrue(vm.isPictureReadyForReveal)

        let s2 = PlayerTestFixtures.makeMovieSession(sessionId: "sess-hold-1", candidateId: "cand-2", headline: "4K Remux")
        transport.holdOutgoingPictureResult = true
        transport.onLoadStream = { _, _, _ in throw URLError(.cannotConnectToHost) }
        await vm.sessionController.applyServerSwitchedSession(s2, client: client, fallbackPosition: 250)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)

        transport.onLoadStream = nil
        transport.heldPictureFrameWaitSeconds = 0.05
        await vm.sessionController.applyServerSwitchedSession(s2, client: client, fallbackPosition: 250)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertTrue(vm.firstFrameFallbackUnlocked)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)

        // 4. Warm playNextEpisode fallback to slow resolveId releases held picture so curtain shows
        fallbackResolveMode.withLock { $0 = true }
        let nextEp = TvNextEpisodeSummary(itemId: "ep-2", season: 1, episode: 2, title: "Episode 2")
        vm.activeSession = PlayerTestFixtures.makeEpisodeSession(sessionId: "sess-ep1", itemId: "ep-1", season: 1, episode: 1, nextEpisode: nextEp)
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

        // 5. Overlapping holdA (true) superseded by holdB (false) releases orphaned hold cleanly
        let overlapTransport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let gateA = TestStepGate(), gateB = TestStepGate(), log = TestLockedBox<[String]>([])
        let holdCalls = TestLockedBox(0)
        overlapTransport.onHoldOutgoingPicture = {
            let n = holdCalls.withLock { $0 += 1; return $0 }
            if n == 1 { await gateA.wait(label: "A", log: log); return true }
            await gateB.wait(label: "B", log: log); return false
        }
        let overlapVM = PlayerViewModel(engine: engineScope.engine, comfort: comfort, transport: overlapTransport, bindOnInit: false)
        let taskA = Task { @MainActor in await overlapVM.sessionController.beginOutgoingPictureHold() }
        await gateA.waitUntilStarted()
        let taskB = Task { @MainActor in await overlapVM.sessionController.beginOutgoingPictureHold() }
        await gateB.waitUntilStarted()
        await gateA.finish(); let tokA = await taskA.value
        await gateB.finish(); let tokB = await taskB.value
        XCTAssertNil(tokA); XCTAssertNil(tokB)
        XCTAssertFalse(overlapVM.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(overlapTransport.releaseOutgoingPictureCallCount, 1)
    }
}
