// Development browser fixture, not an additional Moru application target.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.MORU_PLAYWRIGHT_CORE || 'playwright-core');
const script = await readFile(process.env.MORU_STORAGE_SCRIPT_PATH || '/dev/null', 'utf8');
const profile = await mkdtemp(join(tmpdir(), 'moru-storage-profile-'));
const origins = ['https://moru-miniapp-one.invalid', 'https://moru-miniapp-two.invalid', 'https://moru-miniapp-fresh.invalid'];
let server, context;
const blank = '<!doctype html><meta charset="utf-8"><body>storage fixture</body>';
async function startBackend() {
  server = createServer((request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(blank);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}
async function launch(backend) {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.MORU_CHROMIUM || '/usr/bin/chromium', headless: true,
    args: ['--no-sandbox'],
  });
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (origins.includes(url.origin)) {
      const response = await route.fetch({ url: backend + url.pathname });
      await route.fulfill({ response });
    } else if (url.origin === backend) await route.continue();
    else await route.abort();
  });
}
let serial = 0;
async function send(legacy, page, destination) {
  const nonce = `test-${++serial}`;
  await page.evaluate(script);
  await page.evaluate(({ nonce, sourceOrigin, destination }) => {
    window.__migrationReply = null;
    window.MoruStorageMigration = { postMessage: text => { window.__migrationReply = JSON.parse(text); } };
    window.__moruStorageTransfer.receive(nonce, sourceOrigin, destination);
  }, { nonce, sourceOrigin: new URL(legacy.url()).origin, destination });
  await legacy.evaluate(({ nonce, destination }) => window.__moruStorageTransfer.sendToPopup(nonce, destination, '', ''), { nonce, destination });
  await page.waitForFunction(() => window.__migrationReply !== null);
  assert.equal((await page.evaluate(() => window.__migrationReply)).type, 'complete');
}
async function openMigrated(legacy, destination) {
  const [page] = await Promise.all([
    context.waitForEvent('page'),
    legacy.evaluate(({ nonce, destination }) => window.__moruStorageTransfer.openPopup(nonce, destination), { nonce: 'opening', destination }),
  ]);
  await page.waitForLoadState();
  await send(legacy, page, destination);
  return page;
}
async function readSave(page) {
  return page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('game', 4);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const save = await new Promise((resolve, reject) => {
      const tx = db.transaction('saves');
      const request = tx.objectStore('saves').get(7);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const result = {
      level: save.level, date: save.date.toISOString(), bytes: [...save.bytes],
      blob: await save.blob.text(), cycle: save.self === save,
      map: save.map.get('coins'), set: [...save.set], big: String(save.big),
      version: db.version, index: db.transaction('saves').objectStore('saves').index('byLevel').keyPath,
    };
    db.close();
    return result;
  });
}
async function useKey(page) {
  return page.evaluate(async () => {
    const db = await new Promise(resolve => { const r = indexedDB.open('crypto'); r.onsuccess = () => resolve(r.result); });
    const key = await new Promise(resolve => { const r = db.transaction('keys').objectStore('keys').get('aes'); r.onsuccess = () => resolve(r.result); });
    db.close();
    const iv = new Uint8Array(12), text = new TextEncoder().encode('key retained');
    const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, text);
    return { extractable: key.extractable, text: new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext)) };
  });
}
async function verifyOpaqueCaches(backend) {
  // Desktop cannot emulate Android's file-origin permission. A same-origin
  // popup with a separate cache namespace exercises the actual cross-realm
  // Response copy; native tests and the Android fixture cover its file grant.
  const probe = await context.browser().newContext();
  const asset = 'https://opaque.example.test/asset';
  let assetRequests = 0;
  try {
    await probe.route('**/*', async route => {
      if (route.request().url() === asset) {
        assetRequests++;
        await route.fulfill({ status: 200, contentType: 'text/plain', body: 'opaque saved bytes' });
      } else if (route.request().url().startsWith(backend)) {
        await route.fulfill({ status: 200, contentType: 'text/html', body: blank });
      } else await route.abort();
    });
    const source = await probe.newPage();
    await source.goto(backend + '/opaque-source');
    await source.evaluate(script);
    await source.evaluate(async asset => {
      window.__sourceError = null;
      window.MoruStorageMigration = { postMessage: text => { window.__sourceError = JSON.parse(text); } };
      const response = await fetch(asset, { mode: 'no-cors' });
      if (response.type !== 'opaque') throw Error('Opaque fixture expected');
      await (await caches.open('legacy-opaque')).put(asset, response);
    }, asset);
    const popupReady = probe.waitForEvent('page');
    await source.evaluate(destination => window.__moruStorageTransfer.openPopup('opening', destination), backend);
    const target = await popupReady;
    await target.waitForLoadState();
    await target.evaluate(() => {
      const realCaches = window.caches;
      Object.defineProperty(window, 'caches', { value: { open: name => realCaches.open('target-' + name) } });
    });
    await target.evaluate(script);
    await target.evaluate(destination => {
      window.__reply = null;
      window.MoruStorageMigration = { postMessage: text => { window.__reply = JSON.parse(text); } };
      window.__moruStorageTransfer.receive('opaque-copy', destination, destination);
    }, backend);
    const failure = await source.evaluate(async destination => {
      await window.__moruStorageTransfer.sendToPopup('opaque-copy', destination, '', '');
      return window.__sourceError;
    }, backend);
    assert.equal(failure, null, 'Opaque cache must not block storage migration: ' + JSON.stringify(failure));
    await target.waitForFunction(() => window.__reply !== null);
    assert.equal((await target.evaluate(() => window.__reply)).type, 'complete');
    assert.deepEqual(await target.evaluate(async asset => {
      const response = await (await caches.open('legacy-opaque')).match(asset);
      return { type: response.type, status: response.status };
    }, asset), { type: 'opaque', status: 0 });
    const devtools = await probe.newCDPSession(source);
    const { caches: stores } = await devtools.send('CacheStorage.requestCacheNames', { securityOrigin: backend });
    async function body(name) {
      const cacheId = stores.find(cache => cache.cacheName === name).cacheId;
      return (await devtools.send('CacheStorage.requestCachedResponse', { cacheId, requestURL: asset, requestHeaders: [] })).response.body;
    }
    const original = await body('legacy-opaque'), copied = await body('target-legacy-opaque');
    assert.equal(Buffer.from(original, 'base64').toString(), 'opaque saved bytes');
    assert.equal(copied, original, 'Opaque bytes must remain identical, including in the retained source');
    assert.equal(assetRequests, 1, 'Opaque migration must not refetch the resource');
  } finally { await probe.close(); }
}
try {
  const firstBackend = await startBackend();
  await launch(firstBackend);
  const legacy = await context.newPage();
  await legacy.goto(firstBackend + '/old-game.html');
  await legacy.evaluate(script);
  assert.equal(await legacy.evaluate(() => typeof window.__moruStorageTransfer?.capture), 'function', 'Storage migration must be implemented');
  await legacy.evaluate(async () => {
    localStorage.setItem('progress', 'level-9');
    localStorage.setItem('shared-legacy-setting', 'legacy');
    localStorage.setItem('unicode', '😀'.repeat(80000));
    async function open(name, version, upgrade) {
      return new Promise((resolve, reject) => {
        const r = indexedDB.open(name, version); r.onupgradeneeded = () => upgrade(r.result);
        r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
      });
    }
    async function write(db, store, action) {
      await new Promise((resolve, reject) => {
        const tx = db.transaction(store, 'readwrite'); action(tx.objectStore(store));
        tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
      }); db.close();
    }
    const db = await open('game', 4, db => {
      const s = db.createObjectStore('saves', { keyPath: 'id', autoIncrement: true });
      s.createIndex('byLevel', 'level', { unique: true });
    });
    await write(db, 'saves', store => {
      const save = { id: 7, level: 9, date: new Date('2025-05-02T00:00:00Z'), bytes: new Uint8Array([2, 3, 5]), blob: new Blob(['saved sprite'], { type: 'text/plain' }), map: new Map([['coins', 42]]), set: new Set(['a', 'b']), big: 9007199254740993n };
      save.self = save; store.put(save); store.put({ id: 100, level: 100 }); store.delete(100);
    });
    await write(await open('ordinary', 1, db => db.createObjectStore('items', { autoIncrement: true })), 'items', store => {
      for (const item of ['one', 'two', 'three']) store.add(item);
    });
    await write(await open('exhausted', 1, db => db.createObjectStore('items', { autoIncrement: true })), 'items', store => {
      store.put('deleted high key', 2 ** 53); store.delete(2 ** 53);
    });
    const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    await write(await open('crypto', 1, db => db.createObjectStore('keys')), 'keys', store => store.put(key, 'aes'));
    const cache = await caches.open('legacy-responses');
    await cache.put('/empty', new Response(null, { status: 204 }));
    for (const language of ['ru', 'en']) {
      await cache.put(new Request('/translated?language=' + language, { headers: { 'Accept-Language': language } }), new Response(language, { headers: { Vary: 'Accept-Language' } }));
    }
  });
  const expected = { level: 9, date: '2025-05-02T00:00:00.000Z', bytes: [2, 3, 5], blob: 'saved sprite', cycle: true, map: 42, set: ['a', 'b'], big: '9007199254740993', version: 4, index: 'level' };
  const one = await openMigrated(legacy, origins[0]);
  assert.equal(await one.evaluate(() => localStorage.getItem('progress')), 'level-9');
  assert.equal(await one.evaluate(() => localStorage.getItem('unicode')), '😀'.repeat(80000));
  assert.deepEqual(await readSave(one), expected);
  assert.deepEqual(await useKey(one), { extractable: false, text: 'key retained' });
  assert.deepEqual(await one.evaluate(async () => {
    const cache = await caches.open('legacy-responses');
    const empty = await cache.match('/empty');
    const languages = [];
    for (const language of ['ru', 'en']) {
      const response = await cache.match(new Request('/translated?language=' + language, { headers: { 'Accept-Language': language } }));
      if (!response) throw Error('Missing cache variant ' + language + ': ' + JSON.stringify(await Promise.all((await cache.keys()).map(async r => ({ url: r.url, headers: [...r.headers], response: [...(await cache.match(r)).headers] })))));
      languages.push(await response.text());
    }
    return { status: empty.status, body: empty.body, languages };
  }), { status: 204, body: null, languages: ['ru', 'en'] });
  assert.equal(await one.evaluate(async () => {
    const db = await new Promise(resolve => { const r = indexedDB.open('ordinary'); r.onsuccess = () => resolve(r.result); });
    const key = await new Promise((resolve, reject) => {
      const tx = db.transaction('items', 'readwrite'); const r = tx.objectStore('items').add('four');
      let key; r.onsuccess = () => { key = r.result; }; tx.oncomplete = () => resolve(key); tx.onerror = () => reject(tx.error);
    }); db.close(); return key;
  }), 4);
  assert.equal(await one.evaluate(async () => {
    const db = await new Promise(resolve => { const r = indexedDB.open('exhausted'); r.onsuccess = () => resolve(r.result); });
    const error = await new Promise(resolve => {
      const tx = db.transaction('items', 'readwrite'); const r = tx.objectStore('items').add('must fail');
      r.onerror = () => resolve(r.error.name);
    }); db.close(); return error;
  }), 'ConstraintError');
  await one.evaluate(async () => {
    localStorage.setItem('progress', 'level-10');
    document.cookie = 'game=retained; Max-Age=86400; Secure; Path=/';
    await (await caches.open('sprites')).put('/sprite', new Response('cached sprite'));
  });
  // Retry adds only missing records and never overwrites newer values.
  await send(legacy, one, origins[0]);
  assert.equal(await one.evaluate(() => localStorage.getItem('progress')), 'level-10');
  const nextKey = await one.evaluate(async () => {
    const db = await new Promise(resolve => { const r = indexedDB.open('game'); r.onsuccess = () => resolve(r.result); });
    const key = await new Promise((resolve, reject) => {
      const tx = db.transaction('saves', 'readwrite'); const r = tx.objectStore('saves').add({ level: 10 });
      let key; r.onsuccess = () => { key = r.result; }; tx.oncomplete = () => resolve(key); tx.onerror = () => reject(tx.error);
    }); db.close(); return key;
  });
  assert.equal(nextKey, 101, 'Deleted high keys must not reset the IDB key generator');
  const two = await openMigrated(legacy, origins[1]);
  assert.equal(await two.evaluate(() => localStorage.getItem('shared-legacy-setting')), 'legacy');
  assert.equal(await two.evaluate(() => localStorage.getItem('progress')), 'level-9');
  assert.equal(await two.evaluate(() => document.cookie), '');
  assert.deepEqual(await readSave(two), expected);
  const fresh = await context.newPage();
  await fresh.goto(origins[2] + '/index.html');
  assert.equal(await fresh.evaluate(() => localStorage.length), 0);
  assert.deepEqual(await fresh.evaluate(() => indexedDB.databases()), []);
  assert.deepEqual(await fresh.evaluate(() => caches.keys()), []);
  // Source is retained unchanged, including its secret key.
  assert.equal(await legacy.evaluate(() => localStorage.getItem('progress')), 'level-9');
  assert.deepEqual(await useKey(legacy), { extractable: false, text: 'key retained' });
  // Destroy all WebViews and the local server, then reopen on another port.
  await context.close(); context = null;
  await new Promise(resolve => server.close(resolve)); server = null;
  const secondBackend = await startBackend();
  assert.notEqual(secondBackend, firstBackend);
  await launch(secondBackend);
  const reopened = await context.newPage();
  await reopened.goto(origins[0] + '/index.html');
  assert.equal(await reopened.evaluate(() => localStorage.getItem('progress')), 'level-10');
  assert.deepEqual(await readSave(reopened), expected);
  assert.deepEqual(await useKey(reopened), { extractable: false, text: 'key retained' });
  assert.equal(await reopened.evaluate(() => document.cookie), 'game=retained');
  assert.equal(await reopened.evaluate(async () => (await (await caches.open('sprites')).match('/sprite')).text()), 'cached sprite');
  await reopened.close();
  const nextView = await context.newPage();
  await nextView.goto(origins[0] + '/index.html');
  assert.equal(await nextView.evaluate(() => localStorage.getItem('progress')), 'level-10');
  assert.deepEqual(await readSave(nextView), expected);
  await verifyOpaqueCaches(secondBackend);
  console.log('MORU_BROWSER_STORAGE: raw migration, CryptoKey/cyclic/binary IDB, key generators, Vary/204/opaque caches, isolation, reopen and process restart passed');
} finally {
  await context?.close();
  if (server) await new Promise(resolve => server.close(resolve));
  await rm(profile, { recursive: true, force: true });
}
