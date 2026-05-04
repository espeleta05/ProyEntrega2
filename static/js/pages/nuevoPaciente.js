(() => {
  const modal = document.getElementById('patientModal');
  const form  = document.getElementById('formNewPatient');
  if (!modal) return;

  window.openPatientModal  = () => modal.classList.add('active');
  window.closePatientModal = () => { modal.classList.remove('active'); form?.reset(); };

  modal.addEventListener('click', e => { if (e.target === modal) window.closePatientModal(); });

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const val = id => document.getElementById(id)?.value || '';
    const data = {
      first_name: val('p_name'),
      last_name:  val('p_lastname'),
      birth_date: val('p_birthdate'),
      gender:     val('p_gender') === 'Masculino' ? 'M' : 'F',
      blood_type: val('p_blood'),
      allergies:  val('p_allergies'),
      tutor: {
        name:     val('t_name'),
        lastname: val('t_lastname'),
        curp:     val('t_curp'),
        number:   val('t_phone'),
        mail:     val('t_email'),
        address:  val('t_address'),
      },
    };
    try {
      const res    = await fetch('/register_patient', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
      const result = await res.json();
      if (res.ok) { alert(result.message || 'Paciente registrado'); window.closePatientModal(); window.location.reload(); }
      else          alert(result.error  || 'Ocurrió un error');
    } catch (err) { console.error(err); alert('Error de conexión'); }
  });
})();
