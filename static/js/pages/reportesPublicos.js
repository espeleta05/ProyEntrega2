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

function paintDetailKpis(kpis, vaccines, monthly, zones) {
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

    const delayedPts = kpis.delayed_patients ?? null;
    const rezagoPct  = (delayedPts !== null && target > 0) ? +(delayedPts / target * 100).toFixed(1) : null;
    if (rezagoPct !== null) {
      setVal('kpi12', fmtDec.format(rezagoPct) + '%', rezagoPct === 0 ? 'green' : rezagoPct < 20 ? 'amber' : 'red');
      setStatus('kpi12-status', rezagoPct === 0 ? '✓ Sin rezago' : rezagoPct < 20 ? '⚠ Rezago moderado' : '✗ Rezago crítico', rezagoPct === 0 ? 'ok' : rezagoPct < 20 ? 'warn' : 'alert');
    } else { setVal('kpi12', 'N/D', 'amber'); setStatus('kpi12-status', '— Sin datos de esquema', 'warn'); }

    const expiringLots = kpis.expiring_lots ?? null;
    if (expiringLots !== null) {
      setVal('kpi13', fmt.format(expiringLots), expiringLots === 0 ? 'green' : expiringLots <= 3 ? 'amber' : 'red');
      setStatus('kpi13-status', expiringLots === 0 ? '✓ Sin lotes en riesgo' : expiringLots <= 3 ? '⚠ Revisar lotes' : '✗ Acción urgente', expiringLots === 0 ? 'ok' : expiringLots <= 3 ? 'warn' : 'alert');
    } else { setVal('kpi13', 'N/D', 'amber'); setStatus('kpi13-status', '— Sin datos de lotes', 'warn'); }

    const pendingAlerts = kpis.pending_alerts ?? null;
    if (pendingAlerts !== null) {
      setVal('kpi14', fmt.format(pendingAlerts), pendingAlerts === 0 ? 'green' : pendingAlerts <= 5 ? 'amber' : 'red');
      setStatus('kpi14-status', pendingAlerts === 0 ? '✓ Sin alertas pendientes' : pendingAlerts <= 5 ? '⚠ Alertas en revisión' : '✗ Múltiples alertas activas', pendingAlerts === 0 ? 'ok' : pendingAlerts <= 5 ? 'warn' : 'alert');
    } else { setVal('kpi14', 'N/D', 'amber'); setStatus('kpi14-status', '— Sin datos de alertas', 'warn'); }

    if (monthly && monthly.length > 0) {
      const monthCount  = monthly.length;
      const avgMonthly  = monthCount > 0 ? (kpis.total_doses_applied || 0) / monthCount : 0;
      setVal('kpi15', fmt.format(Math.round(avgMonthly)), 'blue');
      setStatus('kpi15-status', `${monthCount} mes${monthCount !== 1 ? 'es' : ''} en el período`, 'info');
    } else { setVal('kpi15', 'N/D', 'amber'); setStatus('kpi15-status', '— Sin datos mensuales', 'warn'); }
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
    const EMPTY_ROW = '<tr><td colspan="3" class="tbl-empty-cell">Sin datos para el rango seleccionado.</td></tr>';
    document.getElementById('monthlyBody').innerHTML = rows.length
      ? rows.map(r => `<tr><td>${r.period_label}</td><td>${fmt.format(r.doses_applied || 0)}</td><td>${fmt.format(r.unique_patients || 0)}</td></tr>`).join('')
      : EMPTY_ROW;
  }

  function paintVaccines(rows) {
    const EMPTY_ROW = '<tr><td colspan="4" class="tbl-empty-cell">Sin datos para el rango seleccionado.</td></tr>';
    document.getElementById('vaccinesBody').innerHTML = rows.length
      ? rows.map(r => `<tr><td>${r.vaccine_name}</td><td>${fmt.format(r.doses_applied || 0)}</td><td>${fmt.format(r.unique_patients || 0)}</td><td><span class="rp-pct">${fmtDec.format(r.share_percent || 0)}%</span></td></tr>`).join('')
      : EMPTY_ROW;
  }

  function paintZones(rows) {
    const el = document.getElementById('zonesBody');
    if (!el) return;
    const EMPTY_ROW = '<tr><td colspan="4" class="tbl-empty-cell">Sin zonas registradas.</td></tr>';
    el.innerHTML = rows.length
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

paintDetailKpis(kpis, vaccines, monthly, zones);
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
