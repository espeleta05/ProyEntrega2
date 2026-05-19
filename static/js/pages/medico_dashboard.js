(function () {
  'use strict';

  function renderChart() {
    var dataEl  = document.getElementById('medico-chart-data');
    var chartEl = document.getElementById('chartCitasSemana');
    if (!dataEl || !chartEl) return;

    var chartData;
    try {
      chartData = JSON.parse(dataEl.dataset.semana || '[]');
    } catch (e) {
      chartEl.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">Error al cargar datos.</p>';
      return;
    }

    if (!Array.isArray(chartData) || chartData.length === 0) {
      chartEl.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">Sin citas esta semana.</p>';
      return;
    }

    var style        = getComputedStyle(document.documentElement);
    var colorPrimary = style.getPropertyValue('--md-primary').trim() || '#6B007C';
    var colorVariant = style.getPropertyValue('--md-outline-variant').trim() || '#c4c7c5';

    Highcharts.chart('chartCitasSemana', {
      chart: {
        type: 'column',
        backgroundColor: 'transparent',
        style: { fontFamily: 'inherit' },
        height: 220,
      },
      title:    { text: null },
      credits:  { enabled: false },
      legend:   { enabled: false },
      xAxis: {
        categories: chartData.map(function (d) { return d.dia_label; }),
        crosshair:  true,
        lineColor:  colorVariant,
        tickColor:  colorVariant,
        labels: { style: { fontSize: '13px' } },
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
        pointFormat:  'Citas: <b>{point.y}</b>',
      },
      plotOptions: {
        column: {
          borderRadius: 6,
          color: colorPrimary,
          dataLabels: {
            enabled: true,
            style: { fontSize: '12px', fontWeight: '500', color: colorPrimary, textOutline: 'none' },
            formatter: function () { return this.y > 0 ? this.y : ''; },
          },
        },
      },
      series: [{
        name: 'Citas',
        data: chartData.map(function (d) { return d.total || 0; }),
      }],
    });
  }

  function waitForHighcharts(attempts) {
    if (typeof Highcharts !== 'undefined') {
      renderChart();
      return;
    }
    if (attempts <= 0) {
      var el = document.getElementById('chartCitasSemana');
      if (el) el.innerHTML = '<p style="text-align:center;padding:32px;color:var(--md-on-surface-variant);">No se pudo cargar Highcharts.</p>';
      return;
    }
    setTimeout(function () { waitForHighcharts(attempts - 1); }, 200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { waitForHighcharts(25); });
  } else {
    waitForHighcharts(25);
  }

}());
