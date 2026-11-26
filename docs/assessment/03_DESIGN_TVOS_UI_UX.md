# Vedlegg 3: Design og 10-foot tvOS UI/UX (Lampelys)

> **Dimensjonsvekt:** 25 %  
> **Overordnet mål:** Verifisere at `Luna v3.0.0` innfrir Lampelys 10-foot UI/UX-standarden (`docs/LUNA_TVOS_LAMPELYS_REVIEW.md` §2, §4, §6, §8), `design/tokens.json` (`v2.0.0`) og `AGENTS.md` §6 på tvers av LG OLED (`dv-fel-714`) i mørkt rom og Samsung The Frame (`hdr10-512`) i dagslys, med entydig Siri Remote-fokus på 3 meters avstand.

---

## 1. Designsysteminventar og utgangspunkt (`v3.0.0` vs. Lampelys)

`docs/LUNA_TVOS_LAMPELYS_REVIEW.md` definerte den kanoniske tvOS-standarden og faseplanen F1–F8 mot `v2.9.0`. På `v3.0.0` finnes `design/tokens.json` (`"version": "2.0.0"`), generert `LunaTokens.swift` og `preview/tokens.css`, samt F2-primitivene (`LunaBadges.swift`, `LunaListRow.swift`, `LunaSheetContainer.swift`, `LunaInlineStateViews.swift`). Vurderingen skal derfor kontrollere at **hele `v3.0.0`-flaten** oppfyller den kanoniske standarden og at ingen F3–F8-rester eller lokale avvik gjenstår:

- **Token-kjede:** `design/tokens.json` -> `ops/bin/luna-design-tokens` -> `Sources/DesignSystem/Tokens/LunaTokens.swift` + `preview/tokens.css` (verifisert via SHA-256).
- **Kjernekomponenter (`Sources/DesignSystem/`, 16 filer):** `Tokens/LunaTokens`, `LunaTheme`, `LunaThemeTypography`, `LunaFocusStyle`, `LunaPillButton`, `LunaTextField`, `LunaBadges`, `LunaListRow`, `LunaSheetContainer`, `LunaInlineStateViews`, `LunaCrescentMarkView`, `LunaCopy`, `AmbientBackdropView`, `CachedArtworkView`, `Cards/PosterCardView`, `Cards/BackdropCardView`.
- **Skjermflater (10 områder):** App-rot & Toppbar, Onboarding/Paring, Hjem, Katalog (`Filmer`/`Serier` + `CustomRowBrowseView`), Bibliotek (`Bibliotek` + `Lister`), Søk, Detalj (+ 5 ark), Innstillinger (5 kategorier) og Spiller (+ OSD, scrub-boble, 5 hurtigpanelfaner, serieflyt, teppe, NerdHUD, feiloverlegg).

---

## 2. Vurderingsområder og kriterier

### 2.1 Tokens, fargeatmosfære og 10-foot typografi
- **Hva som vurderes:** Deterministisk token-synk, OLED-trygg palett (`#0A0908` lerret, `#000000` `pureBlack`, `#120F0D @ 92%` `cinemaGlass`, romatmosfærene `.cinema` `dv-fel-714` / `.living` `hdr10-512` / `.neutral`) og streng typografisk disiplin.
- **Kritiske krav:**
  - `design/tokens.json` inneholder ingen `*Legacy`-nøkler og er i 100 % SHA-256-synk med `LunaTokens.swift` og `preview/tokens.css`.
  - `LunaTheme.Font.allFixedPointSizes` (`22` definerte roller: `9` kanoniske tekstroller `heroSerif 64`, `titleSerif 46`, `pageTitle 40`, `sectionTitle 34`, `cardTitle 29`, `body 29`, `subtitle 25`, `caption 23`, `badge 22` + `13` ikon-/pille-/paringsroller) ligger samtlige `>= 22.0 pt`.
  - Null forekomster av rå `.font(.caption/...)`, `.font(.system(size:...))` utenfor `LunaThemeTypography.swift`, `.uppercased()`, `.tracking(...)` på synlig UI-tekst, eller kalde system-blurs (`.ultraThinMaterial` o.l.).

### 2.2 Lampelys «Én app, én hånd» (8 grunnregler)
Vurderingen skal verifisere hver enkelt av de 8 kanoniske reglene fra `LUNA_TVOS_LAMPELYS_REVIEW.md` §2.1 på tvers av `Sources/Features/**` og `Sources/App/**`:
1. **Gull betyr fokus:** `playFocusGradient` brukes kun på kontrollen med Siri Remote-fokus; ufokusert primærknapp skiller seg ut med gullikon, semibold-etikett, tynn `Accent.border`-hårstrek og plassering først — aldri gullfyll i hvile.
2. **Maks én ramme:** Side -> gruppe/ark (`Surface.lv1` / `Surface.sheet` / `Surface.glass`); ingen indre flater eller `strokeBorder` i hvile på kort, listegrupper, rader, hurtigpanelflater eller statuspiller (unntak: kunst, fokus, primær hårstrek og `LunaTextField`).
3. **Maks én badge per kort eller rad:** Kun for unntak (`LunaArtBadge` øverst til venstre, `14 pt` fra kant). Tekniske formater er ren tekst skilt med ` · ` (`maks 3`), lagringsnivå er `8 pt` `LunaTierDotView` i undertekstlinjen (ikke skive oppå kunst), og fremdrift vises kun for `2% < p < 95%`.
4. **Ingen forklarende undertitler:** Undertekst kun for data (verdi, utstyr, språk/format), én linje, maks ~60 tegn. Full gjennomgang mot stryklisten i §8.
5. **Romnavnet vises kun i toppbaren (`LunaTopBarView`) og romvelgeren (`SettingsComfortSectionView`).**
6. **Sidetittel kun når toppbaren er skjult:** Rotfaner (*Hjem · Filmer · Serier · Bibliotek · Søk · Innstillinger*) har ingen sidetittel; undersider bruker `pageTitle` (`40 pt`) ved `subpageTop` (`60 pt`).
7. **Inngang på `x = 90`:** Pil ned fra toppbaren lander på første kontroll ved venstre sidemarg; tomme tilstander (`LunaEmptyState`) og feil (`LunaInlineError`) er venstrejusterte ved `x = 90` (ingen sentrerte avsnitt uten fokusmål).
8. **Tekst endrer seg aldri ved fokus:** Etikett, bredde og linjebryting er identiske i hvile og fokus (f.eks. `SeriesSkipPromptPillView` med reservert plass for chevron, `EpisodeCardView` med reservert to-linjers høyde).

### 2.3 Overscan safe-zones (`90×60`), rutenett og vertikal rytme
- **Hva som vurderes:** At `1920×1080 pt` (`4K = @2x`) overholder action-safe marginer på alle skjermer og at fokusvekst aldri klipper.
- **Kritiske mål (`design/tokens.json` -> `platform.tvos.dimensions`):**
  - Horisontal marg `gutter = 90`, `safeTop = 60`, `safeBottom = 60`, `contentTop = 162`, `subpageTop = 60`.
  - Vertikale mellomrom: `sectionGap = 32`, `headerGap = 16`, `blockGap = 24`, `gridRowGap = 32`.
  - Kortdimensjoner: hylleplakat `280×420` (`cardGap 40`), 6-kolonners rutenett `260×390` (`gridCardGap 36`; `6×260 + 5×36 = 1740 = 1920 − 2×90`), backdrop `520×293`, episode `420×236`.
  - Kontroller og flater: `controlH = 56`, `compactControlH = 48`, `iconButton = 56`, `listRowPadX/Y/MinH = 24/16/72`, `sheetPadding = 48`, arkbredder `880` / `1240`, hurtigpanelbredder `740` / `920`.
  - `1.05x` fokusskalering på `260 pt`-kort gir `6.5 pt` vekst per side (`x = 83.5 > 60`), og alle horisontale rader bruker `.scrollClipDisabled()`.

### 2.4 Fokusarkitektur, Liquid Glass-beskyttelse og Siri Remote-navigasjon
- **Hva som vurderes:** Én felles fokusmotor, fravær av tvOS 26 Liquid Glass-haloer over video og feilfri fjernkontrollnavigasjon.
- **Kritiske kodepunkter:**
  - `LunaFocusStyle`: nøyaktig tre fokusskalaer (`.card 1.05` + `2.0 pt` `85%` gullkant + romglød `30/12`, `.control 1.04` + `playFocusGradient`, `.listRow 1.0` + `surfaceSelected` + `3 pt` gull venstremarkør) og felles fjær (`0.32 / 0.86`) + `focusSelectDebounceMs = 180`.
  - `LunaTextField` (`NonFocusableTVTextField`): eliminerer hvite `UITextField`-fokuskapsler ved paring og søk.
  - Spillerfokus: ingen SwiftUI `Menu` eller ufokusert/halo-aktivert fullskjerms-`Button` over `AetherPlayerSurface`; kun `SiriRemoteTouchSurface` (`.focusEffectDisabled()`), `PlayerBottomBarView` og `PlayerQuickPanelView`.
  - Fokusbroer og kommandoer: `TopBarFocusBridge` (`Opp` -> `selectedTab`, `Ned` -> `x=90`), `MountedEntryCardTracker` når indeks `0` er rullet av skjermen, `.onMoveCommand(.down)` på filterstriper/søkefelt, `.onPlayPauseCommand` snarvei på kort/hero/episoder, `.onExitCommand` på alle `LunaSheetContainer`-ark, toppbar-oppvåkning og 6-stegs Meny-stige i spilleren (`PlayerTimelinePolicy.resolveExitAction`).

### 2.5 Skjerm-for-skjerm paritet og visuell verifisering
Vurderingen skal dekke alle 10 skjermgrupper samt de 20 `--preview-screen`-målene (`PreviewLaunchConfiguration.swift`) og `preview/index.html`:
- **Skjermgrupper:** (1) App-skall & `LunaTopBarView`, (2) `PairingOnboardingView`, (3) `HomeView` + `ShelfRowView` (`showRestingTitle: false` på hylle), (4) `CatalogBrowseView` + `CatalogFilterBarView` + `CustomRowBrowseView`, (5) `LibraryHubView` (`Filmer · Serier · Huskeliste · Lister`), (6) `SearchView`, (7) `MediaDetailView` + `DetailHeroHeaderView` + `DetailSeasonsSectionView` + 5 ark (`SourcePickerSheetView`, `DetailSeasonPickerSheetView`, `DetailMoreSheetView`, `DetailOverviewSheetView`, `DetailDeleteSheetView`), (8) `SettingsView` (5 kategorier + `320 pt` sidemeny), (9) `PlayerContainerView` + alle spilleroverlegg, (10) Delte tilstander (`LunaLoadingRow`, `LunaEmptyState`, `LunaInlineError`, `LunaToast`, `PlayerStatusPill`).

---

## 3. Sjekkliste for vurdering av design og 10-foot UI/UX

- [ ] **Token- & typografiparitet:** `./ops/bin/luna-design-tokens --check` og `./ops/bin/luna-check --local` passerer (`0` legacy-nøkler, SHA-256-synk, `>= 22 pt` på alle `22` fontroller, `0` rå `.font(...)` eller kalde `*Material`).
- [ ] **Forbudt styling & tekststøy:** `rg "scaleEffect\(" Sources/Features Sources/App`, `rg "\.uppercased\(\)|\.tracking\(" Sources/`, og `rg "strokeBorder\(" Sources/Features` gir kun godkjente treff i tråd med `LUNA_TVOS_LAMPELYS_REVIEW.md` §6.
- [ ] **Gull = fokus & maks én ramme:** Ingen ufokusert kontroll bruker `playFocusGradient`; `amber` brukes kun for fokus, primærikon, valgt `checkmark`, fremdrift og scrubbing; ingen boks-i-boks i Innstillinger, ark eller hurtigpanel.
- [ ] **Romnavn & sidetitler:** `roomName` i `Text(...)` forekommer kun i `LunaTopBarView` og `SettingsComfortSectionView`; rotfaner mangler sidetittel; undersider starter på `subpageTop = 60`.
- [ ] **Kort & badges:** `PosterCardView` (`280×420` hylle uten hviletittel / `260×390` rutenett med hviletittel), `BackdropCardView` (`520×293`), `EpisodeCardView` (`420×236`), maks én `LunaArtBadge` øverst til venstre, `LunaTierDotView` utenpå tekstlinje (ikke oppå kunst), fremdrift kun for `2% < p < 95%`.
- [ ] **Fokusbroer & Siri Remote:** Alle skjermer følger fokustabellen i `LUNA_TVOS_LAMPELYS_REVIEW.md` §4; ingen tom tilstand er uten fokusmål; `onExitCommand` lukker ark og følger 6-stegs Meny-stige i spiller; `LunaTextField` gir ikke hvit fokusramme.
- [ ] **Focus Sandbox (`preview/`):** `./scripts/preview-capture.sh` genererer 9 feilfrie `1920×1080` PNG-er med `?guides=1`; interaktiv piltast- og `G`-guide-kontroll viser `0` klipping mot `90×60` safe-zone.
- [ ] **tvOS Simulator Vision (`tvos-vision.yml`):** Alle 21 Simulator-renders (`20` `--preview-screen` + `search --preview-focus select`) er visuelt inspisert uten tekstkollisjon, subtitle-overlapp, feil fokusring eller Liquid Glass-utvasking.

---

## 4. Verifiseringsmetoder for Dimensjon 3

| Nivå | Konkret kommando / fremgangsmåte | Forventet evidens |
| :--- | :--- | :--- |
| **Nivå 1 (Statisk)** | `./ops/bin/luna-check --local`; `./ops/bin/luna-design-tokens --check`; `rg`-kjøringene fra `LUNA_TVOS_LAMPELYS_REVIEW.md` §6 | `sha256` token-paritet grønn; `0` ulovlige `scaleEffect`, `strokeBorder`, `.uppercased()`, `.tracking(`, rå `.font(` eller `*Material` |
| **Nivå 3 (Focus Sandbox)** | `./scripts/preview-capture.sh` -> inspisere alle 9 PNG-er i `.ci-screenshots/local-preview/`; interaktiv `preview/index.html?guides=1` piltast-test | Verifisert `90×60`-klaring, 6-kolonners `1740 pt`-rutenett, fokusoverganger og panelbredder på `1920×1080` |
| **Nivå 3 (tvOS Tester & Vision)** | `build-tvos.yml` (`DesignTokensAndCopyTests`, `ThemeAndArtworkViewTests`, `LunaNavigationAndDetailRaceTests`, `AppPolishAndDetailZeroRTTTests`, `PlayerOverlayAndCacheTests`, `PlayerSeriesCurtainAndSubtitleTests`); `tvos-vision.yml` (`gh run download -n tvos-screenshots`) | Alle 21 ekte tvOS 26 Simulator-PNG-er visuelt inspisert og godkjent |
| **Nivå 4 (Fysisk TV-panel)** | Visuell sjekk på LG OLED (`dv-fel-714`) i mørkt rom og Samsung The Frame (`hdr10-512`) i dagslys på 3 m avstand | `2 pt / 85%` kortkant og gullfokus er tydelige i begge lysmiljøer; ingen OLED-brenning på pauserte skjermer (`12 s` pausehvile) |
