(async function () {
  const status = document.querySelector('#status');
  const form = document.querySelector('#edit');
  const day = document.querySelector('#day');
  const input = document.querySelector('#value');
  const button = form.querySelector('button');
  let chart;
  let values = [2, 4, 3, 5, 4, 6, 5];
  const fail = error => { status.textContent = `Ошибка: ${error.message}`; };
  function colors() {
    const css = getComputedStyle(document.documentElement);
    return ['accent', 'text', 'border'].map(name => css.getPropertyValue(`--moru-${name}`).trim());
  }
  function repaint() {
    const [accent, text, border] = colors();
    chart.data.datasets[0].backgroundColor = accent;
    chart.options.scales.x.ticks.color = chart.options.scales.y.ticks.color = text;
    chart.options.scales.x.grid.color = chart.options.scales.y.grid.color = border;
    chart.update('none');
  }
  async function redraw() {
    const saved = await moru.storage.get('values');
    if (Array.isArray(saved) && saved.length === 7 && saved.every(n => Number.isFinite(n) && n >= 0)) values = saved;
    else values = [2, 4, 3, 5, 4, 6, 5];
    chart.data.datasets[0].data = [...values];
    input.value = values[Number(day.value)];
    repaint();
  }
  try {
    await Promise.all([moru.assets.load('ui'), moru.assets.load('chartjs')]);
    chart = new Chart(document.querySelector('#chart'), {
      type: 'bar',
      data: { labels: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'], datasets: [{ data: values, borderRadius: 6 }] },
      options: { responsive: true, maintainAspectRatio: false, animation: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
    });
    await redraw();
    button.disabled = false;
    status.textContent = 'Готово';
    day.addEventListener('change', () => { input.value = values[Number(day.value)]; });
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (!form.reportValidity() || button.disabled) return;
      button.disabled = true;
      try {
        const next = [...values];
        next[Number(day.value)] = Number(input.value);
        await moru.storage.set('values', next);
        await redraw();
        status.textContent = 'Сохранено';
      } catch (error) { fail(error); }
      finally { button.disabled = false; }
    });
    window.addEventListener('moru:storage', event => { if (event.detail.key === 'values') void redraw().catch(fail); });
    window.addEventListener('moru:theme', repaint);
    window.addEventListener('pagehide', () => chart.destroy(), { once: true });
  } catch (error) { fail(error); }
})();
