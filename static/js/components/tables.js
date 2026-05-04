/**
 * tables.js — Client-side table filter + sort
 *
 * Reemplaza los scripts inline repetidos de aplicaciones, inventario, citas,
 * pacientes, etc. Una sola llamada a Tables.init() por tabla.
 *
 * API:
 *   const ctrl = Tables.init(config)
 *   ctrl.applyFilter()
 *   ctrl.applySort()
 *   ctrl.refresh()   → re-cachea filas (útil tras agregar filas dinámicamente)
 *
 * Config:
 *   tableId:         Selector del <tbody> — ej. '#appsTable'
 *   rowSelector:     Selector de filas a filtrar (default: 'tr:not(.js-empty-row)')
 *   searchId:        Selector del input de búsqueda
 *   filterSelectId:  Selector del <select> de filtro
 *   filterDataKey:   Atributo data-* de la fila para texto de búsqueda (default: 'search')
 *                    Si la fila no tiene ese atributo se usa su textContent.
 *   sortSelectId:    Selector del <select> de orden
 *   colMap:          { 'valorOpcion': índiceColumna } para el sort por select
 *   onFilter:        callback(visibleRows) tras cada filtrado
 *
 * Ejemplo:
 *   Tables.init({
 *     tableId:        '#appsTable',
 *     searchId:       '#searchInput',
 *     filterSelectId: '#roleFilterSelect',
 *     filterDataKey:  'search',
 *     sortSelectId:   '#sortSelect',
 *     colMap:         { vacuna:0, paciente:1, dosis:2, fecha:3, doctor:5, estado:7 },
 *   });
 */
(function () {
  'use strict';

  function init(config) {
    const {
      tableId,
      rowSelector    = 'tr:not(.js-empty-row)',
      searchId,
      filterSelectId,
      filterDataKey  = 'search',
      sortSelectId,
      colMap         = {},
      onFilter,
    } = config;

    const tbody    = typeof tableId === 'string' ? document.querySelector(tableId)        : tableId;
    const searchEl = searchId       ? document.querySelector(searchId)                    : null;
    const filterEl = filterSelectId ? document.querySelector(filterSelectId)              : null;
    const sortEl   = sortSelectId   ? document.querySelector(sortSelectId)                : null;

    if (!tbody) { console.warn('[Tables] tbody no encontrado:', tableId); return null; }

    // Cache de filas en el momento del init
    let rows = Array.from(tbody.querySelectorAll(rowSelector));

    // ── Filtrar ──────────────────────────────────────────────────────────────
    function applyFilter() {
      const q      = (searchEl?.value  || '').toLowerCase().trim();
      const filter = (filterEl?.value || '').toLowerCase().trim();

      rows.forEach((row) => {
        const text = (
          row.dataset[filterDataKey] ||
          row.getAttribute('data-' + filterDataKey.replace(/([A-Z])/g, '-$1').toLowerCase()) ||
          row.textContent ||
          ''
        ).toLowerCase();

        const matchQ = !q      || text.includes(q);
        const matchF = !filter || text.includes(filter);
        row.style.display = matchQ && matchF ? '' : 'none';
      });

      renderEmptyState();
      onFilter?.(rows.filter((r) => r.style.display !== 'none'));
    }

    // ── Ordenar por select ────────────────────────────────────────────────────
    function applySort() {
      if (!sortEl?.value) return;
      const colIdx = colMap[sortEl.value] ?? 0;
      sortByColumn(colIdx, 'asc');
    }

    // ── Ordenar por índice de columna ─────────────────────────────────────────
    function sortByColumn(colIdx, dir = 'asc') {
      const visible = rows.filter((r) => r.style.display !== 'none');
      visible.sort((a, b) => {
        const tA = a.children[colIdx]?.innerText?.trim() || '';
        const tB = b.children[colIdx]?.innerText?.trim() || '';
        const cmp = tA.localeCompare(tB, 'es', { numeric: true, sensitivity: 'base' });
        return dir === 'asc' ? cmp : -cmp;
      });
      visible.forEach((r) => tbody.appendChild(r));
    }

    // ── Fila de estado vacío ──────────────────────────────────────────────────
    function renderEmptyState() {
      const visible = rows.filter((r) => r.style.display !== 'none');
      let emptyRow  = tbody.querySelector('.js-empty-row');

      if (visible.length === 0) {
        if (!emptyRow) {
          emptyRow = document.createElement('tr');
          emptyRow.className = 'js-empty-row';
          const colCount = rows[0]?.children?.length || 1;
          emptyRow.innerHTML = `
            <td colspan="${colCount}" style="text-align:center; padding:40px 16px; color:var(--md-on-surface-variant,#666);">
              <i class="fa-solid fa-magnifying-glass" style="font-size:1.5rem;display:block;margin-bottom:8px;opacity:.4;"></i>
              Sin resultados para la búsqueda actual
            </td>`;
          tbody.appendChild(emptyRow);
        }
      } else {
        emptyRow?.remove();
      }
    }

    // ── Clicks en cabeceras ordenables ────────────────────────────────────────
    const table = tbody.closest('table');
    if (table) {
      table.querySelectorAll('th.col-sortable').forEach((th) => {
        th.style.cursor = 'pointer';
        th.setAttribute('role', 'columnheader');
        th.setAttribute('aria-sort', 'none');

        th.addEventListener('click', () => {
          // Determinar dirección
          const prevDir = th.dataset.sortDir || 'none';
          const newDir  = prevDir === 'asc' ? 'desc' : 'asc';

          // Reset otros headers
          table.querySelectorAll('th.col-sortable').forEach((h) => {
            h.dataset.sortDir = 'none';
            h.setAttribute('aria-sort', 'none');
            h.classList.remove('col-asc', 'col-desc');
            const ico = h.querySelector('.sort-icon');
            if (ico) ico.className = 'fa-solid fa-sort sort-icon';
          });

          // Aplicar al header actual
          th.dataset.sortDir = newDir;
          th.setAttribute('aria-sort', newDir === 'asc' ? 'ascending' : 'descending');
          th.classList.add(newDir === 'asc' ? 'col-asc' : 'col-desc');
          const ico = th.querySelector('.sort-icon');
          if (ico) ico.className = `fa-solid fa-sort-${newDir === 'asc' ? 'up' : 'down'} sort-icon`;

          const colIdx = [...th.parentElement.children].indexOf(th);
          sortByColumn(colIdx, newDir);
        });
      });
    }

    // ── Wire eventos ─────────────────────────────────────────────────────────
    searchEl?.addEventListener('input',  () => { applyFilter(); applySort(); });
    filterEl?.addEventListener('change', () => { applyFilter(); applySort(); });
    sortEl?.addEventListener('change',   () => { applySort(); applyFilter(); });

    // ── Pase inicial ──────────────────────────────────────────────────────────
    applyFilter();

    // ── Controlador ───────────────────────────────────────────────────────────
    return {
      applyFilter,
      applySort,
      refresh() {
        rows = Array.from(tbody.querySelectorAll(rowSelector));
        applyFilter();
      },
    };
  }

  // ── Global API ─────────────────────────────────────────────────────────────
  window.Tables = { init };
})();
