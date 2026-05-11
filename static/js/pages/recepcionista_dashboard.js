/**
 * recepcionista_dashboard.js
 * Gráfica de pacientes registrados por día (semana actual) — Highcharts
 * Lee los datos del elemento #rec-chart-data para evitar JS inline.
 */
(function () {
  'use strict';

  if (typeof Highcharts === 'undefined') return;

  var dataEl = document.getElementById('rec-chart-data');
  if (!dataEl) return;

  var chartData;
  try {
    chartData = JSON.parse(dataEl.dataset.semana || '[]');
  } catch (e) {
    console.error('[recepcionista_dashboard] Error al parsear datos de gráfica:', e);
    return;
  }

  if (!Array.isArray(chartData) || chartData.length === 0) return;

  if (!document.getElementById('chartPacientesSemana')) return;

  var style          = getComputedStyle(document.documentElement);
  var colorPrimary   = style.getPropertyValue('--md-primary').trim()           || '#6B007C';
  var colorContainer = style.getPropertyValue('--md-primary-container').trim() || '#FAD9FF';
  var colorVariant   = style.getPropertyValue('--md-outline-variant').trim()   || '#c4c7c5';

  Highcharts.chart('chartPacientesSemana', {
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
      pointFormat:  'Pacientes registrados: <b>{point.y}</b>',
    },

    plotOptions: {
      column: {
        borderRadius: 6,
        color: colorPrimary,
        dataLabels: {
          enabled: true,
          style: {
            fontSize: '12px',
            fontWeight: '500',
            color: colorPrimary,
            textOutline: 'none',
          },
          formatter: function () {
            return this.y > 0 ? this.y : '';
          },
        },
      },
    },

    series: [{
      name: 'Pacientes',
      data: chartData.map(function (d) { return d.total; }),
    }],
  });

}());
