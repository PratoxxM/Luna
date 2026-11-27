# Luna (`v3.0.0`) — Codebase Module Map

Domain-level architecture, dual-target build boundary, `/api/tv/v2` surface mapping, and test layout for **Luna** (`tvOS 26.0`, Swift `6.2`, `AetherEngine 7.76.0`).

---

## 1. Dual-Target Build Topology

| Target | Manifest | Platform | Scope |
| :--- | :--- | :--- | :--- |
| **`LunaCore`** | `Package.swift` | Linux (`swift:6.2`) & macOS | Pure-Swift networking, `/api/tv/v2` DTOs, `DiskSWRStore`, `ArtworkDiskCache`, `BlurHashDecoder`, `SideloadSafeStorage`, `ServerSessionCore`, `CatalogShelfIndexer`, `SmartTrackRuleEngine`, pure ViewModels, and playback/timeline/scrub/series policies. Zero `SwiftUI`/`UIKit`/`AVFoundation` dependencies. |
| **`Luna`** | `project.yml` + `Packages/AetherBridge/` | `tvOS 26.0` (`arm64` & Simulator) | Full Lampelys 10-foot `SwiftUI`/`UIKit` app shell, `NWBrowser` Bonjour discovery, `CoreGraphics`/`ImageIO` `ArtworkPipeline`, `AVAudioSession`/QMS display criteria coordination, and single-instance `@MainActor AetherEngine` (`7.76.0`) playback host. |

---

## 2. Source Domains (`Sources/` & `Packages/`)

### `Sources/App/` — Lifecycle, Top Bar & Offline Preview Mode
- Owns the single app-lifetime `@MainActor AetherEngine`, root `MainNavigationShell` (*Hjem · Filmer · Serier · Bibliotek* + *Søk · Innstillinger*), `LunaTopBarView`, scroll-collapse/Menu-wakeup state (`LunaNavigationBarVisibility`), and deterministic `--preview-screen` / `--preview-focus` Simulator launch fixtures (`PreviewLaunchConfiguration`, `PreviewMockFixtures`, `PreviewMockURLProtocol`, `PreviewMockArtworkRenderer`).

### `Sources/Core/` — Networking, Discovery, Config, Cache, Models & Playback Policies
- **`Config/`**: Bundle-ID-independent `SideloadSafeStorage` (`luna.v1.*` keys for ATVLoadly OTA safety), `DeviceHardwareCapabilities` (`4 GB .standard` vs `8 GB .high2026` A19 memory/decode budgets), `ServerFailoverPolicy`, `@Observable ServerSessionCore` (`GET /api/tv/v2/bootstrap`, `PATCH /api/tv/v2/device/profile`), `AppSessionStore` Darwin adapter, `ComfortPreferences`, `PlaybackPreferenceStore`, and `SmartTrackRuleEngine`.
- **`Discovery/`**: Pure-Swift `BonjourServiceParser` and tvOS `NWBrowser` `BonjourServerBrowser` for dual-stack `_lunacore._tcp` mDNS discovery.
- **`Cache/`**: Multi-tab conditional ETag/JSON `DiskSWRStore`, size-agnostic `ArtworkSubjectKey`, SHA-256 `ArtworkDiskCache` + `ThreadSafeLRUMemoryCache`, `InflightTaskCoalescer`, pure-Swift `BlurHashDecoder`, and off-main-actor `CoreGraphics` `ArtworkPipeline` / `BlurHashImageCache`.
- **`Catalog/` & `Models/`**: `CatalogShelfIndexer` (handoff ordering & cross-row active-series deduplication), `Codable` `/api/tv/v2` DTOs (`MediaCardModels`, `HomeShelfModels`, `CatalogAndLibraryModels`, `DetailModels`, `PlaybackModels`, `PlaybackActionModels`, `PlaybackDrawerModels`, `TvDeletionModels`), `ChapterModels` (`theintrodb` + MKV merge & `.postCredits`), and `EpisodeTitleFormatter`.
- **`Networking/`**: `LunaCoreHTTPTransport`, `LunaCoreClient` extensions (`/pair/*`, `/bootstrap`, `/home`, `/catalog/*`, `/rows/*`, `/library`, `/items/*`, `/search`, `/monitor`, `/watchlist`, `/watched`, `/delete/*`, `/playback/*`), `LunaCoreSessionPool` (`api`, `artwork`, `ws` lanes + self-signed LAN TLS trust), and `PlaybackResolveSocket` (`WS /api/tv/v2/ws/playback/:resolveId`).
- **`Playback/`**: Pure-Swift playback state machines and math: `PlaybackCurtainWatchdog`, `PlaybackCurtainPresentationPolicy` (`180 ms` `0-RTT` grace), `PlayerTimelinePolicy` (`0.5s`/`2s`/`10s` buckets & 6-step `Menu` exit ladder), `RemoteScrubMath`, `PlaybackTrickplayPolicy`, `PlaybackTrackIntent`, `OriginalLanguageTrackSelector`, `PlaybackSubtitleSyncActionPolicy`, `DolbyVisionFallbackPolicy`, `EmbeddedFontNamePolicy`, `SubtitleOCRPolicy`, `SubtitleOverlayLayout`, and `SeriesFlowPolicy` / `SeriesFlowEligibility`.

### `Sources/DesignSystem/` — Lampelys 10-Foot Design System
- Generated `LunaTokens` (from `design/tokens.json`, `>= 22 pt` tvOS typography floor), `LunaTheme` & `LunaThemeTypography` (warm espresso `#0A0908` / `#14110F` & honey-brass `#C48C3A`), `LunaCopy` (Norwegian localization & pluralization paired with `Resources/Localizable.xcstrings`), `LunaFocusStyle`, `LunaPillButton`, `LunaListRow`, `LunaSheetContainer`, `LunaBadges`, `LunaTextField`, `CachedArtworkView`, `AmbientBackdropView`, and `PosterCardView` / `BackdropCardView`.

### `Sources/Features/` & `Packages/AetherBridge/` — Screens, ViewModels & Player Host
- **`Onboarding/`, `Home/`, `Browse/`, `Library/`, `Search/`, `Detail/`, `Settings/`, `Shared/`**: Pure-Swift `@Observable` ViewModels (`PairingViewModel`, `HomeViewModel`, `CatalogBrowseViewModel`, `LibraryViewModel`, `SearchViewModel`, `MediaDetailViewModel`, `DetailPreResolveController`, `SourcePickerViewModel`) paired with focus-isolated tvOS `SwiftUI` views and modal sheets.
- **`Player/` & `Packages/AetherBridge/`**: Pins `AetherEngine 7.76.0` with 5 audio/Dolby Vision traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) and coordinates playback through `PlayerViewModel` and its 5 `@MainActor` controllers (`PlayerSessionController`, `PlayerTrackController`, `PlayerScrubController`, `PlayerRestoreController`, `PlayerQoSReporter`), `PlayerOSDCoordinator`, `PlayerAudioSessionCoordinator`, `SiriRemoteTouchSurface`, `ResolvingCurtainView`, `PlayerBottomBarView`, `PlayerQuickPanelView`, `SubtitleOverlayView`, `EmbeddedFontRegistry`, `SeriesFlowOverlays`, and `NerdHUDView`.

---

## 3. Test Architecture (`Tests/`)

| Suite Directory | Runner | Responsibility |
| :--- | :--- | :--- |
| **`Tests/LunaCoreTests/`** | `./scripts/test-core.sh` (`swift test --parallel` in `swift:6.2`) | Canonical domain suites for all platform-independent logic: HTTP transport & `/api/tv/v2` contracts, DTO decoding, episode/chapter parsers, `DiskSWRStore` & cache policies, `SideloadSafeStorage` & `ServerSessionCore`, Home/Catalog/Library/Detail/Search/Pairing ViewModels, and timeline/scrub/track/diagnostics/series/curtain policies (`LunaCoreTestSupport.swift` shared mock protocol & gates). |
| **`Tests/LunaTests/`** | `xcodebuild test -scheme Luna` (tvOS Simulator in `.github/workflows/build-tvos.yml`) | Canonical domain suites for tvOS-only behavior: `BonjourServerBrowser` (`NWBrowser`), `ArtworkPipeline` & `BlurHashImageCache` (`CoreGraphics`/`ImageIO`), Lampelys theme/tokens/views/hosting-window layout, detail/source-picker UI flows, offline preview rendering, and `PlayerViewModel` / `AetherEngine` lifecycle, restore, QMS/audio-session, scrub, quick-panel, source-switch, reload serialization, QoS, embedded fonts, and subtitle/series overlays (`PlayerTestDoubles.swift` shared transport & URL mocks). |

---

## 4. Guardrails, Sandbox & CI Workflows

- **`ops/bin/luna-check`**: Fast (`< 0.3s` local, `--remote` in CI) static gate enforcing `0755`/`0644` permissions, `<= 800 LOC`, sideload safety, `>= 22 pt` typography floor, iOS-API & cold-Material blocks, public-repo hygiene, `Localizable.xcstrings` & `VERSION` parity, test naming hygiene, and `ops/bin/luna-design-tokens --check`.
- **`preview/`**: Local `1920×1080` HTML/CSS/JS Lampelys focus & overscan sandbox (`preview/index.html`, generated `preview/tokens.css`).
- **`.github/workflows/tvos-vision.yml`**: Parallel `luna-check --remote` + `linux-core-tests`, followed by `xcodebuild build` (no XCTest overhead) and rapid Simulator screenshot capture (`6` core screens by default, configurable via `inputs.screens` or `[vision-all]`).
- **`.github/workflows/build-tvos.yml`**: Parallel `luna-check --remote` + `linux-core-tests`, diff-gated `test-tvos` on tvOS Simulator, `arm64` Release `Luna-unsigned.ipa` packaging, and rolling `latest` GitHub Release upload for ATVLoadly.
