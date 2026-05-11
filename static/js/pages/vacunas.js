(() => {
  // El macro table no expone el id del tbody, así que lo asignamos aquí.
  document.querySelector('.vaccines-table .md3-table tbody')
          ?.setAttribute('id', 'tableBody');

  const rows        = Array.from(document.querySelectorAll('#tableBody tr[data-name]'));
  const searchInput = document.getElementById('searchInput');
  const filterSelect = document.getElementById('roleFilterSelect');
  const sortSelect  = document.getElementById('sortSelect');

  function applyView() {
    const term   = (searchInput?.value  || '').toLowerCase().trim();
    const filter = (filterSelect?.value || '').toLowerCase().trim();
    rows.forEach(row => {
      const name = row.dataset.name || '';
      const lot  = row.dataset.lot  || '';
      row.style.display = (!term || name.includes(term) || lot.includes(term)) && (!filter || name.includes(filter)) ? '' : 'none';
    });
  }

  function sortRows() {
    if (!sortSelect) return;
    const key   = sortSelect.value;
    const tbody = document.getElementById('tableBody');
    const visible = rows.filter(r => r.style.display !== 'none');
    visible.sort((a, b) => {
      if (key === 'lote')  return (a.dataset.lot || '').localeCompare(b.dataset.lot || '', 'es', { numeric: true, sensitivity: 'base' });
      if (key === 'stock') return Number(b.querySelector('.stock-td')?.innerText || 0) - Number(a.querySelector('.stock-td')?.innerText || 0);
      if (key === 'dosis') return Number(b.children[5]?.innerText || 0) - Number(a.children[5]?.innerText || 0);
      return (a.dataset.name || '').localeCompare(b.dataset.name || '', 'es', { sensitivity: 'base' });
    });
    visible.forEach(row => tbody.appendChild(row));
  }

  if (searchInput)  searchInput.addEventListener('input',  () => { applyView(); sortRows(); });
  if (filterSelect) filterSelect.addEventListener('change', () => { applyView(); sortRows(); });
  if (sortSelect)   sortSelect.addEventListener('change',   () => { sortRows(); applyView(); });

  const q = new URLSearchParams(window.location.search).get('q')?.trim();
  if (q && searchInput) { searchInput.value = q; }
  sortRows();
  applyView();
})();
