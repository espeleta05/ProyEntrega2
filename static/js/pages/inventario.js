(() => {
  const invSearch = document.getElementById('searchInput');
  const invFilter = document.getElementById('roleFilterSelect');
  const invSort   = document.getElementById('sortSelect');
  const invRows   = Array.from(document.querySelectorAll('#inventoryTable tr[data-clinic]'));

  function applyInventoryView() {
    const q      = (invSearch?.value || '').toLowerCase();
    const filter = (invFilter?.value || '').toLowerCase();
    invRows.forEach(row => {
      const clinic = row.dataset.clinic.toLowerCase();
      const supply = row.dataset.supply.toLowerCase();
      row.style.display = (!q || clinic.includes(q) || supply.includes(q)) && (!filter || supply.includes(filter)) ? '' : 'none';
    });
  }

  function sortInventory() {
    if (!invSort) return;
    const key   = invSort.value;
    const tbody = document.getElementById('inventoryTable');
    const visible = invRows.filter(r => r.style.display !== 'none');
    const idxMap  = { clinica: 0, insumo: 1, unidad: 2, stock: 3, categoria: 5, estado: 6 };
    const idx = idxMap[key] ?? 0;
    visible.sort((a, b) => (a.children[idx]?.innerText || '').localeCompare(b.children[idx]?.innerText || '', 'es', { numeric: true, sensitivity: 'base' }));
    visible.forEach(row => tbody.appendChild(row));
  }

  if (invSearch) invSearch.addEventListener('input',  () => { applyInventoryView(); sortInventory(); });
  if (invFilter) invFilter.addEventListener('change', () => { applyInventoryView(); sortInventory(); });
  if (invSort)   invSort.addEventListener('change',   () => { sortInventory(); applyInventoryView(); });

  applyInventoryView();
})();
