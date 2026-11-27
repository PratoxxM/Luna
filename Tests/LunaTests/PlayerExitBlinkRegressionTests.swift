import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PlayerExitBlinkRegressionTests: XCTestCase {
    @MainActor
    func testSharedEngineDisablesAudioSessionDeactivationOnStop() throws {
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        XCTAssertFalse(engine.deactivatesAudioSessionOnStop)
        XCTAssertEqual(engine.maximumSubtitleAdvanceSeconds, 0)
        XCTAssertEqual(engine.maximumSubtitleDelaySeconds, 10)
        XCTAssertTrue(engine.ownsSoftwareNowPlaying)
        XCTAssertTrue(engine.ownsVideoNowPlayingSession)
        XCTAssertTrue(engine.ownsVideoNowPlayingCommands)
    }

    func testShouldPauseEngineOnDismissPredicate() {
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .playing, playbackPhase: .playing))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .seeking, playbackPhase: .seeking))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .loading, playbackPhase: .loading))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .rebuffering))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .stalled(reconnecting: true)))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .paused))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .idle, playbackPhase: .idle))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .ended, playbackPhase: .ended))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .error("err"), playbackPhase: .error("err")))
    }

    @MainActor
    func testPrepareForDismissalPausesWithoutFrameZeroStopAndTeardownStopsOffScreen() throws {
        let suite = "luna.test.dismissal.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let comfort = ComfortPreferences(defaults: defaults)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport)
        vm.isResolving = false
        vm.playbackPhase = .playing

        vm.prepareForDismissal()
        XCTAssertTrue(vm.isDismissing)
        XCTAssertFalse(vm.isTeardownCompleted)
        XCTAssertEqual(transport.events, ["pause"])
        XCTAssertEqual(vm.playbackPhase, .playing)

        // Calling prepareForDismissal twice is idempotent
        vm.prepareForDismissal()
        XCTAssertEqual(transport.events, ["pause"])

        var didComplete = false
        vm.teardownAndStop {
            didComplete = true
        }
        XCTAssertTrue(vm.isTeardownCompleted)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(transport.events, ["pause", "stop(true,true)"])

        // Calling teardownAndStop twice is idempotent
        vm.teardownAndStop()
        XCTAssertEqual(transport.events, ["pause", "stop(true,true)"])
    }

    @MainActor
    func testSupersededOwnerSkipsEngineStopDuringLateDisappear() throws {
        let suite = "luna.test.ownership.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport1 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let transport2 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let comfort = ComfortPreferences(defaults: defaults)
        let vm1 = PlayerViewModel(engine: engine, comfort: comfort, transport: transport1)
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort, transport: transport2)

        let req1 = PlaybackLaunchRequest(
            itemId: "episode:tmdb:100:s1:e1",
            title: "Episode 1",
            seriesTitle: "Test",
            season: 1,
            episode: 1
        )
        let req2 = PlaybackLaunchRequest(
            itemId: "episode:tmdb:100:s1:e2",
            title: "Episode 2",
            seriesTitle: "Test",
            season: 1,
            episode: 2
        )

        vm1.start(request: req1, client: nil)
        vm1.fatalError = nil
        vm1.playbackPhase = .playing
        XCTAssertTrue(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))

        vm1.prepareForDismissal()
        XCTAssertEqual(transport1.events, ["pause"])

        vm2.start(request: req2, client: nil)
        XCTAssertFalse(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm2.engineOwnerToken))

        vm1.teardownAndStop()
        XCTAssertTrue(vm1.isTeardownCompleted)
        XCTAssertEqual(transport1.events, ["pause"])

        vm2.teardownAndStop()
        XCTAssertTrue(vm2.isTeardownCompleted)
        XCTAssertEqual(transport2.events, ["stop(true,true)"])
    }

    @MainActor
    func testKeepDisplayModeInMenuPreferenceMigratesExistingTVsTo60HzAndSupportsPerTvOptOut() async throws {
        let suite = "luna.test.displayhold.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let comfort = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(comfort.menuDisplayMode, .sdr60Hz)
        XCTAssertFalse(comfort.keepDisplayModeInMenuAfterPlayback)

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let defaultTransport = MockPlayerTransport()
        let defaultVm = PlayerViewModel(engine: engine, comfort: comfort, transport: defaultTransport)
        defaultVm.teardownAndStop()
        XCTAssertEqual(defaultTransport.events, ["stop(true,true)"])

        var syncCalls = 0
        comfort.onSyncRequested = { _ in syncCalls += 1 }
        comfort.menuDisplayMode = .preserveExactMatch
        XCTAssertEqual(syncCalls, 1)
        XCTAssertTrue(comfort.keepDisplayModeInMenuAfterPlayback)
        XCTAssertEqual(
            defaults.string(forKey: SideloadSafeStorage.menuDisplayModeKey),
            MenuDisplayMode.preserveExactMatch.rawValue
        )

        let reloaded = ComfortPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.menuDisplayMode, .preserveExactMatch)
        XCTAssertTrue(reloaded.keepDisplayModeInMenuAfterPlayback)

        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: .preserveExactMatch,
                videoFormat: .dolbyVision,
                isForegroundActive: true
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: .preserveExactMatch,
                videoFormat: .dolbyVision,
                isForegroundActive: false
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetDisplayCriteriaOnPlayerExit(
                menuDisplayMode: .sdr60Hz,
                videoFormat: .dolbyVision,
                isForegroundActive: true
            )
        )

        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: false,
                keepDisplayModeInMenu: true
            )
        )
        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isBackgroundScene: true,
                hasActivePlayback: false,
                engineState: .idle
            )
        )
        // Control Center / Siri `.inactive` must NOT reset held QMS/HDR display criteria
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isBackgroundScene: false,
                hasActivePlayback: false,
                engineState: .idle
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isBackgroundScene: true,
                hasActivePlayback: true,
                engineState: .idle
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isBackgroundScene: true,
                hasActivePlayback: false,
                engineState: .playing
            )
        )

        let coordinator = PlayerAudioSessionCoordinator()
        var resetCount = 0
        coordinator.holdDisplayCriteriaUntilBackground(
            shouldExecute: { true },
            performReset: { resetCount += 1 }
        )
        coordinator.handleDetailDisappear(
            isLaunchingPlayback: false,
            isShowingSourcePicker: false,
            keepDisplayModeInMenu: true
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(resetCount, 0)

        coordinator.flushDeferredDisplayCriteriaResetIfIdle()
        XCTAssertEqual(resetCount, 1)
        coordinator.flushDeferredDisplayCriteriaResetIfIdle()
        XCTAssertEqual(resetCount, 1)

        let optOutTransport = MockPlayerTransport()
        let optOutVm = PlayerViewModel(engine: engine, comfort: reloaded, transport: optOutTransport)
        optOutVm.teardownAndStop()
        XCTAssertEqual(optOutTransport.events, ["stop(false,true)"])
    }

    @MainActor
    func testPlayerViewModelDeallocatesCleanlyWithoutRetainCyclesAndSupportsDeferredBind() throws {
        let suite = "luna.test.vm.deinit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)

        weak var weakUnboundVM: PlayerViewModel?
        do {
            let unbound = PlayerViewModel(engine: engine, comfort: comfort, bindOnInit: false)
            XCTAssertTrue(unbound.cancellables.isEmpty)
            weakUnboundVM = unbound
        }
        XCTAssertNil(weakUnboundVM, "Unbound @State init instance must deallocate immediately")

        weak var weakBoundVM: PlayerViewModel?
        weak var weakDismissedVM: PlayerViewModel?
        do {
            let bound = PlayerViewModel(engine: engine, comfort: comfort)
            XCTAssertFalse(bound.cancellables.isEmpty)
            weakBoundVM = bound

            let dismissed = PlayerViewModel(engine: engine, comfort: comfort)
            XCTAssertFalse(dismissed.cancellables.isEmpty)
            dismissed.prepareForDismissal()
            dismissed.teardownAndStop()
            weakDismissedVM = dismissed
        }
        XCTAssertNil(weakBoundVM, "All [weak self] Combine sinks in PlayerEnginePublishers must release PlayerViewModel without retain cycles")
        XCTAssertNil(weakDismissedVM, "Dismissed PlayerViewModel must deallocate cleanly")
    }

    @MainActor
    func testEarlyBackAbortDuringResolvingCurtainStopsHandedOverAndInflightSessionsWithoutLeak() async throws {
        let host = "player-early-abort-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.test.earlyabort.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let resolveGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let stoppedHeartbeatCount = TestLockedBox(0)

        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                await resolveGate.wait(label: "resolve", log: gateLog)
                return (resp, Data(#"{"ok":false,"status":"failed","resolveId":"r1"}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/heartbeat" {
                stoppedHeartbeatCount.withLock { $0 += 1 }
                return (resp, Data(#"{"ok":true,"sessionId":"stopped","state":"stopped"}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)
        let client = try MockURLProtocol.makeClient(host: host)

        // Sub-case A: Pre-resolved prepareToken handed over, then user presses Back in ResolvingCurtainView
        let transportA = MockPlayerTransport()
        let vmA = PlayerViewModel(engine: engine, comfort: comfort, transport: transportA)
        let reqA = PlaybackLaunchRequest(
            itemId: "movie:tmdb:550",
            title: "Fight Club",
            prepareToken: "tvs_handed_over_1"
        )
        vmA.start(request: reqA, client: client)
        await resolveGate.waitUntilStarted()

        let stopDoneA = expectation(description: "Stopped heartbeat sent for handed-over session")
        vmA.prepareForDismissal()
        vmA.teardownAndStop {
            stopDoneA.fulfill()
        }
        await resolveGate.finish()
        await fulfillment(of: [stopDoneA], timeout: 3.0)
        XCTAssertEqual(stoppedHeartbeatCount.withLock { $0 }, 1)

        // Sub-case B: Early click handed over an in-flight prepareTask that finishes during Back abort
        await resolveGate.reset()
        let latePrepJSON = #"""
        {"ok":true,"status":"prepared","prepareToken":"tvs_inflight_orphan_2"}
        """#
        let latePrep = try JSONDecoder().decode(TvPrepareResponse.self, from: Data(latePrepJSON.utf8))
        let inflightPrepTask = Task<TvPrepareResponse?, Never> {
            try? await Task.sleep(nanoseconds: 25_000_000)
            return latePrep
        }

        let transportB = MockPlayerTransport()
        let vmB = PlayerViewModel(engine: engine, comfort: comfort, transport: transportB)
        let reqB = PlaybackLaunchRequest(
            itemId: "movie:tmdb:603",
            title: "The Matrix",
            inflightPrepareTask: inflightPrepTask
        )
        vmB.start(request: reqB, client: client)
        await resolveGate.waitUntilStarted()

        let stopDoneB = expectation(description: "Stopped heartbeat sent for late in-flight prepare session")
        vmB.prepareForDismissal()
        vmB.teardownAndStop {
            stopDoneB.fulfill()
        }
        await resolveGate.finish()
        await fulfillment(of: [stopDoneB], timeout: 3.0)
        XCTAssertEqual(stoppedHeartbeatCount.withLock { $0 }, 2, "Both handed-over and in-flight sessions must send state='stopped' on curtain abort")
    }

    @MainActor
    func testTwentyCyclePlayerViewModelAndControllerDeallocationWithoutRetainCycles() throws {
        let suite = "luna.test.vm.deinit20.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)

        for cycle in 0..<20 {
            weak var weakVM: PlayerViewModel?
            weak var weakSession: PlayerSessionController?
            weak var weakTrack: PlayerTrackController?
            weak var weakScrub: PlayerScrubController?
            weak var weakRestore: PlayerRestoreController?
            weak var weakQoS: PlayerQoSReporter?

            do {
                let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: Double(cycle * 10))
                let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: true)
                weakVM = vm
                weakSession = vm.sessionController
                weakTrack = vm.trackController
                weakScrub = vm.scrubController
                weakRestore = vm.restoreController
                weakQoS = vm.qosReporter

                let req = PlaybackLaunchRequest(
                    itemId: "episode:tmdb:95396:s1:e\(cycle + 1)",
                    title: "Episode \(cycle + 1)",
                    seriesTitle: "Test",
                    season: 1,
                    episode: cycle + 1
                )
                vm.start(request: req, client: nil)
                vm.prepareForDismissal()
                vm.teardownAndStop()
            }

            XCTAssertNil(weakVM, "Cycle \(cycle): PlayerViewModel must deallocate")
            XCTAssertNil(weakSession, "Cycle \(cycle): PlayerSessionController must deallocate")
            XCTAssertNil(weakTrack, "Cycle \(cycle): PlayerTrackController must deallocate")
            XCTAssertNil(weakScrub, "Cycle \(cycle): PlayerScrubController must deallocate")
            XCTAssertNil(weakRestore, "Cycle \(cycle): PlayerRestoreController must deallocate")
            XCTAssertNil(weakQoS, "Cycle \(cycle): PlayerQoSReporter must deallocate")
        }
    }

    @MainActor
    func testTeardownAndStopEmitsPlaybackStopReceiptAfterStoppedHeartbeat() async throws {
        let host = "stop-receipt-\(UUID().uuidString.lowercased()).local"
        let suite = "luna.test.stopreceipt.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true,"sessionId":"sess-receipt-1","state":"stopped","watchCompleted":true}"#.utf8))
        }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)
        let client = try MockURLProtocol.makeClient(host: host)
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 1850)
        let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: transport, bindOnInit: false)

        let sessionJSON = #"""
        {
          "sessionId": "sess-receipt-1",
          "streamToken": "tok-receipt-secret-112233",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "episode:tmdb:95396:s2:e5",
            "mediaType": "episode",
            "ids": { "tmdb": 95396 },
            "title": "Trojan's Horse",
            "seriesTitle": "Severance",
            "season": 2,
            "episode": 5,
            "runtimeSeconds": 2800
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K WEB-DL",
            "releaseTitle": "Severance.S02E05.2160p",
            "source": "nvme"
          },
          "stream": { "url": "/api/tv/v2/stream/sess-receipt-1/tok-receipt-secret-112233/video.mkv" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        vm.activeSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        vm.activeClient = client
        vm.durationSeconds = 2800

        let exp = expectation(description: "PlaybackStopReceipt delivered")
        var capturedReceipt: PlaybackStopReceipt?
        vm.prepareForDismissal()
        vm.teardownAndStop(
            onComplete: { exp.fulfill() },
            onStopReceipt: { receipt in capturedReceipt = receipt }
        )
        await fulfillment(of: [exp], timeout: 3.0)

        let receipt = try XCTUnwrap(capturedReceipt)
        XCTAssertEqual(receipt.itemId, "episode:tmdb:95396:s2:e5")
        XCTAssertEqual(receipt.mediaType, "episode")
        XCTAssertEqual(receipt.seasonNumber, 2)
        XCTAssertEqual(receipt.episodeNumber, 5)
        XCTAssertEqual(receipt.positionSeconds, 1850, accuracy: 0.1)
        XCTAssertTrue(receipt.completed)
    }

    @MainActor
    func testDismissalTeardownAndFatalErrorReleaseActiveOutgoingPictureHoldWithoutPollutingNonHoldEvents() throws {
        let suite = "luna.test.holdrelease.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = try AetherEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let comfort = ComfortPreferences(defaults: defaults)

        // 1. Active hold released once by prepareForDismissal(), not duplicated by teardownAndStop()
        let t1 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let vm1 = PlayerViewModel(engine: engine, comfort: comfort, transport: t1, bindOnInit: false)
        vm1.sessionController.isHoldingOutgoingPicture = true
        t1.isHoldingOutgoingPicture = true
        vm1.prepareForDismissal()
        XCTAssertFalse(vm1.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(t1.isHoldingOutgoingPicture)
        XCTAssertEqual(t1.releaseOutgoingPictureCallCount, 1)
        vm1.teardownAndStop()
        XCTAssertEqual(t1.releaseOutgoingPictureCallCount, 1)
        XCTAssertEqual(t1.events, ["releaseOutgoingPicture", "pause", "stop(true,true)"])

        // 2. Direct teardownAndStop() without prepareForDismissal() releases active hold
        let t2 = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort, transport: t2, bindOnInit: false)
        vm2.sessionController.isHoldingOutgoingPicture = true
        t2.isHoldingOutgoingPicture = true
        vm2.teardownAndStop()
        XCTAssertFalse(vm2.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(t2.releaseOutgoingPictureCallCount, 1)
        XCTAssertEqual(t2.events, ["releaseOutgoingPicture", "stop(true,true)"])

        // 3. Setting fatalError immediately releases active hold
        let t3 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let vm3 = PlayerViewModel(engine: engine, comfort: comfort, transport: t3, bindOnInit: false)
        vm3.sessionController.isHoldingOutgoingPicture = true
        t3.isHoldingOutgoingPicture = true
        vm3.fatalError = "Avspillingsfeil"
        XCTAssertFalse(vm3.sessionController.isHoldingOutgoingPicture)
        XCTAssertFalse(vm3.isPictureReadyForReveal)
        XCTAssertEqual(t3.releaseOutgoingPictureCallCount, 1)
    }

    @MainActor
    func testForegroundVideoRestorePreservesExternalSubtitlesWhenClientAndSessionPresent() async throws {
        let suite = "luna.test.restore.extsubs.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let sessionJSON = #"""
        {
          "sessionId": "sess-restore-subs-1",
          "streamToken": "tok-restore-subs-445566",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": { "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Fight Club" },
          "selectedCandidate": { "candidateId": "cand-1", "displayHeadline": "4K HDR10+", "releaseTitle": "Fight.Club.2160p", "source": "nvme" },
          "stream": { "url": "/api/tv/v2/stream/sess-restore-subs-1/tok-restore-subs-445566/video.mkv" },
          "tracks": {
            "externalSubtitles": [
              { "id": "ext-nob-1", "url": "/api/tv/v2/subtitles/sess-restore-subs-1/0/nob.srt", "format": "srt", "language": "nob", "name": "Norsk", "isDefault": true }
            ]
          },
          "aetherConfig": { "preferDualLayerDolbyVision": false, "dolbyVisionHandling": "baseLayerOnly", "matchContentEnabled": true, "audioBridgeMode": "lossless" }
        }
        """#
        let session = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(sessionJSON.utf8))
        let client = try MockURLProtocol.makeClient(host: "restore-extsubs.invalid")
        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(
            state: .paused,
            playbackPhase: .paused,
            videoRoute: .loopback,
            currentTime: 420,
            needsForegroundVideoRestore: true
        )
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, bindOnInit: false)
        vm.activeSession = session
        vm.activeClient = client
        vm.isResolving = false
        vm.lastForegroundPlaybackWasPlaying = true
        vm.sessionController.isHoldingOutgoingPicture = true
        transport.isHoldingOutgoingPicture = true

        vm.handleScenePhaseChange(.active)
        await vm.restoreController.foregroundRestoreTask?.value

        XCTAssertEqual(transport.reloadCallCount, 1)
        XCTAssertEqual(transport.lastReloadedOptions?.autoplay, true)
        XCTAssertEqual(transport.lastReloadedOptions?.externalSubtitles.count, 1)
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)
    }

    @MainActor
    func testWarmDirectMountPromotionAndSupersededSwitchGenerationNonInterference() async throws {
        let host = "warm-promo-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.test.warmpromo.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let makeSessionData: (String, String) -> Data = { sid, cid in
            Data("""
            {
              "sessionId": "\(sid)", "streamToken": "tok-promo-secret-112233", "roomName": "Stua", "hardwareProfile": "hdr10-512",
              "item": { "itemId": "movie:tmdb:550", "mediaType": "movie", "ids": { "tmdb": 550 }, "title": "Fight Club" },
              "selectedCandidate": { "candidateId": "\(cid)", "displayHeadline": "4K HDR10+", "releaseTitle": "Fight.Club.2160p", "source": "nvme" },
              "stream": { "url": "/api/tv/v2/stream/\(sid)/tok-promo-secret-112233/video.mkv" },
              "aetherConfig": { "preferDualLayerDolbyVision": false, "dolbyVisionHandling": "baseLayerOnly", "matchContentEnabled": true, "audioBridgeMode": "lossless" }
            }
            """.utf8)
        }
        let prepSession = try JSONDecoder().decode(TvPlaybackSession.self, from: makeSessionData("sess-prep-1", "cand-1"))
        let promoData = makeSessionData("sess-promo-2", "cand-2")
        let switchData = makeSessionData("sess-switch-3", "cand-3")

        let switchGate = TestStepGate()
        let switchLog = TestLockedBox<[String]>([])
        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                let promoObj = try JSONSerialization.jsonObject(with: promoData)
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "status": "ready", "resolveId": "res-promo-2", "playbackSession": promoObj]))
            }
            if url.path.hasSuffix("/switch") {
                await switchGate.wait(label: "switch", log: switchLog)
                let swObj = try JSONSerialization.jsonObject(with: switchData)
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": swObj]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .loopback, currentTime: 100)
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        let client = try MockURLProtocol.makeClient(host: host)
        vm.activeClient = client

        // 1. Warm direct-mount promotion holds outgoing frame until promoted stream renders first frame
        let req = PlaybackLaunchRequest(itemId: "movie:tmdb:550", title: "Fight Club", prepareToken: "sess-prep-1", preparedSession: prepSession)
        await vm.sessionController.runResolveAndLoad(request: req, client: client)
        XCTAssertEqual(vm.activeSession?.sessionId, "sess-promo-2")
        XCTAssertEqual(transport.holdOutgoingPictureCallCount, 1)
        XCTAssertTrue(transport.events.contains("prepareForItemReplacement"))
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)

        // 2. Cancelled switchSource task must NOT interfere with a newer active hold token
        vm.triggerSourceSwitch(to: "cand-3")
        await switchGate.waitUntilStarted()
        let supersededTask = vm.sessionController.switchSourceTask
        supersededTask?.cancel()
        _ = await vm.sessionController.beginOutgoingPictureHold()
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        await switchGate.finish()
        await supersededTask?.value
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        vm.teardownAndStop()
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
    }

    @MainActor
    func testStaleFirstFrameFallbackWatchdogIsCancelledAndDoesNotDropHoldMidSwitch() async throws {
        let host = "stale-wd-\(UUID().uuidString.lowercased()).invalid"
        let suite = "luna.test.stalewd.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { MockURLProtocol.unregister(host: host); defaults.removePersistentDomain(forName: suite) }
        let sessionJSON: @Sendable (String) -> Data = { cand in
            Data(#"{"sessionId":"sess-wd-1","streamToken":"tok-wd-secret-112233","roomName":"Stua","hardwareProfile":"hdr10-512","item":{"itemId":"movie:tmdb:550","mediaType":"movie","ids":{"tmdb":550},"title":"Fight Club"},"selectedCandidate":{"candidateId":"\#(cand)","displayHeadline":"4K","releaseTitle":"Fight.Club","source":"nvme"},"stream":{"url":"/api/tv/v2/stream/sess-wd-1/tok-wd-secret-112233/video.mkv"},"aetherConfig":{"preferDualLayerDolbyVision":false,"dolbyVisionHandling":"baseLayerOnly","matchContentEnabled":true,"audioBridgeMode":"lossless"}}"#.utf8)
        }
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let switched = try JSONSerialization.jsonObject(with: sessionJSON("cand-2"))
            return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switched]))
        }
        let engine = try LunaApp.makeSharedEngine()
        defer { PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset(); engine.stop(resetDisplayCriteria: true) }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 300)
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = try JSONDecoder().decode(TvPlaybackSession.self, from: sessionJSON("cand-1"))
        vm.isResolving = false
        vm.sessionController.armFirstFrameFallbackWatchdog(timeoutNanoseconds: 30_000_000)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertNil(vm.sessionController.firstFrameFallbackTask)

        // Re-arm while first frame is already true to simulate a lingering timer crossing switchSource
        vm.sessionController.armFirstFrameFallbackWatchdog(timeoutNanoseconds: 30_000_000)
        var midLoadSnapshot: (holding: Bool, fallbackUnlocked: Bool, releaseCount: Int)?
        transport.onLoadStream = { _, _, _ in
            try await Task.sleep(nanoseconds: 60_000_000)
            midLoadSnapshot = (vm.sessionController.isHoldingOutgoingPicture, vm.firstFrameFallbackUnlocked, transport.releaseOutgoingPictureCallCount)
        }
        await vm.switchSource(to: "cand-2")
        let snap = try XCTUnwrap(midLoadSnapshot)
        XCTAssertTrue(snap.holding)
        XCTAssertFalse(snap.fallbackUnlocked)
        XCTAssertEqual(snap.releaseCount, 0)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        vm.hasFirstFrameReadyForDisplay = true
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertNil(vm.sessionController.firstFrameFallbackTask)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)
    }

    @MainActor
    func testSupersededBeginOutgoingPictureHoldDoesNotReleaseNewerActiveHold() async throws {
        let suite = "luna.test.supersededhold.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try AetherEngine()
        defer { PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset(); engine.stop(resetDisplayCriteria: true) }
        let transport = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let holdGate = TestStepGate()
        let holdLog = TestLockedBox<[String]>([])
        let calls = TestLockedBox(0)
        transport.onHoldOutgoingPicture = {
            if calls.withLock({ $0 += 1; return $0 }) == 1 { await holdGate.wait(label: "holdA", log: holdLog) }
            return true
        }
        let vm = PlayerViewModel(engine: engine, comfort: ComfortPreferences(defaults: defaults), transport: transport, bindOnInit: false)
        let taskA = Task { @MainActor in await vm.sessionController.beginOutgoingPictureHold() }
        await holdGate.waitUntilStarted()
        taskA.cancel()
        let tokenB = await vm.sessionController.beginOutgoingPictureHold()
        XCTAssertNotNil(tokenB)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertTrue(transport.isHoldingOutgoingPicture)
        await holdGate.finish()
        let tokenA = await taskA.value
        XCTAssertNil(tokenA)
        XCTAssertTrue(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertTrue(transport.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 0)
        vm.teardownAndStop()
        XCTAssertFalse(vm.sessionController.isHoldingOutgoingPicture)
        XCTAssertEqual(transport.releaseOutgoingPictureCallCount, 1)
    }
}
