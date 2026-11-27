import AetherBridge
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import MediaPlayer
import XCTest
@testable import Luna

final class PlayerLifecycleAndRestoreTests: XCTestCase {
    // MARK: - Shared Engine Invariants, NowPlaying, LoadOptions & Memory Mode

    @MainActor
    func testSharedEngineLoadOptionsUpscaleAttachmentsAndPlaybackMemoryMode() async throws {
        let host = "warm-memory-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.opts")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            ArtworkPipeline.shared.exitPlaybackMemoryMode()
            engineScope.stop()
            scope.cleanup()
        }

        let engine = engineScope.engine
        XCTAssertFalse(engine.deactivatesAudioSessionOnStop)
        XCTAssertEqual(engine.maximumSubtitleAdvanceSeconds, 0)
        XCTAssertEqual(engine.maximumSubtitleDelaySeconds, 10)
        XCTAssertTrue(engine.ownsSoftwareNowPlaying && engine.ownsVideoNowPlayingSession && engine.ownsVideoNowPlayingCommands)

        // NowPlaying metadata for generic episode code vs named episode
        let genericEp = PlayerTestFixtures.makeEpisodeSession(title: "S02E03")
        let genericNP = PlayerNowPlayingCoordinator.makeBaseInfo(for: genericEp)
        XCTAssertEqual(genericNP[MPMediaItemPropertyTitle] as? String, "S02E03")
        XCTAssertEqual(genericNP[MPMediaItemPropertyAlbumTitle] as? String, "Severance")
        XCTAssertEqual(genericNP[MPMediaItemPropertyMediaType] as? UInt, MPMediaType.tvShow.rawValue)

        let namedEp = PlayerTestFixtures.makeEpisodeSession(title: "401 Unauthorized")
        XCTAssertEqual(PlayerNowPlayingCoordinator.makeBaseInfo(for: namedEp)[MPMediaItemPropertyAlbumTitle] as? String, "Severance · S02E03")

        // A19 8 GB vs 4 GB standard LoadOptions, HDR10/DV panel gating, 1080p Lanczos & Vision OCR opt-in
        let high8GB = DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824, activeProcessorCount: 6)
        let standard4GB = DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 5)
        let highComfort = ComfortPreferences(defaults: scope.defaults, memoryTier: .high2026)
        highComfort.audioDelayMs = -45
        let binauralShaping = highComfort.buildAudioShaping(enhancement: .dialogueLift, binaural: true)
        XCTAssertTrue(binauralShaping.binaural)
        XCTAssertEqual(binauralShaping.dialogueGainDB, 4.0)

        let client = try MockURLProtocol.makeClient(host: host)
        let hdr10Session = PlayerTestFixtures.makeMovieSession(
            sizeBytes: 64_424_509_440, declaredDurationSeconds: 9960,
            preferDualLayerDolbyVision: true, foldsDolbyVisionFEL: true,
            objectAudioLayout: "5.1.2", skipsContainerAttachments: true
        )
        let hdr10OnlyCaps = DisplayCapabilities(supportsHDR: true, supportsDolbyVision: false, supportsHDR10: true, supportsHLG: true)
        let optsHigh = PlayerViewModel.buildLoadOptions(
            session: hdr10Session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: highComfort.audioDelaySeconds,
            displayCapabilities: hdr10OnlyCaps, memoryProfile: high8GB, availableMemoryBytes: 2_048 * 1_048_576
        )
        XCTAssertEqual(optsHigh.audioDelaySeconds, -0.045, accuracy: 0.0001)
        XCTAssertFalse(optsHigh.preferDualLayerDolbyVision || optsHigh.foldsDolbyVisionFEL)
        XCTAssertEqual(optsHigh.untaggedVideoColor, .hdr10)
        XCTAssertEqual(optsHigh.objectAudioRendering, .render(.l512))
        XCTAssertTrue(optsHigh.confirmAtmos && optsHigh.retainsSessionCacheAfterStop)
        XCTAssertEqual(optsHigh.maxConcurrentSourceRequests, 8)
        XCTAssertEqual(optsHigh.forwardBufferSegments, 45)
        XCTAssertFalse(optsHigh.skipsContainerAttachments || optsHigh.readsContainerAttachmentsAtOpen || optsHigh.recognizesBitmapSubtitleText)

        highComfort.recognizesBitmapSubtitleText = true
        let ocrHighOpts = PlayerEngineConfigurator.buildLoadOptions(
            session: hdr10Session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: high8GB, availableMemoryBytes: 2_200 * 1_048_576
        )
        let ocrStdOpts = PlayerEngineConfigurator.buildLoadOptions(
            session: hdr10Session, client: client, comfort: highComfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: standard4GB, availableMemoryBytes: 900 * 1_048_576
        )
        XCTAssertTrue(ocrHighOpts.recognizesBitmapSubtitleText)
        XCTAssertFalse(ocrStdOpts.recognizesBitmapSubtitleText || ocrStdOpts.retainsSessionCacheAfterStop || ocrStdOpts.confirmAtmos)

        // 1080p SDR Lanczos vs anime lineArt & single warm playback memory mode entry
        let sdr1080 = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-1080p-1", itemId: "movie:tmdb:603", tmdbId: 603, title: "The Matrix",
            resolution: "1080p", videoRangeType: "SDR", videoCodec: "h264", dolbyVisionHandling: "baseLayerOnly"
        )
        highComfort.lowResUpscaleMode = .off
        highComfort.upscalesFullHDVideo = true
        let optsLanczos = PlayerViewModel.buildLoadOptions(
            session: sdr1080, client: client, comfort: highComfort, audioEnhancement: .reference, audioDelaySeconds: 0, memoryProfile: high8GB
        )
        XCTAssertFalse(optsLanczos.upscalesLowResolutionVideo)
        XCTAssertEqual(optsLanczos.upscaleScaler, .lanczos)
        XCTAssertTrue(optsLanczos.upscalesFullHDVideo)
        XCTAssertTrue(PlayerViewModel.isLikelyHeavySoftwareSession(sdr1080, dualLayerOverride: .auto, lowResUpscaleMode: .auto, upscalesFullHDVideo: true, supportsHardwareAV1: true))

        let resolveRespData = try JSONEncoder().encode(
            TvResolveStartResponse(ok: true, resolveId: "res-warm", playbackSession: sdr1080)
        )
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, url.path == "/api/tv/v2/playback/resolve" ? resolveRespData : Data(#"{"ok":true}"#.utf8))
        }

        let purgeCount = TestLockedBox(0)
        let observer = NotificationCenter.default.addObserver(
            forName: ArtworkPipeline.didPurgeMemoryNotification, object: nil, queue: .main
        ) { _ in purgeCount.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }

        let transport = MockPlayerTransport()
        let vm = PlayerViewModel(engine: engine, comfort: highComfort, transport: transport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        vm.start(
            request: PlaybackLaunchRequest(itemId: "movie:tmdb:603", title: "The Matrix", startPositionSeconds: 0, prepareToken: "sess-1080p-1", preparedSession: sdr1080),
            client: client
        )
        await vm.sessionController.resolveTask?.value
        XCTAssertTrue(ArtworkPipeline.shared.isPlaybackActive)

        vm.adjustAudioDelay(byMs: 25)
        vm.flushPendingAudioDelayCommitIfNeeded()
        XCTAssertTrue(transport.events.contains("audioDelay(25ms)"))
        vm.adjustAudioDelay(byMs: 20)
        vm.teardownAndStop()
        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertFalse(transport.events.contains("audioDelay(45ms)"))
        XCTAssertLessThanOrEqual(purgeCount.withLock { $0 }, 1)
    }

    // MARK: - Exit Blink Guard, Superseded Owner, Deallocation & Early Curtain Abort

    @MainActor
    func testDismissalOwnerGuardMenuDisplayModeDeallocationAndStopReceipt() async throws {
        let host = "player-abort-\(UUID().uuidString.lowercased()).local"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.dismiss")
        let engineScope = try SharedTestEngineScope(configured: false)
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }
        let engine = engineScope.engine
        let comfort = ComfortPreferences(defaults: scope.defaults)

        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .playing, playbackPhase: .playing))
        XCTAssertTrue(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .rebuffering))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .paused, playbackPhase: .paused))
        XCTAssertFalse(PlayerViewModel.shouldPauseEngineOnDismiss(engineState: .idle, playbackPhase: .idle))

        // Superseded owner skips stop() so back-to-back player transition never stops new stream
        let t1 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let t2 = MockPlayerTransport(state: .playing, playbackPhase: .playing)
        let vm1 = PlayerViewModel(engine: engine, comfort: comfort, transport: t1)
        let vm2 = PlayerViewModel(engine: engine, comfort: comfort, transport: t2)
        vm1.start(request: PlaybackLaunchRequest(itemId: "episode:tmdb:100:s1:e1", title: "E1", seriesTitle: "Test", season: 1, episode: 1), client: nil)
        vm1.fatalError = nil
        vm1.playbackPhase = .playing
        vm1.prepareForDismissal()
        vm2.start(request: PlaybackLaunchRequest(itemId: "episode:tmdb:100:s1:e2", title: "E2", seriesTitle: "Test", season: 1, episode: 2), client: nil)
        XCTAssertFalse(PlayerAudioSessionCoordinator.shared.isCurrentEngineOwner(vm1.engineOwnerToken))
        vm1.teardownAndStop()
        XCTAssertEqual(t1.events, ["pause"])
        vm2.teardownAndStop()
        XCTAssertEqual(t2.events, ["stop(true,true)"])

        // menuDisplayMode .preserveExactMatch skips resetDisplayCriteria on foreground exit
        comfort.menuDisplayMode = .preserveExactMatch
        let optOutTransport = MockPlayerTransport()
        let optOutVM = PlayerViewModel(engine: engine, comfort: comfort, transport: optOutTransport)
        optOutVM.teardownAndStop()
        XCTAssertEqual(optOutTransport.events, ["stop(false,true)"])
        comfort.menuDisplayMode = .sdr60Hz

        // 12-cycle weak deallocation check across PlayerViewModel and all 5 @MainActor controllers
        for cycle in 0..<12 {
            weak var weakVM: PlayerViewModel?
            weak var weakSession: PlayerSessionController?
            weak var weakTrack: PlayerTrackController?
            weak var weakScrub: PlayerScrubController?
            weak var weakRestore: PlayerRestoreController?
            weak var weakQoS: PlayerQoSReporter?
            do {
                let vm = PlayerViewModel(engine: engine, comfort: comfort, transport: MockPlayerTransport(state: .playing, playbackPhase: .playing), bindOnInit: true)
                weakVM = vm; weakSession = vm.sessionController; weakTrack = vm.trackController
                weakScrub = vm.scrubController; weakRestore = vm.restoreController; weakQoS = vm.qosReporter
                vm.start(request: PlaybackLaunchRequest(itemId: "episode:tmdb:95396:s1:e\(cycle + 1)", title: "E\(cycle + 1)"), client: nil)
                vm.prepareForDismissal()
                vm.teardownAndStop()
            }
            XCTAssertNil(weakVM)
            XCTAssertNil(weakSession)
            XCTAssertNil(weakTrack)
            XCTAssertNil(weakScrub)
            XCTAssertNil(weakRestore)
            XCTAssertNil(weakQoS)
        }

        // Early Back abort during resolving curtain sends stopped heartbeat + StopReceipt delivery
        let resolveGate = TestStepGate()
        let gateLog = TestLockedBox<[String]>([])
        let stoppedHeartbeats = TestLockedBox(0)
        MockURLProtocol.registerAsync(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                await resolveGate.wait(label: "resolve", log: gateLog)
                return (resp, Data(#"{"ok":false,"status":"failed","resolveId":"r1"}"#.utf8))
            }
            if url.path == "/api/tv/v2/playback/heartbeat" {
                stoppedHeartbeats.withLock { $0 += 1 }
                return (resp, Data(#"{"ok":true,"sessionId":"sess-ep-1","state":"stopped","watchCompleted":true}"#.utf8))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let client = try MockURLProtocol.makeClient(host: host)
        let vmAbort = PlayerViewModel(engine: engine, comfort: comfort, transport: MockPlayerTransport())
        vmAbort.start(request: PlaybackLaunchRequest(itemId: "movie:tmdb:550", title: "Fight Club", prepareToken: "tvs_handed_1"), client: client)
        await resolveGate.waitUntilStarted()
        let abortDone = expectation(description: "Stopped heartbeat sent on early curtain abort")
        vmAbort.prepareForDismissal()
        vmAbort.teardownAndStop { abortDone.fulfill() }
        await resolveGate.finish()
        await fulfillment(of: [abortDone], timeout: 3.0)
        XCTAssertEqual(stoppedHeartbeats.withLock { $0 }, 1)

        let vmReceipt = PlayerViewModel(engine: engine, comfort: comfort, transport: MockPlayerTransport(state: .playing, playbackPhase: .playing, currentTime: 1850), bindOnInit: false)
        vmReceipt.activeSession = PlayerTestFixtures.makeEpisodeSession(season: 2, episode: 5, runtimeSeconds: 2800)
        vmReceipt.activeClient = client
        vmReceipt.durationSeconds = 2800
        let receiptExp = expectation(description: "Stop receipt delivered")
        var capturedReceipt: PlaybackStopReceipt?
        vmReceipt.prepareForDismissal()
        vmReceipt.teardownAndStop(onComplete: { receiptExp.fulfill() }, onStopReceipt: { capturedReceipt = $0 })
        await fulfillment(of: [receiptExp], timeout: 3.0)
        XCTAssertEqual(capturedReceipt?.seasonNumber, 2)
        XCTAssertEqual(capturedReceipt?.episodeNumber, 5)
        XCTAssertEqual(capturedReceipt?.completed, true)
    }

    @MainActor
    func testOutgoingPictureHoldWarmPromotionAndStaleWatchdogGuards() async throws {
        let host = "warm-promo-\(UUID().uuidString.lowercased()).invalid"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.hold")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }
        let engine = engineScope.engine
        let comfort = ComfortPreferences(defaults: scope.defaults)

        let prepSession = PlayerTestFixtures.makeMovieSession(sessionId: "sess-prep-1", candidateId: "cand-1")
        let promoSession = PlayerTestFixtures.makeMovieSession(sessionId: "sess-promo-2", candidateId: "cand-2")
        let switchedSession = PlayerTestFixtures.makeMovieSession(sessionId: "sess-switch-3", candidateId: "cand-3")
        let promoObj = try PlayerTestFixtures.sessionJSONObject(promoSession)
        let switchObj = try PlayerTestFixtures.sessionJSONObject(switchedSession)

        MockURLProtocol.register(host: host) { request in
            let url = try XCTUnwrap(request.url)
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            if url.path == "/api/tv/v2/playback/resolve" {
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "status": "ready", "resolveId": "res-promo-2", "playbackSession": promoObj]))
            }
            if url.path.hasSuffix("/switch") {
                return (resp, try JSONSerialization.data(withJSONObject: ["ok": true, "playbackSession": switchObj]))
            }
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let promoTransport = MockPlayerTransport(state: .playing, playbackPhase: .playing, videoRoute: .loopback, currentTime: 100)
        let promoVM = PlayerViewModel(engine: engine, comfort: comfort, transport: promoTransport, audioActivator: MockNativeAudioActivator { _ in }, bindOnInit: false)
        let promoClient = try MockURLProtocol.makeClient(host: host)
        promoVM.activeClient = promoClient

        await promoVM.sessionController.runResolveAndLoad(
            request: PlaybackLaunchRequest(itemId: prepSession.item.itemId, title: prepSession.item.title, prepareToken: "sess-prep-1", preparedSession: prepSession),
            client: promoClient
        )
        XCTAssertEqual(promoVM.activeSession?.sessionId, "sess-promo-2")
        XCTAssertTrue(promoVM.sessionController.isHoldingOutgoingPicture)
        promoVM.hasFirstFrameReadyForDisplay = true
        XCTAssertFalse(promoVM.sessionController.isHoldingOutgoingPicture)

        // Stale first-frame watchdog does not drop outgoing hold mid-switch
        promoVM.sessionController.armFirstFrameFallbackWatchdog(timeoutNanoseconds: 25_000_000)
        var midLoadHolding = false
        promoTransport.onLoadStream = { _, _, _ in
            try await Task.sleep(nanoseconds: 55_000_000)
            midLoadHolding = promoVM.sessionController.isHoldingOutgoingPicture
        }
        await promoVM.switchSource(to: "cand-3")
        XCTAssertTrue(midLoadHolding)
        promoVM.fatalError = "Avspillingsfeil"
        XCTAssertFalse(promoVM.sessionController.isHoldingOutgoingPicture)
        promoVM.teardownAndStop()
    }

    // MARK: - AudioSession Coordinator, QMS / HDR Menu Criteria & Foreground Restore

    @MainActor
    func testAudioSessionQMSMenuCriteriaPausedRestoreOrderingAndForegroundRestore() async throws {
        let host = "restore-subs-\(UUID().uuidString.lowercased()).invalid"
        let scope = try IsolatedDefaultsScope(prefix: "luna.test.restore")
        let engineScope = try SharedTestEngineScope()
        defer {
            MockURLProtocol.unregister(host: host)
            engineScope.stop()
            scope.cleanup()
        }
        let engine = engineScope.engine

        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .loopback))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .remoteBypass))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .software))
        XCTAssertTrue(PlayerAudioSessionCoordinator.isBinauralAudioRoute(portTypes: [.bluetoothA2DP]))
        XCTAssertFalse(PlayerAudioSessionCoordinator.isBinauralAudioRoute(portTypes: [.HDMI]))

        let coordinator = PlayerAudioSessionCoordinator()
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 23.976))
        XCTAssertEqual(try XCTUnwrap(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 50.01)), 50.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 59.94)), Float(60_000.0 / 1_001.0), accuracy: 0.001)
        XCTAssertTrue(coordinator.recordSampledMenuRefreshRate(rawHz: 50.0, hasPreferredDisplayCriteria: false, isDisplayModeSwitchInProgress: false, hasActivePlayback: false))
        XCTAssertEqual(coordinator.effectiveMenuRefreshRateHz, 50.0, accuracy: 0.001)

        XCTAssertNil(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .sdr))
        let dvDesc = try XCTUnwrap(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .dolbyVision))
        let dvExts = try XCTUnwrap(CMFormatDescriptionGetExtensions(dvDesc) as? [CFString: Any])
        let dvAtoms = try XCTUnwrap(dvExts[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Data])
        XCTAssertEqual(Array(try XCTUnwrap(dvAtoms["dvcC"]).prefix(5)), [0x01, 0x00, 0x10, 0x35, 0x10])
        XCTAssertNotNil(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .hlg))

        var resetCount = 0
        coordinator.holdDisplayCriteriaUntilBackground(shouldExecute: { true }, performReset: { resetCount += 1 })
        coordinator.handleDetailDisappear(isLaunchingPlayback: true, isShowingSourcePicker: false)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false, keepDisplayModeInMenu: true)
        XCTAssertEqual(resetCount, 0)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(resetCount, 1)

        // Paused restore: off-main native audio activation strictly precedes play() and respects cancellation
        let log = TestLockedBox<[String]>([])
        let gate = TestStepGate()
        let pausedTransport = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        pausedTransport.onPlay = { log.withLock { $0.append("play") } }
        let comfort = ComfortPreferences(defaults: scope.defaults, memoryTier: .standard)
        let pausedVM = PlayerViewModel(
            engine: engine, comfort: comfort, transport: pausedTransport,
            audioActivator: MockNativeAudioActivator { _ in await gate.wait(label: "activate", log: log) }
        )
        pausedVM.isResolving = false
        pausedVM.needsNativeAudioActivationAfterPausedRestore = true
        pausedVM.togglePlayPause()
        await gate.waitUntilStarted()
        let task1 = pausedVM.pausedRestoreResumeTask
        await gate.finish()
        await task1?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end", "play"])
        XCTAssertFalse(pausedVM.needsNativeAudioActivationAfterPausedRestore)

        log.withLock { $0.removeAll() }
        await gate.reset()
        pausedTransport.state = .paused; pausedTransport.playbackPhase = .paused
        pausedVM.needsNativeAudioActivationAfterPausedRestore = true
        pausedVM.togglePlayPause()
        await gate.waitUntilStarted()
        let task2 = pausedVM.pausedRestoreResumeTask
        pausedVM.handleScenePhaseChange(.background)
        await gate.finish()
        await task2?.value
        XCTAssertEqual(log.withLock { $0 }, ["activate_start", "activate_end"])
        pausedVM.teardownAndStop()

        // Foreground restore reloads options with external subtitles + wireless lip-sync zeroing + stereo 2.0 binaural suppression
        comfort.audioDelayMs = -50
        comfort.lowResUpscaleMode = .animeLineArt
        let extSub = TvExternalSubtitle(id: "ext-nob-1", url: "/api/tv/v2/subtitles/sess-r1/0/nob.srt", format: "srt", language: "nob", name: "Norsk", isDefault: true)
        let restoreSession = PlayerTestFixtures.makeMovieSession(
            sessionId: "sess-r1", startPositionSeconds: 120,
            tracks: TvSessionTracks(externalSubtitles: [extSub]),
            objectAudioLayout: "2.0"
        )
        let client = try MockURLProtocol.makeClient(host: host)
        let restoreTransport = MockPlayerTransport(state: .paused, playbackPhase: .paused, videoRoute: .loopback, currentTime: 420, needsForegroundVideoRestore: true)
        let restoreVM = PlayerViewModel(engine: engine, comfort: comfort, transport: restoreTransport, bindOnInit: false)
        restoreVM.activeSession = restoreSession
        restoreVM.activeClient = client
        restoreVM.isResolving = false
        restoreVM.lastForegroundPlaybackWasPlaying = true
        restoreVM.sessionController.isHoldingOutgoingPicture = true
        restoreTransport.isHoldingOutgoingPicture = true

        restoreVM.handleAudioRouteChange(isWirelessOverride: true, isBinauralOverride: true)
        XCTAssertEqual(restoreTransport.lastAudioDelaySeconds, 0)
        restoreVM.handleAudioRouteChange(isWirelessOverride: false, isBinauralOverride: false)
        XCTAssertEqual(restoreTransport.events.last, "audioDelay(-50ms)")

        restoreVM.handleScenePhaseChange(.active)
        await restoreVM.restoreController.foregroundRestoreTask?.value
        XCTAssertEqual(restoreTransport.reloadCallCount, 1)
        XCTAssertEqual(restoreTransport.lastReloadedOptions?.externalSubtitles.count, 1)
        XCTAssertEqual(restoreTransport.lastReloadedOptions?.upscaleScaler, .lineArt)
        XCTAssertEqual(restoreTransport.releaseOutgoingPictureCallCount, 1)
        XCTAssertEqual(restoreTransport.state, .playing)

        let stereoOpts = PlayerEngineConfigurator.buildLoadOptions(
            session: restoreSession, client: client, comfort: comfort,
            audioEnhancement: .reference, audioDelaySeconds: 0, binauralAudioActive: true
        )
        XCTAssertEqual(stereoOpts.objectAudioRendering, .off)
        XCTAssertFalse(stereoOpts.audioShaping.binaural)
        XCTAssertEqual(stereoOpts.audioShaping.maxChannels, 2)
    }
}
