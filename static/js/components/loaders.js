/**
 * loaders.js — MD3 Loader manager
 *
 * No tiene auto-init; se usa de forma programática.
 *
 * API:
 *   Loader.show(containerEl, text?)     → superpone spinner sobre el elemento
 *   Loader.hide(containerEl)            → lo retira
 *   Loader.showById(id)                 → muestra un loader pre-renderizado (display:none → '')
 *   Loader.hideById(id)                 → lo oculta
 *   Loader.button(btnEl, loading, text?) → estado loading en botón (spinner inline)
 *   Loader.fetchWithLoader(url, opts, containerEl, text?) → fetch + loader automático
 */
(function () {
  'use strict';

  // ── Estilos (inyectados una sola vez) ─────────────────────────────────────
  const STYLE_ID = 'md3-loader-styles';

  function injectStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      @keyframes _md3spin { to { transform: rotate(360deg); } }

      .md3-loader-overlay {
        position: absolute;
        inset: 0;
        background: rgba(255, 255, 255, 0.78);
        backdrop-filter: blur(2px);
        -webkit-backdrop-filter: blur(2px);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 12px;
        z-index: 100;
        border-radius: inherit;
        transition: opacity 0.18s ease;
      }

      .md3-loader-overlay.is-hiding {
        opacity: 0;
        pointer-events: none;
      }

      .md3-loader-overlay__spinner {
        width: 36px;
        height: 36px;
        border: 4px solid color-mix(in srgb, var(--md-primary, #6B007C) 22%, transparent);
        border-top-color: var(--md-primary, #6B007C);
        border-radius: 50%;
        animation: _md3spin 0.72s linear infinite;
        flex-shrink: 0;
      }

      .md3-loader-overlay__text {
        font-family: var(--md-font-family-body, sans-serif);
        font-size: var(--md-font-size-body-sm, 0.8125rem);
        color: var(--md-on-surface-variant, #49454F);
      }

      .md3-btn-spinner {
        display: inline-block;
        width: 14px;
        height: 14px;
        border: 2px solid rgba(255,255,255,.4);
        border-top-color: currentColor;
        border-radius: 50%;
        animation: _md3spin 0.7s linear infinite;
        vertical-align: middle;
        flex-shrink: 0;
      }
    `;
    document.head.appendChild(style);
  }

  // ── show / hide overlay ───────────────────────────────────────────────────
  function show(targetEl, text = '') {
    injectStyles();
    if (!targetEl) return;

    // El padre necesita position no-static para que position:absolute funcione
    if (getComputedStyle(targetEl).position === 'static') {
      targetEl.style.position = 'relative';
    }

    // Evitar duplicados
    targetEl.querySelector('.md3-loader-overlay')?.remove();

    const overlay = document.createElement('div');
    overlay.className = 'md3-loader-overlay';
    overlay.setAttribute('role', 'status');
    overlay.innerHTML = `
      <div class="md3-loader-overlay__spinner"></div>
      ${text ? `<span class="md3-loader-overlay__text">${text}</span>` : ''}
      <span class="sr-only">Cargando${text ? ': ' + text : ''}…</span>
    `;
    targetEl.appendChild(overlay);
  }

  function hide(targetEl) {
    if (!targetEl) return;
    const overlay = targetEl.querySelector('.md3-loader-overlay');
    if (!overlay) return;

    overlay.classList.add('is-hiding');
    const remove = () => overlay.isConnected && overlay.remove();
    overlay.addEventListener('transitionend', remove, { once: true });
    setTimeout(remove, 300);
  }

  // ── show / hide por ID (para loaders pre-renderizados) ────────────────────
  function showById(id) {
    const el = document.getElementById(id);
    if (el) {
      el.style.display = '';
      el.removeAttribute('hidden');
    }
  }

  function hideById(id) {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  }

  // ── Estado loading en botón ───────────────────────────────────────────────
  function button(btn, loading, loadingText = null) {
    if (!btn) return;
    injectStyles();

    if (loading) {
      if (btn._mdLoaderSaved) return; // ya está en loading
      btn._mdLoaderSaved = { html: btn.innerHTML, disabled: btn.disabled };
      btn.disabled = true;
      btn.innerHTML = loadingText
        ? `<span class="md3-btn-spinner"></span> ${loadingText}`
        : '<span class="md3-btn-spinner"></span>';
    } else {
      if (!btn._mdLoaderSaved) return;
      btn.disabled     = btn._mdLoaderSaved.disabled;
      btn.innerHTML    = btn._mdLoaderSaved.html;
      delete btn._mdLoaderSaved;
    }
  }

  // ── fetch + loader automático ─────────────────────────────────────────────
  async function fetchWithLoader(url, opts = {}, containerEl = null, text = 'Cargando…') {
    if (containerEl) show(containerEl, text);
    try {
      return await fetch(url, opts);
    } finally {
      if (containerEl) hide(containerEl);
    }
  }

  // ── Inject styles on load ─────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', injectStyles);

  // ── Global API ────────────────────────────────────────────────────────────
  window.Loader = { show, hide, showById, hideById, button, fetchWithLoader };
})();
