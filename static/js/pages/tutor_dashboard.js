/**
 * tutor_dashboard.js
 * Donut chart de progreso vacunal — portal familiar
 * Librería: Highcharts (cargado antes que este script)
 */
(function () {
  'use strict';

  if (typeof Highcharts === 'undefined') return;

  var dataEl = document.getElementById('tutor-chart-data');
  if (!dataEl) return;

  var applied  = parseInt(dataEl.dataset.applied  || '0', 10);
  var pending  = parseInt(dataEl.dataset.pending  || '0', 10);
  var total    = applied + pending;

  if (!document.getElementById('tutorDonutChart')) return;

  var style          = getComputedStyle(document.documentElement);
  var colorSuccess   = style.getPropertyValue('--md-success').trim()          || '#1D7B00';
  var colorVariant   = style.getPropertyValue('--md-outline-variant').trim()  || '#c4c7c5';
  var colorSurface   = style.getPropertyValue('--md-surface-container').trim()|| '#f4eff8';
  var colorOnSurface = style.getPropertyValue('--md-on-surface').trim()       || '#1a1a1a';

  var pct = total > 0 ? Math.round(applied / total * 100) : 0;

  Highcharts.chart('tutorDonutChart', {
    chart: {
      type: 'pie',
      backgroundColor: 'transparent',
      style: { fontFamily: 'inherit' },
      height: 220,
      margin: [0, 0, 0, 0],
    },
    title:    { text: null },
    subtitle: { text: null },
    credits:  { enabled: false },
    legend:   { enabled: false },

    tooltip: {
      pointFormat: '<b>{point.name}</b>: {point.y} dosis ({point.percentage:.0f}%)',
    },

    plotOptions: {
      pie: {
        innerSize: '62%',
        borderWidth: 0,
        dataLabels: { enabled: false },
        states: {
          hover: { halo: { size: 6 } },
        },
      },
    },

    series: [{
      name: 'Dosis',
      data: [
        {
          name:  'Aplicadas',
          y:      applied,
          color:  colorSuccess,
        },
        {
          name:  'Pendientes',
          y:      pending,
          color:  colorVariant,
        },
      ],
    }],
  }, function (chart) {
    /* Texto central: porcentaje grande */
    var cx = chart.plotLeft + chart.plotWidth  / 2;
    var cy = chart.plotTop  + chart.plotHeight / 2;

    chart.renderer.text(pct + '%', cx, cy - 6)
      .attr({ align: 'center', zIndex: 5 })
      .css({
        fontSize:   '1.6rem',
        fontWeight: '800',
        color:      colorOnSurface,
        fontFamily: 'inherit',
      })
      .add();

    chart.renderer.text('completado', cx, cy + 16)
      .attr({ align: 'center', zIndex: 5 })
      .css({
        fontSize:   '0.68rem',
        fontWeight: '600',
        color:      '#49454f',
        fontFamily: 'inherit',
      })
      .add();
  });

}());
