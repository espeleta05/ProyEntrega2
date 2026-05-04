(() => {
  const fromInput     = document.getElementById('fromDate');
  const toInput       = document.getElementById('toDate');
  const minGroupInput = document.getElementById('minGroup');
  const runButton     = document.getElementById('runReport');
  const noDataBox     = document.getElementById('rp-no-data');
  if (!runButton) return;

  const now  = new Date();
  toInput.value = now.toISOString().slice(0, 10);
  const past = new Date(now); past.setFullYear(now.getFullYear() - 5);
  fromInput.value = past.toISOString().slice(0, 10);

  const fmt    = new Intl.NumberFormat('es-MX');
  const fmtDec = new Intl.NumberFormat('es-MX', { minimumFractionDigits: 1, maximumFractionDigits: 1 });

  function setVal(id, val, cls) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = val;
    el.classList.remove('loading');
    if (cls) el.classList.add(cls);
  }

  function setStatus(id, text, cls) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.className = 'kpi-status ' + (cls || 'info');
  }

  function coverageStatus(pct) {
    if (pct >= 80) return ['ok',   '✓ Óptimo'];
    if (pct >= 50) return ['warn', '⚠ Moderado'];
    return                ['alert','✗ Crítico'];
  }

  function reactionStatus(pct) {
    if (pct < 2) return ['ok',   '✓ Normal'];
    if (pct < 5) return ['warn', '⚠ Elevado'];
    return              ['alert','✗ Alto'];
  }

  function tempStatus(t) {
    if (!t)     return ['info', '— Sin datos'];
    if (t <= 37.5) return ['ok', '✓ Normal'];
    return             ['warn', '⚠ Revisar'];
  }

  function paintSummary(kpis) {
    document.getElementById('kpiDoses').textContent    = fmt.format(kpis.total_doses_applied || 0);
    document.getElementById('kpiTarget').textContent   = fmt.format(kpis.target_population  || 0);
    document.getElementById('kpiReached').textContent  = fmt.format(kpis.reached_population || 0);
    document.getElementById('kpiCoverage').textContent = fmtDec.format(kpis.coverage_percent || 0) + '%';
    document.getElementById('kpiDelay').textContent    = fmtDec.format(kpis.avg_delay_days  || 0);
    document.getElementById('kpiZones').textContent    = fmt.format(kpis.active_zones       || 0);
  }

  function paintDetailKpis(kpis, vaccines, monthly) {
    const doses   = kpis.total_doses_applied || 0;
    const reached = kpis.reached_population  || 0;
    const target  = kpis.target_population   || 1;
    const cov     = kpis.coverage_percent    || 0;

    const [cs, cl] = coverageStatus(cov);
    setVal('kpi01', fmtDec.format(cov) + '%', cov >= 80 ? 'green' : cov >= 50 ? 'amber' : 'red');
    setStatus('kpi01-status', cl, cs);

    setVal('kpi02', fmt.format(doses));
    setStatus('kpi02-status', doses > 0 ? '✓ Datos disponibles' : '— Sin registros', doses > 0 ? 'ok' : 'warn');

    const avgDose = reached > 0 ? (doses / reached) : 0;
    setVal('kpi03', fmtDec.format(avgDose), avgDose >= 2 ? 'green' : avgDose >= 1 ? 'amber' : 'red');
    setStatus('kpi03-status', avgDose >= 2 ? '✓ Buena adherencia' : avgDose >= 1 ? '⚠ Revisar' : '✗ Abandono temprano', avgDose >= 2 ? 'ok' : avgDose >= 1 ? 'warn' : 'alert');

    const reactionPct = kpis.reaction_rate ?? null;
    if (reactionPct !== null) {
      const [rs, rl] = reactionStatus(reactionPct);
      setVal('kpi04', fmtDec.format(reactionPct) + '%', rs === 'ok' ? 'green' : rs === 'warn' ? 'amber' : 'red');
      setStatus('kpi04-status', rl, rs);
    } else { setVal('kpi04', 'N/D', 'amber'); setStatus('kpi04-status', '— Requiere SP', 'warn'); }

    const completed = kpis.completed_scheme ?? null;
    if (completed !== null) {
      const pct = target > 0 ? (completed / target * 100) : 0;
      setVal('kpi05', fmt.format(completed), pct >= 90 ? 'green' : pct >= 70 ? 'amber' : 'red');
      setStatus('kpi05-status', pct >= 90 ? '✓ Óptimo' : pct >= 70 ? '⚠ Moderado' : '✗ Bajo', pct >= 90 ? 'ok' : pct >= 70 ? 'warn' : 'alert');
    } else { setVal('kpi05', 'N/D', 'amber'); setStatus('kpi05-status', '— Requiere SP', 'warn'); }

    const delayed = kpis.delayed_patients ?? null;
    if (delayed !== null) {
      const pctD = target > 0 ? (delayed / target * 100) : 0;
      setVal('kpi06', fmt.format(delayed), delayed === 0 ? 'green' : pctD < 20 ? 'amber' : 'red');
      setStatus('kpi06-status', delayed === 0 ? '✓ Sin rezago' : pctD < 20 ? '⚠ Bajo rezago' : '✗ Alto rezago', delayed === 0 ? 'ok' : pctD < 20 ? 'warn' : 'alert');
    } else { setVal('kpi06', 'N/D', 'amber'); setStatus('kpi06-status', '— Requiere SP', 'warn'); }

    if (vaccines && vaccines.length > 0) {
      const top = vaccines[0];
      setVal('kpi07', top.vaccine_name, 'green');
      setStatus('kpi07-status', fmt.format(top.doses_applied) + ' dosis aplicadas', 'ok');
    } else { setVal('kpi07', 'Sin datos', 'amber'); setStatus('kpi07-status', '— Sin registros', 'warn'); }

    const apptRate = kpis.appointment_completion_rate ?? null;
    if (apptRate !== null) {
      setVal('kpi08', fmtDec.format(apptRate) + '%', apptRate >= 75 ? 'green' : apptRate >= 50 ? 'amber' : 'red');
      setStatus('kpi08-status', apptRate >= 75 ? '✓ Buena gestión' : apptRate >= 50 ? '⚠ Moderado' : '✗ Bajo', apptRate >= 75 ? 'ok' : apptRate >= 50 ? 'warn' : 'alert');
    } else { setVal('kpi08', 'N/D', 'amber'); setStatus('kpi08-status', '— Requiere datos de citas', 'warn'); }

    const lowStock = kpis.low_stock_count ?? null;
    if (lowStock !== null) {
      setVal('kpi09', fmt.format(lowStock), lowStock === 0 ? 'green' : lowStock < 5 ? 'amber' : 'red');
      setStatus('kpi09-status', lowStock === 0 ? '✓ Stock OK' : lowStock < 5 ? '⚠ Revisar' : '✗ Crítico', lowStock === 0 ? 'ok' : lowStock < 5 ? 'warn' : 'alert');
    } else { setVal('kpi09', 'N/D', 'amber'); setStatus('kpi09-status', '— Requiere inventario', 'warn'); }

    const newPts = kpis.new_patients ?? null;
    if (newPts !== null) {
      setVal('kpi10', fmt.format(newPts), 'green');
      setStatus('kpi10-status', newPts > 0 ? '✓ Crecimiento activo' : '— Sin altas nuevas', newPts > 0 ? 'ok' : 'warn');
    } else { setVal('kpi10', 'N/D', 'amber'); setStatus('kpi10-status', '— Sin columna created_at', 'warn'); }

    const workerCount = kpis.active_workers ?? null;
    if (workerCount && workerCount > 0) {
      const prod = doses / workerCount;
      setVal('kpi11', fmtDec.format(prod), 'blue');
      setStatus('kpi11-status', fmt.format(workerCount) + ' trabajadores activos', 'info');
    } else { setVal('kpi11', 'N/D', 'amber'); setStatus('kpi11-status', '— Sin datos de personal', 'warn'); }

    const thisMonth  = new Date().toISOString().slice(0, 7);
    const monthRow   = (monthly || []).find(r => r.period_label === thisMonth);
    const dosesMonth = monthRow ? monthRow.doses_applied : 0;
    setVal('kpi12', fmt.format(dosesMonth), dosesMonth > 0 ? 'green' : 'amber');
    setStatus('kpi12-status', dosesMonth > 0 ? '✓ Actividad este mes' : '— Sin actividad este mes', dosesMonth > 0 ? 'ok' : 'warn');

    const avgTemp    = kpis.avg_temp_c ?? null;
    const [ts, tl]   = tempStatus(avgTemp);
    setVal('kpi13', avgTemp ? fmtDec.format(avgTemp) + ' °C' : 'N/D', ts === 'ok' ? 'green' : ts === 'warn' ? 'amber' : 'red');
    setStatus('kpi13-status', tl, ts);

    const uniqueVax = vaccines ? vaccines.length : 0;
    setVal('kpi14', fmt.format(uniqueVax), uniqueVax >= 5 ? 'green' : uniqueVax >= 2 ? 'amber' : 'red');
    setStatus('kpi14-status', uniqueVax >= 5 ? '✓ Alta diversidad' : uniqueVax >= 2 ? '⚠ Moderada' : '✗ Baja', uniqueVax >= 5 ? 'ok' : uniqueVax >= 2 ? 'warn' : 'alert');

    if (monthly && monthly.length >= 2) {
      const vals  = monthly.map(r => r.doses_applied || 0);
      const mx    = Math.max(...vals), mn = Math.min(...vals);
      const varPct = mx > 0 ? ((mx - mn) / mx * 100) : 0;
      setVal('kpi15', fmtDec.format(varPct) + '%', varPct < 30 ? 'green' : varPct < 60 ? 'amber' : 'red');
      setStatus('kpi15-status', varPct < 30 ? '✓ Estable' : varPct < 60 ? '⚠ Variable' : '✗ Muy variable', varPct < 30 ? 'ok' : varPct < 60 ? 'warn' : 'alert');
    } else { setVal('kpi15', 'N/D', 'amber'); setStatus('kpi15-status', '— Menos de 2 meses de datos', 'warn'); }
  }

  let monthlyHC, vaccineHC;

  const HC_THEME = {
    chart:   { backgroundColor: 'transparent', style: { fontFamily: "'DM Sans', sans-serif" } },
    title:   { text: null },
    credits: { enabled: false },
    legend:  { itemStyle: { color: '#6b7a9f', fontWeight: '500' } },
    xAxis:   { lineColor: '#2a3050', tickColor: '#2a3050', labels: { style: { color: '#6b7a9f' } } },
    yAxis:   { gridLineColor: '#1f2436', labels: { style: { color: '#6b7a9f' } }, title: { text: null } },
    tooltip: { backgroundColor: '#1f2436', borderColor: '#2a3050', style: { color: '#e8ecf4' } },
  };

  function paintMonthly(rows) {
    if (monthlyHC) monthlyHC.destroy();
    monthlyHC = Highcharts.chart('monthlyChart', {
      ...HC_THEME,
      chart:       { ...HC_THEME.chart, type: 'areaspline' },
      xAxis:       { ...HC_THEME.xAxis, categories: rows.map(r => r.period_label) },
      plotOptions: { areaspline: { fillOpacity: 0.15, marker: { enabled: false } } },
      series: [
        { name: 'Dosis aplicadas',    data: rows.map(r => r.doses_applied),   color: '#4f8ef7', fillColor: 'rgba(79,142,247,.15)' },
        { name: 'Personas atendidas', data: rows.map(r => r.unique_patients), color: '#34d399', fillColor: 'rgba(52,211,153,.1)'  },
      ],
    });

    const EMPTY_ROW = '<tr><td colspan="3" class="tbl-empty-cell">Sin datos para el rango seleccionado.</td></tr>';
    document.getElementById('monthlyBody').innerHTML = rows.length
      ? rows.map(r => `<tr><td>${r.period_label}</td><td>${fmt.format(r.doses_applied || 0)}</td><td>${fmt.format(r.unique_patients || 0)}</td></tr>`).join('')
      : EMPTY_ROW;
  }

  function paintVaccines(rows) {
    if (vaccineHC) vaccineHC.destroy();
    vaccineHC = Highcharts.chart('vaccineChart', {
      ...HC_THEME,
      chart:  { ...HC_THEME.chart, type: 'bar' },
      xAxis:  { ...HC_THEME.xAxis, categories: rows.map(r => r.vaccine_name) },
      series: [{ name: 'Dosis aplicadas', data: rows.map(r => r.doses_applied), color: '#4f8ef7', borderRadius: 4 }],
      legend: { enabled: false },
    });

    const EMPTY_ROW = '<tr><td colspan="4" class="tbl-empty-cell">Sin datos para el rango seleccionado.</td></tr>';
    document.getElementById('vaccinesBody').innerHTML = rows.length
      ? rows.map(r => `<tr><td>${r.vaccine_name}</td><td>${fmt.format(r.doses_applied || 0)}</td><td>${fmt.format(r.unique_patients || 0)}</td><td>${fmtDec.format(r.share_percent || 0)}%</td></tr>`).join('')
      : EMPTY_ROW;
  }

  function paintZones(rows) {
    const EMPTY_ROW = '<tr><td colspan="4" class="tbl-empty-cell">Sin zonas registradas.</td></tr>';
    document.getElementById('zonesBody').innerHTML = rows.length
      ? rows.map(r => `<tr><td>${r.zone_name}</td><td>${fmt.format(r.doses_applied || 0)}</td><td>${fmt.format(r.unique_patients || 0)}</td><td><span class="risk-badge ${r.risk_level || ''}">${r.risk_label || '—'}</span></td></tr>`).join('')
      : EMPTY_ROW;
  }

  async function loadReport() {
    runButton.disabled = true;
    runButton.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Generando…';

    for (let i = 1; i <= 15; i++) {
      const id = String(i).padStart(2, '0');
      const el = document.getElementById('kpi' + id);
      if (el) { el.textContent = '—'; el.className = 'kpi-card-value loading'; }
      const st = document.getElementById('kpi' + id + '-status');
      if (st) { st.textContent = 'Calculando…'; st.className = 'kpi-status info'; }
    }

    const params = new URLSearchParams({
      from: fromInput.value, to: toInput.value,
      min_group: String(minGroupInput.value || 1),
    });

    try {
      const res = await fetch(`/api/reportes-publicos/resumen?${params}`);
      const ct  = res.headers.get('content-type') || '';
      const raw = await res.text();

      if (!ct.includes('application/json'))
        throw new Error('El servidor no devolvió JSON. Verifica login o SPs en PostgreSQL.');

      const data = raw ? JSON.parse(raw) : {};
      if (!res.ok) throw new Error(data.error || 'Error al generar el reporte');

      const kpis     = data.kpis     || {};
      const vaccines = data.vaccines || [];
      const monthly  = data.monthly  || [];
      const zones    = data.zones    || [];

      paintSummary(kpis);
      paintDetailKpis(kpis, vaccines, monthly);
      paintMonthly(monthly);
      paintVaccines(vaccines);
      paintZones(zones);

      noDataBox.hidden = (kpis.total_doses_applied || 0) > 0;

    } catch (err) {
      alert(err.message || 'Error generando reporte');
      noDataBox.hidden = false;
    } finally {
      runButton.disabled = false;
      runButton.innerHTML = '<i class="fa-solid fa-chart-column"></i> Generar reporte';
    }
  }

  runButton.addEventListener('click', loadReport);
  loadReport();
})();
