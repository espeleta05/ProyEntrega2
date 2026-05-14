(() => {
  'use strict';

  if (typeof Highcharts === 'undefined') return;

  const dataEl = document.getElementById('medico-chart-data');
  if (!dataEl) return;

  let chartData;
  try {
    chartData = JSON.parse(dataEl.dataset.semana || '[]');
  } catch (e) {
    return;
  }

  if (!Array.isArray(chartData) || chartData.length === 0) return;
  if (!document.getElementById('chartCitasSemana')) return;

  const style        = getComputedStyle(document.documentElement);
  const colorPrimary = style.getPropertyValue('--md-primary').trim() || '#6B007C';
  const colorVariant = style.getPropertyValue('--md-outline-variant').trim() || '#c4c7c5';

  Highcharts.chart('chartCitasSemana', {
    chart: {
      type: 'column',
      backgroundColor: 'transparent',
      style: { fontFamily: 'inherit' },
      height: 220,
    },
    title:   { text: null },
    credits: { enabled: false },
    legend:  { enabled: false },
    xAxis: {
      categories: chartData.map(d => d.dia_label),
      crosshair:  true,
      lineColor:  colorVariant,
      tickColor:  colorVariant,
    },
    yAxis: {
      min: 0,
      allowDecimals: false,
      title: { text: null },
      gridLineColor: colorVariant,
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
          formatter() { return this.y > 0 ? this.y : ''; },
        },
      },
    },
    series: [{ name: 'Citas', data: chartData.map(d => d.total) }],
  });
})();
