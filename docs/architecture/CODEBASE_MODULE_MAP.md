# Luna (`v2.5.0`) — Codebase Module Map

Quick lookup mapping relative repository paths to their responsibilities, **LunaCore** `/api/tv/v1` endpoints, and `Tests/LunaTests` coverage.

## 1. App Shell, Discovery & Networking (`Sources/App/`, `Sources/Core/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/App/LunaApp.swift` | Owns single `@MainActor AetherEngine`, root `AppSessionStore`, `ComfortPreferences` | — | — |
| `Sources/App/MainNavigationShell.swift` | Custom top bar (`LunaTopBarView`) + hidden stock tab bar, server bootstrap sync (`fetchBootstrap`), background display-criteria reset, playback presentation | `GET /api/tv/v1/bootstrap` | `PlayerOverlayAndCacheTests.swift`, `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/App/LunaTopBarView.swift` | Slim warm-espresso & honey-brass top navigation dock with vector crescent mark, 180 ms focus-debounce, scroll auto-hide & Siri Remote Menu wakeup | — | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Core/Discovery/BonjourServerBrowser.swift` | `NWBrowser` discovery for `_lunacore._tcp`, publishes `DiscoveredLunaCoreServer` | mDNS `_lunacore._tcp` (`api`, `https_port`) | — |
| `Sources/Core/Config/SideloadSafeStorage.swift` | Bundle-ID-independent `UserDefaults` + Keychain persistence (`luna.v1.*`) | — | — |
| `Sources/Core/Config/ServerConfiguration.swift` | `AppSessionStore`, URL normalization, LAN TLS evaluator, `LunaCoreClient` factory | — | `ClientOriginAndBlurHashTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Config/ComfortPreferences.swift` | Subtitle preset/scale/box, DV P7 FEL, speaker & MetalFX upscaling settings | `PATCH /api/tv/v1/device/profile` | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Config/SmartTrackRuleEngine.swift` | Automatic Nordic/English audio & subtitle track matching | — | `SmartTrackRuleEngineTests.swift` |
| `Sources/Core/Networking/LunaCoreClient.swift` | Typed REST client (`LunaCoreClient`, `LunaCoreError`), URL/path builders | All `/api/tv/v1/*` REST routes | `ClientOriginAndBlurHashTests.swift`, `PlaybackAndNavigationFixesTests.swift` |
| `Sources/Core/Networking/LunaCoreSessionPool.swift` | Shared ephemeral `URLSession` lanes (`api`, `artwork`, `ws`) + `LanURLSessionDelegate` | HTTP keep-alive & LAN self-signed TLS | — |
| `Sources/Core/Networking/PlaybackResolveSocket.swift` | `AsyncThrowingStream` WebSocket client for playback resolution progress | `WS /api/tv/v1/ws/playback/:resolveId` | — |
| `Sources/Core/Cache/DiskSWRStore.swift` | `.cachesDirectory` ETag/JSON SWR snapshot persistence for cold start | `GET /api/tv/v1/home` (`If-None-Match` / `304`) | — |
| `Sources/Core/Cache/ArtworkPipeline.swift` | Off-main-actor image download/downsample cache & BlurHash decoding | Same-origin artwork auth & CDN fetch | `PlayerOverlayAndCacheTests.swift`, `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Models/*.swift` | `Codable` contracts (`HomeModels`, `DetailModels`, `PlaybackModels`, `ChapterModels`) | `/api/tv/v1` JSON schemas & chapter classifier | `ModelDecodingTests.swift`, `ChapterClassificationTests.swift`, `PlaybackAndNavigationFixesTests.swift` |

## 2. Features & Design System (`Sources/DesignSystem/`, `Sources/Features/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/DesignSystem/LunaTheme.swift` | Warm espresso & honey-brass OLED/HDR palette, cinema glass surfaces, vector crescent mark, matte pill styles, stale-free `CachedArtworkView` | — | `CatScaleAndButtonThemeTests.swift` |
| `Sources/DesignSystem/Cards/` | `PosterCardView`, `BackdropCardView`, isolated `@FocusState`, unified 1 pt warm frames & context menus | Artwork pipeline loading | — |
| `Sources/DesignSystem/AmbientBackdropView.swift` | Static warm charcoal/espresso canvas with subtle candlelight glow (paused during video playback) | — | — |
| `Sources/Features/Shared/MediaCardComponents.swift` | `TransientErrorBanner`, `MediaCardMutator`, shared poster context-menu actions | `POST /api/tv/v1/{watchlist,watched,continue/remove,rows/:id/remove}` | `V250NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Onboarding/PairingOnboardingView.swift` | `_lunacore._tcp` auto-discovery & 6-digit pairing code flow (`lunacore.local`) | `POST /api/tv/v1/pair/request`, `GET /pair/poll/:code` | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Home/` | `HomeView`, `ShelfRowView` (4-row evening home with SWR instant paint & ongoing/list removal) | `GET /api/tv/v1/home` | `PlaybackAndNavigationFixesTests.swift` |
| `Sources/Features/Browse/` | `CatalogBrowseView`, `CustomRowBrowseView` (paginated genres & shelves) | `GET /api/tv/v1/catalog/*`, `/api/tv/v1/rows/*` | `PlaybackAndNavigationFixesTests.swift` |
| `Sources/Features/Library/LibraryHubView.swift` | *Mitt bibliotek*: *Huskeliste*, *Egne lister*, and *Lokalt på NAS* (with delete) | `GET /api/tv/v1/library?section={watchlist,lists,local}` | `V250NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Search/SearchView.swift` | Instant search across local library and TMDB catalog | `GET /api/tv/v1/search` | — |
| `Sources/Features/Detail/` | `MediaDetailView`, `DetailHeroHeaderView`, `DetailSeasonsSectionView`, `DetailDeleteSheetView`, `DetailPreResolveController`, `SourcePickerSheetView`, `EpisodeCardView` | `GET /items/*`, `POST /monitor`, `POST /delete/{preflight,}`, `POST /playback/prepare`, `GET /playback/:id/alternatives` | `PlaybackAndNavigationFixesTests.swift`, `ModelDecodingTests.swift`, `LunaNavigationAndDetailRaceTests.swift`, `V250NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsView.swift` | 2-column settings (*Rom & Skjerm · Lyd & Synk · Undertekster · Avspilling · System*), room/hardware profiles, DV/speaker/MetalFX, subtitle comfort | `PATCH /api/tv/v1/device/profile`, `GET /bootstrap` | `PlayerOverlayAndCacheTests.swift`, `V250NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Player/` | `PlayerViewModel`, `PlayerSessionCoordinator`, `PlayerAudioSessionCoordinator`, `PlayerContainerView`, `PlayerEngineConfigurator`, `PlayerNowPlayingCoordinator`, `SiriRemoteTouchSurface`, `ResolvingCurtainView`, `PlayerBottomBarView`, `PlayerTopDrawerView`, `ScrubPreviewBubbleView`, `SubtitleOverlayView`, `SeriesFlowOverlays`, `NerdHUDView` | `POST /playback/resolve`, `POST /heartbeat`, `POST /playback/:id/switch` | `ChapterClassificationTests.swift`, `SmartTrackRuleEngineTests.swift`, `PlayerOverlayAndCacheTests.swift`, `PlaybackAndNavigationFixesTests.swift`, `PausedScrubCommitTests.swift`, `PlayerExitBlinkRegressionTests.swift` |

## 3. Build Configuration & Cloud CI

- `project.yml`: XcodeGen specification (`MARKETING_VERSION: "2.5.0"`, `CURRENT_PROJECT_VERSION: "52"`, `bundleIdPrefix: local.lunacore`, `PRODUCT_BUNDLE_IDENTIFIER: local.lunacore.luna`).
- `Config/Info.plist`: App Transport Security (`NSAllowsArbitraryLoads`) & Bonjour service type (`_lunacore._tcp`).
- `Packages/AetherBridge/Package.swift`: Local SwiftPM wrapper pinning `AetherEngine` `7.69.0` and its 5 media/audio/DV traits.
- `.github/workflows/build-tvos.yml`: Static guardrails (800 LOC, `0644`, no `Bundle.main.bundleIdentifier`, zero private infra leaks, zero retired legacy brand references), `LunaTests`, unsigned tvOS Release archive, and publishing `Luna-unsigned.ipa` to the rolling `latest` release.
