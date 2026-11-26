# Luna (`v3.0.0`) — Codebase Module Map

Complete 1:1 module, endpoint, build, and XCTest inventory for `Luna` (enforced bidirectionally by `ops/bin/luna-check`).

## 1. App Shell, Discovery, Config, Cache & Models (`Sources/App/`, `Sources/Core/`)

| Module Path | Responsibility | `/api/tv/v2` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/App/LunaApp.swift` | Owns single `@MainActor AetherEngine`, root `AppSessionStore`, `ComfortPreferences` & `--preview-screen` boot | — | `LunaCoreLinuxTests.swift` |
| `Sources/App/PreviewLaunchConfiguration.swift` | Parses `--preview-screen` (`home`, `home-poster`, `catalog`, `catalog-series`, `library`, `search`, `details`, `detail-movie`, `detail-source-picker`, `settings`, `player-osd`, `player-scrub`, `player-subtitles`, `player-audio`, `player-source`, `player-picture`, `player-chapters`, `player-skip-intro`, `player-next-episode`, `player-error`) & `--preview-focus` CLI arguments | — | `CatalogShelfAndStorageLinuxTests.swift` |
| `Sources/App/PreviewMockFixtures.swift` | Deterministic offline Lampelys Home, catalog & library fixtures | Mock `/api/tv/v2/*` | `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/App/PreviewMockDetailAndPlayerFixtures.swift` | Deterministic 28-season detail & playback session fixtures | Mock `/api/tv/v2/*` | `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/App/PreviewMockURLProtocol.swift` | Offline `URLProtocol` router for preview mode & Linux/tvOS tests | Mock `/api/tv/v2/*` | `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/App/PreviewMockArtworkRenderer.swift` | Procedural CoreGraphics Lampelys cinema artwork & scrub preview PNG generator for preview mode | `/preview-art/*` | — |
| `Sources/App/MainNavigationShell.swift` | Owns 5 root tab VMs, custom top bar + hidden stock tab bar, 4 GB memory-warning grid eviction, room atmosphere & player sheet | `GET /api/tv/v2/bootstrap` | `LunaNavigationAndDetailRaceTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/App/LunaNavigationBarVisibility.swift` | Pure-Swift `MainNavigationTab` (*Hjem · Filmer · Serier · Bibliotek* + *Søk/Innstillinger*), scroll collapse & Menu-wakeup policy | — | `LunaNavigationAndDetailRaceTests.swift`, `ArtworkCacheAndNavigationPolicyTests.swift` |
| `Sources/App/LunaNavigationBarVisibilityModifier.swift` | SwiftUI `EnvironmentValues` keys and `lunaRootScrollTopBarTracking` scroll-geometry modifier | — | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/App/LunaTopBarView.swift` | Left-aligned crescent mark, divider & tabs (`x=90`) + right-anchored `56×56` utility triggers (`x=1830`), single `.focusSection()`, resting `22×2.5 pt` bronze underline & deterministic `Down` bridges | — | `LunaNavigationAndDetailRaceTests.swift`, `ThemeAndArtworkViewTests.swift` |
| `Sources/Core/Discovery/BonjourServiceParser.swift` | Pure-Swift `DiscoveredLunaCoreServer`, dual-stack `BonjourDiscoveryPolicy` & TXT/IPv4/IPv6 mDNS parser | mDNS `_lunacore._tcp` (`api=/api/tv/v2`, `https_port`) | `BonjourServerBrowserTests.swift`, `ServerFailoverAndComfortModelsTests.swift` |
| `Sources/Core/Discovery/BonjourServerBrowser.swift` | Dual-stack `NWBrowser` discovery for `_lunacore._tcp`, publishes `DiscoveredLunaCoreServer` | mDNS `_lunacore._tcp` (`api`, `https_port`) | `BonjourServerBrowserTests.swift` |
| `Sources/Core/Config/SideloadSafeStorage.swift` | Bundle-ID-independent `UserDefaults` + Keychain persistence (`luna.v1.*`) | — | `SideloadSafeStorageTests.swift` |
| `Sources/Core/Config/DeviceHardwareCapabilities.swift` | Runtime RAM tier (`DeviceMemoryProfile`), cached hardware AV1 (`VideoToolbox`) detection & A19 playback budgets | `X-Supports-HW-AV1`, `X-Physical-Memory-GB` | `LunaCoreLinuxTests.swift`, `NetworkCacheAndMemoryProfileTests.swift` |
| `Sources/Core/Config/ServerFailoverPolicy.swift` | Pure-Swift `HardwareProfilePreset` & `ServerFailoverPolicy` (`isFailoverEligibleError`, candidate ordering, `/api/tv/v2` URL normalization, LAN TLS host trust) | — | `ServerFailoverAndComfortModelsTests.swift`, `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Config/ServerConfiguration.swift` | `AppSessionStore`, stop-receipt waiter hub, failover runner, LAN TLS evaluator & `LunaCoreClient` factory | — | `ClientOriginAndBlurHashTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Config/ComfortPreferenceModels.swift` | Pure-Swift comfort & player enum presets (`SubtitleFontSizePreset`, `SpeakerLayoutOverrideMode`, `LowResUpscaleMode`, etc.) | — | `ServerFailoverAndComfortModelsTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Config/ComfortPreferences.swift` | Subtitle preset/scale/box, DV P7 FEL, speaker & MetalFX upscaling settings | `PATCH /api/tv/v2/device/profile` | `PlayerOverlayAndCacheTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Core/Config/PlaybackPreferenceStore.swift` | Non-isolated `luna.v1.*` persistence for per-title «Norsk tale» & per-candidate `subtitleDelayMs` | — | `PlayerLanguageAndPreferenceTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Core/Config/SmartTrackRuleEngine.swift` | Automatic Nordic/English audio & subtitle track matching | — | `SmartTrackRuleEngineTests.swift` |
| `Sources/Core/Config/TabMemoryEvictionPolicy.swift` | Pure-Swift inactive-tab memory-warning eviction policy for 4 GB models | — | `HomeCatalogLibraryViewModelsTests.swift` |
| `Sources/Core/Config/TabSessionContracts.swift` | Pure-Swift client/session/discovery protocols decoupling `LunaCore` ViewModels from UIKit/Network | — | `HomeCatalogLibraryViewModelsTests.swift`, `SearchPairingAndRoomProfileTests.swift` |
| `Sources/Core/Cache/ArtworkSubjectKey.swift` | Pure-Swift `ArtworkLoadPriority`, pixel buckets, raw URL identity & size-agnostic `/api/tv/v2/img/*` subject key normalization | `/api/tv/v2/img/*`, `/api/media/v2/img/*` | `ArtworkCacheAndNavigationPolicyTests.swift`, `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Cache/ArtworkPipeline.swift` | Off-main-actor image download/downsample cache & BlurHash placeholder pipeline | Same-origin artwork auth & CDN fetch | `ClientOriginAndBlurHashTests.swift`, `PlayerArtworkMemoryTests.swift` |
| `Sources/Core/Cache/ArtworkDiskCache.swift` | Linux-compatible `ArtworkDiskCache` (SHA-256 disk keys, read-touch LRU, `Caches/Luna/img` migration) & native `CGImage` `Mutex` memory cache | `.cachesDirectory/Luna/img` | `ArtworkCacheAndNavigationPolicyTests.swift`, `PlayerArtworkMemoryTests.swift` |
| `Sources/Core/Cache/BlurHashDecoder.swift` | Pure-Swift BlurHash DCT pixel decoder (`decodePixels` -> RGBA8888) | — | `ArtworkCacheAndNavigationPolicyTests.swift`, `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Cache/BlurHashImageCache.swift` | Darwin `CoreGraphics` `CGImage` wrapper & `InflightTaskCoalescer` cache over `BlurHashDecoder` | — | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Core/Cache/DiskSWRStore.swift` | `.cachesDirectory` multi-tab ETag/JSON SWR snapshot persistence (`Home`, `Filmer`, `Serier`, `Bibliotek`) for cold start & memory recovery | `GET /api/tv/v2/{home,catalog/*,library}` (`If-None-Match` / `304`) | `DiskSWRStoreTests.swift`, `DiskSWRStoreMultiTabLinuxTests.swift`, `LunaCoreLinuxTests.swift` |
| `Sources/Core/Cache/InflightTaskCoalescer.swift` | Waiter-isolated in-flight task deduplicator, `BoundedLRUMemoryCache` & directory byte counter | — | `NetworkCacheAndMemoryProfileTests.swift`, `LunaCoreHTTPTransportTests.swift` |
| `Sources/Core/Catalog/CatalogShelfIndexer.swift` | Pure-Swift shelf deduplication, server-ordered shelves (`Kommende episoder`), `Fra iPhone`/`I kveld` continue ordering & tier indexing | — | `DynamicHomeRowTests.swift`, `LunaCoreLinuxTests.swift` |
| `Sources/Core/Playback/DolbyVisionFallbackPolicy.swift` | Pure-Swift Profile 7 FEL frame-drop threshold policy for 1-tap `Bytt til HDR10-baselag` | — | `PlayerLanguageAndPreferenceTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Core/Playback/OriginalLanguageTrackSelector.swift` | Pure-Swift `originalLanguage` lossless audio ranking (`TrueHD Atmos` > `DTS:X` > lossless) + «Norsk tale» override | — | `PlayerLanguageAndPreferenceTests.swift`, `SmartTrackRuleEngineTests.swift` |
| `Sources/Core/Playback/PlaybackCoreAbstractions.swift` | Pure-Swift `PlaybackCurtainWatchdog` & `180 ms` `0-RTT` `PlaybackCurtainPresentationPolicy` | — | `LunaCoreLinuxTests.swift`, `SeriesFlowAndCurtainPolicyTests.swift` |
| `Sources/Core/Playback/PlaybackSessionPolicy.swift` | Pure-Swift playback completion (`>= 75%` + credits/post-credits), media-type inference & initial `subtitleDelayMs` policy | — | `PlayerLanguageAndPreferenceTests.swift` |
| `Sources/Core/Playback/PlaybackStopReceipt.swift` | Pure-Swift `PlaybackStopReceipt` & `@MainActor PlaybackStopReceiptStore` for post-playback `nextUp` wakeup | — | `TvV2ClientAndPlaybackReceiptTests.swift`, `PlayerExitBlinkRegressionTests.swift` |
| `Sources/Core/Playback/PlaybackSubtitleSyncActionPolicy.swift` | Pure-Swift sofa subtitle search-and-attach & auto-align merge/matching helpers | — | `PlayerLanguageAndPreferenceTests.swift` |
| `Sources/Core/Playback/PlaybackTrackIntent.swift` | Pure-Swift `PlaybackSyncTimingPolicy` (`ms` sync step/clamp/format) & `PlaybackTrackIntent` track/forced/off matcher across MKV switches | — | `PlaybackTrackIntentAndSyncTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Core/Playback/PlayerOSDVisibilityPolicy.swift` | Pure-Swift OSD visibility, `12 s` OLED pause rest & subtitle visibility policy | — | `PlayerOverlayPolicyAndStingerTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Playback/PlayerStartupState.swift` | Isolated `@Observable` startup & WebSocket resolve progress state | — | `PlayerOverlayPolicyAndStingerTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Playback/PlayerTimelinePolicy.swift` | Pure-Swift `0.5 s` / `2.0 s` / `10.0 s` clock bucketing, 24h `Slutter kl. HH:mm` formatter & 6-step `Menu` (`PlayerExitAction`) resolver | — | `PlayerTimelinePolicyTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Core/Playback/RemoteScrubMath.swift` | Paused-only Siri Remote pan breakaway (`20 pt`), `0 pt` reversal deadzone, EMA velocity (`α=0.35`), 3-zone duration-adaptive scrub curve & `< 280 ms` ring-hold speeds | — | `LunaCoreLinuxTests.swift`, `RemoteScrubMathTests.swift` |
| `Sources/Core/Playback/SeriesFlowEligibility.swift` | Pure-Swift stream duration, resume-banner, `Neste episode` & `.postCredits` (`>= 25 s` tail) stinger skip eligibility | — | `PlayerOverlayPolicyAndStingerTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Playback/SeriesFlowPolicy.swift` | Pure-Swift `ActiveSeriesOverlayKind`, directional `SeriesFlowPolicy` (`Spill nå ↔ Skjul`), 1-click auto-focus & `10 s` `NextEpisodeCountdownState` | — | `SeriesFlowAndCurtainPolicyTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Core/Playback/SubtitleOverlayLayout.swift` | Pure-Swift collision-free subtitle placement geometry across OSD, series cards, quick-panel & `NerdHUDView` | — | `PlayerOverlayPolicyAndStingerTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Core/Models/ChapterModels.swift` | Chapter & intro/recap/credits/post-credits (`Etter rulletekst`) classification models | `chapters[]` metadata | `ChapterClassificationTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/Core/Models/DetailModels.swift` | `Codable` item detail, seasons, episodes & source candidate models | `GET /api/tv/v2/items/*` | `ModelDecodingTests.swift`, `MediaDetailViewModelTests.swift` |
| `Sources/Core/Models/EpisodeTitleFormatter.swift` | Norwegian/Nordic episode label & air-date formatting helpers | — | `EpisodeTitleFormattingTests.swift` |
| `Sources/Core/Models/MediaCardModels.swift` | `Codable` card IDs, availability, watch progress, direct-play target & `TvMediaCard` core display models (`< 260 LOC`) | `/api/tv/v2/{home,catalog/*,library}` | `ModelDecodingTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Core/Models/HomeShelfModels.swift` | `Codable` home shelf rows, `TvTonightPayload`, `TvHomeResponse`, `TvRowPageResponse` & shelf card helpers (`< 260 LOC`) | `GET /api/tv/v2/{home,rows/*}` | `ModelDecodingTests.swift`, `DynamicHomeRowTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Models/CatalogAndLibraryModels.swift` | `Codable` catalog filters, `TvLibraryCustomList`, `TvLibraryCounts`, `TvLibraryResponse`, `TvRoomDefinition` (`speakerLayout`) & bootstrap DTOs (`< 260 LOC`) | `GET /api/tv/v2/{bootstrap,catalog/*,library}` | `ModelDecodingTests.swift`, `SearchPairingAndRoomProfileTests.swift` |
| `Sources/Core/Models/PlaybackDrawerModels.swift` | `HDRSubtitlePreset`, `PlayerQuickPanelTab`, `PlayerDrawerAudioOption`, `PlayerDrawerSubtitleOption` & `TvCandidateInfo` display helpers | — | `PlaybackTrackIntentAndSyncTests.swift`, `ModelDecodingTests.swift` |
| `Sources/Core/Models/PlaybackModels.swift` | `Codable` playback prepare, resolve, heartbeat, QoS, subtitle search/align, switch & alternative models | `/api/tv/v2/playback/*` | `ModelDecodingTests.swift`, `PlaybackTitleAndNowPlayingTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/Core/Models/TvDeletionModels.swift` | `Codable` delete preflight & execution request/response DTOs | `POST /api/tv/v2/delete/{preflight,}` | `NavigationSettingsAndDeleteTests.swift` |

## 2. Networking (`Sources/Core/Networking/`) & AetherEngine Bridge (`Packages/AetherBridge/`)

| Module Path | Responsibility | `/api/tv/v2` Endpoints & Protocols | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/Core/Networking/LunaCoreHTTPTransport.swift` | `LunaCoreClient`, `LunaCoreError`, `ConditionalHTTPResult`, `InflightTaskCoalescer` key disambiguation, HTTP request builder & JSON decoding | All `/api/tv/v2/*` HTTP transport | `LunaCoreHTTPTransportTests.swift`, `ClientOriginAndBlurHashTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+HomeCatalog.swift` | Pairing, bootstrap, conditional `/home`, catalog & custom row requests | `/pair/*`, `/bootstrap`, `/home`, `/catalog/*`, `/rows/*` | `DynamicHomeRowTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+LibraryDetail.swift` | Conditional `/library` (`If-None-Match`/`304`, `TvLibrarySectionFilter`), item detail, search, monitor, watchlist/watched, custom row & delete mutations | `/library`, `/items/*`, `/search`, `/monitor`, `/watchlist`, `/watched`, `/delete/*` | `MediaDetailViewModelTests.swift`, `NavigationSettingsAndDeleteTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/Core/Networking/LunaCoreClient+Playback.swift` | Playback prepare, resolve, heartbeat (+ QoS/delay), source switch, item candidates & subtitle search/auto-align | `/playback/{prepare,candidates,resolve,heartbeat,*/switch,*/alternatives,*/subtitles/*}` | `PlaybackTitleAndNowPlayingTests.swift`, `SeriesFlowAndHomePolicyTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Sources/Core/Networking/LunaCoreSessionPool.swift` | Shared ephemeral `URLSession` lanes (`api`, `artwork`, `ws`) + `LanURLSessionDelegate` | HTTP keep-alive & LAN self-signed TLS | `LunaCoreSessionPoolTests.swift` |
| `Sources/Core/Networking/PlaybackResolveSocket.swift` | Protocol-abstracted (`PlaybackResolveSocketProviding`) `AsyncThrowingStream` WebSocket client for playback resolution progress | `WS /api/tv/v2/ws/playback/:resolveId` | `PlaybackResolveSocketTests.swift`, `TvV2ClientAndPlaybackReceiptTests.swift` |
| `Packages/AetherBridge/Package.swift` | Local SwiftPM wrapper pinning `AetherEngine` `7.73.0` + 5 audio/DV traits (`tvOS 26.0`, Swift `6.2`) | SwiftPM (`TrueHD`, `DTSX`, `DualLayerDV`, `FelCurves`, `StillReshaping`) | — |
| `Packages/AetherBridge/Sources/AetherBridge/Exports.swift` | Public `@_exported import AetherEngine` re-export for app & test targets | — | — |

## 3. Design System & Feature Modules (`Sources/DesignSystem/`, `Sources/Features/`)

| Module Path | Responsibility | `/api/tv/v2` Endpoints | Unit Test Coverage |
| :--- | :--- | :--- | :--- |
| `Sources/DesignSystem/Tokens/LunaTokens.swift` | Generated platform-scaled colors, typography, radii & focus springs from `design/tokens.json` | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaTheme.swift` | Warm espresso & honey-brass OLED/HDR palette, `LunaRoomAtmosphere` & card tint resolvers | — | `ThemeAndArtworkViewTests.swift`, `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaThemeTypography.swift` | `LunaTheme.Font` 10-foot typography & role tokens (`heroSerif`, `titleSerif`, `pageTitle`, `sectionTitle`, `cardTitle`, `body`, `subtitle`, `caption`, `badge`) | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaCrescentMarkView.swift` | Clean vector crescent moon brand mark (`LunaCrescentMarkView`) | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/LunaPillButton.swift` | Focus-safe `LunaChromelessButtonStyle`, `LunaPillButton`, `LunaButtonProminence/Accent/Size` | — | `ThemeAndArtworkViewTests.swift`, `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaTextField.swift` | Dark-surface chromeless tvOS text input (`LunaTextField` + `NonFocusableTVTextField`) eliminating white `UITextField` focus pills | — | `AppPolishAndDetailZeroRTTTests.swift` |
| `Sources/DesignSystem/CachedArtworkView.swift` | Off-main-actor key-matched artwork view preventing 1-frame recycled cell flash | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/LunaFocusStyle.swift` | Shared `0.32/0.86` tvOS focus spring, `.card`/`.control`/`.listRow` modifiers & room glow | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/LunaBadges.swift` | Borderless `LunaArtBadge`, `LunaTierDotView` & `56×56` `LunaIconButton` | — | — |
| `Sources/DesignSystem/LunaListRow.swift` | Canonical `LunaSectionHeader`, single-frame `LunaListGroup`, `LunaListDivider`, `LunaInfoRow`, `LunaControlRow` & `LunaListRow` (`1.0x`) | — | — |
| `Sources/DesignSystem/LunaSheetContainer.swift` | Unified `880`/`1240 pt` `LunaSheetContainer` modal frame (`48 pt` padding, `Surface.sheet`) | — | — |
| `Sources/DesignSystem/LunaInlineStateViews.swift` | Left-aligned `LunaLoadingRow`, `LunaEmptyState`, `LunaInlineError`, `LunaToast` & `PlayerStatusPill` | — | — |
| `Sources/DesignSystem/LunaCopy.swift` | Norwegian pluralization, comma decimal formatter, room/tier labels & greetings | — | `DesignTokensAndCopyTests.swift` |
| `Sources/DesignSystem/AmbientBackdropView.swift` | Static warm charcoal/espresso ambient glow backdrop (paused during playback) | — | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/Cards/PosterCardView.swift` | Isolated `@FocusState` poster card (`280×420` shelf / `260×390` grid; resting title, metadata & `LunaTierDotView` in grids, focus-only captions on shelves) | Artwork pipeline loading | `ThemeAndArtworkViewTests.swift` |
| `Sources/DesignSystem/Cards/BackdropCardView.swift` | Isolated `@FocusState` 520×293 16:9 card (`continueWatching`, `upcomingEpisode`, `standard`, `LunaArtBadge`, focus-only `LunaTierDotView` & progress bar) | Artwork pipeline loading | `ThemeAndArtworkViewTests.swift` |
| `Sources/Features/Shared/MediaCardComponents.swift` | `MediaCardMutator` & shared context-menu mutations | `POST /api/tv/v2/{watchlist,watched,continue/remove,rows/:id/remove}` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Shared/SourceCandidateRowView.swift` | Unified source release candidate row shared between `SourcePickerSheetView` & `PlayerQuickPanelView` | — | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Onboarding/PairingOnboardingView.swift` | `_lunacore._tcp` auto-discovery & 6-digit pairing UI bound to `PairingViewModel` | — | `ClientOriginAndBlurHashTests.swift` |
| `Sources/Features/Onboarding/PairingViewModel.swift` | Pure-Swift `@Observable` discovery & pairing code polling ViewModel (`LunaCore`) | `POST /api/tv/v2/pair/request`, `GET /pair/poll/:code` | `SearchPairingAndRoomProfileTests.swift` |
| `Sources/Features/Home/HomeRefreshPolicy.swift` | Pure-Swift foreground revalidation debounce policy (`LunaCore`) | — | `HomeCatalogLibraryViewModelsTests.swift`, `SeriesFlowAndHomePolicyTests.swift` |
| `Sources/Features/Home/HomeViewModel.swift` | Pure-Swift `@Observable` Home SWR, conditional ETag refresh, warmup & card mutation ViewModel (`LunaCore`) | `GET /api/tv/v2/home` | `HomeCatalogLibraryViewModelsTests.swift` |
| `Sources/Features/Home/HomeView.swift` | 4-row evening home UI with native `ScrollPosition` & context-menu shelf mutators | — | `SeriesFlowAndHomePolicyTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Features/Home/ShelfRowView.swift` | Horizontal focus-safe shelf carousel supporting continue, upcoming (`upcoming_backdrop`), backdrop & poster styles | — | `DynamicHomeRowTests.swift` |
| `Sources/Features/Browse/CatalogBrowseViewModel.swift` | Pure-Swift `@Observable` paginated catalog ViewModel, `CatalogSortOption` & `CatalogBrowseMemoryCache` (`LunaCore`) | `GET /api/tv/v2/catalog/{movies,series}` | `HomeCatalogLibraryViewModelsTests.swift` |
| `Sources/Features/Browse/CatalogBrowseView.swift` | Paginated genre & sort catalog browser UI with native `ScrollPosition` | — | `SeriesFlowAndHomePolicyTests.swift`, `AppPolishAndDetailZeroRTTTests.swift` |
| `Sources/Features/Browse/CatalogFilterBarView.swift` | Fixed left sort/filter triggers, `56 pt` edge-masked genre scroller & `LunaSheetContainer` sort picker | — | `AppPolishAndDetailZeroRTTTests.swift` |
| `Sources/Features/Browse/CustomRowContextPolicy.swift` | Pure-Swift custom row ID normalization (`/api/tv/v2/rows/` & `/v1/rows/`) & removal action policy (`LunaCore`) | — | `HomeCatalogLibraryViewModelsTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Browse/CustomRowBrowseView.swift` | Paginated custom row browser | `GET /api/tv/v2/rows/:id` | `DynamicHomeRowTests.swift` |
| `Sources/Features/Library/LibraryFilterSection.swift` | Pure-Swift 4-pill `LibraryFilterSection` (*Filmer · Serier · Huskeliste · Lister*), fallback resolver & `LibraryBrowseMemoryCache` (`LunaCore`) | — | `HomeCatalogLibraryViewModelsTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Features/Library/LibraryViewModel.swift` | Pure-Swift `@Observable` Bibliotek SWR, `If-None-Match`/`304` & `customLists` ViewModel (`LunaCore`) | `GET /api/tv/v2/library` | `HomeCatalogLibraryViewModelsTests.swift` |
| `Sources/Features/Library/LibraryHubView.swift` | Clean 4-pill horizontal Bibliotek hub (*Filmer · Serier · Huskeliste · Lister · N*) with 6-column `260×390` poster grid & custom lists navigation | — | `NavigationSettingsAndDeleteTests.swift`, `DynamicHomeRowTests.swift` |
| `Sources/Features/Search/SearchViewModel.swift` | Pure-Swift `@Observable` debounced search ViewModel with structured cancellation & memory unload (`LunaCore`) | `GET /api/tv/v2/search` | `SearchPairingAndRoomProfileTests.swift` |
| `Sources/Features/Search/SearchView.swift` | Instant search UI across local library & TMDB catalog with native `ScrollPosition` | — | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailView.swift` | Title detail container coordinating hero, seasons, source picker & delete sheet | `GET /api/tv/v2/items/*` | `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailViewModel.swift` | Observable detail state, episode loading & pre-resolve orchestration | `GET /items/*`, `GET /playback/:id/alternatives` | `MediaDetailViewModelTests.swift`, `LunaNavigationAndDetailRaceTests.swift` |
| `Sources/Features/Detail/MediaDetailViewModel+Mutations.swift` | Watchlist, watched, follow/monitor & preflight delete mutations | `POST /monitor`, `/watchlist`, `/watched`, `/delete/*` | `MediaDetailViewModelTests.swift`, `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Detail/DetailHeroHeaderView.swift` | Editorial `heroSerif` 4K header, metadata watched indicator, `LunaTierDotView` format line, Play/Kilde/Huskeliste/Mer actions | — | — |
| `Sources/Features/Detail/DetailMoreAndOverviewSheets.swift` | «Mer» action sheet (`Les hele handlingen`, `Sett`, `Følg`, `Slett`) & `titleSerif` overview modal in `LunaSheetContainer` | — | — |
| `Sources/Features/Detail/DetailSeasonsSectionView.swift` | Season tabs, 4-column `LunaListRow` season picker & horizontal episode strip with default focus on next episode | — | — |
| `Sources/Features/Detail/EpisodeCardView.swift` | Focusable episode tile with progress, air badge, «Neste for deg» & watched toggle | — | `EpisodeTitleFormattingTests.swift` |
| `Sources/Features/Detail/DetailPreResolveController.swift` | Pure-Swift background pre-resolve + `DetailStreamPrewarming` protocol (`LunaCore`) | `POST /playback/prepare` | `DetailAndSourcePickerViewModelTests.swift`, `PlaybackResolveSocketTests.swift` |
| `Sources/Features/Detail/SourcePickerViewModel.swift` | Pure-Swift `@Observable` release/source selector ViewModel & token policy (`LunaCore`) | `POST /playback/candidates`, `GET /playback/:id/alternatives` | `DetailAndSourcePickerViewModelTests.swift`, `AppPolishAndDetailZeroRTTTests.swift` |
| `Sources/Features/Detail/SourcePickerSheetView.swift` | Focusable release/source selector sheet in `LunaSheetContainer` using flat `LunaListRow` candidates | — | `ClientOriginAndBlurHashTests.swift`, `AppPolishAndDetailZeroRTTTests.swift` |
| `Sources/Features/Detail/DetailDeleteSheetView.swift` | Confined media deletion sheet with preflight byte summary | `POST /delete/{preflight,}` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsView.swift` | 2-column settings root (*Rom og skjerm · Undertekster · Avspilling · System · Avansert*) + shared `SettingsSectionPanel` & `SettingsToggleRowButton` | `PATCH /api/tv/v2/device/profile`, `GET /bootstrap` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsComfortSectionView.swift` | Unified Rom og skjerm (server room selector, MetalFX 4K upscaling, QMS menu display mode) + Kveldslys & autoplay | `PATCH /api/tv/v2/device/profile` | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Settings/SettingsAdvancedSectionView.swift` | DV P7 FEL, 7.1.4 / Stereo 2.0 speaker fallback, eARC sync, Nerd HUD & LAN self-signed TLS controls | `PATCH /api/tv/v2/device/profile` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Settings/SettingsServerDiagnosticsSectionView.swift` | Server connection, room equipment summary, cache clear & unified reconnect trigger | `GET /api/tv/v2/bootstrap` | `NavigationSettingsAndDeleteTests.swift` |
| `Sources/Features/Player/PlayerViewModel.swift` | Thin `@Observable` player facade owning 5 `@MainActor` controllers (`weak var host`, `0` retain cycles) | — | `PlayerExitBlinkRegressionTests.swift`, `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/PlayerSessionController.swift` | Owns engine mount, next-episode advance, curtain watchdog, two-phase dismissal & `PlaybackStopReceipt` emission | `POST /playback/{resolve,heartbeat}` | `PlayerExitBlinkRegressionTests.swift`, `PlaybackTitleAndNowPlayingTests.swift` |
| `Sources/Features/Player/PlayerSessionController+ResolveAndSwitch.swift` | Warm/cold playback resolve, alternatives fetch & seamless track-intent-preserving `switchSource` | `POST /playback/{resolve,*/switch}`, `GET /playback/:id/alternatives` | `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerResolvePipeline.swift` | Stateless WebSocket/HTTP resolve fallback & detached `stopped` heartbeat + `PlaybackStopReceipt` dispatch | `WS /playback/:id`, `POST /playback/heartbeat` | `PlayerExitBlinkRegressionTests.swift` |
| `Sources/Features/Player/PlayerTrackController.swift` | Audio/subtitle track selection, `ms` sync, `Lydmodus`, live MetalFX/speaker reloads & chapter merge | — | `SmartTrackRuleEngineTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerTrackController+SubtitleAndHDR.swift` | `originalLanguage` + «Norsk tale» toggle, sofa `search-and-attach` / `auto-align`, `Bytt til HDR10-baselag` & track-intent capture | `POST /playback/:id/subtitles/{search-and-attach,auto-align}` | `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerScrubController.swift` | Siri Remote touch scrub, ring-hold progressive seek, coalesced `±10 s` seek & compositor thumbnail worker | — | `PausedScrubCommitTests.swift`, `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/PlayerRestoreController.swift` | Scene foreground/background restore via `transport.reloadAtCurrentPosition`, paused-restore native audio & idle timer | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerQoSReporter.swift` | 15s QoS heartbeat loop, next-episode prewarm, remote commands & `0 Hz` thresholded `DolbyVisionFallbackPolicy` | `POST /playback/heartbeat` | `SeriesFlowAndHomePolicyTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerQoSReporter+Formatting.swift` | Live video/HDR/audio/MetalFX format badges & room layout labels | — | `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/PlayerContainerView.swift` | Full-screen `AetherPlayerSurface` host, curtain, HUD, subtitles & overlay orchestration | — | `PlayerExitBlinkRegressionTests.swift`, `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/PlayerContainerOverlayHelpers.swift` | Isolated overlay sub-builders, focus-restore/auto-hide tasks & `.onDisappear` `PlaybackStopReceipt` wiring | — | `PlayerExitBlinkRegressionTests.swift`, `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/PlayerOSDCoordinator.swift` | `0 Hz` OSD visibility, `12 s` OLED pause rest, pause-scrub focus handoff & 6-step `Menu` ladder | — | `PlayerTimelineAndScrubUXTests.swift`, `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/PlayerPreviewStageView.swift` | Offline preview cinema stage & `CoalescedSeekOverlayLeafView` | — | `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/PlayerAudioSessionCoordinator.swift` | `AVAudioSession` activation & route change handling | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerEngineConfigurator.swift` | Configures single `@MainActor AetherEngine` options, `originalLanguage` preferences & `LoadOptions` | — | `PlayerOverlayAndCacheTests.swift` |
| `Sources/Features/Player/PlayerEnginePublishers.swift` | Combine/observation bridge from `AetherEngine` publishers into the 5 player controllers | — | `PlaybackRestoreAndAudioSessionTests.swift` |
| `Sources/Features/Player/PlayerNowPlayingCoordinator.swift` | `MPNowPlayingInfoCenter` metadata & remote command center bindings | — | `PlaybackTitleAndNowPlayingTests.swift` |
| `Sources/Features/Player/PlayerTransportProtocol.swift` | Testable transport abstraction (`loadStream`, `reloadAtCurrentPosition`, `stop`) decoupling controllers from `AetherEngine` | — | `PlayerTestDoubles.swift` |
| `Sources/Features/Player/PlayerBottomBarView.swift` | Bottom transport OSD, `EndsAtLeafView`, `ActiveChapterLabelLeafView` & quick-action pill row | — | `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/PlayerTimelineScrubberView.swift` | Isolated leaf timeline scrubber (`TimelineScrubberLeafView`) observing `engine.clock` (`0.5 s` / `2.0 s` buckets) | — | `PausedScrubCommitTests.swift`, `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/PlayerQuickPanelView.swift` | Floating quick-panel shell (*Tekst · Lyd · Velg utgave · Bilde · Kapitler*) with `16 pt` GPU shadow & focus anchoring | `GET /playback/:id/alternatives` | `PlayerOverlayAndCacheTests.swift`, `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerQuickPanelSections.swift` | Quick-panel `Velg utgave`, `Bilde` (`Bytt til HDR10-baselag`) & `Kapitler` sections | — | `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/PlayerQuickPanelTrackSections.swift` | Quick-panel `Tekst` (`Hent undertekst…`, `Synk automatisk`, `Kveldslys`), `Lyd` (`Norsk tale`) & `ms` sync rows | — | `PlayerQuickPanelAndSwitchTests.swift` |
| `Sources/Features/Player/SiriRemoteTouchSurface.swift` | SwiftUI `UIViewRepresentable` wrapper for `TouchCaptureUIView` with `.focusEffectDisabled()` | — | `PausedScrubCommitTests.swift` |
| `Sources/Features/Player/TouchCaptureUIView.swift` | UIKit indirect clickpad pan, `< 280 ms` ring-click vs hold-to-scrub & focus-lock capture view | — | `PlayerTimelineAndScrubUXTests.swift` |
| `Sources/Features/Player/ResolvingCurtainView.swift` | Shared `PlayerCurtainBackdropView` + `180 ms` `0-RTT` grace curtain preventing HDMI black flash | — | `PlayerExitBlinkRegressionTests.swift`, `SeriesFlowAndCurtainPolicyTests.swift` |
| `Sources/Features/Player/ScrubPreviewBubbleView.swift` | Frame-accurate `284`/`252 pt` scrub thumbnail preview bubble (`>= 22 pt` typography) | — | `PlayerTimelineAndScrubUXTests.swift`, `ThemeAndArtworkViewTests.swift` |
| `Sources/Features/Player/SubtitleOverlayView.swift` | Collision-free leaf subtitle renderer (OSD, series cards, quick-panel & `NerdHUDView` corridors + single-pass shadow) | — | `PlayerOverlayAndCacheTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/SeriesFlowOverlays.swift` | 1-click auto-focused skip-intro/recap/stinger, isolated `10 s` next-episode countdown & resume banner coordinator | — | `SeriesFlowAndHomePolicyTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/SeriesFlowOverlays+Evaluation.swift` | Continuity, `.postCredits` stinger jump, move-command & dismissal state evaluation | — | `SeriesFlowAndHomePolicyTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/SeriesFlowCardViews.swift` | Lampelys `548 pt` `Neste episode` card (`152×86` `16:9` `stillUrl`), fixed-width chevron `SeriesSkipPromptPillView` & `Start på nytt` views | — | `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/NerdHUDView.swift` | `740 pt` 1 Hz telemetry diagnostics overlay (`184 pt` single-line keys, discrete `RAM-buffer` label) observing `engine.diagnostics` | — | `PlayerSeriesCurtainAndSubtitleTests.swift` |
| `Sources/Features/Player/PlayerFatalErrorOverlayView.swift` | Lampelys playback fatal-error recovery curtain (`PlayerCurtainBackdropView` + `Prøv på nytt`) & `±10 s` seek pill | — | `PlayerExitBlinkRegressionTests.swift`, `PlayerSeriesCurtainAndSubtitleTests.swift` |

## 4. Build, Guardrails, Actions & `LunaTests` (`Tests/LunaTests/`)

- **Build, Tokens & CI**: `VERSION` (`3.0.0`), `project.yml` (`tvOS: "26.0"`, `SWIFT_VERSION: "6.2"`, `MARKETING_VERSION: "3.0.0"`, `CURRENT_PROJECT_VERSION: "70"`, `bundleIdPrefix: local.lunacore`), `Package.swift` (`swift-tools-version: 6.2`, `.tvOS(.v26)`, Linux `LunaCore` test target), `design/tokens.json`, `preview/tokens.css`, `preview/index.html`, `preview/styles.css`, `preview/app.js`, `Resources/Localizable.xcstrings`, `ops/bin/luna-design-tokens`, `Config/Info.plist` (`NSAllowsArbitraryLoads`, `_lunacore._tcp`), `.github/workflows/build-tvos.yml` (`linux-core-tests` `swift:6.2` gate before `test-tvos`/`build-ipa`/`publish-release`), `.github/workflows/tvos-vision.yml` (`linux-core-tests` `swift:6.2` gate before `tvos-screenshots`), `scripts/test-core.sh` (`swift:6.2`), `scripts/preview-capture.sh`, `.github/actions/setup-tvos-xcode/action.yml` (`Xcode 26.2+/27`, `XcodeGen`), and `ops/bin/luna-check` (permissions, `<= 800 LOC`, `>= 22 pt` tvOS font floor, zero system `Material`, sideload, zero private infra leaks, version parity, token parity & bidirectional doc parity).
- **28 XCTest Suites + Test Doubles (`Tests/LunaTests/`)**:
  - `Tests/LunaTests/AppPolishAndDetailZeroRTTTests.swift`
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
  - `Tests/LunaTests/PlayerArtworkMemoryTests.swift`
  - `Tests/LunaTests/PlayerOverlayAndCacheTests.swift`
  - `Tests/LunaTests/PlayerQuickPanelAndSwitchTests.swift`
  - `Tests/LunaTests/PlayerSeriesCurtainAndSubtitleTests.swift`
  - `Tests/LunaTests/PlayerTimelineAndScrubUXTests.swift`
  - `Tests/LunaTests/SeriesFlowAndHomePolicyTests.swift`
  - `Tests/LunaTests/SideloadSafeStorageTests.swift`
  - `Tests/LunaTests/SmartTrackRuleEngineTests.swift`
  - `Tests/LunaTests/ThemeAndArtworkViewTests.swift`
  - `Tests/LunaTests/PlayerTestDoubles.swift` (shared player/transport test doubles)
- **Linux `LunaCoreTests` (`Package.swift` / `./scripts/test-core.sh`)**:
  - `Tests/LunaCoreTests/ArtworkCacheAndNavigationPolicyTests.swift` (native Linux x86_64 tests for `ArtworkSubjectKey`, `ArtworkDiskCache` SHA-256 keys, `Caches/Luna/img` migration & read-touch LRU trim, `BlurHashDecoder.decodePixels`, and `LunaNavigationBarVisibility` policies)
  - `Tests/LunaCoreTests/CatalogShelfAndStorageLinuxTests.swift` (native Linux x86_64 tests for cross-row `CatalogShelfIndexer` series deduplication, `ArtworkDecodeTargets`, `SideloadSafeStorage` & `PreviewLaunchConfiguration`)
  - `Tests/LunaCoreTests/DetailAndSourcePickerViewModelTests.swift` (native Linux x86_64 tests for `MediaDetailViewModel` `0 ms` `PlaybackStopReceipt` wakeup, `DetailPreResolveController` + `DetailStreamPrewarming`, and `SourcePickerViewModel`)
  - `Tests/LunaCoreTests/DiskSWRStoreMultiTabLinuxTests.swift` (native Linux x86_64 tests for multi-tab `DiskSWRStore` persistence, `ETag` round-trip & concurrent `clearAllAsync` race safety across `Home`, `Filmer`, `Serier` & `Bibliotek`)
  - `Tests/LunaCoreTests/Etappe6AdversarialHardeningTests.swift` (native Linux x86_64 Tier 5 adversarial hardening tests covering `/api/tv/v2/*` negative HTTP envelopes, `Int.max` sync overflow safety, malformed `BlurHash`, corrupt `DiskSWRStore`/`ArtworkDiskCache` recovery, `PlaybackStopReceiptStore` cancellation/isolation, `SideloadSafeStorage` fallback & `2.0` stereo downmix)
  - `Tests/LunaCoreTests/Etappe6ContractAcceptanceTests.swift` (native Linux x86_64 `swift-testing` contract acceptance suite for `/api/tv/v2/*` transport, `ETag`/`304`, `customLists`, subtitle search/auto-align, `InflightTaskCoalescer`, `.postCredits` stinger skip, `OriginalLanguageTrackSelector`, `DolbyVisionFallbackPolicy` & `ComfortPreferenceModels`)
  - `Tests/LunaCoreTests/Etappe6NumericOverflowTests.swift` (native Linux x86_64 regression suite covering numeric/overflow `SIGILL` bounds across `ChapterModels`, `PlayerTimelinePolicy`, `LunaCoreSessionPool`, `MediaDetailViewModel`, `PairingViewModel`, `PlaybackTrackIntent`, `LunaNavigationBarVisibility` & `LunaCoreClient+HomeCatalog`)
  - `Tests/LunaCoreTests/HomeCatalogLibraryEdgeTests.swift` (native Linux x86_64 regression tests for Home & Catalog ETag/scope isolation, memory-warning missing-cache `304` prevention, and `isLoadingMore`/`isInitialColdFetch` cancellation hygiene)
  - `Tests/LunaCoreTests/HomeCatalogLibraryViewModelsTests.swift` (native Linux x86_64 tests for `HomeViewModel`, `CatalogBrowseViewModel`, `LibraryViewModel`, `LibraryFilterSection` 4th `Lister · N` pill, `CustomRowContextPolicy`, `HomeRefreshPolicy` & `TabMemoryEvictionPolicy`)
  - `Tests/LunaCoreTests/LibraryEdgeTests.swift` (native Linux x86_64 regression tests for Library ETag clearing, section-switch error clearing & cold `.movies` -> `.series` fallback switching)
  - `Tests/LunaCoreTests/LunaCoreLinuxTests.swift` (native Linux x86_64 tests for `PlaybackCurtainWatchdog`, `LunaCoreClient`, same-origin token boundaries & `prepareToken` wire payloads)
  - `Tests/LunaCoreTests/NetworkCacheAndMemoryProfileTests.swift` (native Linux x86_64 tests for `DeviceMemoryProfile` 4 GB vs. 8 GB scaling, `InflightTaskCoalescer` deduplication & per-waiter cancellation isolation, and `BoundedLRUMemoryCache`)
  - `Tests/LunaCoreTests/PlaybackTrackIntentAndSyncTests.swift` (native Linux x86_64 unit tests for `PlaybackTrackIntent` MKV track-ID permutation matching, `ms` sync step/clamp/format, `Kveldslys` warm RGB presets & quick-panel tab switching)
  - `Tests/LunaCoreTests/PlayerLanguageAndPreferenceTests.swift` (native Linux x86_64 tests for `OriginalLanguageTrackSelector`, `PlaybackPreferenceStore`, `DolbyVisionFallbackPolicy`, `PlaybackSessionPolicy` & `PlaybackSubtitleSyncActionPolicy`)
  - `Tests/LunaCoreTests/PlayerOverlayPolicyAndStingerTests.swift` (native Linux x86_64 tests for `SeriesFlowEligibility.postCreditsSkipTargetSeconds`, `SubtitleOverlayLayout`, `PlayerOSDVisibilityPolicy` & `PlayerStartupState`)
  - `Tests/LunaCoreTests/PlayerTimelinePolicyTests.swift` (native Linux x86_64 unit tests for `0.5 s`/`2.0 s`/`10.0 s` clock bucketers, 24h `Slutter kl. HH:mm` formatting & all 6 steps of `PlayerTimelinePolicy.resolveExitAction`)
  - `Tests/LunaCoreTests/RemoteScrubMathTests.swift` (native Linux x86_64 unit tests for paused-only 3-zone scrubbing, `20 pt` breakaway, `0 pt` reversal, EMA smoothing & `< 280 ms` ring-hold speeds)
  - `Tests/LunaCoreTests/SearchPairingAndRoomProfileTests.swift` (native Linux x86_64 tests for `SearchViewModel`, `PairingViewModel`, and `SpeakerLayoutOverrideMode.resolveAutoSpeakerLayout` + `TvRoomDefinition` decoding)
  - `Tests/LunaCoreTests/SeriesFlowAndCurtainPolicyTests.swift` (native Linux x86_64 unit tests for `SeriesFlowPolicy` directional matrix, 1-click auto-focus, `10 s` `NextEpisodeCountdownState` & `180 ms` `0-RTT` `PlaybackCurtainPresentationPolicy`)
  - `Tests/LunaCoreTests/ServerFailoverAndComfortModelsTests.swift` (native Linux x86_64 unit tests for dual-stack `BonjourServiceParser`, `ServerFailoverPolicy`, and `ComfortPreferenceModels`)
  - `Tests/LunaCoreTests/TvV2ClientAndPlaybackReceiptTests.swift` (native Linux x86_64 unit tests for `InflightTaskCoalescer` typed keys, `PlaybackResolveSocketProviding`, `/api/tv/v2/*` endpoints, `fetchLibrary` `304`, subtitle search/auto-align, `.postCredits`, and `PlaybackStopReceiptStore`)
