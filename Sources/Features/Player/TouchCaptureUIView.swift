import UIKit

@MainActor
final class TouchCaptureUIView: UIView, UIGestureRecognizerDelegate {
    var isPlayingProvider: () -> Bool = { false }
    var isScrubbingProvider: () -> Bool = { false }
    var canLockHorizontalFocusProvider: () -> Bool = { true }
    var durationSecondsProvider: () -> Double = { 0 }
    var onLightTouch: (() -> Void)?
    var onScrubBegan: (() -> Void)?
    var onScrubChanged: ((_ deltaSeconds: Double) -> Void)?
    var onSelectClick: (() -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onRingHoldBegan: ((_ direction: Int) -> Void)?
    var onRingHoldEnded: ((_ cancelled: Bool) -> Void)?
    var onUpClick: (() -> Void)?
    var onDownClick: (() -> Void)?

    private enum PanAxis {
        case undecided
        case horizontalScrub
        case verticalCommand
    }

    private var panAxis: PanAxis = .undecided
    private var prevPanDx: Double = 0
    private var smoothedSpeedNorm: Double = 0
    private var lastDiscreteClickUptime: TimeInterval?
    private var didCommitDuringCurrentPan: Bool = false
    private var activeSelectPress: Bool = false
    private var activeRingDirection: Int?
    private var didEnterRingHold: Bool = false
    private var ringHoldTask: Task<Void, Never>?
    private var focusRetryTask: Task<Void, Never>?
    private var indirectPanRecognizer: UIPanGestureRecognizer?
    private var appliedCancelHoldNonce: Int = 0
    private var appliedFocusRequestNonce: Int = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override var canBecomeFocused: Bool { true }
    override var canBecomeFirstResponder: Bool { true }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if context.previouslyFocusedItem === self {
            if panAxis == .horizontalScrub || isScrubbingProvider() {
                return false
            }
            if canLockHorizontalFocusProvider(),
               (context.focusHeading == .left || context.focusHeading == .right) {
                return false
            }
        }
        return super.shouldUpdateFocus(in: context)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, canLockHorizontalFocusProvider() {
            scheduleDirectFocusAcquisition()
        } else if window == nil {
            focusRetryTask?.cancel()
            focusRetryTask = nil
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            focusRetryTask?.cancel()
            focusRetryTask = nil
            cancelActiveRingHold(cancelled: true)
            activeSelectPress = false
        }
    }

    private func configureSurface() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleIndirectPan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)
        indirectPanRecognizer = pan
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func applyFocusRequestNonce(_ nonce: Int) {
        guard nonce != appliedFocusRequestNonce else { return }
        appliedFocusRequestNonce = nonce
        guard nonce > 0, window != nil, canLockHorizontalFocusProvider() else { return }
        scheduleDirectFocusAcquisition()
    }

    func requestUIKitFocusOnce() {
        guard window != nil, !isFocused, canLockHorizontalFocusProvider() else { return }
        if let focusSystem = UIFocusSystem.focusSystem(for: self) {
            focusSystem.requestFocusUpdate(to: self)
            focusSystem.updateFocusIfNeeded()
        } else {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    private func scheduleDirectFocusAcquisition() {
        focusRetryTask?.cancel()
        requestUIKitFocusOnce()
        focusRetryTask = Task { @MainActor [weak self] in
            for delayNs: UInt64 in [16_000_000, 48_000_000, 120_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, let self, self.window != nil else { return }
                if self.isFocused || !self.canLockHorizontalFocusProvider() {
                    return
                }
                self.requestUIKitFocusOnce()
            }
        }
    }

    // MARK: - Indirect Touch (Wake OSD & Paused Adaptive Scrubbing)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { $0.type == .indirect }) {
            onLightTouch?()
        }
    }

    @objc private func handleIndirectPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panAxis = .undecided
            prevPanDx = 0
            smoothedSpeedNorm = 0
            didCommitDuringCurrentPan = false

        case .changed:
            guard !didCommitDuringCurrentPan else { return }
            let translation = recognizer.translation(in: self)
            let dx = Double(translation.x)
            let dy = Double(translation.y)

            switch panAxis {
            case .undecided:
                let distance = hypot(dx, dy)
                guard distance >= 14 else { return }

                if abs(dy) > abs(dx) * RemoteScrubMath.axisLockRatio, distance >= 42 {
                    panAxis = .verticalCommand
                    if dy > 0 { onDownClick?() } else { onUpClick?() }
                    return
                }

                let elapsedSinceClick = lastDiscreteClickUptime.map {
                    ProcessInfo.processInfo.systemUptime - $0
                }
                guard RemoteScrubMath.shouldActivateTouchScrub(
                    dx: dx,
                    dy: dy,
                    isPlaying: isPlayingProvider(),
                    isSelectPressed: activeSelectPress,
                    secondsSinceDiscreteClick: elapsedSinceClick
                ) else {
                    return
                }
                panAxis = .horizontalScrub
                prevPanDx = dx
                smoothedSpeedNorm = 0
                onScrubBegan?()

            case .horizontalScrub:
                guard !activeSelectPress else { return }
                let stepDx = dx - prevPanDx
                prevPanDx = dx
                let velocityX = Double(recognizer.velocity(in: self).x)
                smoothedSpeedNorm = RemoteScrubMath.smoothedSpeedNorm(
                    previous: smoothedSpeedNorm,
                    velocityXPointsPerSecond: velocityX
                )
                let delta = RemoteScrubMath.incrementalStepSeconds(
                    stepDxPoints: stepDx,
                    durationSeconds: durationSecondsProvider(),
                    speedNorm: smoothedSpeedNorm
                )
                if abs(delta) > 0.001 {
                    onScrubChanged?(delta)
                }

            case .verticalCommand:
                break
            }

        case .ended, .cancelled, .failed:
            panAxis = .undecided
            prevPanDx = 0
            smoothedSpeedNorm = 0
            didCommitDuringCurrentPan = false

        default:
            break
        }
    }

    // MARK: - Physical Clickpad & Ring Hold

    private static func isLocallyHandledPress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .select, .leftArrow, .rightArrow, .upArrow, .downArrow:
            return true
        default:
            return false
        }
    }

    private func beginRingArrowPress(direction: Int) {
        ringHoldTask?.cancel()
        activeRingDirection = direction
        didEnterRingHold = false
        let thresholdNs = UInt64(RemoteScrubMath.ringHoldThresholdSeconds * 1_000_000_000)
        ringHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: thresholdNs)
            guard !Task.isCancelled, let self, self.activeRingDirection == direction else { return }
            self.didEnterRingHold = true
            self.onRingHoldBegan?(direction)
        }
    }

    private func endRingArrowPress() {
        ringHoldTask?.cancel()
        ringHoldTask = nil
        guard let direction = activeRingDirection else { return }
        let held = didEnterRingHold
        activeRingDirection = nil
        didEnterRingHold = false
        if held {
            onRingHoldEnded?(false)
        } else if direction < 0 {
            onLeftClick?()
        } else {
            onRightClick?()
        }
    }

    private func cancelActiveRingHold(cancelled: Bool) {
        ringHoldTask?.cancel()
        ringHoldTask = nil
        let held = didEnterRingHold
        activeRingDirection = nil
        didEnterRingHold = false
        if held {
            onRingHoldEnded?(cancelled)
        }
    }

    func abortRingHoldWithoutCallback() {
        ringHoldTask?.cancel()
        ringHoldTask = nil
        activeRingDirection = nil
        didEnterRingHold = false
        didCommitDuringCurrentPan = true
    }

    func applyCancelHoldNonce(_ nonce: Int) {
        guard nonce != appliedCancelHoldNonce else { return }
        appliedCancelHoldNonce = nonce
        abortRingHoldWithoutCallback()
    }

    var hasActiveOrPendingRingPress: Bool {
        activeRingDirection != nil || didEnterRingHold || ringHoldTask != nil
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough = Set<UIPress>()

        for press in presses {
            if Self.isLocallyHandledPress(press.type) {
                lastDiscreteClickUptime = ProcessInfo.processInfo.systemUptime
            }
            switch press.type {
            case .select:
                activeSelectPress = true
            case .leftArrow:
                beginRingArrowPress(direction: -1)
            case .rightArrow:
                beginRingArrowPress(direction: 1)
            case .upArrow:
                onUpClick?()
            case .downArrow:
                onDownClick?()
            case .menu:
                abortRingHoldWithoutCallback()
                passthrough.insert(press)
            default:
                passthrough.insert(press)
            }
        }

        if !passthrough.isEmpty {
            super.pressesBegan(passthrough, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough = Set<UIPress>()

        for press in presses {
            switch press.type {
            case .select:
                if activeSelectPress {
                    activeSelectPress = false
                    let wasScrubbing = (panAxis == .horizontalScrub) || isScrubbingProvider()
                    onSelectClick?()
                    if wasScrubbing {
                        didCommitDuringCurrentPan = true
                    } else {
                        didCommitDuringCurrentPan = false
                        panAxis = .undecided
                        prevPanDx = 0
                        smoothedSpeedNorm = 0
                        indirectPanRecognizer?.setTranslation(.zero, in: self)
                    }
                }
            case .leftArrow, .rightArrow:
                endRingArrowPress()
            case .upArrow, .downArrow:
                break
            default:
                passthrough.insert(press)
            }
        }

        if !passthrough.isEmpty {
            super.pressesEnded(passthrough, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough = Set<UIPress>()

        for press in presses {
            switch press.type {
            case .select:
                activeSelectPress = false
            case .leftArrow, .rightArrow:
                cancelActiveRingHold(cancelled: true)
            case .upArrow, .downArrow:
                break
            default:
                passthrough.insert(press)
            }
        }

        if !passthrough.isEmpty {
            super.pressesCancelled(passthrough, with: event)
        }
    }
}
