import AetherBridge
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import XCTest
@testable import Luna

final class PlaybackAudioSessionAndQMSCriteriaTests: XCTestCase {
    func testNativeAudioSessionActivationOnlyAppliesToNativeRoutes() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .loopback))
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .remoteBypass))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .software))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .audio))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldActivateNativeAudioSession(for: .none))
    }

    func testDeferredDisplayCriteriaResetStatePredicate() {
        XCTAssertTrue(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .idle))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .loading))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .playing))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .paused))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .seeking))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .ended))
        XCTAssertFalse(PlayerAudioSessionCoordinator.shouldExecuteDeferredDisplayCriteriaReset(engineState: .error("err")))
    }

    @MainActor
    func testHeldDisplayCriteriaResetAndQMSMenuRefreshRateSafety() throws {
        final class ResetCounter {
            var count = 0
            var eligible = true
        }

        XCTAssertTrue(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: false
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: true,
                isShowingSourcePicker: false
            )
        )
        XCTAssertFalse(
            PlayerAudioSessionCoordinator.shouldFlushDeferredResetOnDetailDisappear(
                isLaunchingPlayback: false,
                isShowingSourcePicker: true
            )
        )

        let coordinator = PlayerAudioSessionCoordinator()
        let counter = ResetCounter()

        // Default fallback before any valid VSync tick is 60.0 Hz
        XCTAssertNil(coordinator.cachedMenuRefreshRateHz)
        XCTAssertEqual(coordinator.effectiveMenuRefreshRateHz, 60.0, accuracy: 0.001)

        // Invalid/zero/cinema rates must never be accepted as menu rates
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: nil))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 0))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: -60))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: .nan))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 23.976))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 24.0))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 25.0))
        XCTAssertNil(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 30.0))

        // Valid menu refresh rates snap cleanly to 50.0, 59.94, and 60.0 Hz
        XCTAssertEqual(try XCTUnwrap(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 50.01)), 50.0, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 59.94)),
            Float(60_000.0 / 1_001.0),
            accuracy: 0.001
        )
        XCTAssertEqual(try XCTUnwrap(PlayerAudioSessionCoordinator.snappedMenuRefreshRate(fromHz: 60.0)), 60.0, accuracy: 0.001)

        // Sample 50 Hz PAL menu while idle, then verify episode transition (preferredDisplayCriteria != nil / 23.976 Hz) never overwrites it
        XCTAssertTrue(
            coordinator.recordSampledMenuRefreshRate(
                rawHz: 50.0,
                hasPreferredDisplayCriteria: false,
                isDisplayModeSwitchInProgress: false,
                hasActivePlayback: false
            )
        )
        XCTAssertEqual(coordinator.effectiveMenuRefreshRateHz, 50.0, accuracy: 0.001)

        XCTAssertFalse(
            coordinator.recordSampledMenuRefreshRate(
                rawHz: 60.0,
                hasPreferredDisplayCriteria: true,
                isDisplayModeSwitchInProgress: false,
                hasActivePlayback: false
            )
        )
        XCTAssertFalse(
            coordinator.recordSampledMenuRefreshRate(
                rawHz: 23.976,
                hasPreferredDisplayCriteria: false,
                isDisplayModeSwitchInProgress: false,
                hasActivePlayback: false
            )
        )
        XCTAssertEqual(coordinator.effectiveMenuRefreshRateHz, 50.0, accuracy: 0.001)

        // Dolby Vision, HDR10, HDR10+ and HLG format descriptions carry BT.2020 + PQ/HLG extensions for QMS
        XCTAssertNil(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .sdr))
        let dvDesc = try XCTUnwrap(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .dolbyVision))
        let dvExts = try XCTUnwrap(CMFormatDescriptionGetExtensions(dvDesc) as? [CFString: Any])
        XCTAssertEqual(dvExts[kCMFormatDescriptionExtension_ColorPrimaries] as? String, kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        XCTAssertEqual(dvExts[kCMFormatDescriptionExtension_TransferFunction] as? String, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        XCTAssertEqual(dvExts[kCMFormatDescriptionExtension_YCbCrMatrix] as? String, kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
        let dvAtoms = try XCTUnwrap(dvExts[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Data])
        let dvcC = try XCTUnwrap(dvAtoms["dvcC"])
        XCTAssertEqual(dvcC.count, 24)
        XCTAssertEqual(Array(dvcC.prefix(5)), [0x01, 0x00, 0x10, 0x35, 0x10])

        let hlgDesc = try XCTUnwrap(PlayerAudioSessionCoordinator.hdrMenuFormatDescription(for: .hlg))
        let hlgExts = try XCTUnwrap(CMFormatDescriptionGetExtensions(hlgDesc) as? [CFString: Any])
        XCTAssertEqual(hlgExts[kCMFormatDescriptionExtension_TransferFunction] as? String, kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)

        // Held display criteria cancellation & detail disappear flush
        coordinator.holdDisplayCriteriaUntilBackground(
            shouldExecute: { true },
            performReset: { counter.count += 1 }
        )
        coordinator.cancelDeferredDisplayCriteriaReset()
        coordinator.flushDeferredDisplayCriteriaResetIfIdle()
        XCTAssertEqual(counter.count, 0)

        counter.eligible = false
        coordinator.holdDisplayCriteriaUntilBackground(
            shouldExecute: { counter.eligible },
            performReset: { counter.count += 1 }
        )
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 0)

        counter.eligible = true
        coordinator.handleDetailDisappear(isLaunchingPlayback: true, isShowingSourcePicker: false)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: true)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false, keepDisplayModeInMenu: true)
        XCTAssertEqual(counter.count, 0)

        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 1)
        coordinator.handleDetailDisappear(isLaunchingPlayback: false, isShowingSourcePicker: false)
        XCTAssertEqual(counter.count, 1)
    }
}
