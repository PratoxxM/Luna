# Vedlegg 1: Kodekvalitet (`Sources/`, `Packages/`, `Tests/`)

> **Dimensjonsvekt:** 20 %  
> **Overordnet mål:** Verifisere at hele Swift `6.2`-kodebasen er dataras-sikker, deterministisk ved kansellering og minnepress, fri for skjulte feil og sideload-feller, samt tilstrekkelig dekket av troverdige tester.

---

## 1. Kodebaseinventar og vurderingsomfang

Totalt omfang i repoet (per `docs/architecture/CODEBASE_MODULE_MAP.md` og `ops/bin/luna-check`): **194 `.swift`-filer** fordelt på **144 produksjons- og brofiler (`36 615` LOC: 142 i `Sources/` med `36 573` LOC + 2 i `Packages/AetherBridge/` med `42` LOC)** og **50 testfiler (`16 966` LOC)**.

| Område | Filer | LOC | Kjerneansvar |
| :--- | ---: | ---: | :--- |
| `Sources/App/` | 10 | 2 701 | App-livssyklus (`LunaApp`), navigasjonsskall, toppbar, `--preview-screen`-rigg |
| `Sources/Core/Cache/` | 7 | 2 045 | `ArtworkPipeline`, `ArtworkDiskCache`, `DiskSWRStore`, `InflightTaskCoalescer`, `BlurHash*` |
| `Sources/Core/Catalog/` | 1 | 214 | `CatalogShelfIndexer` (deduplisering, hylleorden) |
| `Sources/Core/Config/` | 10 | 2 421 | `SideloadSafeStorage`, `ServerConfiguration`, `ServerFailoverPolicy`, `DeviceHardwareCapabilities`, `ComfortPreferences*`, `PlaybackPreferenceStore`, `SmartTrackRuleEngine`, `TabMemoryEvictionPolicy`, `TabSessionContracts` |
| `Sources/Core/Discovery/` | 2 | 395 | `BonjourServiceParser`, `BonjourServerBrowser` (`NWBrowser`) |
| `Sources/Core/Models/` | 9 | 3 256 | `Codable` DTO-er og visningsmodeller for hjem, katalog, bibliotek, detalj, kapitler og avspilling |
| `Sources/Core/Networking/` | 6 | 1 593 | `LunaCoreHTTPTransport`, `LunaCoreClient+*`, `LunaCoreSessionPool`, `PlaybackResolveSocket` |
| `Sources/Core/Playback/` | 14 | 1 758 | Rene politikker og matematikk for teppe, QMS/HDR-fallback, sporvalg, scrubbing, serieflyt, stoppkvittering |
| `Sources/DesignSystem/` | 16 | 3 797 | Tokens, tema, typografi, fokusstil, tekstfelt, kort og delte primitiver |
| `Sources/Features/` | 67 | 18 393 | `Browse` (5), `Detail` (11), `Home` (4), `Library` (3), `Onboarding` (2), `Player` (34 / 9 328 LOC), `Search` (2), `Settings` (4), `Shared` (2) |
| `Packages/AetherBridge/` | 2 | 42 | `Package.swift` (trait-låsing `AetherEngine 7.76.0`) + `Exports.swift` |
| `Tests/LunaCoreTests/` | 21 | 6 653 | Linux-kjørbare (`swift:6.2`) enhets-, kontrakt-, overflyt- og adversariale tester |
| `Tests/LunaTests/` | 29 | 10 313 | 28 tvOS XCTest-suiter + `PlayerTestDoubles.swift` |

---

## 2. Vurderingsområder og kriterier

### 2.1 Swift 6.2 streng samtidighet (`Mutex`, `@MainActor`, `Sendable`, `Task`)
- **Hva som vurderes:** Korrekt bruk av Swift `6.2`-isolasjon uten dataras, aktør-reentrancy-feil, eller minnelekkasjer gjennom fangede `self`-referanser.
- **Kritiske kodepunkter:**
  - `Mutex`-beskyttet tilstand i `LunaCoreHTTPTransport`, `LunaCoreSessionPool`, `DiskSWRStore`, `InflightTaskCoalescer` og `ArtworkDiskCache`.
  - Egendefinerte aktører og låser: `ArtworkPipeline` (off-main bildedekoding), `DiskSWRStorageActor`, `NativeAudioSessionActivator`, `ResolveFirstEventLatch`.
  - De fem `@MainActor`-kontrollerne eid av `PlayerViewModel` (`PlayerSessionController`, `PlayerTrackController`, `PlayerScrubController`, `PlayerRestoreController`, `PlayerQoSReporter`): kontrollere at alle referanser tilbake til verten bruker `weak var host` uten retain-sykluser.
  - `Task` / `Task.detached`-livssyklus i `PlayerResolvePipeline` (frakoblet `stopped`-heartbeat), `PlayerQoSReporter` (`15 s`-løkke), `DetailPreResolveController` (`taskToken` ved rask A->B->A-navigasjon), `PairingViewModel` (`pollGeneration`) og `SearchViewModel` (debounce-kansellering).
  - Combine-abonnementer (`cancellables`) i `PlayerEnginePublishers` og `PlayerAudioSessionCoordinator`.

### 2.2 Feilhåndtering, kansellering og numeriske grenser
- **Hva som vurderes:** At nettverks-, dekodings- og avspillingsfeil ikke maskeres av stille `try?`, at kansellering ikke behandles som ekte feil, og at tallkonverteringer fra ekstern JSON/media ikke kan utløse `SIGILL`/overflyt.
- **Kritiske kodepunkter:**
  - `LunaCoreError`: tydelig skille mellom `isCancellation`, `.unauthorized` (`401` -> tvungen `unpairDevice()` og cachetømming), `.serverMessage`, `.decodingFailed` og failover-kvalifiserte nettverksfeil (`ServerFailoverPolicy.isFailoverEligibleError`).
  - Revisjon av `try?`-forekomster i kritiske løp: `PlayerRestoreController`, `PlayerTrackController+SubtitleAndHDR`, `DetailPreResolveController`, `ServerConfiguration` og `DiskSWRStore`.
  - Numeriske grenser: `isFinite`-sjekk for `Double` (varighet, posisjon, fps, bitrate), `Int(exactly:)` / clamping for `ms`-forsinkelser og byte-budsjetter, samt fravær av heltallsoverflyt i `ChapterModels`, `PlayerTimelinePolicy`, `LunaCoreSessionPool`, `MediaDetailViewModel` og `PlaybackTrackIntent`.

### 2.3 Sideload-sikkerhet og hemmeligholdshygiene
- **Hva som vurderes:** At koden tåler ATVLoadly sin omskriving av `CFBundleIdentifier`, og at verken enhetstoken eller signerte strømmetokener kan lekke til logger, krasjrapporter eller tredjepartstjenere.
- **Kritiske kodepunkter:**
  - Zero `Bundle.main.bundleIdentifier` i hele repoet.
  - Stabilt `"luna.v1.*"`-navnerom i `SideloadSafeStorage` (alle konfigurasjons-, komfort-, tale- og forsinkelsesnøkler) + statisk Keychain `kSecAttrService = "luna.v1.credentials"` uten bundle-bundne access groups + `-34018`-fallback til `"luna.v1.keychain_fallback.*"`.
  - Symmetrisk `EngineLog.registerSecret(_:)` / `unregisterSecret(_:)` (og minimum tokenlengde-vakt) for `deviceToken` i `ServerConfiguration` (`AppSessionStore` ved oppstart, `completePairing`, `unpairDevice`), `AetherDetailStreamPrewarmer` i `MediaDetailView`, `PlayerSessionController` (`preparedSession`, `activeSession`, feil/nedrigging/episodebytte), `PlayerResolvePipeline` og `PlayerQoSReporter` (`nextEpisodePrewarm`).
  - Strenge `isSameOrigin(_:)`- og `LanURLSessionDelegate`-grenser mot utilsiktet header- eller TLS-lekkasje.

### 2.4 Testdekning, testkvalitet og mock-troverdighet
- **Hva som vurderes:** At kritisk logikk er testet mot reell oppførsel (ikke implementasjonsdetaljer), og at gap mellom `CODEBASE_MODULE_MAP.md` og testsuiter er kartlagt og vurdert etter risiko.
- **Dokumenterte dekningsspalter med `—` i `CODEBASE_MODULE_MAP.md` som skal risikovurderes:**
  - `Sources/App/PreviewMockArtworkRenderer.swift` (lav risiko; test-/preview-rigg)
  - `Packages/AetherBridge/Package.swift` og `Packages/AetherBridge/Sources/AetherBridge/Exports.swift` (bygg-/trait-kontrakt og `@_exported import AetherEngine`-bro; krever CI-byggverifisering)
  - `Sources/DesignSystem/{LunaBadges,LunaListRow,LunaSheetContainer,LunaInlineStateViews}.swift` (nye F2-primitiver uten direkte enhetstest i tabellen)
  - `Sources/Features/Detail/{DetailHeroHeaderView,DetailMoreAndOverviewSheets,DetailSeasonsSectionView}.swift` (sentrale tvOS-fokus- og layoutkomponenter uten direkte XCTest-oppføring)
- **Testdobbel-troverdighet:** Evaluere om `Tests/LunaTests/PlayerTestDoubles.swift`, `PreviewMockURLProtocol.swift` og `PreviewMockFixtures.swift` realistisk speiler `AetherEngine 7.76.0`-signaturer (`docs/aether-engine-api.md`) og `/api/tv/v2`-svar (inklusive feilkonvolutter og `WS`-tidslinjer).

### 2.5 Vedlikeholdbarhet, modulstørrelse og norsk teksthygiene
- **Hva som vurderes:** Teknisk gjeld, modulstørrelse mot `800` LOC-budsjettet (spesielt i `Sources/Features/Player/` på 34 filer / `9 328` LOC), død kode og lokalisering.
- **Kritiske kodepunkter:** Filer over ~`500–600` LOC som er nær `800`-grensen, duplisert logikk mellom ark og hurtigpaneler, og etterlevelse av `Resources/Localizable.xcstrings` (`sourceLanguage == "nb"`) + `LunaCopy`.

---

## 3. Sjekkliste for vurdering av kodekvalitet

- [ ] **Samtidighet:** Alle delte samlinger og caches i `Sources/Core/` er beskyttet med `Mutex`, `actor` eller `@MainActor`, og ingen nye `Task.detached` lekker arbeid etter at brukeren forlater skjermen.
- [ ] **Minnelekkasjer:** `PlayerViewModel` og de 5 spillerkontrollerne har verifisert `[weak host]`/`[weak self]`, og `PlayerExitBlinkRegressionTests` / `PausedScrubCommitTests` bekrefter deallokering uten retain-syklus.
- [ ] **Kansellering:** `CancellationError` og `LunaCoreError.isCancellation` logges ikke som brukerfeil, og raske skjermbytter (A->B->A i `DetailPreResolveController`, fanebytte, søketasting, parings-polling) bruker generasjonsteller eller kansellering uten kappløp.
- [ ] **Stille `try?`-revisjon:** Alle `try?`-forekomster i `Player*`, `DetailPreResolveController`, `ServerConfiguration` og `DiskSWRStore` er gjennomgått; ingen svelger kritiske I/O-, dekodings- eller avspillingsfeil uten fallback eller logging.
- [ ] **Numerisk robusthet:** Alle eksterne verdier fra `/api/tv/v2` og `AetherEngine` (`duration`, `currentTime`, `subtitleDelayMs`, `chapters`, byte-tellinger) har `isFinite`- / `max(0, ...)`- / `Int(exactly:)`-vakter; `Etappe6NumericOverflowTests` og `Etappe6AdversarialHardeningTests` passerer.
- [ ] **Sideload-lagring:** Ingen forekomst av `Bundle.main.bundleIdentifier`; alle `"luna.v1.*"`-nøkler i `SideloadSafeStorage` og `PlaybackPreferenceStore` er intakte, og `SideloadSafeStorageTests` + `CatalogShelfAndStorageLinuxTests` dekker Keychain + `-34018`-fallback.
- [ ] **Hemmelighetsredaksjon:** Alle livssykluser for `deviceToken` og `streamToken` (oppstart, paring, avparing, detail-prewarm, warm direct-mount, cold resolve, source switch, next-episode prewarm, error/teardown) har matchende `EngineLog.registerSecret` og `unregisterSecret`.
- [ ] **Testdekning & gap:** `./scripts/test-core.sh` (21 `LunaCoreTests`-suiter) og `build-tvos.yml` (`28` `LunaTests`-suiter) kjører uten hopp (`XCTSkip` revidert), og alle moduler med `—` i `CODEBASE_MODULE_MAP.md` har enten dokumentert indirekte dekning eller oppført P2-oppgave.
- [ ] **Testdobbel-paritet:** `PlayerTestDoubles.swift` og `PreviewMockURLProtocol.swift` speiler reelle state-overganger, feilkonvolutter og `LoadOptions`-kontrakter.
- [ ] **LOC & kopikvalitet:** `./ops/bin/luna-check --local` bestått (`<= 800` LOC, ingen forbudte mønstre, ren `Localizable.xcstrings` norsk flertallsbøying).

---

## 4. Verifiseringsmetoder for Dimensjon 1

| Nivå | Konkret kommando / fremgangsmåte | Forventet evidens |
| :--- | :--- | :--- |
| **Nivå 1 (Statisk)** | `./ops/bin/luna-check --local` | `194 .swift files`, `<= 800 LOC`, `0` sideload/hygiene/copy-brudd |
| **Nivå 1 (Manuell/grep)** | `grep -rnE "try\?" Sources/`; `grep -rnE "registerSecret\|unregisterSecret" Sources/`; `grep -rnE "Task\.detached" Sources/`; `find Sources -name '*.swift' -print0 \| xargs -0 wc -l \| sort -nr \| head -n 25` (alternativt `rg`) | Full oversikt over stille `try?`, token-symmetri, frakoblede oppgaver og største filer |
| **Nivå 2 (Linux kjerne)** | `./scripts/test-core.sh` | Alle 21 suiter i `Tests/LunaCoreTests/` grønne (spesielt `Etappe6AdversarialHardeningTests`, `Etappe6NumericOverflowTests`, `Etappe6ContractAcceptanceTests`, `TvV2ClientAndPlaybackReceiptTests`, `CatalogShelfAndStorageLinuxTests`) |
| **Nivå 3 (tvOS Simulator)** | `build-tvos.yml` (`test-tvos` -> `xcodebuild test`) | Alle 28 suiter i `Tests/LunaTests/` grønne (spesielt `SideloadSafeStorageTests`, `PlayerExitBlinkRegressionTests`, `LunaCoreHTTPTransportTests`, `LunaCoreSessionPoolTests`) |
