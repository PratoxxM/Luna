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
  let activeQuickPanel = null;
  let focusedEl = null;

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
        { id: 's1', title: 'Anbefalt · 4K HDR10+ TrueHD Atmos', sub: 'Norsk · På NVMe · HEVC · Bluray-2160p · 58,4 GB · Spilles nå', active: true },
        { id: 's2', title: '4K Dolby Vision Dolby Atmos', sub: 'Strømmes ved start · HEVC · WEB-DL · 21,6 GB', active: false },
        { id: 's3', title: '1080p Dolby Digital+ 5.1', sub: 'I Arkiv · HEVC · WEB-DL · 6,2 GB', active: false }
      ]
    },
    picture: {
      title: 'Bilde', wide: false,
      rows: [
        { id: 'off', title: 'MetalFX: Av', sub: 'Standard tvOS-skalering uten MetalFX', active: false, keepOpen: true },
        { id: 'auto', title: 'MetalFX: Auto', sub: 'Kun < 1080p 8-bit SDR · 4K og HDR urørt', active: true, keepOpen: true },
        { id: 'line_art', title: 'MetalFX: Animasjon', sub: 'Anime4K 2× linjekunst for ≤ 1080p SDR', active: false, keepOpen: true },
        { id: 'hud', title: 'Teknisk oversikt', sub: '', active: false, keepOpen: true }
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

  function renderLibraryGrid() {
    const container = document.getElementById('library-grid-container');
    if (!container) return;
    const items = LIBRARY_ITEMS[currentLibraryFilter] || [];
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
          <article class="poster-card ${item.art}" data-focusable="true" data-action="open-details">
            <div class="poster-emblem">${item.title}</div>
          </article>
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
  }

  function openQuickPanel(panelKey) {
    const spec = QUICK_PANELS[panelKey];
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
        <button class="quick-row${r.active ? ' is-active' : ''}" data-focusable="true" data-quick-row="${r.id}" data-keep-open="${r.keepOpen ? '1' : '0'}">
          <div>
            <div class="quick-row-title">${r.title}</div>
            ${r.sub ? `<div class="quick-row-sub">${r.sub}</div>` : ''}
          </div>
          <div style="display:flex;align-items:center;gap:12px;">
            ${r.trailing ? `<span class="section-sub">${r.trailing}</span>` : ''}
            ${r.active ? '<span class="quick-row-check">✓</span>' : ''}
          </div>
        </button>
      `).join('')}
    `;
    const activeBtn = panelEl.querySelector('.quick-row.is-active') || panelEl.querySelector('.quick-row');
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
    if (topBar) topBar.classList.toggle('has-focus', !!focusedEl.closest('.top-bar'));
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
    if (!inTopBar && direction === 'ArrowUp') {
      const screenCandidates = candidates.filter((el) => !el.closest('.top-bar'));
      const curRect = focusedEl.getBoundingClientRect();
      const hasContentAbove = screenCandidates.some((el) => el !== focusedEl && el.getBoundingClientRect().bottom < curRect.top - 12);
      if (!hasContentAbove && currentScreen !== 'player' && currentScreen !== 'details') {
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

    let best = null;
    let bestScore = Infinity;

    for (const el of candidates) {
      if (el === focusedEl) continue;
      const r = el.getBoundingClientRect();
      const ex = r.left + r.width / 2;
      const ey = r.top + r.height / 2;
      const dx = ex - cx;
      const dy = ey - cy;

      if (direction === 'ArrowRight' && dx <= 12) continue;
      if (direction === 'ArrowLeft' && dx >= -12) continue;
      if (direction === 'ArrowDown' && dy <= 18) continue;
      if (direction === 'ArrowUp' && dy >= -18) continue;

      const primary = (direction === 'ArrowLeft' || direction === 'ArrowRight') ? Math.abs(dx) : Math.abs(dy);
      const ortho = (direction === 'ArrowLeft' || direction === 'ArrowRight') ? Math.abs(dy) : Math.abs(dx);
      const score = primary + ortho * 2.6;
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    }
    if (best) setFocus(best);
  }

  function activateFocused() {
    if (!focusedEl) return;
    if (focusedEl.dataset.libFilter) {
      currentLibraryFilter = focusedEl.dataset.libFilter;
      renderLibraryGrid();
      setFocus(focusedEl);
      return;
    }
    if (focusedEl.dataset.quickPanel) {
      openQuickPanel(focusedEl.dataset.quickPanel);
      return;
    }
    if (focusedEl.dataset.quickRow) {
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

  switchScreen(currentScreen, true);
  const initialPanel = params.get('panel');
  if (currentScreen === 'player' && initialPanel) {
    openQuickPanel(initialPanel);
  }
  const initialFocusDir = params.get('focus');
  if (initialFocusDir === 'right') moveSpatialFocus('ArrowRight');
  if (initialFocusDir === 'down') moveSpatialFocus('ArrowDown');
  if (initialFocusDir === 'up') moveSpatialFocus('ArrowUp');
})();
