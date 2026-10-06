(async function () {
  const status = document.querySelector('#status');
  const start = document.querySelector('#start');
  const pause = document.querySelector('#pause');
  const scoreLabel = document.querySelector('#score');
  const bestLabel = document.querySelector('#best');
  const pad = document.querySelector('#joystick');
  const knob = document.querySelector('#knob');
  const stick = { x: 0, y: 0, pointer: null };
  const keys = new Set();
  let engine, state = 'ready', score = 0, best = 0, elapsed = 0, halfWidth = 3;
  const fail = error => { status.textContent = `Ошибка: ${error.message}`; };
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  function release() { stick.x = stick.y = 0; stick.pointer = null; knob.style.transform = ''; keys.clear(); }
  function move(event) {
    if (event.pointerId !== stick.pointer) return;
    const box = pad.getBoundingClientRect();
    const x = event.clientX - box.left - box.width / 2;
    const y = event.clientY - box.top - box.height / 2;
    const length = Math.max(38, Math.hypot(x, y));
    stick.x = x / length;
    stick.y = -y / length;
    knob.style.transform = `translate(${stick.x * 38}px, ${-stick.y * 38}px)`;
  }
  try {
    await Promise.all([moru.assets.load('ui'), moru.assets.load('galacean')]);
    if ((await moru.app.info()).background) { status.textContent = 'Фоновый режим'; return; }
    best = Math.max(0, Number(await moru.storage.get('best')) || 0);
    bestLabel.textContent = String(best);
    const { WebGLEngine, Camera, Sprite, SpriteRenderer, Texture2D, TextureFormat, Script, Color } = Galacean;
    engine = await WebGLEngine.create({ canvas: document.querySelector('#world') });
    const scene = engine.sceneManager.activeScene;
    const root = scene.createRootEntity('Game');
    const cameraEntity = root.createChild('Camera');
    cameraEntity.transform.setPosition(0, 0, 10);
    const camera = cameraEntity.addComponent(Camera);
    camera.isOrthographic = true;
    camera.orthographicSize = 4;
    // Procedural local texture, rendered by real Galacean SpriteRenderer components.
    const texture = new Texture2D(engine, 32, 32, TextureFormat.R8G8B8A8, false);
    const pixels = new Uint8Array(32 * 32 * 4);
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
      const offset = (y * 32 + x) * 4;
      pixels.set([255, 255, 255, Math.hypot(x - 15.5, y - 15.5) < 15 ? 255 : 0], offset);
    }
    texture.setPixelBuffer(pixels);
    const sprite = new Sprite(engine, texture);
    sprite.width = sprite.height = 1;
    function actor(name, color, radius, x, y) {
      const entity = root.createChild(name);
      entity.transform.setPosition(x, y, 0);
      const renderer = entity.addComponent(SpriteRenderer);
      renderer.sprite = sprite;
      renderer.width = renderer.height = radius * 2;
      renderer.color = color;
      return { entity, renderer, radius, x, y };
    }
    const hero = actor('Hero', new Color(0.2, 0.65, 1, 1), 0.28, 0, -2.5);
    const star = actor('Star', new Color(1, 0.75, 0.1, 1), 0.2, 0, -1.2);
    const enemy = actor('Enemy', new Color(1, 0.2, 0.3, 1), 0.3, 1.4, 2.5);
    function place(actor) { actor.entity.transform.setPosition(actor.x, actor.y, 0); }
    function resize() {
      engine.canvas.resizeByClientSize();
      halfWidth = camera.orthographicSize * engine.canvas.width / engine.canvas.height;
      hero.x = clamp(hero.x, -halfWidth + hero.radius, halfWidth - hero.radius);
      star.x = clamp(star.x, -halfWidth + star.radius, halfWidth - star.radius);
      enemy.x = clamp(enemy.x, -halfWidth + enemy.radius, halfWidth - enemy.radius);
      [hero, star, enemy].forEach(place);
    }
    function repaint() {
      const css = getComputedStyle(document.documentElement);
      // Background colors are sRGB CSS hex strings; engine Color uses linear RGB.
      const hex = css.getPropertyValue('--moru-surface').trim().replace('#', '');
      const rgb = [0, 2, 4].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255);
      const linear = value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
      scene.background.solidColor = new Color(...rgb.map(linear), 1);
    }
    async function finish() {
      if (state !== 'running') return;
      state = 'over';
      release();
      pause.disabled = true;
      start.disabled = true;
      start.textContent = 'Ещё раз';
      status.textContent = `Игра окончена. Очки: ${score}`;
      try {
        best = Math.max(best, score);
        await moru.storage.set('best', best);
        bestLabel.textContent = String(best);
      } catch (error) { fail(error); }
      finally { start.disabled = false; }
    }
    function togglePause() {
      if (state === 'running') { state = 'paused'; release(); pause.textContent = 'Продолжить'; status.textContent = 'Пауза'; }
      else if (state === 'paused') { state = 'running'; pause.textContent = 'Пауза'; status.textContent = 'Собирайте звёзды!'; }
    }
    class Play extends Script {
      onUpdate(deltaTime) {
        if (state !== 'running') return;
        const dt = Math.min(deltaTime, 0.05);
        const dx = stick.x + (keys.has('ArrowRight') ? 1 : 0) - (keys.has('ArrowLeft') ? 1 : 0);
        const dy = stick.y + (keys.has('ArrowUp') ? 1 : 0) - (keys.has('ArrowDown') ? 1 : 0);
        const length = Math.max(1, Math.hypot(dx, dy));
        hero.x = clamp(hero.x + dx / length * dt * 3, -halfWidth + hero.radius, halfWidth - hero.radius);
        hero.y = clamp(hero.y + dy / length * dt * 3, -3.7, 3.7);
        const distance = Math.hypot(hero.x - enemy.x, hero.y - enemy.y);
        if (distance > 0) { enemy.x += (hero.x - enemy.x) / distance * dt * 0.8; enemy.y += (hero.y - enemy.y) / distance * dt * 0.8; }
        [hero, enemy].forEach(place);
        // Explicit circle collisions in scene coordinates; no external physics plugin.
        if (Math.hypot(hero.x - star.x, hero.y - star.y) < hero.radius + star.radius) {
          scoreLabel.textContent = String(++score);
          star.x = (Math.random() * 2 - 1) * Math.max(0, halfWidth - star.radius);
          star.y = Math.random() * 6 - 3;
          place(star);
        }
        elapsed += dt;
        if (Math.hypot(hero.x - enemy.x, hero.y - enemy.y) < hero.radius + enemy.radius || elapsed >= 30) void finish();
      }
    }
    root.addComponent(Play);
    resize();
    repaint();
    engine.run();
    start.disabled = false;
    status.textContent = 'Нажмите «Начать»';
    start.addEventListener('click', () => {
      release();
      score = elapsed = 0;
      scoreLabel.textContent = '0';
      hero.x = 0; hero.y = -2.5; star.x = 0; star.y = -1.2; enemy.x = Math.min(1.4, halfWidth - enemy.radius); enemy.y = 2.5;
      [hero, star, enemy].forEach(place);
      state = 'running';
      start.textContent = 'Заново';
      pause.textContent = 'Пауза';
      pause.disabled = false;
      status.textContent = 'Собирайте звёзды!';
    });
    pause.addEventListener('click', togglePause);
    pad.addEventListener('pointerdown', event => {
      if (stick.pointer !== null) return;
      stick.pointer = event.pointerId;
      pad.setPointerCapture(event.pointerId);
      move(event);
    });
    pad.addEventListener('pointermove', move);
    for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) pad.addEventListener(name, event => { if (event.pointerId === stick.pointer) release(); });
    window.addEventListener('keydown', event => { if (event.key.startsWith('Arrow')) { event.preventDefault(); keys.add(event.key); } });
    window.addEventListener('keyup', event => keys.delete(event.key));
    window.addEventListener('blur', () => { release(); if (state === 'running') togglePause(); });
    document.addEventListener('visibilitychange', () => { if (document.hidden && state === 'running') togglePause(); });
    window.addEventListener('resize', resize);
    window.addEventListener('moru:theme', repaint);
    window.addEventListener('moru:storage', event => {
      if (event.detail.key === 'best') void moru.storage.get('best').then(value => { best = Math.max(0, Number(value) || 0); bestLabel.textContent = String(best); }).catch(fail);
    });
    window.addEventListener('pagehide', () => engine.destroy(), { once: true });
  } catch (error) { fail(error); if (engine) engine.destroy(); }
})();
