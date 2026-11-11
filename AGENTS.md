# AGENTS.md — Luna (tvOS)

## 1. Purpose & Public-Repository Security Rules

`Luna` is a public, standalone tvOS client powered by `AetherEngine` (`7.62.1`) and backed by the MediaOS TV BFF (`/api/tv/v1`).

Because this repository is **public on GitHub**, these rules are hard invariants:

- **Zero private infrastructure details**: Never commit private IP addresses (`10.x`, `172.16-31.x`, `192.168.x`), internal hostnames/domains, API keys, Bearer tokens, or local filesystem paths.
- All server discovery happens at runtime on the Apple TV via Bonjour/mDNS (`_mediaos._tcp`) or manual URL input, authenticated via a 6-digit Device Flow pairing code approved in MediaOS Web.

## 2. Sideload Compatibility (ATVLoadly / Free Apple ID Signing)

`Luna-unsigned.ipa` is signed and sideloaded onto Apple TV devices by **ATVLoadly**, which **rewrites `CFBundleIdentifier`** on every free Apple ID signing profile.

- **NEVER** read, assert on, or key storage by `Bundle.main.bundleIdentifier`.
- Always use the fixed storage namespace in `Sources/Core/Config/SideloadSafeStorage.swift` (`luna.v1.*` keys in `UserDefaults.standard` and static Keychain `kSecAttrService = "luna.v1.credentials"` without bundle-tied access groups).

## 3. PC / Linux Development Without a Mac

Development happens on Linux/Windows without a local macOS SDK:

1. **Ignore local SDK diagnostics**: Any local LSP/compiler errors complaining about missing `SwiftUI`, `UIKit`, `AVFoundation`, `Network`, `tvOS` SDKs, or `AetherEngine` binaries on Linux/Windows are expected and **must be ignored**.
2. **`project.yml` is the single source of truth**: Never hand-edit or commit `Luna.xcodeproj` or `*.xcworkspace`. XcodeGen generates `Luna.xcodeproj` fresh inside GitHub Actions on every build.
3. **SPM Traits via `Packages/AetherBridge`**: XcodeGen does not serialize SwiftPM `traits:` on remote packages, and `xcodebuild` has no CLI flag for package traits. All `AetherEngine` version pinning (`exact: "7.62.1"`) and optional traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) MUST stay in `Packages/AetherBridge/Package.swift`.

## 4. Cloud Build & Verification Workflow (`gh` CLI)

Every code change is verified in GitHub Actions (`.github/workflows/build-tvos.yml`), which compiles `Luna` for `generic/platform=tvOS` using Xcode 26.3+ / 27 and uploads `Luna-unsigned.ipa` to the rolling `latest` GitHub Release monitored by ATVLoadly.

```bash
# Push changes and watch the cloud build
git push origin main
gh run list --workflow=build-tvos.yml --limit 5
gh run watch

# Inspect compiler errors if a build fails
gh run view --log-failed

# Verify the published unsigned IPA asset on the rolling 'latest' release
gh release view latest --json assets,updatedAt
```

## 5. tvOS 26 & AetherEngine Host Rules

- Reuse a **single** `@MainActor` `AetherEngine` instance across the app lifetime (`LunaApp.swift`). Call `engine.prepareForItemReplacement()` for back-to-back episode transitions and `engine.stop()` when dismissing the player.
- Observe `engine.clock` (`$currentTime`, `$sourceTime`) **only** in leaf scrubber and subtitle overlay views so 10 Hz clock ticks never trigger re-renders across the player hierarchy.
- **Never** use SwiftUI `Menu` inside tvOS 26 player overlays (causes focus flicker on `objectWillChange`). Always present focusable modal sheets (`PlayerSheets.swift`).
- Explicitly manage `UIApplication.shared.isIdleTimerDisabled` while playing/loading/rebuffering so tvOS never starts the screensaver on the software decode route (`.softwareHost` Dolby Vision Profile 7 FEL / AV1).
