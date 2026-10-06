// Emulator overlay: runs a built PRG in c64-ready's C64Player.
//
// Thrust reads the keyboard only (no joystick), so the player runs in
// keyboard mode and the editor's own shortcuts are paused while it is open.
// Each run uses a fresh player (the same path as a first start), which is
// the reliable way to autorun a new PRG.
//
// Two layouts, picked by "play full screen" in the panel:
// * windowed: over the map, with the panel beside it; a bar above the game
//   (title, status, Rebuild, Restart, ...) and the keys below it.
// * full screen: the browser's full screen where it allows it, else covering
//   the page. The game fills the screen; Close, Pad and Pause float over it,
//   and short messages fade.
// The virtual gamepad (touch) and physical gamepads hold Thrust's keys
// through a KeyMixer (controls.ts).

import { C64Player, CanvasRenderer } from 'c64-ready';
import { ACTION_KEYS, type Action, KeyMixer, dpadActions, gamepadActions } from './controls';

const BASE = import.meta.env.BASE_URL;
const WASM_URL = `${BASE}c64/c64.wasm`;
const WORKLET_URL = `${BASE}c64/audio-worklet-processor.js`;
const PAD_KEY = 'thrust-editor.vpad';
const MESSAGE_MS = 3000;

// c64-ready drives the C64 joystick from a gamepad, which Thrust never reads
// (and joystick lines can look like keys to the keyboard scan): keep its
// gamepad handling out, controls.ts maps gamepads to keys instead.
// Capture listeners on the target run before c64-ready's own listener.
window.addEventListener('gamepadconnected', (e) => e.stopImmediatePropagation(), true);

type FullscreenEl = HTMLElement & { webkitRequestFullscreen?: () => void };
type FullscreenDoc = Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => void };

export class PlayerOverlay {
  /** True while the overlay is shown (input.ts ignores editor shortcuts). */
  isOpen = false;
  onRebuild: () => void = () => {};
  onOpen: () => void = () => {};
  onClose: () => void = () => {};

  private root: HTMLElement;
  private canvas: HTMLCanvasElement;
  private message: HTMLElement;
  private status: HTMLElement;
  private title: HTMLElement;
  private last: { prg: Uint8Array; title: string } | null = null;
  private muted = false;
  private messageTimer = 0;
  private player: C64Player | null = null;
  private paused = false;
  private padShown: boolean;
  private generation = 0;
  private keys = new KeyMixer((type, a, shift) => this.sendKey(type, a, shift));
  private pollFrame = 0;
  private startWasDown = false;
  private gamepadSeen = false;

  constructor(host: HTMLElement) {
    this.root = document.createElement('div');
    this.root.id = 'play';
    this.root.hidden = true;
    this.root.innerHTML = `
      <div class="play-top">
        <b id="play-title"></b>
        <span id="play-status" class="muted"></span>
        <span class="spacer"></span>
        <button id="play-rebuild" title="build the current edits and restart">Rebuild</button>
        <button id="play-restart" title="run this build again">Restart</button>
        <button id="play-mute">Sound off</button>
        <button id="play-close" title="back to the editor">Close</button>
      </div>
      <div class="play-screen">
        <canvas id="play-canvas" width="384" height="272"></canvas>
        <div class="play-bar">
          <button id="play-x" title="back to the editor" aria-label="Close">✕</button>
          <button id="play-pad" title="show or hide the on-screen gamepad">Pad</button>
          <button id="play-pause" title="pause (F5) / resume (F7)">Pause</button>
        </div>
        <div id="play-message" hidden></div>
      </div>
      <div class="play-help">
        <kbd>Space</kbd> start game / shield &amp; tractor ·
        <kbd>A</kbd> <kbd>S</kbd> rotate · <kbd>Shift</kbd> thrust · <kbd>Return</kbd> fire ·
        <kbd>F5</kbd> pause, <kbd>F7</kbd> resume · <kbd>Esc</kbd> (Run/Stop) abort
      </div>
      <div class="vpad-dpad" aria-label="D-pad: rotate, up thrust, down shield">
        <span class="up">▲</span><span class="left">◀</span><span class="right">▶</span><span class="down">▼</span>
      </div>
      <div class="vpad-btns">
        <button data-act="shield">Shield</button>
        <button data-act="fire">Fire</button>
        <button data-act="thrust">Thrust</button>
      </div>`;
    host.append(this.root);
    const $ = (id: string) => this.root.querySelector<HTMLElement>('#' + id)!;
    this.canvas = $('play-canvas') as HTMLCanvasElement;
    this.message = $('play-message');
    this.status = $('play-status');
    this.title = $('play-title');
    $('play-pause').onclick = () => this.togglePause();
    $('play-close').onclick = () => this.close();
    $('play-x').onclick = () => this.close();
    $('play-rebuild').onclick = () => this.onRebuild();
    $('play-restart').onclick = () => this.last && this.play(this.last.prg, this.last.title);
    $('play-mute').onclick = (e) => {
      this.muted = !this.muted;
      this.player?.audio.setMuted(this.muted);
      (e.target as HTMLElement).textContent = this.muted ? 'Sound on' : 'Sound off';
    };
    let pref: string | null = null;
    try {
      pref = localStorage.getItem(PAD_KEY);
    } catch {}
    this.padShown = pref ? pref === 'on' : matchMedia('(pointer: coarse)').matches;
    $('play-pad').onclick = () => {
      this.showPad(!this.padShown);
      try {
        localStorage.setItem(PAD_KEY, this.padShown ? 'on' : 'off');
      } catch {}
    };
    this.showPad(this.padShown);
    this.mountPad();
    // left full screen (Esc, the system back gesture): a tap on the game goes back
    this.canvas.addEventListener('pointerdown', () => this.isOpen && this.isFull && !fullscreenElement() && this.enterFullscreen());
    // no key stays held when the page goes to the background
    document.addEventListener('visibilitychange', () => document.hidden && this.keys.releaseAll());
  }

  private get isFull(): boolean {
    return this.root.classList.contains('full');
  }

  /** The status: in the bar when windowed; full screen, a short message over
   *  the top of the game that fades unless `stay`. */
  setStatus(text: string, stay = false): void {
    this.status.textContent = text;
    clearTimeout(this.messageTimer);
    if (!this.isFull) return void (this.message.hidden = true);
    this.message.textContent = text;
    this.message.hidden = !text;
    if (text && !stay) this.messageTimer = window.setTimeout(() => (this.message.hidden = true), MESSAGE_MS);
  }

  /**
   * Shows the overlay, windowed or full screen. Call it straight from the
   * click or key that asked to play: browsers only allow full screen from one.
   */
  open(full = false): void {
    if (this.isOpen) return;
    this.isOpen = true;
    this.onOpen();
    this.root.hidden = false;
    this.root.classList.toggle('full', full);
    if (full) {
      document.body.classList.add('playing');
      this.enterFullscreen();
    }
    this.startPolling();
  }

  /** The build for this run failed: the panel shows why. */
  buildFailed(): void {
    if (!this.isOpen) return;
    // full screen, or nothing to go back to: close, so the panel shows
    if (this.isFull || !this.player) void this.close();
    else this.setStatus('build failed: see the panel', true);
  }

  async play(prg: Uint8Array, title: string): Promise<void> {
    const gen = ++this.generation;
    this.last = { prg, title };
    this.open();
    this.title.textContent = title;
    this.setStatus('starting…', true);
    this.keys.releaseAll();
    this.setPaused(false);
    await this.stopPlayer();
    if (gen !== this.generation) return;
    const renderer = new CanvasRenderer(this.canvas);
    const player = new C64Player({
      wasmUrl: WASM_URL,
      gameUrl: 'null',
      gameData: prg,
      gameType: 'prg',
      gameSource: title,
      renderer,
      audio: { workletUrl: WORKLET_URL },
      onProgress: (pct, label) => {
        if (gen !== this.generation) return;
        renderer.setProgress(pct, label);
        if (pct >= 100) renderer.hideLoader(300);
      },
    });
    this.player = player;
    try {
      await player.start();
      if (gen !== this.generation) return void player.destroy();
      player.setInputMode('keyboard');
      player.audio.setMuted(this.muted);
      this.setStatus(this.padShown ? 'press Shield to start' : 'press Space (or B) to start');
      this.canvas.focus();
    } catch (e) {
      renderer.setError(String(e));
      this.setStatus(`emulator error: ${e}`, true);
    }
  }

  async close(): Promise<void> {
    this.generation++;
    this.isOpen = false;
    this.keys.releaseAll();
    cancelAnimationFrame(this.pollFrame);
    if (fullscreenElement() === this.root) exitFullscreen();
    document.body.classList.remove('playing');
    this.root.classList.remove('full');
    this.setStatus('');
    this.root.hidden = true;
    await this.stopPlayer();
    this.onClose();
  }

  private async stopPlayer(): Promise<void> {
    const p = this.player;
    this.player = null;
    if (p) await p.destroy().catch(() => {});
  }

  /** The browser's full screen, where it allows it (not on iPhone; and only from a click or key). */
  private enterFullscreen(): void {
    if (fullscreenElement()) return;
    const el = this.root as FullscreenEl;
    try {
      const r = el.requestFullscreen ? el.requestFullscreen({ navigationUI: 'hide' }) : el.webkitRequestFullscreen?.();
      if (r instanceof Promise) r.catch(() => {});
    } catch {
      // not allowed here: the overlay covers the page anyway
    }
  }

  private showPad(on: boolean): void {
    this.padShown = on;
    this.root.classList.toggle('pad', on);
    this.root.querySelector('#play-pad')!.classList.toggle('on', on);
    if (!on) this.keys.releaseAll();
  }

  private setPaused(on: boolean): void {
    this.paused = on;
    this.root.querySelector('#play-pause')!.textContent = on ? 'Resume' : 'Pause';
    this.root.querySelector('#play-pause')!.classList.toggle('on', on);
  }

  private togglePause(): void {
    if (!this.player) return;
    this.keys.tap(this.paused ? 'resume' : 'pause');
    this.setPaused(!this.paused);
  }

  /** Thrust's key for an action, as a key event c64-ready's keyboard handler reads. */
  private sendKey(type: 'keydown' | 'keyup', a: Action, shift: boolean): void {
    if (!this.player) return;
    const [key, code] = ACTION_KEYS[a];
    window.dispatchEvent(new KeyboardEvent(type, { key, code, shiftKey: shift, bubbles: true, cancelable: true }));
  }

  private mountPad(): void {
    const dpad = this.root.querySelector<HTMLElement>('.vpad-dpad')!;
    const arrows = (held: Action[]) => {
      for (const [cls, a] of [['up', 'thrust'], ['down', 'shield'], ['left', 'left'], ['right', 'right']] as const)
        dpad.querySelector('.' + cls)!.classList.toggle('on', held.includes(a));
    };
    const fromPointer = (e: PointerEvent) => {
      const r = dpad.getBoundingClientRect();
      const held = dpadActions(e.clientX - (r.left + r.width / 2), e.clientY - (r.top + r.height / 2), r.width / 2);
      this.keys.set(`dpad:${e.pointerId}`, held);
      arrows(held);
    };
    const end = (e: PointerEvent) => {
      this.keys.set(`dpad:${e.pointerId}`, []);
      arrows([]);
    };
    dpad.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      capture(dpad, e.pointerId);
      navigator.vibrate?.(8);
      fromPointer(e);
    });
    dpad.addEventListener('pointermove', (e) => e.buttons && fromPointer(e));
    for (const t of ['pointerup', 'pointercancel', 'lostpointercapture']) dpad.addEventListener(t, end as EventListener);

    for (const b of this.root.querySelectorAll<HTMLElement>('.vpad-btns button')) {
      const a = b.dataset.act as Action;
      const end = (e: PointerEvent) => {
        this.keys.set(`btn:${e.pointerId}:${a}`, []);
        b.classList.remove('on');
      };
      b.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        capture(b, e.pointerId);
        navigator.vibrate?.(8);
        this.keys.set(`btn:${e.pointerId}:${a}`, [a]);
        b.classList.add('on');
      });
      for (const t of ['pointerup', 'pointercancel', 'lostpointercapture']) b.addEventListener(t, end as EventListener);
    }
    // no long-press menus, text selection or double-tap zoom on the pad
    for (const el of this.root.querySelectorAll<HTMLElement>('.vpad-dpad, .vpad-btns'))
      el.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  /** Reads every connected gamepad once per frame while the overlay is open. */
  private startPolling(): void {
    const step = () => {
      this.pollFrame = requestAnimationFrame(step);
      const pads = navigator.getGamepads?.() ?? [];
      const held = new Set<Action>();
      let start = false;
      for (const gp of pads) {
        if (!gp?.connected) continue;
        const r = gamepadActions(
          gp.buttons.map((b) => b.pressed),
          gp.axes,
        );
        r.held.forEach((a) => held.add(a));
        start ||= r.start;
        if (!this.gamepadSeen && (r.held.size || r.start)) {
          this.gamepadSeen = true;
          this.setStatus(`gamepad: ${gp.id.replace(/\s*\(.*$/, '')}`);
        }
      }
      this.keys.set('gamepad', held);
      if (start && !this.startWasDown) this.togglePause();
      this.startWasDown = start;
    };
    cancelAnimationFrame(this.pollFrame);
    step();
  }
}

function capture(el: HTMLElement, id: number): void {
  try {
    el.setPointerCapture(id);
  } catch {
    // synthetic pointers (tests) cannot be captured
  }
}

function fullscreenElement(): Element | null {
  const d = document as FullscreenDoc;
  return d.fullscreenElement ?? d.webkitFullscreenElement ?? null;
}

function exitFullscreen(): void {
  const d = document as FullscreenDoc;
  if (d.exitFullscreen) d.exitFullscreen().catch(() => {});
  else d.webkitExitFullscreen?.();
}
