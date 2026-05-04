(() => {
  const apptSearch = document.getElementById('searchInput');
  const apptFilter = document.getElementById('roleFilterSelect');
  const apptSort   = document.getElementById('sortSelect');
  const apptRows   = Array.from(document.querySelectorAll('#appointmentsTable tr[data-patient]'));

  function applyAppointmentsView() {
    const q    = (apptSearch?.value || '').toLowerCase();
    const date = (apptFilter?.value || '').toLowerCase();
    apptRows.forEach(row => {
      const patient  = (row.getAttribute('data-patient') || '').toLowerCase();
      const cellDate = (row.children[4]?.innerText || '').toLowerCase();
      row.style.display = (!q || patient.includes(q)) && (!date || cellDate.includes(date)) ? '' : 'none';
    });
  }

  function sortAppointments() {
    if (!apptSort) return;
    const key   = apptSort.value;
    const tbody = document.getElementById('appointmentsTable');
    const visible = apptRows.filter(r => r.style.display !== 'none');
    const idxMap  = { paciente: 0, clinica: 1, area: 2, trabajador: 3, fecha: 4, estado: 6 };
    const idx = idxMap[key] ?? 0;
    visible.sort((a, b) => (a.children[idx]?.innerText || '').localeCompare(b.children[idx]?.innerText || '', 'es', { numeric: true, sensitivity: 'base' }));
    visible.forEach(row => tbody.appendChild(row));
  }

  if (apptSearch) apptSearch.addEventListener('input',  () => { applyAppointmentsView(); sortAppointments(); });
  if (apptFilter) apptFilter.addEventListener('change', () => { applyAppointmentsView(); sortAppointments(); });
  if (apptSort)   apptSort.addEventListener('change',   () => { sortAppointments(); applyAppointmentsView(); });

  applyAppointmentsView();
})();
