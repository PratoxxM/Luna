# Luna tvOS: Lampelys design-review og komponentstandard (10-foot UI)

> **Status:** Godkjent for implementering (Q1–Q7 = Ja, kun 4K `@2x` 3840×2160 px, hvilekant `0,5 pt` på piller for kontrast i dagslys/urolige bakgrunner, og diskret sett-status i detaljens metadatalinje).
> **Dato:** 2026-11-21 · **Gjelder:** Luna `v2.9.0` (`main@a909588`) · **Rolle:** Principal tvOS & UI/UX (Lampelys)
> **Søsterdokument:** `LunaCore/docs/architecture/LAMPELYS_UX_UNIFICATION_PLAN.md` (iPhone-PWA, eget repo). Samme prinsipper: maks én ramme, én variant per komponenttype, maks én badge, ingen forklarende undertitler.

---

## 0. Metode og forbehold

| Punkt | Verdi |
| --- | --- |
| Grunnlag | Lest kode: `Sources/DesignSystem/**`, alle visninger under `Sources/App/` og `Sources/Features/**`, `design/tokens.json`, `ops/bin/luna-check`, låste verdier i `Tests/LunaTests/*` |
| Skjermbilder | Repoet har ingen simulatorrender (`.ci-screenshots/` finnes ikke), og ingen ble generert (ingen bygg, i tråd med oppdraget). Alle mål er hentet direkte fra koden i punkt (pt) på 1920×1080-lerretet (4K = @2x) |
| Målplattform | LG OLED 4K (Dolby Vision, mørkt rom, `cinema`-atmosfære) og Samsung The Frame (HDR10+, lyst rom med matt panel, `living`-atmosfære), 3 m avstand, Siri Remote |
| Notasjon | **Behold** = uendret, **Endre** = konkret ny verdi, **Stryk** = fjernes uten tap av funksjon. `Fil.swift#L10-L20` peker til gjeldende linjer på `a909588` |

---

## 1. Viktigste sprik og støyfunn i dag

Grunnmuren er god: varme tokens (`#0A0908`-lerret, linen-tekst, bronse-aksent), 90 pt sidemarg, 6-kolonners rutenett som går nøyaktig opp (6 × 260 + 5 × 36 = 1740 = 1920 − 2 × 90), fokusbroer til toppbaren og en forutsigbar Meny-stige i spilleren. Uroen kommer, som på iPhone, fra **dekorasjon og drift rundt komponentene**, ikke fra selve skalaen.

### 1.1 Fokus spriker: sju skalaer og to betydninger av gull

| Komponent | Fil | Fokusskala | Kant ved fokus | Glød |
| --- | --- | ---: | --- | --- |
| Plakat | `PosterCardView.swift#L145` | 1,04 | 1,5 pt gull 70 % | rom-lampe 30/12 |
| Backdrop | `BackdropCardView.swift#L147` | 1,03 | 1,5 pt gull 70 % | rom-lampe 30/12 |
| Episode | `EpisodeCardView.swift#L87` | 1,03 | 1,5 pt gull 70 % | rom-lampe 30/12 |
| «Se alle»-kort | `ShelfRowView.swift#L286` | 1,03 (`.secondaryPill`) | 1,5 pt gull 70 % | rom-lampe 30/12 |
| Toppbar-fane | `LunaTopBarView.swift#L333-L339` | 1,04 | 1,5 pt gull 70 % | **24/10** (egen verdi) |
| Pille-knapp | `LunaPillButton.swift#L195-L197` | 1,03 / 1,04 | 1,5 pt gull 70 % | rom-lampe 30/12 |
| «Spill av» | `DetailHeroHeaderView.swift#L331` | 1,04 | svak toppkant 26 % | rom-lampe 30/12 |
| ⋯-sirkel | `DetailHeroHeaderView.swift#L374` | **1,05** | 1,5 pt gull 70 % | rom-lampe 30/12 |
| Sesongflis | `DetailSeasonsSectionView.swift#L306-L312` | 1,03 | 1,5 pt gull 70 % | **70 % · 20/6** |
| Kilde-/panelrad | `SourceCandidateRowView.swift#L76-L82`, `PlayerQuickPanelView.swift#L669` | **1,015** | 1,5 pt gull 70 % | **70 % · 20/6** |

- `LunaFocusStyle.scaleEffect(for: .card)` returner **1,0** (`LunaFocusStyle.swift#L28-L38`, låst i `Tests/LunaTests/DesignTokensAndCopyTests.swift#L70-L73`), mens kortene selv legger på 1,03–1,04. Tokenet og virkeligheten er koblet fra hverandre.
- **Gull betyr to ting.** «Spill av», «Prøv igjen» og «Spill nå» er gullfylte i hvile, mens en *fokusert* sekundærknapp bare får mørk flate med 1,5 pt gullkant. Når fokus står på «Kilde», er den ufokuserte «Spill av» fortsatt det sterkeste elementet på skjermen. På The Frame i dagslys forsvinner en 1,5 pt-kant med 70 % dekning mot varm kunst, og romgløden (22 % styrke) er nesten usynlig.

### 1.2 Fem måter å si «valgt»

| Markør | Brukes i |
| --- | --- |
| Tekstglyf «✓» i gull | `SourceCandidateRowView.swift#L49-L54`, `DetailSeasonsSectionView.swift#L278-L282`, `PlayerQuickPanelView.swift#L642` |
| `checkmark.circle.fill` i grønt + teksten «Aktiv» | `SettingsComponents.swift#L123-L136` |
| Gull venstremarkør + gullkant + `Accent.soft`-fyll | `SettingsView.swift#L228-L254` |
| `Accent.soft`-fyll + aksentkant | `LunaPillButton.swift#L148-L150` og `#L324-L326`, `DetailSeasonsSectionView.swift#L290-L303` |
| «På»/«Av» i grønn pille med kant | `SettingsComponents.swift#L187-L205` |

### 1.3 Boks-i-boks

- **Innstillinger:** `SettingsSectionPanel` er en r24-flate med 24 pt innmarg (`SettingsComponents.swift#L3-L24`). Inne i den har hver rad sin egen r12-flate (`#L142-L150`, `#L210-L214`), og bryterraden har i tillegg en innrammet «På/Av»-pille. Det gir **tre nivåer**.
- **Ark:** «Mer», «Velg kilde» og «Slett» tegner et r24-panel, og hver rad inne i det har egen `surfaceRaised`-flate med r18 (`DetailMoreAndOverviewSheets.swift#L183-L186`, `SourceCandidateRowView.swift#L59-L75`, `DetailDeleteSheetView.swift#L67-L71`).
- **Hurtigpanel i spilleren:** glassflate, 1 pt kant, toppkant og svart skygge på samme r24-flate (`PlayerQuickPanelView.swift#L177-L195`), med rader som også har egen flate og kant.

### 1.4 Typografi: 45 roller for 8 behov

`LunaTheme.Font.allFixedPointSizes` har **45 roller** (`LunaThemeTypography.swift#L9-L55`). Det er tre serif-titler (52, 56 og 72 pt), tre korttitler (29, 30 og 30), to undertitler (24 og 25) og to sidetitler (42 bold og 34 semibold). Korttittelen er 29 pt på plakater, men 30 pt på backdrop og episoder.

- Detaljtittelen er **72 pt bold serif** (`DetailHeroHeaderView.swift#L44`), mens oversiktsarket bruker 52 pt (`DetailMoreAndOverviewSheets.swift#L255`) og paringen 56 pt.
- Versal-kicker med sperring på detaljsiden (`DetailHeroHeaderView.swift#L34-L40`) og versal-badges med 0,8 tracking (`#L59-L61`). Dette er de samme versalene som fjernes på iPhone.

### 1.5 Sidetopper og vertikal rytme er ulike på hver fane

| Fane | Sidetittel | Avstand mellom blokker | Fil |
| --- | --- | ---: | --- |
| Hjem | ingen | 28 | `HomeView.swift#L110` |
| Filmer / Serier | «Filmer» 42 bold | 26 | `CatalogBrowseView.swift#L134-L142` |
| Bibliotek | «Bibliotek» 42 bold | 22 | `LibraryHubView.swift#L58-L66` |
| Søk | «Søk» 42 bold | 22 | `SearchView.swift#L58-L66` |
| Innstillinger | ingen | 24 | `SettingsView.swift#L85` |
| Detalj | (hero) | 20 | `MediaDetailView.swift#L49` |

Toppbaren viser allerede aktiv fane med understrek. Sidetittelen på tre av seks rotfaner gjentar den derfor, og innholdet starter på ulik `y` fra fane til fane.

### 1.6 Badges og statusmerker brukes som metadata

- **Detaljsiden** viser opptil fire innrammede versal-badges (r6, en sjette radius, `DetailHeroHeaderView.swift#L56-L72`). I tillegg kommer en egen tilgjengelighetslinje med glødende prikk og «På NVMe · klar for Stua» (`#L103-L114`) og en egen «Kommer:»-linje (`#L93-L102`). Det blir tre rader med metadata før handlingene.
- **Kort:** opprinnelses- og dato-piller med både glassfyll og 1 pt kant (`BackdropCardView.swift#L177-L213`, `EpisodeCardView.swift#L50-L58`). Lagringsskiven ligger oppå kunsten (`PosterCardView.swift#L115-L118`). «Fortsett»-undertittelen får påhengt «· På NVMe» (`BackdropCardView.swift#L220-L228`).
- **Spiller-OSD:** kvalitetspille med kant (`PlayerBottomBarView.swift#L129-L138`) og passive badges «•» og «MetalFX» i hurtigstripen (`#L213-L222`).
- **Kilderad:** flagg-emoji-badge «🇳🇴 Norsk» med kant (`SourceCandidateRowView.swift#L38-L47`).

### 1.7 Knapper: tre former på én rad

Handlingsraden på detaljsiden består av et **r16-rektangel** («Spill av», `DetailHeroHeaderView.swift#L318-L331`), **kapsler** (Kilde, Huskeliste, Sett) og en **60 pt sirkel** (⋯, `#L352`). Toppbarens ikonknapper er 56 pt. Destruktive og varslende piller har farget kant også i hvile (`LunaPillButton.swift#L139-L144`), så «Tøm logg» og «Tøm hurtigbuffer» roper selv uten fokus.

### 1.8 Romnavnet gjentas overalt

Romnavnet står i toppbarens emblem (`LunaTopBarView.swift#L196-L212`, som er riktig sted). Det gjentas likevel i «klar for Stua» (detalj), «Tittel · Stua» og «Anbefalt for Stua» (Mer-arket), «· Tilpasset Stua» (kildevelger og kildepanel), «Teknisk oversikt · Stua» (NerdHUD), og to ganger som «Aktivt rom» i Innstillinger (`SettingsComfortSectionView.swift#L12-L15`, `SettingsServerDiagnosticsSectionView.swift#L29-L32`).

### 1.9 Ark og paneler har hver sin størrelse

| Flate | Bredde | Innmarg | Fil |
| --- | ---: | ---: | --- |
| Mer | 880 | 52 | `DetailMoreAndOverviewSheets.swift#L104-L105` |
| Handling | 980 | 52 | `DetailMoreAndOverviewSheets.swift#L282-L283` |
| Slett | 920 | 44 | `DetailDeleteSheetView.swift#L153-L154` |
| Velg kilde | 1020 | 56 | `SourcePickerSheetView.swift#L377-L387` |
| Velg sesong | 1480 | 48 | `DetailSeasonsSectionView.swift#L234-L235` |
| Feil i spiller | 860 | – | `PlayerFatalErrorOverlayView.swift#L87` |
| Hurtigpanel | 580 / 600 / 600 / 670 / 780 | 26 × 22 | `PlayerQuickPanelView.swift#L65-L73` |

### 1.10 Tilstander (lasting, tom, feil) har seks dialekter

- **Lastetekst** bruker fire ulike størrelser: `cardTitle` på Hjem og Katalog, `subtitle` i Bibliotek, `body` i Søk og episoder.
- **Feil** vises som **rød brødtekst** (`LunaTheme.danger`) på Hjem, Katalog, Bibliotek, Søk og Detalj. Lang rød tekst er tung å lese på 3 m, og den virker unødig alarmerende.
- **Tomme tilstander** er sentrert med maskot på 80 eller 64 pt og et forklarende avsnitt (`LibrarySidebarAndEmptyViews.swift#L136-L169`, `SearchView.swift#L180-L196`), mens resten av appen er venstrejustert fra x = 90.
- **Midlertidige feilbannere** legger seg oppå første hylletittel (`HomeView.swift#L213-L220` og tilsvarende i tre andre visninger). I spilleren ligger tre ulike statuspiller på to forskjellige plasser (`PlayerBottomBarView.swift#L72-L87` øverst til venstre, `PlayerContainerView.swift#L350-L394` øverst i midten).

### 1.11 Fokus som hopper eller klipper

- Serieprompten endrer knappeteksten ved fokus, fra «▲ Hopp over intro» til «Hopp over intro» og fra «▲ Start på nytt» til «Start på nytt» (`SeriesFlowOverlays.swift#L330-L331`, `#L422-L423`). Pillen endrer dermed bredde i fokusøyeblikket.
- «Les mer» er et eget fokusstopp mellom metadata og handlingsraden (`DetailHeroHeaderView.swift#L84-L88`). Pil opp fra «Spill av» lander derfor på en liten chip i stedet for å bli stående eller gå til toppen.
- Hvis tom-tilstanden i Bibliotek mangler handling, får den `.focused(...)` på en ikke-fokuserbar `VStack` (`LibraryHubView.swift#L249-L251`, `#L320-L331`). Pil ned fra fanepillene havner da ingen steder.
- Plakattitler er skjult i hvile på Hjem (`PosterCardView.swift#L164`), men synlige i alle rutenett (`showRestingTitle: true`). Det er to kortspråk for samme komponent. Valget for Hjem er riktig (rolig rad), men regelen er ikke dokumentert.

### 1.12 Maskot og varme toner

Maskoten (månesigd) brukes stort sett riktig: gull i toppbaren og på paringen, dempet i tomme tilstander. Størrelsen varierer likevel (34/62/64/80 pt). Gullfarge brukes også for en øyenbryn-tekst («Neste episode · S2 E4», `SeriesFlowOverlays.swift#L356-L359`), for ikonet i panelhodet (`PlayerQuickPanelView.swift#L207-L209`) og for valgt kategori-ikon i Innstillinger. Det svekker gull som fokussignal.

---

## 2. Kanonisk Lampelys tvOS-komponentstandard

### 2.1 Grunnregler («Én app, én hånd»)

1. **Gull betyr fokus.** Bronsefyll (`playFocusGradient`) er forbeholdt kontrollen som har Siri Remote-fokus. Primærhandlingen skiller seg ut i hvile med gullikon, semibold-etikett og plassering først, ikke med gullfyll (se Q1).
2. **Maks én ramme.** En synlig flate ligger maks ett nivå under siden: side › gruppe/ark. Inne i en gruppe tegnes ingen nye flater eller kanter. Unntakene er kunst (plakat/still), fokus og et tekstfelt.
3. **Maks én badge per kort eller rad**, og bare for unntak («I kveld», «Fra iPhone», «Neste», dato for kommende). Tekniske formater og lagring er tekst, ikke piller.
4. **Ingen forklarende undertitler.** Tittelen skal bære meningen. Undertekst er bare lov når den bærer **data** (verdi, utstyr, språk/format), på én linje og med maks ≈ 60 tegn.
5. **Romnavnet vises bare i toppbaren** og i romvelgeren i Innstillinger.
6. **Sidetittel bare når toppbaren er skjult** (undersider som «Drama · Filmer» og «Se alle»). Rotfanene har ingen sidetittel.
7. **Inngang på x = 90.** Pil ned fra toppbaren lander alltid på den første kontrollen ved venstre sidemarg (dette er allerede invarianten i `LunaTopBarView.swift#L76-L79`). Tomme og feilende tilstander er venstrejusterte, slik at inngangen alltid treffer noe.
8. **Tekst endrer seg aldri ved fokus.** Etikett, bredde og linjebryting er like i hvile og ved fokus. Fokus endrer bare farge, fyll, skala og glød.

### 2.2 Rutenett, safe area og rytme (1920 × 1080 pt, 4K = @2x)

| Token (`platform.tvos.dimensions`) | Verdi | Merknad |
| --- | ---: | --- |
| `gutter` | 90 | Behold. Action-safe horisontalt |
| `safeTop` / `safeBottom` | 60 / 60 | Ny. Toppbaren flyttes fra `top: 46` til 60 (`LunaTopBarView.swift#L70`) |
| `contentTop` | 162 | Behold verdien, men flytt den fra `LunaTopBarView.contentTopPadding` til token (60 + 56 + 14 + 32) |
| `subpageTop` | 60 | Ny. Erstatter de hardkodede `60` for undersider |
| `sectionGap` | 32 | Ny. Avstand mellom hyller og seksjoner (erstatter 20/22/24/26/28) |
| `headerGap` | 16 | Ny. Seksjonshode → innhold (erstatter 14/18) |
| `blockGap` | 24 | Ny. Filterstripe → rutenett, felt → resultater |
| `gridRowGap` | 32 | Ny. Erstatter 26 i alle `LazyVGrid` |
| `gridPosterW × H` | 260 × 390 | Behold. 6 kolonner, `gridCardGap` 36 |
| `posterW × H` | 280 × 420 | Behold. Hylle, `cardGap` 40, sjette plakat stikker frem |
| `backdropW × H` | 520 × 293 | Behold |
| `episodeW × H` | 420 × 236 | Ny som token (i dag `private static` i `EpisodeCardView.swift#L4-L5`) |
| `controlH` / `compactControlH` | 56 / 48 | Ny. Høyde for `.regular` og `.compact` |
| `iconButton` | 56 | Ny. ⋯-sirkel (i dag 60) og toppbar-ikon (56) |
| `listRowPadX` / `listRowPadY` / `listRowMinH` | 24 / 16 / 72 | Ny |
| `sheetPadding` | 48 | Ny. Alle ark |
| `sheetNarrowW` / `sheetWideW` | 880 / 1240 | Ny. Erstatter fem bredder |
| `quickPanelW` / `quickPanelWideW` | 640 / 820 | Ny. Tekst/Lyd/Bilde/Kapitler / Kilde |

Fokusskala 1,05 på et 260 pt-kort gir 6,5 pt vekst til hver side. Det får plass i 36 pt mellomrom og i 90 pt sidemarg (venstrekant x = 83,5 > 60), så ingenting klipper. Alle horisontale rader beholder `.scrollClipDisabled()`.

### 2.3 Typografi: 9 tekstroller

| Rolle | Størrelse / vekt | Design | Brukes til | Erstatter |
| --- | --- | --- | --- | --- |
| `heroSerif` | **64** semibold | serif | Innholdstittel i detalj-hero, ordmerket «Luna» på paring | `detailHeroSerif` 72, `heroDisplay` 56, `heroSerif` 52 |
| `titleSerif` | 46 semibold | serif | Tittel i avspillingsteppet og i Handling-arket | `curtainTitle` 46 |
| `pageTitle` | **40** semibold | sans | Sidetittel på undersider, arktitler, overskrift i tom tilstand | `pageTitle` 42 bold |
| `sectionTitle` | 34 semibold | sans | Hyllehoder, seksjoner i Innstillinger, tittel i spiller-OSD | `settingsHeading` |
| `cardTitle` | **29** semibold | sans | Kort-, rad- og panelradtitler | `posterTitle`, `backdropTitle`, `cardTitle` 30, `settingsSectionTitle` |
| `body` | 29 regular | sans | Handling og lengre tekst | `settingsRowTitle` (blir `cardTitle` medium) |
| `subtitle` | 25 medium | sans | Metadata, radundertekst, tider | `posterSubtitle` 24, `backdropSubtitle`, `settingsSubLabel` 24, `settingsMeta*` |
| `caption` | 23 medium | sans | Tellere, «Ferdig kl.», hint | `settingsRowSubtitle`, `settingsStatusTag`, `settingsToggleState` |
| `badge` | 22 semibold | sans | Kunst-badge, panel-badge | `tierBadge`, `cardMicroLabel`, `compactPillBadge` |

- Ikonroller beholdes separat (`tabIcon` 24, `pillIcon` 22, `primaryPlayIcon` 24, `largeStatusIcon` 52, `pairingCode` 88). Pilleetiketter (`pillLabel` 25, `compactPillLabel` 23) beholdes.
- **Forbudt:** `.uppercased()` og `.tracking(...)` på synlig UI-tekst. Tall bruker `.monospacedDigit()`.
- Serif brukes **bare** til navn på innhold (film, serie, episode) og ordmerket. All chrome er sans.
- Migrering: de gamle navnene blir `@available(*, deprecated)`-aliaser til de nye i én release og fjernes deretter. `allFixedPointSizes` oppdateres (testen i `DesignTokensAndCopyTests.swift#L39-L40` sjekker fortsatt gulvet på 22 pt).

### 2.4 Flater og kanter

| Nivå | Token | Radius | Kant | Bruk |
| --- | --- | ---: | --- | --- |
| 0 Lerret | `Surface.canvas` + `AmbientBackdropView` | – | – | Alle sider |
| 1 Gruppe | `Surface.lv1` | 18 (`card`) | Bare toppkant `Edge.top1` | Listegrupper i Innstillinger, ark og paneler |
| 1 Ark | `Surface.sheet` | 24 (`panel`) | Bare toppkant `Edge.top3` → `top1` | Ark (Mer, Kilde, Slett, Sesong, Handling, Feil) |
| 1 Spilleroverlegg | `Surface.glass` | 24 / pill | Bare toppkant + `pureBlack` 0,6-skygge (over video) | Hurtigpanel, neste episode, statuspille |
| Kunst | – | 16 plakat / 18 landskap | Ingen kant i hvile | Kort |

- **Stryk** `strokeBorder(warmBorderStrong / warmBorderSubtle)` på alle flater i hvile: piller, badges, paneler og rader. Bare fokus, primærknappens hårstrek og tekstfeltet kan ha kant.
- Skillelinjer i grupper: 1 pt `Edge.divider`, innrykket med `listRowPadX`.
- Radiusene er nå 12/16/18/24/pill. **Stryk** r6 på detaljbadges og r16 på «Spill av» og radene i kilde- og hurtigpanelet (de blir 18 eller pill).

### 2.5 Fokusstil: tre typer, én kilde

All fokusvisning går gjennom `LunaFocusStyle` / `lunaFocusSurface`. Ingen visning setter egen `scaleEffect`, glød eller fokuskant.

| Type (`LunaFocusKind`) | Hvile | Fokus | Skala | Glød |
| --- | --- | --- | ---: | --- |
| `.card` (plakat, backdrop, episode, «Se alle») | Kunst 90 % lysstyrke, ingen kant | Kunst 100 %, **2 pt `Accent.line` 85 %** innvendig kant | **1,05** | Rom-lampe, blur 30, y 12 |
| `.control` (pille, fane, ikonsirkel, primær) | `surfaceRaised`, etikett `moonlight` (fane: transparent, `muted`) | **`playFocusGradient`-fyll**, etikett og ikon `Text.onAccent`, ingen kant | **1,04** | Rom-lampe, blur 30, y 12 |
| `.control` destruktiv | `surfaceRaised`, etikett `coral`, **ingen kant** | `Status.dangerBg`, 2 pt `coral` 85 % | 1,04 | Ingen |
| `.listRow` (rader, felt, sidemeny) | Ingen fyll (felt: `surfaceRaised`) | `surfaceSelected` + 3 pt gull venstremarkør, ingen ramme | 1,0 | Ingen |

| Valgt-tilstand (ikke fokusert) | Visning |
| --- | --- |
| Pille i gruppe (sortering, sesong, MetalFX, Kveldslys) | `surfaceSelected`-fyll + `linen`-etikett. Ingen `Accent.soft`, ingen kant |
| Valg i liste (rom, spor, kilde, sesong i rutenett) | Ett `checkmark`-symbol (SF Symbol, `settingsRowIcon` 24 pt) i `amber`, høyrestilt. Stryk «✓»-glyfen, «Aktiv», `checkmark.circle.fill`, tom `circle` og grønn farge |
| Navigasjon (toppfane, sidemeny i Innstillinger) | Etikett `linen` + 22 × 2,5 gull understrek (fane) eller gullikon (sidemeny). Ingen fyll, ingen kant |
| Av/på | Høyrestilt verditekst «På» (`linen`) / «Av» (`muted`), `caption` bold. Ingen pille |

- **Bevegelse:** én fjær (`focusSpringResponse` 0,32 / `damping` 0,86). Fokus-for-å-velge (toppbar og sidemeny) bruker samme debounce, `focusSelectDebounceMs` = 180 (i dag 180 i toppbaren og 120 i `SettingsView.swift#L266`).
- **Begrunnelse:** et gullfylt mål på 1,04 er entydig både på OLED (mørkt) og The Frame (lyst), uavhengig av gløden. Kortene får tydeligere kant (2 pt / 85 %) fordi kunsten ofte er varm og flerfarget.

### 2.6 Knapper

| Variant | Form | Høyde | Innhold | Regel |
| --- | --- | ---: | --- | --- |
| Primær (`.primary`, tidl. `.primaryAmber`) | Kapsel | 56 | `play.fill` i `amber` + etikett `linen` semibold, hårstrek `Accent.border` i hvile | **Maks én per skjerm eller ark**. Fokus som `.control` |
| Sekundær (`.glassPill`) | Kapsel | 56 / 48 | Valgfritt ikon + etikett | Maks tre tekstknapper + ett ⋯ på en handlingsrad |
| Ikon (`LunaIconButton`, ny) | Sirkel | 56 | Ett SF Symbol | ⋯, tøm søk, toppbarens Søk og Innstillinger |
| Teksthandling (`.subtleChip`) | Ingen flate i hvile | 48 | Etikett `moonlight` | «Tøm», «Nullstill filtre» og andre lavprioriterte handlinger |
| Destruktiv | Som sekundær | 56 | Etikett `coral` | Fokus som destruktiv `.control` |

- `badgeText` i pille brukes bare til **tall** («12», «S2 · E4»). Den er aldri tekst som «MetalFX» eller «•».
- `.compact` (48) brukes i filterstriper, sesongvalg og spillerstripen. Alt annet er `.regular` (56).

### 2.7 Badges, merker og fremdrift

| Element | Spesifikasjon | Erstatter |
| --- | --- | --- |
| `LunaArtBadge` (ny, på kunst) | Kapsel, fyll `Surface.badgeScrim`, **ingen kant**, `badge` 22 semibold `linen`, innmarg 12 × 6, valgfri 8 pt prikk eller ett ikon. Øverst til venstre, 14 pt fra kant. **Maks én per kort** | `originPill`, `upcomingDatePill`, episode-«Kommer», sett-hake på glass |
| Sett | `LunaArtBadge` med bare `checkmark` i `emerald` | Hake på `cinemaGlass`-sirkel og 100 %-fremdrift på episoder |
| Lagringsnivå | 8 pt prikk (`tierNvme` fylt / `tierArchive` ring / ingen for strøm) **foran undertekstlinjen** (ved fokus på hyller, og synlig sammen med hviletittel i rutenett som Bibliotek). Ingen skive på kunsten | `LunaTierMarkView` oppå kunst |
| Formater (4K, Dolby Vision, HDR10+, Atmos) | Ren tekst i `subtitle` `muted`, skilt med « · », maks tre, i formatlinjen på detaljsiden og i OSD-hodet | Innrammede versal-badges, kvalitetspille i OSD |
| Fremdrift | 6 pt kapsel, spor `Edge.progressTrack`, fyll `amber`, 14 pt fra kant. **Vises bare når 2 % < p < 95 %** på alle korttyper | Tre ulike terskler (`> 2`, `> 0`, `> 1 \|\| watched`) |

### 2.8 Seksjonshode, listegruppe og rad

- **Seksjonshode:** `sectionTitle` `linen`, setningsstil, uten ikon og uten undertittel. Høyre side har enten én metaverdi (`caption` `muted`, f.eks. «8 episoder») eller én teksthandling («Tøm»). `headerGap` 16 under.
- **Listegruppe (`LunaListGroup`, ny):** nivå 1-flate, r18, `overflow` klippet, skillelinjer mellom radene, ingen indre flater.
- **Rad (`LunaListRow`, ny):** min. 72 pt, innmarg 24 × 16. Valgfritt ledende SF Symbol (24 pt, `moonlight`, aldri ikonflis). Tittel `cardTitle` på én linje. Valgfri dataundertekst `subtitle` `muted` på én linje. På høyre side står **én** av følgende: verdi (`subtitle` `moonlight`), `checkmark`, kompakte segmentpiller eller chevron. Fokus som `.listRow`.

### 2.9 Ark og paneler

- **Ark (`LunaSheetContainer`, ny):** lerret, sentrert nivå 1-ark, `sheetPadding` 48, bredde `sheetNarrowW` (Mer, Slett, Handling, Feil) eller `sheetWideW` (Velg kilde, Velg sesong). Hodet er `pageTitle` pluss maks én metalinje (`subtitle` `muted`, uten romnavn), og deretter innhold direkte uten skillelinje. Radene inne i arket er en `LunaListGroup` uten egen bakgrunn, slik at radene ligger flatt på arkflaten. `onExitCommand` lukker.
- **Hurtigpanel i spiller:** nivå 1-glass, r24, toppkant + skygge, **ingen 1 pt kant**, bredde 740/920. Hodet er bare tittelen (`cardTitle`), uten ikon og uten gjentatt valgt verdi. Grupper i panelet skilles med en `caption`-etikett i `muted` («Kveldslys», «Tekstsynk»), ikke med en ny flate.

### 2.10 Tilstander

| Tilstand | Komponent (ny, `Sources/DesignSystem/LunaInlineStateViews.swift`) | Spesifikasjon |
| --- | --- | --- |
| Lasting | `LunaLoadingRow` | `ProgressView` + «Henter …» i `subtitle` `muted`, venstrejustert ved gutter, 48 pt vertikalt |
| Tom | `LunaEmptyState` | Venstrejustert ved gutter: maskot 64 pt `moonlight` 50 %, én overskrift i `pageTitle`, maks én handling (sekundær). **Ingen forklarende avsnitt** |
| Feil | `LunaInlineError` | 8 pt `coral`-prikk + melding i `body` `linen` (ikke rød tekst), deretter «Prøv igjen» (sekundær, fokuserbar, mål for x = 90-inngang) |
| Midlertidig melding | `LunaToast` | Kapsel `Surface.glass`, ingen kant, 8 pt tonet prikk (ok/warn/danger), `subtitle`. **Nederst til venstre** (x 90, bunn 60), 4 s. Overlapper aldri toppbar eller hyllehode |
| Spillerstatus | `PlayerStatusPill` | Som `LunaToast`, men øverst i midten (y 60) og med valgfri `ProgressView`. Maks én om gangen (kø), erstatter tre overlegg |

### 2.11 Tokenendringer (`design/tokens.json` → `platform.tvos`)

```json
{
  "typography": { "heroSerif": 64, "titleSerif": 46, "pageTitle": 40, "cardTitle": 29 },
  "dimensions": {
    "focusBorderWidth": 2.0, "focusBorderOpacity": 0.85,
    "focusScaleCard": 1.05, "focusScaleControl": 1.04, "focusScaleRow": 1.0,
    "safeTop": 60, "safeBottom": 60, "contentTop": 162, "subpageTop": 60,
    "sectionGap": 32, "headerGap": 16, "blockGap": 24, "gridRowGap": 32,
    "episodeW": 420, "episodeH": 236, "controlH": 56, "compactControlH": 48, "iconButton": 56,
    "listRowPadX": 24, "listRowPadY": 16, "listRowMinH": 72,
    "sheetPadding": 48, "sheetNarrowW": 880, "sheetWideW": 1240,
    "quickPanelW": 740, "quickPanelWideW": 920
  },
  "motion": { "focusSelectDebounceMs": 180 }
}
```

Regenerer med `./ops/bin/luna-design-tokens --sync`. Hvis generatoren ikke skriver ut nye nøkler eller `motion`-blokken automatisk, utvides den først. `LunaTokens.swift` skal aldri redigeres for hånd.

---

## 3. Skjerm for skjerm: stryk- og forbedringsliste

### 3.1 Toppbar og skall

| # | Tiltak | Fil |
| --- | --- | --- |
| T1 | **Endre** `.padding(.top, 46)` til `safeTop` (60). `contentTopPadding` leses fra token | `LunaTopBarView.swift#L5`, `#L70` |
| T2 | **Endre** fanefokus til `.control`-standard (gullfyll, 1,04, standard glød). Stryk egen glød 24/10 og egen kant | `LunaTopBarView.swift#L305-L340` |
| T3 | **Behold** emblem (månesigd 34 pt gull + romnavn `brandSerif` `moonlight`). Dette er den eneste faste plassen for romnavnet | `LunaTopBarView.swift#L196-L212` |
| T4 | **Behold** fokus-for-å-velge (180 ms), fokusbroene opp og ned og hvilestreken under aktiv fane | `LunaTopBarView.swift#L76-L153`, `#L323-L332` |
| T5 | **Endre** toppgradientens høyde fra 164 til `contentTop` (162), slik at gradient og innholdsstart følger samme token | `MainNavigationShell.swift#L194-L208` |

### 3.2 Hjem

| # | Tiltak | Fil |
| --- | --- | --- |
| H1 | **Endre** blokkavstand fra 28 til `sectionGap` og hode → rad fra 14 til `headerGap` | `HomeView.swift#L110`, `ShelfRowView.swift#L42` |
| H2 | **Endre** alle kort til `LunaFocusStyle` (`.card`, 1,05, 2 pt / 85 %). Stryk lokale `scaleEffect` | `PosterCardView.swift#L140-L146`, `BackdropCardView.swift#L142-L148` |
| H3 | **Behold** skjult plakattittel i hvile på hyller (`showRestingTitle: false`) og synlig i rutenett. Dokumenter dette som regel: *hylle = rolig kunst, rutenett = titler* | `ShelfRowView.swift#L213` |
| H4 | **Stryk** lagringsskiven på kunsten. **Endre** til tier-prikk foran undertekstlinjen ved fokus | `PosterCardView.swift#L115-L118`, `#L166-L170`, `BackdropCardView.swift#L85-L88` |
| H5 | **Endre** opprinnelses- og datopille til `LunaArtBadge` (ingen kant, `calendar`-ikonet strykes) | `BackdropCardView.swift#L177-L213` |
| H6 | **Stryk** «· {NVMe-fordel}» som legges til «Fortsett»-undertittelen | `BackdropCardView.swift#L220-L228` |
| H7 | **Endre** fremdriftsterskel på backdrop fra `pct > 0` til 2–95 % | `BackdropCardView.swift#L126` |
| H8 | **Endre** «Se alle»-kortet til `.card`-fokus. Radius følger raden (16 i plakatrad, 18 i landskapsrad) | `ShelfRowView.swift#L263-L293` |
| H9 | **Endre** lasting, feil og banner til `LunaLoadingRow` / `LunaInlineError` / `LunaToast` | `HomeView.swift#L115-L137`, `#L213-L220` |
| H10 | **Endre** ikonet for «Åpne detaljer» i kommende-raden fra `tv` til `info.circle`, som i resten av kontekstmenyene | `ShelfRowView.swift#L127` |

### 3.3 Filmer og Serier (`CatalogBrowseView`)

| # | Tiltak | Fil |
| --- | --- | --- |
| K1 | **Stryk** sidetittelen «Filmer»/«Serier» på rotfanen. **Behold** den på undersider («Drama · Filmer»), med `pageTitle` 40 semibold | `CatalogBrowseView.swift#L139-L142` |
| K2 | **Endre** filterstripen til tre grupper med 1 pt skille mellom **hver** gruppe: [sortering] │ [Kun lokalt, Skjul sette] │ [Alle sjangre, sjangre…]. Valgt sortering og sjanger vises med `surfaceSelected`. Av/på-filtre har `checkmark`-ikon når de er på | `CatalogBrowseView.swift#L145-L221`, skille `#L184-L189` |
| K3 | **Endre** rutenettets radavstand fra 26 til `gridRowGap` og blokkavstand fra 26 til `blockGap` | `CatalogBrowseView.swift#L134`, `#L278` |
| K4 | **Endre** «Ingenting passer akkurat disse filtrene.» til `LunaEmptyState` «Ingen treff med disse filtrene» + teksthandling «Nullstill filtre» | `CatalogBrowseView.swift#L261-L276` |
| K5 | **Endre** «Henter utvalg…» og feil til felles tilstandskomponenter | `CatalogBrowseView.swift#L242-L260` |

### 3.4 Bibliotek

| # | Tiltak | Fil |
| --- | --- | --- |
| B1 | **Stryk** sidetittelen «Bibliotek» | `LibraryHubView.swift#L63-L66` |
| B2 | **Endre** «Filmer (12)» til etikett «Filmer» + `badgeText: "12"` (tall-badge i pillen) | `LibrarySidebarAndEmptyViews.swift#L83-L86`, `LibraryHubView.swift#L70-L75` |
| B3 | **Endre** tom tilstand til venstrejustert `LunaEmptyState`. **Stryk** de tre forklaringsavsnittene (`emptySubtitle`). Overskriftene beholdes | `LibrarySidebarAndEmptyViews.swift#L110-L119`, `#L136-L169` |
| B4 | **Fiks fokusfelle:** tom tilstand uten handling får ikke `.focused(...)`. Da faller pil ned tilbake til fanepillene. Med handling er handlingsknappen fokusmålet | `LibraryHubView.swift#L249-L251`, `#L230-L241` |
| B5 | **Endre** blokkavstand fra 22 til `blockGap` og radavstand fra 26 til `gridRowGap`. Lasting og feil til felles komponenter | `LibraryHubView.swift#L58`, `#L96-L113`, `#L253` |

### 3.5 Detaljside, sesonger, episoder og ark

**Hero (`DetailHeroHeaderView.swift`), målstruktur:**

```
[Tittel – heroSerif 64]
2024 · Drama, Thriller · 2 t 14 min · ★ 7,8                 (metalinje, subtitle moonlight)
● 4K Dolby Vision · Dolby Atmos                               (formatlinje, subtitle muted, tier-prikk)
Handlingen over maks 3 (film) / 2 (serie) linjer …            (body moonlight)
[▶ Fortsett · S1 E3]  [Kilde]  [Huskeliste]  (⋯)              (handlingsrad, én primær)
```

| # | Tiltak | Fil |
| --- | --- | --- |
| D1 | **Stryk** versal-kickeren (studio/nettverk) | `DetailHeroHeaderView.swift#L34-L40` |
| D2 | **Endre** tittelen fra `detailHeroSerif` 72 bold til `heroSerif` 64 semibold | `#L43-L47` |
| D3 | **Stryk** innrammede badges og tilgjengelighetslinjen. **Endre** til én formatlinje: tier-prikk (bare NVMe/arkiv) + maks tre formater som tekst. Strenger som «klar i vfs» og «på nvme» filtreres fortsatt bort (`#L263-L283`) | `#L55-L72`, `#L103-L114` |
| D4 | **Endre** «Kommer: {dato}» fra egen linje til siste ledd i metalinjen («Ny episode 24. nov.») | `#L93-L102`, `#L243-L261` |
| D5 | **Stryk** «Les mer»-chipen (eget fokusstopp). **Endre** slik at hele handlingen åpnes fra ⋯ → «Les hele handlingen» | `#L84-L88` |
| D6 | **Endre** «Spill av» fra r16-rektangel til primær kapsel (56 pt) med `.control`-fokus | `#L286-L333` |
| D7 | **Stryk** «Sett» fra handlingsraden og flytt den til ⋯ (se Q3). Raden blir Spill av · Kilde · Huskeliste · ⋯ | `#L142-L150` |
| D8 | **Endre** ⋯ fra 60 pt sirkel med skala 1,05 til `LunaIconButton` 56 med 1,04 | `#L335-L383` |
| D9 | **Behold** hero-høyder (film 760 / serie 500), toppinnmarg 136 / 64 og gradientene | `#L24-L26`, `#L171-L234` |

**Sesonger og episoder:**

| # | Tiltak | Fil |
| --- | --- | --- |
| D10 | **Endre** «{Sesong} ▾» med `square.grid.2x2`-ikon til etikett + `chevron.down`-symbol. Stryk tekstglyfen «▾» og rutenettikonet | `DetailSeasonsSectionView.swift#L72-L81` |
| D11 | **Endre** episodekortet: `.card`-fokus. Sett vises som hake-badge (stryk 100 %-linjen og teksten «Sett»). «Neste for deg» blir `LunaArtBadge` «Neste» | `EpisodeCardView.swift#L66-L88`, `#L132-L145` |
| D12 | **Endre** handlingen på episodekortet slik at den bare vises på fokusert kort. Høyden på to linjer reserveres alltid, så ingenting hopper (samme mønster som plakaten) | `EpisodeCardView.swift#L149-L155` |
| D13 | **Endre** `cardWidth`/`cardHeight` til tokenene `episodeW`/`episodeH` | `EpisodeCardView.swift#L4-L5` |
| D14 | **Endre** sesongvelgeren til `LunaSheetContainer` (bredt). Flisene blir `LunaListRow`-stil i fire kolonner med `checkmark` for valgt. Stryk kant i hvile, `Accent.soft`, «✓» og egen glød | `DetailSeasonsSectionView.swift#L166-L319` |

**Ark:**

| # | Tiltak | Fil |
| --- | --- | --- |
| D15 | **Mer-arket:** tittelen blir innholdstittelen (`pageTitle`). Stryk «Mer» og «· {rom}». Radene er en `LunaListGroup` uten undertekst: Les hele handlingen, Marker som sett/usett, Følg serien / Gjør klar på forhånd, Slett sesong N, Slett fra samlingen. **Stryk** «Velg kilde» (dublett av Kilde-knappen) og alle fire forklarende undertitler | `DetailMoreAndOverviewSheets.swift#L42-L146`, rad `#L148-L199` |
| D16 | **Handling-arket:** tittel `titleSerif` 46, bredde `sheetNarrowW`. **Behold** fokuserbare avsnitt for rulling | `DetailMoreAndOverviewSheets.swift#L247-L321` |
| D17 | **Velg kilde:** stryk «· Tilpasset {rom}». Kilderaden blir `LunaListRow`: tittel, dataundertekst og `checkmark`. Flagg-badgen «🇳🇴 Norsk» blir «Norsk» som første ledd i underteksten. Stryk r16 og skala 1,015 | `SourcePickerSheetView.swift#L308-L313`, `#L377-L387`, `SourceCandidateRowView.swift#L17-L88` |
| D18 | **Slett:** `LunaSheetContainer` (smalt). Innholdsoppsummeringen (`#L67-L71`, `#L212-L213`) ligger flatt på arket uten egen r16-flate | `DetailDeleteSheetView.swift` |

### 3.6 Søk

| # | Tiltak | Fil |
| --- | --- | --- |
| S1 | **Stryk** sidetittelen «Søk» | `SearchView.swift#L63-L66` |
| S2 | **Endre** feltet: ett fokussignal (`.listRow`: fyll + venstremarkør). Stryk fargeskiftet på forstørrelsesglasset. Plassholder blir «Film, serie eller person» | `#L68-L91`, `#L72`, `#L74` |
| S3 | **Endre** «Tøm» ved feltet til `LunaIconButton(xmark)` | `#L92-L97` |
| S4 | **Endre** «Tidligere søk» til kanonisk seksjonshode (`sectionTitle` `linen`) med teksthandling «Tøm». Stryk søppelbøtteikonet og koralfargen. Stryk klokkeikonene i pillene | `#L104-L131` |
| S5 | **Stryk** hintet «Skriv minst to tegn for å søke i bibliotek og katalog.» | `#L134-L140` |
| S6 | **Endre** «N i Lokalt»-pillen og «N treff totalt» til én metalinje i `caption` `muted`: «24 treff · 6 lokalt» | `#L142-L158` |
| S7 | **Endre** «Fant ikke …» til venstrejustert `LunaEmptyState` (alltid `pageTitle`, aldri `heroSerif`). Stryk tipssetningen. Handling: «Tøm søk» | `#L180-L196` |

### 3.7 Innstillinger

| # | Tiltak | Fil |
| --- | --- | --- |
| I1 | **Endre** `SettingsSectionPanel` til seksjonshode + `LunaListGroup`. Stryk r24-panelet med 24 pt innmarg | `SettingsComponents.swift#L3-L24` |
| I2 | **Endre** `SettingsRoomRowButton` til `LunaListRow`: tittel, utstyr som undertekst og `checkmark` for valgt. Stryk «Aktiv», `checkmark.circle.fill`, `circle` og egen r12-flate | `SettingsComponents.swift#L100-L158` |
| I3 | **Endre** `SettingsToggleRowButton` til `LunaListRow` med verditekst «På»/«Av». Stryk pillen med grønn kant | `SettingsComponents.swift#L160-L222` |
| I4 | **Endre** `SettingsControlRow` til horisontal standard: tittel til venstre, kompakte segmentpiller til høyre, maks én dataundertekst. Vertikal akse bare når pillene ikke får plass | `SettingsComponents.swift#L34-L78` |
| I5 | **Endre** sidemenyen: fokus som `.listRow`. Valgt i hvile vises med `linen`-tekst og gullikon. Stryk fyll, `Accent.soft`, kant og gull venstremarkør for valgt-i-hvile. Debounce 120 → 180 | `SettingsView.swift#L210-L270` |
| I6 | **Stryk** infolinjen «Aktivt rom» og hintet «Velg rom for denne Apple TV-en (oppdaterer LunaCore direkte)» i Rom og skjerm. Romlisten med hake viser det samme | `SettingsComfortSectionView.swift#L12-L20` |
| I7 | **Endre** «Aktiv tvOS-videomodus nå» til «Skjermen støtter», som er det verdien faktisk viser | `SettingsComfortSectionView.swift#L91`, `#L95-L106` |
| I8 | **System:** stryk den dupliserte «Aktivt rom». Informasjonsradene samles i én gruppe «Om denne Apple TV-en». «Tøm hurtigbuffer» og «Koble til på nytt…» blir destruktive rader i egen gruppe. «Hurtigbuffer tømt» vises som verditekst i raden | `SettingsServerDiagnosticsSectionView.swift#L13-L84` |
| I9 | **Forkort** undertitler til én linje med data: lyd «Auto 7.1.4 anbefales · Stereo for TV-høyttalere», lydsynk «Negativ verdi sender lyden tidligere». Stryk undertitlene til «Spill neste episode automatisk» og «Vis teknisk oversikt i spilleren» | `SettingsAdvancedSectionView.swift#L26-L28`, `#L46-L48`, `#L78-L79`, `SettingsComfortSectionView.swift#L182-L183` |

### 3.8 Avspiller: OSD, scrubbing, paneler og overlegg

**Behold (fungerer godt med Siri Remote):**

- Meny-stigen er forutsigbar: panel → avbryt scrub → serieprompt → hurtigstripe → skjul OSD → lukk (`PlayerContainerView.swift#L503-L523`).
- Touch-scrubbing bare i pause, med 20 pt løsrivelse, aksesperre og tre fartsoner. Holdt ringpil gir 30 → 120 → 300 s/s. Spoleklikk samles med «±N s»-tilbakemelding (`RemoteScrubMath.swift`).
- Auto-skjul etter 4 s (spiller), 7 s (hurtigstripe) og 12 s hvile i pause (`PlayerContainerView.swift#L5-L7`).
- Tidslinjen: 5 → 8 pt utvidet, kapittelstreker, utgangspunktmarkør og forhåndsvisningsboble. Klokkeobservasjon bare i bladvisninger.
- Feiloverlegget har én primær («Prøv igjen»), «Velg kilde» og «Avslutt» (`PlayerFatalErrorOverlayView.swift#L66-L79`).

| # | Tiltak | Fil |
| --- | --- | --- |
| P1 | **Endre** OSD-hodet: kvalitetspillen blir tekst i `caption` `muted` foran «Ferdig kl. 21.47» («4K DV · Atmos · Ferdig kl. 21.47») | `PlayerBottomBarView.swift#L129-L145` |
| P2 | **Stryk** passive badges i hurtigstripen. «MetalFX» fjernes helt. «•» for aktiv tekst blir en 8 pt `moonlight`-prikk rett etter etiketten, ikke `badgeText` | `PlayerBottomBarView.swift#L213-L226` |
| P3 | **Endre** scrub-hintet fra «Trykk for å spille herfra · Meny avbryter» til «Klikk for å spille herfra» (Meny avbryter alltid på tvOS) | `PlayerBottomBarView.swift#L496-L500` |
| P4 | **Stryk** gløden på scrub-knotten. Gullfyll, gull knott og gull tid er nok signal | `PlayerBottomBarView.swift#L446` |
| P5 | **Endre** «Bytter kilde…», advarselsbanner og fjernkontroll-toast til én `PlayerStatusPill` øverst i midten, med kø og maks én om gangen | `PlayerBottomBarView.swift#L72-L87`, `PlayerContainerView.swift#L350-L394` |
| P6 | **Endre** spoletilbakemeldingen (`CoalescedSeekFeedbackPillView`): stryk kanten, behold glass | `PlayerFatalErrorOverlayView.swift#L4-L26` |
| P7 | **Endre** hurtigpanelet: bredde 640/820, stryk 1 pt kant, stryk ikon og gjentatt verdi i hodet (`headerSubtitle`, inkl. «Tilpasset {rom}»). Radene blir `LunaListRow` (r18, `checkmark`, ingen skala 1,015) | `PlayerQuickPanelView.swift#L65-L73`, `#L174-L246`, `#L600-L676` |
| P8 | **Stryk** underteksten «Ingen undertekster» under «Av». Øvrige radundertekster beholdes bare når de bærer data (format, kanaler, SDH) | `PlayerQuickPanelView.swift#L268-L276` |
| P9 | **Fiks hopp:** serieprompt-etiketter endres ikke ved fokus. Stryk «▲ »-prefikset. Hintet blir et separat `chevron.up`-symbol i `muted` til venstre for pillen, i en ramme med fast bredde som alltid er reservert | `SeriesFlowOverlays.swift#L330-L331`, `#L422-L423` |
| P10 | **Endre** øyenbrynet «Neste episode · S2 E4» fra `amber` til `muted` (gull = fokus) | `SeriesFlowOverlays.swift#L356-L359` |
| P11 | **Stryk** «· {rom}» i NerdHUD-tittelen | `NerdHUDView.swift#L19` |
| P12 | **Stryk** kanten på statuskapselen i teppet | `ResolvingCurtainView.swift#L176-L188` |

### 3.9 Paring (kort)

| # | Tiltak | Fil |
| --- | --- | --- |
| O1 | **Stryk** slagordet «Hjemmekino for LunaCore · Dolby Vision og romtilpasset lyd». Ordmerket «Luna» bruker `heroSerif` 64 | `PairingOnboardingView.swift#L25-L30` |
| O2 | **Behold** paringskoden (88 pt), «Ny kode» som eneste primær og «Bytt server» som teksthandling | `PairingOnboardingView.swift#L127-L160` |

---

## 4. Siri Remote-fokuskart (invarianter)

| Fra | Handling | Til | Status |
| --- | --- | --- | --- |
| Toppbar | ↓ | Første kontroll ved x = 90: Hjem → første kort, Filmer/Serier → valgt sortering, Bibliotek → aktiv pille, Søk → feltet, Innstillinger → valgt kategori | Behold |
| Første rad/kontroll | ↑ | Valgt fane (bro) | Behold |
| Toppbar | → / ← | Bytter fane etter 180 ms | Behold |
| Filterstripe | ↓ | Første kort i rutenettet | Behold. Ved tomt rutenett: «Nullstill filtre» eller ingen bevegelse (aldri et dødt mål) |
| Detalj: handlingsrad | ↑ | Ingen bevegelse (D5 fjerner «Les mer») | Endre |
| Detalj: handlingsrad | ↓ | Valgt sesong-pille → neste episode | Behold |
| Spiller (lerret) | ↓ / klikk | Viser OSD og fokuserer «Tekst» | Behold |
| Hurtigstripe | ↑ | Tilbake til lerret | Behold |
| Ark | Meny | Lukker ark, fokus tilbake til utløser | Behold, gjelder alle `LunaSheetContainer` |
| Overalt | Spill/pause på kort | Spiller av (snarvei) | Behold |

**Akseptanse for fokus:** et fokusert element kan aldri ha lavere visuell vekt enn et ufokusert element i samme synsfelt. Tekst endrer seg ikke ved fokus. Ingen fokusmål kan ligge utenfor 90/60-safe area etter skalering.

---

## 5. Implementeringsrekkefølge (etter godkjenning)

Hver fase er én commit. Verifikasjonssløyfen i AGENTS.md §7 kjøres per fase (`luna-check` + `test-core.sh` lokalt, preview-sandkasse, til slutt `tvos-vision.yml` på en `agent/*`-gren).

| Fase | Innhold | Hovedfiler |
| --- | --- | --- |
| F1 Tokens og typografi | §2.11 i `design/tokens.json`, regenerer `LunaTokens.swift`, konsolider `LunaTheme.Font` (deprecated-aliaser), `LunaFocusStyle` (`.card` 1,05 · `.control` 1,04 · `.listRow` 1,0), `LunaPillButton` (gull = fokus, ingen kant i hvile, `.primary`) | `design/tokens.json`, `Sources/DesignSystem/Tokens/LunaTokens.swift`, `LunaThemeTypography.swift`, `LunaFocusStyle.swift`, `LunaPillButton.swift` |
| F2 Nye primitiver | `LunaListGroup`/`LunaListRow`, `LunaArtBadge`, `LunaIconButton`, `LunaSheetContainer`, `LunaLoadingRow`/`LunaEmptyState`/`LunaInlineError`/`LunaToast`/`PlayerStatusPill`. Hver fil ≤ 800 LOC og føres inn i `CODEBASE_MODULE_MAP.md` | `Sources/DesignSystem/LunaListRow.swift`, `LunaBadges.swift`, `LunaSheetContainer.swift`, `LunaInlineStateViews.swift` (nye) |
| F3 Kort | Plakat, backdrop, episode og «Se alle» | `Sources/DesignSystem/Cards/*`, `EpisodeCardView.swift`, `ShelfRowView.swift` |
| F4 Skall og faner | T1–T5, H1–H10, K1–K5, B1–B5, S1–S7 | `LunaTopBarView.swift`, `MainNavigationShell.swift`, `HomeView.swift`, `CatalogBrowseView.swift`, `CustomRowBrowseView.swift`, `LibraryHubView.swift`, `LibrarySidebarAndEmptyViews.swift`, `SearchView.swift` |
| F5 Detalj og ark | D1–D18 | `DetailHeroHeaderView.swift`, `DetailSeasonsSectionView.swift`, `EpisodeCardView.swift`, `DetailMoreAndOverviewSheets.swift`, `SourcePickerSheetView.swift`, `SourceCandidateRowView.swift`, `DetailDeleteSheetView.swift`, `MediaDetailView.swift` |
| F6 Innstillinger | I1–I9 | `Sources/Features/Settings/*` |
| F7 Spiller | P1–P12 | `PlayerBottomBarView.swift`, `PlayerQuickPanelView.swift`, `PlayerContainerView.swift`, `SeriesFlowOverlays.swift`, `PlayerFatalErrorOverlayView.swift`, `NerdHUDView.swift`, `ResolvingCurtainView.swift` |
| F8 Paritet og tester | Speil endringene i `preview/index.html` (sandkassen). Oppdater låste testverdier: `DesignTokensAndCopyTests.swift#L70-L73` (skala), `PlayerOverlayAndCacheTests.swift#L522-L523` (panelbredder) og øvrige påvirkede tester i `ThemeAndArtworkViewTests`, `NavigationSettingsAndDeleteTests`, `LunaNavigationAndDetailRaceTests`, `PlayerExitBlinkRegressionTests`. Kopiendringer føres i `Resources/Localizable.xcstrings` | `preview/*`, `Tests/LunaTests/*`, `Resources/Localizable.xcstrings` |

> Rekkefølgen er valgt slik at F1–F2 gir alle skjermer det nye språket automatisk der de allerede bruker delte komponenter. F3–F7 rydder lokale avvik. Hver fase er bygbar og kan sendes for seg.

---

## 6. Akseptansekriterier

1. **Fokus:** `rg "scaleEffect\(" Sources/Features Sources/App` gir bare treff via `LunaFocusStyle` eller trykk-skala i `LunaChromelessButtonStyle`. Det finnes nøyaktig tre fokusskalaer (1,0 / 1,04 / 1,05).
2. **Gull = fokus:** ingen ufokusert kontroll har `playFocusGradient`- eller `primaryAmberGradient`-fyll. `amber` brukes bare til fokus, primærikon, valgt-hake, fremdrift og scrubbing.
3. **Én ramme:** ingen `strokeBorder` på flater i hvile i `Sources/Features/**`, unntatt primærens hårstrek og tekstfeltet.
4. **Typografi:** ≤ 9 tekstroller + ikonroller i `allFixedPointSizes`. Ingen `.uppercased()` eller `.tracking(` på synlig tekst.
5. **Størrelser:** to arkbredder (880/1240) og to panelbredder (740/920). Alle vertikale avstander kommer fra `sectionGap`/`headerGap`/`blockGap`/`gridRowGap`.
6. **Romnavn:** `sessionStore.roomName` og `activeSession?.roomName` forekommer i `Text(...)` bare i toppbaren og romvelgeren.
7. **Fokusflyt:** tabellen i §4 holder på alle seks faner. Ingen etikett endrer tekst ved fokus. Det finnes ingen tom tilstand uten fokusmål.
8. **Porter:** `./ops/bin/luna-check` og `./scripts/test-core.sh` er grønne. Preview-sandkassen (1920 × 1080, `?guides=1`) og de fire `tvos-vision`-renderne (`home`, `catalog`, `details`, `player`) er inspisert visuelt. Ingen fokusert kant klipper mot 90/60-guidene.

---

## 7. Åpne spørsmål

| # | Spørsmål | Anbefaling |
| --- | --- | --- |
| Q1 | **Gull = fokus** (primær hviler på `surfaceRaised` med gullikon, og bare fokusert kontroll er gullfylt) eller beholde gullfylt «Spill av» i hvile og bare styrke fokus på sekundærknapper? | **Gull = fokus.** Det er det eneste som er entydig på The Frame i dagslys og som fjerner dobbeltbetydningen. |
| Q2 | Stryke sidetitler på rotfanene Filmer, Serier, Bibliotek og Søk? | **Ja.** Toppbaren er tittelen. Gir ≈ 70 pt mer innhold og lik `y` på alle faner. |
| Q3 | Flytte «Marker som sett» fra detaljens handlingsrad til ⋯? | **Ja.** Den brukes sjelden, finnes i kontekstmenyen og gir maks fire elementer på raden. |
| Q4 | Lagringsnivå på kort: prikk i undertekstlinjen ved fokus, eller beholde skiven på kunsten? | **Prikk i undertekst.** Rolig kunst, samme språk som `ui-tier-mark` på iPhone. |
| Q5 | Episodehandling bare på fokusert kort (fast reservert høyde)? | **Ja.** Raden blir roligere, og kortet du står på gir full kontekst. |
| Q6 | Scrub-hint: alltid synlig (forkortet) eller bare de første gangene? | **Alltid, forkortet.** Det krever ingen ny lagret tilstand. |
| Q7 | Skal dette dokumentet lenkes fra `AGENTS.md` §4 og `CODEBASE_MODULE_MAP.md` som designkilde? | Ja, i F8. |

---

## 8. Strykliste: tekst som fjernes eller forkortes

| Tekst i dag | Fil | Tiltak |
| --- | --- | --- |
| Studio-/nettverkskicker i VERSALER | `DetailHeroHeaderView.swift#L34-L40` | Stryk |
| «{fordel} · klar for {rom}» | `DetailHeroHeaderView.swift#L109` | Stryk (tier-prikk i formatlinjen) |
| «Kommer: {dato}» (egen linje) | `DetailHeroHeaderView.swift#L98` | Flytt til metalinjen |
| «Les mer» | `DetailHeroHeaderView.swift#L85` | Stryk (⋯ → «Les hele handlingen») |
| «Mer» + «{tittel} · {rom}» | `DetailMoreAndOverviewSheets.swift#L44-L50` | Bare innholdstittel |
| «Anbefalt for {rom}: beste bilde og lyd» | `DetailMoreAndOverviewSheets.swift#L58` | Stryk (raden fjernes) |
| «Frigjør lagringsplass for valgt sesong etter bekreftelse» | `DetailMoreAndOverviewSheets.swift#L80` | Stryk |
| «Du får se nøyaktig hva som fjernes før du bekrefter» | `DetailMoreAndOverviewSheets.swift#L92` | Stryk |
| «Nye episoder hentes automatisk (når de kommer)» / «Lagres på NVMe …» / «Starter umiddelbart …» | `DetailMoreAndOverviewSheets.swift#L133-L138` | Stryk |
| «· Tilpasset {rom}» | `SourcePickerSheetView.swift#L312`, `PlayerQuickPanelView.swift#L239-L240` | Stryk |
| «🇳🇴 Norsk»-badge | `SourceCandidateRowView.swift#L38-L47` | «Norsk» i underteksten |
| «Søk etter film, serie, person eller originaltittel…» | `SearchView.swift#L74` | «Film, serie eller person» |
| «Skriv minst to tegn for å søke i bibliotek og katalog.» | `SearchView.swift#L135` | Stryk |
| «{n} i Lokalt» + «{n} treff totalt» | `SearchView.swift#L144-L155` | «{n} treff · {m} lokalt» |
| «Prøv originaltittelen eller en annen stavemåte.» | `SearchView.swift#L186` | Stryk |
| «Tøm logg» (koral, søppelbøtte) | `SearchView.swift#L112` | «Tøm» (teksthandling) |
| Tre forklarende tom-avsnitt i Bibliotek | `LibrarySidebarAndEmptyViews.swift#L110-L119` | Stryk |
| «Filmer (12)» | `LibrarySidebarAndEmptyViews.swift#L83-L86` | «Filmer» + tall-badge |
| «Ingenting passer akkurat disse filtrene.» | `CatalogBrowseView.swift#L263` | «Ingen treff med disse filtrene» |
| «Velg rom for denne Apple TV-en (oppdaterer LunaCore direkte)» | `SettingsComfortSectionView.swift#L18` | Stryk |
| «Aktivt rom» (to steder) | `SettingsComfortSectionView.swift#L12-L15`, `SettingsServerDiagnosticsSectionView.swift#L29-L32` | Stryk |
| «Aktiv» | `SettingsComponents.swift#L125` | Stryk (`checkmark`) |
| «Aktiv tvOS-videomodus nå» | `SettingsComfortSectionView.swift#L91` | «Skjermen støtter» |
| «Starter neste episode automatisk når episoden er helt ferdig» | `SettingsComfortSectionView.swift#L183` | Stryk |
| «Sanntids bilde-, lyd- og bufferoversikt under avspilling» | `SettingsAdvancedSectionView.swift#L79` | Stryk |
| Lange lyd-/lydsynk-forklaringer | `SettingsAdvancedSectionView.swift#L28`, `#L48` | Én datalinje (I9) |
| «Hjemmekino for LunaCore · Dolby Vision og romtilpasset lyd» | `PairingOnboardingView.swift#L29` | Stryk |
| «· {fordel}» i Fortsett-undertittel | `BackdropCardView.swift#L220-L228` | Stryk |
| «Neste for deg» (tekst) | `EpisodeCardView.swift#L138` | `LunaArtBadge` «Neste» |
| «Sett» (tekst + 100 %-linje) | `EpisodeCardView.swift#L66-L78`, `#L132-L135` | Hake-badge |
| «Ingen undertekster» | `PlayerQuickPanelView.swift#L270` | Stryk |
| «MetalFX» / «•» som badge | `PlayerBottomBarView.swift#L213-L222` | Stryk / prikk |
| «Trykk for å spille herfra · Meny avbryter» | `PlayerBottomBarView.swift#L497` | «Klikk for å spille herfra» |
| «▲ Hopp over intro» / «▲ Start på nytt» | `SeriesFlowOverlays.swift#L331`, `#L423` | Fast etikett uten «▲» |
| «Teknisk oversikt · {rom}» | `NerdHUDView.swift#L19` | «Teknisk oversikt» |
