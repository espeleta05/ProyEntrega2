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

// ── Modal nuevo paciente ────────────────────────────────────────────────────

function openPatientModal() {
  document.getElementById('patientModal')?.classList.add('active');
}

function closePatientModal() {
  document.getElementById('patientModal')?.classList.remove('active');
  document.getElementById('formNewPatient')?.reset();
  _resetPhotoPreview();
}

window.openPatientModal  = openPatientModal;
window.closePatientModal = closePatientModal;

document.getElementById('patientModal')?.addEventListener('click', e => {
  if (e.target === document.getElementById('patientModal')) closePatientModal();
});

// ── Preview de foto en el modal ─────────────────────────────────────────────

function _updateModalInitials() {
  const name = document.getElementById('p_name')?.value    || '';
  const last = document.getElementById('p_lastname')?.value || '';
  const initials = (name[0] || '—').toUpperCase() + (last[0] || '').toUpperCase();
  const el = document.getElementById('photoPreviewInitials');
  if (el) el.textContent = initials;
}

function _resetPhotoPreview() {
  const img      = document.getElementById('photoPreviewImg');
  const initials = document.getElementById('photoPreviewInitials');
  if (img)      { img.src = ''; img.classList.remove('visible'); }
  if (initials) { initials.style.display = ''; initials.textContent = '—'; }
  const input = document.getElementById('p_photo');
  if (input) input.value = '';
}

document.getElementById('p_name')?.addEventListener('input',     _updateModalInitials);
document.getElementById('p_lastname')?.addEventListener('input',  _updateModalInitials);

document.getElementById('p_photo')?.addEventListener('change', function () {
  const file = this.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = e => {
    const img      = document.getElementById('photoPreviewImg');
    const initials = document.getElementById('photoPreviewInitials');
    if (img)      { img.src = e.target.result; img.classList.add('visible'); }
    if (initials) initials.style.display = 'none';
  };
  reader.readAsDataURL(file);
});

// ── Submit del formulario ───────────────────────────────────────────────────

document.getElementById('formNewPatient')?.addEventListener('submit', async e => {
  e.preventDefault();
  const val = id => document.getElementById(id)?.value?.trim() || '';

  const data = {
    first_name: val('p_name'),
    last_name:  val('p_lastname'),
    birth_date: val('p_birthdate'),
    gender:     val('p_gender') === 'Masculino' ? 'M' : 'F',
    blood_type: val('p_blood'),
    allergies:  val('p_allergies'),
    rfc:        val('p_rfc').toUpperCase(),
    tutor: {
      name:     val('t_name'),
      lastname: val('t_lastname'),
      curp:     val('t_curp'),
      number:   val('t_phone'),
      mail:     val('t_email'),
      address:  val('t_address'),
    },
  };

  let patientId;
  try {
    const res    = await fetch('/register_patient', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(data),
    });
    const result = await res.json();
    if (!res.ok) { alert(result.error || 'Ocurrió un error al registrar'); return; }
    patientId = result.patient_id;
  } catch {
    alert('Error de conexión');
    return;
  }

  const photoInput = document.getElementById('p_photo');
  if (patientId && photoInput?.files[0]) {
    const formData = new FormData();
    formData.append('photo', photoInput.files[0]);
    await fetch(`/patients/${patientId}/photo`, { method: 'POST', body: formData });
  }

  closePatientModal();
  window.location.reload();
});

// ── Upload foto desde card ──────────────────────────────────────────────────

async function uploadPatientPhoto(patientId, input) {
  const file = input.files[0];
  if (!file) return;

  const avatarDiv  = input.previousElementSibling;
  const img        = avatarDiv.querySelector('.pt-avatar-img');
  const overlayIcon = avatarDiv.querySelector('.pt-avatar-overlay i');
  const formData   = new FormData();
  formData.append('photo', file);

  avatarDiv.classList.add('pt-avatar--loading');
  if (overlayIcon) overlayIcon.className = 'fa-solid fa-spinner';

  try {
    const res  = await fetch(`/patients/${patientId}/photo`, { method: 'POST', body: formData });
    const data = await res.json();
    if (res.ok) {
      const url = data.photo_url + '?t=' + Date.now();
      if (img) {
        img.src = url;
      } else {
        const newImg = document.createElement('img');
        newImg.className = 'pt-avatar-img';
        avatarDiv.prepend(newImg);
        newImg.src = url;
      }
    } else {
      alert(data.error || 'Error al subir la foto');
    }
  } catch {
    alert('Error de conexión al subir la foto');
  } finally {
    avatarDiv.classList.remove('pt-avatar--loading');
    if (overlayIcon) overlayIcon.className = 'fa-solid fa-camera';
    input.value = '';
  }
}

window.uploadPatientPhoto = uploadPatientPhoto;
