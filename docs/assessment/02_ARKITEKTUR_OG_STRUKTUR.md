# Vedlegg 2: Struktur og arkitektur (`Package.swift`, `project.yml`, lagdeling)

> **Dimensjonsvekt:** 20 %  
> **Overordnet mål:** Verifisere at modulgrensene, tilstandseierskapet, observasjonsgranulariteten, minne-/cache-arkitekturen, nettverks-/tillitsgrensene og bygg-/dokumentstyringen gir høy stabilitet uten kobling mellom UI, nettverk og avspillingsmotor.

---

## 1. Arkitekturkart og ansvarsfordeling

`Luna` er strukturert i to tydelig adskilte kompileringssoner:

1. **Linux-testbar kjerne (`Package.swift` -> `LunaCore`, 62 filer):**
   - Pure-Swift-kode uten `UIKit`, `SwiftUI`, `TVUIKit`, `AVFoundation`, `Network` eller `AetherEngine`-avhengighet.
   - Omfatter `Core/Models/*` (9 filer), `Core/Networking/*` (6 filer), `Core/Playback/*` (14 filer), `Core/Catalog/CatalogShelfIndexer.swift`, `Core/Discovery/BonjourServiceParser.swift`, rene deler av `Core/Cache/*` og `Core/Config/*`, `DesignSystem/LunaCopy.swift`, `App/{LunaNavigationBarVisibility,PreviewLaunchConfiguration,PreviewMock*}`, samt alle ikke-visuelle ViewModels (`PairingViewModel`, `HomeViewModel`, `CatalogBrowseViewModel`, `LibraryViewModel`, `SearchViewModel`, `MediaDetailViewModel`, `SourcePickerViewModel`, `DetailPreResolveController`).
2. **Darwin / tvOS 26-skall (`project.yml` -> `Luna`, 80 resterende `Sources/`-filer + `Packages/AetherBridge/`):**
   - App-vert (`LunaApp`, `MainNavigationShell`, `LunaTopBarView`), plattformtjenester (`BonjourServerBrowser`, `ArtworkPipeline`, `BlurHashImageCache`, `ServerConfiguration`, `ComfortPreferences`), hele `DesignSystem/`, alle SwiftUI/UIKit-visninger og hele spillervert-laget (`Sources/Features/Player/` — 34 filer).

---

## 2. Vurderingsområder og kriterier

### 2.1 Grenseflaten mellom ren kjerne (`LunaCore`) og Darwin-skall
- **Hva som vurderes:** Om all ikke-visuell forretningslogikk, tilstandsmaskiner og regler faktisk ligger i `LunaCore` (`Package.swift`), eller om kompleks logikk har «lekket» inn i Darwin-ekskluderte filer (`42` oppføringer i `Package.swift` `exclude:`).
- **Kritiske protokollkontrakter:**
  - `TabSessionContracts.swift`: dekobler tab- og feature-ViewModels fra `AppSessionStore` / UIKit / `Network`.
  - `DetailPreResolveController.swift` (`DetailStreamPrewarming`): dekobler pre-resolve fra `AetherEngine.prewarm`.
  - `PlaybackResolveSocket.swift` (`PlaybackResolveSocketProviding`): dekobler WebSocket-oppslag for Linux-testing.
  - `PlayerTransportProtocol.swift` (`PlayerTransportControlling`, `NativeAudioActivating`): dekobler spillerkontrollerne fra `AetherEngine` og `AVAudioSession`.
- **Vurderingsspørsmål:** Inneholder `ServerConfiguration.swift`, `ComfortPreferences.swift`, `ArtworkPipeline.swift` eller `Sources/Features/Player/*` ren tilstands- eller beregningslogikk som heller burde vært ekstrahert til `LunaCore` for Linux-testing?

### 2.2 Tilstandseierskap, spiller-dekomponering og observasjonsgranularitet
- **Hva som vurderes:** Om høyfrekvente endringer i avspilleren eller globale miljøtilstander utløser unødvendige SwiftUI-re-evalueringer på tvOS (`60 Hz` / `0 Hz` i hvile).
- **Kritiske arkitekturinvarianter:**
  - **Én delt `@MainActor AetherEngine`:** Opprettet én gang i `LunaApp.swift` og gjenbrukt gjennom hele appens levetid (aldri instansiert per spillervisning).
  - **`AppSessionStore` (`ServerConfiguration.swift`):** Vurderer vifteutbredelse (`@Observable` feltgranularitet) slik at f.eks. bakgrunnsoppdateringer eller stoppkvitteringer ikke tvinger hele navigasjonsskallet til å tegne om.
  - **5-kontroller-fasaden (`PlayerViewModel.swift`):** Koordinering mellom `PlayerSessionController`, `PlayerTrackController`, `PlayerScrubController`, `PlayerRestoreController` og `PlayerQoSReporter` via `weak var host` og `PlayerEnginePublishers`. Vurdere om ansvaret mellom kontrollerne er skarpt avgrenset uten sirkulære sideeffekter.
  - **Blad-observasjon (tick-isolasjon):** `engine.clock` (`$currentTime`, `$sourceTime`, `$bufferedPosition`) skal **kun** observeres i bladvisninger (`PlayerBottomBarView`, `PlayerTimelineScrubberView`, `EndsAtLeafView`, `ActiveChapterLabelLeafView`, `SubtitleOverlayView`), og `engine.diagnostics.$liveTelemetry` **kun** i `NerdHUDView` (`1 Hz`). `PlayerQoSReporter` skal holde `0 Hz` UI-oppdatering i normal avspilling ved terskelstyrt `DolbyVisionFallbackPolicy`.

### 2.3 Caching, oppgavekoalescering og maskinvare-/minneprofiler
- **Hva som vurderes:** Om minne- og diskcaches samarbeider sømløst mellom kaldstart, blaing og tung 4K/DV-avspilling på både `4 GB`-modeller og nyere Apple TV-maskinvare.
- **Kritiske kodepunkter:**
  - `DeviceMemoryProfile` (`DeviceHardwareCapabilities.swift`): skille mellom `.standard` (`< 6 GB`) og `.high2026` (`>= 6 GB`) på tvers av `sessionCacheByteBudget` (`1 GB` vs. `3 GB`), `forwardBufferSegments`, `maxConcurrentSourceRequests`, `retainsSessionCacheAfterStop`, `confirmAtmos` og `supportsHardwareAV1`.
  - `InflightTaskCoalescer` & `BoundedLRUMemoryCache`: verifisere at per-venter-kansellering ikke avbryter andre samtidige kallere på samme nøkkel, og at nøkkelkonstruksjonen i `LunaCoreHTTPTransport` unngår kollisjoner.
  - `DiskSWRStore`: `.cachesDirectory`-lagring av ETag + JSON for `Home`, `Filmer`, `Serier` og `Bibliotek`, samt beskyttelse mot at `304 Not Modified` leverer tomt resultat etter minnevarsel (`HomeCatalogLibraryEdgeTests`).
  - `ArtworkPipeline` & `ArtworkDiskCache`: SHA-256-nøkler, read-touch LRU, `Caches/Luna/img`-migrering, `enterPlaybackMemoryMode` ved avspilling (beholder bakteppe/logo for teppe) og totaltømming via `TabMemoryEvictionPolicy` + `AetherEngine.discardPrewarmedSources()` / `discardRetainedSessionCache()` på `UIApplicationDidReceiveMemoryWarningNotification`.

### 2.4 Nettverksoppdagelse, failover og origin-/TLS-tillit
- **Hva som vurderes:** Robustheten i å finne riktig LunaCore-tjener på lokalt nett, bytte sømløst mellom primær/lokal/reserve-URL, og beskytte legitimasjon på tvers av porter og domener.
- **Kritiske kodepunkter:**
  - `BonjourServerBrowser` + `BonjourServiceParser`: dual-stack IPv4/IPv6 mDNS `_lunacore._tcp`, lesing av TXT `api` og `https_port`/`tls_port`, avvisning av link-local `%`-soner i IPv6, `8 s` oppslagstimeout og ryddig opprydding av avbrutte resolvere.
  - `ServerFailoverPolicy`: prioritert rekkefølge mellom primær URL, `.local`-vertsnavn og reserve-URL, `probeReachability(timeoutSeconds: 3.0)` mot `GET /api/tv/v2/bootstrap`, og feilklassifisering (`isFailoverEligibleError`).
  - `LunaCoreHTTPTransport.isSameOrigin(_:)`: samlet origin-sjekk som behandler HTTP `:8090` og HTTPS `:8920` på samme vert som ekvivalente for auth-headere (`Authorization`, `X-Device-Id`), mens eksterne CDN- og bilde-URL-er går på egen uautentisert `URLSession`-bane i `LunaCoreSessionPool` (`api`, `artwork`, `ws`).
  - `LanURLSessionDelegate` + `EngineTLS.serverTrustEvaluator`: når `allowSelfSignedLanTLS == true`, skal selvsignert TLS-tillit være strengt avgrenset til konfigurert vert eller `.local`-adresser — aldri vilkårlige eksterne verter — og synkroniseres på nytt ved serverbytte/failover.

### 2.5 Byggsystem, SwiftPM-traits og dokumentstyring
- **Hva som vurderes:** At Linux-test, CI-bygg, `AetherEngine`-traits og modulkartet aldri driver fra hverandre.
- **Kritiske kodepunkter:**
  - `project.yml` som eneste kilde for XcodeGen (ingen sjekket inn `.xcodeproj`/`.xcworkspace`, `CODE_SIGNING_ALLOWED: NO`, `ENABLE_DEBUG_DYLIB: NO`, `local.lunacore`).
  - `Packages/AetherBridge/Package.swift` som eneste eier av `AetherEngine` (`exact: "7.75.0"`) og de 5 påkrevde traitene (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`).
  - `docs/architecture/CODEBASE_MODULE_MAP.md` 1:1-paritet og `design/tokens.json` -> `LunaTokens.swift` / `preview/tokens.css` generering.

---

## 3. Sjekkliste for vurdering av struktur og arkitektur

- [ ] **Ren kjerne vs. skall:** Alle `62` filer i `Package.swift` kompilerer og tester rent på Linux (`./scripts/test-core.sh`); ingen sentrale forretningsregler er unødvendig bundet til Darwin-lag i `Sources/Features/` eller `ServerConfiguration.swift`.
- [ ] **Protokollgrenser:** `TabSessionContracts`, `DetailStreamPrewarming`, `PlaybackResolveSocketProviding` og `PlayerTransportControlling` har rene grensesnitt uten lekkasje av UIKit/`AetherEngine`-konkrete typer inn i `LunaCore`.
- [ ] **Enkelt-motor & 5-kontroller-skille:** `LunaApp` oppretter kun én `@MainActor AetherEngine`, og `PlayerViewModel` delegerer rent til sine 5 kontrollere uten dobbelt eierskap av avspillingsøkt eller lydøkt.
- [ ] **Observasjonsgranularitet:** `rg "\.clock\b|\$currentTime|\$sourceTime|\$bufferedPosition|liveTelemetry" Sources/` bekrefter at høyfrekvent tilstand kun leses i bladvisninger (`PlayerBottomBarView`, `PlayerTimelineScrubberView`, `SubtitleOverlayView`, `NerdHUDView`).
- [ ] **Minneprofiler & tømming:** `DeviceMemoryProfile` skalerer korrekt mellom `.standard` og `.high2026`, `ArtworkPipeline.enterPlaybackMemoryMode` frigjør ikke-nødvendige bilder ved avspilling, og `TabMemoryEvictionPolicy` + `UIApplicationDidReceiveMemoryWarningNotification` tømmer inaktive faner og motor-caches.
- [ ] **Koalescering & SWR:** `InflightTaskCoalescer` isolerer kansellering per venter, `DiskSWRStore` bruker entydige fane-/filternøkler, og `HomeCatalogLibraryEdgeTests` / `DiskSWRStoreMultiTabLinuxTests` passerer.
- [ ] **Discovery & failover:** `BonjourServerBrowser` avviser `%`-link-local IPv6, `ServerFailoverPolicy` håndterer `:8090`/`:8920`/`.local`/reserve uten løkker, og `LunaCoreSessionPool` skiller `api`, `artwork` og `ws` i separate ephemere `URLSession`-baner.
- [ ] **Origin & TLS-tillit:** `isSameOrigin(_:)` sender aldri `Authorization`/`X-Device-Id` til eksterne verter, og `LanURLSessionDelegate` + `EngineTLS.serverTrustEvaluator` oppdateres konsistent ved innstillingsendring og failover.
- [ ] **Bygg & trait-styring:** `Packages/AetherBridge/Package.swift` pinner `exact: "7.75.0"` og alle 5 traits; `project.yml` genererer gyldig tvOS 26.0-prosjekt i `build-tvos.yml` med korrekt `Info.plist`, `Assets.car` og `Top Shelf`.

---

## 4. Verifiseringsmetoder for Dimensjon 2

| Nivå | Konkret kommando / fremgangsmåte | Forventet evidens |
| :--- | :--- | :--- |
| **Nivå 1 (Statisk)** | `./ops/bin/luna-check --local`; `rg "import (SwiftUI\|UIKit\|AVFoundation\|Network\|Aether)"` på alle filer listet i `Package.swift` `sources:`; `rg "AetherEngine\(" Sources/` | `CODEBASE_MODULE_MAP.md` 1:1 grønn; `0` Darwin-importer i `LunaCore`; `1` instansiering av `AetherEngine` i `LunaApp.swift` |
| **Nivå 1 (Observasjonsrevisjon)** | `rg "engine\.clock\|engine\.diagnostics\|liveTelemetry\|sessionCacheStatus" Sources/Features/Player/` | Treff kun i godkjente bladvisninger (`PlayerBottomBarView`, `PlayerTimelineScrubberView`, `SubtitleOverlayView`, `NerdHUDView`) |
| **Nivå 2 (Linux kjerne)** | `./scripts/test-core.sh` | `NetworkCacheAndMemoryProfileTests`, `ServerFailoverAndComfortModelsTests`, `DiskSWRStoreMultiTabLinuxTests`, `HomeCatalogLibraryViewModelsTests`, `HomeCatalogLibraryEdgeTests`, `LibraryEdgeTests` passerer |
| **Nivå 3 (tvOS Simulator & IPA)** | `build-tvos.yml` (`test-tvos` + `build-ipa`) | `BonjourServerBrowserTests`, `LunaCoreSessionPoolTests`, `LunaCoreHTTPTransportTests`, `ClientOriginAndBlurHashTests`, `LunaNavigationAndDetailRaceTests` grønne; `Luna-unsigned.ipa` bygget med `AetherBridge`-traits |
