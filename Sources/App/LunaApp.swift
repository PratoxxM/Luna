import SwiftUI
import AetherBridge

@main
struct LunaApp: App {
    @StateObject private var sessionStore = AppSessionStore()

    /// Long-lived AetherEngine instance shared across all playback sessions
    /// so HDMI display criteria and audio session controllers are never torn
    /// down unnecessarily between titles.
    private let engine: AetherEngine = {
        do {
            return try AetherEngine()
        } catch {
            fatalError("AetherEngine initialization failed: \(error)")
        }
    }()

    init() {
        Task.detached(priority: .utility) {
            _ = await AetherEngine.prewarmDualLayerDolbyVision()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionStore.isPaired {
                    MainTabShell(engine: engine)
                } else {
                    PairingOnboardingView()
                }
            }
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
    }
}
