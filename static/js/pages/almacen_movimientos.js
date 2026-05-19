(function () {
  'use strict';

  const searchInput = document.getElementById('searchInput');
  const typeFilter  = document.getElementById('typeFilter');
  const dateFrom    = document.getElementById('dateFrom');
  const dateTo      = document.getElementById('dateTo');
  const btnFilter   = document.getElementById('btnFilter');
  const btnClear    = document.getElementById('btnClear');
  const movTable    = document.getElementById('movTable');

  /* ── Totales en el footer ── */
  const SALIDA_TYPES = ['Salida_Aplicacion', 'Salida_Merma', 'Salida_Caducidad',
                        'Ajuste_Negativo', 'Transferencia_Salida'];

  function recalcTotals(rows) {
    var entradas      = 0;
    var salidas       = 0;
    var aplicaciones  = 0;
    var ajustes       = 0;
    var mermas        = 0;

    rows.forEach(function (row) {
      if (row.style.display === 'none') return;
      var tdQty = row.querySelector('td:nth-child(6)');
      var qty   = tdQty ? parseInt(tdQty.textContent.trim(), 10) || 0 : 0;
      var type = row.dataset.type || '';

      if (type === 'Entrada')              { entradas += qty; }
      if (SALIDA_TYPES.includes(type))     { salidas  += qty; }
      if (type === 'Salida_Aplicacion')    { aplicaciones += qty; }
      if (type === 'Salida_Merma')         { mermas   += qty; }
      if (type === 'Ajuste_Positivo' || type === 'Ajuste_Negativo') { ajustes += qty; }
    });

    function set(id, v) {
      var el = document.getElementById(id);
      if (el) el.textContent = v;
    }
    set('totalEntradas',     entradas);
    set('totalSalidas',      salidas);
    set('totalAplicaciones', aplicaciones);
    set('totalAjustes',      ajustes);
    set('totalMermas',       mermas);
  }

  /* ── Filtrado ── */
  function applyFilters() {
    if (!movTable) return;

    var q    = searchInput ? searchInput.value.trim().toLowerCase() : '';
    var type = typeFilter  ? typeFilter.value                        : '';
    var from = dateFrom    ? dateFrom.value                          : '';
    var to   = dateTo      ? dateTo.value                            : '';

    var rows = Array.from(movTable.querySelectorAll('tbody tr'));

    rows.forEach(function (row) {
      var vaccine = (row.dataset.vaccine || '').toLowerCase();
      var lot     = (row.dataset.lot     || '').toLowerCase();
      var rowType = (row.dataset.type    || '');
      var rowDate = (row.dataset.date    || '');

      var matchQ    = !q    || vaccine.includes(q) || lot.includes(q);
      var matchType = !type || rowType === type;
      var matchFrom = !from || rowDate >= from;
      var matchTo   = !to   || rowDate <= to;

      row.style.display = (matchQ && matchType && matchFrom && matchTo) ? '' : 'none';
    });

    recalcTotals(rows);
  }

  if (btnFilter) btnFilter.addEventListener('click', applyFilters);

  if (btnClear) {
    btnClear.addEventListener('click', function () {
      if (searchInput) searchInput.value = '';
      if (typeFilter)  typeFilter.value  = '';
      if (dateFrom)    dateFrom.value    = '';
      if (dateTo)      dateTo.value      = '';
      applyFilters();
    });
  }

  /* Allow Enter key in search box */
  if (searchInput) {
    searchInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') applyFilters();
    });
  }

  /* Initial totals on page load */
  if (movTable) {
    recalcTotals(Array.from(movTable.querySelectorAll('tbody tr')));
  }

}());
