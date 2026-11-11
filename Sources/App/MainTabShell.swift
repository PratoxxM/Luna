import SwiftUI
import AetherBridge

struct MainTabShell: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    let engine: AetherEngine

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Hjem", systemImage: "sparkles.tv")
            }
            .tag(0)

            NavigationStack {
                WatchlistView()
            }
            .tabItem {
                Label("Huskeliste", systemImage: "bookmark")
            }
            .tag(1)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Søk", systemImage: "magnifyingglass")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Innstillinger", systemImage: "gearshape")
            }
            .tag(3)
        }
        .fullScreenCover(item: $sessionStore.activePlaybackTarget) { launchRequest in
            PlayerContainerView(
                engine: engine,
                initialRequest: launchRequest,
                onDismiss: {
                    sessionStore.activePlaybackTarget = nil
                }
            )
            .environmentObject(sessionStore)
        }
        .task {
            await refreshBootstrapProfile()
        }
    }

    private func refreshBootstrapProfile() async {
        guard let client = sessionStore.makeClient() else { return }
        do {
            let boot = try await client.fetchBootstrap()
            sessionStore.syncFromBootstrap(boot.device)
        } catch BFFError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            // Keep cached room/profile when temporarily offline
        }
    }
}
