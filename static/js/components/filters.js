/**
 * filters.js — MD3 Filter bar utilities
 *
 * Auto-init:
 *   • Añade/quita .has-value en .md3-filter-select cuando cambia su valor.
 *   • Carga el valor guardado en ?param=valor desde la URL al iniciar.
 *   • Wire clicks de .md3-filter-pill__remove y .md3-filter-clear-all.
 *
 * API:
 *   Filters.init(scopeEl?)          → re-inicia en un nodo (útil tras ajax)
 *   Filters.addPill(container, labelKey, labelValue, key, onRemove?)
 *   Filters.clearAll(pillsContainer)
 *   Filters.syncFromURL(scopeEl?)   → lee ?key=val y rellena los selects
 *   Filters.syncToURL(scopeEl?, replace?) → escribe ?key=val en la URL
 *
 * Convención: el select/input debe tener name="key" o data-filter="key"
 * para que syncFromURL/syncToURL funcionen.
 */
(function () {
  'use strict';

  // ── has-value en selects ──────────────────────────────────────────────────
  function syncSelectState(select) {
    // Tiene valor cuando no está vacío y no es el primer option vacío
    const empty = !select.value || select.value === (select.options[0]?.value ?? '');
    select.classList.toggle('has-value', !empty);
  }

  function initSelect(select) {
    if (select._mdFilterInit) return;
    select._mdFilterInit = true;
    syncSelectState(select);
    select.addEventListener('change', () => syncSelectState(select));
  }

  // ── Pills ──────────────────────────────────────────────────────────────────
  /**
   * Agrega una pill al container.
   * Si ya existe una con el mismo key, la reemplaza.
   */
  function addPill(container, labelKey, labelValue, key, onRemove) {
    if (!container) return null;

    // Quitar pill previa con igual key
    container.querySelector(`[data-filter-key="${CSS.escape(key)}"]`)?.remove();

    const pill = document.createElement('span');
    pill.className = 'md3-filter-pill';
    pill.dataset.filterKey = key;
    pill.innerHTML = `
      <span class="md3-filter-pill__label">${labelKey}:</span>
      ${labelValue}
      <button type="button" class="md3-filter-pill__remove" aria-label="Quitar filtro ${labelKey}">
        <i class="fa-solid fa-xmark"></i>
      </button>
    `;

    pill.querySelector('.md3-filter-pill__remove').addEventListener('click', () => {
      pill.remove();
      onRemove?.(key);
    });

    container.appendChild(pill);
    return pill;
  }

  function clearAll(container) {
    container?.querySelectorAll('.md3-filter-pill').forEach((p) => p.remove());
  }

  // ── Sync URL ───────────────────────────────────────────────────────────────
  function filterKey(el) {
    return el.dataset.filter || el.name || null;
  }

  function syncFromURL(scope = document) {
    const params = new URLSearchParams(window.location.search);
    scope
      .querySelectorAll('.md3-filter-select, .md3-filter-search__input, [data-filter], select[name], input[data-filter]')
      .forEach((el) => {
        const key = filterKey(el);
        if (!key) return;
        const val = params.get(key);
        if (val != null) {
          el.value = val;
          if (el.matches('select')) syncSelectState(el);
        }
      });
  }

  function syncToURL(scope = document, replace = false) {
    const params = new URLSearchParams(window.location.search);
    scope
      .querySelectorAll('.md3-filter-select, .md3-filter-search__input, [data-filter], select[name], input[data-filter]')
      .forEach((el) => {
        const key = filterKey(el);
        if (!key) return;
        el.value ? params.set(key, el.value) : params.delete(key);
      });

    const newUrl = `${window.location.pathname}?${params.toString()}`;
    replace
      ? history.replaceState(null, '', newUrl)
      : history.pushState(null, '', newUrl);
  }

  // ── Wire clear-all ─────────────────────────────────────────────────────────
  function wireClearAll(scope) {
    scope.querySelectorAll('.md3-filter-clear-all').forEach((btn) => {
      if (btn._mdFilterClearWired) return;
      btn._mdFilterClearWired = true;
      btn.addEventListener('click', () => {
        // Limpiar selects y search dentro del mismo filter-bar
        const bar = btn.closest('.md3-filter-bar') || document;
        bar.querySelectorAll('.md3-filter-select, .md3-filter-search__input').forEach((el) => {
          el.value = '';
          if (el.matches('select')) syncSelectState(el);
          el.dispatchEvent(new Event('change', { bubbles: true }));
          el.dispatchEvent(new Event('input',  { bubbles: true }));
        });
        // Limpiar pills
        const pillsContainer = bar.querySelector('.md3-filter-pills');
        clearAll(pillsContainer);
      });
    });
  }

  // ── Wire remove pills ──────────────────────────────────────────────────────
  function wirePillRemove(scope) {
    scope.querySelectorAll('.md3-filter-pill__remove').forEach((btn) => {
      if (btn._mdPillWired) return;
      btn._mdPillWired = true;
      btn.addEventListener('click', () => btn.closest('.md3-filter-pill')?.remove());
    });
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  function init(scope = document) {
    scope.querySelectorAll('.md3-filter-select').forEach(initSelect);
    wireClearAll(scope);
    wirePillRemove(scope);
  }

  // ── MutationObserver ──────────────────────────────────────────────────────
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((m) =>
      m.addedNodes.forEach((node) => {
        if (node.nodeType !== 1) return;
        if (node.matches?.('.md3-filter-select')) initSelect(node);
        node.querySelectorAll?.('.md3-filter-select').forEach(initSelect);
        wireClearAll(node);
        wirePillRemove(node);
      })
    );
  });

  document.addEventListener('DOMContentLoaded', () => {
    init();
    observer.observe(document.body, { childList: true, subtree: true });
  });

  // ── Global API ─────────────────────────────────────────────────────────────
  window.Filters = { init, addPill, clearAll, syncFromURL, syncToURL };
})();
