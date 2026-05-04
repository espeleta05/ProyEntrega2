(() => {
  const dataEl = document.getElementById('dash-chart-data');
  if (!dataEl || typeof Chart === 'undefined') return;

  const coverageData = JSON.parse(dataEl.dataset.coverage || '[]');
  const dosesData    = JSON.parse(dataEl.dataset.monthly  || '[]');
  const delayData    = JSON.parse(dataEl.dataset.delays   || '[]');

  new Chart(document.getElementById('coverageChart'), {
    type: 'bar',
    data: {
      labels: coverageData.map(d => d.label),
      datasets: [{
        label: '% cobertura',
        data: coverageData.map(d => d.pct),
        backgroundColor: ['#4CAF7D','#5B8DD9','#29B6C5','#F4A84A','#AB6BD6'],
        borderRadius: 6,
        borderSkipped: false,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        y: { beginAtZero: true, max: 100, ticks: { callback: v => v + '%' }, grid: { color: '#f0f0f0' } },
        x: { grid: { display: false } },
      },
    },
  });

  new Chart(document.getElementById('dosesChart'), {
    type: 'line',
    data: {
      labels: dosesData.map(d => d.label),
      datasets: [{
        label: 'Dosis',
        data: dosesData.map(d => d.count),
        borderColor: '#4f46e5',
        backgroundColor: 'rgba(79,70,229,.1)',
        borderWidth: 2.5,
        pointRadius: 4,
        pointBackgroundColor: '#4f46e5',
        tension: 0.4,
        fill: true,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        y: { beginAtZero: true, grid: { color: '#f0f0f0' } },
        x: { grid: { display: false } },
      },
    },
  });

  new Chart(document.getElementById('delayChart'), {
    type: 'bar',
    data: {
      labels: delayData.map(d => d.vaccine),
      datasets: [{
        label: '% retraso',
        data: delayData.map(d => d.pct),
        backgroundColor: '#E05252',
        borderRadius: 6,
        borderSkipped: false,
      }],
    },
    options: {
      indexAxis: 'y',
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { beginAtZero: true, max: 100, ticks: { callback: v => v + '%' }, grid: { color: '#f0f0f0' } },
        y: { grid: { display: false } },
      },
    },
  });
})();
