(function () {
  'use strict';

  /* ── Highcharts: consumo semanal por lote crítico ── */
  function renderAlmacenChart() {
    var dataEl  = document.getElementById('almacen-chart-data');
    var chartEl = document.getElementById('chartConsumoSemana');
    if (!dataEl || !chartEl) return;

    var lotesCriticos;
    try {
      lotesCriticos = JSON.parse(dataEl.dataset.lotesCriticos || '[]');
    } catch (e) {
      chartEl.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">Error al cargar datos.</p>';
      return;
    }

    if (!Array.isArray(lotesCriticos) || lotesCriticos.length === 0) {
      chartEl.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">Sin lotes críticos esta semana.</p>';
      return;
    }

    var style        = getComputedStyle(document.documentElement);
    var colorPrimary = style.getPropertyValue('--md-primary').trim()         || '#6B007C';
    var colorError   = style.getPropertyValue('--md-error').trim()           || '#b3261e';
    var colorVariant = style.getPropertyValue('--md-outline-variant').trim() || '#c4c7c5';

    var categories = lotesCriticos.map(function (l) {
      return l.vaccine_name + '\n' + l.lot_number;
    });

    var stockData = lotesCriticos.map(function (l) {
      var qty = l.quantity_available || 0;
      return { y: qty, color: qty <= 5 ? colorError : colorPrimary };
    });

    Highcharts.chart('chartConsumoSemana', {
      chart: {
        type: 'column',
        backgroundColor: 'transparent',
        style: { fontFamily: 'inherit' },
        height: 220,
      },
      title:    { text: null },
      subtitle: { text: null },
      credits:  { enabled: false },
      legend:   { enabled: false },
      xAxis: {
        categories: categories,
        crosshair:  true,
        lineColor:  colorVariant,
        tickColor:  colorVariant,
        labels: { style: { fontSize: '12px' } },
      },
      yAxis: {
        min: 0,
        allowDecimals: false,
        title: { text: null },
        gridLineColor: colorVariant,
        labels: { style: { fontSize: '12px' } },
      },
      tooltip: {
        headerFormat: '<b>{point.key}</b><br/>',
        pointFormat:  'Dosis disponibles: <b>{point.y}</b>',
      },
      plotOptions: {
        column: {
          borderRadius: 6,
          dataLabels: {
            enabled: true,
            style: { fontSize: '12px', fontWeight: '600', textOutline: 'none' },
            formatter: function () { return this.y > 0 ? this.y : ''; },
          },
        },
      },
      series: [{ name: 'Dosis disponibles', data: stockData }],
    });
  }

  function waitForHighchartsAlmacen(attempts) {
    if (typeof Highcharts !== 'undefined') {
      renderAlmacenChart();
      return;
    }
    if (attempts <= 0) {
      var el = document.getElementById('chartConsumoSemana');
      if (el) el.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">No se pudo cargar Highcharts.</p>';
      return;
    }
    setTimeout(function () { waitForHighchartsAlmacen(attempts - 1); }, 200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { waitForHighchartsAlmacen(25); });
  } else {
    waitForHighchartsAlmacen(25);
  }

  /* ── Auto-refresh del badge de alertas cada 60 segundos ── */
  function refreshAlerts() {
    fetch('/api/almacen/alertas', { credentials: 'same-origin' })
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (data) {
        if (!data) return;

        var badge = document.querySelector('.chart-badge[data-alert-count]');
        if (badge) badge.textContent = data.length;

        var panel = document.querySelector('.almacen-alerts-list');
        if (!panel || !Array.isArray(data)) return;

        if (data.length === 0) {
          panel.innerHTML =
            '<div class="md3-alert md3-alert--success md3-alert--compact">' +
            '<i class="fa-solid fa-circle-check"></i>' +
            '<span>Sin alertas de inventario activas.</span>' +
            '</div>';
          return;
        }

        panel.innerHTML = data.slice(0, 10).map(function (a) {
          var isCritical = a.alert_type === 'Critico';
          var cls  = isCritical ? 'md3-alert--error'   : 'md3-alert--warning';
          var icon = isCritical ? 'fa-circle-exclamation' : 'fa-clock';
          return (
            '<div class="md3-alert ' + cls + ' md3-alert--compact">' +
            '<i class="fa-solid ' + icon + '"></i>' +
            '<span>' + a.vaccine_name + ' · ' + a.lot_number + ' — ' + a.alert_reason + '</span>' +
            '</div>'
          );
        }).join('');
      })
      .catch(function () { /* silencioso */ });
  }

  setInterval(refreshAlerts, 60000);

}());
