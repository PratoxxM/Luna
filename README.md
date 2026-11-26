<p align="center">
  <img src=".github/banner.png" alt="Luna for Apple TV" width="100%">
</p>

<h1 align="center">Luna</h1>

<p align="center">
  Native Apple TV home-cinema player built with SwiftUI and <a href="https://github.com/superuser404notfound/AetherEngine">AetherEngine</a> for <b>LunaCore</b>.
</p>

<p align="center">
  <a href="https://github.com/PratoxxM/Luna/actions/workflows/build-tvos.yml"><img src="https://github.com/PratoxxM/Luna/actions/workflows/build-tvos.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/PratoxxM/Luna/releases/latest"><img src="https://img.shields.io/badge/IPA-latest-d4a056" alt="Latest IPA"></a>
  <img src="https://img.shields.io/badge/tvOS-26%2B-1c1917?logo=appletv&logoColor=white" alt="tvOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-44403c" alt="MIT License"></a>
</p>

---

## Highlights

- **Reference Picture & Sound** — Dolby Vision (Profile 7 FEL, Profile 8 & Profile 5), HDR10+/HDR10, and spatial TrueHD Atmos & DTS:X audio powered by [AetherEngine](https://github.com/superuser404notfound/AetherEngine).
- **Made for the Living Room** — Warm OLED-safe cinema interface, instant cold-start shelves, Siri Remote touch scrubbing with live frame previews, and blink-free HDMI range/frame-rate switching.
- **Viewing Comfort** — HDR-dimmed subtitles (SRT, ASS, PGS, DVB), automatic Nordic/English track selection, intro & next-episode prompts, seamless source switching, and optional MetalFX upscaling.
- **Zero-Touch LAN Pairing** — Automatic server discovery via Bonjour (`_lunacore._tcp`) and quick 6-digit TV pairing.

## Install on Apple TV

1. Download **`Luna-unsigned.ipa`** from the [Latest Release](https://github.com/PratoxxM/Luna/releases/latest), or add `PratoxxM/Luna` in **ATVLoadly** for wireless installation and automatic 7-day signing renewal.
2. Open **Luna** on Apple TV — your **LunaCore** server is discovered automatically on the local network.
3. Approve the 6-digit code in LunaCore Web.

## Development

`Luna.xcodeproj` is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen), and `AetherEngine` (`7.73.0`) traits are configured in [`Packages/AetherBridge`](Packages/AetherBridge/Package.swift). See [`CODEBASE_MODULE_MAP.md`](docs/architecture/CODEBASE_MODULE_MAP.md) for the module and `/api/tv/v2` endpoint overview.

## License

[MIT](LICENSE)
