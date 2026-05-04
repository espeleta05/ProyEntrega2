(() => {
  const input      = document.getElementById('personalSearchInput');
  const roleFilter = document.getElementById('roleFilterSelect');
  const sortSelect = document.getElementById('sortSelect');
  if (!input) return;

  const rows     = Array.from(document.querySelectorAll('.employee-row'));
  const sections = Array.from(document.querySelectorAll('.role-section'));

  function applyFilter() {
    const term     = (input.value    || '').toLowerCase().trim();
    const roleTerm = (roleFilter?.value || '').toLowerCase().trim();
    rows.forEach(row => {
      const text        = row.innerText.toLowerCase();
      const sectionRole = (row.closest('.role-section')?.dataset.role || '').toLowerCase();
      row.style.display = (!term || text.includes(term)) && (!roleTerm || sectionRole.includes(roleTerm)) ? '' : 'none';
    });
    sections.forEach(sec => {
      const visible = sec.querySelectorAll('.employee-row:not([style*="none"])').length;
      sec.style.display = visible > 0 ? '' : 'none';
    });
  }

  function sortRows() {
    const key = sortSelect?.value || 'name';
    sections.forEach(sec => {
      const tbody = sec.querySelector('tbody');
      if (!tbody) return;
      const sRows = Array.from(tbody.querySelectorAll('.employee-row'));
      sRows.sort((a, b) => {
        if (key === 'id')   return Number(a.querySelector('.emp-id-badge')?.innerText.replace(/\D/g,'') || 0) - Number(b.querySelector('.emp-id-badge')?.innerText.replace(/\D/g,'') || 0);
        if (key === 'role') return (a.closest('.role-section')?.dataset.role || '').localeCompare(b.closest('.role-section')?.dataset.role || '', 'es', { sensitivity: 'base' });
        return (a.querySelector('.cell-main')?.innerText || '').toLowerCase().localeCompare((b.querySelector('.cell-main')?.innerText || '').toLowerCase(), 'es', { sensitivity: 'base' });
      });
      sRows.forEach(r => tbody.appendChild(r));
    });
  }

  input.addEventListener('input', applyFilter);
  if (roleFilter) roleFilter.addEventListener('change', applyFilter);
  if (sortSelect) sortSelect.addEventListener('change', () => { sortRows(); applyFilter(); });

  const q = new URLSearchParams(window.location.search).get('q')?.trim();
  if (q) input.value = q;
  sortRows();
  applyFilter();
})();
