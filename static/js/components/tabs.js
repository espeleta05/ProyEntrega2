/**
 * tabs.js — MD3 Tab manager
 *
 * Auto-init: cualquier .md3-tab-bar en el DOM.
 * Cada .md3-tab necesita data-target="panelId" para cambiar paneles.
 *
 * API:
 *   Tabs.init(barEl)               → inicia una barra específica
 *   Tabs.activate(tabEl)           → activa una tab por referencia
 *   Tabs.activateByIndex(barEl, n) → activa la n-ésima tab de una barra
 *
 * Evento: la tab activada dispara 'md3:tab:change' (bubbles)
 *   e.detail → { tab: Element, targetId: string }
 *
 * HTML:
 *   <div class="md3-tabs">
 *     <div class="md3-tab-bar" role="tablist">
 *       <button class="md3-tab active" data-target="panel-1" id="tab-1">Pacientes</button>
 *       <button class="md3-tab"        data-target="panel-2" id="tab-2">Vacunas</button>
 *     </div>
 *     <div class="md3-tab-panel active" id="panel-1">...</div>
 *     <div class="md3-tab-panel"        id="panel-2">...</div>
 *   </div>
 */
(function () {
  'use strict';

  // ── Activar una tab ────────────────────────────────────────────────────────
  function activate(tabEl) {
    const bar = tabEl.closest('.md3-tab-bar');
    if (!bar) return;

    // Desactivar todas las tabs de esta barra
    bar.querySelectorAll('.md3-tab').forEach((t) => {
      t.classList.remove('active');
      t.setAttribute('aria-selected', 'false');
      t.setAttribute('tabindex', '-1');
    });

    // Activar la elegida
    tabEl.classList.add('active');
    tabEl.setAttribute('aria-selected', 'true');
    tabEl.setAttribute('tabindex', '0');

    // Cambiar paneles
    const targetId = tabEl.dataset.target;
    if (targetId) {
      const container = bar.closest('.md3-tabs') || document;
      container.querySelectorAll('.md3-tab-panel').forEach((panel) => {
        panel.classList.toggle('active', panel.id === targetId);
        // Accesibilidad: ocultar paneles inactivos de lectores de pantalla
        panel.hidden = panel.id !== targetId;
      });
    }

    // Guardar en hash sólo si la tab tiene id
    if (tabEl.id && typeof history.replaceState === 'function') {
      history.replaceState(null, '', `#${tabEl.id}`);
    }

    // Evento personalizado
    tabEl.dispatchEvent(
      new CustomEvent('md3:tab:change', { bubbles: true, detail: { tab: tabEl, targetId } })
    );
  }

  // ── Activar por índice ─────────────────────────────────────────────────────
  function activateByIndex(barEl, index) {
    const tabs = barEl.querySelectorAll('.md3-tab');
    if (tabs[index]) activate(tabs[index]);
  }

  // ── Init una barra ─────────────────────────────────────────────────────────
  function initBar(bar) {
    if (bar._mdTabsInit) return;
    bar._mdTabsInit = true;

    const tabs = bar.querySelectorAll('.md3-tab');
    if (!tabs.length) return;

    // ARIA
    bar.setAttribute('role', 'tablist');
    tabs.forEach((tab, i) => {
      tab.setAttribute('role', 'tab');
      if (!tab.hasAttribute('aria-selected'))
        tab.setAttribute('aria-selected', tab.classList.contains('active') ? 'true' : 'false');
      if (!tab.hasAttribute('tabindex'))
        tab.setAttribute('tabindex', tab.classList.contains('active') ? '0' : '-1');
      const panelId = tab.dataset.target;
      if (panelId) tab.setAttribute('aria-controls', panelId);

      tab.addEventListener('click', () => activate(tab));
    });

    // Navegación con teclado: ← → para horizontal, ↑ ↓ para vertical
    bar.addEventListener('keydown', (e) => {
      const isVertical = bar.classList.contains('md3-tab-bar--vertical');
      const allTabs    = Array.from(tabs);
      const current    = bar.querySelector('.md3-tab.active');
      const idx        = allTabs.indexOf(current);
      if (idx < 0) return;

      let next;
      const fwd  = isVertical ? 'ArrowDown'  : 'ArrowRight';
      const back = isVertical ? 'ArrowUp'    : 'ArrowLeft';

      if (e.key === fwd)    next = allTabs[(idx + 1) % allTabs.length];
      else if (e.key === back) next = allTabs[(idx - 1 + allTabs.length) % allTabs.length];
      else if (e.key === 'Home') next = allTabs[0];
      else if (e.key === 'End')  next = allTabs[allTabs.length - 1];

      if (next) {
        e.preventDefault();
        activate(next);
        next.focus();
      }
    });

    // Restaurar desde hash de URL
    const hash = window.location.hash.slice(1);
    if (hash) {
      const hashTab = bar.querySelector(`#${CSS.escape(hash)}, [data-target="${CSS.escape(hash)}"]`);
      if (hashTab) { activate(hashTab); return; }
    }

    // Activar la primera si ninguna tiene .active
    const hasActive = bar.querySelector('.md3-tab.active');
    if (!hasActive) activate(tabs[0]);
  }

  // ── Auto-init + MutationObserver ──────────────────────────────────────────
  function init(scope = document) {
    scope.querySelectorAll('.md3-tab-bar').forEach(initBar);
  }

  const observer = new MutationObserver((mutations) => {
    mutations.forEach((m) =>
      m.addedNodes.forEach((node) => {
        if (node.nodeType !== 1) return;
        if (node.matches?.('.md3-tab-bar')) initBar(node);
        node.querySelectorAll?.('.md3-tab-bar').forEach(initBar);
      })
    );
  });

  document.addEventListener('DOMContentLoaded', () => {
    init();
    observer.observe(document.body, { childList: true, subtree: true });
  });

  // ── Global API ─────────────────────────────────────────────────────────────
  window.Tabs = { init: initBar, activate, activateByIndex };
})();
