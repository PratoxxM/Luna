import SwiftUI

/// Static, calm LunaCore menu canvas: near-black warm charcoal (`#0A0908`) with a subtle
/// top warm candlelight shimmer — zero shifting poster colors or BlurHash crossfades during scrolling,
/// and paused down to a single flat layer whenever full-screen video playback is active.
public struct AmbientBackdropView: View {
    public var isPaused: Bool

    public init(isPaused: Bool = false) {
        self.isPaused = isPaused
    }

    public var body: some View {
        ZStack {
            LunaTheme.canvas

            if !isPaused {
                // Subtle warm espresso depth across the upper third
                LinearGradient(
                    stops: [
                        .init(color: LunaTheme.surface.opacity(0.78), location: 0.0),
                        .init(color: LunaTheme.surface.opacity(0.28), location: 0.36),
                        .init(color: .clear, location: 0.72),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft fixed candlelight glow — warm and cozy without distracting poster color shifts
                RadialGradient(
                    colors: [
                        LunaTheme.amber.opacity(0.065),
                        LunaTheme.amberDeep.opacity(0.024),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.50, y: -0.06),
                    startRadius: 40,
                    endRadius: 980
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
