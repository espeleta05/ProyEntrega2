/* ═══════════════════════════════════════════════════════════════════
   citas.js  —  Admin citas page interactions
   Nueva estructura de columnas (upcoming table):
     0 = Paciente  1 = Tutor  2 = Vacuna/Dosis  3 = Fecha  4 = Área·Médico  5 = Estado  6 = Acciones
   ═══════════════════════════════════════════════════════════════════ */

// ── Filtros y ordenamiento de la tabla de citas programadas ──────
(() => {
  const apptSearch = document.getElementById('searchInput');
  const apptFilter = document.getElementById('roleFilterSelect');
  const apptSort   = document.getElementById('sortSelect');
  const apptRows   = Array.from(
    document.querySelectorAll('#appointmentsTable tr[data-patient]')
  );

  // Columnas nuevas: 0=Paciente, 1=Tutor, 2=Vacuna, 3=Fecha, 4=Área·Médico, 5=Estado, 6=Acciones
  const idxMap = { paciente: 0, tutor: 1, vacuna: 2, fecha: 3, estado: 5 };

  function applyAppointmentsView() {
    const q    = (apptSearch?.value || '').toLowerCase();
    const date = (apptFilter?.value || '').toLowerCase();

    apptRows.forEach(row => {
      const patient  = (row.getAttribute('data-patient') || '').toLowerCase();
      const cellDate = (row.children[3]?.innerText || '').toLowerCase();
      const visible  = (!q || patient.includes(q)) &&
                       (!date || cellDate.includes(date));
      row.style.display = visible ? '' : 'none';
    });
  }

  function sortAppointments() {
    if (!apptSort) return;
    const key   = apptSort.value;
    const tbody = document.getElementById('appointmentsTable');
    if (!tbody) return;

    const idx     = idxMap[key] ?? 0;
    const visible = apptRows.filter(r => r.style.display !== 'none');

    visible.sort((a, b) =>
      (a.children[idx]?.innerText || '').localeCompare(
        b.children[idx]?.innerText || '',
        'es',
        { numeric: true, sensitivity: 'base' }
      )
    );

    visible.forEach(row => tbody.appendChild(row));
  }

  if (apptSearch) apptSearch.addEventListener('input',  () => { applyAppointmentsView(); sortAppointments(); });
  if (apptFilter) apptFilter.addEventListener('change', () => { applyAppointmentsView(); sortAppointments(); });
  if (apptSort)   apptSort.addEventListener('change',   () => { sortAppointments(); applyAppointmentsView(); });

  applyAppointmentsView();
})();
