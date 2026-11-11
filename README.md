# Luna for tvOS

**Luna** is a native SwiftUI tvOS media player built on [AetherEngine](https://github.com/superuser404notfound/AetherEngine) (`7.62.1`) for the MediaOS `/api/tv/v1` Backend-for-Frontend (BFF).

## Highlights

- **Dual-Layer Dolby Vision & Spatial Object Audio**: Linked against `AetherEngine 7.62.1` via `Packages/AetherBridge` with `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`, `TrueHDObjectAudio`, and `DTSXObjectAudio` enabled.
- **Room & Hardware Profiles**:
  - `dv-fel-714` (*Kjellerstua*): Prioritizes 4K UHD BluRay Remuxes with Dolby Vision Profile 7 FEL / Profile 8 and renders TrueHD Atmos / DTS:X into a `7.1.4` spatial bed.
  - `hdr10-512` (*Stua*): Prioritizes 4K HDR10+ / HDR10 streams with `baseLayerOnly` DV handling and renders spatial audio into a `5.1.2` bed.
- **Zero-Touch LAN Setup**: Discovers MediaOS automatically via Bonjour (`_mediaos._tcp`) and pairs using a 6-digit TV code approved in MediaOS Web.
- **Pause-Safe Streaming**: 15-second playback & pause heartbeats maintain server-side VFS session locks, sync watch progress, pre-warm next episodes at 85%, and support instant source switching at the exact current timecode.
- **Sideload-Ready Cloud Builds**: GitHub Actions generates `Luna.xcodeproj` via XcodeGen, builds an unsigned Release `Luna-unsigned.ipa`, and publishes it to the rolling `latest` GitHub Release for automatic wireless installation and 7-day certificate renewal via ATVLoadly.

## Architecture

```text
Luna/
├── AGENTS.md
├── project.yml                        # XcodeGen specification (single source of truth)
├── Config/Info.plist                  # ATS LAN HTTP + Bonjour (_mediaos._tcp)
├── Packages/AetherBridge/             # Local SPM bridge enabling all 5 AetherEngine traits
├── Resources/Assets.xcassets/         # tvOS App Icon & Top Shelf brand assets
├── Sources/
│   ├── App/                           # App entry point, single AetherEngine host & TabView
│   ├── Core/
│   │   ├── Config/                    # Bundle-ID-agnostic UserDefaults & Keychain storage
│   │   ├── Discovery/                 # NWBrowser Bonjour (_mediaos._tcp) discovery
│   │   ├── Models/                    # Codable contracts for /api/tv/v1
│   │   └── Networking/                # HTTP BFF client & WebSocket resolve stream
│   └── Features/
│       ├── Onboarding/                # 6-digit Device Flow pairing UI
│       ├── Home/                      # Hero banner, server-driven shelves & genre chips
│       ├── Detail/                    # Movies, seasons/episodes & source picker
│       ├── Watchlist/                 # Household watchlist
│       ├── Search/                    # Instant catalog & TMDB search
│       ├── Settings/                  # Room/profile switcher & HDMI/trait diagnostics
│       └── Player/                    # AetherPlayerSurface, subtitles & modal track/source sheets
└── .github/workflows/build-tvos.yml   # Cloud build -> GitHub Release "latest" (Luna-unsigned.ipa)
```

## License

MIT — see [LICENSE](LICENSE).
