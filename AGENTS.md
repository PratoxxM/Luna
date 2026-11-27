# AGENTS.md — Luna (tvOS)

## 1. Purpose & Public-Repository Security Rules

`Luna` (`v3.0.0`, pure `tvOS 26.0` / Swift `6.2`) is a public, standalone tvOS client powered by `AetherEngine` (`7.76.0`) and backed by the native LunaCore TV API (`/api/tv/v2` on `:8090` / `:8920`).

Because this repository is **public on GitHub**, these rules are hard invariants:

- **Zero private infrastructure details**: Never commit private IP addresses (`10.x`, `100.64-127.x`, `172.16-31.x`, `192.168.x`), internal hostnames/domains, API keys, Bearer tokens, Apple IDs, UDIDs, or local NAS filesystem paths.
- All server discovery happens at runtime on the Apple TV via Bonjour/mDNS (`_lunacore._tcp`) or manual URL input, authenticated via a 6-digit Device Flow pairing code approved in LunaCore Web.
- Signed stream tokens must be registered with `EngineLog.registerSecret(...)` before loading a stream and unregistered on stop so playback logs never leak URL credentials.

## 2. Sideload Compatibility (ATVLoadly / Free Apple ID Signing)

`Luna-unsigned.ipa` is signed and sideloaded onto Apple TV devices by **ATVLoadly** (`local.lunacore.luna` bundle prefix in `project.yml`), which **rewrites `CFBundleIdentifier`** on every free Apple ID signing profile.

- **NEVER** read, assert on, or key storage by `Bundle.main.bundleIdentifier`.
- Always use the fixed storage namespace in `Sources/Core/Config/SideloadSafeStorage.swift` (`luna.v1.*` keys in `UserDefaults.standard` and static Keychain `kSecAttrService = "luna.v1.credentials"` without bundle-tied access groups). Preserve these exact `"luna.v1.*"` key strings across major/minor releases so already-paired Apple TV devices never lose their pairing tokens or comfort settings during OTA updates.

## 3. Code Organization & Naming Rules

- **Domain naming only**: Use `LunaCoreClient` / `LunaCoreError` / `LunaCoreSessionPool` for `/api/tv/v2` networking (`Sources/Core/Networking/`) and `DiscoveredLunaCoreServer` in `Sources/Core/Discovery/BonjourServiceParser.swift`. Never reintroduce retired legacy client names, `BFF*` typealiases, `*FixesTests`, or `*ForTesting` closures.
- **File size & permission budget**: Keep every `.swift` source/test file and `.md` document strictly `<= 800 LOC` (`0644` permissions; `0755` for directories, `ops/bin/*`, and `scripts/*.sh`), enforced locally in `< 0.3s` by `./ops/bin/luna-check` (and with `--remote` tag verification in CI).
- **Shared networking & caching**: Reuse pooled `URLSession` lanes via `LunaCoreSessionPool`, decode images off the main actor via `ArtworkPipeline`, and persist `/api/tv/v2` ETag/JSON snapshots in `DiskSWRStore` (`.cachesDirectory`).

## 4. Test Hygiene & Anti-Bloat Rules

To keep local Linux loops under a few seconds and tvOS Simulator builds lean, enforce these rules strictly:

1. **Max 1 canonical test file per domain/feature (`<= 800 LOC`)**: Add new assertions into the existing domain test file and delete obsolete assertions when behavior changes. **Never** create milestone, round, or bugfix-named files (`Etappe*`, `M1*..M9*`, `Round*`, `*FixesTests`, `*RegressionTests` — blocked by `ops/bin/luna-check`).
2. **Sharp boundary between `Tests/LunaCoreTests/` and `Tests/LunaTests/` (zero duplication)**:
   - `Tests/LunaCoreTests/` (`Package.swift` -> `./scripts/test-core.sh` on Linux Swift 6.2) owns **all** platform-independent logic (`LunaCoreClient`, `LunaCoreHTTPTransport`, `LunaCoreSessionPool`, `PlaybackResolveSocket`, `/api/tv/v2` models, `DiskSWRStore`, `SideloadSafeStorage`, `SmartTrackRuleEngine`, `EpisodeTitleFormatter`, `ChapterModels`, pure ViewModels, and timeline/scrub/track/series policies), sharing `LunaCoreTestSupport.swift`.
   - `Tests/LunaTests/` (`project.yml` -> tvOS Simulator XCTest) is reserved **strictly** for tvOS-specific UI (`SwiftUI`/`UIKit`), `NWBrowser` `BonjourServerBrowser`, `CoreGraphics`/`ImageIO` `ArtworkPipeline`/`BlurHashImageCache`, `PreviewRenderingAndLaunchTests`, and `PlayerViewModel`/`PlayerSessionController` integration against `AetherEngine`, sharing `PlayerTestDoubles.swift`. Never duplicate Linux-testable `LunaCore` tests inside `Tests/LunaTests/`.
3. **Test runtime behavior, not source text**: Assert outputs, state transitions, and wire payloads rather than grepping `.swift` files with regexes or asserting that long-retired files remain absent.

## 5. Where to Look First

- **Domain architecture & target map**: [`docs/architecture/CODEBASE_MODULE_MAP.md`](docs/architecture/CODEBASE_MODULE_MAP.md)
- **Canonical Lampelys 10-foot tvOS UI/UX specification**: [`docs/LUNA_TVOS_LAMPELYS_REVIEW.md`](docs/LUNA_TVOS_LAMPELYS_REVIEW.md)
- **Canonical `AetherEngine` (`7.76.0`) API signatures (never guess signatures)**: [`docs/aether-engine-api.md`](docs/aether-engine-api.md)
- **App lifecycle, `--preview-screen` launch mode & single `@MainActor` engine**: `Sources/App/LunaApp.swift`, `Sources/App/PreviewLaunchConfiguration.swift`, `Sources/App/PreviewMockFixtures.swift`, `Sources/App/MainNavigationShell.swift`, `Sources/App/LunaTopBarView.swift`
- **Discovery, pairing & config**: `Sources/Core/Discovery/BonjourServerBrowser.swift`, `Sources/Core/Config/ServerConfiguration.swift`, `Sources/Core/Config/ServerSessionCore.swift`, `Sources/Core/Config/SideloadSafeStorage.swift`
- **Linux-testable core (`Package.swift` -> `LunaCore`)**: `Sources/Core/Networking/*`, `Sources/Core/Models/*`, `Sources/Core/Catalog/CatalogShelfIndexer.swift`, `Sources/Core/Playback/*`, `Sources/Core/Cache/{DiskSWRStore,ArtworkDiskCache,BlurHashDecoder,InflightTaskCoalescer}.swift`, `Tests/LunaCoreTests/*`
- **Player shell & AetherEngine bridge**: `Packages/AetherBridge/Package.swift`, `Sources/Features/Player/PlayerViewModel.swift`, `Sources/Features/Player/PlayerSessionController.swift`, `Sources/Features/Player/PlayerContainerView.swift`
- **Local 1920×1080 Lampelys Focus Sandbox**: `preview/index.html`, `preview/tokens.css`, `design/tokens.json`

## 6. PC / Linux Development Without a Mac

Development happens on Linux/Docker without a local macOS SDK:

1. **Ignore local SDK diagnostics**: Any local LSP/compiler errors complaining about missing `SwiftUI`, `UIKit`, `AVFoundation`, `Network`, `tvOS` SDKs, or `AetherEngine` binaries on Linux are expected and **must be ignored**.
2. **Keep pure business logic Linux-native (`LunaCore`)**: Non-UI networking, models, shelf indexing, SWR caching, pure ViewModels, and playback/scrub/track policies live in `Package.swift` -> `LunaCore` (`#if canImport(FoundationNetworking)` where needed) with zero `UIKit`, `SwiftUI`, `TVUIKit`, or `AVFoundation` imports so `./scripts/test-core.sh` compiles and tests them locally in Docker (`swift:6.2`).
3. **Run `./ops/bin/luna-check` locally**: Completes in `< 0.3s` without network calls (`--remote` runs in CI) and validates `0644`/`0755` permissions, `<= 800 LOC`, `>= 22 pt` tvOS typography floor, sideload safety, public-repo hygiene, `VERSION` parity, and `luna-design-tokens --check`.
4. **`project.yml` is the single source of truth for tvOS**: Never hand-edit or commit `Luna.xcodeproj` or `*.xcworkspace`. XcodeGen generates `Luna.xcodeproj` fresh inside GitHub Actions on every build.
5. **SPM Traits via `Packages/AetherBridge`**: All `AetherEngine` version pinning (`exact: "7.76.0"`) and optional traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) MUST stay in `Packages/AetherBridge/Package.swift`.

## 7. Strict tvOS Guardrails & `AetherEngine` Host Rules

### tvOS UI & Siri Remote Guardrails
- **Strictly forbidden iOS-only APIs**: Never use `.navigationBarTitleDisplayMode`, bare `.onTapGesture` without focusable `Button` wrappers, `Slider`, iOS-only `Picker` `.wheel` / `.menu` styles, cold system `Material` blurs, or `UIScreen.main` (`>= 22 pt` `LunaTheme.Font.*` typography only — raw `.font(.caption/.body/...)` is blocked by `luna-check`).
- **Explicit Focus & Remote Handling**: Manage tvOS focus explicitly with `@FocusState`, `.focusSection()`, `.prefersDefaultFocus(..., in:)`, `LunaChromelessButtonStyle` / `LunaFocusStyle`, and Siri Remote command handlers (`.onExitCommand`, `.onPlayPauseCommand`, `.onMoveCommand`, `SiriRemoteTouchSurface`). Respect tvOS overscan/action-safe margins (`90 pt` horizontal gutter, `60 pt` vertical safe margin).

### tvOS 26 & `AetherEngine` (`7.76.0`) Rules
- Reuse a **single** `@MainActor` `AetherEngine` instance across the app lifetime (`LunaApp.swift`), setting `engine.maximumSubtitleAdvanceSeconds = 0` and `engine.maximumSubtitleDelaySeconds = 10` at initialization and before `engine.load(...)` so active subtitles never open a second parallel 4K HTTP stream.
- Call `engine.prepareForItemReplacement()` for back-to-back episode transitions and seamless timecode source switches (`HeldStillPresenter`), and `engine.stop(resetDisplayCriteria: true)` when dismissing the player.
- Hold `ResolvingCurtainView` visible until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch` (with a 5-second fallback watchdog via `PlaybackCurtainWatchdog`) so HDMI range/frame-rate switches never flash black.
- Observe `engine.clock` (`$currentTime`, `$sourceTime`) **only** in leaf scrubber (`PlayerBottomBarView`) and subtitle (`SubtitleOverlayView`) views, and `engine.diagnostics.$liveTelemetry` **only** in `NerdHUDView` (1 Hz), so high-frequency ticks never re-render the player hierarchy.
- **Never** use SwiftUI `Menu` inside tvOS 26 player overlays or a halo-enabled full-screen SwiftUI `Button` above `AetherPlayerSurface`. Always use `SiriRemoteTouchSurface` (`UIView` + `.focusEffectDisabled()`), `PlayerBottomBarView`, `PlayerQuickPanelView`, or focusable modal sheets (`SourcePickerSheetView`).
- Explicitly manage `UIApplication.shared.isIdleTimerDisabled` while playing/loading/rebuffering/resolving so tvOS never starts the screensaver on `.softwareHost` (Dolby Vision Profile 7 FEL / AV1).

## 8. Mandatory Autonomous Self-Verification Loop

1. **Local Guardrails & Linux `LunaCore` Unit Tests (after every Swift logic change)**:
   ```bash
   ./ops/bin/luna-check
   ./scripts/test-core.sh
   ```
2. **Local 1920×1080 Focus Sandbox (for UI, layout, token & focus iterations)**:
   Render `preview/index.html` in a headless browser / Playwright at `1920x1080`, toggle overscan safe-zones (`G` or `?guides=1`), test keyboard/remote focus transitions, and inspect screenshots before pushing to CI.
3. **Cloud tvOS Simulator Vision & Release Build (`gh` CLI)**:
   - **Visual Simulator verification (`.github/workflows/tvos-vision.yml`)**: Runs `luna-check --remote` and `linux-core-tests` in parallel, builds `Luna.app` via `xcodebuild build` (without running XCTest), and captures the fast **6-screen default** (`home,catalog,library,details,player-osd,settings`) in ~15–20s. Pass `inputs.screens` (e.g. `detail-source-picker,player-subtitles` or `all`) via `workflow_dispatch` or include `[vision-all]` in the commit message on an `agent/*` push when full 32-screen coverage is needed:
     ```bash
     git push origin HEAD:agent/<feature-name>
     gh run watch
     rm -rf .ci-screenshots && gh run download -n tvos-screenshots -D .ci-screenshots
     ```
   - **Production `main` build & rolling unsigned IPA (`.github/workflows/build-tvos.yml`)**: Runs `luna-check --remote` and `linux-core-tests` in parallel, conditionally runs `test-tvos` on tvOS Simulator when tvOS UI/host files changed (always on PRs), compiles `Luna` for `generic/platform=tvOS`, and publishes `Luna-unsigned.ipa` to the rolling `latest` GitHub Release for ATVLoadly:
     ```bash
     ./ops/bin/luna-check
     git push origin main
     gh run watch
     gh release view latest --json assets,publishedAt
     ```
