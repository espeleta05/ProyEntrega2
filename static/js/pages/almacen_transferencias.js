(function () {
  'use strict';

  /* ── Filtros de tabla ── */
  var table = document.getElementById('transTable');

  function getRows() {
    return table ? Array.from(table.querySelectorAll('tbody tr')) : [];
  }

  window.applyFilters = function () {
    var q      = (document.getElementById('searchInput')    || {value: ''}).value.trim().toLowerCase();
    var status = (document.getElementById('statusFilterBar') || {value: ''}).value.toLowerCase();
    var count  = 0;

    getRows().forEach(function (row) {
      var vaccine = (row.dataset.vaccine || '');
      var lot     = (row.dataset.lot     || '');
      var from    = (row.dataset.from    || '');
      var to      = (row.dataset.to      || '');
      var st      = (row.dataset.status  || '');

      var matchQ = !q || vaccine.includes(q) || lot.includes(q) || from.includes(q) || to.includes(q);
      var matchS = !status || st === status;

      var visible = matchQ && matchS;
      row.style.display = visible ? '' : 'none';
      if (visible) count++;
    });

    var tfoot = table ? table.querySelector('tfoot td') : null;
    if (tfoot) tfoot.textContent = 'Total: ' + count + ' transferencia(s) visible(s)';
  };

  /* ── Utilidad: abrir / cerrar modales ── */
  window.closeModal = function (id) {
    var el = document.getElementById(id);
    if (el) { el.classList.remove('active'); el.hidden = true; }
    document.body.style.overflow = '';
  };

  function openModal(id) {
    var el = document.getElementById(id);
    if (el) { el.hidden = false; el.classList.add('active'); document.body.style.overflow = 'hidden'; }
  }

  /* Cerrar con Escape o clic en overlay */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      ['nuevaTransModal', 'solicitarModal', 'aceptarModal', 'rechazarModal', 'cancelarModal'].forEach(window.closeModal);
    }
  });
  ['nuevaTransModal', 'solicitarModal', 'aceptarModal', 'rechazarModal', 'cancelarModal'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) {
      el.addEventListener('click', function (e) {
        if (e.target === el) window.closeModal(id);
      });
    }
  });

  /* ── Modal: Nueva transferencia ── */
  window.openNuevaTransModal = function () {
    openModal('nuevaTransModal');
  };

  /* ── Modal: Solicitar stock ── */
  window.openSolicitarModal = function () {
    openModal('solicitarModal');
  };

  window.updateSolStock = function () {
    var sel   = document.getElementById('solLotSelect');
    var hint  = document.getElementById('solStockHint');
    var input = document.getElementById('solQtyInput');
    var clinicSel = document.getElementById('solClinicSelect');
    if (!sel || !hint || !input) return;

    var opt      = sel.options[sel.selectedIndex];
    var stock    = opt ? parseInt(opt.dataset.stock    || '0', 10) : 0;
    var originId = opt ? (opt.dataset.clinicId || '')              : '';

    hint.textContent = stock > 0 ? 'Stock disponible: ' + stock + ' dosis' : '';
    input.max = stock > 0 ? stock : '';

    // Para admin (sin clínica fija): ocultar la clínica origen en destino
    if (clinicSel) {
      Array.from(clinicSel.options).forEach(function (o) {
        if (!o.value) return;
        var hide = originId && o.value === originId;
        o.hidden = hide; o.disabled = hide;
        if (hide && clinicSel.value === o.value) clinicSel.value = '';
      });
    }
  };

  /* Validar cantidad al enviar solicitud */
  var formSolicitar = document.querySelector('#solicitarModal form');
  if (formSolicitar) {
    formSolicitar.addEventListener('submit', function (e) {
      var sel   = document.getElementById('solLotSelect');
      var input = document.getElementById('solQtyInput');
      if (!sel || !input) return;
      var stock = parseInt((sel.options[sel.selectedIndex] || {}).dataset.stock || '0', 10);
      var qty   = parseInt(input.value, 10);
      if (qty > stock) {
        e.preventDefault();
        alert('La cantidad solicitada (' + qty + ') supera el stock disponible (' + stock + ').');
      }
    });
  }

  /* Actualizar hint de stock y filtrar clínica destino al cambiar lote */
  window.updateTransStock = function () {
    var sel        = document.getElementById('transLotSelect');
    var hint       = document.getElementById('transStockHint');
    var input      = document.getElementById('transQtyInput');
    var clinicSel  = document.getElementById('transClinicSelect');
    if (!sel || !hint || !input) return;

    var opt        = sel.options[sel.selectedIndex];
    var stock      = opt ? parseInt(opt.dataset.stock    || '0', 10) : 0;
    var originId   = opt ? (opt.dataset.clinicId || '')              : '';

    hint.textContent = stock > 0 ? 'Stock disponible: ' + stock + ' dosis' : '';
    input.max = stock > 0 ? stock : '';

    // Ocultar la clínica de origen en el dropdown destino
    if (clinicSel) {
      Array.from(clinicSel.options).forEach(function (o) {
        if (!o.value) return; // placeholder
        var hide = originId && o.value === originId;
        o.hidden   = hide;
        o.disabled = hide;
        if (hide && clinicSel.value === o.value) clinicSel.value = '';
      });
    }
  };

  /* Validar cantidad no excede stock al enviar */
  var formNueva = document.querySelector('#nuevaTransModal form');
  if (formNueva) {
    formNueva.addEventListener('submit', function (e) {
      var sel   = document.getElementById('transLotSelect');
      var input = document.getElementById('transQtyInput');
      if (!sel || !input) return;

      var opt   = sel.options[sel.selectedIndex];
      var stock = opt ? parseInt(opt.dataset.stock || '0', 10) : 0;
      var qty   = parseInt(input.value, 10);

      if (qty > stock) {
        e.preventDefault();
        alert('La cantidad solicitada (' + qty + ') supera el stock disponible (' + stock + ').');
      }
    });
  }

  /* ── Modal: Aceptar ── */
  window.openAceptarModal = function (transferId, vaccineName, lotNumber, quantity, fromClinic, toClinic) {
    var form  = document.getElementById('formAceptar');
    var label = document.getElementById('aceptarLabel');

    if (form)  form.action = '/almacen/transferencias/' + transferId + '/aceptar';
    if (label) label.textContent =
      vaccineName + ' · Lote ' + lotNumber +
      ' — ' + quantity + ' dosis de ' + fromClinic + ' → ' + toClinic;

    openModal('aceptarModal');
  };

  /* ── Modal: Rechazar ── */
  window.openRechazarModal = function (transferId, vaccineName, lotNumber) {
    var form  = document.getElementById('formRechazar');
    var label = document.getElementById('rechazarLabel');

    if (form)  form.action = '/almacen/transferencias/' + transferId + '/rechazar';
    if (label) label.textContent =
      '¿Rechazar la transferencia de ' + vaccineName + ' · Lote ' + lotNumber + '?';

    openModal('rechazarModal');
  };

  /* ── Modal: Cancelar ── */
  window.openCancelarModal = function (transferId, vaccineName, lotNumber) {
    var form  = document.getElementById('formCancelar');
    var label = document.getElementById('cancelarLabel');

    if (form)  form.action = '/almacen/transferencias/' + transferId + '/cancelar';
    if (label) label.textContent =
      '¿Cancelar la transferencia de ' + vaccineName + ' · Lote ' + lotNumber + '?';

    openModal('cancelarModal');
  };

}());
