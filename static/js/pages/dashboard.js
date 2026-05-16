/**
 * dashboard.js — Gráficas del panel clínico principal
 * Librería: Highcharts (cargado antes que este script)
 */
(function () {
  'use strict';

  if (typeof Highcharts === 'undefined') return;

  var _d        = window._dashCharts || {};
  var coverageData = _d.coverage || [];
  var dosesData    = _d.monthly  || [];
  var delayData    = _d.delays   || [];

  var sharedOptions = {
    chart:    { backgroundColor: 'transparent', style: { fontFamily: 'inherit' } },
    title:    { text: null },
    subtitle: { text: null },
    credits:  { enabled: false },
    legend:   { enabled: false },
  };

  /* ── Cobertura por grupo de edad (columnas) ──────────────────────────── */
  if (document.getElementById('coverageChart') && coverageData.length) {
    Highcharts.chart('coverageChart', Object.assign({}, sharedOptions, {
      chart: Object.assign({}, sharedOptions.chart, { type: 'column', height: 220 }),
      xAxis: {
        categories: coverageData.map(function (d) { return d.label; }),
        crosshair: true,
        lineColor:  '#c4c7c5',
        tickColor:  '#c4c7c5',
      },
      yAxis: {
        min: 0,
        max: 100,
        title: { text: null },
        labels: { format: '{value}%' },
        gridLineColor: '#f0f0f0',
      },
      tooltip: {
        valueSuffix: '%',
        headerFormat: '<b>{point.key}</b><br/>',
        pointFormat:  'Cobertura: <b>{point.y}%</b>',
      },
      plotOptions: {
        column: {
          borderRadius: 6,
          colorByPoint: true,
          colors: ['#4CAF7D', '#5B8DD9', '#29B6C5', '#F4A84A', '#AB6BD6'],
          dataLabels: {
            enabled: true,
            format: '{point.y}%',
            style: { fontSize: '11px', fontWeight: '600', textOutline: 'none' },
          },
        },
      },
      series: [{ name: 'Cobertura', data: coverageData.map(function (d) { return d.value; }) }],
    }));
  }

  /* ── Dosis aplicadas por mes (área) ──────────────────────────────────── */
  if (document.getElementById('dosesChart') && dosesData.length) {
    Highcharts.chart('dosesChart', Object.assign({}, sharedOptions, {
      chart: Object.assign({}, sharedOptions.chart, { type: 'area', height: 220 }),
      xAxis: {
        categories: dosesData.map(function (d) { return d.label; }),
        lineColor:  '#c4c7c5',
        tickColor:  '#c4c7c5',
      },
      yAxis: {
        min: 0,
        title: { text: null },
        allowDecimals: false,
        gridLineColor: '#f0f0f0',
      },
      tooltip: {
        headerFormat: '<b>{point.key}</b><br/>',
        pointFormat:  'Dosis aplicadas: <b>{point.y}</b>',
      },
      plotOptions: {
        area: {
          color: '#4f46e5',
          fillColor: {
            linearGradient: { x1: 0, y1: 0, x2: 0, y2: 1 },
            stops: [
              [0, 'rgba(79,70,229,0.30)'],
              [1, 'rgba(79,70,229,0.00)'],
            ],
          },
          lineWidth: 2.5,
          marker: { radius: 4, fillColor: '#4f46e5' },
        },
      },
      series: [{ name: 'Dosis', data: dosesData.map(function (d) { return d.value; }) }],
    }));
  }

  /* ── Retraso por vacuna (barras horizontales) ────────────────────────── */
  if (document.getElementById('delayChart') && delayData.length) {
    Highcharts.chart('delayChart', Object.assign({}, sharedOptions, {
      chart: Object.assign({}, sharedOptions.chart, { type: 'bar', height: 200 }),
      xAxis: {
        categories: delayData.map(function (d) { return d.label; }),
        lineColor:  '#c4c7c5',
        tickColor:  '#c4c7c5',
      },
      yAxis: {
        min: 0,
        max: 100,
        title: { text: null },
        labels: { format: '{value}%' },
        gridLineColor: '#f0f0f0',
      },
      tooltip: {
        valueSuffix: '%',
        headerFormat: '<b>{point.key}</b><br/>',
        pointFormat:  'Retraso: <b>{point.y}%</b>',
      },
      plotOptions: {
        bar: {
          color: '#E05252',
          borderRadius: 4,
        },
      },
      series: [{ name: 'Retraso', data: delayData.map(function (d) { return d.value; }) }],
    }));
  }

}());
