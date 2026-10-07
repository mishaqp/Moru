(async function () {
  const scoreLabel = document.querySelector('#score');
  const bestLabel = document.querySelector('#best');
  const status = document.querySelector('#status');
  const start = document.querySelector('#start');
  const pause = document.querySelector('#pause');
  let best = 0, direction = 0, game;
  const fail = error => { status.textContent = `Ошибка: ${error.message}`; };
  try {
    await Promise.all([moru.assets.load('ui'), moru.assets.load('phaser')]);
    if ((await moru.app.info()).background) { status.textContent = 'Фоновый режим'; return; }
    best = Math.max(0, Number(await moru.storage.get('best')) || 0);
    bestLabel.textContent = String(best);
    class Coins extends Phaser.Scene {
      create() {
        const draw = this.make.graphics({ x: 0, y: 0, add: false });
        for (const [key, color, radius] of [['hero', 0x5cb9ff, 20], ['coin', 0xffce45, 12], ['danger', 0xf06c76, 18]]) {
          draw.clear().fillStyle(color).fillCircle(24, 24, radius).generateTexture(key, 48, 48);
        }
        draw.destroy();
        this.hero = this.physics.add.image(180, 490, 'hero').setCircle(20, 4, 4).setCollideWorldBounds(true);
        this.coin = this.physics.add.image(180, 250, 'coin').setCircle(12, 12, 12);
        this.danger = this.physics.add.image(180, -100, 'danger').setCircle(18, 6, 6);
        this.physics.add.overlap(this.hero, this.coin, () => {
          if (this.state !== 'running') return;
          scoreLabel.textContent = String(++this.score);
          this.coin.setPosition(30 + Math.random() * 300, -30);
        });
        this.physics.add.overlap(this.hero, this.danger, () => { void this.finish(); });
        this.keys = this.input.keyboard.createCursorKeys();
        const move = pointer => {
          if (this.state === 'running' && pointer.isDown) this.hero.x = Phaser.Math.Clamp(pointer.x, 24, 336);
        };
        this.input.on('pointerdown', move);
        this.input.on('pointermove', move);
        this.state = 'ready';
        this.physics.pause();
        const repaint = () => { this.cameras.main.setBackgroundColor(getComputedStyle(document.documentElement).getPropertyValue('--moru-surface').trim()); };
        repaint();
        window.addEventListener('moru:theme', repaint);
        start.disabled = false;
        status.textContent = 'Нажмите «Начать»';
        start.addEventListener('click', () => this.begin());
        pause.addEventListener('click', () => this.togglePause());
        document.addEventListener('visibilitychange', () => {
          direction = 0;
          if (document.hidden && this.state === 'running') this.togglePause();
        });
      }
      begin() {
        this.score = 0;
        this.elapsed = 0;
        scoreLabel.textContent = '0';
        this.hero.setPosition(180, 490).setVelocity(0, 0);
        this.coin.setPosition(180, 250).setVelocity(0, 90);
        this.danger.setPosition(180, -100).setVelocity(0, 110);
        this.state = 'running';
        direction = 0;
        this.physics.resume();
        start.textContent = 'Заново';
        pause.textContent = 'Пауза';
        pause.disabled = false;
        status.textContent = 'Собирайте монеты!';
      }
      togglePause() {
        if (this.state === 'running') {
          this.state = 'paused';
          this.physics.pause();
          pause.textContent = 'Продолжить';
          status.textContent = 'Пауза';
        } else if (this.state === 'paused') {
          this.state = 'running';
          this.physics.resume();
          pause.textContent = 'Пауза';
          status.textContent = 'Собирайте монеты!';
        }
      }
      async finish() {
        if (this.state !== 'running') return;
        this.state = 'over';
        this.physics.pause();
        pause.disabled = true;
        start.disabled = true;
        start.textContent = 'Ещё раз';
        status.textContent = `Игра окончена. Очки: ${this.score}`;
        try {
          best = Math.max(best, this.score);
          await moru.storage.set('best', best);
          bestLabel.textContent = String(best);
        } catch (error) { fail(error); }
        finally { start.disabled = false; }
      }
      update(_time, delta) {
        if (this.state !== 'running') return;
        this.hero.setVelocityX((this.keys.left.isDown ? -1 : this.keys.right.isDown ? 1 : direction) * 230);
        if (this.coin.y > 600) this.coin.setPosition(30 + Math.random() * 300, -30);
        if (this.danger.y > 600) this.danger.setPosition(30 + Math.random() * 300, -100);
        this.elapsed += delta;
        if (this.elapsed >= 30000) void this.finish();
      }
    }
    for (const [id, value] of [['left', -1], ['right', 1]]) {
      const button = document.querySelector(`#${id}`);
      button.addEventListener('pointerdown', event => { button.setPointerCapture(event.pointerId); direction = value; });
      for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) button.addEventListener(event, () => { direction = 0; });
    }
    game = new Phaser.Game({
      type: Phaser.AUTO, width: 360, height: 560, parent: 'stage',
      scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_BOTH },
      physics: { default: 'arcade', arcade: { debug: false } },
      scene: Coins, audio: { noAudio: true }
    });
    window.addEventListener('moru:storage', event => {
      if (event.detail.key === 'best') void moru.storage.get('best').then(value => {
        best = Math.max(0, Number(value) || 0);
        bestLabel.textContent = String(best);
      }).catch(fail);
    });
    window.addEventListener('pagehide', () => game.destroy(true), { once: true });
  } catch (error) { fail(error); }
})();
