import SwiftUI
import UIKit
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

    @State private var homeViewModel: HomeViewModel
    @State private var moviesViewModel = CatalogBrowseViewModel(mediaType: "movie", isRootTab: true)
    @State private var seriesViewModel = CatalogBrowseViewModel(mediaType: "series", isRootTab: true)
    @State private var libraryViewModel = LibraryViewModel()
    @State private var searchViewModel: SearchViewModel

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
        case .catalogSeries, .details, .detailSeasons:
            initialTab = .series
        case .library:
            initialTab = .library
        case .search:
            initialTab = .search
        case .settings, .settingsSubtitles, .settingsPlayback, .settingsAudio, .settingsDiagnostics:
            initialTab = .settings
        default:
            initialTab = .home
        }
        _selectedTab = State(initialValue: initialTab)
        let shouldAllowColdFocus = (previewConfiguration == nil
            || previewConfiguration?.screen == .home
            || previewConfiguration?.screen == .homePoster)
            && previewConfiguration?.focusDirection != .up
        _allowColdHomeCardFocus = State(initialValue: shouldAllowColdFocus)

        let defaults = UserDefaults.standard
        let initialHost = (previewConfiguration != nil)
            ? PreviewMockFixtures.previewHost
            : (defaults.string(forKey: SideloadSafeStorage.serverURLKey).flatMap { URL(string: $0)?.host })
        let initialRoom = (previewConfiguration != nil)
            ? PreviewMockFixtures.previewRoomName
            : (defaults.string(forKey: SideloadSafeStorage.roomNameKey) ?? "Stua")
        let initialProfile = (previewConfiguration != nil)
            ? PreviewMockFixtures.previewHardwareProfile
            : (defaults.string(forKey: SideloadSafeStorage.hardwareProfileKey) ?? HardwareProfilePreset.hdr10512.rawValue)
        _homeViewModel = State(
            initialValue: HomeViewModel(
                initialServerHost: initialHost,
                initialRoomName: initialRoom,
                initialHardwareProfile: initialProfile
            )
        )
        let initialSearchQuery = (previewConfiguration?.screen == .search && previewConfiguration?.focusDirection != .select)
            ? "Dune"
            : ""
        _searchViewModel = State(
            initialValue: SearchViewModel(
                initialQuery: initialSearchQuery,
                isRootTab: true
            )
        )
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
                initialRequest: PreviewMockFixtures.playerLaunchRequest(for: screen),
                isPreviewMode: true,
                previewScreenTarget: screen,
                previewFocusDirection: previewConfiguration?.focusDirection ?? .down,
                previewQuickPanel: previewPanel,
                previewFatalError: previewError,
                onDismiss: {}
            )
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environment(sessionStore)
            .environment(sessionStore.comfort)
            .preferredColorScheme(.dark)
        } else if previewConfiguration?.screen == .customRow {
            NavigationStack {
                CustomRowBrowseView(
                    title: "Nordisk spenning",
                    pathOrRowId: "/api/tv/v2/rows/custom%3Anordic-noir"
                )
            }
            .ignoresSafeArea()
            .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environment(sessionStore.comfort)
        } else if previewConfiguration?.screen == .details || previewConfiguration?.screen == .detailSeasons {
            NavigationStack {
                MediaDetailView(
                    mediaType: "series",
                    itemId: "series:tmdb:246810",
                    initialTitle: "Luksusfellen",
                    previewAutoOpenSheet: previewConfiguration?.screen == .detailSeasons ? .seasons : nil
                )
            }
            .ignoresSafeArea()
            .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
            .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
            .environment(sessionStore.comfort)
        } else if let screen = previewConfiguration?.screen,
                  let autoOpenSheet: PreviewDetailAutoOpenSheet? = {
                      switch screen {
                      case .detailMovie: return Optional<PreviewDetailAutoOpenSheet>.none
                      case .detailSourcePicker: return .sourcePicker
                      case .detailMore: return .more
                      case .detailOverview: return .overview
                      case .detailDelete: return .delete
                      default: return nil
                      }
                  }(),
                  screen == .detailMovie || autoOpenSheet != nil {
            NavigationStack {
                MediaDetailView(
                    mediaType: "movie",
                    itemId: "movie:tmdb:693134",
                    initialTitle: "Dune: Part Two",
                    previewAutoOpenSourcePicker: screen == .detailSourcePicker,
                    previewAutoOpenSheet: autoOpenSheet
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

    private var previewSettingsCategory: SettingsCategory {
        switch previewConfiguration?.screen {
        case .settingsSubtitles: return .subtitles
        case .settingsPlayback: return .playback
        case .settingsAudio: return .advanced
        case .settingsDiagnostics: return .system
        default: return .roomAndDisplay
        }
    }

    private var mainTabbedShell: some View {
        @Bindable var sessionStore = sessionStore
        let isPlaybackActive = sessionStore.activePlaybackTarget != nil
        let focusPosterPreview = previewConfiguration?.screen == .homePoster

        return ZStack(alignment: .topLeading) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        viewModel: homeViewModel,
                        initialServerHost: sessionStore.serverBaseURL?.host,
                        initialRoomName: sessionStore.roomName,
                        initialHardwareProfile: sessionStore.hardwareProfile,
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
                        viewModel: moviesViewModel,
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
                        viewModel: seriesViewModel,
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
                    LibraryHubView(
                        viewModel: libraryViewModel,
                        isActiveTab: selectedTab == .library
                    ) { targetTab in
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
                        viewModel: searchViewModel,
                        initialQuery: searchViewModel.initialQuery,
                        isRootTab: true,
                        isActiveTab: selectedTab == .search,
                        previewFocusFirstResult: previewConfiguration?.screen == .search && previewConfiguration?.focusDirection != .select,
                        previewFocusSearchField: previewConfiguration?.screen == .search && previewConfiguration?.focusDirection == .select
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
                    SettingsView(
                        initialCategory: previewSettingsCategory,
                        isActiveTab: selectedTab == .settings
                    )
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

            TopBarOverlayHostView(
                navBarVisibility: navBarVisibility,
                selectedTab: $selectedTab,
                roomName: sessionStore.isRoomUnassigned ? "Velg rom i Innstillinger" : sessionStore.roomName,
                isPlaybackActive: isPlaybackActive,
                onClearColdHomeCardFocus: {
                    if allowColdHomeCardFocus {
                        allowColdHomeCardFocus = false
                    }
                }
            )
            .zIndex(10)
        }
        .environment(\.lunaSubpageVisibility, navBarVisibility.sink)
        .modifier(
            NavigationShellVisibilityBridgeModifier(
                navBarVisibility: navBarVisibility,
                isPlaybackActive: isPlaybackActive
            )
        )
        .environment(\.lunaRoomAtmosphere, sessionStore.effectiveRoomAtmosphere)
        .environment(sessionStore.comfort)
        .onChange(of: selectedTab) { _, newTab in
            if allowColdHomeCardFocus {
                allowColdHomeCardFocus = false
            }
            navBarVisibility.syncActiveTab(newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            DiskSWRStore.clearMemory()
            let tabsToUnload = TabMemoryEvictionPolicy.inactiveTabsToUnload(activeTab: selectedTab)
            if tabsToUnload.contains(.home) { homeViewModel.unloadForMemoryWarning() }
            if tabsToUnload.contains(.movies) { moviesViewModel.unloadForMemoryWarning() }
            if tabsToUnload.contains(.series) { seriesViewModel.unloadForMemoryWarning() }
            if tabsToUnload.contains(.library) { libraryViewModel.unloadForMemoryWarning() }
            if tabsToUnload.contains(.search) { searchViewModel.unloadForMemoryWarning() }
        }
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
            if phase == .background {
                ArtworkPipeline.shared.handleSceneDidEnterBackground()
            }
            if PlayerAudioSessionCoordinator.shouldResetHeldDisplayCriteriaOnScenePhase(
                isBackgroundScene: phase == .background,
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

private struct TopBarOverlayHostView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let navBarVisibility: LunaNavigationBarVisibility
    @Binding var selectedTab: MainNavigationTab
    let roomName: String
    let isPlaybackActive: Bool
    let onClearColdHomeCardFocus: @MainActor () -> Void

    var body: some View {
        let hideTopBar = navBarVisibility.isTopBarHidden
        let isUpwardBridgeEnabled = !hideTopBar
            && !navBarVisibility.isTopBarFocused
            && !navBarVisibility.isModalActive
            && !isPlaybackActive

        ZStack(alignment: .topLeading) {
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
            .animation(
                LunaFocusStyle.calmEaseOut(duration: 0.22, reduceMotion: reduceMotion) ?? .linear(duration: 0.01),
                value: hideTopBar
            )

            LunaTopBarView(
                selectedTab: $selectedTab,
                roomName: roomName,
                focusRequestNonce: navBarVisibility.focusRequestNonce,
                isUpwardBridgeEnabled: isUpwardBridgeEnabled,
                onFocusPresenceChanged: { isFocused in
                    navBarVisibility.updateTopBarFocused(isFocused)
                    if isFocused {
                        onClearColdHomeCardFocus()
                    }
                },
                onRequestDownwardContentFocus: { tab in
                    onClearColdHomeCardFocus()
                    navBarVisibility.requestContentEntryFocus(for: tab)
                }
            )
            .opacity(hideTopBar ? 0 : 1)
            .offset(y: (!reduceMotion && hideTopBar) ? -24 : 0)
            .allowsHitTesting(!hideTopBar)
            .disabled(hideTopBar)
            .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: hideTopBar)
        }
    }
}

private struct NavigationShellVisibilityBridgeModifier: ViewModifier {
    let navBarVisibility: LunaNavigationBarVisibility
    let isPlaybackActive: Bool

    func body(content: Content) -> some View {
        let interceptMenu = navBarVisibility.shouldInterceptMenuPress(hasActivePlayback: isPlaybackActive)
        content
            .environment(\.lunaScrollToTopNonce, navBarVisibility.scrollToTopNonce)
            .environment(\.lunaContentEntryFocusNonce, navBarVisibility.contentEntryFocusNonce)
            .onExitCommand(perform: interceptMenu ? {
                navBarVisibility.handleMenuPressToRevealTopBar()
            } : nil)
    }
}
