import SwiftUI
import AetherBridge

public enum MainNavigationTab: Hashable, Sendable {
    case home
    case movies
    case series
    case library
    case search
    case settings
}

struct MainNavigationShell: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var ambientController = AmbientBackdropController()

    let engine: AetherEngine
    @State private var selectedTab: MainNavigationTab = .home
    @State private var lastBootstrapRefreshAt: Date = .distantPast

    var body: some View {
        ZStack {
            if sessionStore.activePlaybackTarget == nil {
                AmbientBackdropView(controller: ambientController)
            }

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        initialServerHost: sessionStore.serverBaseURL?.host,
                        initialRoomName: sessionStore.roomName,
                        initialHardwareProfile: sessionStore.effectiveHardwareProfile
                    )
                }
                .tabItem {
                    Label("Hjem", systemImage: "sparkles.tv")
                }
                .tag(MainNavigationTab.home)

                NavigationStack {
                    CatalogBrowseView(mediaType: "movie", initialGenre: nil)
                }
                .tabItem {
                    Label("Filmer", systemImage: "film")
                }
                .tag(MainNavigationTab.movies)

                NavigationStack {
                    CatalogBrowseView(mediaType: "series", initialGenre: nil)
                }
                .tabItem {
                    Label("Serier", systemImage: "tv")
                }
                .tag(MainNavigationTab.series)

                NavigationStack {
                    LibraryHubView()
                }
                .tabItem {
                    Label("Mitt bibliotek", systemImage: "books.vertical.fill")
                }
                .tag(MainNavigationTab.library)

                NavigationStack {
                    SearchView()
                }
                .tabItem {
                    Label("Søk", systemImage: "magnifyingglass")
                }
                .tag(MainNavigationTab.search)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Innstillinger", systemImage: "gearshape.fill")
                }
                .tag(MainNavigationTab.settings)
            }
            .tint(LunaTheme.amber)
        }
        .environmentObject(ambientController)
        .environmentObject(sessionStore.comfort)
        .fullScreenCover(item: $sessionStore.activePlaybackTarget) { launchRequest in
            PlayerContainerView(
                engine: engine,
                comfort: sessionStore.comfort,
                initialRequest: launchRequest,
                onDismiss: {
                    sessionStore.activePlaybackTarget = nil
                }
            )
            .environmentObject(sessionStore)
            .environmentObject(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .task {
            await refreshBootstrapProfile()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  sessionStore.activePlaybackTarget == nil,
                  Date().timeIntervalSince(lastBootstrapRefreshAt) >= 30 else {
                return
            }
            Task { await refreshBootstrapProfile() }
        }
    }

    private func refreshBootstrapProfile() async {
        guard let client = sessionStore.makeClient() else { return }
        lastBootstrapRefreshAt = Date()
        do {
            let boot = try await client.fetchBootstrap()
            sessionStore.syncFromBootstrap(boot.device)
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            // Preserve cached room and hardware profile if MediaOS is briefly unreachable
        }
    }
}
