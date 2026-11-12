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
            // AE#1015: Prevent background forward subtitle prefetch from downloading
            // high-bitrate interleaved 4K MKV streams a second time over HTTP/VFS.
            created.maximumSubtitleAdvanceSeconds = 0
            created.maximumSubtitleDelaySeconds = 10
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
