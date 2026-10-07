(async function () {
  const status = document.querySelector('#status');
  const form = document.querySelector('#add');
  const button = form.querySelector('button');
  let SQL, db, busy = false;
  const fail = error => { status.textContent = `Ошибка базы: ${error.message}`; };
  async function restore() {
    const bytes = await moru.storage.get('database');
    const next = bytes === null ? new SQL.Database() : new SQL.Database(new Uint8Array(bytes));
    try { next.run('CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, text TEXT NOT NULL)'); }
    catch (error) { next.close(); throw error; }
    if (db) db.close();
    db = next;
    redraw();
  }
  function redraw() {
    const statement = db.prepare('SELECT id, text FROM notes ORDER BY id DESC');
    const rows = [];
    try {
      while (statement.step()) {
        const { id, text } = statement.getAsObject();
        const li = document.createElement('li');
        li.className = 'moru-list-item';
        const label = document.createElement('span');
        label.className = 'note-text';
        label.textContent = text;
        const remove = document.createElement('button');
        remove.className = 'moru-button moru-button--secondary';
        remove.textContent = 'Удалить';
        remove.setAttribute('aria-label', `Удалить заметку: ${text}`);
        remove.disabled = busy;
        remove.addEventListener('click', () => { void change('DELETE FROM notes WHERE id = ?', [id]); });
        li.append(label, remove);
        rows.push(li);
      }
    } finally { statement.free(); }
    document.querySelector('#notes').replaceChildren(...rows);
  }
  async function change(sql, parameters) {
    if (busy) return;
    busy = true;
    button.disabled = true;
    const previous = db.export();
    try {
      db.run(sql, parameters);
      await moru.storage.set('database', Array.from(db.export()));
      form.reset();
      status.textContent = 'Сохранено';
    } catch (error) {
      db.close();
      db = new SQL.Database(previous);
      fail(error);
    } finally {
      busy = false;
      button.disabled = false;
      redraw();
    }
  }
  try {
    await Promise.all([moru.assets.load('ui'), moru.assets.load('sqljs')]);
    SQL = await initSqlJs({ locateFile: () => moru.assets.url('sqljs-wasm') });
    await restore();
    button.disabled = false;
    status.textContent = 'Готово';
    form.addEventListener('submit', event => {
      event.preventDefault();
      const text = document.querySelector('#text').value.trim();
      if (text && form.reportValidity()) void change('INSERT INTO notes(text) VALUES (?)', [text]);
    });
    window.addEventListener('moru:storage', event => {
      if (event.detail.key === 'database' && !busy) void restore().catch(fail);
    });
    window.addEventListener('pagehide', () => db.close(), { once: true });
  } catch (error) { fail(error); }
})();
