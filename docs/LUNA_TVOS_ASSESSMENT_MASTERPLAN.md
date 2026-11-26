# Luna tvOS — Masterplan for helhetlig vurdering (`v3.0.0`)

> **Formål:** Strukturert vurderingsrammeverk, vurderingsområder, verifiseringsmetodikk og prioritert gjennomføringsplan for en grundig evaluering av `Luna` tvOS-klienten på tvers av **kodekvalitet**, **struktur og arkitektur**, **design (10-foot tvOS UI/UX)** og **funksjonalitet for best mulig streaming fra LunaCore (`/api/tv/v2`)**.  
> **Leveransetype:** Kun masterplan (selve evalueringen, poengsettingen og eventuelle kodeendringer gjennomføres i etterfølgende faser etter denne planen).

---

## 1. Systemgrense og autoritativ referansebase

### 1.1 Systemgrense
Vurderingen omfatter **utelukkende** `Luna` tvOS-klienten (`<repo-root>`, versjon `3.0.0`, `tvOS 26.0`, `Swift 6.2`, `AetherEngine 7.76.0`) og klientens observerbare kontrakt mot **LunaCore TV API (`/api/tv/v2`)** og lokal nettverksoppdagelse (`_lunacore._tcp`).

- **Inkludert:** Alle `.swift`-moduler under `Sources/` og `Packages/AetherBridge/`, testsuiter under `Tests/LunaCoreTests/` og `Tests/LunaTests/`, design tokens (`design/tokens.json`), lokal 1920×1080 Focus Sandbox (`preview/`), bygg- og portskript (`Package.swift`, `project.yml`, `Config/Info.plist`, `ops/bin/*`, `scripts/*`), samt CI-arbeidsflyter (`.github/workflows/*`).
- **Ekskludert:** Interne implementasjonsdetaljer i serverkomponenter eller eksterne plattformer, private nettverksadresser, interne vertsnavn, hemmeligheter eller lokale filsystemstier. Alt som dokumenteres i vurderingen skal overholde kravene til et offentlig GitHub-repo (`ops/bin/luna-check`).

### 1.2 Autoritativ referansebase i repoet

| Dokument / konfigurasjon | Rolle i vurderingen |
| :--- | :--- |
| `AGENTS.md` | Harde invarianter for offentlig repo, ATVLoadly-sideloading (`luna.v1.*`), `<= 800` linjer/fil, Linux-vs-tvOS-deling, `AetherEngine`-regler og 3-stegs verifikasjonssløyfe |
| `docs/architecture/CODEBASE_MODULE_MAP.md` | 1:1 modul-, endepunkt- og testoversikt (håndhevet toveis av `ops/bin/luna-check`) |
| `docs/LUNA_TVOS_LAMPELYS_REVIEW.md` | Kanonisk Lampelys 10-foot UI/UX-standard («Én app, én hånd», §2, §4, §6, §8 og F1–F8) |
| `docs/aether-engine-api.md` | Ekstraherte vertssignaturer for `AetherEngine` (`7.76.0`), `LoadOptions`, `PlaybackClock`, `EngineDiagnostics`, `EngineLog` og `EngineTLS` |
| `design/tokens.json` (`v2.0.0`) | Autoritativ kilde for farger, typografi (`>= 22 pt`), dimensjoner og fokusbevegelse (`ops/bin/luna-design-tokens`) |
| `Package.swift` & `project.yml` | Grenseflate mellom Linux-testbar `LunaCore` (`62` filer) og XcodeGen/tvOS-applikasjonen (`144` produksjons-/brofiler + `50` testfiler) |
| `Packages/AetherBridge/Package.swift` | Versjonslåsing (`exact: "7.76.0"`) og 5 SwiftPM-traits (`TrueHDObjectAudio`, `DTSXObjectAudio`, `DualLayerDolbyVision`, `DolbyVisionFelCurves`, `DolbyVisionStillReshaping`) |

---

## 2. Strukturert vurderingsrammeverk

### 2.1 De fire dimensjonene + tverrgående sikkerhet og sideloading

| Dimensjon | Vekt | Hovedfokus | Detaljvedlegg |
| :--- | ---: | :--- | :--- |
| **1. Kodekvalitet** | 20 % | Swift 6.2 samtidighet (`Mutex`, `@MainActor`, `Sendable`), feil-/kansellerings-/grensehåndtering, `luna.v1.*`-hygiene, `EngineLog.registerSecret`, testdekning og vedlikeholdbarhet | [`docs/assessment/01_KODEKVALITET.md`](assessment/01_KODEKVALITET.md) |
| **2. Struktur og arkitektur** | 20 % | `LunaCore` vs. Darwin-skall, én delt `AetherEngine` + 5-kontroller `PlayerViewModel`, observasjonsgranularitet (`0 Hz` hvile), `DeviceMemoryProfile`, Bonjour/failover/origin-tillit og bygg-/dok-styring | [`docs/assessment/02_ARKITEKTUR_OG_STRUKTUR.md`](assessment/02_ARKITEKTUR_OG_STRUKTUR.md) |
| **3. Design (10-foot tvOS UI/UX)** | 25 % | `design/tokens.json` v2.0.0-paritet, Lampelys «Én app, én hånd», `>= 22 pt` typografigulv, `90×60` overscan, fokus vs. Liquid Glass, Siri Remote-navigasjon og alle skjermflater | [`docs/assessment/03_DESIGN_TVOS_UI_UX.md`](assessment/03_DESIGN_TVOS_UI_UX.md) |
| **4. Streaming-funksjonalitet (`/api/tv/v2`)** | 35 % | Ende-til-ende streamingkjede fra discovery/SWR/`0-RTT` pre-resolve og WS/HTTP-oppslag til `LoadOptions`, HDMI QMS/teppe, lyd/tekst/HDR10-fallback, kildebytte, scrubbing, restore, QoS-heartbeat, serieflyt og `4 GB`-minnefrigjøring | [`docs/assessment/04_STREAMING_LUNACORE_V2.md`](assessment/04_STREAMING_LUNACORE_V2.md) |

> **Tverrgående port (sikkerhet & ATVLoadly-sideloading):** Vurderes integrert i Dimensjon 1 (kode-/nøkkelhygiene), Dimensjon 2 (origin-/TLS-grenser) og Dimensjon 4 (strømmetoken-livssyklus), og kan utløse uavhengig **No-Go** uavhengig av totalscore.

### 2.2 Modenhetsskala (1–5) per vurderingsområde

| Score | Modenhetsnivå | Operasjonell definisjon |
| :---: | :--- | :--- |
| **5** | **Produksjonsklar referanse** | Alle krav og grensetilfeller oppfylt, dokumentert og automatisert verifisert uten kjente regresjoner eller manuelle omgåelser |
| **4** | **Solid / mindre avvik** | Kjernefunksjonalitet og invarianter holder; kun mindre P2/P3-forbedringspunkter uten bruker- eller stabilitetsrisiko |
| **3** | **Akseptabel med mangler** | Fungerer i normalflyt, men mangler verifisering på viktige kanttilfeller (f.eks. `4 GB` minnepress, failover, fokusbro eller manglende testdekning) |
| **2** | **Sårbar / tydelige sprik** | Dokumenterte brudd på arkitektur-, design- eller streamingkontrakter (P1) som kan gi synlige feil på Apple TV |
| **1** | **Kritisk svikt** | P0-brudd: sikkerhetslekkasje, krasj, ødelagt sideload-oppgradering, permanent fokusfelle eller brutt streamingkjede |

### 2.3 Alvorlighetsgrader (P0–P3) for enkeltfunn

| Nivå | Klassifisering | Eksempler på utløsende funn | Krav til håndtering |
| :--- | :--- | :--- | :--- |
| **P0** | **Blokkerende (Release/Public No-Go)** | Privat IP/NAS-sti/hemlighet i repo, `Bundle.main.bundleIdentifier`-bruk, manglende `EngineLog.unregisterSecret` eller auth-lekkasje til ekstern CDN, uendelig svart skjerm/heng i avspiller, krasj eller `luna-check`-brudd | Må løses før sign-off |
| **P1** | **Høy (Funksjonell/UX-svekkelse)** | HDMI-blink mellom episoder, tapt lyd/tekst-intensjon ved kildebytte, død fokusfelle på Siri Remote, brudd på `90×60` overscan eller `22 pt` lesbarhet, dupliserte 4K-strømmer, manglende `4 GB`-minnereduksjon | Planlegges utbedret i neste prioriterte runde |
| **P2** | **Middels (Kvalitet/konsistens)** | Avvik fra Lampelys «Én app, én hånd» uten funksjonstap, manglende testdekning for ikke-kritisk UI-visning, overflødige `try?`, lokal `> 600` LOC-modul som nærmer seg 800-grensen | Føres i forbedringskø |
| **P3** | **Lav (Observasjon/finpuss)** | Mindre tekstjustering, kosmetisk spacing-avvik, mulighet for tydeligere telemetri eller refaktorering uten funksjonsrisiko | Valgfri utbedring |

### 2.4 Evidenskrav og Go / No-Go-kriterier
Et sjekkpunkt kan **ikke** markeres som bestått basert på antagelser. Hvert funn og hver delscore må støttes av minst én av følgende evidenskilder:
1. **Statisk / kodebevis:** Eksakt filsti, linjeintervall og symbolnavn (eller kommandoresultat fra `./ops/bin/luna-check`).
2. **Automatisert testbevis:** Navngitt suite i `Tests/LunaCoreTests/` (`./scripts/test-core.sh`) eller `Tests/LunaTests/` (`xcodebuild test`).
3. **Visuelt / simulatorbevis:** Generert `1920×1080` PNG fra `scripts/preview-capture.sh` (`?guides=1`) eller `tvos-vision.yml` (`--preview-screen`).
4. **Fysisk enhetsbevis:** Dokumentert observasjon på fysisk Apple TV 4K (`dv-fel-714` OLED / `hdr10-512` lyst rom) med Siri Remote og live `/api/tv/v2`-tjener.

**Go / No-Go-porter for endelig vurderingsgodkjenning:**
- **Ingen uløste P0-funn** på tvers av alle fire dimensjoner.
- **Vektet snittscore >= 4.0**, og **ingen enkelt dimensjon < 3.5**.
- **Nivå 1–3 verifisering** gjennomført grønt (`luna-check`, `test-core.sh`, `LunaTests`, `preview-capture.sh` og `tvos-vision.yml`).

---

## 3. Verifiseringsmetodikk i fire nivåer

Vurderingsplanen skiller eksplisitt mellom hva som kan verifiseres lokalt på Linux/Docker, i skybasert macOS/tvOS Simulator CI og på fysisk Apple TV 4K:

| Nivå | Miljø | Verktøy / kommandoer | Hva som verifiseres |
| :--- | :--- | :--- | :--- |
| **Nivå 1: Statisk & repo-hygiene** | Lokalt (Linux / macOS) | `./ops/bin/luna-check --local`, `./ops/bin/luna-check`, `./ops/bin/luna-design-tokens --check`, `rg`-søk | Tillatelser (`0755`/`0644`), `<= 800` LOC, sideload-forbud (`Bundle.main.bundleIdentifier`), forbudte iOS-API-er og kalde `*Material`-er, offentlig repo-hygiene, `CODEBASE_MODULE_MAP.md` 1:1-paritet, `Localizable.xcstrings`, token SHA-256 og `>= 22 pt` typografi |
| **Nivå 2: Linux kjerne-logikk** | Lokalt (Docker `swift:6.2`) | `./scripts/test-core.sh` (`swift test --parallel`) | Alle 21 suiter i `Tests/LunaCoreTests/` over 62 rene Swift-moduler (`LunaCore`): `/api/tv/v2`-klient, SWR-cache, failover, `PlaybackTrackIntent`, `RemoteScrubMath`, `SeriesFlowPolicy`, `PlaybackCurtainWatchdog`, `DeviceMemoryProfile`, overflyt og adversariale tester |
| **Nivå 3: Focus Sandbox, tvOS Simulator & IPA** | Lokalt (Playwright Docker) + GitHub Actions (`xcode-27`) | `./scripts/preview-capture.sh`, `tvos-vision.yml` (`--preview-screen` × 20 + `search --preview-focus select`), `build-tvos.yml` (`xcodegen generate`, `xcodebuild test`, `build-ipa`) | 9 HTML/CSS `1920×1080` renders med `?guides=1`, alle 28 suiter i `Tests/LunaTests/`, alle 21 ekte tvOS Simulator-skjermbilder, `Info.plist`/ATS/Bonjour/`Assets.car`-validering i `Luna-unsigned.ipa` |
| **Nivå 4: Fysisk Apple TV 4K (Live LAN)** | Apple TV 4K (4 GB & evt. nyere/high2026) + OLED / HDR10+ TV + AVR | ATVLoadly-sideloading av `Luna-unsigned.ipa`, Siri Remote, live `/api/tv/v2`-tjener | Reell Bonjour mDNS-oppdagelse, Device Flow-paring, HDMI QMS/Dynamic Range-veksling uten blink, DV Profile 7 FEL/AV1-avspilling, eARC/AirPlay-lydsynk, taktil clickpad-scrubbing, HDR-undertekstkomfort og minnepress over lengre økter |

---

## 4. Oversikt over vurderingsdimensjoner og toppsjekkliste

### 4.1 Dimensjon 1 — Kodekvalitet (`docs/assessment/01_KODEKVALITET.md`)
Dekker `144` produksjons-/brofiler (`36 615` LOC) og `50` testfiler (`16 966` LOC):
- [ ] **K1.1 Samtidighet & minnesikkerhet (Swift 6.2):** Verifisere `Mutex`, `actor`-isolasjon (`ArtworkPipeline`, `DiskSWRStorageActor`, `NativeAudioSessionActivator`), strukturert `Task`-kansellering og syklusfri `[weak host]`/`[weak self]` i de 5 spillerkontrollerne.
- [ ] **K1.2 Feilhåndtering, kansellering & numeriske grenser:** Revidere `LunaCoreError`-mapping, stille `try?`-uttrykk og `isFinite`/`Int(exactly:)`-beskyttelse.
- [ ] **K1.3 Sideload- & hemmeligholdshygiene:** Bekrefte fast `"luna.v1.*"`-lagring, Keychain `-34018`-fallback og symmetrisk `EngineLog.registerSecret`/`unregisterSecret` for både enhetstoken og strømmetokener.
- [ ] **K1.4 Testdekning & testdobbel-troverdighet:** Kartlegge moduler med `—` i `CODEBASE_MODULE_MAP.md` og kontrollere at `PlayerTestDoubles` og `PreviewMockURLProtocol` speiler reell `AetherEngine 7.76.0`- og `/api/tv/v2`-oppførsel.
- [ ] **K1.5 Vedlikeholdbarhet & lokalisering:** Kontrollere filstørrelsesmarginer opp mot `800` LOC-grensen og `Localizable.xcstrings` (`nb`).

### 4.2 Dimensjon 2 — Struktur og arkitektur (`docs/assessment/02_ARKITEKTUR_OG_STRUKTUR.md`)
Dekker moduldeling, avhengighetsretning, tilstandseierskap og ressursprofiler:
- [ ] **A2.1 Ren kjerne vs. Darwin-skall:** Vurdere `Package.swift`-grensen (`62` `LunaCore`-filer vs. `42` utelatelser) og protokollkontraktene (`TabSessionContracts`, `PlayerTransportControlling`, `DetailStreamPrewarming`, `PlaybackResolveSocketProviding`).
- [ ] **A2.2 Spiller- og tilstandseierskap:** Kontrollere én felles `@MainActor AetherEngine`, `AppSessionStore`-vifteutbredelse, 5-kontroller-dekomponering i `PlayerViewModel` og streng blad-observasjon (`0 Hz` i hvile).
- [ ] **A2.3 Caching, koalescering & minneprofiler:** Evaluere `DeviceMemoryProfile` (`.standard` vs. `.high2026`), `InflightTaskCoalescer` per-venter-kansellering, `DiskSWRStore`, `ArtworkPipeline` og `4 GB` minneadvarselsflyt.
- [ ] **A2.4 Nettverk, discovery & tillitsgrenser:** Revidere `BonjourServerBrowser` dual-stack IPv4/IPv6, `ServerFailoverPolicy`, `isSameOrigin` (`:8090`/`:8920`) og scoped LAN-TLS (`LanURLSessionDelegate` + `EngineTLS`).
- [ ] **A2.5 Bygg-, trait- og dokumentstyring:** Kontrollere `project.yml` -> XcodeGen, `Packages/AetherBridge` (`7.76.0` + 5 traits) og 1:1-paritet i `CODEBASE_MODULE_MAP.md` + `design/tokens.json`.

### 4.3 Dimensjon 3 — Design / 10-foot tvOS UI/UX (`docs/assessment/03_DESIGN_TVOS_UI_UX.md`)
Dekker visuell enhet, 3-meters lesbarhet, fokusarkitektur og F1–F8-etterlevelse på `v3.0.0`:
- [ ] **D3.1 Tokens & typografi:** Verifisere `design/tokens.json` v2.0.0 -> `LunaTokens.swift` / `preview/tokens.css`, `LunaTheme.Font` (9 tekstroller + ikonroller, alt `>= 22 pt`), og fravær av rå `.font(...)`, `.uppercased()`, `.tracking(` og kalde `*Material`.
- [ ] **D3.2 Lampelys «Én app, én hånd»:** Revidere alle 8 grunnregler (spesielt *Gull betyr fokus*, *Maks én ramme*, *Maks én badge*, romnavn kun i toppbar/romvelger, fast tekst ved fokus).
- [ ] **D3.3 Overscan, rutenett & vertikal rytme:** Kontrollere `90×60` safe-area, 6-kolonners `260 pt` rutenett (`1740 pt`), `162 pt` `contentTop`, `60 pt` `subpageTop` og `1.05x`-skalering uten klipping.
- [ ] **D3.4 Siri Remote & fokusbroer:** Teste `TopBarFocusBridge` (`180 ms`), `MountedEntryCardTracker` på `x = 90`, `.focusSection()`/`.focusScope()`, `TouchCaptureUIView` og 6-stegs Meny-stige i spiller.
- [ ] **D3.5 Skjerm-for-skjerm & visuell verifisering:** Inspisere alle 10 skjermområder via `scripts/preview-capture.sh` (`?guides=1`) og alle 21 renders i `tvos-vision.yml`.

### 4.4 Dimensjon 4 — Funksjonalitet for best mulig streaming fra LunaCore (`docs/assessment/04_STREAMING_LUNACORE_V2.md`)
Dekker hele verdikjeden for rask, feilfri og bilde-/lydtro streaming over `/api/tv/v2` og `AetherEngine 7.76.0`:
- [ ] **S4.1 Oppstart, SWR & `0-RTT` pre-resolve:** Verifisere `GET /bootstrap`, betinget `If-None-Match`/`304`, `DetailPreResolveController` (`0 ms`/`180 ms`), `canClientPrewarmBytes`-sperre for arkivdisker og `performWarmDirectMount`.
- [ ] **S4.2 Oppslag & `AetherEngine`-konfigurasjon:** Revidere `POST /playback/resolve` + `WS /ws/playback/:resolveId` (`1.5 s` watchdog -> `750 ms` polling), `cancelInflightPlayback`, `LoadOptions` (`maximumSubtitleAdvanceSeconds = 0`, DV P7 FEL, AV1, MetalFX, `DeviceMemoryProfile`).
- [ ] **S4.3 Teppe, HDMI QMS/Range & lydøkt:** Kontrollere `PlaybackCurtainWatchdog` (`5 s`) + `180 ms` sort-pause, `MenuDisplayMode` (`QMS` + `dvcC`), `deactivatesAudioSessionOnStop = false` og AirPlay/BT-lip-sync-nullstilling.
- [ ] **S4.4 Sporvalg, undertekster, HDR10-fallback & kildebytte:** Verifisere `OriginalLanguageTrackSelector` / «Norsk tale», `SmartTrackRuleEngine`, sofa `search-and-attach` / `auto-align`, `PlaybackTrackIntent` ved `POST /playback/*/switch` og 1-trykks `Bytt til HDR10-baselag`.
- [ ] **S4.5 Scrubbing, restore, QoS, serieflyt & nedrigging:** Revidere `RemoteScrubMath`, `PlayerRestoreController`, `isIdleTimerDisabled`, `15 s` `heartbeat` + `pendingCommand`, `SeriesFlowOverlays` + `8 MB` `nextEpisodePrewarm`, `PlaybackStopReceipt`, `4 GB` minnetømming og strømmetoken-avregistrering.

---

## 5. Prioritert gjennomføringsplan (Fase 0–5)

| Fase | Navn | Inndata | Ansvarlig rolle | Hovedaktivitet & verifisering | Utgangskriterium (Exit Gate) | Avhengigheter / parallellitet |
| :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **Fase 0** | **Grunnlinje & miljølås** | `AGENTS.md`, `VERSION`, `CODEBASE_MODULE_MAP.md` | Evalueringsleder / QA | Bekrefte ren arbeidsgren, ta baseline med `./ops/bin/luna-check` og `./scripts/test-core.sh`, låse eval-matrise | Grønn `luna-check` og `test-core.sh` på uendret kodebase; miljø klar for nivå 1–3 | Ingen (startpunkt) |
| **Fase 1** | **Kodekvalitet & arkitektur** | `01_KODEKVALITET.md`, `02_ARKITEKTUR_OG_STRUKTUR.md`, `Package.swift`, `project.yml` | Senior Swift-arkitekt | Gjennomgå samtidighet, `try?`/grenser, sideload-lagring, `EngineLog`, `LunaCore`-grense, `AetherEngine`-eierskap, caching og testgap | Utfylte sjekklister for Dimensjon 1 & 2, rangert funnliste (P0–P3) med fil:linje-bevis | Avhenger av Fase 0; kan kjøres **parallelt** med Fase 2 (statisk del) og Fase 3 (sandbox) |
| **Fase 2** | **Streaming-kjerne (`/api/tv/v2` + `AetherEngine`)** | `04_STREAMING_LUNACORE_V2.md`, `docs/aether-engine-api.md`, `Sources/Core/{Networking,Playback}`, `Sources/Features/{Detail,Player}` | Streaming-/avspillings-spesialist | Spore hele kjeden: pre-resolve -> WS/HTTP resolve -> `LoadOptions` -> curtain/QMS -> spor/tekst/HDR10 -> `switch` -> scrub/restore/heartbeat/teardown | Verifisert ende-til-ende streamingmatrise, alle `/api/tv/v2`-endepunkter og `AetherEngine`-invarianter dokumentert | Avhenger av Fase 0; overlapper naturlig med Fase 1 |
| **Fase 3** | **Design, fokus & 10-foot UI/UX** | `03_DESIGN_TVOS_UI_UX.md`, `LUNA_TVOS_LAMPELYS_REVIEW.md`, `design/tokens.json`, `preview/` | tvOS UI/UX-ansvarlig | Kjøre `luna-design-tokens --check`, `scripts/preview-capture.sh` (`?guides=1`), interaktiv piltast-gjennomgang og full F1–F8- og skjerm-audit | Alle 9 sandbox-PNG-er vurdert; avvik mot Lampelys §2/§6/§8 loggført med P0–P3 | Avhenger av Fase 0; parallell med Fase 1 & 2 |
| **Fase 4** | **CI Simulator Vision & full `LunaTests`** | `.github/workflows/{tvos-vision,build-tvos}.yml`, gren `agent/*` | CI / tvOS QA | Kjøre `tvos-vision.yml` og `build-tvos.yml` i GitHub Actions, hente `tvos-screenshots` (21 PNG-er), inspisere alle `LunaTests`-resultater og IPA-sjekk | Alle 28 `LunaTests`-suiter grønne; 21 ekte Apple TV 4K Simulator-renders inspisert; unsigned IPA validert | Avhenger av Fase 1–3 (for samlet sjekkliste for simulatorvisninger) |
| **Fase 5** | **Fysisk Apple TV 4K & sluttrapport** | `Luna-unsigned.ipa`, ATVLoadly, OLED (`dv-fel-714`) & lyst rom (`hdr10-512`), live LunaCore | Ekte enhetstester + Evalueringsleder | Gjennomføre Nivå 4-testplan (mDNS, pairing, QMS, P7 FEL, eARC, clickpad-scrubbing, langtidsspilling på 4 GB), sammenstille vektet totalscore og tiltaksplan | Signert vurderingsrapport med score (1–5) per dimensjon, P0–P3-backlog og Go/No-Go-beslutning | Avhenger av Fase 1–4 |

---

## 6. Retningslinjer for gjennomføring av vurderingen

1. **Ingen stille omskriving:** Under vurderingsløpet skal funn dokumenteres med eksakte observasjoner (filsti, linjenummer, kommandoresultat eller skjermbilde) før tiltak foreslås.
2. **Skille mellom Linux-bekreftet og Apple-TV-bekreftet:** Oppgi alltid hvilket verifikasjonsnivå (Nivå 1–4) som støtter hvert punkt, slik at antatt oppførsel i Darwin-only kode (`AetherEngine`, `AVDisplayManager`, `NWBrowser`, `VideoToolbox`) ikke forveksles med Linux-verifiserte tester.
3. **Respekt for offentlig repo:** All rapportering, eventuelle skjermbilder og feillogger må være renset for private adresser, brukerdata og tokener før de lagres i repoet.
