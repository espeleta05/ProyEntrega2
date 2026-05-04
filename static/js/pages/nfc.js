(() => {
  const cardsSearch = document.getElementById('searchCardsInput');
  const cardsFilter = document.getElementById('roleFilterSelect');
  const cardsSort   = document.getElementById('sortSelect');
  const scanSearch  = document.getElementById('searchScansInput');
  const cardRows    = Array.from(document.querySelectorAll('#cardsTable tr[data-uid]'));
  const scanRows    = Array.from(document.querySelectorAll('#scansTable tr[data-patient]'));

  function applyCardsView() {
    const q      = (cardsSearch?.value || '').toLowerCase();
    const status = (cardsFilter?.value || '').toLowerCase();
    cardRows.forEach(row => {
      const uid     = (row.getAttribute('data-uid')     || '').toLowerCase();
      const patient = (row.getAttribute('data-patient') || '').toLowerCase();
      const state   = row.innerText.toLowerCase().includes('activa') ? 'activa' : 'inactiva';
      row.style.display = (!q || uid.includes(q) || patient.includes(q)) && (!status || state.includes(status)) ? '' : 'none';
    });
  }

  function sortCards() {
    if (!cardsSort) return;
    const key   = cardsSort.value;
    const tbody = document.getElementById('cardsTable');
    const visible = cardRows.filter(r => r.style.display !== 'none');
    const idxMap  = { paciente: 1, tipo_tarjeta: 2, fecha_emision: 4 };
    const idx = idxMap[key] ?? 1;
    visible.sort((a, b) => (a.children[idx]?.innerText || '').localeCompare(b.children[idx]?.innerText || '', 'es', { numeric: true, sensitivity: 'base' }));
    visible.forEach(row => tbody.appendChild(row));
  }

  function applyScansView() {
    const q = (scanSearch?.value || '').toLowerCase();
    scanRows.forEach(row => {
      const patient = (row.getAttribute('data-patient') || '').toLowerCase();
      const worker  = (row.getAttribute('data-worker')  || '').toLowerCase();
      row.style.display = (!q || patient.includes(q) || worker.includes(q)) ? '' : 'none';
    });
  }

  if (cardsSearch) cardsSearch.addEventListener('input',  () => { applyCardsView(); sortCards(); });
  if (cardsFilter) cardsFilter.addEventListener('change', () => { applyCardsView(); sortCards(); });
  if (cardsSort)   cardsSort.addEventListener('change',   () => { sortCards(); applyCardsView(); });
  if (scanSearch)  scanSearch.addEventListener('input', applyScansView);

  applyCardsView();
  applyScansView();
})();
