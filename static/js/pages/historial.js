(() => {
  const input      = document.getElementById('historialSearchInput');
  const grid       = document.getElementById('patientsGrid');
  const noResults  = document.getElementById('patientsNoResults');
  if (!input || !grid) return;

  const items = Array.from(grid.querySelectorAll('.patient-item'));

  input.addEventListener('input', (e) => {
    const term = (e.target.value || '').toLowerCase().trim();
    let visible = 0;
    items.forEach(item => {
      const show = !term || item.textContent.toLowerCase().includes(term);
      item.classList.toggle('hidden', !show);
      if (show) visible++;
    });
    if (noResults) noResults.classList.toggle('hidden', !(term && visible === 0));
  });
})();
