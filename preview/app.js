(function () {
  const stage = document.getElementById('tvos-stage');
  const guides = document.getElementById('overscan-guides');
  const guideBtn = document.getElementById('toggle-guides-btn');
  const focusHud = document.getElementById('focus-hud');
  const params = new URLSearchParams(window.location.search);

  function fitViewport() {
    const sx = window.innerWidth / 1920;
    const sy = window.innerHeight / 1080;
    const scale = Math.min(1, sx, sy);
    stage.style.transform = scale < 0.999 ? `scale(${scale})` : 'none';
  }
  window.addEventListener('resize', fitViewport);
  fitViewport();

  let currentScreen = params.get('screen') || 'home';
  let currentLibraryFilter = 'movies';
  let currentLibraryTier = 'all';
  let currentLibrarySort = 'recent';
  let currentSearchKind = 'all';
  let activeQuickPanel = null;
  let focusedEl = null;

  const LIBRARY_SORT_LABELS = {
    recent: '⇅ Nylig lagt til',
    rating: '⇅ Høyest vurdert',
    title: '⇅ Alfabetisk'
  };

  const METALFX_DESCRIPTIONS = {
    off: 'Standard tvOS-skalering uten MetalFX.',
    auto: 'MetalFX for < 1080p SDR · 4K og HDR urørt.',
    line_art: 'Anime4K 2× linjekunst for ≤ 1080p SDR.'
  };
  const comfortState = {
    lowResUpscaleMode: 'auto',
    upscalesFullHDVideo: true,
    showNerdHUD: false
  };

  const LIBRARY_ITEMS = {
    movies: [
      { title: 'Dune: Part Two', year: '2024 · ★ 8,5', art: 'art-ochre', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Nosferatu', year: '2024 · ★ 7,7', art: 'art-aubergine', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Blade Runner 2049', year: '2017 · ★ 8,0', art: 'art-teal', badge: 'I Arkiv', cls: 'tier-archive' },
      { title: 'Oppenheimer', year: '2023 · ★ 8,3', art: 'art-ochre', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Interstellar', year: '2014 · ★ 8,7', art: 'art-navy', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Arrival', year: '2016 · ★ 7,9', art: 'art-navy', badge: 'I Arkiv', cls: 'tier-archive' }
    ],
    series: [
      { title: 'Lykkeland', year: '2018 · ★ 8,1', art: 'art-ochre', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Severance', year: '2022 · ★ 8,7', art: 'art-navy', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Andor', year: '2022 · ★ 8,4', art: 'art-teal', badge: 'På NVMe', cls: 'tier-nvme' }
    ],
    watchlist: [
      { title: 'Dune: Part Two', year: '2024 · ★ 8,5', art: 'art-ochre', badge: 'På NVMe', cls: 'tier-nvme' },
      { title: 'Lykkeland', year: '2018 · ★ 8,1', art: 'art-ochre', badge: 'På NVMe', cls: 'tier-nvme' }
    ],
    lists: [
      { title: 'Nordisk spenning', subtitle: 'Serier', countText: '4 titler' },
      { title: 'Helgefilm · Sci-Fi', subtitle: 'Filmer', countText: '6 titler' }
    ]
  };

  const QUICK_PANELS = {
    subtitles: {
      title: 'Tekst', wide: false,
      rows: [
        { id: 'off', title: 'Av', sub: '', active: false },
        { id: 'nob', title: 'Norsk', sub: 'Innebygd i utgaven', active: true },
        { id: 'eng', title: 'Engelsk', sub: 'Fra egen tekstfil', active: false },
        { id: 'kveldslys', title: 'Kveldslys', sub: 'Varm 75 % (Standard)', active: true, keepOpen: true }
      ]
    },
    audio: {
      title: 'Lyd', wide: false,
      rows: [
        { id: 'eng', title: 'Engelsk', sub: 'TrueHD Atmos 7.1.4', active: true },
        { id: 'ref', title: 'Ren kino', sub: 'Ubehandlet dynamikk og objektlyd', active: true, keepOpen: true },
        { id: 'dialog', title: 'Dialogløft', sub: '+4 dB senterkanal', active: false, keepOpen: true }
      ]
    },
    source: {
      title: 'Utgave', wide: true,
      rows: [
        { id: 's1', title: 'Anbefalt · 4K HDR10+ TrueHD Atmos', sub: 'Norsk · På NVMe · HEVC · 58,4 GB · Spilles nå · FraMeSToR · DV P7 FEL', active: true },
        { id: 's2', title: '4K Dolby Vision Dolby Atmos', sub: 'Strømmes ved start · HEVC · 21,6 GB · FLUX · DDP Atmos', active: false },
        { id: 's3', title: '1080p Dolby Digital+ 5.1', sub: 'I Arkiv · HEVC · 6,2 GB · CtrlHD · Tapsfri lyd', active: false }
      ]
    },
    chapters: {
      title: 'Kapitler', wide: false,
      rows: [
        { id: 'c1', title: 'Prolog', sub: '', trailing: '00:00', active: false },
        { id: 'c2', title: 'Introduksjon', sub: 'Spilles nå', trailing: '04:00', active: true },
        { id: 'c3', title: 'Hjemreise', sub: '', trailing: '05:20', active: false }
      ]
    }
  };

  function getQuickPanelSpec(panelKey) {
    if (panelKey === 'picture') {
      return {
        title: 'Bilde',
        wide: false,
        rows: [
          {
            id: 'off',
            title: 'MetalFX: Av',
            sub: METALFX_DESCRIPTIONS.off,
            active: comfortState.lowResUpscaleMode === 'off',
            keepOpen: true
          },
          {
            id: 'auto',
            title: 'MetalFX: Auto',
            sub: METALFX_DESCRIPTIONS.auto,
            active: comfortState.lowResUpscaleMode === 'auto',
            keepOpen: true
          },
          {
            id: 'line_art',
            title: 'MetalFX: Animasjon',
            sub: METALFX_DESCRIPTIONS.line_art,
            active: comfortState.lowResUpscaleMode === 'line_art',
            keepOpen: true
          },
          {
            id: 'lanczos',
            title: '1080p SDR → 4K (Lanczos)',
            sub: comfortState.lowResUpscaleMode === 'line_art'
              ? 'Overstyres av Animasjon (Anime4K 2×)'
              : '',
            toggle: true,
            on: comfortState.upscalesFullHDVideo,
            keepOpen: true,
            dividerAfter: true
          },
          {
            id: 'hud',
            title: 'Teknisk oversikt',
            sub: '',
            toggle: true,
            on: comfortState.showNerdHUD,
            keepOpen: true
          }
        ]
      };
    }
    return QUICK_PANELS[panelKey] || null;
  }

  function syncSettingsComfortUI() {
    const metalfxSub = document.getElementById('settings-metalfx-sub');
    if (metalfxSub) {
      metalfxSub.textContent = METALFX_DESCRIPTIONS[comfortState.lowResUpscaleMode] || METALFX_DESCRIPTIONS.auto;
    }
    document.querySelectorAll('[data-metalfx-mode]').forEach((btn) => {
      btn.classList.toggle('is-selected', btn.dataset.metalfxMode === comfortState.lowResUpscaleMode);
    });
    const lanczosRow = document.getElementById('settings-lanczos-row');
    if (lanczosRow) {
      lanczosRow.setAttribute('aria-pressed', comfortState.upscalesFullHDVideo ? 'true' : 'false');
    }
    const lanczosSub = document.getElementById('settings-lanczos-sub');
    if (lanczosSub) {
      lanczosSub.textContent = comfortState.lowResUpscaleMode === 'line_art'
        ? 'Overstyres av Animasjon (Anime4K 2×)'
        : 'Skalerer 1080p SDR til 4K · 4K og HDR urørt';
    }
    const lanczosVal = document.getElementById('settings-lanczos-value');
    if (lanczosVal) {
      lanczosVal.textContent = comfortState.upscalesFullHDVideo ? 'På' : 'Av';
      lanczosVal.classList.toggle('is-on', comfortState.upscalesFullHDVideo);
    }
  }

  function renderLibraryGrid() {
    const container = document.getElementById('library-grid-container');
    if (!container) return;
    let items = (LIBRARY_ITEMS[currentLibraryFilter] || []).slice();
    const supportsTierSort = currentLibraryFilter === 'movies' || currentLibraryFilter === 'series';
    if (supportsTierSort && currentLibraryTier !== 'all') {
      items = items.filter((item) => item.cls === `tier-${currentLibraryTier}`);
    }
    if (supportsTierSort && currentLibrarySort === 'title') {
      items.sort((a, b) => a.title.localeCompare(b.title, 'nb'));
    } else if (supportsTierSort && currentLibrarySort === 'rating') {
      items.reverse();
    }
    if (currentLibraryFilter === 'lists') {
      container.className = 'library-lists-wrap';
      container.innerHTML = `
        <div class="list-group">
          ${items.map((list, idx) => `
            <button class="quick-row" data-focusable="true" data-action="open-catalog" data-label="${list.title}">
              <div>
                <div class="quick-row-title">${list.title}</div>
                ${list.subtitle ? `<div class="quick-row-sub">${list.subtitle}</div>` : ''}
              </div>
              <div style="display:flex;align-items:center;gap:14px;">
                <span class="section-sub">${list.countText}</span>
                <span class="section-sub">›</span>
              </div>
            </button>
            ${idx < items.length - 1 ? '<div class="settings-divider"></div>' : ''}
          `).join('')}
        </div>
      `;
    } else {
      container.className = 'library-grid';
      container.innerHTML = items.map((item) => `
        <div class="poster-slot grid-poster">
          <article class="poster-card ${item.art}" data-focusable="true" data-action="open-details" data-label="${item.title}"></article>
          <div class="poster-grid-caption">
            <div class="poster-caption-title">${item.title}</div>
            <div class="poster-caption-meta card-subtitle"><span class="tier-dot ${item.cls === 'tier-nvme' ? 'nvme' : 'archive'}"></span>${item.year}</div>
          </div>
        </div>
      `).join('');
    }
    document.querySelectorAll('[data-lib-filter]').forEach((btn) => {
      const active = btn.dataset.libFilter === currentLibraryFilter;
      btn.classList.toggle('is-selected', active);
    });
    document.querySelectorAll('[data-lib-tier]').forEach((btn) => {
      btn.style.display = supportsTierSort ? '' : 'none';
      btn.classList.toggle('is-selected', btn.dataset.libTier === currentLibraryTier);
    });
    document.querySelectorAll('[data-lib-sort]').forEach((btn) => {
      btn.style.display = supportsTierSort ? '' : 'none';
      btn.textContent = LIBRARY_SORT_LABELS[currentLibrarySort] || LIBRARY_SORT_LABELS.recent;
      btn.classList.toggle('is-selected', currentLibrarySort !== 'recent');
    });
    const libDiv = document.querySelector('#screen-library .filter-divider');
    if (libDiv) libDiv.style.display = supportsTierSort ? '' : 'none';
  }

  function openQuickPanel(panelKey, preferredFocusRowId = null) {
    const spec = getQuickPanelSpec(panelKey);
    const panelEl = document.getElementById('player-quick-panel');
    const cueEl = document.getElementById('player-subtitle-cue');
    if (!spec || !panelEl) return;
    activeQuickPanel = panelKey;
    const panelWidth = spec.wide ? 920 : 740;
    panelEl.style.width = `${panelWidth}px`;
    const triggerBtn = document.querySelector(`#screen-player [data-quick-panel="${panelKey}"]`);
    const triggerX = triggerBtn ? triggerBtn.offsetLeft : 90;
    const clampedX = Math.max(90, Math.min(1920 - 90 - panelWidth, triggerX));
    panelEl.style.left = `${clampedX}px`;
    panelEl.className = `player-quick-panel focus-section is-open${spec.wide ? ' is-wide' : ''}`;
    if (cueEl) cueEl.classList.add('is-relocated');
    panelEl.innerHTML = `
      <div class="quick-panel-header">
        <span class="quick-row-title" style="color: var(--text-secondary);">${spec.title}</span>
      </div>
      ${spec.rows.map((r) => `
        <button class="quick-row${r.active ? ' is-active' : ''}" data-focusable="true" data-quick-row="${r.id}" data-keep-open="${r.keepOpen ? '1' : '0'}"${r.toggle ? ` aria-pressed="${r.on ? 'true' : 'false'}"` : ''}>
          <div>
            <div class="quick-row-title">${r.title}</div>
            ${r.sub ? `<div class="quick-row-sub">${r.sub}</div>` : ''}
          </div>
          <div style="display:flex;align-items:center;gap:12px;">
            ${r.toggle
              ? `<span class="quick-row-value${r.on ? ' is-on' : ''}">${r.on ? 'På' : 'Av'}</span>`
              : `${r.trailing ? `<span class="section-sub">${r.trailing}</span>` : ''}${r.active ? '<span class="quick-row-check">✓</span>' : ''}`}
          </div>
        </button>
        ${r.dividerAfter ? '<div class="quick-panel-divider"></div>' : ''}
      `).join('')}
    `;
    const preferredBtn = preferredFocusRowId
      ? panelEl.querySelector(`[data-quick-row="${preferredFocusRowId}"]`)
      : null;
    const activeBtn = preferredBtn || panelEl.querySelector('.quick-row.is-active') || panelEl.querySelector('.quick-row');
    if (activeBtn) setFocus(activeBtn);
  }

  function closeQuickPanel(returnToPill) {
    const prev = activeQuickPanel;
    activeQuickPanel = null;
    const panelEl = document.getElementById('player-quick-panel');
    const cueEl = document.getElementById('player-subtitle-cue');
    if (cueEl) cueEl.classList.remove('is-relocated');
    if (panelEl) {
      panelEl.classList.remove('is-open');
      panelEl.innerHTML = '';
    }
    if (returnToPill && prev) {
      const pill = document.querySelector(`#screen-player [data-quick-panel="${prev}"]`);
      if (pill) setFocus(pill);
    }
  }

  function setGuidesVisible(visible) {
    guides.classList.toggle('is-visible', visible);
    guideBtn.classList.toggle('active', visible);
  }

  if (params.get('guides') === '1') {
    setGuidesVisible(true);
  }
  guideBtn.addEventListener('click', () => {
    setGuidesVisible(!guides.classList.contains('is-visible'));
  });

  function visibleFocusables() {
    return Array.from(stage.querySelectorAll('[data-focusable="true"]')).filter((el) => {
      const parentScreen = el.closest('.screen');
      if (parentScreen && !parentScreen.classList.contains('is-visible')) return false;
      if (activeQuickPanel && currentScreen === 'player') {
        return !!el.closest('#player-quick-panel');
      }
      if (el.closest('#player-quick-panel') && !activeQuickPanel) return false;
      return true;
    });
  }

  function setFocus(el) {
    if (!el) return;
    if (focusedEl) focusedEl.classList.remove('is-focused');
    focusedEl = el;
    focusedEl.classList.add('is-focused');
    const topBar = document.querySelector('.top-bar');
    const inTopBar = !!focusedEl.closest('.top-bar');
    if (topBar) topBar.classList.toggle('has-focus', inTopBar);
    const activeScreenEl = document.getElementById(`screen-${currentScreen}`);
    if (activeScreenEl) {
      if (inTopBar) {
        activeScreenEl.scrollLeft = 0;
      } else {
        const shelfRow = focusedEl.closest('.shelf-row');
        if (shelfRow && shelfRow.offsetLeft + shelfRow.offsetWidth <= activeScreenEl.clientWidth) {
          activeScreenEl.scrollLeft = 0;
        }
      }
    }
    const slot = focusedEl.closest('.poster-slot') || focusedEl;
    slot.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    const label = focusedEl.dataset.label || focusedEl.textContent.trim().slice(0, 38);
    focusHud.textContent = `Safe-Zone 90×60px · Screen: ${currentScreen} · Fokus: ${label}`;
  }

  function switchScreen(nextScreen, focusContentTarget = true, keepTopBarFocus = false) {
    if (!['home', 'catalog', 'library', 'search', 'details', 'settings', 'player'].includes(nextScreen)) {
      nextScreen = 'home';
    }
    if (nextScreen !== 'player') closeQuickPanel(false);
    currentScreen = nextScreen;
    stage.dataset.activeScreen = nextScreen;
    const topBar = document.querySelector('.top-bar');
    if (topBar) topBar.style.display = nextScreen === 'player' ? 'none' : 'flex';
    document.querySelectorAll('.screen').forEach((sc) => {
      sc.classList.toggle('is-visible', sc.id === `screen-${nextScreen}`);
    });
    document.querySelectorAll('.nav-tab, .nav-icon-btn').forEach((tab) => {
      tab.classList.toggle('is-active', tab.dataset.targetScreen === nextScreen);
    });
    if (nextScreen === 'library') renderLibraryGrid();
    if (focusContentTarget && !keepTopBarFocus) {
      const firstInScreen = nextScreen === 'player'
        ? document.querySelector('#screen-player [data-quick-panel="subtitles"]')
        : (document.querySelector(`#screen-${nextScreen} [data-entry-default="true"]`)
            || document.querySelector(`#screen-${nextScreen} [data-focusable="true"]`));
      if (firstInScreen) setFocus(firstInScreen);
    } else if (topBar && keepTopBarFocus) {
      topBar.classList.add('has-focus');
    }
  }

  function moveSpatialFocus(direction) {
    if (activeQuickPanel) {
      const rows = Array.from(document.querySelectorAll('#player-quick-panel [data-focusable="true"]'));
      const idx = rows.indexOf(focusedEl);
      if (direction === 'ArrowDown' && idx >= 0 && idx + 1 < rows.length) setFocus(rows[idx + 1]);
      if (direction === 'ArrowUp' && idx > 0) setFocus(rows[idx - 1]);
      return;
    }
    const candidates = visibleFocusables();
    if (!candidates.length) return;
    if (!focusedEl || !candidates.includes(focusedEl)) {
      setFocus(candidates[0]);
      return;
    }
    const inTopBar = !!focusedEl.closest('.top-bar');
    if (inTopBar && (direction === 'ArrowLeft' || direction === 'ArrowRight')) {
      const tabs = Array.from(document.querySelectorAll('.top-bar [data-focusable="true"]'));
      const idx = tabs.indexOf(focusedEl);
      const nextIdx = direction === 'ArrowRight' ? Math.min(tabs.length - 1, idx + 1) : Math.max(0, idx - 1);
      const nextTab = tabs[nextIdx];
      if (nextTab) {
        if (nextTab.dataset.targetScreen) {
          switchScreen(nextTab.dataset.targetScreen, false, true);
        }
        setFocus(nextTab);
      }
      return;
    }
    if (inTopBar && direction === 'ArrowDown') {
      const entryTarget = document.querySelector(`#screen-${currentScreen} [data-entry-default="true"]`)
        || document.querySelector(`#screen-${currentScreen} [data-focusable="true"]`);
      if (entryTarget) setFocus(entryTarget);
      return;
    }
    const inSettingsSidebar = !!focusedEl.closest('.settings-sidebar');
    if (!inTopBar && direction === 'ArrowUp') {
      const screenCandidates = candidates.filter((el) => !el.closest('.top-bar'));
      const curRect = focusedEl.getBoundingClientRect();
      const hasContentAbove = screenCandidates.some((el) => {
        if (el === focusedEl) return false;
        if (inSettingsSidebar && !el.closest('.settings-sidebar')) return false;
        if (!inSettingsSidebar && el.closest('.settings-sidebar')) return false;
        return el.getBoundingClientRect().bottom <= curRect.top + 2;
      });
      if (!hasContentAbove) {
        if (currentScreen === 'player' || currentScreen === 'details') {
          return;
        }
        const activeTab = document.querySelector(`.top-bar [data-target-screen="${currentScreen}"]`) || document.querySelector('.top-bar .is-active');
        if (activeTab) {
          setFocus(activeTab);
          return;
        }
      }
    }

    const curRect = focusedEl.getBoundingClientRect();
    const cx = curRect.left + curRect.width / 2;
    const cy = curRect.top + curRect.height / 2;
    const isVertical = direction === 'ArrowUp' || direction === 'ArrowDown';

    const directional = [];
    for (const el of candidates) {
      if (el === focusedEl || (!inTopBar && el.closest('.top-bar'))) continue;
      const r = el.getBoundingClientRect();
      const ex = r.left + r.width / 2;
      const ey = r.top + r.height / 2;
      const dx = ex - cx;
      const dy = ey - cy;

      if (direction === 'ArrowRight' && dx <= 12) continue;
      if (direction === 'ArrowLeft' && dx >= -12) continue;
      if (direction === 'ArrowDown' && dy <= 18) continue;
      if (direction === 'ArrowUp' && dy >= -18) continue;

      const primary = isVertical ? Math.abs(dy) : Math.abs(dx);
      const ortho = isVertical ? Math.abs(dx) : Math.abs(dy);
      directional.push({ el, rect: r, cy: ey, primary, ortho, inSidebar: !!el.closest('.settings-sidebar') });
    }

    if (!directional.length) return;

    const sameRow = (c) =>
      Math.min(curRect.bottom, c.rect.bottom) > Math.max(curRect.top, c.rect.top);

    let pool = directional;
    if (isVertical) {
      pool = pool.filter((c) => (inSettingsSidebar ? c.inSidebar : !c.inSidebar));
      if (!pool.length) return;
      const minPrimary = Math.min(...pool.map((c) => c.primary));
      pool = pool.filter((c) => c.primary <= minPrimary + 48);
    } else if (currentScreen === 'settings') {
      if (inSettingsSidebar) {
        if (direction === 'ArrowLeft') return;
        pool = pool.filter((c) => !c.inSidebar);
        if (!pool.length) return;
        const rowMatches = pool.filter(sameRow);
        if (rowMatches.length) {
          pool = rowMatches;
        } else {
          const minDy = Math.min(...pool.map((c) => Math.abs(c.cy - cy)));
          pool = pool.filter((c) => Math.abs(c.cy - cy) <= minDy + 8);
        }
      } else if (direction === 'ArrowLeft') {
        const detailRowMatches = pool.filter((c) => !c.inSidebar && sameRow(c));
        if (detailRowMatches.length) {
          pool = detailRowMatches;
        } else {
          pool = pool.filter((c) => c.inSidebar);
          if (!pool.length) return;
          const sidebarRowMatches = pool.filter(sameRow);
          if (sidebarRowMatches.length) {
            pool = sidebarRowMatches;
          } else {
            const minDy = Math.min(...pool.map((c) => Math.abs(c.cy - cy)));
            pool = pool.filter((c) => Math.abs(c.cy - cy) <= minDy + 8);
          }
        }
      } else {
        pool = pool.filter((c) => !c.inSidebar && sameRow(c));
        if (!pool.length) return;
      }
    } else {
      pool = pool.filter(sameRow);
      if (!pool.length) return;
    }

    let best = null;
    let bestScore = Infinity;
    for (const c of pool) {
      const score = c.primary + c.ortho * 2.6;
      if (score < bestScore) {
        bestScore = score;
        best = c.el;
      }
    }
    if (best) setFocus(best);
  }

  function activateFocused() {
    if (!focusedEl) return;
    if (focusedEl.dataset.metalfxMode) {
      comfortState.lowResUpscaleMode = focusedEl.dataset.metalfxMode;
      syncSettingsComfortUI();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.settingToggle === 'lanczos') {
      comfortState.upscalesFullHDVideo = !comfortState.upscalesFullHDVideo;
      syncSettingsComfortUI();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.libFilter) {
      currentLibraryFilter = focusedEl.dataset.libFilter;
      renderLibraryGrid();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.libTier) {
      currentLibraryTier = focusedEl.dataset.libTier;
      renderLibraryGrid();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.libSort) {
      const order = ['recent', 'rating', 'title'];
      currentLibrarySort = order[(order.indexOf(currentLibrarySort) + 1) % order.length];
      renderLibraryGrid();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.searchKind) {
      currentSearchKind = focusedEl.dataset.searchKind;
      document.querySelectorAll('[data-search-kind]').forEach((btn) => {
        btn.classList.toggle('is-selected', btn.dataset.searchKind === currentSearchKind);
      });
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.quickPanel) {
      openQuickPanel(focusedEl.dataset.quickPanel);
      return;
    }
    if (focusedEl.dataset.quickRow) {
      const rowId = focusedEl.dataset.quickRow;
      if (activeQuickPanel === 'picture') {
        if (rowId === 'off' || rowId === 'auto' || rowId === 'line_art') {
          comfortState.lowResUpscaleMode = rowId;
        } else if (rowId === 'lanczos') {
          comfortState.upscalesFullHDVideo = !comfortState.upscalesFullHDVideo;
        } else if (rowId === 'hud') {
          comfortState.showNerdHUD = !comfortState.showNerdHUD;
        }
        syncSettingsComfortUI();
        openQuickPanel('picture', rowId);
        return;
      }
      if (focusedEl.dataset.keepOpen !== '1') {
        closeQuickPanel(true);
      }
      return;
    }
    if (focusedEl.dataset.targetScreen) {
      switchScreen(focusedEl.dataset.targetScreen, true);
      return;
    }
    if (focusedEl.dataset.action === 'open-catalog') {
      switchScreen('catalog', true);
      return;
    }
    if (focusedEl.dataset.action === 'open-details') {
      switchScreen('details', true);
      return;
    }
    if (focusedEl.dataset.action === 'open-player') {
      switchScreen('player', true);
    }
  }

  stage.addEventListener('click', (e) => {
    const target = e.target.closest('[data-focusable="true"]');
    if (target) {
      setFocus(target);
      activateFocused();
    }
  });

  window.addEventListener('keydown', (e) => {
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
      e.preventDefault();
      moveSpatialFocus(e.key);
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      activateFocused();
    } else if (e.key === 'Escape' || e.key === 'Backspace') {
      e.preventDefault();
      if (currentScreen === 'player' && activeQuickPanel) {
        closeQuickPanel(true);
      } else if (currentScreen === 'player' || currentScreen === 'details') {
        switchScreen('home', true);
      } else {
        const screenEl = document.getElementById(`screen-${currentScreen}`);
        if (screenEl) screenEl.scrollTop = 0;
        const activeTab = document.querySelector(`.top-bar [data-target-screen="${currentScreen}"]`);
        setFocus(activeTab);
      }
    } else if (e.key === 'g' || e.key === 'G') {
      setGuidesVisible(!guides.classList.contains('is-visible'));
    }
  });

  document.body.classList.add('is-bootstrapping');
  syncSettingsComfortUI();
  const initialPanel = params.get('panel');
  const shouldOpenInitialPanel = currentScreen === 'player' && !!initialPanel && !!getQuickPanelSpec(initialPanel);
  switchScreen(currentScreen, !shouldOpenInitialPanel);
  if (shouldOpenInitialPanel) {
    openQuickPanel(initialPanel);
  }
  const initialFocusRaw = params.get('focus');
  if (initialFocusRaw) {
    const dirMap = {
      right: 'ArrowRight',
      left: 'ArrowLeft',
      down: 'ArrowDown',
      up: 'ArrowUp'
    };
    for (const step of initialFocusRaw.split(',')) {
      const arrow = dirMap[step.trim().toLowerCase()];
      if (arrow) moveSpatialFocus(arrow);
    }
  }
  void document.body.offsetWidth;
  document.body.classList.remove('is-bootstrapping');
})();
