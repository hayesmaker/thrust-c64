// Editing operations with the format's constraints. Walls: points[0] is the
// fixed anchor, rows strictly increase, X and rows are whole.

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
