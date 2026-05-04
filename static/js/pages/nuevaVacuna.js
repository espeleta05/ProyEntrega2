(() => {
  const modal = document.getElementById('vaccineModal');
  const form  = document.getElementById('formNewVaccine');
  if (!modal) return;

  window.openVaccineModal  = () => modal.classList.add('active');
  window.closeVaccineModal = () => { modal.classList.remove('active'); form?.reset(); };

  modal.addEventListener('click', e => { if (e.target === modal) window.closeVaccineModal(); });

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const val = id => document.getElementById(id)?.value || null;
    const data = {
      name:           val('v_name'),
      manufacturer:   val('v_manufacturer'),
      inventory:      val('v_inventory') !== null ? parseInt(val('v_inventory')) : 0,
      description:    val('v_description'),
      min_age_months: val('v_min_age') !== null ? parseInt(val('v_min_age')) : null,
      max_age_months: val('v_max_age') !== null ? parseInt(val('v_max_age')) : null,
    };
    try {
      const res    = await fetch('/register_vaccine', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
      const result = await res.json();
      if (res.ok) { alert(result.message || 'Vacuna registrada'); window.closeVaccineModal(); window.location.reload(); }
      else          alert(result.error  || 'Ocurrió un error');
    } catch (err) { console.error(err); alert('Error de conexión'); }
  });
})();
