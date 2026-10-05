// Editing operations with the format's constraints. Walls: points[0] is the
// fixed anchor, rows strictly increase, X and rows are whole.

import { type Door, MAX_DOOR_ROWS, newDoor } from '../model/door';
import { type Level, type LevelObject, ObjType, type RestartPoint, type Wall, touchWall } from '../model/level';
import { isGun, snapObject } from '../model/objects';
import { ANCHOR_ROW } from '../model/terrain';

/** Snap X so the segment from the previous point is a pure slope
 *  (whole step per row: 0 = vertical, ±1 = standard slope, ...). */
export function lockSlope(prev: { row: number; x: number }, row: number, x: number): number {
  const dy = row - prev.row;
  if (dy <= 0) return x;
  return prev.x + Math.round((x - prev.x) / dy) * dy;
}

/** Move point i; the row is clamped between its neighbours. Returns false if
 *  nothing changed. */
export function movePoint(w: Wall, i: number, row: number, x: number, slopeLock = false): boolean {
  if (i <= 0 || i >= w.points.length) return false;
  const prev = w.points[i - 1];
  const next = w.points[i + 1];
  row = Math.round(row);
  x = Math.round(x);
  row = Math.max(prev.row + 1, next ? Math.min(next.row - 1, row) : row);
  if (slopeLock) x = lockSlope(prev, row, x);
  const p = w.points[i];
  if (p.row === row && p.x === x) return false;
  w.points[i] = { row, x };
  touchWall(w);
  return true;
}

/** Insert a point at index i (between points i-1 and i, or at the end).
 *  Returns false if there is no free row there. */
export function insertPoint(w: Wall, i: number, row: number, x: number): boolean {
  if (i <= 0 || i > w.points.length) return false;
  row = Math.round(row);
  const prev = w.points[i - 1];
  const next = w.points[i];
  if (row <= prev.row || (next && row >= next.row)) return false;
  w.points.splice(i, 0, { row, x: Math.round(x) });
  touchWall(w);
  return true;
}

export function deletePoint(w: Wall, i: number): boolean {
  if (i <= 0 || i >= w.points.length) return false;
  w.points.splice(i, 1);
  touchWall(w);
  return true;
}

/** X of the drawn (straight) wall line at a row, unwrapped. Below the last
 *  point the wall is vertical. */
export function wallXAt(w: Wall, row: number): number {
  const p = w.points;
  if (row <= ANCHOR_ROW) return p[0].x;
  for (let k = 1; k < p.length; k++)
    if (row <= p[k].row) return p[k - 1].x + ((p[k].x - p[k - 1].x) * (row - p[k - 1].row)) / (p[k].row - p[k - 1].row);
  return p[p.length - 1].x;
}

// ---- objects ----------------------------------------------------------------

/** Window offset for a new restart point: window = ship - (X $16, Y $64). */
export const WINDOW_DX = 0x16;
export const WINDOW_DY = 0x64;

const sameObj = (a: LevelObject, b: { x: number; y: number }) => a.x === b.x && a.y === b.y;

/** Move object i (X wraps). With `snap`, it rests on the terrain per its type. */
export function moveObject(
  l: Level,
  i: number,
  x: number,
  y: number,
  snap: boolean,
  decoded: { left: number[]; right: number[] },
): boolean {
  const o = l.objects[i];
  if (!o) return false;
  let next = { ...o, x: Math.round(x) & 0xff, y: Math.max(0, Math.round(y)) };
  if (snap) {
    const s = snapObject(next, decoded.left, decoded.right);
    if (s) next = { ...next, ...s };
  }
  if (sameObj(o, next)) return false;
  l.objects[i] = next;
  return true;
}

/** Most common gun parameter per gun type in the original levels. */
const DEFAULT_GUN = [0x1e, 0x06, 0x1a, 0x12];

export function addObject(
  l: Level,
  type: number,
  x: number,
  y: number,
  decoded: { left: number[]; right: number[] },
): number {
  const o: LevelObject = { type, x: Math.round(x) & 0xff, y: Math.max(0, Math.round(y)), gun: isGun(type) ? DEFAULT_GUN[type] : 0 };
  const s = snapObject(o, decoded.left, decoded.right);
  if (s) Object.assign(o, s);
  // pod stand goes first, fuel before other objects (rules in level_format.md)
  let at = l.objects.length;
  if (type === ObjType.PodStand) at = 0;
  else if (type === ObjType.Fuel) {
    const firstOther = l.objects.findIndex((v, k) => k > 0 && v.type !== ObjType.Generator && v.type !== ObjType.Fuel);
    if (firstOther >= 0) at = firstOther;
  }
  l.objects.splice(at, 0, o);
  return at;
}

export function deleteObject(l: Level, i: number): boolean {
  if (!l.objects[i]) return false;
  l.objects.splice(i, 1);
  return true;
}

/** Move object i up/down in the list; returns its new index. */
export function reorderObject(l: Level, i: number, dir: -1 | 1): number {
  const j = i + dir;
  if (j < 0 || j >= l.objects.length) return i;
  [l.objects[i], l.objects[j]] = [l.objects[j], l.objects[i]];
  return j;
}

/** Stable sort: pod stand, generator, fuel, then the rest. */
export function sortObjects(l: Level): void {
  const rank = (t: number) => (t === ObjType.PodStand ? 0 : t === ObjType.Generator ? 1 : t === ObjType.Fuel ? 2 : 3);
  l.objects = l.objects.map((o, k) => ({ o, k })).sort((a, b) => rank(a.o.type) - rank(b.o.type) || a.k - b.k).map((e) => e.o);
}

// ---- restart points ---------------------------------------------------------------

/** Move restart i's ship; the window moves with it. */
export function moveRestart(l: Level, i: number, x: number, y: number): boolean {
  const r = l.restarts[i];
  if (!r) return false;
  const nx = Math.round(x) & 0xff;
  const ny = Math.max(0, Math.round(y));
  if (nx === r.shipX && ny === r.shipY) return false;
  l.restarts[i] = {
    shipX: nx,
    shipY: ny,
    windowX: (r.windowX + nx - r.shipX) & 0xff,
    windowY: Math.max(0, r.windowY + ny - r.shipY),
  };
  return true;
}

export function centreWindow(r: RestartPoint): RestartPoint {
  return { ...r, windowX: (r.shipX - WINDOW_DX) & 0xff, windowY: Math.max(0, r.shipY - WINDOW_DY) };
}

/** Add a restart point, keeping them in order of depth; returns its index. */
export function addRestart(l: Level, x: number, y: number): number {
  const r = centreWindow({ shipX: Math.round(x) & 0xff, shipY: Math.max(0, Math.round(y)), windowX: 0, windowY: 0 });
  let at = l.restarts.findIndex((v, k) => k > 0 && v.shipY > r.shipY);
  if (at < 0) at = l.restarts.length;
  at = Math.max(1, at);
  l.restarts.splice(at, 0, r);
  return at;
}

export function deleteRestart(l: Level, i: number): boolean {
  if (i <= 0 || !l.restarts[i]) return false; // keep the start position
  l.restarts.splice(i, 1);
  return true;
}

// ---- doors ---------------------------------------------------------------------

/** A door at `top` on a wall: `rows` rows, closed `depth` X units out from the
 *  terrain (`decoded` wall X per row). */
export function createDoor(l: Level, side: Door['side'], top: number, rows: number, depth: number, decoded: { left: number[]; right: number[] }): void {
  top = Math.max(0, Math.round(top));
  const wall = decoded[side];
  const xs = Array.from({ length: Math.max(1, Math.min(MAX_DOOR_ROWS, rows)) }, (_, k) => {
    const w = wall[Math.min(top + k, wall.length - 1)] ?? 0x80;
    return clampByte(side === 'left' ? w + depth : w - depth);
  });
  l.door = { ...newDoor(side, top, xs), max: depth };
}

/** Move door row i to wall X `x`. */
export function moveDoorRow(l: Level, i: number, x: number): boolean {
  const d = l.door;
  if (!d || i < 0 || i >= d.rows.length) return false;
  x = clampByte(x);
  if (d.rows[i] === x) return false;
  d.rows[i] = x;
  return true;
}

/** Move the whole door: top row to `top`, every row `dx` X units. */
export function moveDoor(l: Level, top: number, dx: number): boolean {
  const d = l.door;
  if (!d) return false;
  top = Math.max(0, Math.min(0xffff, Math.round(top)));
  dx = Math.round(dx);
  if (top === d.top && dx === 0) return false;
  d.top = top;
  if (dx) d.rows = d.rows.map((x) => clampByte(x + dx));
  return true;
}

export function deleteDoor(l: Level): boolean {
  if (!l.door) return false;
  l.door = null;
  return true;
}

/** Remove door row i (the last row cannot be removed: delete the door). */
export function deleteDoorRow(l: Level, i: number): boolean {
  const d = l.door;
  if (!d || d.rows.length <= 1 || i < 0 || i >= d.rows.length) return false;
  d.rows.splice(i, 1);
  if (d.mode === 'reveal') d.max = Math.min(d.max, d.rows.length);
  return true;
}

/** Add a row below the door (a copy of the last row). */
export function addDoorRow(l: Level): boolean {
  const d = l.door;
  if (!d || d.rows.length >= MAX_DOOR_ROWS) return false;
  d.rows.push(d.rows[d.rows.length - 1]);
  return true;
}

/** Set every row's closed X to the terrain wall plus `depth` (re-trace). */
export function traceDoor(l: Level, depth: number, decoded: { left: number[]; right: number[] }): boolean {
  const d = l.door;
  if (!d) return false;
  const wall = decoded[d.side];
  const before = d.rows.join();
  d.rows = d.rows.map((_, k) => {
    const w = wall[Math.min(d.top + k, wall.length - 1)] ?? 0x80;
    return clampByte(d.side === 'left' ? w + depth : w - depth);
  });
  return d.rows.join() !== before;
}

/** Close the passage: every row's closed edge meets the opposite wall, and a
 *  slide door opens far enough to clear it (back to its own wall). */
export function fillDoor(l: Level, decoded: { left: number[]; right: number[] }): boolean {
  const d = l.door;
  if (!d) return false;
  const at = (a: number[], row: number) => a[Math.min(row, a.length - 1)] ?? 0x80;
  const other = d.side === 'left' ? decoded.right : decoded.left;
  const own = decoded[d.side];
  const before = JSON.stringify(d);
  // left door: rock is X < door X, the cave ends at the right wall X (open up to
  // and including it); right door: rock is X > door X, the cave starts at left wall X
  d.rows = d.rows.map((_, k) => clampByte(d.side === 'left' ? at(other, d.top + k) + 1 : at(other, d.top + k) - 1));
  if (d.mode === 'slide')
    d.max = clampByte(Math.max(...d.rows.map((x, k) => Math.abs(x - at(own, d.top + k)))));
  return JSON.stringify(d) !== before;
}

const clampByte = (v: number) => Math.max(0, Math.min(0xff, Math.round(v)));
