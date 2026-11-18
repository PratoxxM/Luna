import AetherBridge
import Foundation
import XCTest
@testable import Luna

final class PausedScrubCommitTests: XCTestCase {
    @MainActor
    func testCommitTouchScrubOrdersSeekThenNativeAudioActivationThenPlayAndRespectsCancellation() async throws {
        let suite = "luna.test.scrubcommit.\(UUID().uuidString)"
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

        let log = TestLockedBox<[String]>([])
        let seekGate = TestStepGate()
        let audioGate = TestStepGate()

        let transport = MockPlayerTransport(state: .paused, playbackPhase: .paused)
        transport.onSeek = { target, _ in
            await seekGate.wait(label: "seek(\(Int(target)))", log: log)
        }
        transport.onPlay = {
            log.withLock { $0.append("play") }
        }
        let activator = MockNativeAudioActivator { _ in
            await audioGate.wait(label: "activate", log: log)
        }

        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: transport,
            audioActivator: activator
        )
        vm.isResolving = false
        vm.durationSeconds = 180

        // 1. Happy path: seek -> native audio activation -> play
        vm.needsNativeAudioActivationAfterPausedRestore = true
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 42)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        XCTAssertEqual(log.withLock { $0 }, ["seek(42)_start"])
        let task1 = vm.scrubCommitTask
        XCTAssertNotNil(task1)

        await seekGate.finish()
        await audioGate.waitUntilStarted()
        XCTAssertEqual(log.withLock { $0 }, ["seek(42)_start", "seek(42)_end", "activate_start"])

        await audioGate.finish()
        await task1?.value
        XCTAssertEqual(
            log.withLock { $0 },
            ["seek(42)_start", "seek(42)_end", "activate_start", "activate_end", "play"]
        )
        XCTAssertFalse(vm.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertNil(vm.scrubCommitTask)

        // 2. Pressing togglePlayPause while seek is in flight cancels commit before audio activation or play
        log.withLock { $0.removeAll() }
        await seekGate.reset()
        await audioGate.reset()
        transport.state = .paused
        transport.playbackPhase = .paused
        vm.needsNativeAudioActivationAfterPausedRestore = true
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 15)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task2 = vm.scrubCommitTask
        vm.togglePlayPause()
        XCTAssertNil(vm.scrubCommitTask)
        await seekGate.finish()
        await task2?.value
        XCTAssertEqual(log.withLock { $0 }, ["seek(15)_start", "seek(15)_end"])
        XCTAssertTrue(vm.needsNativeAudioActivationAfterPausedRestore)

        // 3. Starting another scrub while activation is in flight cancels the previous commit before play
        log.withLock { $0.removeAll() }
        await seekGate.reset()
        await audioGate.reset()
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 30)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task3 = vm.scrubCommitTask
        await seekGate.finish()
        await audioGate.waitUntilStarted()
        vm.beginTouchScrub()
        XCTAssertNil(vm.scrubCommitTask)
        await audioGate.finish()
        await task3?.value
        XCTAssertEqual(
            log.withLock { $0 },
            ["seek(30)_start", "seek(30)_end", "activate_start", "activate_end"]
        )
        XCTAssertTrue(vm.needsNativeAudioActivationAfterPausedRestore)
        vm.cancelTouchScrub()

        // 4. Backgrounding during seek blocks subsequent activation and play
        log.withLock { $0.removeAll() }
        await seekGate.reset()
        await audioGate.reset()
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 60)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task4 = vm.scrubCommitTask
        vm.handleScenePhaseChange(.background)
        await seekGate.finish()
        await task4?.value
        XCTAssertEqual(log.withLock { $0 }, ["seek(60)_start", "seek(60)_end"])
        XCTAssertNil(vm.scrubCommitTask)

        // 5. Teardown during activation blocks play and clears flag
        log.withLock { $0.removeAll() }
        await seekGate.reset()
        await audioGate.reset()
        vm.handleScenePhaseChange(.active)
        vm.beginTouchScrub()
        vm.stepTouchScrub(by: 75)
        vm.commitTouchScrub()
        await seekGate.waitUntilStarted()
        let task5 = vm.scrubCommitTask
        await seekGate.finish()
        await audioGate.waitUntilStarted()
        vm.teardownAndStop()
        await audioGate.finish()
        await task5?.value
        XCTAssertEqual(
            log.withLock { $0 },
            ["seek(75)_start", "seek(75)_end", "activate_start", "activate_end"]
        )
        XCTAssertFalse(vm.needsNativeAudioActivationAfterPausedRestore)
        XCTAssertNil(vm.scrubCommitTask)
    }

    @MainActor
    func testCancelledTaskSkipsNativeAudioActivationCoordinator() async {
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await PlayerAudioSessionCoordinator.shared.activateNativePlaybackIfNeeded(videoRoute: .loopback)
        }
        task.cancel()
        await task.value
    }
}
