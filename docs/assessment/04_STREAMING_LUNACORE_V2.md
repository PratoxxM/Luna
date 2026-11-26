# Vedlegg 4: Funksjonalitet for best mulig streaming fra LunaCore (`/api/tv/v2`)

> **Dimensjonsvekt:** 35 %  
> **Overordnet mål:** Verifisere hvert ledd i den ende-til-ende streamingkjeden mellom `Luna` tvOS-klienten, `/api/tv/v2`-endepunktene og `AetherEngine 7.76.0` — fra oppdagelse og `0-RTT` forhåndsoppslag til flimmerfri bilde-/HDMI-overgang, tapsfri lyd, intelligent teksting, sømløst kildebytte, taktil spoling, serieflyt og trygg minne-/tokenhåndtering.

---

## 1. End-to-End streamingkjede og `/api/tv/v2`-overflate

`Luna` er bygget rundt en kontinuerlig 6-trinns streamingkjede over `/api/tv/v2` (utledet utelukkende fra klientkoden i `Sources/Core/Networking/`, `Sources/Core/Playback/`, `Sources/Features/{Detail,Player}/` og `docs/aether-engine-api.md`):

| Trinn | Klientkomponenter | `/api/tv/v2` & protokoll-grensesnitt |
| :--- | :--- | :--- |
| **1. Discovery, bootstrap & SWR** | `BonjourServerBrowser`, `ServerConfiguration`, `ServerFailoverPolicy`, `DiskSWRStore`, `HomeViewModel`, `CatalogBrowseViewModel`, `LibraryViewModel` | `_lunacore._tcp` (`api`, `https_port`), `POST /pair/request`, `GET /pair/poll/{code}`, `GET /bootstrap`, `PATCH /device/profile`, `GET /{home,catalog/*,rows/*,library,items/*,search}` (`If-None-Match` / `304`), `/api/tv/v2/img/*` |
| **2. Pre-resolve & `0-RTT` oppvarming** | `DetailPreResolveController`, `AetherDetailStreamPrewarmer`, `SourcePickerViewModel` | `POST /playback/prepare`, `POST /playback/candidates`, `GET /playback/{sessionId}/alternatives` |
| **3. Oppslag & motorstart** | `PlayerSessionController`, `PlayerResolvePipeline`, `PlaybackResolveSocket`, `PlayerEngineConfigurator`, `LunaApp` | `POST /playback/resolve`, `WS /ws/playback/:resolveId`, `GET /playback/resolve/{resolveId}`, `AetherEngine.load(url:startPosition:options:)` |
| **4. Teppe, QMS/HDR & lydøkt** | `ResolvingCurtainView`, `PlaybackCurtainWatchdog`, `PlaybackCurtainPresentationPolicy`, `PlayerAudioSessionCoordinator` | `AVDisplayManager` / `AVDisplayCriteria` (`dvcC`), `CADisplayLink` QMS, `AVAudioSession`, `hasFirstFrameReadyForDisplay` / `isAwaitingDisplaySwitch` |
| **5. Spor, teksting, HDR10 & kildebytte** | `PlayerTrackController`, `OriginalLanguageTrackSelector`, `SmartTrackRuleEngine`, `PlaybackTrackIntent`, `DolbyVisionFallbackPolicy`, `SubtitleOverlayView` | `POST /playback/{sessionId}/switch`, `POST /playback/{sessionId}/subtitles/search-and-attach`, `POST /playback/{sessionId}/subtitles/auto-align`, `PlaybackPreferenceStore` |
| **6. Scrub, restore, QoS, serieflyt & nedrigging** | `PlayerScrubController`, `TouchCaptureUIView`, `RemoteScrubMath`, `PlayerRestoreController`, `PlayerQoSReporter`, `SeriesFlowOverlays`, `ArtworkPipeline`, `PlaybackStopReceipt` | `POST /playback/heartbeat` (`playing`/`paused`/`stopped`, `qos`, `cancelInflight`), `nextEpisodePrewarm` (`8 MB`), `pendingCommand`, `TabMemoryEvictionPolicy` |

---

## 2. Vurderingsområder og kriterier

### 2.1 Discovery, SWR-kaldstart, failover og `0-RTT` pre-resolve
- **Hva som vurderes:** Hvor raskt og driftssikkert brukeren kommer fra app-åpning til valgt tittel og klar strøm, uten å vekke arkivdisker unødig.
- **Kritiske kodepunkter:**
  - `GET /api/tv/v2/bootstrap` + `PATCH /api/tv/v2/device/profile` (`350 ms` debounce): synkronisering av romnavn, maskinvareprofil, `X-Supports-HW-AV1`, `X-Physical-Memory-GB` og brukerpreferanser.
  - `DiskSWRStore` + `InflightTaskCoalescer`: umiddelbar visning fra `.cachesDirectory` med betinget `If-None-Match` / `304` for `home`, `catalog/*` og `library`, samt sikker failover (`ServerFailoverPolicy`) ved midlertidige brudd.
  - `DetailPreResolveController`: `0 ms` / `180 ms` debounced `POST /playback/prepare`, `taskToken`-beskyttelse mot A->B->A-kappløp, gjenbruk av pågående `inflightPrepareTask` ved tidlig klikk på «Spill av», opprydding av foreldreløse økter, og **streng `canClientPrewarmBytes == true`-sperre** før `AetherEngine.prewarm` (beskytter spinn-ned på arkivlagring).
  - `performWarmDirectMount` (`PlayerSessionController+ResolveAndSwitch.swift`): spekulativ montering av forberedt strøm med bakgrunnspromotering til full økt og sømløst fall til kaldt oppslag ved utløpt/avvist økt.

### 2.2 Playback-oppslag (`WS`/HTTP) og `AetherEngine 7.76.0` `LoadOptions`
- **Hva som vurderes:** Driftssikkerheten i asynkront oppslag og at alle motorflagg matcher Apple TV-maskinvaren og `docs/aether-engine-api.md`.
- **Kritiske kodepunkter:**
  - `PlayerResolvePipeline` + `PlaybackResolveSocket`: håndterer både umiddelbar `200` `TvPlaybackSession` og `wsPath` + `resolveId`; `WS /api/tv/v2/ws/playback/:resolveId` terminerer på `resolve.ready` / `resolve.failed`, med **`1.5 s` første-hendelse-watchdog** (`ResolveFirstEventLatch`) som automatisk faller tilbake til `GET /api/tv/v2/playback/resolve/{resolveId}` hvert `750 ms` (opptil 248 forsøk). Tidlig brukeravbrudd sender `POST /playback/heartbeat` med `cancelInflight: true`.
  - Enkelt-motor-invarianter (`LunaApp.swift` + `PlayerEngineConfigurator.swift`): `maximumSubtitleAdvanceSeconds = 0` (hindrer 2. parallelle 4K HTTP-strøm når teksting er aktiv), `maximumSubtitleDelaySeconds = 10` (10 s historikk for positiv forsinkelse), `ownsSoftwareNowPlaying = true`, `ownsVideoNowPlayingSession = true`, `ownsVideoNowPlayingCommands = true`, og asynkron `prewarmDualLayerDolbyVision()` ved oppstart.
  - `LoadOptions`-kalibrering: `dualLayerRoute = .softwareHost`, DV Profile 7 FEL (`preferDualLayerDolbyVision`, `foldsDolbyVisionFEL`, `canCarryDualLayerDolbyVision`, `allowsDualLayerDolbyVisionWhenForced`), `preferHDR10PlusOverForcedDolbyVision` for `hdr10-512` (Samsung The Frame), `untaggedVideoColor`, `inverseTelecine`, `upscalesLowResolutionVideo` / `upscaleScaler` (MetalFX / Anime4K), `audioBridgeMode` (`.lossless` / `.surroundCompat`), `audioShaping` (nattmodus / dialogforsterkning), `objectAudioRendering` (`Auto` / `5.1.2` / `7.1.4` / `Stereo 2.0`), `externalSubtitles`, samt `DeviceMemoryProfile`-budsjetter og `4 GB`-vern (`sessionCacheByteBudget`, `sessionCacheFreeReserveBytes`, `forwardBufferSegments`, `maxConcurrentSourceRequests`, `retainsSessionCacheAfterStop`, `confirmAtmos` og deaktivering av `generatesBackgroundScrubPreviews` på `.standard` `4 GB` ved DV P7).

### 2.3 Blinkfri teppe-avdekking, HDMI QMS/Dynamic Range og lydøkt
- **Hva som vurderes:** At avspillingsstart, episodeoverganger og avslutning ikke gir HDMI-blink, svart skjerm-heng eller tapte lydkanaler.
- **Kritiske kodepunkter:**
  - `PlaybackCurtainWatchdog` (`5.0 s` sikkerhetsutløser) + `PlaybackCurtainPresentationPolicy` (`180 ms` ren sort `#000000`-pause på varme starter uten skjermbytte) i `ResolvingCurtainView`: holder teppet opakt til `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch`.
  - `PlayerAudioSessionCoordinator`: `deactivatesAudioSessionOnStop = false` (hindrer AVR/HDMI-resynk ved exit), `MenuDisplayMode` (`.sdr60Hz`, `.preserveHDR60HzQMS` med `CADisplayLink`-sampling og HEVC/DV P8.1 `dvcC` `AVDisplayCriteria`, `.preserveExactMatch`), utsatt `engine.stop(resetDisplayCriteria: true)` til bakgrunn/detaljexit, off-main `NativeAudioSessionActivator` for `.loopback`/`.remoteBypass`, og automatisk nullstilling av eARC-lydsynk på trådløs AirPlay/Bluetooth-rute.

### 2.4 Lydspor, undertekster, HDR10-fallback og sømløst kildebytte
- **Hva som vurderes:** At brukeren får riktig originalspråk/tapsfritt lydspor, lesbar og synkronisert teksting, og smertefri redning hvis DV FEL hakker eller kilde må byttes.
- **Kritiske kodepunkter:**
  - `OriginalLanguageTrackSelector` + `PlaybackPreferenceStore`: «Norsk tale» per-tittel-overstyring, `TrueHD Atmos` > `DTS:X` > tapsfri rangering for `originalLanguage`.
  - `SmartTrackRuleEngine`: nordisk/engelsk tale- og tekstlogikk (tvungen vs. full vs. SDH vs. bitmap PGS).
  - `PlayerTrackController+SubtitleAndHDR`: sofa-henting (`POST /playback/{sessionId}/subtitles/search-and-attach`), automatisk synkronisering (`POST /playback/{sessionId}/subtitles/auto-align`) + `reloadAtCurrentPosition` for eksterne tekstspor, `220 ms` debounced lyd-/tekstforsinkelse (`PlaybackSyncTimingPolicy`), Kveldslys HDR-dimming og kollisjonsfrie tekstkorridorer (`SubtitleOverlayLayout` / `SubtitleOverlayView`).
  - `DolbyVisionFallbackPolicy`: `0 Hz` terskelstyrt deteksjon av DV P7 FEL-bildebortfall og 1-trykks `Bytt til HDR10-baselag` (`switchToHDR10BaseLayer`).
  - `switchSource` (`POST /playback/{sessionId}/switch` + `GET /alternatives` + `POST /candidates`): bruker `prepareForItemReplacement()` og `PlaybackTrackIntent` for å bevare brukerens aktive lyd-/tekst-/forced-/av-intensjon og `ms`-forsinkelse selv når ny MKV har annen sporrekkefølge.

### 2.5 Spoling, bakgrunnsgjenoppretting, QoS-heartbeat, serieflyt og nedrigging
- **Hva som vurderes:** Taktil presisjon på Siri Remote, pålitelig gjenoppretting etter pause/bakgrunn, oppdaterte `nextUp`-hyller og trygg ressurs-/tokenopprydding.
- **Kritiske kodepunkter:**
  - `PlayerScrubController` + `TouchCaptureUIView` + `RemoteScrubMath`: berøringsspoling kun i pause (`20 pt` løsrivelse, `0 pt` revers-dødsone, `1.35` akselås, EMA `α=0.35`, 3-soners varighetskurve), `< 280 ms` ringklikk `±10 s` (koalescert med `150 ms` debounce) vs. `>= 280 ms` ringhold (`30 -> 120 -> 300 s/s`), `AetherScrubPreviewView` / `CGImage`-boble (`45 ms` takt), og `scrubCommitToken`-kappløpsvakt.
  - `PlayerRestoreController`: `ScenePhase`-gjenoppretting via `transport.reloadAtCurrentPosition` (med full re-resolve fallback hvis sesjonen er utløpt), riktig aktiveringsrekkefølge for pauset gjenopptak, og eksplisitt styring av `UIApplication.shared.isIdleTimerDisabled` under oppslag/avspilling/spoling/gjenoppretting (hindrer skjermsparer på `.softwareHost`).
  - `PlayerQoSReporter`: `15 s` `POST /playback/heartbeat` med `qos`-telemetri og `subtitleDelayMs`, håndtering av `vfsTelemetry`, `watchCompleted` (`>= 75%` + credits/post-credits via `PlaybackSessionPolicy`), `pendingCommand` (`reload_switched_stream`, `next_episode`, `subtitles_on`) og `nextEpisodePrewarm` (`AetherEngine.prewarm(..., byteBudget: 8 MB)` kun når `> 512 MB` RAM tilgjengelig og `canClientPrewarmBytes == true`).
  - `SeriesFlowOverlays` + `SeriesFlowPolicy` + `SeriesFlowEligibility`: kapittelfletting, `Hopp over intro`, `.postCredits` stinger-hopp (`>= 25 s`), `10 s` `Neste episode`-nedtelling, og `Start på nytt`.
  - Minnefrigjøring og to-fase nedrigging (`prepareForDismissal` + `teardownAndStop`): ved avspillingsstart/-montering kalles `ArtworkPipeline.shared.enterPlaybackMemoryMode(...)` for å frigi bilde-RAM før `.softwareHost`-dekoding; ved nedrigging i `teardownAndStop` kalles `ArtworkPipeline.shared.exitPlaybackMemoryMode()`, frakoblet `stopped`-heartbeat (`PlayerResolvePipeline`), `PlaybackStopReceipt` -> `0 ms` oppdatering av detalj og `nextUp`, og full `EngineLog.unregisterSecret` for alle strømme- og prewarm-tokener; ved `UIApplicationDidReceiveMemoryWarningNotification` utløses `TabMemoryEvictionPolicy` + `AetherEngine.discardPrewarmedSources()` / `discardRetainedSessionCache()`.

---

## 3. Sjekkliste for vurdering av streaming-funksjonalitet (`/api/tv/v2`)

- [ ] **Discovery & SWR-start:** `BonjourServerBrowser`, `GET /bootstrap`, `PATCH /device/profile` (`350 ms`), `DiskSWRStore` (`If-None-Match`/`304`) og `ServerFailoverPolicy` håndterer oppstart og midlertidige serverutfall uten blank skjerm.
- [ ] **`0-RTT` Pre-resolve & arkivsikkerhet:** `DetailPreResolveController` respekterer `0 ms`/`180 ms` debounce, hindrer A->B->A-kappløp via `taskToken`, overleverer `inflightPrepareTask`, rydder foreldreløse økter, og kaller **aldri** `AetherEngine.prewarm` når `canClientPrewarmBytes == false`.
- [ ] **WS/HTTP-oppslag & avbrudd:** `POST /playback/resolve` -> `WS /ws/playback/:resolveId` faller tilbake til `750 ms` HTTP-polling etter `1.5 s` watchdog, og tidlig avbrudd sender `cancelInflight: true`.
- [ ] **`AetherEngine`-invarianter:** Én delt `@MainActor AetherEngine`, `maximumSubtitleAdvanceSeconds = 0`, `maximumSubtitleDelaySeconds = 10`, korrekt `LoadOptions`-kartlegging mot `docs/aether-engine-api.md` og `DeviceMemoryProfile` (`.standard` vs. `.high2026`).
- [ ] **Teppe, QMS & lydøkt:** `PlaybackCurtainWatchdog` (`5 s`) + `180 ms` sort-pause hindrer HDMI-blink; `deactivatesAudioSessionOnStop = false`; `MenuDisplayMode` og utsatt `stop(resetDisplayCriteria: true)` holder AVR/TV stabil; AirPlay/BT nullstiller eARC-forsinkelse.
- [ ] **Spor, teksting & HDR10-fallback:** `OriginalLanguageTrackSelector` («Norsk tale» + Atmos/DTS:X), `SmartTrackRuleEngine`, sofa `search-and-attach` / `auto-align`, `PlaybackTrackIntent` ved `POST /playback/*/switch` og 1-trykks `Bytt til HDR10-baselag` virker deterministisk.
- [ ] **Scrubbing, restore & idle timer:** `RemoteScrubMath` (pause-only pan, ringklikk vs. hold, `scrubCommitToken`), `PlayerRestoreController` (inkl. full re-resolve fallback) og `isIdleTimerDisabled` oppfyller alle overganger.
- [ ] **QoS, serieflyt, minne & tokener:** `15 s` heartbeat (`qos`, `pendingCommand`, `watchCompleted >= 75%`), `8 MB` `nextEpisodePrewarm` (RAM- og `canClientPrewarmBytes`-sikret), to-fase nedrigging + `PlaybackStopReceipt`, `4 GB` minneadvarsel-opprydding, og 100 % symmetrisk `EngineLog.registerSecret`/`unregisterSecret`.
- [ ] **Kontrakts- & overflytrobusthet:** Alle `/api/tv/v2`-modeller (`PlaybackModels`, `PlaybackDrawerModels`, `ChapterModels`, `DetailModels`) tåler negative HTTP-konvolutter, manglende felt og ekstreme tallverdier uten dekodingsfeil eller krasj.

---

## 4. Verifiseringsmetoder for Dimensjon 4

| Nivå | Konkret kommando / fremgangsmåte | Forventet evidens |
| :--- | :--- | :--- |
| **Nivå 1 (Statisk)** | `./ops/bin/luna-check --local`; revisjon av `PlayerEngineConfigurator.swift` og `LunaApp.swift` mot `docs/aether-engine-api.md`; `rg "registerSecret\|unregisterSecret\|canClientPrewarmBytes\|maximumSubtitleAdvanceSeconds" Sources/` | Alle `LoadOptions`- og `AetherEngine`-signaturer stemmer; `canClientPrewarmBytes` beskytter byte-prewarm; symmetrisk token-redaksjon |
| **Nivå 2 (Linux kjerne)** | `./scripts/test-core.sh` | Grønn kjøring av `TvV2ClientAndPlaybackReceiptTests`, `DetailAndSourcePickerViewModelTests`, `PlaybackTrackIntentAndSyncTests`, `PlayerLanguageAndPreferenceTests`, `PlayerOverlayPolicyAndStingerTests`, `PlayerTimelinePolicyTests`, `RemoteScrubMathTests`, `SeriesFlowAndCurtainPolicyTests`, `NetworkCacheAndMemoryProfileTests`, `Etappe6ContractAcceptanceTests`, `Etappe6AdversarialHardeningTests`, `Etappe6NumericOverflowTests` |
| **Nivå 3 (tvOS Simulator & Vision)** | `build-tvos.yml` (`PlaybackResolveSocketTests`, `PlaybackRestoreAndAudioSessionTests`, `PlaybackTitleAndNowPlayingTests`, `PlayerExitBlinkRegressionTests`, `PlayerArtworkMemoryTests`, `PlayerOverlayAndCacheTests`, `PlayerQuickPanelAndSwitchTests`, `PlayerSeriesCurtainAndSubtitleTests`, `PlayerTimelineAndScrubUXTests`, `PausedScrubCommitTests`, `SmartTrackRuleEngineTests`, `ChapterClassificationTests`); `tvos-vision.yml` (alle 10 `player-*` + `detail-*` PNG-er) | Alle 12+ spiller-/strømme-XCTest-suiter grønne; visuell kontroll av OSD, hurtigpaneler, skip-intro, neste episode, scrub-boble og feiloverlegg |
| **Nivå 4 (Fysisk Apple TV 4K)** | Live streaming på `dv-fel-714` OLED & `hdr10-512` lyst rom mot `/api/tv/v2`-tjener | Målt `0-RTT` oppstart, blunkefri QMS/DV-veksling, P7 FEL -> HDR10 fallback, eARC-synk, taktil clickpad-scrubbing, episodebytte uten AVR-blink og stabilt RAM-fotavtrykk på 4 GB-enhet |
