// Thrust autopilot: flies the original mission 1 in the level editor's player
// (see autopilot-run.md). Paste into the browser console on the editor run
// with `npm run dev` (it needs window.editor and the build API). It builds the
// template's levels, opens the player covering the page (click the game to go
// full screen for a recording), starts a game and flies it: to the pod, beam,
// lift, out. It only presses Thrust's keys and reads memory.
// Stop it early with: autopilot.stop()

(async () => {
  const { player } = window.editor;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  // keys, as key events to c64-ready's keyboard handler. c64-ready lets go of
  // the C64's Shift on any key down without shiftKey, so every event says
  // whether thrust (Shift) is held
  const K = { left: ['a', 'KeyA'], right: ['s', 'KeyS'], thrust: ['Shift', 'ShiftLeft'], shield: [' ', 'Space'] };
  const held = new Set();
  const send = (type, a) =>
    window.dispatchEvent(new KeyboardEvent(type, { key: K[a][0], code: K[a][1], shiftKey: held.has('thrust'), bubbles: true }));
  const set = (a, on) => {
    if (on && !held.has(a)) { held.add(a); send('keydown', a); }
    else if (!on && held.has(a)) { held.delete(a); send('keyup', a); }
  };
  const releaseAll = () => [...held].forEach((a) => set(a, false));

  // memory (labels from src/thrust.asm)
  const rd = (a) => player.player.ramRead(a);
  const s8 = (v) => (v > 127 ? v - 256 : v);
  const state = () => ({
    ang: rd(0x0d), // ship_angle: 0 up, 8 right, 16 down
    x: rd(0x33) + rd(0x32) / 256, // player_xpos
    y: rd(0x30) * 256 + rd(0x2f) + rd(0x2e) / 256, // player_ypos (down is +)
    vx: s8(rd(0x14)) + rd(0x13) / 256, // velocity_vectorx
    vy: s8(rd(0x16)) + rd(0x15) / 256, // velocity_vectory
    attached: rd(0x22), // pod_attached_flag_1
    line: rd(0x45), // pod_line_exists_flag
    tick: rd(0x61), // level_tick_state: 0 while playing
  });

  // 1. build the original levels and open the player
  const t = await (await fetch('/api/template')).json();
  const r = await (
    await fetch('/api/build', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ levelsAsm: t.levelsAsm, tablesAsm: t.tablesAsm, startLevel: 0 }),
    })
  ).json();
  if (!r.ok) throw new Error('build failed: ' + r.errors?.join('; '));
  const prg = new Uint8Array(await (await fetch(`/api/builds/${r.id}/play.prg`)).arrayBuffer());
  player.open(true);
  await player.play(prg, 'mission 1 (autopilot)');

  // 2. start a game: the title ignores keys for a few seconds, then Space
  //    has to be held for a moment
  await wait(5000);
  set('shield', true);
  await wait(1500);
  set('shield', false);

  // 3. fly
  const POD = { x: 0x8f, y: 0x1bd }; // mission 1's pod stand
  const c = { kp: 0.03, kv: 0.2, g: 0.006, thrMin: 0.002 };
  const clamp = (v, m) => Math.max(-m, Math.min(m, v));
  let phase = 'go';
  let running = true;
  let doneAt = 0;
  const stop = () => { running = false; releaseAll(); };
  window.autopilot = { stop, get phase() { return phase; } };

  function loop() {
    if (!running) return;
    requestAnimationFrame(loop);
    const s = state();
    // starting, paused, exploding or between lives: hands off, start over
    if (s.tick !== 0 || s.y < 16) { releaseAll(); phase = 'go'; return; }
    let tx = POD.x, ty = POD.y - 20, vmax = 0.5, tractor = false;
    if (phase === 'go' && Math.abs(tx - s.x) < 3 && Math.abs(ty - s.y) < 6 && Math.abs(s.vx) < 0.15 && Math.abs(s.vy) < 0.2)
      phase = 'grab';
    // hover 14 rows above the stand with the beam on until the line appears
    if (phase === 'grab') { ty = POD.y - 14; tractor = true; if (s.line) phase = 'lift'; }
    // climb out, holding the beam until the pod is attached
    if (phase === 'lift') { ty = 0x100; vmax = 0.25; tractor = !s.attached; }
    if (phase === 'lift' && s.attached && s.y < 0x118 && !doneAt) {
      doneAt = performance.now();
      setTimeout(() => { stop(); console.log('autopilot: out with the pod'); }, 3000);
    }

    // wanted speed towards the target, the push that needs, and its angle
    const ex = ((Math.round(tx - s.x) + 128) & 255) - 128; // X wraps at 256
    const ey = ty - s.y;
    const Tx = (clamp(ex * c.kp, vmax) - s.vx) * c.kv;
    const Ty = (clamp(ey * c.kp, vmax) - s.vy) * c.kv - c.g;
    let ta = Math.round((Math.atan2(Tx, -Ty) / (2 * Math.PI)) * 32);
    ta = (Math.max(-7, Math.min(7, ((((ta + 16) % 32) + 32) % 32) - 16)) + 32) % 32; // at most ~80° from up
    // turn towards it; thrust when within a step and the push is the way we face
    const err = ((ta - s.ang + 48) % 32) - 16;
    set('right', err > 0);
    set('left', err < 0);
    const th = (s.ang * 2 * Math.PI) / 32;
    set('thrust', Math.abs(err) <= 1 && Tx * Math.sin(th) - Ty * Math.cos(th) > c.thrMin);
    set('shield', tractor);
  }
  loop();
})();
