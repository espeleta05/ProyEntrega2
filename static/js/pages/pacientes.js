(() => {
  const container   = document.getElementById('patientsContainer');
  const cards       = container ? Array.from(container.querySelectorAll('.patient-card-wrapper')) : [];
  const searchInput = document.getElementById('searchInput');
  const bloodFilter = document.getElementById('roleFilterSelect');
  const sortSelect  = document.getElementById('sortSelect');

  function applyPatientsView() {
    const q     = (searchInput?.value || '').toLowerCase().trim();
    const blood = (bloodFilter?.value || '').toLowerCase().trim();
    cards.forEach(card => {
      const id      = (card.dataset.patientId || '').toLowerCase();
      const name    = (card.dataset.name || '').toLowerCase();
      const bld     = (card.dataset.blood || '').toLowerCase();
      const okQ     = !q     || id === q  || name.includes(q);
      const okBlood = !blood || bld === blood;
      card.style.display = (okQ && okBlood) ? 'block' : 'none';
    });
  }

  function sortPatients() {
    if (!container || !sortSelect) return;
    const key     = sortSelect.value;
    const visible = cards.filter(c => c.style.display !== 'none');
    visible.sort((a, b) => {
      if (key === 'id')   return Number(a.dataset.patientId || 0) - Number(b.dataset.patientId || 0);
      if (key === 'edad') return (b.dataset.birth || '').localeCompare(a.dataset.birth || '', 'es');
      return (a.dataset.name || '').localeCompare(b.dataset.name || '', 'es', { sensitivity: 'base' });
    });
    visible.forEach(c => container.appendChild(c));
  }

  if (searchInput) searchInput.addEventListener('input',  () => { applyPatientsView(); sortPatients(); });
  if (bloodFilter) bloodFilter.addEventListener('change', () => { applyPatientsView(); sortPatients(); });
  if (sortSelect)  sortSelect.addEventListener('change',  () => { sortPatients(); applyPatientsView(); });

  const q = new URLSearchParams(window.location.search).get('q')?.trim();
  if (q && searchInput) { searchInput.value = q; }
  sortPatients();
  applyPatientsView();

  document.querySelectorAll('.delete-patient-btn').forEach(btn => {
    btn.addEventListener('click', async function () {
      const id = this.dataset.patientId;
      if (!id) return;
      if (!confirm('Esta accion eliminara al paciente y sus registros relacionados. Continuar?')) return;
      try {
        const res  = await fetch(`/delete_patient/${id}`, { method: 'POST', headers: { 'Content-Type': 'application/json' } });
        const data = await res.json();
        if (!res.ok) { alert(data.error || 'No se pudo eliminar el paciente'); return; }
        document.getElementById(`patient-card-${id}`)?.remove();
        alert(data.message || 'Paciente eliminado correctamente');
        window.location.reload();
      } catch (err) {
        alert('Error de conexion al eliminar paciente');
        console.error(err);
      }
    });
  });
})();
