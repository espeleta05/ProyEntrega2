(() => {
  // El macro table no expone el id del tbody, así que lo asignamos aquí.
  document.querySelector('.apps-table .md3-table tbody')
          ?.setAttribute('id', 'appsTable');

  const appsSearch = document.getElementById('searchInput');
  const appsFilter = document.getElementById('roleFilterSelect');
  const appsSort   = document.getElementById('sortSelect');
  const appsRows   = Array.from(document.querySelectorAll('#appsTable tr[data-search]'));

  function applyAppsView() {
    const q      = (appsSearch?.value || '').toLowerCase().trim();
    const filter = (appsFilter?.value || '').toLowerCase().trim();
    appsRows.forEach(row => {
      const vaccine = (row.children[0]?.innerText || '').toLowerCase();
      row.style.display = (!q || row.dataset.search.includes(q)) && (!filter || vaccine.includes(filter)) ? '' : 'none';
    });
  }

  function sortApps() {
    if (!appsSort) return;
    const key  = appsSort.value;
    const tbody = document.getElementById('appsTable');
    const visibleRows = appsRows.filter(r => r.style.display !== 'none');
    const idxMap = { vacuna: 0, paciente: 1, dosis: 2, fecha: 3, doctor: 5, estado: 7 };
    const idx = idxMap[key] ?? 0;
    visibleRows.sort((a, b) => (a.children[idx]?.innerText || '').localeCompare(b.children[idx]?.innerText || '', 'es', { numeric: true, sensitivity: 'base' }));
    visibleRows.forEach(row => tbody.appendChild(row));
  }

  if (appsSearch) appsSearch.addEventListener('input',  () => { applyAppsView(); sortApps(); });
  if (appsFilter) appsFilter.addEventListener('change', () => { applyAppsView(); sortApps(); });
  if (appsSort)   appsSort.addEventListener('change',   () => { sortApps(); applyAppsView(); });

  applyAppsView();
})();
