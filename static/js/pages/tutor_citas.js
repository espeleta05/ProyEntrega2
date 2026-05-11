/**
 * tutor_citas.js
 * Filtrado de tabla + AJAX aceptar/rechazar citas
 */
(function () {
  'use strict';

  /* ── Toast helper ─────────────────────────────────────────────────────── */
  function showToast(msg, ok) {
    var existing = document.querySelector('.tutor-toast');
    if (existing) existing.remove();

    var el = document.createElement('div');
    el.className = 'tutor-toast ' + (ok ? 'tutor-toast--ok' : 'tutor-toast--err');
    el.innerHTML = '<i class="fa-solid ' + (ok ? 'fa-circle-check' : 'fa-circle-xmark') + '"></i> ' + msg;
    document.body.appendChild(el);

    setTimeout(function () {
      el.style.opacity = '0';
      el.style.transition = 'opacity 0.3s';
      setTimeout(function () { el.remove(); }, 320);
    }, 3200);
  }

  /* ── Actualiza la celda de confirmación inline ────────────────────────── */
  function updateConfirmCell(appointmentId, accion) {
    var cell = document.getElementById('confirm-' + appointmentId);
    if (!cell) return;

    if (accion === 'aceptar') {
      cell.innerHTML =
        '<span class="ndt-badge ndt-badge--accepted">' +
        '<i class="fa-solid fa-circle-check"></i> Aceptada</span>';
    } else {
      cell.innerHTML =
        '<span class="ndt-badge ndt-badge--rejected">' +
        '<i class="fa-solid fa-circle-xmark"></i> No aceptada</span>';
    }
  }

  /* ── Elimina los botones de acción tras responder ─────────────────────── */
  function removeActionBtns(appointmentId) {
    var cell = document.getElementById('actions-' + appointmentId);
    if (cell) cell.innerHTML = '<span class="ndt-muted">—</span>';

    var row = cell ? cell.closest('tr') : null;
    if (row) {
      row.classList.remove('tutor-row-action');
      row.dataset.accepted = appointmentId;   // marca como procesada
    }
  }

  /* ── Envía la respuesta al servidor ──────────────────────────────────── */
  function responder(appointmentId, accion, btn) {
    btn.disabled = true;
    var sibling = btn.parentElement.querySelector(
      accion === 'aceptar' ? '.tutor-reject-btn' : '.tutor-accept-btn'
    );
    if (sibling) sibling.disabled = true;

    fetch('/tutor/cita/' + appointmentId + '/responder', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ accion: accion }),
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.ok) {
          updateConfirmCell(appointmentId, accion);
          removeActionBtns(appointmentId);
          showToast(
            accion === 'aceptar' ? 'Cita aceptada correctamente.' : 'Cita marcada como no aceptada.',
            true
          );
        } else {
          showToast('Error: ' + (data.error || 'No se pudo actualizar.'), false);
          btn.disabled = false;
          if (sibling) sibling.disabled = false;
        }
      })
      .catch(function () {
        showToast('Error de conexión. Intente de nuevo.', false);
        btn.disabled = false;
        if (sibling) sibling.disabled = false;
      });
  }

  /* ── Delegación de eventos en la tabla ───────────────────────────────── */
  var table = document.getElementById('tutorCitasTable');
  if (table) {
    table.addEventListener('click', function (e) {
      var btn = e.target.closest('.tutor-accept-btn, .tutor-reject-btn');
      if (!btn || btn.disabled) return;
      var id    = parseInt(btn.dataset.id,    10);
      var accion = btn.dataset.accion;
      responder(id, accion, btn);
    });
  }

  /* ── Filtros rápidos ─────────────────────────────────────────────────── */
  var filterBtns = document.querySelectorAll('.tutor-filter-btn');
  var rows       = table ? Array.from(table.querySelectorAll('tbody .tutor-cita-row')) : [];

  filterBtns.forEach(function (btn) {
    btn.addEventListener('click', function () {
      filterBtns.forEach(function (b) { b.classList.remove('active'); });
      btn.classList.add('active');

      var filter = btn.dataset.filter;

      rows.forEach(function (row) {
        var show = true;
        if (filter === 'all') {
          show = true;
        } else if (filter === 'pending') {
          var status   = row.dataset.status;
          var accepted = row.dataset.accepted;
          show = (status === 'programada' && accepted === 'none');
        } else {
          show = row.dataset.status === filter;
        }
        row.classList.toggle('tutor-row-hidden', !show);
      });
    });
  });

}());
