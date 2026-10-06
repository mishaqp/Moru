// Invoked by verify_mini_app_examples_test.dart against the production server.
// playwright-core is an external development dependency, never an APK asset.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.MORU_PLAYWRIGHT_CORE || 'playwright-core');
const urls = JSON.parse(process.env.MORU_EXAMPLE_URLS || '{}');
assert.deepEqual(Object.keys(urls), ['tracker', 'chart', 'phaser', 'galacean', 'sqlite']);
const browser = await chromium.launch({
  executablePath: process.env.MORU_CHROMIUM || '/usr/bin/chromium',
  headless: true,
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
try {
  for (const [name, url] of Object.entries(urls)) {
    const context = await browser.newContext({ viewport: { width: 393, height: 852 }, isMobile: true, hasTouch: true });
    const errors = [], external = [], requests = [];
    await context.route('**/*', async route => {
      const request = route.request();
      const parsed = new URL(request.url());
      if (!['127.0.0.1', 'localhost'].includes(parsed.hostname)) {
        external.push(request.url());
        await route.abort();
      } else {
        requests.push(parsed.pathname);
        await route.continue();
      }
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForFunction(() => !document.querySelector('#status').textContent.includes('Загрузка'), null, { timeout: 15000 });
    assert.ok(!/Ошибка|Не удалось/.test(await page.locator('#status').textContent()), `${name} startup failed`);
    assert.equal(await page.evaluate(() => moru.theme.dark), false);
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--moru-accent').trim()), '#1b7b6b');
    await page.evaluate(async () => {
      assertLocal(moru.assets.url('ui'));
      await Promise.all([moru.assets.load('ui'), moru.assets.load('ui')]);
      function assertLocal(url) { if (new URL(url).origin !== location.origin) throw Error('Asset escaped origin'); }
    });
    assert.equal(await page.locator('link[href*="moru-ui-"]').count(), 1, `${name}: CSS loader must deduplicate`);

    if (name === 'tracker') {
      // Hidden checker/job WebViews have no visible Moru theme callback.
      // The bridge must still provide the documented snapshot shape.
      const themePage = await context.newPage();
      await themePage.route('**/moru.js', async route => {
        const response = await route.fetch();
        const script = await response.text();
        const theme = script.indexOf('window.__moruTheme =');
        const bootstrap = script.lastIndexOf('(function () {', theme);
        assert.ok(bootstrap > 0, 'Theme fixture bootstrap must be present');
        await route.fulfill({ response, body: script.slice(0, bootstrap) });
      });
      await themePage.goto(url, { waitUntil: 'networkidle' });
      assert.equal(await themePage.evaluate(() => typeof moru.theme.dark), 'boolean');
      assert.match(await themePage.evaluate(() => moru.theme.colors.accent), /^#[0-9a-f]{6}$/);
      assert.equal(await themePage.evaluate(() => moru.theme.insets.top), 0);
      await themePage.close();
    }

    if (name === 'tracker') {
      await page.locator('#amount').fill('375');
      await page.locator('#add button[type="submit"]').tap();
      await page.waitForFunction(() => document.querySelector('#total').textContent === '375');
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForFunction(() => document.querySelector('#total').textContent === '375');
      await page.evaluate(async () => {
        const log = await moru.storage.get('log');
        const day = Object.keys(log)[0];
        log[day].push(125);
        await moru.storage.set('log', log);
        window.__moruChanged('log');
      });
      await page.waitForFunction(() => document.querySelector('#total').textContent === '500');
      await page.locator('#undo').tap();
      await page.waitForFunction(() => document.querySelector('#total').textContent === '375');
      // Load UI on a page that has not loaded the engine: its declared
      // dependency must finish first, even with concurrent repeated calls.
      await page.evaluate(async () => {
        await Promise.all([moru.assets.load('galacean-ui'), moru.assets.load('galacean-ui')]);
        if (!Galacean.UI.UICanvas || !Galacean.UI.Image) throw Error('Galacean UI was not ready');
      });
      const scripts = await page.locator('script[src*="__moru_assets/"]').evaluateAll(tags => tags.map(tag => tag.src));
      assert.equal(scripts.filter(src => src.includes('galacean-engine-1.6.13')).length, 1);
      assert.equal(scripts.filter(src => src.includes('galacean-engine-ui-1.6.13')).length, 1);
      assert.ok(scripts.findIndex(src => src.includes('galacean-engine-1.6.13')) < scripts.findIndex(src => src.includes('galacean-engine-ui-1.6.13')));
    } else if (name === 'chart') {
      assert.equal(await page.evaluate(() => Chart.version), '4.5.1');
      await page.locator('#value').fill('11');
      await page.locator('#edit button').tap();
      await page.waitForFunction(() => Chart.getChart(document.querySelector('#chart')).data.datasets[0].data[0] === 11);
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForFunction(() => Chart.getChart(document.querySelector('#chart'))?.data.datasets[0].data[0] === 11);
      await page.evaluate(async () => {
        await moru.storage.set('values', [9, 8, 7, 6, 5, 4, 3]);
        window.__moruChanged('values');
      });
      await page.waitForFunction(() => Chart.getChart(document.querySelector('#chart')).data.datasets[0].data[0] === 9);
    } else if (name === 'sqlite') {
      await page.locator('#text').fill('Проверено без сети');
      await page.locator('#add button').tap();
      await page.waitForFunction(() => document.querySelector('#notes').textContent.includes('Проверено без сети'));
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForFunction(() => document.querySelector('#notes').textContent.includes('Проверено без сети'));
      assert.ok(requests.some(path => path.endsWith('.wasm')), 'SQLite must load actual WASM');
      await page.locator('#notes button').tap();
      await page.waitForFunction(() => document.querySelector('#notes').children.length === 0);
      const bytes = await page.evaluate(() => moru.storage.get('database'));
      assert.deepEqual(bytes.slice(0, 15), [...Buffer.from('SQLite format 3')]);
    } else {
      const canvas = page.locator(name === 'phaser' ? '#stage canvas' : '#world');
      assert.equal(await canvas.count(), 1, `${name} must render a real canvas`);
      await page.waitForFunction(() => !document.querySelector('#start').disabled);
      await page.locator('#start').tap();
      await page.locator('#pause').tap();
      assert.equal(await page.locator('#status').textContent(), 'Пауза');
      await page.locator('#pause').tap();
      if (name === 'phaser') {
        assert.equal(await page.evaluate(() => Phaser.VERSION), '3.90.0');
        // With the hero in its starting lane, the first coin and then the
        // danger collide through the real Phaser Arcade Physics world.
      } else {
        assert.equal(await page.evaluate(() => typeof Galacean.WebGLEngine.create), 'function');
        // Move the real sprite up into the first collectible using pointer
        // input on the on-screen joystick, then release so the enemy catches it.
        const box = await page.locator('#joystick').boundingBox();
        const x = box.x + box.width / 2, y = box.y + box.height / 2;
        await page.mouse.move(x, y);
        await page.mouse.down();
        await page.mouse.move(x, y - 36);
        await page.waitForFunction(() => Number(document.querySelector('#score').textContent) >= 1, null, { timeout: 5000 });
        await page.mouse.up();
        assert.equal(await page.locator('#knob').evaluate(knob => knob.style.transform), '');
      }
      await page.waitForFunction(() => document.querySelector('#status').textContent.startsWith('Игра окончена'), null, { timeout: 35000 });
      await page.waitForFunction(() => !document.querySelector('#start').disabled);
      assert.ok(Number(await page.locator('#score').textContent()) >= 1, `${name}: collectible collision failed`);
      assert.ok(Number(await page.locator('#best').textContent()) >= 1, `${name}: best score was not saved`);
      await page.locator('#start').tap();
      assert.equal(await page.locator('#score').textContent(), '0');
      await page.locator('#pause').tap();
      await page.reload({ waitUntil: 'networkidle' });
      await page.waitForFunction(() => Number(document.querySelector('#best').textContent) >= 1);
    }

    await page.evaluate(script => (0, eval)(script), process.env.MORU_DARK_THEME);
    assert.equal(await page.evaluate(() => moru.theme.dark), true);
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--moru-accent').trim()), '#89d8c5');
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--moru-surface').trim()), '#25262d');
    if (name === 'chart') assert.equal(await page.evaluate(() => Chart.getChart(document.querySelector('#chart')).data.datasets[0].backgroundColor), '#89d8c5');
    await page.setViewportSize({ width: 320, height: 640 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${name}: narrow layout overflows`);
    assert.deepEqual(external, [], `${name} attempted external network access`);
    assert.deepEqual(errors, [], `${name} script/console errors`);
    console.log(JSON.stringify({ example: name, offline: true, runtimeRequests: requests.filter(path => path.includes('__moru_assets/')).length, interactions: 'passed' }));
    await context.close();
  }
} finally {
  await browser.close();
}
