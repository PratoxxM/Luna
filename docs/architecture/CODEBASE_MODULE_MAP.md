# Luna (`v2.3.0`) — Codebase Module Map

Quick lookup mapping relative repository paths to their responsibilities, **LunaCore** `/api/tv/v1` endpoints, and `Tests/LunaTests` coverage.

## 1. App Shell, Discovery & Networking (`Sources/App/`, `Sources/Core/`)

| Module Path | Responsibility | `/api/tv/v1` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/App/LunaApp.swift` | Owns single `@MainActor AetherEngine`, root `AppSessionStore`, `ComfortPreferences` | — | — |
| `Sources/App/MainNavigationShell.swift` | Top tab bar, server bootstrap sync (`fetchBootstrap`), playback presentation | `GET /api/tv/v1/bootstrap` | `PlayerOverlayAndCacheTests.swift` |
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
| `Sources/DesignSystem/LunaTheme.swift` | OLED/HDR palette, cinema glass surfaces, reusable pill/focus styles | — | — |
| `Sources/DesignSystem/Cards/` | `PosterCardView`, `BackdropCardView`, isolated `@FocusState`, context menus | Artwork pipeline loading | — |
| `Sources/DesignSystem/AmbientBackdropView.swift` | Blurred hero/detail ambient backdrop renderer | — | — |
| `Sources/Features/Shared/MediaCardComponents.swift` | `TransientErrorBanner`, `MediaCardMutator`, shared poster context-menu actions | `POST /api/tv/v1/{watchlist,favorite,watched}` | — |
| `Sources/Features/Onboarding/PairingOnboardingView.swift` | `_lunacore._tcp` auto-discovery & 6-digit pairing code flow (`lunacore.local`) | `POST /api/tv/v1/pair/request`, `GET /pair/poll/:code` | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Home/` | `HomeView`, `ShelfRowView` (4-row evening home with SWR instant paint) | `GET /api/tv/v1/home` | `PlaybackAndNavigationFixesTests.swift` |
| `Sources/Features/Browse/` | `CatalogBrowseView`, `CustomRowBrowseView` (paginated genres & shelves) | `GET /api/tv/v1/catalog/*`, `/api/tv/v1/rows/*` | `PlaybackAndNavigationFixesTests.swift` |
| `Sources/Features/Library/LibraryHubView.swift` | *Mitt bibliotek*: *Ønsker å se*, *Favoritter*, and *Lokalt på NAS* | `GET /api/tv/v1/library` | — |
| `Sources/Features/Search/SearchView.swift` | Instant search across local library and TMDB catalog | `GET /api/tv/v1/search` | — |
| `Sources/Features/Detail/` | `MediaDetailView`, `DetailHeroHeaderView`, `DetailPreResolveController`, `SourcePickerSheetView`, `EpisodeCardView`, `DetailCastStripView` | `GET /items/*`, `POST /playback/prepare`, `GET /playback/:id/alternatives` | `PlaybackAndNavigationFixesTests.swift`, `ModelDecodingTests.swift` |
| `Sources/Features/Settings/SettingsView.swift` | Room/hardware profiles, DV/speaker/MetalFX overrides, subtitle comfort, cache/pairing reset | `PATCH /api/tv/v1/device/profile`, `GET /bootstrap` | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/` | `PlayerViewModel`, `PlayerSessionCoordinator`, `PlayerContainerView`, `PlayerEngineConfigurator`, `PlayerNowPlayingCoordinator`, `SiriRemoteTouchSurface`, `ResolvingCurtainView`, `PlayerBottomBarView`, `PlayerTopDrawerView`, `ScrubPreviewBubbleView`, `SubtitleOverlayView`, `SeriesFlowOverlays`, `NerdHUDView` | `POST /playback/resolve`, `POST /heartbeat`, `POST /playback/:id/switch` | `ChapterClassificationTests.swift`, `SmartTrackRuleEngineTests.swift`, `PlayerOverlayAndCacheTests.swift` |

## 3. Build Configuration & Cloud CI

- `project.yml`: XcodeGen specification (`MARKETING_VERSION: "2.3.0"`, `CURRENT_PROJECT_VERSION: "16"`, `bundleIdPrefix: local.lunacore`, `PRODUCT_BUNDLE_IDENTIFIER: local.lunacore.luna`).
- `Config/Info.plist`: App Transport Security (`NSAllowsArbitraryLoads`) & Bonjour service type (`_lunacore._tcp`).
- `Packages/AetherBridge/Package.swift`: Local SwiftPM wrapper pinning `AetherEngine` `7.65.0` and its 5 media/audio/DV traits.
- `.github/workflows/build-tvos.yml`: Static guardrails (800 LOC, `0644`, no `Bundle.main.bundleIdentifier`, zero private infra leaks, zero retired legacy brand references), `LunaTests`, unsigned tvOS Release archive, and publishing `Luna-unsigned.ipa` to the rolling `latest` release.
