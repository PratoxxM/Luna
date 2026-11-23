import Foundation
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import QuartzCore
import UIKit
import AetherBridge
import os

private final class MenuDisplayLinkTarget: NSObject {
    let onTick: (CADisplayLink) -> Void

    init(onTick: @escaping (CADisplayLink) -> Void) {
        self.onTick = onTick
    }

    @objc func handleTick(_ link: CADisplayLink) {
        onTick(link)
    }
}

private actor NativeAudioSessionActivator {
    private let logger = Logger(subsystem: "local.lunacore.luna", category: "AudioSession")

    /// Activates the shared `AVAudioSession` off-main for bare `AVPlayerLayer` native routes.
    /// `AetherEngine` owns category/policy/multichannel configuration on first load and activates
    /// `.software` / `.audio` paths itself (`activateRendererAudioSession`). When `deactivatesAudioSessionOnStop`
    /// is enabled, final stop deactivates the session, so native `AVPlayerLayer` playback ensures
    /// the session is active once `engine.load(...)` completes without mutating category or mode.
    func ensureActiveOffMain() {
        guard !Task.isCancelled else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.warning("Failed to activate native AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Aligns `AVAudioSession` native-layer activation, QMS menu refresh-rate preservation,
/// wireless route lip-sync compensation, and held HDMI display-criteria resets with `AetherEngine` 7.73.0.
@MainActor
final class PlayerAudioSessionCoordinator {
    static let shared = PlayerAudioSessionCoordinator()

    nonisolated static let fallbackMenuRefreshRateHz: Float = 60.0
    nonisolated static let wirelessCompensatedPortTypes: Set<AVAudioSession.Port> = [
        .bluetoothA2DP,
        .bluetoothLE,
        .bluetoothHFP,
        .airPlay,
    ]

    private let activator = NativeAudioSessionActivator()
    private var activeEngineOwnerToken: UInt64 = 0
    private var isHoldingDisplayCriteriaReset: Bool = false
    private var pendingResetCheck: (@MainActor () -> Bool)?
    private var pendingResetAction: (@MainActor () -> Void)?
    private(set) var cachedMenuRefreshRateHz: Float?
    private var menuRateDisplayLink: CADisplayLink?
    private var menuRateTickCount: Int = 0

    init() {}

    @discardableResult
    func claimEngineOwnership() -> UInt64 {
        activeEngineOwnerToken &+= 1
        if activeEngineOwnerToken == 0 {
            activeEngineOwnerToken = 1
        }
        return activeEngineOwnerToken
    }

    func isCurrentEngineOwner(_ token: UInt64) -> Bool {
        token == 0 || activeEngineOwnerToken == token
    }

    /// Only native `AVPlayerLayer` routes (`.loopback`, `.remoteBypass`) bypass `AVPlayerViewController`
    /// and `AetherEngine`'s renderer activation. `.software` and `.audio` are activated by the engine.
    nonisolated static func shouldActivateNativeAudioSession(for videoRoute: VideoRoute) -> Bool {
        switch videoRoute {
        case .loopback, .remoteBypass:
            return true
        case .software, .audio, .none:
            return false
        }
    }

    /// Only reset display criteria once the singleton engine is genuinely idle so a held reset
    /// never interrupts a follow-up playback load or active session.
    nonisolated static func shouldExecuteDeferredDisplayCriteriaReset(engineState: PlaybackState) -> Bool {
        engineState == .idle
    }

    nonisolated static func shouldFlushDeferredResetOnDetailDisappear(
        isLaunchingPlayback: Bool,
        isShowingSourcePicker: Bool,
        keepDisplayModeInMenu: Bool = false
    ) -> Bool {
        !keepDisplayModeInMenu && !isLaunchingPlayback && !isShowingSourcePicker
    }

    nonisolated static func shouldResetDisplayCriteriaOnPlayerExit(
        menuDisplayMode: MenuDisplayMode,
        videoFormat: VideoFormat,
        isForegroundActive: Bool = true
    ) -> Bool {
        guard isForegroundActive else { return true }
        switch menuDisplayMode {
        case .sdr60Hz:
            return true
        case .preserveHDR60HzQMS:
            return videoFormat == .sdr
        case .preserveExactMatch:
            return false
        }
    }

    nonisolated static func shouldResetHeldDisplayCriteriaOnScenePhase(
        isBackgroundScene: Bool,
        hasActivePlayback: Bool,
        engineState: PlaybackState
    ) -> Bool {
        isBackgroundScene && !hasActivePlayback && engineState == .idle
    }

    nonisolated static func isWirelessCompensatedRoute(portTypes: [AVAudioSession.Port]) -> Bool {
        portTypes.contains { wirelessCompensatedPortTypes.contains($0) }
    }

    nonisolated static func effectiveAudioDelaySeconds(
        configuredDelaySeconds: Double,
        isWirelessRoute: Bool
    ) -> Double {
        isWirelessRoute ? 0.0 : configuredDelaySeconds
    }

    nonisolated static func currentOutputUsesWirelessCompensation() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return isWirelessCompensatedRoute(portTypes: outputs.map(\.portType))
    }

    /// Snaps a measured VSync refresh rate strictly to valid tvOS HDMI menu rates
    /// (`50.0`, `59.94`, or `60.0 Hz`), rejecting cinema rates (`23.976` / `24` / `25` / `30`)
    /// and invalid/zero `CADisplayLink` readings before the first VSync tick.
    nonisolated static func snappedMenuRefreshRate(fromHz rawHz: Double?) -> Float? {
        guard let rawHz, rawHz.isFinite, rawHz > 0 else { return nil }
        if (49.5...50.5).contains(rawHz) {
            return 50.0
        }
        if (59.88..<59.97).contains(rawHz) {
            return Float(60_000.0 / 1_001.0)
        }
        if (59.97...60.5).contains(rawHz) {
            return 60.0
        }
        return nil
    }

    nonisolated static func canSampleMenuRefreshRate(
        hasPreferredDisplayCriteria: Bool,
        isDisplayModeSwitchInProgress: Bool,
        hasActivePlayback: Bool
    ) -> Bool {
        !hasPreferredDisplayCriteria && !isDisplayModeSwitchInProgress && !hasActivePlayback
    }

    @discardableResult
    func recordSampledMenuRefreshRate(
        rawHz: Double,
        hasPreferredDisplayCriteria: Bool,
        isDisplayModeSwitchInProgress: Bool,
        hasActivePlayback: Bool
    ) -> Bool {
        guard Self.canSampleMenuRefreshRate(
            hasPreferredDisplayCriteria: hasPreferredDisplayCriteria,
            isDisplayModeSwitchInProgress: isDisplayModeSwitchInProgress,
            hasActivePlayback: hasActivePlayback
        ), let snapped = Self.snappedMenuRefreshRate(fromHz: rawHz) else {
            return false
        }
        cachedMenuRefreshRateHz = snapped
        return true
    }

    func sampleMenuRefreshRateIfIdle(hasActivePlayback: Bool = false) {
        guard menuRateDisplayLink == nil,
              let window = Self.activeKeyWindow() else {
            return
        }
        let dm = window.avDisplayManager
        guard Self.canSampleMenuRefreshRate(
            hasPreferredDisplayCriteria: dm.preferredDisplayCriteria != nil,
            isDisplayModeSwitchInProgress: dm.isDisplayModeSwitchInProgress,
            hasActivePlayback: hasActivePlayback
        ) else {
            return
        }

        menuRateTickCount = 0
        let target = MenuDisplayLinkTarget { [weak self] link in
            MainActor.assumeIsolated {
                self?.handleMenuDisplayLinkTick(link)
            }
        }
        let link = CADisplayLink(target: target, selector: #selector(MenuDisplayLinkTarget.handleTick(_:)))
        menuRateDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func handleMenuDisplayLinkTick(_ link: CADisplayLink) {
        guard let window = Self.activeKeyWindow() else {
            stopMenuRateSampling()
            return
        }
        let dm = window.avDisplayManager
        guard Self.canSampleMenuRefreshRate(
            hasPreferredDisplayCriteria: dm.preferredDisplayCriteria != nil,
            isDisplayModeSwitchInProgress: dm.isDisplayModeSwitchInProgress,
            hasActivePlayback: false
        ) else {
            stopMenuRateSampling()
            return
        }

        menuRateTickCount += 1
        if menuRateTickCount > 8 {
            stopMenuRateSampling()
            return
        }

        guard link.timestamp > 0 else { return }
        let dt = link.targetTimestamp - link.timestamp
        guard dt > 0 else { return }

        _ = recordSampledMenuRefreshRate(
            rawHz: 1.0 / dt,
            hasPreferredDisplayCriteria: false,
            isDisplayModeSwitchInProgress: false,
            hasActivePlayback: false
        )
        stopMenuRateSampling()
    }

    func stopMenuRateSampling() {
        menuRateDisplayLink?.invalidate()
        menuRateDisplayLink = nil
        menuRateTickCount = 0
    }

    nonisolated static func hdrMenuFormatDescription(for videoFormat: VideoFormat) -> CMVideoFormatDescription? {
        guard videoFormat != .sdr else { return nil }
        let transferFunction: CFString = switch videoFormat {
        case .hlg:
            kCVImageBufferTransferFunction_ITU_R_2100_HLG
        default:
            kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        }
        var extDict: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction: transferFunction,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_2020,
        ]
        if videoFormat == .dolbyVision {
            // Canonical 24-byte DOVIDecoderConfigurationRecord (`dvcC`) for Profile 8.1 @ Level 06 (4K60):
            // major=1, minor=0, profile=8 (0b0001000), level=6 (0b000110), rpu=1, el=0, bl=1 -> 0x1035, compat=1 -> 0x10.
            var doviConfig = [UInt8](repeating: 0, count: 24)
            doviConfig[0] = 0x01
            doviConfig[1] = 0x00
            doviConfig[2] = 0x10
            doviConfig[3] = 0x35
            doviConfig[4] = 0x10
            extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] = [
                "dvcC": Data(doviConfig),
            ] as NSDictionary
        }
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: (videoFormat == .dolbyVision) ? CMVideoCodecType(0x64766831) : kCMVideoCodecType_HEVC,
            width: 3840,
            height: 2160,
            extensions: extDict as NSDictionary,
            formatDescriptionOut: &formatDesc
        )
        return formatDesc
    }

    var effectiveMenuRefreshRateHz: Float {
        cachedMenuRefreshRateHz ?? Self.fallbackMenuRefreshRateHz
    }

    func activateNativePlaybackIfNeeded(videoRoute: VideoRoute) async {
        guard !Task.isCancelled, Self.shouldActivateNativeAudioSession(for: videoRoute) else {
            return
        }
        await activator.ensureActiveOffMain()
    }

    func cancelDeferredDisplayCriteriaReset() {
        isHoldingDisplayCriteriaReset = false
        pendingResetCheck = nil
        pendingResetAction = nil
    }

    func applyMenu60HzHDRCriteriaIfNeeded(videoFormat: VideoFormat) {
        guard let desc = Self.hdrMenuFormatDescription(for: videoFormat),
              let window = Self.activeKeyWindow() else {
            return
        }
        let displayManager = window.avDisplayManager
        guard displayManager.isDisplayCriteriaMatchingEnabled else { return }
        stopMenuRateSampling()
        displayManager.preferredDisplayCriteria = AVDisplayCriteria(
            refreshRate: effectiveMenuRefreshRateHz,
            formatDescription: desc
        )
    }

    private static func activeKeyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    func holdDisplayCriteriaUntilBackground(engine: AetherEngine) {
        holdDisplayCriteriaUntilBackground(
            shouldExecute: { [weak engine] in
                guard let engine else { return false }
                return Self.shouldExecuteDeferredDisplayCriteriaReset(engineState: engine.state)
            },
            performReset: { [weak engine] in
                engine?.stop(resetDisplayCriteria: true)
                Self.activeKeyWindow()?.avDisplayManager.preferredDisplayCriteria = nil
            }
        )
    }

    func holdDisplayCriteriaUntilBackground(
        shouldExecute: @escaping @MainActor () -> Bool,
        performReset: @escaping @MainActor () -> Void
    ) {
        cancelDeferredDisplayCriteriaReset()
        isHoldingDisplayCriteriaReset = true
        pendingResetCheck = shouldExecute
        pendingResetAction = performReset
    }

    func handleDetailDisappear(
        isLaunchingPlayback: Bool,
        isShowingSourcePicker: Bool,
        keepDisplayModeInMenu: Bool = false
    ) {
        guard Self.shouldFlushDeferredResetOnDetailDisappear(
            isLaunchingPlayback: isLaunchingPlayback,
            isShowingSourcePicker: isShowingSourcePicker,
            keepDisplayModeInMenu: keepDisplayModeInMenu
        ) else {
            return
        }
        flushDeferredDisplayCriteriaResetIfIdle()
    }

    func flushDeferredDisplayCriteriaResetIfIdle() {
        guard isHoldingDisplayCriteriaReset else { return }
        if pendingResetCheck?() == true {
            executePendingResetIfEligible()
        }
    }

    func flushDeferredDisplayCriteriaResetIfIdle(engine: AetherEngine) {
        guard isHoldingDisplayCriteriaReset else { return }
        if Self.shouldExecuteDeferredDisplayCriteriaReset(engineState: engine.state) {
            executePendingResetIfEligible()
        }
    }

    private func executePendingResetIfEligible() {
        let shouldExecute = pendingResetCheck
        let action = pendingResetAction
        isHoldingDisplayCriteriaReset = false
        pendingResetCheck = nil
        pendingResetAction = nil
        if shouldExecute?() == true {
            action?()
        }
    }
}
