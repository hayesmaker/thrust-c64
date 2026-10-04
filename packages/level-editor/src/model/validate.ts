// Level checks (rules from docs/level_format.md) and the memory budget.

import { type Level, OBJ_NAMES, ObjType, decodeLevel, levelRows, wallTables } from './level';
import { isSolid, snapObject } from './objects';

export type Severity = 'error' | 'warn' | 'info';

export type Target =
  | { kind: 'object'; index: number }
  | { kind: 'restart'; index: number }
  | { kind: 'wall'; side: 'left' | 'right' };

export interface Issue {
  level: number;
  severity: Severity;
  message: string;
  target?: Target;
}

export const MAX_OBJECTS = 32;
export const FUEL_SLOTS = 12;
export const MAX_ENTRIES = 255;

/** Doors are code (tick_door_logic), not data: top row and rows per level. */
export const DOORS: Record<number, { top: number; xs: number[] }> = {
  3: { top: 0x269, xs: new Array(13).fill(0xae) },
  4: { top: 0x344, xs: new Array(21).fill(0xa6) },
  5: {
    top: 0x370,
    xs: [...Array.from({ length: 7 }, (_, k) => 0xc0 + k), ...Array.from({ length: 8 }, (_, k) => 0xc7 - k)],
  },
};

export function validateLevel(l: Level): Issue[] {
  const out: Issue[] = [];
  const add = (severity: Severity, message: string, target?: Target) =>
    out.push({ level: l.index, severity, message, target });
  const { left, right } = decodeLevel(l, levelRows(l, 64));
  const o = l.objects;

  // objects
  if (o.length > MAX_OBJECTS) add('error', `${o.length} objects: the limit is ${MAX_OBJECTS}`);
  if (o[0]?.type !== ObjType.PodStand) add('error', 'object 0 must be the pod stand', o.length ? { kind: 'object', index: 0 } : undefined);
  const pods = o.filter((v) => v.type === ObjType.PodStand).length;
  if (pods > 1) add('warn', `${pods} pod stands: only object 0 is used for the pod`);
  if (!o.some((v) => v.type === ObjType.Generator)) add('warn', 'no generator (reactor)');
  o.forEach((v, i) => {
    const t: Target = { kind: 'object', index: i };
    if (v.type > 8) return add('error', `object ${i}: unknown type ${v.type}`, t);
    if (v.type === ObjType.Fuel && i >= FUEL_SLOTS)
      add('error', `object ${i} (fuel) must be among the first ${FUEL_SLOTS} objects`, t);
    if (v.y < 0 || v.y > 0xffff) add('error', `object ${i}: Y out of range`, t);
    const s = snapObject(v, left, right);
    if (!s) add('warn', `object ${i} (${OBJ_NAMES[v.type]}) has no terrain to rest on`, t);
    else if (s.x !== v.x || s.y !== v.y)
      add('info', `object ${i} (${OBJ_NAMES[v.type]}) is not resting on the terrain`, t);
  });

  // restart points
  const r = l.restarts;
  if (r.length === 0) add('error', 'at least one restart point (the start) is needed');
  r.forEach((p, i) => {
    const t: Target = { kind: 'restart', index: i };
    if (i > 0 && p.shipY < r[i - 1].shipY)
      add('warn', `restart ${i} is above restart ${i - 1}: they should go down in order`, t);
    if (isSolid(left, right, p.shipX, p.shipY)) add('warn', `restart ${i}: ship starts inside rock`, t);
  });

  // terrain
  for (const side of ['left', 'right'] as const) {
    const n = wallTables(l[side]).counts.length;
    if (n > MAX_ENTRIES) add('error', `${side} wall: ${n} table entries (max ${MAX_ENTRIES})`, { kind: 'wall', side });
  }
  const last = left.length - 1;
  if (left[last] < right[last]) add('warn', 'the cave is open at the bottom (the walls never meet)');

  if (DOORS[l.index])
    add('info', `level ${l.index} has a hard-coded door at row $${DOORS[l.index].top.toString(16)} (orange): keep the left wall there`);
  if (o.some((v) => v.gun & 0xe0)) add('info', 'some gun parameters use bits 5-7 (ignored by the game)');
  return out;
}

// ---- memory -------------------------------------------------------------------

/** Level data in the main block in the original game: terrain 434 +
 *  objects 356 + restart tables 102 bytes; 348 bytes are free at $BEA4-$BFFF. */
export const ORIGINAL_LEVEL_BYTES = 892;
export const FREE_MAIN_BYTES = 348;
export const LEVEL_BUDGET = ORIGINAL_LEVEL_BYTES + FREE_MAIN_BYTES;

export function levelBytes(l: Level): { terrain: number; objects: number; restarts: number; total: number } {
  const terrain = 2 * (wallTables(l.left).counts.length + wallTables(l.right).counts.length);
  const objects = 5 * l.objects.length + 1;
  const restarts = 6 * l.restarts.length;
  return { terrain, objects, restarts, total: terrain + objects + restarts };
}
