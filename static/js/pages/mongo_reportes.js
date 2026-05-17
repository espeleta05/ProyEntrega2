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
    accessibility: { enabled: false },
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
        chart:   { type: 'areaspline', height: 340 },
        title:   { text: 'Dosis aplicadas por mes' },
        subtitle:{ text: 'Fuente: historial_vacunacion (MongoDB) · Sincronizado desde PostgreSQL por pg_record_id' },
        xAxis:   { categories: d.categorias },
        yAxis:   [
          { title: { text: 'Dosis' }, allowDecimals: false },
          { title: { text: 'Pacientes únicos' }, opposite: true, allowDecimals: false },
        ],
        tooltip: { shared: true },
        plotOptions: { areaspline: { fillOpacity: 0.2 } },
        series:  [
          { name: 'Dosis aplicadas', data: d.dosis,    color: COLOR_PRIMARY },
          { name: 'Pacientes únicos', data: d.pacientes, color: '#1ca657', yAxis: 1 },
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

  // ── Reporte 3: distribución por edad ────────────────────────
  // Fuente: historial_vacunacion (MongoDB)
  // Consulta: $bucket por campo edad → grupos etarios

  async function cargarEdades() {
    const cont = document.getElementById('mrChartEdades');
    if (!cont) return;
    try {
      const d = await apiFetch('/api/mongo/historial/edades?meses=' + getMeses());
      if (!d.categorias.length) {
        cont.innerHTML = '<p style="padding:24px;color:#888">Sin datos disponibles.</p>';
        return;
      }
      Highcharts.chart(cont, {
        chart:   { type: 'column', height: 320 },
        title:   { text: 'Distribución por grupo de edad' },
        subtitle:{ text: 'Fuente: MongoDB (historial_vacunacion) · $bucket por campo edad' },
        xAxis:   { categories: d.categorias, title: { text: 'Grupo etario' } },
        yAxis:   { title: { text: 'Pacientes atendidos' }, allowDecimals: false },
        legend:  { enabled: false },
        plotOptions: {
          column: {
            borderRadius: 4,
            dataLabels: { enabled: true },
            colorByPoint: true,
            colors: PALETA,
          },
        },
        series: [{ name: 'Pacientes', data: d.datos }],
      });
    } catch (e) {
      cont.innerHTML = '<p style="padding:24px;color:#a02a2a">Error al cargar datos.</p>';
    }
  }

  // ── Carga automática junto con la página de reportes ────────

  document.addEventListener('DOMContentLoaded', function () {
    cargarMes();
    cargarVacuna();
    cargarEdades();
  });

})();
