(() => {
  const input      = document.getElementById('globalSearchInput');
  const resultsBox = document.getElementById('globalSearchResults');
  if (!input || !resultsBox) return;

  let debounceTimer;
  let activeIndex = -1;

  const typeLabel = { paciente: 'Paciente', vacuna: 'Vacuna', personal: 'Personal' };

  function closeResults() {
    resultsBox.hidden = true;
    resultsBox.innerHTML = '';
    activeIndex = -1;
  }

  function getItems() { return Array.from(resultsBox.querySelectorAll('.search-item')); }

  function setActive(index) {
    getItems().forEach((item, i) => {
      const active = i === index;
      item.classList.toggle('active', active);
      if (active) item.scrollIntoView({ block: 'nearest' });
    });
  }

  function moveActive(delta) {
    const items = getItems();
    if (!items.length) return;
    activeIndex = (activeIndex + delta + items.length) % items.length;
    setActive(activeIndex);
  }

  function goToActiveOrFirst() {
    const items = getItems();
    if (!items.length) return;
    const url = items[activeIndex >= 0 ? activeIndex : 0].dataset.url;
    if (url) window.location.href = url;
  }

  function renderResults(items) {
    if (!items.length) {
      resultsBox.innerHTML = '<div class="search-empty">Sin coincidencias</div>';
      resultsBox.hidden = false;
      return;
    }
    resultsBox.innerHTML = items.map(item =>
      `<button type="button" class="search-item" data-url="${item.url}">
         <span class="search-type ${item.type}">${typeLabel[item.type] || item.type}</span>
         <span class="search-main">${item.title || ''}</span>
         <span class="search-sub">${item.subtitle || ''}</span>
       </button>`
    ).join('');
    activeIndex = -1;
    resultsBox.hidden = false;
  }

  async function fetchResults(query) {
    try {
      const res = await fetch(`/api/global-search?q=${encodeURIComponent(query)}`);
      if (!res.ok) { closeResults(); return; }
      renderResults((await res.json()).results || []);
    } catch { closeResults(); }
  }

  input.addEventListener('input', () => {
    const q = input.value.trim();
    clearTimeout(debounceTimer);
    if (q.length < 1) { closeResults(); return; }
    debounceTimer = setTimeout(() => fetchResults(q), 180);
  });

  resultsBox.addEventListener('click', e => {
    const btn = e.target.closest('.search-item');
    if (btn?.dataset.url) window.location.href = btn.dataset.url;
  });

  document.addEventListener('click', e => {
    if (!resultsBox.contains(e.target) && e.target !== input) closeResults();
  });

  input.addEventListener('keydown', e => {
    if (e.key === 'Escape') { closeResults(); return; }
    if (resultsBox.hidden) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); moveActive(1);  return; }
    if (e.key === 'ArrowUp')   { e.preventDefault(); moveActive(-1); return; }
    if (e.key === 'Enter')     { e.preventDefault(); goToActiveOrFirst(); }
  });
})();
