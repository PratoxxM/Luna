import SwiftUI
import Combine
import AetherBridge

struct MainNavigationShell: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navBarVisibility = LunaNavigationBarVisibility()

    let engine: AetherEngine
    let previewConfiguration: PreviewLaunchConfiguration?
    @State private var selectedTab: MainNavigationTab
    @State private var lastBootstrapRefreshAt: Date = .distantPast

    init(
        engine: AetherEngine,
        previewConfiguration: PreviewLaunchConfiguration? = nil
    ) {
        self.engine = engine
        self.previewConfiguration = previewConfiguration
        let initialTab: MainNavigationTab
        switch previewConfiguration?.screen {
        case .catalog:
            initialTab = .movies
        case .library:
            initialTab = .library
        case .settings:
            initialTab = .settings
        case .details:
            initialTab = .series
        default:
            initialTab = .home
        }
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        if let screen = previewConfiguration?.screen, screen.isPlayerScreen {
            let drawerTab: PlayerTopDrawerTab = screen == .playerSource ? .source : .audioAndSubtitles
            PlayerContainerView(
                engine: engine,
                comfort: sessionStore.comfort,
                initialRequest: PreviewMockFixtures.playerLaunchRequest,
                isPreviewMode: true,
                previewFocusDirection: previewConfiguration?.focusDirection ?? .down,
                previewDrawerTab: drawerTab,
                onDismiss: {}
            )
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environmentObject(sessionStore)
            .environmentObject(sessionStore.comfort)
            .preferredColorScheme(.dark)
        } else if previewConfiguration?.screen == .details {
            NavigationStack {
                MediaDetailView(
                    mediaType: "series",
                    itemId: "series:246810",
                    initialTitle: "Luksusfellen"
                )
            }
            .ignoresSafeArea()
            .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environmentObject(sessionStore.comfort)
        } else {
            mainTabbedShell
        }
    }

    private var mainTabbedShell: some View {
        let isPlaybackActive = sessionStore.activePlaybackTarget != nil
        let hideTopBar = navBarVisibility.isTopBarHidden
        let interceptMenu = navBarVisibility.shouldInterceptMenuPress(hasActivePlayback: isPlaybackActive)
        let focusPosterPreview = previewConfiguration?.screen == .homePoster

        return ZStack(alignment: .topLeading) {
            AmbientBackdropView(isPaused: isPlaybackActive)

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        initialServerHost: sessionStore.serverBaseURL?.host,
                        initialRoomName: sessionStore.roomName,
                        initialHardwareProfile: sessionStore.effectiveHardwareProfile,
                        isActiveTab: selectedTab == .home,
                        previewFocusPosterRow: focusPosterPreview
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
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
                    .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
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
                    .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.series.title, systemImage: MainNavigationTab.series.systemImage)
                }
                .tag(MainNavigationTab.series)

                NavigationStack {
                    LibraryHubView(isActiveTab: selectedTab == .library) { targetTab in
                        selectedTab = targetTab
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.library.title, systemImage: MainNavigationTab.library.systemImage)
                }
                .tag(MainNavigationTab.library)

                NavigationStack {
                    SearchView(isRootTab: true)
                        .toolbar(.hidden, for: .tabBar)
                        .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.search.title, systemImage: MainNavigationTab.search.systemImage)
                }
                .tag(MainNavigationTab.search)

                NavigationStack {
                    SettingsView()
                        .toolbar(.hidden, for: .tabBar)
                        .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.settings.title, systemImage: MainNavigationTab.settings.systemImage)
                }
                .tag(MainNavigationTab.settings)
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .tabBar)

            LinearGradient(
                stops: [
                    .init(color: LunaTheme.canvas.opacity(0.92), location: 0.0),
                    .init(color: LunaTheme.canvas.opacity(0.50), location: 0.62),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 152)
            .ignoresSafeArea(edges: [.top, .horizontal])
            .opacity(hideTopBar ? 0 : 1)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.22), value: hideTopBar)
            .zIndex(9)

            LunaTopBarView(
                selectedTab: $selectedTab,
                roomName: sessionStore.roomName,
                focusRequestNonce: navBarVisibility.focusRequestNonce,
                onFocusPresenceChanged: { isFocused in
                    navBarVisibility.updateTopBarFocused(isFocused)
                }
            )
            .opacity(hideTopBar ? 0 : 1)
            .offset(y: hideTopBar ? -24 : 0)
            .allowsHitTesting(!hideTopBar)
            .disabled(hideTopBar)
            .animation(LunaFocusStyle.focusSpring, value: hideTopBar)
            .zIndex(10)
        }
        .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
        .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
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
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environmentObject(sessionStore)
            .environmentObject(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .task {
            if previewConfiguration?.focusDirection == .up {
                navBarVisibility.handleMenuPressToRevealTopBar()
            }
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
