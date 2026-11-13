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
            let created = try AetherEngine()
            // AE#1015 / AE#1031: Keep forward subtitle prefetch disabled so 4K MKVs never open
            // a parallel HTTP stream, while retaining 10 s of past PGS history for positive delay.
            created.maximumSubtitleAdvanceSeconds = 0
            created.maximumSubtitleDelaySeconds = 10
            created.ownsSoftwareNowPlaying = true
            created.ownsVideoNowPlayingSession = true
            created.ownsVideoNowPlayingCommands = true
            return created
        } catch {
            fatalError("AetherEngine initialization failed: \(error)")
        }
    }()

    init() {
        Task.detached(priority: .utility) {
            _ = await AetherEngine.prewarmDualLayerDolbyVision()
            await ArtworkPipeline.shared.trimDiskCacheIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionStore.isPaired {
                    MainNavigationShell(engine: engine)
                } else {
                    PairingOnboardingView()
                }
            }
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
    }
}
