# Luna (`v2.8.0`) — Codebase Module Map

Complete 1:1 module, endpoint, build, and XCTest inventory for `Luna` (enforced bidirectionally by `ops/bin/luna-check`).

## 1. App Shell, Discovery, Config, Cache & Models (`Sources/App/`, `Sources/Core/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/App/LunaApp.swift` | Owns single `@MainActor AetherEngine`, root `AppSessionStore`, `ComfortPreferences` & `--preview-screen` boot | — | `LunaCoreLinuxTests.swift` |
| `Sources/App/PreviewLaunchConfiguration.swift` | Parses `--preview-screen` (`home`, `home-poster`, `catalog`, `library`, `details`, `settings`, `player-audio`, `player-source`) & `--preview-focus` CLI arguments | — | `LunaCoreLinuxTests.swift` |
| `Sources/App/PreviewMockFixtures.swift` | Deterministic offline Lampelys catalog, 28-season detail & playback fixtures | Mock `/api/tv/v1/*` | — |
| `Sources/App/PreviewMockURLProtocol.swift` | Offline `URLProtocol` router & procedural cinema artwork PNG generator for preview mode | Mock `/api/tv/v1/*`, `/preview-art/*` | — |
| `Sources/App/MainNavigationShell.swift` | Custom top bar + hidden stock tab bar, room atmosphere env, bootstrap sync & player sheet | `GET /api/tv/v1/bootstrap` | `LunaNavigationAndDetailRaceTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/App/LunaNavigationBarVisibility.swift` | `MainNavigationTab` (*Hjem · Filmer · Serier · Bibliotek* + *Søk/Innstillinger*), scroll collapse & Menu-wakeup policy | — | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/App/LunaTopBarView.swift` | Warm-espresso & honey-brass top navigation dock with room crescent mark & icon utility triggers | — | `LunaNavigationAndDetailRaceTests.swift`, `ThemeAndArtworkViewTests.swift` |
| `Sources/Core/Discovery/BonjourServerBrowser.swift` | `NWBrowser` discovery for `_lunacore._tcp`, publishes `DiscoveredLunaCoreServer` | mDNS `_lunacore._tcp` (`api`, `https_port`) | `BonjourServerBrowserTests.swift` |
| `Sources/Core/Config/SideloadSafeStorage.swift` | Bundle-ID-independent `UserDefaults` + Keychain persistence (`luna.v1.*`) | — | `SideloadSafeStorageTests.swift` |
| `Sources/Core/Config/ServerConfiguration.swift` | `AppSessionStore`, URL normalization, LAN TLS evaluator & `LunaCoreClient` factory | — | `ClientOriginAndBlurHashTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Config/ComfortPreferences.swift` | Subtitle preset/scale/box, DV P7 FEL, speaker & MetalFX upscaling settings | `PATCH /api/tv/v1/device/profile` | `PlayerOverlayAndCacheTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Core/Config/SmartTrackRuleEngine.swift` | Automatic Nordic/English audio & subtitle track matching | — | `SmartTrackRuleEngineTests.swift` |
| `Sources/Core/Cache/ArtworkPipeline.swift` | Off-main-actor image download/downsample cache & BlurHash placeholder pipeline | Same-origin artwork auth & CDN fetch | `ClientOriginAndBlurHashTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Cache/BlurHashDecoder.swift` | Pure Swift BlurHash decoder for instant card & hero placeholders | — | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Cache/DiskSWRStore.swift` | `.cachesDirectory` ETag/JSON SWR snapshot persistence for cold start | `GET /api/tv/v1/home` (`If-None-Match` / `304`) | `DiskSWRStoreTests.swift`, `LunaCoreLinuxTests.swift` |
| `Sources/Core/Catalog/CatalogShelfIndexer.swift` | Pure-Swift shelf deduplication, `Fra iPhone`/`I kveld` continue ordering & tier indexing | — | `DynamicHomeRowTests.swift`, `LunaCoreLinuxTests.swift` |
| `Sources/Core/Playback/PlaybackCoreAbstractions.swift` | Pure-Swift `PlaybackEngine`, `IOReader`, `PlaybackCurtainWatchdog` & coordinator state machine | — | `LunaCoreLinuxTests.swift` |
| `Sources/Core/Models/ChapterModels.swift` | Chapter & intro/recap/credits classification models | `chapters[]` metadata | `ChapterClassificationTests.swift` |
| `Sources/Core/Models/DetailModels.swift` | `Codable` item detail, seasons, episodes & source candidate models | `GET /api/tv/v1/items/*` | `ModelDecodingTests.swift`, `MediaDetailViewModelTests.swift` |
| `Sources/Core/Models/EpisodeTitleFormatter.swift` | Norwegian/Nordic episode label & air-date formatting helpers | — | `EpisodeTitleFormattingTests.swift` |
| `Sources/Core/Models/HomeModels.swift` | `Codable` bootstrap, pairing, home shelves & catalog models | `GET /api/tv/v1/{bootstrap,home,catalog/*,library}` | `ModelDecodingTests.swift`, `DynamicHomeRowTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Models/PlaybackModels.swift` | `Codable` playback prepare, resolve, heartbeat, switch & alternative models | `/api/tv/v1/playback/*` | `ModelDecodingTests.swift`, `PlaybackTitleAndNowPlayingTests.swift` |
| `Sources/Core/Models/TvDeletionModels.swift` | `Codable` delete preflight & execution request/response DTOs | `POST /api/tv/v1/delete/{preflight,}` | `NavigationSettingsAndDeleteTests.swift` |

## 2. Networking (`Sources/Core/Networking/`) & AetherEngine Bridge (`Packages/AetherBridge/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/Core/Networking/LunaCoreHTTPTransport.swift` | `LunaCoreClient`, `LunaCoreError`, `HomeConditionalResult`, HTTP request builder & JSON decoding | All `/api/tv/v1/*` HTTP transport | `LunaCoreHTTPTransportTests.swift`, `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+HomeCatalog.swift` | Pairing, bootstrap, conditional `/home`, catalog, library, search & shelf mutations | `/pair/*`, `/bootstrap`, `/home`, `/catalog/*`, `/library`, `/search` | `DynamicHomeRowTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+LibraryDetail.swift` | Item detail, monitor toggle, watchlist/watched, custom row & delete preflight/execute | `/items/*`, `/monitor`, `/watchlist`, `/watched`, `/delete/*` | `MediaDetailViewModelTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+Playback.swift` | Playback prepare, resolve, heartbeat, stop, source switch & alternatives | `/playback/{prepare,resolve,heartbeat,stop,*/switch,*/alternatives}` | `PlaybackTitleAndNowPlayingTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Networking/LunaCoreSessionPool.swift` | Shared ephemeral `URLSession` lanes (`api`, `artwork`, `ws`) + `LanURLSessionDelegate` | HTTP keep-alive & LAN self-signed TLS | `LunaCoreSessionPoolTests.swift` |
| `Sources/Core/Networking/PlaybackResolveSocket.swift` | `AsyncThrowingStream` WebSocket client for playback resolution progress | `WS /api/tv/v1/ws/playback/:resolveId` | `PlaybackResolveSocketTests.swift` |
| `Packages/AetherBridge/Package.swift` | Local SwiftPM wrapper pinning `AetherEngine` `7.69.0` + 5 audio/DV traits | SwiftPM (`TrueHD`, `DTSX`, `DualLayerDV`, `FelCurves`, `StillReshaping`) | — |
| `Packages/AetherBridge/Sources/AetherBridge/Exports.swift` | Public `@_exported import AetherEngine` re-export for app & test targets | — | — |

## 3. Design System & Feature Modules (`Sources/DesignSystem/`, `Sources/Features/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/DesignSystem/Tokens/LunaTokens.swift` | Generated platform-scaled colors, typography, radii & focus springs from `design/tokens.json` | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaTheme.swift` | Warm espresso & honey-brass OLED/HDR palette, `LunaRoomAtmosphere` & card tint resolvers | — | `ThemeAndArtworkViewTests.swift`, `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaThemeTypography.swift` | `LunaTheme.Font` 10-foot typography & role tokens (`heroSerif`, `tabTitle`, `posterTitle`, `pairingCode`, `subtitleCue`) | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaCrescentMarkView.swift` | Clean vector crescent moon brand mark (`LunaCrescentMarkView`) | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/LunaPillButton.swift` | Focus-safe `LunaChromelessButtonStyle`, `LunaPillButton`, `LunaButtonProminence/Accent/Size` | — | `ThemeAndArtworkViewTests.swift`, `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/CachedArtworkView.swift` | Off-main-actor key-matched artwork view preventing 1-frame recycled cell flash | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/LunaFocusStyle.swift` | Shared `0.32/0.86` tvOS focus spring, inner gold border & warm under-glow modifier | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaCopy.swift` | Norwegian pluralization, comma decimal formatter, room/tier labels & greetings | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/AmbientBackdropView.swift` | Static warm charcoal/espresso ambient glow backdrop (paused during playback) | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/Cards/PosterCardView.swift` | Isolated `@FocusState` 280×420 poster card (`LunaTierMarkView`, focus-only titles, gold ring & warm glow) | Artwork pipeline loading | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/Cards/BackdropCardView.swift` | Isolated `@FocusState` 520×293 16:9 card (internal titles, `Fra iPhone`/`I kveld` pill & progress bar) | Artwork pipeline loading | `ThemeAndArtworkViewTests.swift` |
| `Sources/Features/Shared/MediaCardComponents.swift` | `TransientErrorBanner`, `MediaCardMutator` & shared context-menu mutations | `POST /api/tv/v1/{watchlist,watched,continue/remove,rows/:id/remove}` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Onboarding/PairingOnboardingView.swift` | `_lunacore._tcp` auto-discovery & 6-digit pairing flow | `POST /api/tv/v1/pair/request`, `GET /pair/poll/:code` | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Home/HomeView.swift` | 4-row evening home with SWR instant paint & context-menu shelf mutators | `GET /api/tv/v1/home` | `SeriesFlowAndHomePolicyTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Features/Home/ShelfRowView.swift` | Horizontal focus-safe shelf carousel supporting poster & backdrop styles | — | `DynamicHomeRowTests.swift` |
| `Sources/Features/Browse/CatalogBrowseView.swift` | Paginated genre & sort catalog browser | `GET /api/tv/v1/catalog/{movies,series}` | `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Features/Browse/CustomRowBrowseView.swift` | Paginated custom row browser | `GET /api/tv/v1/rows/:id` | `DynamicHomeRowTests.swift` |
| `Sources/Features/Library/LibraryHubView.swift` | Split 2-column Bibliotek hub (*Lokalt · Filmer · Serier · Huskeliste · Egne lister*) | `GET /api/tv/v1/library?section={watchlist,lists,local}` | `NavigationSettingsAndDeleteTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Features/Library/LibrarySidebarAndEmptyViews.swift` | Focus-driven Bibliotek sidebar rows, list tiles & crescent-serif empty states | — | `DynamicHomeRowTests.swift` |
| `Sources/Features/Search/SearchView.swift` | Instant search across local library & TMDB catalog | `GET /api/tv/v1/search` | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailView.swift` | Title detail container coordinating hero, seasons, source picker & delete sheet | `GET /api/tv/v1/items/*` | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailViewModel.swift` | Observable detail state, episode loading & pre-resolve orchestration | `GET /items/*`, `GET /playback/:id/alternatives` | `MediaDetailViewModelTests.swift`, `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailViewModel+Mutations.swift` | Watchlist, watched, follow/monitor & preflight delete mutations | `POST /monitor`, `/watchlist`, `/watched`, `/delete/*` | `MediaDetailViewModelTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Detail/DetailHeroHeaderView.swift` | Editorial `heroSerif` header, gold primary play CTA, Huskeliste/Sett/Mer icon actions | — | — |
| `Sources/Features/Detail/DetailMoreAndOverviewSheets.swift` | «Mer» action sheet (Kilde, Følg, Slett) & «Les mer» synopsis modal | — | — |
| `Sources/Features/Detail/DetailSeasonsSectionView.swift` | Season tabs & horizontal episode strip with default focus on next episode | — | — |
| `Sources/Features/Detail/EpisodeCardView.swift` | Focusable episode tile with progress, air badge, «Neste for deg» & watched toggle | — | `EpisodeTitleFormattingTests.swift` |
| `Sources/Features/Detail/DetailPreResolveController.swift` | Background pre-resolve + WebSocket progress bridge | `POST /playback/prepare`, `WS /ws/playback/:id` | `PlaybackResolveSocketTests.swift` |
| `Sources/Features/Detail/SourcePickerSheetView.swift` | Focusable release/source selector sheet with room equipment & human explanation | `GET /playback/:id/alternatives` | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Detail/DetailDeleteSheetView.swift` | Confined media deletion sheet with preflight byte summary | `POST /delete/{preflight,}` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsView.swift` | 2-column settings root (*Rom og skjerm · Undertekster · Avspilling · System · Avansert*) | `PATCH /api/tv/v1/device/profile`, `GET /bootstrap` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsComfortSectionView.swift` | Room equipment summary, Kveldslys subtitles & autoplay controls | `PATCH /api/tv/v1/device/profile` | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Settings/SettingsAdvancedSectionView.swift` | Room override, low-res upscaling (`Auto MetalFX`), DV P7 FEL, speaker/eARC sync, Nerd HUD & LAN self-signed TLS controls | `PATCH /api/tv/v1/device/profile` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsServerDiagnosticsSectionView.swift` | Server connection, room equipment summary, cache clear & unified reconnect trigger | `GET /api/tv/v1/bootstrap` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsComponents.swift` | Shared settings row & pill primitives | — | — |
| `Sources/Features/Player/PlayerViewModel.swift` | Playback coordinator owning resolve, transport bindings, chapters & source switch | `POST /playback/{resolve,heartbeat,stop,*/switch}` | `PlaybackTitleAndNowPlayingTests.swift`, `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/PlayerContainerView.swift` | Full-screen `AetherPlayerSurface` host, curtain, HUD, remote toasts, drawer & Remote touch | — | `PlayerExitBlinkRegressionTests.swift` |
| `Sources/Features/Player/PlayerSessionCoordinator.swift` | Playback resolve, heartbeat loop, remote commands (`next_episode`/`subtitles_on`) & scrobble | `POST /playback/{resolve,heartbeat,stop}` | `PlaybackTitleAndNowPlayingTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Features/Player/PlayerAudioSessionCoordinator.swift` | `AVAudioSession` activation & route change handling | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerEngineConfigurator.swift` | Configures single `@MainActor AetherEngine` options, subtitle limits & `LoadOptions` | — | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/PlayerEnginePublishers.swift` | Combine/observation bridge from `AetherEngine` state & clock into player coordinators | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerForegroundRestoreCoordinator.swift` | Scene foreground/background audio & surface restoration | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerNowPlayingCoordinator.swift` | `MPNowPlayingInfoCenter` metadata & remote command center bindings | — | `PlaybackTitleAndNowPlayingTests.swift` |
| `Sources/Features/Player/PlayerTransportProtocol.swift` | Testable transport abstraction decoupling `PlayerViewModel` from `AetherEngine` | — | `PlayerTestDoubles.swift` |
| `Sources/Features/Player/PlayerTrackControls.swift` | Audio, subtitle & video track selection state and `SmartTrackRuleEngine` wiring | — | `SmartTrackRuleEngineTests.swift` |
| `Sources/Features/Player/PlayerBottomBarView.swift` | Leaf scrubber bar observing `engine.clock`, live timecode commits & first-time scrub hint | — | `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/PlayerTopDrawerView.swift` | Focus-isolated 4-tab top drawer (*Info · Lyd og tekst · Kilde · Kapitler*) & row cards | `GET /playback/:id/alternatives` | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/PlayerTopDrawerPanelsView.swift` | Content panels for Info, Lyd og tekst (`Kveldslys`), Kilde & Kapitler drawer tabs | `GET /playback/:id/alternatives` | `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Features/Player/SiriRemoteTouchSurface.swift` | `UIView` Siri Remote pan/tap/menu handler with `.focusEffectDisabled()` | — | `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/ResolvingCurtainView.swift` | Hold curtain preventing HDMI black flash on display-mode switches | — | `PlayerExitBlinkRegressionTests.swift` |
| `Sources/Features/Player/ScrubPreviewBubbleView.swift` | Frame-accurate scrub thumbnail preview bubble | — | — |
| `Sources/Features/Player/SubtitleOverlayView.swift` | Leaf HDR-dimmed subtitle renderer observing `engine.clock` | — | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/SeriesFlowOverlays.swift` | Skip-intro/recap & next-episode countdown overlays | — | `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Features/Player/NerdHUDView.swift` | 1 Hz telemetry diagnostics overlay observing `engine.diagnostics.$liveTelemetry` | — | — |

## 4. Build, Guardrails, Actions & `LunaTests` (`Tests/LunaTests/`)

- **Build, Tokens & CI**: `project.yml` (`MARKETING_VERSION: "2.8.0"`, `CURRENT_PROJECT_VERSION: "60"`, `bundleIdPrefix: local.lunacore`), `Package.swift` (Linux `LunaCore` test target), `design/tokens.json`, `Resources/Localizable.xcstrings`, `ops/bin/luna-design-tokens`, `Config/Info.plist` (`NSAllowsArbitraryLoads`, `_lunacore._tcp`), `.github/workflows/build-tvos.yml`, `.github/workflows/tvos-vision.yml`, `scripts/test-core.sh`, `scripts/preview-capture.sh`, `.github/actions/setup-tvos-xcode/action.yml` (`Xcode 26.2+/27`, `XcodeGen`), and `ops/bin/luna-check` (permissions, `<= 800 LOC`, `>= 22 pt` tvOS font floor, zero system `Material`, sideload, zero private infra leaks, token parity & bidirectional doc parity).
- **23 XCTest Suites + Test Doubles (`Tests/LunaTests/`)**:
  - `Tests/LunaTests/BonjourServerBrowserTests.swift`
  - `Tests/LunaTests/ChapterClassificationTests.swift`
  - `Tests/LunaTests/ClientOriginAndBlurHashTests.swift`
  - `Tests/LunaTests/DesignTokensAndCopyTests.swift`
  - `Tests/LunaTests/DiskSWRStoreTests.swift`
  - `Tests/LunaTests/DynamicHomeRowTests.swift`
  - `Tests/LunaTests/EpisodeTitleFormattingTests.swift`
  - `Tests/LunaTests/LunaCoreHTTPTransportTests.swift`
  - `Tests/LunaTests/LunaCoreSessionPoolTests.swift`
  - `Tests/LunaTests/LunaNavigationAndDetailRaceTests.swift`
  - `Tests/LunaTests/MediaDetailViewModelTests.swift`
  - `Tests/LunaTests/ModelDecodingTests.swift`
  - `Tests/LunaTests/NavigationSettingsAndDeleteTests.swift`
  - `Tests/LunaTests/PausedScrubCommitTests.swift`
  - `Tests/LunaTests/PlaybackResolveSocketTests.swift`
  - `Tests/LunaTests/PlaybackRestoreAndAudioSessionTests.swift`
  - `Tests/LunaTests/PlaybackTitleAndNowPlayingTests.swift`
  - `Tests/LunaTests/PlayerExitBlinkRegressionTests.swift`
  - `Tests/LunaTests/PlayerOverlayAndCacheTests.swift`
  - `Tests/LunaTests/SeriesFlowAndHomePolicyTests.swift`
  - `Tests/LunaTests/SideloadSafeStorageTests.swift`
  - `Tests/LunaTests/SmartTrackRuleEngineTests.swift`
  - `Tests/LunaTests/ThemeAndArtworkViewTests.swift`
  - `Tests/LunaTests/PlayerTestDoubles.swift` (shared player/transport test doubles)
- **Linux `LunaCoreTests` (`Package.swift` / `./scripts/test-core.sh`)**:
  - `Tests/LunaCoreTests/LunaCoreLinuxTests.swift` (native Linux x86_64 tests for `PlaybackEngine`/`IOReader`, `PlaybackCurtainWatchdog`, `CatalogShelfIndexer`, `LunaCoreClient`, `SmartTrackRuleEngine`, `PlaybackChapter`, `SideloadSafeStorage` & `PreviewLaunchConfiguration`)
