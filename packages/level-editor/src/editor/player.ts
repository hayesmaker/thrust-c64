// Emulator overlay: runs a built PRG in c64-ready's C64Player.
//
// Thrust reads the keyboard only (no joystick), so the player runs in
// keyboard mode and the editor's own shortcuts are paused while it is open.
// Each run uses a fresh player (the same path as a first start), which is
// the reliable way to autorun a new PRG.

import { C64Player, CanvasRenderer } from 'c64-ready';

const BASE = import.meta.env.BASE_URL;
const WASM_URL = `${BASE}c64/c64.wasm`;
const WORKLET_URL = `${BASE}c64/audio-worklet-processor.js`;

export class PlayerOverlay {
  /** True while the overlay is shown (input.ts ignores editor shortcuts). */
  isOpen = false;
  onRebuild: () => void = () => {};
  onOpen: () => void = () => {};
  onClose: () => void = () => {};

  private root: HTMLElement;
  private canvas: HTMLCanvasElement;
  private status: HTMLElement;
  private title: HTMLElement;
  private player: C64Player | null = null;
  private last: { prg: Uint8Array; title: string } | null = null;
  private muted = false;
  private generation = 0;

  constructor(host: HTMLElement) {
    this.root = document.createElement('div');
    this.root.id = 'play';
    this.root.hidden = true;
    this.root.innerHTML = `
      <div class="play-bar">
        <b id="play-title"></b>
        <span id="play-status" class="muted"></span>
        <span class="spacer"></span>
        <button id="play-rebuild" title="build the current edits and restart">Rebuild</button>
        <button id="play-restart" title="run this build again">Restart</button>
        <button id="play-mute">Sound off</button>
        <button id="play-close">Close</button>
      </div>
      <div class="play-screen"><canvas id="play-canvas" width="384" height="272"></canvas></div>
      <div class="play-help">
        <kbd>Space</kbd> start game / shield &amp; tractor ·
        <kbd>A</kbd> <kbd>S</kbd> rotate · <kbd>Shift</kbd> thrust · <kbd>Return</kbd> fire ·
        <kbd>F5</kbd> pause, <kbd>F7</kbd> resume · <kbd>Esc</kbd> (Run/Stop) abort
      </div>`;
    host.append(this.root);
    const $ = (id: string) => this.root.querySelector<HTMLElement>('#' + id)!;
    this.canvas = $('play-canvas') as HTMLCanvasElement;
    this.status = $('play-status');
    this.title = $('play-title');
    $('play-rebuild').onclick = () => this.onRebuild();
    $('play-restart').onclick = () => this.last && this.play(this.last.prg, this.last.title);
    $('play-mute').onclick = (e) => {
      this.muted = !this.muted;
      this.player?.audio.setMuted(this.muted);
      (e.target as HTMLElement).textContent = this.muted ? 'Sound on' : 'Sound off';
    };
    $('play-close').onclick = () => this.close();
  }

  setStatus(text: string): void {
    this.status.textContent = text;
  }

  async play(prg: Uint8Array, title: string): Promise<void> {
    const gen = ++this.generation;
    this.last = { prg, title };
    if (!this.isOpen) this.onOpen();
    this.isOpen = true;
    this.root.hidden = false;
    this.title.textContent = title;
    this.setStatus('starting…');
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
      this.setStatus('running: press Space to start');
      this.canvas.focus();
    } catch (e) {
      renderer.setError(String(e));
      this.setStatus(`emulator error: ${e}`);
    }
  }

  async close(): Promise<void> {
    this.generation++;
    this.isOpen = false;
    this.root.hidden = true;
    await this.stopPlayer();
    this.onClose();
  }

  private async stopPlayer(): Promise<void> {
    const p = this.player;
    this.player = null;
    if (p) await p.destroy().catch(() => {});
  }
}
