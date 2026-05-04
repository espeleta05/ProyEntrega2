/**
 * dropdowns.js — MD3 Dropdown manager
 *
 * Auto-init: cualquier .md3-dropdown con un .md3-dropdown__trigger.
 * Expone global: Dropdown.open(el), Dropdown.close(el), Dropdown.toggle(el)
 *
 * HTML esperado:
 *   <div class="md3-dropdown">
 *     <button class="md3-dropdown__trigger" aria-expanded="false">Opciones</button>
 *     <div class="md3-dropdown__menu">
 *       <button class="md3-dropdown__item">Editar</button>
 *       <button class="md3-dropdown__item md3-dropdown__item--danger">Eliminar</button>
 *     </div>
 *   </div>
 */
(function () {
  'use strict';

  // ── Core ─────────────────────────────────────────────────────────────────
  function open(dropdown) {
    dropdown.classList.add('open');
    const trigger = dropdown.querySelector('.md3-dropdown__trigger');
    trigger?.setAttribute('aria-expanded', 'true');
    // Foco en primer item
    dropdown.querySelector('.md3-dropdown__item:not(.md3-dropdown__item--disabled)')?.focus();
  }

  function close(dropdown) {
    dropdown.classList.remove('open');
    dropdown.querySelector('.md3-dropdown__trigger')?.setAttribute('aria-expanded', 'false');
  }

  function toggle(dropdown) {
    dropdown.classList.contains('open') ? close(dropdown) : open(dropdown);
  }

  function closeAll(except = null) {
    document.querySelectorAll('.md3-dropdown.open').forEach(d => {
      if (d !== except) close(d);
    });
  }

  // ── Navegación teclado ────────────────────────────────────────────────────
  function getItems(dropdown) {
    return Array.from(
      dropdown.querySelectorAll('.md3-dropdown__item:not(.md3-dropdown__item--disabled)')
    );
  }

  function handleKey(e, dropdown) {
    const items = getItems(dropdown);
    const idx   = items.indexOf(document.activeElement);

    switch (e.key) {
      case 'Escape':
        e.preventDefault();
        close(dropdown);
        dropdown.querySelector('.md3-dropdown__trigger')?.focus();
        break;
      case 'ArrowDown':
        e.preventDefault();
        items[(idx + 1) % items.length]?.focus();
        break;
      case 'ArrowUp':
        e.preventDefault();
        items[(idx - 1 + items.length) % items.length]?.focus();
        break;
      case 'Home':
        e.preventDefault();
        items[0]?.focus();
        break;
      case 'End':
        e.preventDefault();
        items[items.length - 1]?.focus();
        break;
      case 'Tab':
        close(dropdown);
        break;
    }
  }

  // ── Init individual ───────────────────────────────────────────────────────
  function initDropdown(dropdown) {
    if (dropdown._mdDropdownInit) return;
    dropdown._mdDropdownInit = true;

    const trigger = dropdown.querySelector('.md3-dropdown__trigger');
    trigger?.addEventListener('click', (e) => {
      e.stopPropagation();
      closeAll(dropdown);
      toggle(dropdown);
    });

    dropdown.addEventListener('keydown', (e) => handleKey(e, dropdown));
  }

  // ── Clic fuera cierra todos ───────────────────────────────────────────────
  document.addEventListener('click', () => closeAll());

  // ── Auto-init + MutationObserver ─────────────────────────────────────────
  function init(scope = document) {
    scope.querySelectorAll('.md3-dropdown').forEach(initDropdown);
  }

  const observer = new MutationObserver((mutations) => {
    mutations.forEach((m) =>
      m.addedNodes.forEach((node) => {
        if (node.nodeType !== 1) return;
        if (node.matches?.('.md3-dropdown')) initDropdown(node);
        node.querySelectorAll?.('.md3-dropdown').forEach(initDropdown);
      })
    );
  });

  document.addEventListener('DOMContentLoaded', () => {
    init();
    observer.observe(document.body, { childList: true, subtree: true });
  });

  // ── Global API ────────────────────────────────────────────────────────────
  window.Dropdown = { open, close, toggle, init: initDropdown };
})();
