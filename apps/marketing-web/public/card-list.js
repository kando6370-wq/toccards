document.querySelectorAll('[data-card-list]').forEach((list) => {
  const controls = list.querySelector('form');
  const query = controls.querySelector('input');
  const coverage = controls.querySelector('select');
  const rows = [...list.querySelectorAll('[data-card-row]')];
  const count = list.querySelector('[data-card-count]');
  const empty = list.querySelector('[data-card-empty]');
  const normalize = (value) => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[’']/g, '').trim();

  const update = () => {
    const words = normalize(query.value).split(/\s+/).filter(Boolean);
    let visible = 0;
    rows.forEach((row) => {
      const matchesText = words.every((word) => normalize(row.dataset.search).includes(word));
      const matchesPrice = coverage.value === 'all' || (coverage.value === 'priced') === (row.dataset.priced === 'true');
      row.hidden = !(matchesText && matchesPrice);
      if (!row.hidden) visible += 1;
    });
    count.textContent = `${visible} of ${rows.length} cards shown.`;
    empty.hidden = visible !== 0;
  };

  controls.hidden = false;
  controls.addEventListener('submit', (event) => event.preventDefault());
  query.addEventListener('input', update);
  coverage.addEventListener('change', update);
  controls.addEventListener('reset', (event) => {
    event.preventDefault();
    query.value = '';
    coverage.value = 'all';
    update();
  });
});
