import SwiftUI
import UIKit

/// Invisible UIKit focus & touch capture surface for tvOS playback (`zIndex: 1.5`).
///
/// Why UIKit instead of a SwiftUI `Button`:
/// - Overrides `focusEffect = nil` on `UIView` (combined with `.focusEffectDisabled()` in SwiftUI)
///   so tvOS 18 / tvOS 26 Liquid Glass **never** draws a bright white focus rectangle over the video.
/// - Captures continuous `UITouch.TouchType.indirect` thumb movement on the Siri Remote clickpad
///   for smooth 60/120 Hz velocity-aware timeline scrubbing, light-touch OSD wake, vertical swipe-down
///   for the top drawer, and crisp physical ring/center clicks.
@MainActor
struct SiriRemoteTouchSurface: UIViewRepresentable {
    let onLightTouch: () -> Void
    let onScrubBegan: () -> Void
    let onScrubChanged: (_ deltaPoints: CGFloat, _ velocityPointsPerSec: CGFloat) -> Void
    let onScrubTouchLifted: () -> Void
    let onSelectClick: () -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onUpClick: () -> Void
    let onDownClick: () -> Void

    func makeUIView(context: Context) -> TouchCaptureUIView {
        let view = TouchCaptureUIView()
        updateCallbacks(on: view)
        return view
    }

    func updateUIView(_ uiView: TouchCaptureUIView, context: Context) {
        updateCallbacks(on: uiView)
    }

    private func updateCallbacks(on view: TouchCaptureUIView) {
        view.onLightTouch = onLightTouch
        view.onScrubBegan = onScrubBegan
        view.onScrubChanged = onScrubChanged
        view.onScrubTouchLifted = onScrubTouchLifted
        view.onSelectClick = onSelectClick
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onUpClick = onUpClick
        view.onDownClick = onDownClick
    }
}

@MainActor
final class TouchCaptureUIView: UIView {
    var onLightTouch: (() -> Void)?
    var onScrubBegan: (() -> Void)?
    var onScrubChanged: ((_ deltaPoints: CGFloat, _ velocityPointsPerSec: CGFloat) -> Void)?
    var onScrubTouchLifted: (() -> Void)?
    var onSelectClick: (() -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onUpClick: (() -> Void)?
    var onDownClick: (() -> Void)?

    private enum PanAxis {
        case undecided
        case horizontalScrub
        case verticalCommand
    }

    private var panAxis: PanAxis = .undecided
    private var lastTranslation: CGPoint = .zero
    private var didCommitDuringCurrentPan: Bool = false
    private var activeSelectPress: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override var canBecomeFocused: Bool {
        true
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    /// Explicitly disables every tvOS system halo / Liquid Glass focus plate on the video canvas.
    override var focusEffect: UIFocusEffect? {
        nil
    }

    private func configureSurface() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleIndirectPan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    // MARK: - Indirect Touch (Wake OSD & Continuous Scrubbing)

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
            lastTranslation = .zero
            didCommitDuringCurrentPan = false

        case .changed:
            guard !didCommitDuringCurrentPan else { return }
            let translation = recognizer.translation(in: self)
            let velocity = recognizer.velocity(in: self)

            switch panAxis {
            case .undecided:
                let distance = hypot(translation.x, translation.y)
                guard distance >= 14 else { return }

                if abs(translation.x) >= abs(translation.y) * 1.1 {
                    panAxis = .horizontalScrub
                    lastTranslation = translation
                    onScrubBegan?()
                    onScrubChanged?(translation.x, velocity.x)
                } else if abs(translation.y) > abs(translation.x) * 1.35, distance >= 42 {
                    panAxis = .verticalCommand
                    if translation.y > 0 {
                        onDownClick?()
                    } else {
                        onUpClick?()
                    }
                }

            case .horizontalScrub:
                let deltaX = translation.x - lastTranslation.x
                lastTranslation = translation
                if abs(deltaX) > 0.05 {
                    onScrubChanged?(deltaX, velocity.x)
                }

            case .verticalCommand:
                break
            }

        case .ended, .cancelled, .failed:
            if panAxis == .horizontalScrub && !didCommitDuringCurrentPan {
                onScrubTouchLifted?()
            }
            panAxis = .undecided
            lastTranslation = .zero
            didCommitDuringCurrentPan = false

        default:
            break
        }
    }

    // MARK: - Physical Clickpad & Remote Button Presses

    private static func isLocallyHandledPress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .select, .leftArrow, .rightArrow, .upArrow, .downArrow:
            return true
        default:
            return false
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough = Set<UIPress>()

        for press in presses {
            switch press.type {
            case .select:
                activeSelectPress = true
            case .leftArrow:
                onLeftClick?()
            case .rightArrow:
                onRightClick?()
            case .upArrow:
                onUpClick?()
            case .downArrow:
                onDownClick?()
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
            if press.type == .select {
                if activeSelectPress {
                    activeSelectPress = false
                    didCommitDuringCurrentPan = true
                    onSelectClick?()
                }
            } else if !Self.isLocallyHandledPress(press.type) {
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
            if press.type == .select {
                activeSelectPress = false
            } else if !Self.isLocallyHandledPress(press.type) {
                passthrough.insert(press)
            }
        }

        if !passthrough.isEmpty {
            super.pressesCancelled(passthrough, with: event)
        }
    }
}
