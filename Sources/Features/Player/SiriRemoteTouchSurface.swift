import SwiftUI
import UIKit

/// Invisible UIKit focus & touch capture surface for tvOS playback (`zIndex: 1.5`).
///
/// Why UIKit instead of a SwiftUI `Button`:
/// - Plain `UIView` (`canBecomeFocused = true`, `backgroundColor = .clear`) paired with
///   `.focusEffectDisabled()` in SwiftUI draws **zero** tvOS system halo or Liquid Glass
///   focus rectangle over `AetherPlayerSurface`.
/// - Captures `UITouch.TouchType.indirect` clickpad movement for paused-only adaptive scrubbing
///   and light-touch OSD wake, while differentiating `< 280 ms` ring clicks (`±10 s`) from
///   `>= 280 ms` progressive hold-on-ring seeking.
@MainActor
struct SiriRemoteTouchSurface: UIViewRepresentable {
    var isPlayingProvider: () -> Bool = { false }
    var isScrubbingProvider: () -> Bool = { false }
    var canLockHorizontalFocusProvider: () -> Bool = { true }
    var durationSecondsProvider: () -> Double = { 0 }
    var focusRequestNonce: Int = 0
    var cancelHoldNonce: Int = 0
    let onLightTouch: () -> Void
    let onScrubBegan: () -> Void
    let onScrubChanged: (_ deltaSeconds: Double) -> Void
    let onSelectClick: () -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    var onRingHoldBegan: (_ direction: Int) -> Void = { _ in }
    var onRingHoldEnded: (_ cancelled: Bool) -> Void = { _ in }
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
        view.isPlayingProvider = isPlayingProvider
        view.isScrubbingProvider = isScrubbingProvider
        view.canLockHorizontalFocusProvider = canLockHorizontalFocusProvider
        view.durationSecondsProvider = durationSecondsProvider
        view.onLightTouch = onLightTouch
        view.onScrubBegan = onScrubBegan
        view.onScrubChanged = onScrubChanged
        view.onSelectClick = onSelectClick
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onRingHoldBegan = onRingHoldBegan
        view.onRingHoldEnded = onRingHoldEnded
        view.onUpClick = onUpClick
        view.onDownClick = onDownClick
        view.applyCancelHoldNonce(cancelHoldNonce)
        view.applyFocusRequestNonce(focusRequestNonce)
    }
}
