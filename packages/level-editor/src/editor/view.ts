// Canvas view: camera, terrain rendering, overlays, rulers, hit testing.
//
// World: X 0-255 (wraps; drawn repeated), rows downwards. Game aspect: one X
// unit is 4 C64 pixels and one row is 2, so an X unit is drawn 2x as wide as
// a row is tall. `scale` = screen pixels per row.

import { PALETTE_RGB, hex2, hex3 } from '../c64';
import type { Level, Wall } from '../model/level';
import { GUN_MUZZLE, gunArc, isGun } from '../model/objects';
import { doorWallX } from '../model/door';
import { OBJ_BOUNDS, SPRITE_ROWS, SPRITE_UNITS, objectParts, spriteImage } from './look';
import { wallXAt } from './ops';
import { type Selection, type Side, type Store, sameSelection } from './store';

export const RULER_LEFT = 64;
export const RULER_TOP = 22;
const HANDLE = 5; // half size of a point handle, px
const HIT = 8;
/** Approximate playfield: rows window Y + $38 ... + 92, 80 X units wide. */
const SCREEN_TOP = 0x38;
const SCREEN_ROWS = 92;
const SCREEN_COLS = 80;
const MIN_SCALE = 0.25;
const MAX_SCALE = 24;

export const WALL_COLOUR: Record<Side, string> = { left: '#4fd1ff', right: '#ffb84f' };

export interface SegmentHit {
  side: Side;
  /** Insert position in points. */
  index: number;
  row: number;
  x: number; // unwrapped
}

export class View {
  camX = 0;
  camY = 0x100;
  scale = 2;
  showObjects = true;
  showScreen = true;
  /** Gun firing arcs for all guns (the selected gun always shows its arc). */
  showArcs = false;
  /** Objects in the level's own colours instead of one colour per type. */
  gameColours = false;
  cursor: { x: number; row: number } | null = null;

  private ctx: CanvasRenderingContext2D;
  private terrain = document.createElement('canvas');
  private w = 0;
  private h = 0;
  private frame = 0;

  constructor(
    readonly canvas: HTMLCanvasElement,
    private store: Store,
  ) {
    this.ctx = canvas.getContext('2d')!;
    new ResizeObserver(() => this.resize()).observe(canvas);
    this.resize();
  }

  get ux(): number {
    return this.scale * 2;
  }

  resize(): void {
    const dpr = window.devicePixelRatio || 1;
    const r = this.canvas.getBoundingClientRect();
    this.w = r.width;
    this.h = r.height;
    this.canvas.width = Math.round(r.width * dpr);
    this.canvas.height = Math.round(r.height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.draw();
  }

  sx(x: number): number {
    return RULER_LEFT + (x - this.camX) * this.ux;
  }

  sy(row: number): number {
    return RULER_TOP + (row - this.camY) * this.scale;
  }

  toWorld(sx: number, sy: number): { x: number; row: number } {
    return { x: this.camX + (sx - RULER_LEFT) / this.ux, row: this.camY + (sy - RULER_TOP) / this.scale };
  }

  pan(dxPx: number, dyPx: number): void {
    this.camX -= dxPx / this.ux;
    this.camY = Math.max(-16, this.camY - dyPx / this.scale);
    this.requestDraw();
  }

  zoomAt(sx: number, sy: number, factor: number): void {
    const before = this.toWorld(sx, sy);
    this.scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale * factor));
    const after = this.toWorld(sx, sy);
    this.camX += before.x - after.x;
    this.camY += before.row - after.row;
    this.requestDraw();
  }

  /** Fit the cave (from just above the surface to the bottom) in the view. */
  fitLevel(): void {
    const l = this.store.current;
    if (!l) return;
    const top = Math.min(l.left.points[1]?.row ?? 0x1a0, l.right.points[1]?.row ?? 0x1a0) - 40;
    const bottom = Math.max(l.left.points.at(-1)!.row, l.right.points.at(-1)!.row) + 40;
    const s = Math.min((this.h - RULER_TOP) / (bottom - top), (this.w - RULER_LEFT) / (256 * 2));
    this.scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, s));
    this.camY = top;
    // centre on the cave horizontally
    const xs = [...l.left.points, ...l.right.points].slice(1).map((p) => p.x & 0xff);
    const mid = xs.length ? (Math.min(...xs) + Math.max(...xs)) / 2 : 128;
    this.camX = mid - (this.w - RULER_LEFT) / this.ux / 2;
    this.requestDraw();
  }

  /** Redraw the terrain bitmap (call when walls or colours change). */
  rebuildTerrain(): void {
    const l = this.store.current;
    const { left, right } = this.store.decoded;
    const rows = left.length;
    if (!l || rows === 0) return;
    this.terrain.width = 256;
    this.terrain.height = rows;
    const tctx = this.terrain.getContext('2d')!;
    const img = tctx.createImageData(256, rows);
    const [r, g, b] = PALETTE_RGB[l.colours.terrain || 9];
    const d = img.data;
    for (let y = 0; y < rows; y++) {
      const lx = left[y];
      const rx = right[y];
      for (let x = 0; x < 256; x++) {
        const solid = lx < rx ? x < lx || x > rx : true;
        const o = (y * 256 + x) * 4;
        if (solid) {
          d[o] = r;
          d[o + 1] = g;
          d[o + 2] = b;
          d[o + 3] = 255;
        }
      }
    }
    tctx.putImageData(img, 0, 0);
  }

  requestDraw(): void {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.draw();
    });
  }

  /** World X offsets (multiples of 256) of the copies that are on screen. */
  private tiles(): number[] {
    const x0 = this.camX;
    const x1 = this.camX + (this.w - RULER_LEFT) / this.ux;
    const out: number[] = [];
    for (let k = Math.floor(x0 / 256) - 1; k * 256 < x1 + 256; k++) out.push(k * 256);
    return out;
  }

  draw(): void {
    const c = this.ctx;
    c.clearRect(0, 0, this.w, this.h);
    c.fillStyle = '#000';
    c.fillRect(0, 0, this.w, this.h);
    const l = this.store.current;
    if (!l) return;
    const rows = this.store.decoded.left.length;

    c.save();
    c.beginPath();
    c.rect(RULER_LEFT, RULER_TOP, this.w - RULER_LEFT, this.h - RULER_TOP);
    c.clip();
    c.imageSmoothingEnabled = false;
    for (const t of this.tiles()) {
      c.drawImage(this.terrain, this.sx(t), this.sy(0), 256 * this.ux, rows * this.scale);
      // repeat the last decoded row (the walls stay put) to the bottom
      const yEnd = this.sy(rows);
      if (yEnd < this.h)
        c.drawImage(this.terrain, 0, rows - 1, 256, 1, this.sx(t), yEnd, 256 * this.ux, this.h - yEnd);
    }
    this.drawGrid();
    this.drawDoor(l);
    if (this.showObjects) {
      this.drawObjects(l);
      this.drawRestarts(l);
    }
    this.drawWall(l.left, 'left');
    this.drawWall(l.right, 'right');
    c.restore();
    this.drawRulers();
  }

  private drawGrid(): void {
    const c = this.ctx;
    const x0 = this.camX;
    const x1 = this.camX + (this.w - RULER_LEFT) / this.ux;
    const r0 = this.camY;
    const r1 = this.camY + (this.h - RULER_TOP) / this.scale;
    const line = (step: number, alpha: number, minPx: number) => {
      if (step * this.scale < minPx) return;
      c.strokeStyle = `rgba(255,255,255,${alpha})`;
      c.lineWidth = 1;
      c.beginPath();
      for (let x = Math.ceil(x0 / step) * step; x <= x1; x += step) {
        const s = Math.round(this.sx(x)) + 0.5;
        c.moveTo(s, RULER_TOP);
        c.lineTo(s, this.h);
      }
      for (let r = Math.ceil(r0 / step) * step; r <= r1; r += step) {
        const s = Math.round(this.sy(r)) + 0.5;
        c.moveTo(RULER_LEFT, s);
        c.lineTo(this.w, s);
      }
      c.stroke();
    };
    line(1, 0.06, 6);
    line(16, 0.12, 12);
    // world X wrap seams
    c.strokeStyle = 'rgba(255,80,80,0.35)';
    c.setLineDash([4, 4]);
    c.beginPath();
    for (const t of this.tiles()) {
      const s = Math.round(this.sx(t)) + 0.5;
      c.moveTo(s, RULER_TOP);
      c.lineTo(s, this.h);
    }
    c.stroke();
    c.setLineDash([]);
  }

  /** The door as the game will show it at the preview opening: each door row
   *  replaces the wall there, so rock out to the door edge (orange) and, where
   *  the edge is set back into the terrain, a hole cut into the rock (black,
   *  hatched). Faint: the closed door. Handles on the closed edge of each row
   *  and a tab on top. */
  private drawDoor(l: Level): void {
    const d = l.door;
    if (!d) return;
    const c = this.ctx;
    const wall = this.store.decoded[d.side];
    const now = doorWallX(d, Math.min(this.store.doorPreview, d.max));
    const sel = this.store.selection;
    const hov = this.store.hover;
    const doorSel = sel?.kind === 'door';
    const h = Math.max(1, this.scale);
    // rock between the terrain wall and the door edge at X
    const span = (row: number, x: number): [number, number] | null => {
      const w = wall[Math.min(row, wall.length - 1)];
      if (w === undefined) return null;
      return d.side === 'left' ? (x > w ? [w, x] : null) : x < w ? [x + 1, w + 1] : null;
    };
    // terrain rock that the door row turns into cave (edge set back into the wall)
    const carved = (row: number, x: number): [number, number] | null => {
      const w = wall[Math.min(row, wall.length - 1)];
      if (w === undefined) return null;
      return d.side === 'left' ? (x < w ? [x, w] : null) : x > w ? [w + 1, x + 1] : null;
    };
    for (const t of this.tiles()) {
      d.rows.forEach((closed, k) => {
        const row = d.top + k;
        const y = this.sy(row);
        const a = span(row, closed);
        if (a) {
          c.fillStyle = 'rgba(221,136,85,0.25)';
          c.fillRect(this.sx(a[0] + t), y, (a[1] - a[0]) * this.ux, h);
        }
        const b = span(row, now[k]);
        if (b) {
          c.fillStyle = 'rgba(221,136,85,0.9)';
          c.fillRect(this.sx(b[0] + t), y, (b[1] - b[0]) * this.ux, h);
        }
        const cut = carved(row, now[k]);
        if (cut) {
          c.fillStyle = '#000';
          c.fillRect(this.sx(cut[0] + t), y, (cut[1] - cut[0]) * this.ux, h);
          if ((row & 1) === 0) {
            c.fillStyle = 'rgba(221,136,85,0.35)';
            c.fillRect(this.sx(cut[0] + t), y, (cut[1] - cut[0]) * this.ux, Math.max(1, h / 2));
          }
        }
      });
      // closed edge
      c.strokeStyle = doorSel ? '#ffd34f' : 'rgba(255,200,150,0.9)';
      c.lineWidth = doorSel ? 2 : 1;
      c.beginPath();
      d.rows.forEach((x, k) => {
        const ex = this.sx(this.doorEdge(d.side, x) + t);
        c[k ? 'lineTo' : 'moveTo'](ex, this.sy(d.top + k));
        c.lineTo(ex, this.sy(d.top + k + 1));
      });
      c.stroke();
      // row handles (when there is room, or while editing the door)
      if (doorSel || this.scale >= 4)
        d.rows.forEach((x, k) => {
          const me: Selection = { kind: 'door', index: k };
          const on = sameSelection(sel, me) || sameSelection(hov, me);
          const r = on ? 4 : 2.5;
          c.fillStyle = sameSelection(sel, me) ? '#fff' : '#ffb27a';
          c.beginPath();
          c.arc(this.sx(this.doorEdge(d.side, x) + t), this.sy(d.top + k + 0.5), r, 0, Math.PI * 2);
          c.fill();
        });
      // tab
      const tab = this.doorTab(d, t);
      const me: Selection = { kind: 'door', index: -1 };
      c.fillStyle = sameSelection(sel, me) ? '#ffd34f' : sameSelection(hov, me) ? '#ffc79a' : '#dd8855';
      c.fillRect(tab.x, tab.y, tab.w, tab.h);
      c.fillStyle = '#000';
      c.font = '10px ui-monospace, monospace';
      c.textBaseline = 'middle';
      c.fillText('door', tab.x + 3, tab.y + tab.h / 2 + 1);
    }
  }

  /** World X of a door row's edge (the left wall is solid up to X). */
  private doorEdge(side: Side, x: number): number {
    return side === 'left' ? x : x + 1;
  }

  private doorTab(d: NonNullable<Level['door']>, t: number): { x: number; y: number; w: number; h: number } {
    const w = 32;
    const ex = this.sx(this.doorEdge(d.side, d.rows[0]) + t);
    return { x: d.side === 'left' ? ex - w : ex, y: this.sy(d.top) - 13, w, h: 12 };
  }

  private drawObjects(l: Level): void {
    const c = this.ctx;
    const sel = this.store.selection;
    const hov = this.store.hover;
    c.font = '11px ui-monospace, monospace';
    c.textBaseline = 'top';
    for (const t of this.tiles()) {
      l.objects.forEach((o, i) => {
        const x = this.sx(o.x + t);
        const y = this.sy(o.y);
        const me: Selection = { kind: 'object', index: i };
        const isSel = sameSelection(sel, me);
        if (isGun(o.type) && (this.showArcs || isSel)) this.drawArc(o.x + t, o.y, o.type, o.gun, isSel);
        // the game's sprites, top-left at the object's position
        const parts = objectParts(o.type, l.colours, this.gameColours);
        for (const p of parts)
          c.drawImage(spriteImage(p.frame, p.colour), x, y, SPRITE_UNITS * this.ux, SPRITE_ROWS * this.scale);
        const b = OBJ_BOUNDS[o.type];
        if (!parts.length || !b) {
          c.fillStyle = '#aaa'; // unknown type
          c.fillRect(x, y, 4 * this.ux, 8 * this.scale);
          return;
        }
        const bx = x + b.x0 * this.ux;
        const by = y + b.y0 * this.scale;
        if (isSel || sameSelection(hov, me)) {
          c.strokeStyle = isSel ? '#fff' : 'rgba(255,255,255,0.6)';
          c.lineWidth = isSel ? 2 : 1;
          c.strokeRect(bx - 2, by - 2, (b.x1 - b.x0) * this.ux + 4, (b.y1 - b.y0) * this.scale + 4);
        }
        if (this.ux >= 3) {
          c.fillStyle = '#fff';
          c.fillText(String(i), bx + 1, by - 14);
        }
      });
    }
  }

  /** Firing arc: the directions base .. base+mask+3 (32 steps, 0 = up). */
  private drawArc(x: number, y: number, type: number, param: number, strong: boolean): void {
    const c = this.ctx;
    const [mx, my] = GUN_MUZZLE[type];
    const cx = this.sx(x + mx);
    const cy = this.sy(y + my);
    const { from, to } = gunArc(param);
    const rad = (a: number) => (a / 32) * Math.PI * 2 - Math.PI / 2; // canvas: 0 = right
    const r = Math.max(40, 30 * this.ux);
    c.fillStyle = strong ? 'rgba(255,90,90,0.28)' : 'rgba(255,90,90,0.14)';
    c.beginPath();
    c.moveTo(cx, cy);
    c.arc(cx, cy, r, rad(from), rad(to));
    c.closePath();
    c.fill();
  }

  private drawRestarts(l: Level): void {
    const c = this.ctx;
    const sel = this.store.selection;
    const hov = this.store.hover;
    c.font = '11px ui-monospace, monospace';
    c.textBaseline = 'top';
    for (const t of this.tiles())
      l.restarts.forEach((r, i) => {
        const me: Selection = { kind: 'restart', index: i };
        const isSel = sameSelection(sel, me);
        const isHov = sameSelection(hov, me);
        const x = this.sx(r.shipX + t);
        const y = this.sy(r.shipY);
        if (this.showScreen || isSel) {
          c.strokeStyle = isSel ? 'rgba(255,255,255,0.8)' : i === 0 ? 'rgba(255,255,255,0.45)' : 'rgba(255,255,255,0.2)';
          c.setLineDash([6, 4]);
          c.strokeRect(this.sx(r.windowX + t), this.sy(r.windowY + SCREEN_TOP), SCREEN_COLS * this.ux, SCREEN_ROWS * this.scale);
          c.setLineDash([]);
        }
        const k = isSel || isHov ? 9 : 6;
        c.strokeStyle = isSel ? '#ffd34f' : '#fff';
        c.lineWidth = isSel ? 2.5 : 1.5;
        c.beginPath();
        c.moveTo(x - k, y);
        c.lineTo(x + k, y);
        c.moveTo(x, y - k);
        c.lineTo(x, y + k);
        c.stroke();
        c.fillStyle = isSel ? '#ffd34f' : '#fff';
        c.fillText(i === 0 ? 'start' : `R${i}`, x + 5, y + 3);
      });
  }

  private drawWall(w: Wall, side: Side): void {
    const c = this.ctx;
    const sel = this.store.selection;
    const hov = this.store.hover;
    const pts = w.points;
    const last = pts[pts.length - 1];
    for (const t of this.tiles()) {
      c.strokeStyle = WALL_COLOUR[side];
      c.lineWidth = 2;
      // pure slopes solid; uneven ones (staircases, several entries) dashed
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1];
        const p = pts[i];
        c.setLineDash(isPureSlope(a, p) ? [] : [6, 3]);
        c.beginPath();
        c.moveTo(this.sx(a.x + t), this.sy(a.row));
        c.lineTo(this.sx(p.x + t), this.sy(p.row));
        c.stroke();
      }
      // below the last point the wall is vertical
      c.setLineDash([3, 5]);
      c.beginPath();
      c.moveTo(this.sx(last.x + t), this.sy(last.row));
      c.lineTo(this.sx(last.x + t), this.h);
      c.stroke();
      c.setLineDash([]);
      pts.forEach((p, i) => {
        const x = this.sx(p.x + t);
        const y = this.sy(p.row);
        if (x < -HANDLE || x > this.w + HANDLE || y < -HANDLE || y > this.h + HANDLE) return;
        if (i === 0) {
          c.fillStyle = '#666';
          c.beginPath();
          c.arc(x, y, 3, 0, Math.PI * 2);
          c.fill();
          return;
        }
        const me: Selection = { kind: 'point', side, index: i };
        const isSel = sameSelection(sel, me);
        const isHov = sameSelection(hov, me);
        const s = isSel || isHov ? HANDLE + 1 : HANDLE;
        c.fillStyle = isSel ? '#fff' : WALL_COLOUR[side];
        c.strokeStyle = '#000';
        c.lineWidth = 1;
        c.fillRect(x - s, y - s, s * 2, s * 2);
        c.strokeRect(x - s + 0.5, y - s + 0.5, s * 2 - 1, s * 2 - 1);
      });
    }
  }

  private drawRulers(): void {
    const c = this.ctx;
    c.fillStyle = '#15151d';
    c.fillRect(0, 0, this.w, RULER_TOP);
    c.fillRect(0, 0, RULER_LEFT, this.h);
    c.fillStyle = '#9aa';
    c.strokeStyle = '#556';
    c.font = '11px ui-monospace, monospace';
    c.lineWidth = 1;
    const pick = (pxPerUnit: number, min: number) =>
      [1, 2, 4, 8, 16, 32, 64, 128, 256, 512].find((s) => s * pxPerUnit >= min) ?? 1024;

    // X
    const xs = pick(this.ux, 44);
    const x0 = this.camX;
    const x1 = this.camX + (this.w - RULER_LEFT) / this.ux;
    c.textBaseline = 'middle';
    c.beginPath();
    for (let x = Math.ceil(x0 / xs) * xs; x <= x1; x += xs) {
      const s = Math.round(this.sx(x)) + 0.5;
      c.moveTo(s, RULER_TOP - 6);
      c.lineTo(s, RULER_TOP);
      c.fillText(hex2(x), s + 3, RULER_TOP / 2 - 2);
    }
    c.stroke();

    // rows
    const rs = pick(this.scale, 28);
    const r0 = this.camY;
    const r1 = this.camY + (this.h - RULER_TOP) / this.scale;
    c.beginPath();
    for (let r = Math.max(0, Math.ceil(r0 / rs) * rs); r <= r1; r += rs) {
      const s = Math.round(this.sy(r)) + 0.5;
      c.moveTo(RULER_LEFT - 6, s);
      c.lineTo(RULER_LEFT, s);
      c.fillText(hex3(r), 4, s - 6);
      c.fillStyle = '#667';
      c.fillText(String(r), 4, s + 6);
      c.fillStyle = '#9aa';
    }
    c.stroke();

    // cursor
    if (this.cursor) {
      c.fillStyle = '#ffd34f';
      c.fillRect(Math.round(this.sx(Math.floor(this.cursor.x))), RULER_TOP - 4, Math.max(1, this.ux), 4);
      c.fillRect(RULER_LEFT - 4, Math.round(this.sy(Math.floor(this.cursor.row))), 4, Math.max(1, this.scale));
    }
    c.fillStyle = '#15151d';
    c.fillRect(0, 0, RULER_LEFT, RULER_TOP);
  }

  // ---- hit testing --------------------------------------------------------

  hitPoint(sx: number, sy: number): { side: Side; index: number; tile: number } | null {
    const l = this.store.current;
    if (!l) return null;
    let best: { side: Side; index: number; tile: number } | null = null;
    let bestD = HIT;
    for (const side of ['left', 'right'] as const)
      for (const t of this.tiles())
        l[side].points.forEach((p, i) => {
          if (i === 0) return;
          const d = Math.max(Math.abs(this.sx(p.x + t) - sx), Math.abs(this.sy(p.row) - sy));
          if (d <= bestD) {
            bestD = d;
            best = { side, index: i, tile: t };
          }
        });
    return best;
  }

  /** Door tab (index -1) or row handle under the mouse. */
  hitDoor(sx: number, sy: number): { index: number; tile: number } | null {
    const d = this.store.current?.door;
    if (!d) return null;
    const rowsShown = this.store.selection?.kind === 'door' || this.scale >= 4;
    for (const t of this.tiles()) {
      const tab = this.doorTab(d, t);
      if (sx >= tab.x && sx <= tab.x + tab.w && sy >= tab.y && sy <= tab.y + tab.h) return { index: -1, tile: t };
      if (!rowsShown) continue;
      const w = this.toWorld(sx, sy);
      const k = Math.floor(w.row) - d.top;
      if (k < 0 || k >= d.rows.length) continue;
      if (Math.abs(this.sx(this.doorEdge(d.side, d.rows[k]) + t) - sx) <= HIT) return { index: k, tile: t };
    }
    return null;
  }

  hitObject(sx: number, sy: number): { index: number; tile: number; grabX: number; grabY: number } | null {
    const l = this.store.current;
    if (!l || !this.showObjects) return null;
    const w = this.toWorld(sx, sy);
    for (const t of this.tiles())
      for (let i = l.objects.length - 1; i >= 0; i--) {
        const o = l.objects[i];
        const b = OBJ_BOUNDS[o.type] ?? { x0: 0, y0: 0, x1: 4, y1: 8 };
        const pad = 3 / this.ux; // a few pixels of slack for tiny zooms
        const gx = w.x - (o.x + t);
        const gy = w.row - o.y;
        if (gx >= b.x0 - pad && gx <= b.x1 + pad && gy >= b.y0 - pad * 2 && gy <= b.y1 + pad * 2)
          return { index: i, tile: t, grabX: gx, grabY: gy };
      }
    return null;
  }

  hitRestart(sx: number, sy: number): { index: number; tile: number } | null {
    const l = this.store.current;
    if (!l || !this.showObjects) return null;
    for (const t of this.tiles())
      for (let i = l.restarts.length - 1; i >= 0; i--) {
        const r = l.restarts[i];
        if (Math.abs(this.sx(r.shipX + t) - sx) <= HIT && Math.abs(this.sy(r.shipY) - sy) <= HIT) return { index: i, tile: t };
      }
    return null;
  }

  hitSegment(sx: number, sy: number): (SegmentHit & { tile: number }) | null {
    const l = this.store.current;
    if (!l) return null;
    const w = this.toWorld(sx, sy);
    const row = Math.round(w.row);
    for (const side of ['left', 'right'] as const) {
      const pts = l[side].points;
      // a new point goes exactly on the line, so the terrain does not jump
      const x = Math.round(wallXAt(l[side], row));
      for (const t of this.tiles()) {
        for (let k = 1; k <= pts.length; k++) {
          const a = pts[k - 1];
          const b = pts[k];
          if (!b) {
            // vertical tail below the last point
            if (row > a.row && Math.abs(this.sx(a.x + t) - sx) <= HIT) return { side, index: k, row, x, tile: t };
            continue;
          }
          if (distToSegment(sx, sy, this.sx(a.x + t), this.sy(a.row), this.sx(b.x + t), this.sy(b.row)) <= HIT)
            return { side, index: k, row, x, tile: t };
        }
      }
    }
    return null;
  }
}

function isPureSlope(a: { row: number; x: number }, b: { row: number; x: number }): boolean {
  const dy = b.row - a.row;
  return dy === 1 || (b.x - a.x) % dy === 0;
}

function distToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax;
  const dy = by - ay;
  const len = dx * dx + dy * dy;
  const t = len ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len)) : 0;
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
