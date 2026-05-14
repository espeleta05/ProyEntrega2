/**
 * tutor_citas.js
 * [CORREGIDO] Eliminado AJAX aceptar/rechazar (flujo tutor_accepted deprecado).
 *             Conservados: toast helper y filtros de tabla.
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

  /* ── Filtros rápidos ─────────────────────────────────────────────────── */
  var table      = document.getElementById('tutorHistorialTable');
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
        } else {
          show = row.dataset.status === filter;
        }
        row.classList.toggle('tutor-row-hidden', !show);
      });
    });
  });

}());
