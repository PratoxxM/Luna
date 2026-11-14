# AGENTS.md — Luna (tvOS)

## 1. Purpose & Public-Repository Security Rules

`Luna` (`v2.3.0`) is a public, standalone tvOS client powered by `AetherEngine` (`7.65.0`) and backed by the native LunaCore TV API (`/api/tv/v1` on `:8090` / `:8920`).

Because this repository is **public on GitHub**, these rules are hard invariants:

- **Zero private infrastructure details**: Never commit private IP addresses (`10.x`, `172.16-31.x`, `192.168.x`), internal hostnames/domains, API keys, Bearer tokens, Apple IDs, UDIDs, or local NAS filesystem paths.
- All server discovery happens at runtime on the Apple TV via Bonjour/mDNS (`_lunacore._tcp`) or manual URL input, authenticated via a 6-digit Device Flow pairing code approved in LunaCore Web.
- Signed stream tokens must be registered with `EngineLog.registerSecret(...)` before loading a stream and unregistered on stop so playback logs never leak URL credentials.

## 2. Sideload Compatibility (ATVLoadly / Free Apple ID Signing)

`Luna-unsigned.ipa` is signed and sideloaded onto Apple TV devices by **ATVLoadly** (`local.lunacore.luna` bundle prefix in `project.yml`), which **rewrites `CFBundleIdentifier`** on every free Apple ID signing profile.

- **NEVER** read, assert on, or key storage by `Bundle.main.bundleIdentifier`.
- Always use the fixed storage namespace in `Sources/Core/Config/SideloadSafeStorage.swift` (`luna.v1.*` keys in `UserDefaults.standard` and static Keychain `kSecAttrService = "luna.v1.credentials"` without bundle-tied access groups). Preserve these exact `"luna.v1.*"` key strings across major/minor releases so already-paired Apple TV devices never lose their pairing tokens or comfort settings during OTA updates.

## 3. Code Organization & Naming Rules

- **Domain naming only**: Use `LunaCoreClient` / `LunaCoreError` / `LunaCoreSessionPool` for `/api/tv/v1` networking (`Sources/Core/Networking/LunaCoreClient.swift`, `Sources/Core/Networking/LunaCoreSessionPool.swift`) and `DiscoveredLunaCoreServer` in `Sources/Core/Discovery/BonjourServerBrowser.swift`. Never reintroduce retired legacy client names, `BFF*` typealiases, `Hero` banners, or retired `Watchlist/` / `PlayerSheets.swift` views.
- **File size budget**: Keep every `.swift` source file in `Sources/` strictly `<= 800 LOC` with clear single responsibility.
- **Shared networking & caching**: Reuse a single `URLSession` per `LunaCoreClient`, decode images off the main actor via `ArtworkPipeline`, and persist `/api/tv/v1/home` ETag/JSON snapshots in `DiskSWRStore` (`.cachesDirectory`).

## 4. Where to Look First

- **Full module-to-endpoint-to-test index**: [`docs/architecture/CODEBASE_MODULE_MAP.md`](docs/architecture/CODEBASE_MODULE_MAP.md)
- **App lifecycle & single `@MainActor` engine**: `Sources/App/LunaApp.swift`, `Sources/App/MainNavigationShell.swift`
- **Discovery, pairing & config**: `Sources/Core/Discovery/BonjourServerBrowser.swift`, `Sources/Core/Config/ServerConfiguration.swift`, `Sources/Core/Config/SideloadSafeStorage.swift`, `Sources/Features/Onboarding/PairingOnboardingView.swift`
- **API client, WebSocket & SWR/image caching**: `Sources/Core/Networking/LunaCoreClient.swift`, `Sources/Core/Networking/LunaCoreSessionPool.swift`, `Sources/Core/Networking/PlaybackResolveSocket.swift`, `Sources/Core/Cache/DiskSWRStore.swift`, `Sources/Core/Cache/ArtworkPipeline.swift`
- **Player shell & AetherEngine bridge**: `Packages/AetherBridge/Package.swift`, `Sources/Features/Player/PlayerViewModel.swift`, `Sources/Features/Player/PlayerSessionCoordinator.swift`, `Sources/Features/Player/PlayerContainerView.swift`

## 4. PC / Linux Development Without a Mac

Development happens on Linux/Windows without a local macOS SDK:

1. **Ignore local SDK diagnostics**: Any local LSP/compiler errors complaining about missing `SwiftUI`, `UIKit`, `AVFoundation`, `Network`, `tvOS` SDKs, or `AetherEngine` binaries on Linux/Windows are expected and **must be ignored**.
2. **`project.yml` is the single source of truth**: Never hand-edit or commit `Luna.xcodeproj` or `*.xcworkspace`. XcodeGen generates `Luna.xcodeproj` fresh inside GitHub Actions on every build.
3. **SPM Traits via `Packages/AetherBridge`**: XcodeGen does not serialize SwiftPM `traits:` on remote packages, and `xcodebuild` has no CLI flag for package traits. All `AetherEngine` version pinning (`exact: "7.65.0"`) and optional traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) MUST stay in `Packages/AetherBridge/Package.swift`.

## 5. Cloud Build & Verification Workflow (`gh` CLI)

Every code change is verified in GitHub Actions (`.github/workflows/build-tvos.yml`), which runs static guardrails, compiles and tests `Tests/LunaTests` (`LunaTests`), compiles `Luna` for `generic/platform=tvOS` using Xcode 26.3+ / 27, and uploads `Luna-unsigned.ipa` to the rolling `latest` GitHub Release monitored by ATVLoadly.

```bash
# Push changes and watch the cloud build
git push origin main
gh run list --workflow=build-tvos.yml --limit 5
gh run watch

# Inspect compiler errors if a build fails
gh run view --log-failed
# If gh blocks ANSI escape sequences in large xcodebuild logs:
gh api --allow-escape-sequences repos/PratoxxM/Luna/actions/jobs/<job-id>/logs | grep -C 4 "error:"

# Verify the published unsigned IPA asset on the rolling 'latest' release
gh release view latest --json assets,updatedAt
```

## 6. tvOS 26 & AetherEngine Host Rules

- Reuse a **single** `@MainActor` `AetherEngine` instance across the app lifetime (`LunaApp.swift`), setting `engine.maximumSubtitleAdvanceSeconds = 0` and `engine.maximumSubtitleDelaySeconds = 10` at initialization and before `engine.load(...)` so active subtitles never open a second parallel 4K HTTP stream.
- Call `engine.prepareForItemReplacement()` for back-to-back episode transitions and seamless timecode source switches (`HeldStillPresenter`), and `engine.stop(resetDisplayCriteria: true)` when dismissing the player.
- Hold `ResolvingCurtainView` visible until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch` (with a 5-second fallback watchdog) so HDMI range/frame-rate switches never flash black.
- Observe `engine.clock` (`$currentTime`, `$sourceTime`) **only** in leaf scrubber (`PlayerBottomBarView`) and subtitle (`SubtitleOverlayView`) views, and `engine.diagnostics.$liveTelemetry` **only** in `NerdHUDView` (1 Hz), so high-frequency ticks never re-render the player hierarchy.
- **Never** use SwiftUI `Menu` inside tvOS 26 player overlays (causes focus flicker on `objectWillChange`) or an unfocused/halo-enabled full-screen SwiftUI `Button` above `AetherPlayerSurface` (causes tvOS Liquid Glass focus rectangle washout). Always use `SiriRemoteTouchSurface` (`UIView` + `.focusEffectDisabled()`), the focus-isolated 3-tab `PlayerTopDrawerView`, or focusable modal sheets (`SourcePickerSheetView`).
- Explicitly manage `UIApplication.shared.isIdleTimerDisabled` while playing/loading/rebuffering/resolving so tvOS never starts the screensaver on `.softwareHost` (Dolby Vision Profile 7 FEL / AV1).
