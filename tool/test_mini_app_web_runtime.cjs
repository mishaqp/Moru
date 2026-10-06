// Run with node --test tool/test_mini_app_web_runtime.cjs.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const store = fs.readFileSync('lib/core/services/mini_apps/mini_app_store.dart', 'utf8');
const legacy = store.match(/static const String (?:moruBridgeScript|_legacyBridgeScript) = r'''([\s\S]*?)''';/)[1];
const runtimePath = 'lib/core/services/mini_apps/mini_app_web_runtime.dart';
const runtime = fs.existsSync(runtimePath)
  ? fs.readFileSync(runtimePath, 'utf8').match(/const String miniAppWebRuntime = r'''([\s\S]*?)''';/)[1] : '';
function page() {
  const appended = [], messages = [], variables = {};
  const ctx = {URL, Promise, Map, Set, console, setTimeout, clearTimeout,
    __moruAssetBase: 'http://127.0.0.1:8123/token/lib/',
    __moruLibraryFiles: {phaser: 'phaser-3.90.0.min.js', ui: 'moru-ui.css', sqljs: 'sql-wasm-1.14.2.js', 'sqljs-wasm': 'sql-wasm-1.14.2.wasm'},
    document: {currentScript: {src: 'http://127.0.0.1:8123/token/app/moru.js'},
      documentElement: {style: {setProperty: (k, v) => variables[k] = v}, dataset: {}},
      createElement: (tagName) => ({tagName}),
      head: {appendChild: (node) => {appended.push(node); queueMicrotask(() => node.onload());}}},
    location: {href: 'http://127.0.0.1:8123/token/app/nested/index.html'},
    addEventListener() {}, dispatchEvent() {},
    CustomEvent: function(type, options) {this.type = type; this.detail = options.detail;},
    matchMedia: () => ({matches: false, addEventListener(){}}),
    MoruBridge: {postMessage: value => messages.push(JSON.parse(value))},
    Phaser: {VERSION: '3.90.0'},
    initSqlJs: async ({locateFile}) => ({wasm: locateFile('sql-wasm.wasm')})};
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(legacy + '\n' + runtime, ctx);
  return {ctx, appended, messages, variables};
}
test('shared library URLs come from host, not nested entry or network CDN', () => {
  const {ctx} = page();
  assert.ok(ctx.moru.libs, 'moru.libs must be available on an old app bridge');
  assert.equal(ctx.moru.libs.url('phaser'), 'http://127.0.0.1:8123/token/lib/phaser-3.90.0.min.js');
  assert.throws(() => ctx.moru.libs.url('../data.json'), /Unknown library/);
});
test('concurrent script loads share one element; CSS is a stylesheet', async () => {
  const {ctx, appended} = page();
  assert.ok(ctx.moru.libs);
  const [a,b] = await Promise.all([ctx.moru.libs.load('phaser'), ctx.moru.libs.load('phaser')]);
  assert.equal(a, ctx.Phaser); assert.equal(a,b); assert.equal(appended.length,1);
  await ctx.moru.libs.load('ui');
  assert.equal(appended[1].tagName, 'link'); assert.equal(appended[1].rel, 'stylesheet');
});
test('SQLite initializes with local WASM and is shared within a page', async () => {
  const {ctx} = page(); assert.ok(ctx.moru.libs);
  const sql = await ctx.moru.libs.load('sqljs');
  assert.equal(sql.wasm,'http://127.0.0.1:8123/token/lib/sql-wasm-1.14.2.wasm');
  assert.equal(await ctx.moru.libs.load('sqljs'),sql);
});
test('startup promises are observable, including rejected startup', async () => {
  const {ctx,messages} = page(); assert.equal(typeof ctx.moru.ready, 'function');
  let finish;
  ctx.moru.ready(new Promise(resolve => finish = resolve));
  assert.equal(ctx.__moruPending,1); finish();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(ctx.__moruPending,0);
  ctx.moru.ready(Promise.reject(new Error('bad startup')));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(ctx.__moruPending,0);
  assert.ok(messages.some(m => m.method === '__report' && JSON.stringify(m).includes('bad startup')));
});
test('native theme changes CSS without replacing moru storage', () => {
  const {ctx,variables} = page(); const storage = ctx.moru.storage;
  assert.equal(typeof ctx.__moruSetTheme, 'function');
  ctx.__moruSetTheme({dark: true, colors: {background:'#101010', primary:'#123456'}, safeArea:{bottom:24}});
  assert.equal(variables['--moru-background'], '#101010');
  assert.equal(variables['--moru-safe-bottom'], '24px');
  assert.equal(ctx.document.documentElement.dataset.moruTheme, 'dark');
  assert.equal(ctx.moru.storage,storage);
});
