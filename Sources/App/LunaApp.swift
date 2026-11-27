import SwiftUI
import AetherBridge

@main
struct LunaApp: App {
    private let previewConfiguration: PreviewLaunchConfiguration?
    @State private var sessionStore: AppSessionStore

    /// Long-lived AetherEngine instance shared across all playback sessions
    /// so HDMI display criteria and audio session controllers are never torn
    /// down unnecessarily between titles.
    @MainActor
    static func makeSharedEngine() throws -> AetherEngine {
        let created = try AetherEngine()
        // AE#1015 / AE#1031: Keep forward subtitle prefetch disabled so 4K MKVs never open
        // a parallel HTTP stream, while retaining 10 s of past PGS history for positive delay.
        created.maximumSubtitleAdvanceSeconds = 0
        created.maximumSubtitleDelaySeconds = 10
        created.ownsSoftwareNowPlaying = true
        created.ownsVideoNowPlayingSession = true
        created.ownsVideoNowPlayingCommands = true
        // Luna delivers bridged/rendered PCM & object audio rather than raw E-AC-3 bitstream
        // passthrough; deactivating AVAudioSession on final stop triggers an immediate HDMI/AVR
        // link renegotiation blink when exiting an episode.
        created.deactivatesAudioSessionOnStop = false
        return created
    }

    private let engine: AetherEngine = {
        do {
            return try makeSharedEngine()
        } catch {
            fatalError("AetherEngine initialization failed: \(error)")
        }
    }()

    init() {
        let parsedPreview = PreviewLaunchConfiguration.current
        self.previewConfiguration = parsedPreview
        if let parsedPreview {
            _sessionStore = State(initialValue: AppSessionStore(previewConfiguration: parsedPreview))
        } else {
            _sessionStore = State(initialValue: AppSessionStore())
            Task.detached(priority: .utility) {
                _ = await AetherEngine.prewarmDualLayerDolbyVision()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await ArtworkPipeline.shared.trimDiskCacheIfNeeded()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionStore.isPaired && previewConfiguration?.screen != .onboarding {
                    MainNavigationShell(
                        engine: engine,
                        previewConfiguration: previewConfiguration
                    )
                } else {
                    PairingOnboardingView(
                        isPreviewMode: previewConfiguration?.screen == .onboarding
                    )
                }
            }
            .environment(sessionStore)
            .environment(sessionStore.comfort)
            .preferredColorScheme(.dark)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"))) { _ in
                CatalogBrowseMemoryCache.shared.clear()
                LibraryBrowseMemoryCache.shared.clear()
                ItemDetailMemoryCache.shared.clear()
                BlurHashDecoder.clearCache()
                DiskSWRStore.clearMemory()
                AetherEngine.discardPrewarmedSources()
                AetherEngine.discardRetainedSessionCache()
            }
        }
    }
}
