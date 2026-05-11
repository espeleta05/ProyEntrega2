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
  // Cargar tutores en background para que el dropdown esté listo
  _loadGuardians();
}

function closePatientModal() {
  document.getElementById('patientModal')?.classList.remove('active');
  document.getElementById('formNewPatient')?.reset();
  _resetPhotoPreview();
  // Volver al modo "tutor nuevo" y limpiar preview
  const noRadio = document.getElementById('tutor_mode_no');
  if (noRadio) noRadio.checked = true;
  _setTutorMode('new');
  _hideTutorPreview();
}

window.openPatientModal  = openPatientModal;
window.closePatientModal = closePatientModal;

// ── Toggle tutor: existente vs. nuevo ──────────────────────────────────────

let _guardiansCache = null;

async function _loadGuardians() {
  if (_guardiansCache) return _guardiansCache;
  try {
    const res = await fetch('/api/guardians');
    const data = await res.json();
    _guardiansCache = Array.isArray(data) ? data : [];
  } catch {
    _guardiansCache = [];
  }
  return _guardiansCache;
}

function _populateGuardianSelect(guardians) {
  const sel = document.getElementById('t_existing_id');
  if (!sel) return;
  // Mantener la opción vacía inicial
  sel.innerHTML = '<option value="">— Selecciona un tutor —</option>';
  guardians.forEach(g => {
    const opt = document.createElement('option');
    opt.value = g.guardian_id;
    const curpTag = g.curp ? ` · ${g.curp}` : '';
    opt.textContent = `${g.first_name} ${g.last_name}${curpTag}`;
    sel.appendChild(opt);
  });
}

function _setTutorMode(mode) {
  const existWrap = document.getElementById('tutor-existing-wrap');
  const newWrap   = document.getElementById('tutor-new-wrap');
  if (!existWrap || !newWrap) return;
  if (mode === 'existing') {
    existWrap.style.display = 'block';
    newWrap.style.display   = 'none';
  } else {
    existWrap.style.display = 'none';
    newWrap.style.display   = 'block';
  }
}

function _showTutorPreview(guardian) {
  const preview = document.getElementById('tutor-preview');
  if (!preview || !guardian) { _hideTutorPreview(); return; }
  document.getElementById('tutor-preview-name').textContent  = `${guardian.first_name} ${guardian.last_name}`;
  document.getElementById('tutor-preview-curp').textContent  = guardian.curp  || '—';
  document.getElementById('tutor-preview-phone').textContent = guardian.phone || '—';
  document.getElementById('tutor-preview-email').textContent = guardian.email || '—';
  preview.style.display = 'flex';
}

function _hideTutorPreview() {
  const preview = document.getElementById('tutor-preview');
  if (preview) preview.style.display = 'none';
  // Limpiar select de tutor existente
  const sel = document.getElementById('t_existing_id');
  if (sel) sel.value = '';
}

// Listeners de los radio buttons
document.querySelectorAll('input[name="tutor_mode"]').forEach(radio => {
  radio.addEventListener('change', async function () {
    _setTutorMode(this.value);
    if (this.value === 'existing') {
      const guardians = await _loadGuardians();
      _populateGuardianSelect(guardians);
    }
  });
});

// Preview al seleccionar tutor del dropdown
document.getElementById('t_existing_id')?.addEventListener('change', function () {
  const id = parseInt(this.value);
  const g  = (_guardiansCache || []).find(x => x.guardian_id === id);
  _showTutorPreview(g || null);
});

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

  // Determinar modo del tutor
  const tutorMode  = document.querySelector('input[name="tutor_mode"]:checked')?.value || 'new';
  const guardianId = tutorMode === 'existing'
    ? (parseInt(val('t_existing_id')) || null)
    : null;

  // Validar que se haya seleccionado un tutor si el modo es "existing"
  if (tutorMode === 'existing' && !guardianId) {
    alert('Por favor, selecciona un tutor de la lista o elige "Registrar nuevo".');
    return;
  }

  const data = {
    first_name:  val('p_name'),
    last_name:   val('p_lastname'),
    birth_date:  val('p_birthdate'),
    gender:      val('p_gender') === 'Masculino' ? 'M' : 'F',
    blood_type:  val('p_blood'),
    allergies:   val('p_allergies'),
    rfc:         val('p_rfc').toUpperCase(),
    guardian_id: guardianId,
    tutor: tutorMode === 'new' ? {
      name:     val('t_name'),
      lastname: val('t_lastname'),
      curp:     val('t_curp'),
      number:   val('t_phone'),
      mail:     val('t_email'),
      address:  val('t_address'),
    } : {},
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

// ── Modal editar paciente ───────────────────────────────────────────────────

let _epGuardiansCache = null;

async function _epLoadGuardians() {
  if (_epGuardiansCache) return _epGuardiansCache;
  try {
    const res  = await fetch('/api/guardians');
    const data = await res.json();
    _epGuardiansCache = Array.isArray(data) ? data : [];
  } catch {
    _epGuardiansCache = [];
  }
  return _epGuardiansCache;
}

function _epSetTutorMode(mode) {
  const existWrap = document.getElementById('ep-tutor-existing-wrap');
  const newWrap   = document.getElementById('ep-tutor-new-wrap');
  if (!existWrap || !newWrap) return;
  existWrap.style.display = mode === 'existing' ? 'block' : 'none';
  newWrap.style.display   = mode === 'new'      ? 'block' : 'none';
}

function _epShowGuardianPreview(g) {
  const preview = document.getElementById('ep-tutor-preview');
  if (!preview || !g) { if (preview) preview.style.display = 'none'; return; }
  document.getElementById('ep-tutor-preview-name').textContent  = `${g.first_name} ${g.last_name}`;
  document.getElementById('ep-tutor-preview-curp').textContent  = g.curp  || '—';
  document.getElementById('ep-tutor-preview-phone').textContent = g.phone || '—';
  document.getElementById('ep-tutor-preview-email').textContent = g.email || '—';
  preview.style.display = 'flex';
}

async function openEditPatientModal(patientId) {
  const modal = document.getElementById('editPatientModal');
  if (!modal) return;

  // Mostrar modal con estado de carga
  document.getElementById('ep_patient_id').value = patientId;
  modal.classList.add('active');

  let patient;
  try {
    const res = await fetch(`/api/patients/${patientId}`);
    patient   = await res.json();
    if (!res.ok) { alert(patient.error || 'No se pudo cargar el paciente'); closeEditPatientModal(); return; }
  } catch {
    alert('Error de conexión al cargar el paciente');
    closeEditPatientModal();
    return;
  }

  // Pre-llenar campos del paciente
  document.getElementById('ep_name').value      = patient.first_name  || '';
  document.getElementById('ep_lastname').value  = patient.last_name   || '';
  document.getElementById('ep_curp').value      = patient.curp        || '';
  document.getElementById('ep_birthdate').value = patient.birth_date  || '';
  document.getElementById('ep_weight').value    = patient.weight_kg   != null ? patient.weight_kg : '';

  const bloodSel = document.getElementById('ep_blood');
  if (bloodSel) {
    const opt = Array.from(bloodSel.options)
      .find(o => o.value.toUpperCase() === (patient.blood_type || '').toUpperCase());
    bloodSel.value = opt ? opt.value : '';
  }

  // Pre-llenar tutor
  const hasGuardian = !!patient.guardian_id;
  if (hasGuardian) {
    // Modo "new" con datos pre-llenados del tutor actual
    const noRadio = document.getElementById('ep_tutor_mode_no');
    if (noRadio) noRadio.checked = true;
    _epSetTutorMode('new');
    document.getElementById('ep_t_name').value     = patient.guardian_first_name || '';
    document.getElementById('ep_t_lastname').value = patient.guardian_last_name  || '';
    document.getElementById('ep_t_curp').value     = patient.guardian_curp       || '';
    document.getElementById('ep_t_phone').value    = patient.guardian_phone      || '';
    document.getElementById('ep_t_email').value    = patient.guardian_email      || '';
  } else {
    const noneRadio = document.getElementById('ep_tutor_mode_none');
    if (noneRadio) noneRadio.checked = true;
    _epSetTutorMode('none');
  }
}

function closeEditPatientModal() {
  document.getElementById('editPatientModal')?.classList.remove('active');
  document.getElementById('formEditPatient')?.reset();
  _epSetTutorMode('new');
  const preview = document.getElementById('ep-tutor-preview');
  if (preview) preview.style.display = 'none';
}

window.openEditPatientModal  = openEditPatientModal;
window.closeEditPatientModal = closeEditPatientModal;

// Cerrar al hacer clic en el overlay
document.getElementById('editPatientModal')?.addEventListener('click', e => {
  if (e.target === document.getElementById('editPatientModal')) closeEditPatientModal();
});

// Cambio de modo tutor
document.querySelectorAll('input[name="ep_tutor_mode"]').forEach(radio => {
  radio.addEventListener('change', async function () {
    _epSetTutorMode(this.value);
    if (this.value === 'existing') {
      const guardians = await _epLoadGuardians();
      const sel = document.getElementById('ep_existing_id');
      if (sel) {
        sel.innerHTML = '<option value="">— Selecciona un tutor —</option>';
        guardians.forEach(g => {
          const opt = document.createElement('option');
          opt.value       = g.guardian_id;
          opt.textContent = `${g.first_name} ${g.last_name}${g.curp ? ' · ' + g.curp : ''}`;
          sel.appendChild(opt);
        });
      }
    }
  });
});

// Preview al seleccionar tutor existente
document.getElementById('ep_existing_id')?.addEventListener('change', function () {
  const id = parseInt(this.value);
  const g  = (_epGuardiansCache || []).find(x => x.guardian_id === id);
  _epShowGuardianPreview(g || null);
});

// Submit
document.getElementById('formEditPatient')?.addEventListener('submit', async e => {
  e.preventDefault();
  const id = document.getElementById('ep_patient_id')?.value;
  if (!id) return;

  const tutorMode = document.querySelector('input[name="ep_tutor_mode"]:checked')?.value || 'none';
  const guardianId = tutorMode === 'existing'
    ? (parseInt(document.getElementById('ep_existing_id')?.value) || null)
    : null;

  if (tutorMode === 'existing' && !guardianId) {
    alert('Por favor selecciona un tutor de la lista o elige otra opción.');
    return;
  }

  const val = elId => document.getElementById(elId)?.value?.trim() || '';

  const data = {
    first_name:  val('ep_name')      || null,
    last_name:   val('ep_lastname')  || null,
    curp:        val('ep_curp')      || null,
    birth_date:  val('ep_birthdate') || null,
    blood_type:  val('ep_blood')     || null,
    weight_kg:   val('ep_weight')    || null,
    tutor_mode:  tutorMode,
    guardian_id: guardianId,
    tutor: tutorMode === 'new' ? {
      name:     val('ep_t_name'),
      lastname: val('ep_t_lastname'),
      curp:     val('ep_t_curp'),
      number:   val('ep_t_phone'),
      mail:     val('ep_t_email'),
    } : {},
  };

  try {
    const res    = await fetch(`/update_patient/${id}`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(data),
    });
    const result = await res.json();
    if (!res.ok) { alert(result.error || 'Error al actualizar el paciente'); return; }
    closeEditPatientModal();
    window.location.reload();
  } catch {
    alert('Error de conexión al actualizar el paciente');
  }
});

// Abrir modal desde botones de las cards
document.querySelectorAll('.edit-patient-btn').forEach(btn => {
  btn.addEventListener('click', function () {
    openEditPatientModal(this.dataset.patientId);
  });
});
