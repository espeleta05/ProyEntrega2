(function () {
  'use strict';

  /* ── Filtros de tabla ── */
  const searchInput    = document.getElementById('searchInput');
  const statusFilter   = document.getElementById('statusFilter');
  const clinicFilter   = document.getElementById('clinicFilterSelect');
  const sortSelect     = document.getElementById('sortSelect');
  const table          = document.getElementById('lotesTable');

  function getRows() {
    if (!table) return [];
    return Array.from(table.querySelectorAll('tbody tr'));
  }

  function applyFilters() {
    const q      = (searchInput  ? searchInput.value.trim().toLowerCase()  : '');
    const status = (statusFilter ? statusFilter.value.toLowerCase()         : '');
    const clinic = (clinicFilter ? clinicFilter.value                       : '');
    let visible  = 0;

    getRows().forEach(function (row) {
      const vaccine    = (row.dataset.vaccine || '').toLowerCase();
      const lot        = (row.dataset.lot     || '').toLowerCase();
      const st         = (row.dataset.status  || '').toLowerCase();
      const rowClinic  = (row.dataset.clinic  || '');

      const matchQ = !q      || vaccine.includes(q) || lot.includes(q);
      const matchS = !status || st === status;
      const matchC = !clinic || rowClinic === clinic;

      row.style.display = (matchQ && matchS && matchC) ? '' : 'none';
      if (matchQ && matchS && matchC) visible++;
    });

    updateFooter(visible);
  }

  function applySorting(key) {
    if (!table) return;
    const tbody = table.querySelector('tbody');
    const rows  = getRows().filter(function (r) { return r.style.display !== 'none'; });

    rows.sort(function (a, b) {
      switch (key) {
        case 'lote':
          return (a.dataset.lot || '').localeCompare(b.dataset.lot || '');
        case 'stock':
          return parseInt(b.dataset.stock || '0', 10) - parseInt(a.dataset.stock || '0', 10);
        case 'vencimiento':
          return (a.dataset.expiry || '').localeCompare(b.dataset.expiry || '');
        default: // 'vacuna'
          return (a.dataset.vaccine || '').localeCompare(b.dataset.vaccine || '');
      }
    });

    rows.forEach(function (row) { tbody.appendChild(row); });
  }

  function updateFooter(count) {
    const tfoot = table ? table.querySelector('tfoot td') : null;
    if (tfoot) tfoot.textContent = 'Total: ' + count + ' lote(s) visible(s)';
  }

  if (searchInput)  searchInput.addEventListener('input',  applyFilters);
  if (statusFilter) statusFilter.addEventListener('change', applyFilters);
  if (clinicFilter) clinicFilter.addEventListener('change', applyFilters);
  if (sortSelect) {
    sortSelect.addEventListener('change', function () {
      applyFilters();
      applySorting(sortSelect.value);
    });
  }

  /* ── Modal de movimiento manual ── */
  var currentStock = 0;

  window.openMovModal = function (lotId, vaccineName, lotNumber, stock) {
    currentStock = stock;
    const modal = document.getElementById('movModal');
    if (!modal) return;

    document.getElementById('movLotId').value    = lotId;
    document.getElementById('movLotLabel').textContent =
      vaccineName + ' · Lote ' + lotNumber + ' — Stock actual: ' + stock + ' dosis';

    modal.hidden = false;
    document.body.style.overflow = 'hidden';
  };

  window.closeMovModal = function () {
    const modal = document.getElementById('movModal');
    if (modal) modal.hidden = true;
    document.body.style.overflow = '';
  };

  /* Validar cantidad no excede stock para ajustes negativos/mermas */
  const movForm = document.querySelector('#movModal form');
  if (movForm) {
    movForm.addEventListener('submit', function (e) {
      const typeSelect = movForm.querySelector('[name="movement_type"]');
      const qtyInput   = movForm.querySelector('[name="quantity"]');
      if (!typeSelect || !qtyInput) return;

      const negativeTypes = ['Ajuste_Negativo', 'Salida_Merma', 'Salida_Caducidad'];
      if (negativeTypes.includes(typeSelect.value)) {
        const qty = parseInt(qtyInput.value, 10);
        if (qty > currentStock) {
          e.preventDefault();
          alert('La cantidad (' + qty + ') supera el stock disponible (' + currentStock + ').');
        }
      }
    });
  }

  /* Cerrar modal con Escape o clic en overlay */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') window.closeMovModal();
  });
  const overlay = document.getElementById('movModal');
  if (overlay) {
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) window.closeMovModal();
    });
  }

}());
