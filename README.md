# Luna for tvOS

**Luna** (`v2.2.8`) is a native SwiftUI tvOS media player built on [AetherEngine](https://github.com/superuser404notfound/AetherEngine) (`7.65.0`) for the MediaOS `/api/tv/v1` native TV engine.

## Highlights

- **Dual-Layer Dolby Vision & Spatial Object Audio**: Linked against `AetherEngine 7.65.0` via `Packages/AetherBridge` with `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`, `TrueHDObjectAudio`, and `DTSXObjectAudio` enabled.
- **Room & Hardware Profiles**:
  - `dv-fel-714` (*Kjellerstua*): Prioritizes 4K UHD BluRay Remuxes with Dolby Vision Profile 7 FEL / Profile 8 and renders TrueHD Atmos / DTS:X into a `7.1.4` spatial bed.
  - `hdr10-512` (*Stua*): Prioritizes 4K HDR10+ / HDR10 streams with `baseLayerOnly` DV handling and renders spatial audio into a `5.1.2` bed.
- **4-Row Evening Home & Instant Cold Boot**:
  - `DiskSWRStore` renders cached `/api/tv/v1/home` shelves in `0 ms` on cold start while refreshing silently via `ETag` / `304 Not Modified`.
  - Streamlined 4-row `HomeView` opens directly on *Fortsett å se* (1-click direct resume/next episode), *Kommende episoder* (with Norwegian air-date badges), *Populære filmer*, and *Populære serier*, while genre browsing and *Mitt bibliotek* (*Ønsker å se*, *Favoritter*, and *Lokalt på NAS*) live cleanly in top tabs.
- **OLED/HDR-Comfortable Custom Player Shell, Now Playing & MetalFX Upscaling**:
  - Invisible UIKit `SiriRemoteTouchSurface` (`UIView` + `.focusEffectDisabled()`) with velocity-aware continuous horizontal thumb scrubbing, multi-swipe parking, and live `16:9` `ScrubPreviewBubbleView` stills (`scrubThumbnail` + `AetherScrubPreviewView` for DV P5 / AV1).
  - Zero-blink HDMI range/frame-rate handoff via `ResolvingCurtainView` locked to `hasFirstFrameReadyForDisplay`, rendered in dark HDR-safe cinema glass (`LunaTheme.cinemaGlass`).
  - Single HTTP 206 stream (`maximumSubtitleAdvanceSeconds = 0` & `maximumSubtitleDelaySeconds = 10`) even when subtitles are active on 80 GB 4K Remuxes.
  - System Control Center & HomeKit metadata integration via `PlayerNowPlayingCoordinator`, plus opt-in MetalFX low-resolution upscaling (`LowResUpscaleMode`: `.off`, `.auto`, `.animeLineArt`) for SD / 720p / 1080p streams.
  - Warm-white text subtitles and `.colorMultiply` HDR luminance dimming for PGS/DVB bitmap subtitles in `SubtitleOverlayView`, plus `SmartTrackRuleEngine` automatic Nordic/English audio & subtitle selection.
  - Compact 3-tab swipe-down `PlayerTopDrawerView` (*Undertekster*, *Lyd* `±50 ms`, *Kilde & Kapitler* seamless timecode switch), intro/credits skip & next-episode cards (`SeriesFlowOverlays`), and a 1 Hz leaf `NerdHUDView`.
- **Zero-Touch LAN Setup & Sideload-Ready Cloud Builds**:
  - Discovers MediaOS automatically via Bonjour (`_mediaos._tcp`) and pairs using a 6-digit TV code approved in MediaOS Web.
  - GitHub Actions generates `Luna.xcodeproj` via XcodeGen, runs `LunaTests`, compiles an unsigned Release `Luna-unsigned.ipa`, and publishes it to the rolling `latest` GitHub Release for wireless installation and 7-day certificate renewal via ATVLoadly.

## Architecture

```text
Luna/
├── AGENTS.md
├── project.yml                        # XcodeGen specification (Luna + LunaTests)
├── Config/Info.plist                  # ATS LAN HTTP + Bonjour (_mediaos._tcp)
├── Packages/AetherBridge/             # Local SPM bridge enabling all 5 AetherEngine traits
├── Resources/Assets.xcassets/         # tvOS App Icon & Top Shelf brand assets
├── Sources/
│   ├── App/                           # LunaApp (single @MainActor AetherEngine) & MainNavigationShell
│   ├── Core/
│   │   ├── Cache/                     # DiskSWRStore (0 ms /home JSON) & ArtworkPipeline (CGImage + BlurHash)
│   │   ├── Config/                    # SideloadSafeStorage, ServerConfiguration, ComfortPreferences & SmartTrackRuleEngine
│   │   ├── Discovery/                 # NWBrowser Bonjour (_mediaos._tcp) discovery
│   │   ├── Models/                    # Codable contracts for /api/tv/v1 (Home, Detail, Playback, Chapters)
│   │   └── Networking/                # MediaOSClient, MediaOSSessionPool & PlaybackResolveSocket
│   ├── DesignSystem/                  # LunaTheme, AmbientBackdropView & isolated-@FocusState Cards/
│   └── Features/
│       ├── Shared/                    # MediaCardComponents (TransientErrorBanner, MediaCardMutator, StandardPosterContextMenuItems)
│       ├── Onboarding/                # 6-digit Device Flow pairing UI
│       ├── Home/                      # Hero-free HomeView & ShelfRowView
│       ├── Browse/                    # CatalogBrowseView & CustomRowBrowseView
│       ├── Library/                   # LibraryHubView (Huskeliste, Favoritter & Lokalt NVMe/Arkiv)
│       ├── Detail/                    # MediaDetailView, DetailHeroHeaderView, DetailPreResolveController, DetailCastStripView & SourcePickerSheetView
│       ├── Search/                    # Instant FTS5 & TMDB SearchView
│       ├── Settings/                  # Dynamic Room/profile switcher, DV/audio/upscaling overrides & cache controls
│       └── Player/                    # PlayerContainerView, PlayerViewModel, PlayerSessionCoordinator,
│                                      # PlayerNowPlayingCoordinator, PlayerEngineConfigurator,
│                                      # SiriRemoteTouchSurface, ScrubPreviewBubbleView,
│                                      # ResolvingCurtainView, PlayerBottomBarView, PlayerTopDrawerView,
│                                      # SubtitleOverlayView, SeriesFlowOverlays & NerdHUDView
├── Tests/
│   └── LunaTests/                     # Swift XCTest suite (tracks, chapters, origin/BlurHash, models, cache)
└── .github/workflows/build-tvos.yml   # Cloud build + LunaTests -> GitHub Release "latest" (Luna-unsigned.ipa)
```

## License

MIT — see [LICENSE](LICENSE).
