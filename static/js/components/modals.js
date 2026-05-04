/**
 * modals.js — MD3 Modal manager
 *
 * Expone globals: openModal(id), closeModal(id)
 *                 showConfirmModal(title, msg, onConfirm), closeConfirmModal(), executeConfirmAction()
 *
 * Incluir UNA SOLA VEZ en base_2daE.html; reemplaza los <script> inline de
 * modal_confirm.html y de cada macro modal.html.
 */
(function () {
  'use strict';

  // ── open / close ────────────────────────────────────────────────────────
  function openModal(id) {
    const el = typeof id === 'string' ? document.getElementById(id) : id;
    if (!el) return;
    el.classList.add('active');
    el.removeAttribute('hidden');
    // Mover foco al primer elemento interactivo dentro del modal
    requestAnimationFrame(() => {
      const focusable = el.querySelector(
        'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      );
      focusable?.focus();
    });
  }

  function closeModal(id) {
    const el = typeof id === 'string' ? document.getElementById(id) : id;
    if (!el) return;
    el.classList.remove('active');
  }

  // ── confirm modal (compat con modal_confirm.html) ────────────────────────
  let _confirmCb = null;

  function showConfirmModal(title, message, onConfirm) {
    const titleEl = document.getElementById('confirmTitle');
    const msgEl   = document.getElementById('confirmMessage');
    if (titleEl) titleEl.textContent = title;
    if (msgEl)   msgEl.textContent   = message;
    _confirmCb = typeof onConfirm === 'function' ? onConfirm : null;
    openModal('confirmModal');
  }

  function closeConfirmModal() {
    closeModal('confirmModal');
    _confirmCb = null;
  }

  function executeConfirmAction() {
    _confirmCb?.();
    closeConfirmModal();
  }

  // ── ESC cierra el modal más reciente activo ──────────────────────────────
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const active = Array.from(
      document.querySelectorAll('.modal-overlay.active, .md3-modal-overlay.active')
    );
    if (active.length) closeModal(active[active.length - 1]);
  });

  // ── Clic en overlay (fuera del contenedor) cierra ───────────────────────
  document.addEventListener('click', (e) => {
    const overlay = e.target.closest('.modal-overlay, .md3-modal-overlay');
    if (overlay && e.target === overlay) closeModal(overlay);
  });

  // ── Botones [data-modal-close] ──────────────────────────────────────────
  document.addEventListener('click', (e) => {
    const closeBtn = e.target.closest('[data-modal-close]');
    if (closeBtn) {
      const target = closeBtn.dataset.modalClose || closeBtn.closest('.modal-overlay, .md3-modal-overlay');
      if (target) closeModal(target);
    }
  });

  // ── Botones [data-modal-open] ───────────────────────────────────────────
  document.addEventListener('click', (e) => {
    const openBtn = e.target.closest('[data-modal-open]');
    if (openBtn) openModal(openBtn.dataset.modalOpen);
  });

  // ── Globals ─────────────────────────────────────────────────────────────
  window.openModal            = openModal;
  window.closeModal           = closeModal;
  window.showConfirmModal     = showConfirmModal;
  window.closeConfirmModal    = closeConfirmModal;
  window.executeConfirmAction = executeConfirmAction;
})();
