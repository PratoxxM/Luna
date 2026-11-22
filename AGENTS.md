# AGENTS.md — Luna (tvOS)

## 1. Purpose & Public-Repository Security Rules

`Luna` (`v2.9.0`) is a public, standalone tvOS client powered by `AetherEngine` (`7.72.1`) and backed by the native LunaCore TV API (`/api/tv/v1` on `:8090` / `:8920`).

Because this repository is **public on GitHub**, these rules are hard invariants:

- **Zero private infrastructure details**: Never commit private IP addresses (`10.x`, `172.16-31.x`, `192.168.x`), internal hostnames/domains, API keys, Bearer tokens, Apple IDs, UDIDs, or local NAS filesystem paths.
- All server discovery happens at runtime on the Apple TV via Bonjour/mDNS (`_lunacore._tcp`) or manual URL input, authenticated via a 6-digit Device Flow pairing code approved in LunaCore Web.
- Signed stream tokens must be registered with `EngineLog.registerSecret(...)` before loading a stream and unregistered on stop so playback logs never leak URL credentials.

## 2. Sideload Compatibility (ATVLoadly / Free Apple ID Signing)

`Luna-unsigned.ipa` is signed and sideloaded onto Apple TV devices by **ATVLoadly** (`local.lunacore.luna` bundle prefix in `project.yml`), which **rewrites `CFBundleIdentifier`** on every free Apple ID signing profile.

- **NEVER** read, assert on, or key storage by `Bundle.main.bundleIdentifier`.
- Always use the fixed storage namespace in `Sources/Core/Config/SideloadSafeStorage.swift` (`luna.v1.*` keys in `UserDefaults.standard` and static Keychain `kSecAttrService = "luna.v1.credentials"` without bundle-tied access groups). Preserve these exact `"luna.v1.*"` key strings across major/minor releases so already-paired Apple TV devices never lose their pairing tokens or comfort settings during OTA updates.

## 3. Code Organization & Naming Rules

- **Domain naming only**: Use `LunaCoreClient` / `LunaCoreError` / `LunaCoreSessionPool` for `/api/tv/v1` networking (`Sources/Core/Networking/LunaCoreHTTPTransport.swift`, `Sources/Core/Networking/LunaCoreClient+HomeCatalog.swift`, `Sources/Core/Networking/LunaCoreClient+LibraryDetail.swift`, `Sources/Core/Networking/LunaCoreClient+Playback.swift`, `Sources/Core/Networking/LunaCoreSessionPool.swift`) and `DiscoveredLunaCoreServer` in `Sources/Core/Discovery/BonjourServerBrowser.swift`. Never reintroduce retired legacy client names, `BFF*` typealiases, `Hero` banners, or retired `Watchlist/` / `PlayerSheets.swift` views.
- **File size & permission budget**: Keep every `.swift` source/test file and doc strictly `<= 800 LOC` (`0644` permissions; `0755` for `ops/bin/*` and `scripts/*.sh`), enforced by `./ops/bin/luna-check`.
- **Shared networking & caching**: Reuse a single `URLSession` per `LunaCoreClient`, decode images off the main actor via `ArtworkPipeline`, and persist `/api/tv/v1/home` ETag/JSON snapshots in `DiskSWRStore` (`.cachesDirectory`).

## 4. Where to Look First

- **Full module-to-endpoint-to-test index (enforced 1:1 by `ops/bin/luna-check`)**: [`docs/architecture/CODEBASE_MODULE_MAP.md`](docs/architecture/CODEBASE_MODULE_MAP.md)
- **Canonical Lampelys 10-foot tvOS UI/UX specification**: [`docs/LUNA_TVOS_LAMPELYS_REVIEW.md`](docs/LUNA_TVOS_LAMPELYS_REVIEW.md)
- **Canonical `AetherEngine` (`7.72.1`) API signatures (never guess signatures)**: [`docs/aether-engine-api.md`](docs/aether-engine-api.md)
- **App lifecycle, `--preview-screen` launch mode & single `@MainActor` engine**: `Sources/App/LunaApp.swift`, `Sources/App/PreviewLaunchConfiguration.swift`, `Sources/App/PreviewMockFixtures.swift`, `Sources/App/MainNavigationShell.swift`, `Sources/App/LunaTopBarView.swift`
- **Discovery, pairing & config**: `Sources/Core/Discovery/BonjourServerBrowser.swift`, `Sources/Core/Config/ServerConfiguration.swift`, `Sources/Core/Config/SideloadSafeStorage.swift`, `Sources/Features/Onboarding/PairingOnboardingView.swift`
- **Linux-testable core (`Package.swift` -> `LunaCore`)**: `Sources/Core/Networking/*`, `Sources/Core/Models/*`, `Sources/Core/Catalog/CatalogShelfIndexer.swift`, `Sources/Core/Playback/PlaybackCoreAbstractions.swift`, `Sources/Core/Cache/DiskSWRStore.swift`, `Tests/LunaCoreTests/LunaCoreLinuxTests.swift`
- **Player shell & AetherEngine bridge**: `Packages/AetherBridge/Package.swift`, `Packages/AetherBridge/Sources/AetherBridge/Exports.swift`, `Sources/Features/Player/PlayerViewModel.swift`, `Sources/Features/Player/PlayerSessionCoordinator.swift`, `Sources/Features/Player/PlayerContainerView.swift`
- **Local 1920×1080 Lampelys Focus Sandbox**: `preview/index.html`, `preview/tokens.json`, `design/tokens.json`

## 5. PC / Linux Development Without a Mac

Development happens on Linux/Docker without a local macOS SDK:

1. **Ignore local SDK diagnostics**: Any local LSP/compiler errors complaining about missing `SwiftUI`, `UIKit`, `AVFoundation`, `Network`, `tvOS` SDKs, or `AetherEngine` binaries on Linux are expected and **must be ignored**.
2. **Keep pure business logic Linux-native (`LunaCore`)**: Non-UI networking, models, shelf indexing, SWR caching, and `PlaybackEngine`/`IOReader` state machines & watchdogs live in pure Swift (`Package.swift` -> `LunaCore`) with zero `UIKit`, `SwiftUI`, or `TVUIKit` imports so `./scripts/test-core.sh` compiles and tests them locally in Docker (`swift:6.0`).
3. **Run `./ops/bin/luna-check` locally**: Validates `0644`/`0755` permissions, `<= 800 LOC`, `>= 22 pt` tvOS typography floor, sideload safety, zero private infra/retired patterns, design token parity, and bidirectional doc-to-disk parity (`CODEBASE_MODULE_MAP.md` <-> `Sources/**/*.swift`, `Tests/LunaTests/*.swift` & `Tests/LunaCoreTests/*.swift`).
4. **`project.yml` is the single source of truth for tvOS**: Never hand-edit or commit `Luna.xcodeproj` or `*.xcworkspace`. XcodeGen generates `Luna.xcodeproj` fresh inside GitHub Actions on every build.
5. **SPM Traits via `Packages/AetherBridge`**: XcodeGen does not serialize SwiftPM `traits:` on remote packages, and `xcodebuild` has no CLI flag for package traits. All `AetherEngine` version pinning (`exact: "7.72.1"`) and optional traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) MUST stay in `Packages/AetherBridge/Package.swift`.

## 6. Strict tvOS Guardrails & `AetherEngine` Host Rules

### tvOS UI & Siri Remote Guardrails
- **Strictly forbidden iOS-only APIs**: Never use `.navigationBarTitleDisplayMode`, bare `.onTapGesture` without focusable `Button` wrappers, `Slider`, iOS-only `Picker` `.wheel` / `.menu` styles, or `UIScreen.main` (`>= 22 pt` `LunaTheme.Font.*` typography only — raw `.font(.caption/.body/...)` is blocked by `luna-check`).
- **Explicit Focus & Remote Handling**: Always manage tvOS focus explicitly with `@FocusState`, `.focusSection()`, `.prefersDefaultFocus(..., in:)`, `LunaChromelessButtonStyle` / `LunaFocusStyle`, and Siri Remote command handlers (`.onExitCommand`, `.onPlayPauseCommand`, `.onMoveCommand`, `SiriRemoteTouchSurface`). Respect tvOS overscan/action-safe margins (`90 pt` horizontal gutter, `60 pt` vertical safe margin).

### tvOS 26 & `AetherEngine` (`7.72.1`) Rules
- Reuse a **single** `@MainActor` `AetherEngine` instance across the app lifetime (`LunaApp.swift`), setting `engine.maximumSubtitleAdvanceSeconds = 0` and `engine.maximumSubtitleDelaySeconds = 10` at initialization and before `engine.load(...)` so active subtitles never open a second parallel 4K HTTP stream.
- Call `engine.prepareForItemReplacement()` for back-to-back episode transitions and seamless timecode source switches (`HeldStillPresenter`), and `engine.stop(resetDisplayCriteria: true)` when dismissing the player.
- Hold `ResolvingCurtainView` visible until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch` (with a 5-second fallback watchdog via `PlaybackCurtainWatchdog`) so HDMI range/frame-rate switches never flash black.
- Observe `engine.clock` (`$currentTime`, `$sourceTime`) **only** in leaf scrubber (`PlayerBottomBarView`) and subtitle (`SubtitleOverlayView`) views, and `engine.diagnostics.$liveTelemetry` **only** in `NerdHUDView` (1 Hz), so high-frequency ticks never re-render the player hierarchy.
- **Never** use SwiftUI `Menu` inside tvOS 26 player overlays (causes focus flicker on `objectWillChange`) or an unfocused/halo-enabled full-screen SwiftUI `Button` above `AetherPlayerSurface` (causes tvOS Liquid Glass focus rectangle washout). Always use `SiriRemoteTouchSurface` (`UIView` + `.focusEffectDisabled()`), the focus-isolated bottom OSD quick-action strip & vertical quick-lists (`PlayerBottomBarView`, `PlayerQuickPanelView`), or focusable modal sheets (`SourcePickerSheetView`).
- Explicitly manage `UIApplication.shared.isIdleTimerDisabled` while playing/loading/rebuffering/resolving so tvOS never starts the screensaver on `.softwareHost` (Dolby Vision Profile 7 FEL / AV1).

## 7. Mandatory Autonomous Self-Verification Loop

Follow this 3-stage verification loop before reporting any change complete:

1. **Local Guardrails & Linux `LunaCore` Unit Tests (after every Swift logic change)**:
   ```bash
   ./ops/bin/luna-check
   ./scripts/test-core.sh
   ```
2. **Local 1920×1080 Focus Sandbox (for UI, layout, token & focus iterations)**:
   Render `preview/index.html` in a headless browser / Playwright at `1920x1080`, toggle overscan safe-zones (`90px` X / `60px` Y via `G` or `?guides=1`), test `ArrowUp` / `ArrowDown` / `ArrowLeft` / `ArrowRight` / `Enter` focus transitions across `home`, `catalog`, `details`, and `player`, and visually inspect screenshots before pushing to CI.
3. **Cloud tvOS Simulator Vision & Release Build (`gh` CLI)**:
   - **Visual Simulator verification (`.github/workflows/tvos-vision.yml`)**: Push to an `agent/*` branch (or trigger `workflow_dispatch`), watch the run, inspect any failure logs, download the `1920x1080` Simulator renders (`home.png`, `catalog.png`, `details.png`, `player.png`), and visually inspect every PNG before merging/reporting completion:
     ```bash
     git push origin HEAD:agent/<feature-name>
     gh run list --workflow=tvos-vision.yml --limit 5
     gh run watch
     # If anything fails:
     gh run view --log-failed
     # Download & inspect real tvOS Simulator screenshots:
     rm -rf .ci-screenshots && gh run download -n tvos-screenshots -D .ci-screenshots
     ```
   - **Production `main` build & rolling unsigned IPA (`.github/workflows/build-tvos.yml`)**: Runs `luna-check`, all XCTest suites in `Tests/LunaTests` on tvOS Simulator, compiles `Luna` for `generic/platform=tvOS`, and publishes `Luna-unsigned.ipa` to the rolling `latest` GitHub Release for ATVLoadly:
     ```bash
     ./ops/bin/luna-check
     git push origin main
     gh run list --workflow=build-tvos.yml --limit 5
     gh run watch
     gh release view latest --json assets,publishedAt
     ```
