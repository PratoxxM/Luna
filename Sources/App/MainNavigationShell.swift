import SwiftUI
import Combine
import AetherBridge

struct MainNavigationShell: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navBarVisibility = LunaNavigationBarVisibility()

    let engine: AetherEngine
    @State private var selectedTab: MainNavigationTab = .home
    @State private var lastBootstrapRefreshAt: Date = .distantPast

    var body: some View {
        let isPlaybackActive = sessionStore.activePlaybackTarget != nil
        let hideTopBar = navBarVisibility.isTopBarHidden
        let interceptMenu = navBarVisibility.shouldInterceptMenuPress(hasActivePlayback: isPlaybackActive)

        ZStack(alignment: .top) {
            AmbientBackdropView(isPaused: isPlaybackActive)

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        initialServerHost: sessionStore.serverBaseURL?.host,
                        initialRoomName: sessionStore.roomName,
                        initialHardwareProfile: sessionStore.effectiveHardwareProfile,
                        isActiveTab: selectedTab == .home
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.home.title, systemImage: MainNavigationTab.home.systemImage)
                }
                .tag(MainNavigationTab.home)

                NavigationStack {
                    CatalogBrowseView(
                        mediaType: "movie",
                        initialGenre: nil,
                        isActiveTab: selectedTab == .movies,
                        isRootTab: true
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.movies.title, systemImage: MainNavigationTab.movies.systemImage)
                }
                .tag(MainNavigationTab.movies)

                NavigationStack {
                    CatalogBrowseView(
                        mediaType: "series",
                        initialGenre: nil,
                        isActiveTab: selectedTab == .series,
                        isRootTab: true
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.series.title, systemImage: MainNavigationTab.series.systemImage)
                }
                .tag(MainNavigationTab.series)

                NavigationStack {
                    LibraryHubView(isActiveTab: selectedTab == .library)
                        .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.library.title, systemImage: MainNavigationTab.library.systemImage)
                }
                .tag(MainNavigationTab.library)

                NavigationStack {
                    SearchView(isRootTab: true)
                        .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.search.title, systemImage: MainNavigationTab.search.systemImage)
                }
                .tag(MainNavigationTab.search)

                NavigationStack {
                    SettingsView()
                        .toolbar(.hidden, for: .tabBar)
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.settings.title, systemImage: MainNavigationTab.settings.systemImage)
                }
                .tag(MainNavigationTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)

            LinearGradient(
                stops: [
                    .init(color: LunaTheme.canvas.opacity(0.94), location: 0.0),
                    .init(color: LunaTheme.canvas.opacity(0.54), location: 0.58),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .ignoresSafeArea(edges: .top)
            .opacity(hideTopBar ? 0 : 1)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.22), value: hideTopBar)
            .zIndex(9)

            LunaTopBarView(
                selectedTab: $selectedTab,
                focusRequestNonce: navBarVisibility.focusRequestNonce,
                onFocusPresenceChanged: { isFocused in
                    navBarVisibility.updateTopBarFocused(isFocused)
                }
            )
            .opacity(hideTopBar ? 0 : 1)
            .offset(y: hideTopBar ? -24 : 0)
            .allowsHitTesting(!hideTopBar)
            .disabled(hideTopBar)
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: hideTopBar)
            .zIndex(10)
        }
        .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
        .environmentObject(sessionStore.comfort)
        .onChange(of: selectedTab) { _, newTab in
            navBarVisibility.syncActiveTab(newTab)
        }
        .onExitCommand(perform: interceptMenu ? {
            navBarVisibility.handleMenuPressToRevealTopBar()
        } : nil)
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
            if PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isActiveScene: phase == .active,
                hasActivePlayback: sessionStore.activePlaybackTarget != nil,
                engineState: engine.state
            ) {
                PlayerAudioSessionCoordinator.shared.flushDeferredDisplayCriteriaResetIfIdle(engine: engine)
            }
            if phase != .active {
                return
            }
            guard sessionStore.activePlaybackTarget == nil,
                  Date().timeIntervalSince(lastBootstrapRefreshAt) >= 30 else {
                return
            }
            Task { await refreshBootstrapProfile() }
        }
        .onReceive(sessionStore.comfort.$keepDisplayModeInMenuAfterPlayback.dropFirst()) { keepInMenu in
            if !keepInMenu && sessionStore.activePlaybackTarget == nil {
                PlayerAudioSessionCoordinator.shared.flushDeferredDisplayCriteriaResetIfIdle(engine: engine)
            }
        }
    }

    private func refreshBootstrapProfile() async {
        guard let client = sessionStore.makeClient() else { return }
        lastBootstrapRefreshAt = Date()
        do {
            let boot = try await client.fetchBootstrap()
            sessionStore.syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            // Preserve cached room and hardware profile if LunaCore is briefly unreachable
        }
    }
}
