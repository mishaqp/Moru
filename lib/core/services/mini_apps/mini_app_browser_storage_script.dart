/// Runs only in trusted blank documents. postMessage uses the same structured
/// clone mechanism as IndexedDB, preserving CryptoKeys, Blobs and cyclic data
/// without exporting secrets or converting stored values to JSON.
const miniAppBrowserStorageScript = r'''
(function () {
  'use strict';
  const request = r => new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  });
  const committed = tx => new Promise((resolve, reject) => {
    tx.oncomplete = resolve; tx.onabort = () => reject(tx.error || Error('Storage transaction aborted'));
    tx.onerror = () => reject(tx.error || Error('Storage transaction failed'));
  });
  function send(nonce, type, value) { MoruStorageMigration.postMessage(JSON.stringify({ nonce, type, value })); }
  async function nextKey(db, name) {
    // Probe the generator in an aborted transaction; never modify source data.
    return new Promise((resolve, reject) => {
      const tx = db.transaction(name, 'readwrite'); let key;
      const r = tx.objectStore(name).add({});
      r.onsuccess = () => { key = r.result; tx.abort(); };
      r.onerror = () => {
        if (r.error && r.error.name === 'ConstraintError') key = 'exhausted';
        else reject(r.error);
      };
      tx.onabort = () => key === undefined ? reject(tx.error || Error('Cannot read IDB generator')) : resolve(key);
    });
  }
  async function databases() {
    let names;
    try { names = await indexedDB.databases(); }
    catch (e) { if (e.name === 'SecurityError') return []; throw e; }
    const result = [];
    for (const info of names) {
      const db = await request(indexedDB.open(info.name));
      try {
        const stores = [];
        for (const name of db.objectStoreNames) {
          const tx = db.transaction(name), store = tx.objectStore(name);
          const done = committed(tx), records = [];
          const indexes = [...store.indexNames].map(name => {
            const index = store.index(name);
            return { name, keyPath: index.keyPath, unique: index.unique, multiEntry: index.multiEntry };
          });
          const cursor = store.openCursor();
          cursor.onsuccess = () => { const c = cursor.result; if (c) { records.push({ key: c.primaryKey, value: c.value }); c.continue(); } };
          await done;
          stores.push({ name, keyPath: store.keyPath, autoIncrement: store.autoIncrement, indexes, records, nextKey: store.autoIncrement ? await nextKey(db, name) : null });
        }
        result.push({ name: db.name, version: db.version, stores });
      } finally { db.close(); }
    }
    return result;
  }
  async function capture(extraCookies = '', fileRoot = '', opaque = []) {
    const local = [];
    for (let i = 0; i < localStorage.length; i++) { const key = localStorage.key(i); local.push([key, localStorage.getItem(key)]); }
    const cacheData = [];
    let cacheNames;
    try { cacheNames = await caches.keys(); }
    catch (e) { if (e.name === 'SecurityError') cacheNames = []; else throw e; }
    for (const name of cacheNames) {
      const cache = await caches.open(name), entries = [];
      for (const r of await cache.keys()) {
        const response = await cache.match(r);
        if (response.status === 0) { opaque.push({ name, request: r, response }); continue; }
        entries.push({ url: r.url, requestHeaders: [...r.headers], mode: r.mode, credentials: r.credentials,
          headers: [...response.headers], status: response.status, statusText: response.statusText,
          body: response.body === null ? null : await response.blob() });
      }
      cacheData.push({ name, entries });
    }
    return { version: 1, source: location.href, fileRoot, local, cookies: document.cookie + ';' + extraCookies, databases: await databases(), caches: cacheData };
  }
  async function restore(data, destination) {
    if (data.version !== 1) throw Error('Unknown browser storage snapshot version');
    for (const [key, value] of data.local) if (localStorage.getItem(key) === null) localStorage.setItem(key, value);
    const existingCookies = new Set(document.cookie.split(';').map(pair => pair.trim().split('=')[0]));
    for (const pair of data.cookies.split(';')) {
      const cookie = pair.trim(), equals = cookie.indexOf('=');
      if (equals > 0 && !existingCookies.has(cookie.slice(0, equals))) document.cookie = cookie + '; Path=/; Max-Age=315360000; Secure; SameSite=Lax';
    }
    for (const entry of data.databases) {
      const open = indexedDB.open(entry.name, entry.version);
      open.onupgradeneeded = () => {
        const db = open.result;
        for (const item of entry.stores) {
          const store = db.objectStoreNames.contains(item.name) ? open.transaction.objectStore(item.name) : db.createObjectStore(item.name, { keyPath: item.keyPath, autoIncrement: item.autoIncrement });
          for (const index of item.indexes) if (!store.indexNames.contains(index.name)) store.createIndex(index.name, index.keyPath, { unique: index.unique, multiEntry: index.multiEntry });
        }
      };
      const db = await request(open);
      try {
        for (const item of entry.stores) {
          const tx = db.transaction(item.name, 'readwrite'), done = committed(tx), store = tx.objectStore(item.name);
          let remaining = item.records.length;
          function advanceGenerator() {
            if (!item.autoIncrement || (item.nextKey !== 'exhausted' && item.nextKey <= 1)) return;
            const key = item.nextKey === 'exhausted' ? 2 ** 53 : item.nextKey - 1;
            const exists = store.getKey(key);
            exists.onsuccess = () => {
              if (exists.result !== undefined) return;
              const placeholder = {};
              if (typeof store.keyPath === 'string') {
                const parts = store.keyPath.split('.'); let target = placeholder;
                for (const part of parts.slice(0, -1)) target = target[part] = {};
                target[parts[parts.length - 1]] = key;
              }
              const add = store.keyPath === null ? store.add(placeholder, key) : store.add(placeholder);
              add.onsuccess = () => store.delete(key);
            };
          }
          function copied() { if (--remaining === 0) advanceGenerator(); }
          for (const record of item.records) {
            const exists = store.getKey(record.key);
            exists.onsuccess = () => {
              if (exists.result !== undefined) { copied(); return; }
              const add = store.keyPath === null ? store.add(record.value, record.key) : store.add(record.value);
              add.onsuccess = copied;
            };
          }
          if (remaining === 0) advanceGenerator();
          await done;
        }
      } finally { db.close(); }
    }
    function targetUrl(url) {
      if (data.fileRoot && url.startsWith(data.fileRoot)) return new URL(url.slice(data.fileRoot.length), destination + '/').href;
      const source = new URL(data.source), requestUrl = new URL(url);
      return source.origin === requestUrl.origin && source.protocol !== 'file:' ? new URL(requestUrl.pathname + requestUrl.search, destination).href : url;
    }
    for (const item of data.caches) {
      const cache = await caches.open(item.name);
      for (const entry of item.entries) {
        const r = new Request(targetUrl(entry.url), { headers: entry.requestHeaders,
          mode: entry.mode === 'navigate' ? 'same-origin' : entry.mode, credentials: entry.credentials });
        if (!await cache.match(r)) await cache.put(r, new Response(entry.body, { status: entry.status, statusText: entry.statusText, headers: entry.headers }));
      }
    }
  }
  let popup;
  window.__moruStorageTransfer = {
    capture, restore,
    openPopup: function (nonce, destination) {
      try { popup = window.open(destination + '/.moru-storage-transfer'); if (!popup) throw Error('Storage transfer window was blocked'); }
      catch (e) { send(nonce, 'error', String(e && e.message || e)); }
    },
    receive: function (nonce, sourceOrigin, destination) {
      const receive = async event => {
        if (event.source !== window.opener || event.origin !== sourceOrigin || !event.data || event.data.nonce !== nonce) return;
        window.removeEventListener('message', receive);
        try { await restore(event.data.snapshot, destination); send(nonce, 'complete', null); }
        catch (e) { send(nonce, 'error', String(e && e.message || e)); }
      };
      window.addEventListener('message', receive);
    },
    sendToPopup: async function (nonce, destination, cookies, fileRoot) {
      try {
        const opaque = [], snapshot = await capture(cookies, fileRoot, opaque);
        if (opaque.length) {
          // Only the native trusted file reader has temporary universal access.
          // Response itself is not structured-cloneable; Cache.put preserves its
          // hidden opaque body without reading it or requesting the network.
          if (popup.location.origin !== destination || popup.location.pathname !== '/.moru-storage-transfer') throw Error('Storage transfer destination changed');
          for (const entry of opaque) {
            const cache = await popup.caches.open(entry.name);
            if (!await cache.match(entry.request)) await cache.put(entry.request, entry.response);
          }
        }
        popup.postMessage({ nonce, snapshot }, destination);
      }
      catch (e) { send(nonce, 'error', String(e && e.message || e)); }
    }
  };
})();
''';
