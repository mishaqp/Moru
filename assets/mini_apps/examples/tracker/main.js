(async function () {
  const status = document.querySelector('#status');
  const form = document.querySelector('#add');
  const undo = document.querySelector('#undo');
  const submit = form.querySelector('[type="submit"]');
  let busy = false;
  const today = () => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  };
  const fail = error => { status.textContent = `Не удалось сохранить: ${error.message}`; };
  async function readLog() {
    const value = await moru.storage.get('log');
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  }
  async function redraw() {
    const log = await readLog();
    const entries = Array.isArray(log[today()]) ? log[today()].filter(n => Number.isFinite(n) && n > 0) : [];
    document.querySelector('#date').textContent = new Date().toLocaleDateString('ru', { day: 'numeric', month: 'long' });
    document.querySelector('#total').textContent = String(entries.reduce((sum, n) => sum + n, 0));
    document.querySelector('#entries').replaceChildren(...entries.map((ml, index) => {
      const li = document.createElement('li');
      li.className = 'moru-list-item';
      li.textContent = `${index + 1}. ${ml} мл`;
      return li;
    }));
    undo.disabled = busy || !entries.length;
  }
  async function change(remove) {
    if (busy) return;
    busy = true;
    submit.disabled = undo.disabled = true;
    try {
      const log = await readLog();
      const day = today();
      const entries = Array.isArray(log[day]) ? [...log[day]] : [];
      if (remove) entries.pop();
      else entries.push(Number(document.querySelector('#amount').value));
      log[day] = entries;
      await moru.storage.set('log', log);
      status.textContent = 'Сохранено';
    } catch (error) { fail(error); }
    finally {
      busy = false;
      submit.disabled = false;
      await redraw().catch(fail);
    }
  }
  try {
    await moru.assets.load('ui');
    await redraw();
    submit.disabled = false;
    status.textContent = 'Готово';
    form.addEventListener('submit', event => { event.preventDefault(); if (form.reportValidity()) void change(false); });
    undo.addEventListener('click', () => { void change(true); });
    window.addEventListener('moru:storage', event => {
      if (event.detail.key === 'log') void redraw().catch(fail);
    });
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) void redraw().catch(fail);
    });
  } catch (error) { fail(error); }
})();
