/*
 * mongo_reportes.js
 * Carga datos desde las APIs /api/mongo/* y renderiza las 3 gráficas con Highcharts.
 * Flujo: MongoDB → Flask (JSON) → Highcharts (frontend)
 */

(function () {

  // Paleta del proyecto
  const COLOR_PRIMARY  = '#6B007C';
  const COLOR_SECOND   = '#E8ABCE';
  const PALETA = ['#6B007C', '#E8ABCE', '#FF6F61', '#1ca657', '#2e90fa', '#f4b400'];

  Highcharts.setOptions({
    colors: PALETA,
    credits: { enabled: false },
    chart:   { style: { fontFamily: "'Open Sans', system-ui, sans-serif" }, backgroundColor: 'transparent' },
    title:   { style: { color: '#1a1a1a', fontWeight: '600', fontSize: '14px' } },
    xAxis:   { labels: { style: { color: '#49454f', fontSize: '11px' } } },
    yAxis:   { labels: { style: { color: '#49454f', fontSize: '11px' } } },
  });

  function getDias()   { return parseInt(document.getElementById('mrDias').value)  || 30; }
  function getMeses()  { return parseInt(document.getElementById('mrMeses').value) || 12; }

  async function apiFetch(url) {
    const r = await fetch(url, { credentials: 'same-origin' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json();
  }

  // ── Estado y conteos ────────────────────────────────────────

  async function cargarEstado() {
    try {
      const d = await apiFetch('/api/mongo/estado');
      if (!d.conectado) return;
      // (conteos removidos)
      //
      //
    } catch (_) {}
  }

  // ── Gráfica MongoDB: dosis aplicadas por clínica ────────────
  // Fuente: colección historial_vacunacion
  // Consulta: $group por clinica_nombre → barras comparativas

  async function cargarClinica() {
    const cont = document.getElementById('mrChartSerie');
    if (!cont) return;
    try {
      const d = await apiFetch('/api/mongo/historial/clinica?meses=6');
      if (!d.categorias.length) {
        cont.innerHTML = '<p style="padding:24px;color:#888">Sin datos disponibles.</p>';
        return;
      }
      Highcharts.chart(cont, {
        chart:   { type: 'bar', height: 280, backgroundColor: 'transparent' },
        title:   { text: 'Dosis aplicadas por clínica' },
        subtitle:{ text: 'Últimos 6 meses · Fuente: MongoDB (historial_vacunacion)' },
        xAxis:   { categories: d.categorias },
        yAxis:   { title: { text: 'Dosis aplicadas' }, allowDecimals: false },
        legend:  { enabled: false },
        plotOptions: { bar: { borderRadius: 4, dataLabels: { enabled: true } } },
        series:  [{ name: 'Dosis', data: d.datos, color: '#6B007C' }],
      });
    } catch (e) {
      cont.innerHTML = '<p style="padding:24px;color:#a02a2a">Error al cargar datos de MongoDB.</p>';
    }
  }

  // ── Reporte 1B: distribución por tipo ───────────────────────

  async function cargarTipos() {
    const cont = document.getElementById('mrChartTipos');
    try {
      const d = await apiFetch('/api/mongo/eventos/tipos?dias=' + getDias());
      if (!d.categorias.length) { cont.innerHTML = '<p style="padding:24px;color:#888">Sin datos.</p>'; return; }
      Highcharts.chart(cont, {
        chart:    { type: 'bar', height: 320 },
        title:    { text: 'Eventos por tipo' },
        subtitle: { text: 'Últimos ' + getDias() + ' días' },
        xAxis:    { categories: d.categorias },
        yAxis:    { title: { text: 'Total' }, allowDecimals: false },
        legend:   { enabled: false },
        plotOptions: { bar: { dataLabels: { enabled: true }, borderRadius: 3 } },
        series:   [{ name: 'Total', data: d.datos }],
      });
    } catch (e) {
      cont.innerHTML = '<p style="padding:24px;color:#a02a2a">Error al cargar datos.</p>';
    }
  }

  // ── Reporte 2A: barras comparativas por mes ──────────────────
  // Fuente: colección "historial_vacunacion"
  // Consulta: $group por anio_mes con dosis y pacientes únicos

  async function cargarMes() {
    const cont = document.getElementById('mrChartMes');
    try {
      const d = await apiFetch('/api/mongo/historial/mes?meses=' + getMeses());
      if (!d.categorias.length) { cont.innerHTML = '<p style="padding:24px;color:#888">Sin datos.</p>'; return; }
      Highcharts.chart(cont, {
        chart:   { height: 340 },
        title:   { text: 'Dosis aplicadas por mes' },
        subtitle:{ text: 'Fuente: historial_vacunacion (MongoDB) · Sincronizado desde PostgreSQL por pg_record_id' },
        xAxis:   { categories: d.categorias },
        yAxis:   [
          { title: { text: 'Dosis' }, allowDecimals: false },
          { title: { text: 'Pacientes únicos' }, opposite: true, allowDecimals: false },
        ],
        tooltip: { shared: true },
        series:  [
          { name: 'Dosis aplicadas', type: 'column', data: d.dosis,    color: COLOR_PRIMARY, borderRadius: 3 },
          { name: 'Pacientes únicos', type: 'spline', data: d.pacientes, color: '#1ca657', yAxis: 1 },
        ],
      });
    } catch (e) {
      cont.innerHTML = '<p style="padding:24px;color:#a02a2a">Error al cargar datos.</p>';
    }
  }

  // ── Reporte 2B: barras por vacuna ────────────────────────────

  async function cargarVacuna() {
    const cont = document.getElementById('mrChartVacuna');
    if (!cont) return;
    try {
      const d = await apiFetch('/api/mongo/historial/vacuna?meses=' + getMeses());
      if (!d.categorias.length) { cont.innerHTML = '<p style="padding:24px;color:#888">Sin datos.</p>'; return; }
      Highcharts.chart(cont, {
        chart:   { type: 'column', height: 340 },
        title:   { text: 'Top vacunas aplicadas' },
        subtitle:{ text: 'Últimos ' + getMeses() + ' meses' },
        xAxis:   { categories: d.categorias, labels: { rotation: -30 } },
        yAxis:   { title: { text: 'Dosis' }, allowDecimals: false },
        legend:  { enabled: false },
        plotOptions: { column: { borderRadius: 4 } },
        series:  [{ name: 'Dosis', data: d.datos }],
      });
    } catch (e) {
      cont.innerHTML = '<p style="padding:24px;color:#a02a2a">Error al cargar datos.</p>';
    }
  }

  // ── Reporte 3: indicadores dinámicos (solid-gauge) ───────────
  // Fuente: historial_vacunacion (MongoDB)
  // Consulta: $group + $cond + $divide → porcentaje de reacción

  async function cargarReaccion() {
    const cont = document.getElementById('mrGauges');
    cont.innerHTML = '';
    try {
      const d = await apiFetch('/api/mongo/historial/reaccion?meses=' + getMeses());
      if (!d.items.length) {
        cont.innerHTML = '<p style="color:#888;padding:12px">Sin datos de reacciones.</p>';
        return;
      }
      d.items.slice(0, 6).forEach(function (item, i) {
        var card = document.createElement('div');
        card.className = 'mr-gauge-card';
        card.innerHTML = '<h4>' + item.vacuna + '</h4><div id="gauge' + i + '" style="width:100%;height:160px"></div>'
          + '<span class="mr-gauge-meta">' + item.reacciones + ' / ' + item.total + ' aplicaciones</span>';
        cont.appendChild(card);

        Highcharts.chart('gauge' + i, {
          chart: { type: 'solidgauge', height: 160, margin: [0,0,0,0], backgroundColor: 'transparent' },
          title: null,
          pane:  {
            center: ['50%', '85%'], size: '140%',
            startAngle: -90, endAngle: 90,
            background: { backgroundColor: '#f0e8f5', borderWidth: 0, innerRadius: '60%', outerRadius: '100%', shape: 'arc' },
          },
          tooltip: { enabled: false },
          yAxis: {
            min: 0, max: 20,
            stops: [[0.33, '#1ca657'], [0.66, '#f4b400'], [1, '#c62828']],
            lineWidth: 0, tickWidth: 0, minorTickInterval: null,
            labels: { y: 16, style: { fontSize: '10px' } },
          },
          plotOptions: {
            solidgauge: {
              dataLabels: {
                y: -22, borderWidth: 0, useHTML: true,
                format: '<div style="text-align:center"><span style="font-size:1.3rem;color:#6B007C;font-weight:700">{y:.1f}%</span></div>',
              },
            },
          },
          series: [{ name: 'Tasa', data: [Math.min(item.tasa, 20)] }],
        });
      });
    } catch (e) {
      cont.innerHTML = '<p style="color:#a02a2a;padding:12px">Error al cargar indicadores.</p>';
    }
  }

  // ── Carga automática junto con la página de reportes ────────

  document.addEventListener('DOMContentLoaded', function () {
    // mrChartSerie se carga sola; los demás (mrChartTipos, mrChartMes, etc.)
    // ya no existen en el HTML, así que las funciones con null-check no hacen nada.
    cargarClinica();
  });

})();
