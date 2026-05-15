(() => {
  document.querySelector('.vaccines-table .md3-table tbody')
          ?.setAttribute('id', 'tableBody');

  const rows              = Array.from(document.querySelectorAll('#tableBody tr[data-name]'));
  const searchInput       = document.getElementById('searchInput');
  const filterSelect      = document.getElementById('roleFilterSelect');
  const clinicSelect      = document.getElementById('clinicFilterSelect');
  const sortSelect        = document.getElementById('sortSelect');
  const showInactiveToggle = document.getElementById('showInactiveToggle');

  // ── Filtrar y ordenar ─────────────────────────────────────────────────────

  function applyView() {
    const term         = (searchInput?.value  || '').toLowerCase().trim();
    const filter       = (filterSelect?.value || '').toLowerCase().trim();
    const clinic       = (clinicSelect?.value || '').trim();
    const showInactive = showInactiveToggle?.checked || false;

    rows.forEach(row => {
      const name      = row.dataset.name   || '';
      const lot       = row.dataset.lot    || '';
      const rowClinic = row.dataset.clinic || '';
      const active    = row.dataset.active !== 'false';

      const ok =
        (!term    || name.includes(term) || lot.includes(term)) &&
        (!filter  || name.includes(filter)) &&
        (!clinic  || rowClinic === clinic) &&
        (showInactive || active);

      row.style.display = ok ? '' : 'none';
    });
  }

  function sortRows() {
    if (!sortSelect) return;
    const key    = sortSelect.value;
    const tbody  = document.getElementById('tableBody');
    const visible = rows.filter(r => r.style.display !== 'none');
    visible.sort((a, b) => {
      if (key === 'lote')  return (a.dataset.lot || '').localeCompare(b.dataset.lot || '', 'es', { numeric: true, sensitivity: 'base' });
      if (key === 'stock') return Number(b.querySelector('.stock-td')?.innerText || 0) - Number(a.querySelector('.stock-td')?.innerText || 0);
      if (key === 'dosis') return Number(b.children[5]?.innerText || 0) - Number(a.children[5]?.innerText || 0);
      return (a.dataset.name || '').localeCompare(b.dataset.name || '', 'es', { sensitivity: 'base' });
    });
    visible.forEach(row => tbody.appendChild(row));
  }

  searchInput?.addEventListener('input',  () => { applyView(); sortRows(); });
  filterSelect?.addEventListener('change', () => { applyView(); sortRows(); });
  clinicSelect?.addEventListener('change', () => { applyView(); sortRows(); });
  sortSelect?.addEventListener('change',   () => { sortRows(); applyView(); });
  showInactiveToggle?.addEventListener('change', () => { applyView(); sortRows(); });

  const q = new URLSearchParams(window.location.search).get('q')?.trim();
  if (q && searchInput) searchInput.value = q;
  sortRows();
  applyView();

  // ── Helpers ───────────────────────────────────────────────────────────────

  function showError(elId, msg) {
    const el = document.getElementById(elId);
    if (!el) return;
    el.textContent   = msg;
    el.style.display = 'block';
  }

  function clearError(elId) {
    const el = document.getElementById(elId);
    if (!el) return;
    el.textContent   = '';
    el.style.display = 'none';
  }

  async function postJSON(url, body) {
    const res  = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    return { ok: res.ok, data };
  }

  // ── Modal: Agregar lote ───────────────────────────────────────────────────

  window.openLotModal = function (vaccineId) {
    clearError('lotModal-error');
    if (vaccineId) document.getElementById('lot_vaccine_id').value = vaccineId;
    document.getElementById('lotModal').classList.add('active');
  };

  window.closeLotModal = function () {
    document.getElementById('lotModal').classList.remove('active');
    document.getElementById('lot_vaccine_id').value = '';
    document.getElementById('lot_clinic_id').value  = '';
    document.getElementById('lot_number').value     = '';
    document.getElementById('lot_qty').value        = '';
    document.getElementById('lot_exp').value        = '';
    clearError('lotModal-error');
  };

  window.submitLotForm = async function () {
    const vaccine_id        = document.getElementById('lot_vaccine_id').value;
    const clinic_id         = document.getElementById('lot_clinic_id').value;
    const lot_number        = document.getElementById('lot_number').value.trim();
    const quantity_received = document.getElementById('lot_qty').value;
    const expiration_date   = document.getElementById('lot_exp').value;

    if (!vaccine_id || !clinic_id || !lot_number || !quantity_received || !expiration_date) {
      showError('lotModal-error', 'Por favor completa todos los campos obligatorios.');
      return;
    }
    try {
      const { ok, data } = await postJSON('/create_vaccine_lot', {
        vaccine_id: Number(vaccine_id), clinic_id: Number(clinic_id),
        lot_number, quantity_received: Number(quantity_received), expiration_date,
      });
      if (!ok) { showError('lotModal-error', data.error || 'Error al crear el lote.'); return; }
      window.location.reload();
    } catch { showError('lotModal-error', 'Error de conexión. Intenta de nuevo.'); }
  };

  // ── Modal: Editar lote ────────────────────────────────────────────────────

  window.openEditLotModal = function (lotId, clinicId, lotNumber, qtyReceived, expDate) {
    clearError('editLotModal-error');
    document.getElementById('edit_lot_id').value       = lotId;
    document.getElementById('edit_clinic_id').value    = clinicId;
    document.getElementById('edit_lot_number').value   = lotNumber;
    document.getElementById('edit_qty_received').value = qtyReceived;
    document.getElementById('edit_exp_date').value     = expDate;
    document.getElementById('editLotModal').classList.add('active');
  };

  window.closeEditLotModal = function () {
    document.getElementById('editLotModal').classList.remove('active');
    clearError('editLotModal-error');
  };

  window.submitEditLotForm = async function () {
    const lot_id         = document.getElementById('edit_lot_id').value;
    const clinic_id      = document.getElementById('edit_clinic_id').value;
    const lot_number     = document.getElementById('edit_lot_number').value.trim();
    const qty_received   = document.getElementById('edit_qty_received').value;
    const expiration_date = document.getElementById('edit_exp_date').value;

    if (!clinic_id || !lot_number || !qty_received || !expiration_date) {
      showError('editLotModal-error', 'Por favor completa todos los campos obligatorios.');
      return;
    }
    try {
      const { ok, data } = await postJSON(`/edit_vaccine_lot/${lot_id}`, {
        clinic_id: Number(clinic_id), lot_number,
        quantity_received: Number(qty_received), expiration_date,
      });
      if (!ok) { showError('editLotModal-error', data.error || 'Error al editar el lote.'); return; }
      window.location.reload();
    } catch { showError('editLotModal-error', 'Error de conexión. Intenta de nuevo.'); }
  };

  // ── Modal: Actualizar stock ───────────────────────────────────────────────

  window.openUpdateStockModal = function (lotId, lotNumber, currentStock) {
    clearError('updateStockModal-error');
    document.getElementById('upd_lot_id').value     = lotId;
    document.getElementById('upd_lot_number').value = lotNumber;
    document.getElementById('upd_stock').value      = currentStock;
    document.getElementById('updateStockModal').classList.add('active');
  };

  window.closeUpdateStockModal = function () {
    document.getElementById('updateStockModal').classList.remove('active');
    clearError('updateStockModal-error');
  };

  window.submitUpdateStockForm = async function () {
    const lot_id             = document.getElementById('upd_lot_id').value;
    const quantity_available = document.getElementById('upd_stock').value;

    if (!lot_id || quantity_available === '') {
      showError('updateStockModal-error', 'Ingresa el nuevo stock disponible.');
      return;
    }
    try {
      const { ok, data } = await postJSON('/update_vaccine_lot_stock', {
        lot_id: Number(lot_id), quantity_available: Number(quantity_available),
      });
      if (!ok) { showError('updateStockModal-error', data.error || 'Error al actualizar el stock.'); return; }
      window.location.reload();
    } catch { showError('updateStockModal-error', 'Error de conexión. Intenta de nuevo.'); }
  };

  // ── Desactivar lote vencido ───────────────────────────────────────────────

  window.deactivateLot = async function (lotId, lotNumber) {
    if (!confirm(`¿Desactivar el lote vencido "${lotNumber}"?\nEl lote quedará oculto pero no se eliminará de la base de datos.`)) return;
    try {
      const { ok, data } = await postJSON(`/delete_vaccine_lot/${lotId}`, {});
      if (!ok) { alert(data.error || 'No se pudo desactivar el lote.'); return; }
      window.location.reload();
    } catch { alert('Error de conexión. Intenta de nuevo.'); }
  };
})();
