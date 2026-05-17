/* ═══════════════════════════════════════════════════════════════════
   agendar.js — Typeahead search + DateTime picker (date + hora split)
   Compartido por nueva_cita.html (admin) y agendar.html (tutor)
   ═══════════════════════════════════════════════════════════════════ */

'use strict';

/* ── Roles médicos permitidos (red de seguridad frontend) ────────── */
const MEDICAL_ROLES = ['médico', 'medico', 'enfermero', 'enfermera'];

/* ── Utilidades ─────────────────────────────────────────────────── */
function initials(name) {
  return (name || '')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(w => w[0].toUpperCase())
    .join('');
}

function normalize(str) {
  return (str || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

function hl(text, query) {
  if (!query) return text;
  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(${escaped})`, 'gi');
  return text.replace(re,
    '<mark style="background:var(--md-primary-container);color:var(--md-on-primary-container);border-radius:2px;padding:0 1px;">$1</mark>');
}

/* ── Typeahead Factory ───────────────────────────────────────────── */
function createTypeahead(cfg) {
  const wrap     = cfg.wrapEl;
  const hidden   = cfg.hiddenEl;
  const input    = wrap.querySelector('.ac-input');
  const clearBtn = wrap.querySelector('.ac-clear');
  const dropdown = wrap.querySelector('.ac-dropdown');
  const chip     = wrap.querySelector('.ac-chip');
  const chipLbl  = chip?.querySelector('.ac-chip-label');
  const chipAvt  = chip?.querySelector('.ac-chip-avatar');
  const chipClr  = chip?.querySelector('.ac-chip-clear');

  if (!input || !dropdown) return;

  let activeIdx = -1;
  let filtered  = [];

  /* ── Render dropdown ── */
  function renderList(items, rawQuery) {
    filtered  = items;
    activeIdx = -1;
    dropdown.innerHTML = '';

    if (!items.length) {
      dropdown.innerHTML =
        `<div class="ac-no-results">
           <i class="fa-solid fa-magnifying-glass"></i>
           Sin resultados para "<strong>${rawQuery}</strong>"
         </div>`;
      openDrop();
      return;
    }

    items.slice(0, 10).forEach((item, i) => {
      const label = cfg.getLabel(item);
      const sub   = cfg.getSub ? cfg.getSub(item) : '';
      const avt   = cfg.getInitials ? cfg.getInitials(item) : initials(label);

      const el = document.createElement('div');
      el.className = 'ac-option';
      el.dataset.i = i;
      el.innerHTML = `
        <div class="ac-avatar">${avt}</div>
        <div>
          <div class="ac-option-name">${hl(label, rawQuery)}</div>
          ${sub ? `<div class="ac-option-sub">${sub}</div>` : ''}
        </div>`;

      el.addEventListener('mousedown', e => { e.preventDefault(); selectItem(item); });
      dropdown.appendChild(el);
    });

    openDrop();
  }

  function openDrop()  { dropdown.classList.add('open'); }
  function closeDrop() { dropdown.classList.remove('open'); activeIdx = -1; }

  /* ── Seleccionar item ── */
  function selectItem(item) {
    const label = cfg.getLabel(item);
    const avt   = cfg.getInitials ? cfg.getInitials(item) : initials(label);

    hidden.value = cfg.getId(item);
    input.value  = label;

    if (chip && chipLbl) {
      if (chipAvt) chipAvt.textContent = avt;
      chipLbl.textContent = label;
      chip.classList.add('visible');
    }
    if (clearBtn) clearBtn.classList.add('visible');

    closeDrop();
    input.blur();
    hidden.dispatchEvent(new Event('change', { bubbles: true }));
  }

  /* ── Limpiar ── */
  function clearField() {
    hidden.value = '';
    input.value  = '';
    chip?.classList.remove('visible');
    clearBtn?.classList.remove('visible');
    closeDrop();
    input.focus();
    hidden.dispatchEvent(new Event('change', { bubbles: true }));
  }

  /* ── Eventos ── */
  input.addEventListener('input', () => {
    const q = input.value.trim();
    if (!q) { closeDrop(); return; }
    const nq = normalize(q);
    renderList(cfg.items.filter(item => cfg.filterFn(item, nq)), q);
  });

  input.addEventListener('focus', () => {
    const q = input.value.trim();
    if (q) {
      const nq = normalize(q);
      renderList(cfg.items.filter(item => cfg.filterFn(item, nq)), q);
    }
  });

  input.addEventListener('keydown', e => {
    const opts = dropdown.querySelectorAll('.ac-option');
    if (!opts.length) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      activeIdx = Math.min(activeIdx + 1, opts.length - 1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      activeIdx = Math.max(activeIdx - 1, 0);
    } else if (e.key === 'Enter' && activeIdx >= 0) {
      e.preventDefault();
      if (filtered[activeIdx]) selectItem(filtered[activeIdx]);
    } else if (e.key === 'Escape') {
      closeDrop();
    }

    opts.forEach((o, i) => o.classList.toggle('active', i === activeIdx));
    opts[activeIdx]?.scrollIntoView({ block: 'nearest' });
  });

  clearBtn?.addEventListener('click', clearField);
  chipClr?.addEventListener('click', clearField);

  document.addEventListener('click', e => {
    if (!wrap.contains(e.target)) closeDrop();
  });

  /* Validación al hacer submit */
  if (cfg.required) {
    wrap.closest('form')?.addEventListener('submit', e => {
      if (input.value.trim() && !hidden.value) {
        e.preventDefault();
        input.setCustomValidity('Selecciona una opción de la lista.');
        input.reportValidity();
      } else {
        input.setCustomValidity('');
      }
    });
  }
}

/* ── Carga dinámica de dosis del paciente ────────────────────────── */
function loadPatientDoses(patientId) {
  const doseField  = document.getElementById('dose-field');
  const doseSelect = document.getElementById('patient_schedule_id');
  if (!doseField || !doseSelect) return;

  if (!patientId) {
    doseField.style.display = 'none';
    doseSelect.innerHTML    = '<option value="">— Sin vacuna específica —</option>';
    return;
  }

  fetch(`/api/paciente/${patientId}/dosis`)
    .then(r => r.json())
    .then(dosis => {
      doseSelect.innerHTML = '<option value="">— Sin vacuna específica —</option>';

      if (!Array.isArray(dosis) || dosis.length === 0) {
        const opt = document.createElement('option');
        opt.value    = '';
        opt.disabled = true;
        opt.textContent = 'Sin dosis pendientes registradas';
        doseSelect.appendChild(opt);
      } else {
        const atrasadas = dosis.filter(d => d.status === 'Atrasada');
        const pendientes = dosis.filter(d => d.status !== 'Atrasada');

        const addGroup = (label, items) => {
          if (!items.length) return;
          const group = document.createElement('optgroup');
          group.label = label;
          items.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.patient_schedule_id;
            opt.textContent = d.dose_label || `${d.vaccine_name} — Dosis`;
            if (d.status === 'Atrasada') opt.style.color = 'var(--md-error)';
            group.appendChild(opt);
          });
          doseSelect.appendChild(group);
        };

        addGroup('⚠ Atrasadas', atrasadas);
        addGroup('Pendientes', pendientes);
      }

      /* Pre-seleccionar si viene ?schedule_id=... en la URL */
      const preselect = window.__PRESELECTSCHEDULE__;
      if (preselect) {
        doseSelect.value = String(preselect);
      }

      doseField.style.display = '';
    })
    .catch(err => {
      console.warn('No se pudieron cargar las dosis:', err);
      doseField.style.display = 'none';
    });
}

/* ── DateTime Split (date + selects de hora) ─────────────────────── */
const MESES_CORTOS = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
const MESES_LARGOS = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
                      'septiembre','octubre','noviembre','diciembre'];
const DIAS_SEMANA  = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];

function initDateTimeSplit() {
  const dateInput = document.getElementById('dt-date');
  const hourSel   = document.getElementById('dt-hour');
  const minSel    = document.getElementById('dt-min');
  const hidden    = document.getElementById('scheduled_at');
  const preview   = document.getElementById('dt-preview');

  if (!dateInput || !hourSel || !minSel || !hidden) return;

  const elMonth   = preview?.querySelector('.dt-tile__month');
  const elDay     = preview?.querySelector('.dt-tile__day');
  const elWeekday = preview?.querySelector('.dt-info__weekday');
  const elTime    = preview?.querySelector('.dt-info__time');
  const elFull    = preview?.querySelector('.dt-info__full');

  function combine() {
    const d = dateInput.value;
    const h = hourSel.value;
    const m = minSel.value;

    if (!d) {
      hidden.value = '';
      preview?.classList.remove('visible');
      return;
    }

    hidden.value = `${d}T${h}:${m}`;

    /* Actualizar preview */
    if (!preview) return;
    const [y, mo, day] = d.split('-').map(Number);
    const dt = new Date(y, mo - 1, day, Number(h), Number(m));
    if (isNaN(dt)) return;

    const ampm = Number(h) >= 12 ? 'PM' : 'AM';
    const h12  = String(Number(h) % 12 || 12).padStart(2, '0');

    if (elMonth)   elMonth.textContent   = MESES_CORTOS[dt.getMonth()];
    if (elDay)     elDay.textContent     = dt.getDate();
    if (elWeekday) elWeekday.textContent = DIAS_SEMANA[dt.getDay()];
    if (elTime)    elTime.textContent    = `${h12}:${m} ${ampm}`;
    if (elFull)    elFull.textContent    =
      `${DIAS_SEMANA[dt.getDay()]} ${dt.getDate()} de ${MESES_LARGOS[dt.getMonth()]} ${y}`;

    preview.classList.add('visible');
  }

  dateInput.addEventListener('change', combine);
  hourSel.addEventListener('change', combine);
  minSel.addEventListener('change', combine);
  combine(); // por si viene pre-cargado
}

/* ── Init ────────────────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {

  /* --- Typeahead: Paciente --------------------------------------- */
  const patWrap   = document.getElementById('ac-patient-wrap');
  const patHidden = document.getElementById('patient_id');
  if (patWrap && patHidden) {
    const raw      = document.getElementById('patients-data');
    const patients = raw ? JSON.parse(raw.textContent) : [];

    createTypeahead({
      wrapEl:   patWrap,
      hiddenEl: patHidden,
      items:    patients,
      getId:    p => p.patient_id,
      getLabel: p => p.full_name,
      getSub:   p => `ID: P${p.patient_id}`,
      filterFn: (p, q) =>
        normalize(p.full_name).includes(q) ||
        String(p.patient_id).includes(q),
      required: patHidden.hasAttribute('required'),
    });

    /* Recargar dosis cada vez que cambia el paciente seleccionado */
    patHidden.addEventListener('change', () => {
      loadPatientDoses(patHidden.value || null);
    });

    /* Si el paciente ya viene pre-seleccionado (p.ej. un solo hijo), cargar sus dosis */
    if (patHidden.value) {
      loadPatientDoses(patHidden.value);
    }
  }

  /* --- Typeahead: Médico / Enfermero ----------------------------- */
  const wrkWrap   = document.getElementById('ac-worker-wrap');
  const wrkHidden = document.getElementById('worker_id');
  if (wrkWrap && wrkHidden) {
    const raw = document.getElementById('workers-data');
    let workers = raw ? JSON.parse(raw.textContent) : [];

    /* Filtro de seguridad frontend: solo roles médicos */
    workers = workers.filter(w =>
      MEDICAL_ROLES.includes(normalize(w.role_name || ''))
    );

    createTypeahead({
      wrapEl:   wrkWrap,
      hiddenEl: wrkHidden,
      items:    workers,
      getId:    w => w.worker_id,
      getLabel: w => w.full_name,
      getSub:   w => w.role_name || '',
      filterFn: (w, q) =>
        normalize(w.full_name).includes(q) ||
        normalize(w.role_name || '').includes(q),
      required: false,
    });
  }

  /* --- Date + Time split ----------------------------------------- */
  initDateTimeSplit();
});
