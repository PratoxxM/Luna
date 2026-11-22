import SwiftUI
import AetherBridge

struct MainNavigationShell: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var navBarVisibility = LunaNavigationBarVisibility()

    let engine: AetherEngine
    let previewConfiguration: PreviewLaunchConfiguration?
    @State private var selectedTab: MainNavigationTab
    @State private var lastBootstrapRefreshAt: Date = .distantPast
    @State private var bootstrapRefreshNonce: Int = 0
    @State private var allowColdHomeCardFocus: Bool

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
        case .search:
            initialTab = .search
        case .settings:
            initialTab = .settings
        case .details:
            initialTab = .series
        default:
            initialTab = .home
        }
        _selectedTab = State(initialValue: initialTab)
        let shouldAllowColdFocus = (previewConfiguration == nil
            || previewConfiguration?.screen == .home
            || previewConfiguration?.screen == .homePoster)
            && previewConfiguration?.focusDirection != .up
        _allowColdHomeCardFocus = State(initialValue: shouldAllowColdFocus)
    }

    var body: some View {
        if let screen = previewConfiguration?.screen, screen.isPlayerScreen {
            let previewPanel: PlayerQuickPanelTab? = {
                switch screen {
                case .playerSource: return .source
                case .playerAudio: return .audio
                case .playerPicture: return .picture
                case .playerChapters: return .chapters
                case .playerSubtitles: return .subtitles
                case .playerError: return nil
                default: return nil
                }
            }()
            let previewError: String? = screen == .playerError
                ? "Kunne ikke lese svaret fra LunaCore akkurat nå."
                : nil
            PlayerContainerView(
                engine: engine,
                comfort: sessionStore.comfort,
                initialRequest: PreviewMockFixtures.playerLaunchRequest,
                isPreviewMode: true,
                previewFocusDirection: previewConfiguration?.focusDirection ?? .down,
                previewQuickPanel: previewPanel,
                previewFatalError: previewError,
                onDismiss: {}
            )
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environment(sessionStore)
            .environment(sessionStore.comfort)
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
            .environment(sessionStore.comfort)
        } else {
            mainTabbedShell
        }
    }

    private var mainTabbedShell: some View {
        @Bindable var sessionStore = sessionStore
        let isPlaybackActive = sessionStore.activePlaybackTarget != nil
        let hideTopBar = navBarVisibility.isTopBarHidden
        let interceptMenu = navBarVisibility.shouldInterceptMenuPress(hasActivePlayback: isPlaybackActive)
        let focusPosterPreview = previewConfiguration?.screen == .homePoster

        return ZStack(alignment: .topLeading) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        initialServerHost: sessionStore.serverBaseURL?.host,
                        initialRoomName: sessionStore.roomName,
                        initialHardwareProfile: sessionStore.effectiveHardwareProfile,
                        isActiveTab: selectedTab == .home,
                        previewFocusPosterRow: focusPosterPreview,
                        allowInitialColdFocus: allowColdHomeCardFocus
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
                    SearchView(
                        initialQuery: previewConfiguration?.screen == .search ? "Dune" : "",
                        isRootTab: true,
                        isActiveTab: selectedTab == .search
                    )
                    .toolbar(.hidden, for: .tabBar)
                    .lunaNavigationContainerBackdrop(mode: .ambient(isPaused: isPlaybackActive))
                }
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(MainNavigationTab.search.title, systemImage: MainNavigationTab.search.systemImage)
                }
                .tag(MainNavigationTab.search)

                NavigationStack {
                    SettingsView(isActiveTab: selectedTab == .settings)
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
            .frame(height: LunaTokens.Layout.contentTop)
            .ignoresSafeArea(edges: [.top, .horizontal])
            .opacity(hideTopBar ? 0 : 1)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.22), value: hideTopBar)
            .zIndex(9)

            LunaTopBarView(
                selectedTab: $selectedTab,
                roomName: sessionStore.roomName,
                focusRequestNonce: navBarVisibility.focusRequestNonce,
                isUpwardBridgeEnabled: !hideTopBar && !navBarVisibility.isTopBarFocused && !navBarVisibility.isModalActive && !isPlaybackActive,
                onFocusPresenceChanged: { isFocused in
                    navBarVisibility.updateTopBarFocused(isFocused)
                    if isFocused && allowColdHomeCardFocus {
                        allowColdHomeCardFocus = false
                    }
                },
                onRequestDownwardContentFocus: { tab in
                    allowColdHomeCardFocus = false
                    navBarVisibility.requestContentEntryFocus(for: tab)
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
        .environment(\.lunaScrollToTopNonce, navBarVisibility.scrollToTopNonce)
        .environment(\.lunaContentEntryFocusNonce, navBarVisibility.contentEntryFocusNonce)
        .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
        .environment(sessionStore.comfort)
        .onChange(of: selectedTab) { _, newTab in
            allowColdHomeCardFocus = false
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
            .environment(sessionStore)
            .environment(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .task {
            if previewConfiguration?.focusDirection == .up {
                navBarVisibility.handleMenuPressToRevealTopBar()
            }
            if sessionStore.activePlaybackTarget == nil {
                PlayerAudioSessionCoordinator.shared.sampleMenuRefreshRateIfIdle(hasActivePlayback: false)
            }
            await refreshBootstrapProfile()
        }
        .task(id: bootstrapRefreshNonce) {
            guard bootstrapRefreshNonce > 0 else { return }
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
            guard sessionStore.activePlaybackTarget == nil else {
                return
            }
            PlayerAudioSessionCoordinator.shared.sampleMenuRefreshRateIfIdle(hasActivePlayback: false)
            guard Date().timeIntervalSince(lastBootstrapRefreshAt) >= 30 else {
                return
            }
            bootstrapRefreshNonce &+= 1
        }
        .onChange(of: sessionStore.comfort.menuDisplayMode) { _, mode in
            if mode == .sdr60Hz && sessionStore.activePlaybackTarget == nil {
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
