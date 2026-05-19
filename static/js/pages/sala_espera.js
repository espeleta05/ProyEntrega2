/* ============================================================
   Monitor de Sala — lógica de tiempo real
   Polling cada 10 seg → /api/visits/realtime
   NFC scan manual → /api/nfc/scan
   Checkout manual → /api/visits/<id>/transition
   ============================================================ */

const POLL_MS   = 10_000;
const cfg       = document.getElementById('sala-config');
const WORKER_ID = cfg?.dataset.workerId  || '';
const DEVICE_ID = null;

let pollTimer        = null;
let pendingCheckout  = null;   // { visitId, patientName }

// ── Reloj ──────────────────────────────────────────────────
function tickClock() {
  const el = document.getElementById('salaClock');
  if (!el) return;
  const now = new Date();
  el.textContent = now.toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' });
}
setInterval(tickClock, 1000);
tickClock();

// ── Helpers de formato ─────────────────────────────────────
function minutesAgo(isoStr) {
  if (!isoStr) return null;
  return Math.floor((Date.now() - new Date(isoStr).getTime()) / 60_000);
}

function initials(name) {
  return (name || '??').split(' ').slice(0, 2).map(w => w[0]).join('').toUpperCase();
}

function timerLabel(mins, colType) {
  if (mins === null) return '';
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  const text = h > 0 ? `${h}h ${m}min` : `${m} min`;
  const icon = colType === 'espera' ? 'fa-hourglass-half' : 'fa-stethoscope';
  const label = colType === 'espera' ? 'esperando' : 'en consulta';
  return `<i class="fa-solid ${icon}"></i> ${text} ${label}`;
}

function timerClass(mins, colType) {
  if (colType !== 'espera') return 'pc-timer--ok';
  if (mins > 30) return 'pc-timer--alert';
  if (mins > 15) return 'pc-timer--warn';
  return 'pc-timer--ok';
}

// ── Construir tarjeta de paciente ──────────────────────────
function buildCard(v, colType) {
  const timeRef  = colType === 'espera' ? v.waiting_since : v.consultation_start;
  const mins     = minutesAgo(timeRef);
  const tClass   = timerClass(mins, colType);
  const tLabel   = timerLabel(mins, colType);
  const avClass  = colType === 'espera' ? 'pc-avatar--espera' : 'pc-avatar--consulta';
  const ini      = initials(v.full_name);
  const age      = v.age != null ? `${v.age} años` : '';

  let badges = '';
  if (v.has_allergies)        badges += `<span class="md3-badge md3-badge--sm md3-badge--error"  title="Alergias"><i class="fa-solid fa-triangle-exclamation"></i> Alergia</span>`;
  if (v.has_overdue_vaccines) badges += `<span class="md3-badge md3-badge--sm md3-badge--warning" title="Vacunas atrasadas"><i class="fa-solid fa-syringe"></i> Vacunas</span>`;
  if (v.wait_time_alert)      badges += `<span class="md3-badge md3-badge--sm md3-badge--error"  title="Más de 30 min esperando"><i class="fa-solid fa-clock"></i> +30 min</span>`;

  const apptBadge = v.appointment_id
    ? `<span class="md3-badge md3-badge--sm md3-badge--primary" title="Cita programada"><i class="fa-solid fa-calendar-check"></i></span>`
    : '';

  return `
  <div class="patient-card" data-visit-id="${v.visit_id}">
    <div class="pc-top">
      <div class="pc-avatar ${avClass}">${ini}</div>
      <div class="pc-info">
        <div class="pc-name">${v.full_name || '—'}</div>
        <div class="pc-meta">${age}${age && v.current_area ? ' · ' : ''}${v.current_area || ''}</div>
      </div>
      ${apptBadge}
    </div>
    ${tLabel ? `<div class="pc-timer ${tClass}">${tLabel}</div>` : ''}
    ${badges ? `<div class="pc-badges">${badges}</div>` : ''}
    <div class="pc-actions">
      <button class="md3-btn md3-btn--outlined md3-btn--sm"
              onclick="openCheckout(${v.visit_id}, '${(v.full_name || '').replace(/'/g, '')}')"
              title="Dar de alta">
        <i class="fa-solid fa-right-from-bracket"></i> Alta
      </button>
    </div>
  </div>`;
}

// ── Renderizar tablero ─────────────────────────────────────
function renderBoard(visits) {
  const espera   = visits.filter(v => v.visit_status === 'En espera');
  const consulta = visits.filter(v => v.visit_status === 'En consulta');

  // Actualizar contadores
  document.getElementById('cntEspera').textContent   = espera.length;
  document.getElementById('cntConsulta').textContent = consulta.length;

  // Columna En espera
  const colE = document.getElementById('colEspera');
  if (espera.length === 0) {
    colE.innerHTML = '<div class="patient-card patient-card--empty"><i class="fa-solid fa-couch"></i><p>Sin pacientes en espera</p></div>';
  } else {
    colE.innerHTML = espera.map(v => buildCard(v, 'espera')).join('');
  }

  // Columna En consulta
  const colC = document.getElementById('colConsulta');
  if (consulta.length === 0) {
    colC.innerHTML = '<div class="patient-card patient-card--empty"><i class="fa-solid fa-stethoscope"></i><p>Sin pacientes en consulta</p></div>';
  } else {
    colC.innerHTML = consulta.map(v => buildCard(v, 'consulta')).join('');
  }

  // Última actualización
  const now = new Date().toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const lastEl = document.getElementById('resumenLast');
  if (lastEl) lastEl.innerHTML = `<i class="fa-solid fa-clock"></i> <span>Actualizado: ${now}</span>`;
}

// ── Polling ────────────────────────────────────────────────
async function poll() {
  try {
    const res  = await fetch('/api/visits/realtime');
    if (!res.ok) return;
    const data = await res.json();
    renderBoard(data.visits || []);
    // Actualizar finalizados
    const finEl = document.getElementById('statFin');
    if (finEl && data.finalizados_hoy != null) {
      finEl.textContent = data.finalizados_hoy;
      document.getElementById('cntFin').textContent = data.finalizados_hoy;
    }
  } catch (_) { /* red cortada — silencioso */ }
}

function startPolling() {
  poll();
  pollTimer = setInterval(poll, POLL_MS);
}

document.getElementById('btnRefresh')?.addEventListener('click', () => {
  poll();
});

// ── Escaneo NFC ────────────────────────────────────────────
function showScanResult(ok, msg) {
  const el = document.getElementById('scanResult');
  if (!el) return;
  el.className = `scan-result scan-result--${ok ? 'ok' : 'error'}`;
  el.innerHTML = `<i class="fa-solid fa-${ok ? 'circle-check' : 'circle-xmark'}"></i> ${msg}`;
  clearTimeout(el._timer);
  el._timer = setTimeout(() => { el.className = 'scan-result scan-result--hidden'; }, 6000);
}

async function doNfcScan(uid, context) {
  if (!uid) return;
  try {
    const res  = await fetch('/api/nfc/scan', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid, context, device_id: DEVICE_ID }),
    });
    const data = await res.json();
    const ok   = data.success === true || data.success === 'true';
    const msg  = data.message || (ok ? 'Procesado correctamente' : 'Error al procesar');
    showScanResult(ok, msg);
    if (ok) {
      setTimeout(poll, 600); // refresca rápido tras scan exitoso
    }
  } catch (e) {
    showScanResult(false, 'Error de red al procesar el escaneo');
  }
}

document.getElementById('btnNfcScan')?.addEventListener('click', () => {
  const uid = document.getElementById('nfcUidInput').value.trim();
  const ctx = document.getElementById('nfcContextSelect').value;
  if (!uid) { showScanResult(false, 'Ingresa o escanea un UID NFC'); return; }
  doNfcScan(uid, ctx);
  document.getElementById('nfcUidInput').value = '';
});

// Procesar al presionar Enter en el input
document.getElementById('nfcUidInput')?.addEventListener('keydown', e => {
  if (e.key === 'Enter') document.getElementById('btnNfcScan').click();
});

// Foco automático al cargar (lector NFC físico escribe en el input activo)
window.addEventListener('load', () => {
  document.getElementById('nfcUidInput')?.focus();
});

// ── Checkout manual ────────────────────────────────────────
function openCheckout(visitId, patientName) {
  pendingCheckout = { visitId, patientName };
  const modal = document.getElementById('checkoutModal');
  const body  = document.getElementById('checkoutModalBody');
  if (body) body.textContent = `¿Dar de alta a ${patientName}?`;
  modal.hidden = false;
}

document.getElementById('checkoutCancel')?.addEventListener('click', () => {
  document.getElementById('checkoutModal').hidden = true;
  pendingCheckout = null;
});

document.getElementById('checkoutConfirm')?.addEventListener('click', async () => {
  if (!pendingCheckout) return;
  document.getElementById('checkoutModal').hidden = true;
  try {
    const res  = await fetch(`/api/visits/${pendingCheckout.visitId}/transition`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'Finalizado', area_id: null, notes: 'Alta manual desde monitor de sala' }),
    });
    const data = await res.json();
    const ok   = data.success === true || data.success === 'true';
    showScanResult(ok, ok ? `Alta registrada: ${pendingCheckout.patientName}` : (data.message || 'Error al dar de alta'));
    if (ok) setTimeout(poll, 400);
  } catch (_) {
    showScanResult(false, 'Error de red al dar de alta');
  }
  pendingCheckout = null;
});

// Cerrar modal al hacer clic fuera
document.getElementById('checkoutModal')?.addEventListener('click', e => {
  if (e.target === document.getElementById('checkoutModal')) {
    document.getElementById('checkoutModal').hidden = true;
    pendingCheckout = null;
  }
});

// ── Inicio ─────────────────────────────────────────────────
startPolling();
