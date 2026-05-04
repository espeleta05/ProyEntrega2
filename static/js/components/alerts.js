/**
 * alerts.js — MD3 Alert & Toast manager
 *
 * Auto-init: cierra alertas flash existentes (.alert) y auto-descarta las
 *            no-danger después de 5 s.
 *
 * API:
 *   Alert.dismiss(el)
 *   Alert.show(container, message, type, options?)
 *     → options: { title, dismissible, autoDismissMs }
 *   Alert.toast(message, type, duration?)
 *
 * Compat legacy: window.closeAlert(btn)
 */
(function () {
  'use strict';

  // ── Dismiss con animación ─────────────────────────────────────────────────
  function dismiss(el) {
    if (!el || !el.isConnected) return;
    el.classList.add('removing');
    const cleanup = () => el.isConnected && el.remove();
    el.addEventListener('animationend', cleanup, { once: true });
    // Fallback por si la animación no dispara
    setTimeout(cleanup, 450);
  }

  // ── Wire botón de cierre ──────────────────────────────────────────────────
  function wireClose(alertEl) {
    alertEl.querySelectorAll('.alert-close, .md3-alert__close').forEach((btn) => {
      if (btn._mdAlertWired) return;
      btn._mdAlertWired = true;
      btn.addEventListener('click', () =>
        dismiss(btn.closest('.alert, .md3-alert'))
      );
    });
  }

  // ── Auto-dismiss ──────────────────────────────────────────────────────────
  function autoDismiss(alertEl, delay = 5000) {
    setTimeout(() => { if (alertEl.isConnected) dismiss(alertEl); }, delay);
  }

  // ── Inline: crea alerta en un contenedor ──────────────────────────────────
  function show(container, message, type = 'info', options = {}) {
    const { title = '', dismissible = true, autoDismissMs = 0 } = options;
    if (!container) return null;

    const iconMap = {
      success: 'fa-circle-check',
      error:   'fa-circle-exclamation',
      danger:  'fa-circle-exclamation',
      warning: 'fa-triangle-exclamation',
      info:    'fa-circle-info',
      neutral: 'fa-circle',
    };
    const cssType = type === 'danger' ? 'error' : type;
    const icon    = iconMap[type] || 'fa-circle-info';

    const alertEl = document.createElement('div');
    alertEl.className = `md3-alert md3-alert--${cssType}`;
    alertEl.setAttribute('role', 'alert');
    alertEl.innerHTML = `
      <i class="fa-solid ${icon} md3-alert__icon"></i>
      <div class="md3-alert__body">
        ${title ? `<p class="md3-alert__title">${title}</p>` : ''}
        <p class="md3-alert__text">${message}</p>
      </div>
      ${dismissible ? `<button class="modal-close md3-alert__close" aria-label="Cerrar">&times;</button>` : ''}
    `;

    wireClose(alertEl);
    container.prepend(alertEl);

    if (autoDismissMs > 0) autoDismiss(alertEl, autoDismissMs);
    return alertEl;
  }

  // ── Toast: notificación esquina inferior derecha ───────────────────────────
  function getToastContainer() {
    let el = document.getElementById('md3-toast-container');
    if (!el) {
      el = document.createElement('div');
      el.id = 'md3-toast-container';
      el.className = 'toast-container';
      el.setAttribute('aria-live', 'polite');
      el.setAttribute('aria-atomic', 'false');
      document.body.appendChild(el);
    }
    return el;
  }

  function toast(message, type = 'info', duration = 4000) {
    const iconMap = {
      success: 'fa-circle-check',
      error:   'fa-circle-exclamation',
      danger:  'fa-circle-exclamation',
      warning: 'fa-triangle-exclamation',
      info:    'fa-circle-info',
    };

    const toastEl = document.createElement('div');
    const cssType = type === 'danger' ? 'danger' : type;
    toastEl.className = `toast ${cssType}`;
    toastEl.setAttribute('role', 'status');
    toastEl.innerHTML = `
      <i class="fa-solid ${iconMap[type] || 'fa-circle-info'}" style="flex-shrink:0; font-size:1.1rem;"></i>
      <span style="flex:1; font-size:0.875rem; line-height:1.4;">${message}</span>
      <button style="background:none;border:none;cursor:pointer;opacity:.6;font-size:1.1rem;padding:0;line-height:1;flex-shrink:0;" aria-label="Cerrar">&times;</button>
    `;

    toastEl.querySelector('button').addEventListener('click', () => dismiss(toastEl));
    getToastContainer().appendChild(toastEl);
    if (duration > 0) setTimeout(() => { if (toastEl.isConnected) dismiss(toastEl); }, duration);
    return toastEl;
  }

  // ── Auto-init ─────────────────────────────────────────────────────────────
  function initAlerts(scope = document) {
    scope.querySelectorAll('.alert, .md3-alert').forEach((alertEl) => {
      wireClose(alertEl);
      const isDanger =
        alertEl.classList.contains('alert-danger') ||
        alertEl.classList.contains('md3-alert--error');
      if (!isDanger) autoDismiss(alertEl, 5000);
    });
  }

  // ── MutationObserver para alertas dinámicas ───────────────────────────────
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((m) =>
      m.addedNodes.forEach((node) => {
        if (node.nodeType !== 1) return;
        if (node.matches?.('.alert, .md3-alert')) wireClose(node);
        node.querySelectorAll?.('.alert, .md3-alert').forEach(wireClose);
      })
    );
  });

  document.addEventListener('DOMContentLoaded', () => {
    initAlerts();
    observer.observe(document.body, { childList: true, subtree: true });
  });

  // ── Legacy compat ──────────────────────────────────────────────────────────
  window.closeAlert = (btn) => dismiss(btn.closest('.alert, .md3-alert'));

  // ── Global API ────────────────────────────────────────────────────────────
  window.Alert = { show, toast, dismiss };
})();
